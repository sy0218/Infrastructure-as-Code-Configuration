# 🔨 BuildKit 설치 (buildkitd) — docker 없는 이미지 빌드/push

- K8s 노드에 docker 를 깔지 않는다는 방침의 연장선 — data_pipeline 의 `build_and_push.sh` 가 docker 없으면 **buildctl 을 자동 선택**(BUILDER 감지)하고, 그 buildctl 이 이 롤이 설치하는 buildkitd 데몬으로 **빌드+push 를 한 단계**로 처리한다.
- runc 는 **없으면 설치, 있으면 그대로**(state=present) — K8s 노드에서는 containerd 롤이 hold 한 짝 버전을 건드리지 않는다.
- 바이너리는 GitHub 릴리스 tarball 을 **버전별 디렉토리**에 풀고 `/usr/local/bin` 심볼릭 링크만 교체한다 — 버전 변경·롤백이 링크 교체 한 번이다.
- 버전 핀/설치 경로/Harbor 인증은 `group_vars/buildkitd.yml` 변수로 관리 (롤은 범용, 인벤토리가 동작 결정)
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# BuildKit 설치 → buildkitd(systemd) + buildctl
# -----------------------------------------------------

# =========================================================================
# 1. runc 설치 (state=present 자체가 멱등 — 없으면 설치, 있으면 그대로)
#    → buildkitd OCI 워커의 실행기다. 없으면 데몬은 떠도 첫 빌드가 죽는다.
#    ⚠ 버전을 지정하지 않는 이유: K8s 노드에는 containerd 롤이 containerd·runc 를
#      짝 버전으로 설치·hold 해 뒀다(짝이 어긋나면 Ubuntu 버그 #2065423).
#      present 는 이미 설치된(hold 포함) 패키지를 건드리지 않아 그 계약과 충돌하지
#      않고, runc 가 정말 없는 호스트에서만 배포판 runc 가 새로 깔린다.
# =========================================================================
- name: "Install runc if missing"
  apt:
    name: runc
    state: present
  register: buildkit_runc
  retries: 3 # apt 저장소 불안정 대비
  delay: 10
  until: buildkit_runc is succeeded

# =========================================================================
# 2. 버전별 설치 디렉토리 (file 모듈 자체가 멱등)
# =========================================================================
- name: "Create buildkit install directory"
  file:
    path: "{{ buildkit_install_root }}/v{{ buildkit_version }}"
    state: directory
    owner: root
    group: root
    mode: '0755'

# =========================================================================
# 3. 릴리스 tarball 다운로드 (파일명에 버전 포함 → 버전 변경 시에만 새로 받음)
# =========================================================================
- name: "Download buildkit release tarball"
  get_url:
    url: "https://github.com/moby/buildkit/releases/download/v{{ buildkit_version }}/buildkit-v{{ buildkit_version }}.linux-amd64.tar.gz"
    dest: "{{ buildkit_install_root }}/buildkit-v{{ buildkit_version }}.linux-amd64.tar.gz"
    owner: root
    group: root
    mode: '0644'
  register: buildkit_tgz
  retries: 3 # 외부망 다운로드 불안정 대비
  delay: 10
  until: buildkit_tgz is succeeded

# =========================================================================
# 4. 압축 해제 (creates 가드로 멱등) → v<버전>/bin/{buildkitd,buildctl}
# =========================================================================
- name: "Extract buildkit binaries"
  unarchive:
    src: "{{ buildkit_install_root }}/buildkit-v{{ buildkit_version }}.linux-amd64.tar.gz"
    dest: "{{ buildkit_install_root }}/v{{ buildkit_version }}"
    remote_src: true
    creates: "{{ buildkit_install_root }}/v{{ buildkit_version }}/bin/buildkitd"

# =========================================================================
# 5. 심볼릭 링크 (버전 변경 시 링크만 교체되어 롤백이 쉽다)
# =========================================================================
- name: "Link buildkit binaries into PATH"
  file:
    src: "{{ buildkit_install_root }}/v{{ buildkit_version }}/bin/{{ item }}"
    path: "/usr/local/bin/{{ item }}"
    state: link
    force: true # 수동 설치(실파일)가 있던 자리도 링크로 수렴시킨다
  loop:
    - buildkitd
    - buildctl
  notify: restart buildkitd

# =========================================================================
# 6. systemd 유닛 (copy 자체가 멱등)
#    → 소켓은 기본값(/run/buildkit/buildkitd.sock, root 전용)을 그대로 쓴다.
# =========================================================================
- name: "Create buildkitd systemd unit"
  copy:
    dest: /etc/systemd/system/buildkitd.service
    owner: root
    group: root
    mode: '0644'
    content: |
      [Unit]
      Description=BuildKit daemon v{{ buildkit_version }}
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      ExecStart=/usr/local/bin/buildkitd
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
  notify: restart buildkitd

# =========================================================================
# 7. Harbor push 인증 파일 (copy 자체가 멱등)
#    → buildctl 은 docker CLI 없이 이 파일의 auths 만 읽는다(root 로 실행하므로 /root).
#    ⚠ 비밀번호는 200-harbor secrets.auto.tfvars 의 harbor_admin_password 와 같아야 한다.
# =========================================================================
- name: "Create docker config directory"
  file:
    path: /root/.docker
    state: directory
    owner: root
    group: root
    mode: '0700'

- name: "Create registry auth for buildctl"
  copy:
    dest: /root/.docker/config.json
    owner: root
    group: root
    mode: '0600' # 자격증명 — root 만 읽는다
    content: "{{ {'auths': {buildkit_registry: {'auth': (buildkit_registry_user ~ ':' ~ buildkit_registry_password) | b64encode}}} | to_nice_json }}\n"

# =========================================================================
# 8. 서비스 기동 + 부팅 자동시작 (systemd 모듈 자체가 멱등)
# =========================================================================
- name: "Enable and start buildkitd"
  systemd:
    name: buildkitd
    enabled: true
    state: started
    daemon_reload: true

# =========================================================================
# 9. 유닛/바이너리 변경분을 검증 전에 반영한다
# =========================================================================
- name: "Flush handlers before verification"
  meta: flush_handlers

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
- name: "Check buildkitd service status"
  command: systemctl is-active buildkitd
  register: buildkitd_status
  changed_when: false
  failed_when: false
  retries: 3
  delay: 5
  until: buildkitd_status.stdout == "active"

- name: "Check installed buildctl version"
  command: /usr/local/bin/buildctl --version
  register: buildctl_version_check
  changed_when: false

# 소켓으로 데몬에 실제 접속해 본다 — active 인데 소켓이 안 열리는 경우를 잡는다
- name: "Check buildkitd responds on its socket"
  command: /usr/local/bin/buildctl debug info
  register: buildctl_debug
  changed_when: false
  failed_when: false

- name: "Assert buildkit is ready for image builds"
  assert:
    that:
      - buildkitd_status.stdout == "active"
      - buildkit_version in buildctl_version_check.stdout # 고정 버전 일치 (조건문 안에서는 {{ }} 금지)
      - buildctl_debug.rc == 0
    success_msg: "Good!.. | buildkitd active — buildctl v{{ buildkit_version }} ready (socket OK)"
    fail_msg: "ERROR!.. | buildkitd NOT ready → 노드에서 journalctl -u buildkitd -n 50 확인"
```
---
<br>

## 📌 group_vars 예시
```yaml
#########################################
# BuildKit 설치 버전 고정 (buildkitd 사용)
# → docker 없이 이미지를 빌드/push 하기 위한 데몬
# → runc 는 없으면 설치, 있으면 그대로 둔다 (state=present — K8s 노드에서는
#   containerd 롤이 hold 한 짝 버전을 건드리지 않는다.)
#########################################
buildkit_version: "0.32.2"

# 설치 경로 → 버전별 디렉토리 + /usr/local/bin 심볼릭 링크(버전 변경 시 링크만 교체)
buildkit_install_root: /application/buildkit

#########################################
# Harbor push 인증 (buildkitd 사용)
#
# [주의] 비밀번호는 Terraform 200-harbor secrets.auto.tfvars 의
# harbor_admin_password 와 글자 그대로 같아야 한다.
#########################################
buildkit_registry: "data-layer-harbor"
buildkit_registry_user: "admin"
buildkit_registry_password: "Harbor12345"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ runc 설치
- buildkitd OCI 워커가 컨테이너 실행에 runc 를 쓴다 — 없으면 데몬은 정상 기동하는데 **첫 빌드가 알 수 없는 에러로 죽는다**(늦게 발견되는 고장이라 롤 첫 태스크로 둔다).
- `state: present` 라 이미 설치돼 있으면 아무것도 하지 않는다. **버전을 지정하지 않는 것이 의도다** — K8s 노드의 runc 는 containerd 롤이 containerd 와 짝 버전으로 hold 해 뒀고(짝이 어긋나면 Ubuntu 버그 #2065423), present 는 hold 를 건드리지 않는다.
---
### 2️⃣ 버전별 설치 디렉토리
- `/application/buildkit/v<버전>/` — 버전마다 딴 디렉토리라 업그레이드가 기존 설치를 덮지 않는다.
---
### 3️⃣ tarball 다운로드
- 대상 파일명에 버전이 박혀 있어(get_url 자체 멱등) **버전 핀을 올릴 때만** 새로 받는다. `latest` 경로를 쓰지 않는 저장소 규칙(재실행마다 다른 바이너리 = 멱등성 붕괴)과 같은 이유.
---
### 4️⃣ 압축 해제
- `creates=` 가드 — 풀린 buildkitd 가 이미 있으면 건너뛴다(unarchive 는 가드 없이는 매번 changed 가 뜬다).
---
### 5️⃣ 심볼릭 링크
- `/usr/local/bin/{buildkitd,buildctl}` → 버전 디렉토리. **버전 변경 = 링크 교체 한 번**이라 롤백이 쉽다. `force: true` 는 수동 설치(실파일)가 있던 자리도 링크로 수렴시키기 위함.
---
### 6️⃣ systemd 유닛
- 소켓은 기본값(`/run/buildkit/buildkitd.sock`, root 전용)을 그대로 쓴다 — buildctl 도 root 로 실행하므로 권한 설정이 따로 필요 없다.
---
### 7️⃣ Harbor push 인증 파일
- buildctl 은 docker CLI 없이 `/root/.docker/config.json` 의 `auths` 만 읽는다(인증 제공자는 데몬이 아니라 **클라이언트 쪽**이다). HTTP(비 TLS) 처리는 이 파일 소관이 아니라 `build_and_push.sh` 가 push 시 `registry.insecure=true` 로 넘긴다.
- ⚠ 비밀번호는 **200-harbor `secrets.auto.tfvars` 의 `harbor_admin_password`** 와 글자 그대로 같아야 한다.
---
### 8️⃣ 서비스 기동
- systemd 모듈 자체가 멱등 — 이미 active 면 아무 일도 없다.
---
### 9️⃣ 핸들러 flush
- 유닛/바이너리 변경분을 검증 **전에** 재시작으로 반영한다 — flush 없이는 검증이 옛 프로세스를 상대로 통과해 버린다.
---
<br>

## 🧩 handlers/main.yml
```yaml
# -----------------------------------------------------
# buildkitd 재시작 핸들러 → systemd 유닛 / 바이너리 링크 변경 시에만 실행
# -----------------------------------------------------
- name: restart buildkitd
  systemd:
    name: buildkitd
    state: restarted
    daemon_reload: true # 유닛 파일 변경분 반영
```
- 유닛 파일·바이너리 링크가 실제로 바뀐 실행에서만 재시작한다 — 재실행마다 데몬이 내려가는 것을 막는다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [buildkitd : Assert buildkit is ready for image builds] ******************
ok: [s2] => {
    "msg": "Good!.. | buildkitd active — buildctl v0.32.2 ready (socket OK)"
}
```
