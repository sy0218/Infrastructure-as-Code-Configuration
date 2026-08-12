# 📦 containerd 설치 및 설정 (Ansible)
- K8s 컨테이너 런타임인 containerd와 **그 짝인 runc**를
**인벤토리 `containerd_version` · `runc_version`으로 버전 고정** 설치하고
`SystemdCgroup = true`를 적용한다.
- ⚠ **둘은 한 apt 트랜잭션에서 함께 설치하고 함께 hold한다.**
containerd의 의존은 버전 없는 `Depends: runc`뿐이라, 따로 두면 runc만 혼자 올라가 짝이 깨진다.
짝이 어긋나면 containerd가 커널에 올리는 AppArmor 프로파일이 runc의 종료 신호를 막아
**파드가 `Terminating`에서 사라지지 않는다** (Ubuntu 버그 [#2065423](https://bugs.launchpad.net/ubuntu/+source/containerd-app/+bug/2065423)).
- ⚠ **버전 변경 후에는 노드 재부팅이 필요하다.** AppArmor 프로파일이 파일이 아니라
containerd 바이너리에 내장돼 실행 시 커널에 로드되므로, 패키지만 갈아도 옛 규칙이 커널에 남는다.
- cgroup v2 환경에서 kubelet(systemd 드라이버)과 cgroup 관리 주체를 일치시키기 위함
— 불일치 시 파드 재시작 반복 등 불안정 발생.
- **인벤토리 `containerd_insecure_registries`** 목록의 HTTP 사설 레지스트리(Harbor 등)에
`certs.d/hosts.toml`로 HTTP 접속을 허용한다.
- 설치 후 hold로 고정하며, 설정(config.toml/hosts.toml)이 실제로 변경된 경우에만 containerd를 재시작한다.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# containerd 설치 및 설정 (K8s 컨테이너 런타임)
# -----------------------------------------------------
# SystemdCgroup = true 필수 — cgroup v2 환경에서 kubelet(systemd 드라이버)과
# cgroup 관리 주체를 일치시킴 (불일치 시 파드 재시작 반복 등 불안정)
# -----------------------------------------------------

# 1. containerd + runc 설치 — 인벤토리 버전으로 둘 다 고정
#    (버전 변경 시 hold 상태여도 해당 버전으로 수렴)
#
#    ⚠ 반드시 한 apt 트랜잭션에서 함께 설치한다.
#      containerd 의 의존은 버전 없는 `Depends: runc` 뿐이라, 따로 설치하면 apt 가
#      먼저 최신 runc 를 끌어온 뒤 다운그레이드하는 모양이 된다.
#    ⚠ 둘의 버전은 짝이 맞아야 한다. 어긋나면 containerd 가 커널에 올리는 AppArmor
#      프로파일이 runc 의 종료 신호를 막아 파드가 Terminating 에서 안 사라진다
#      (Ubuntu 버그 #2065423 — containerd 1.7.12 + runc 1.3.x 조합에서 실제 발생).
- name: "Install containerd and runc"
  apt:
    name:
      - "containerd={{ containerd_version }}"
      - "runc={{ runc_version }}"
    state: present # 없으면 설치
    update_cache: yes # apt update 먼저 실행
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략 (매 실행 시간 절약)
    allow_change_held_packages: true # hold 상태에서도 버전 변경 허용
    allow_downgrade: true # 하위 버전으로 고정 시 다운그레이드 허용

# 2. 버전 고정 — 의도치 않은 업그레이드 방지
#    (dpkg_selections 자체가 멱등 — command apt-mark hold는 매번 changed)
#    runc 도 함께 건다 — 안 걸면 noble-updates 를 타고 혼자 올라가 짝이 깨진다.
- name: "Hold containerd and runc packages"
  dpkg_selections:
    name: "{{ item }}"
    selection: hold
  loop:
    - containerd
    - runc

# 3. 설정 디렉토리 생성 (file 모듈 자체가 멱등)
- name: "Create containerd config directory"
  file:
    path: /etc/containerd
    state: directory
    owner: root
    group: root
    mode: "0755"

# 4. 기본 설정 생성 (조회 전용 → 상태 변경 없음)
- name: "Get containerd default config"
  command: containerd config default
  register: containerd_default
  changed_when: false

# 5. SystemdCgroup 활성화 + certs.d 경로 지정해서 설정 파일 배포
#    - 1.x: config_path 기본값이 빈 문자열(쌍따옴표) → 채워 넣어야 certs.d의 hosts.toml을 읽는다
#    - 2.x(version=3): 기본값이 콜론 목록('/etc/containerd/certs.d:/etc/docker/certs.d')인데,
#      기본 pull 경로(use_local_image_pull=false → transfer 플러그인)가 이 목록을 분리하지
#      않고 통째로 한 디렉토리 경로로 취급한다 → certs.d를 못 찾아 HTTPS로 붙고
#      "server gave HTTP response to HTTPS client"로 pull이 죽는다(2026-08-12 실측 —
#      단일 경로로 바꾸면 즉시 정상). 네 번째 replace가 콜론 목록을 단일 경로로 줄인다.
#      transfer 플러그인 자체의 config_path(빈 값, 홑따옴표)도 세 번째 replace로 채운다
#      (CRI 를 거치지 않는 transfer API 직접 사용 경로 대비 — 결정적이었던 쪽은 콜론 제거다).
#    (파이프+sed는 비멱등이라 금지 — copy는 내용이 같으면 changed=0 보장)
- name: "Apply containerd config"
  copy:
    content: "{{ containerd_default.stdout | replace('SystemdCgroup = false', 'SystemdCgroup = true') | replace('config_path = \"\"', 'config_path = \"/etc/containerd/certs.d\"') | replace(\"config_path = ''\", \"config_path = '/etc/containerd/certs.d'\") | replace(\"config_path = '/etc/containerd/certs.d:/etc/docker/certs.d'\", \"config_path = '/etc/containerd/certs.d'\") }}\n"
    dest: /etc/containerd/config.toml
    owner: root
    group: root
    mode: "0644"
  register: containerd_config

# 6. 서비스 기동 + 부팅 자동시작 (systemd 모듈 자체가 멱등)
- name: "Enable and start containerd"
  systemd:
    name: containerd
    enabled: true
    state: started

# 7. 레지스트리별 접속 규칙 디렉토리 — 디렉토리 이름이 곧 레지스트리 주소(host:port)
- name: "Create certs.d registry directories"
  file:
    path: "/etc/containerd/certs.d/{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop: "{{ containerd_insecure_registries }}"

# 8. hosts.toml 배포 — 스킴을 http로 선언해 HTTPS 시도 자체를 차단
#    (TLS 없는 사설 레지스트리 pull 시 "server gave HTTP response to HTTPS client" 방지)
- name: "Apply insecure registry hosts.toml"
  copy:
    content: |
      server = "http://{{ item }}"

      [host."http://{{ item }}"]
        capabilities = ["pull", "resolve"]
    dest: "/etc/containerd/certs.d/{{ item }}/hosts.toml"
    owner: root
    group: root
    mode: "0644"
  loop: "{{ containerd_insecure_registries }}"
  register: registry_hosts

# 9. 설정이 변경된 경우만 재시작 (매 실행 재시작 방지 — config.toml/hosts.toml 반영에는 재시작 필수)
#    ⚠ 재시작은 이 노드의 모든 컨테이너를 흔든다. s1 은 docker(CDC 소스 DB)가 containerd 를
#      공유하므로 그 컨테이너도 함께 죽는다 → 플레이는 serial: 1 로 한 대씩 돈다.
- name: "Restart containerd on config change"
  systemd:
    name: containerd
    state: restarted
  when: containerd_config.changed or registry_hosts.changed

# 10. 파드 샌드박스 이미지 사전 확보 — 재시작 직후 새로 뜨는 모든 파드가 이 이미지를 쓴다.
#     containerd 2.x 는 기본값이 pause:3.10.1 로 kubeadm 1.34 와 같지만, 노드 캐시에는
#     옛 pause:3.8 만 있을 수 있다. 미리 받아두지 않으면 재시작 직후 샌드박스 생성이 느려진다.
- name: "Pre-pull pod sandbox (pause) image"
  command: ctr -n k8s.io images pull {{ sandbox_image }}
  register: sandbox_pull
  changed_when: false
  failed_when: false

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
- name: "Check containerd status"
  command: systemctl is-active containerd
  register: containerd_status
  failed_when: false
  changed_when: false

# 설치된 버전 확인
- name: "Check installed containerd version"
  command: dpkg-query -W --showformat=${Version} containerd
  register: containerd_pkg_version
  failed_when: false # 미설치여도 아래 assert 가 정돈된 메시지로 알리게 한다
  changed_when: false

# runc 도 같이 확인 — 짝이 어긋난 채 넘어가는 것을 여기서 잡는다
- name: "Check installed runc version"
  command: dpkg-query -W --showformat=${Version} runc
  register: runc_pkg_version
  failed_when: false
  changed_when: false

# 실행 중인 데몬이 새 바이너리인지 확인
# dpkg 버전만 보면 "패키지는 2.2.1인데 데몬은 옛 프로세스" 상태가 통과한다 —
# AppArmor 프로파일은 데몬이 기동할 때 커널에 올라가므로 이 확인이 필요하다.
- name: "Check running containerd daemon version"
  command: containerd --version
  register: containerd_daemon_version
  failed_when: false
  changed_when: false

# hold 상태 확인
- name: "Check held packages"
  command: apt-mark showhold
  register: held_packages
  changed_when: false

# 설정 파일에 SystemdCgroup = true 반영 확인 (grep 미일치 시 rc=1 → 실패 처리 안 함)
- name: "Check SystemdCgroup in config"
  command: grep -c "SystemdCgroup = true" /etc/containerd/config.toml
  register: systemd_cgroup_check
  failed_when: false
  changed_when: false

# 설정 파일에 certs.d 경로 반영 확인
# 따옴표 종류(1.x 쌍따옴표 / 2.x 홑따옴표)와 콜론 목록 형태를 모두 받아들인다.
- name: "Check certs.d config_path in config"
  command: grep -Ec "config_path = ['\"][^'\"]*/etc/containerd/certs\.d" /etc/containerd/config.toml
  register: config_path_check
  failed_when: false
  changed_when: false

# 빈 config_path나 콜론 목록이 남지 않았는지 확인 — 2.x의 transfer 경유 pull은
# 빈 값이면 certs.d를 무시하고, 콜론 목록이면 통째로 한 경로로 취급해 못 찾는다.
# 어느 쪽이든 증상은 같다("HTTP response to HTTPS client"). certs.d 경로 매치만 세는
# 위 검증은 이 두 구멍을 못 잡는 전례가 있어(2026-08-12) 별도로 확인한다.
- name: "Check no empty or colon-list config_path remains"
  command: grep -Ec "config_path = (''|\"\"|['\"][^'\"]*:[^'\"]*['\"])" /etc/containerd/config.toml
  register: empty_config_path_check
  failed_when: false
  changed_when: false

# 레지스트리별 hosts.toml에 http 스킴 선언 확인
- name: "Check insecure registry hosts.toml"
  command: grep -c 'server = "http://{{ item }}"' /etc/containerd/certs.d/{{ item }}/hosts.toml
  register: registry_hosts_check
  failed_when: false
  changed_when: false
  loop: "{{ containerd_insecure_registries }}"

- name: "Assert containerd active, version pinned and held"
  assert:
    that:
      - containerd_status.stdout == "active"
      - containerd_pkg_version.stdout == containerd_version # 고정 버전 일치 (조건문 안에서는 {{ }} 금지)
      - runc_pkg_version.stdout == runc_version # 짝이 어긋나면 파드가 종료되지 않는다
      - '"containerd" in held_packages.stdout_lines'
      - '"runc" in held_packages.stdout_lines'
      - systemd_cgroup_check.stdout | int >= 1
      - config_path_check.stdout | int >= 1
      - empty_config_path_check.stdout | int == 0 # 빈 값/콜론 목록이 남으면 pull이 certs.d를 못 쓴다
      - containerd_version.split("-")[0] in containerd_daemon_version.stdout # 데몬이 옛 바이너리로 남아 있으면 실패
    success_msg: "Good!.. | containerd {{ containerd_pkg_version.stdout }} + runc {{ runc_pkg_version.stdout }} active & held (SystemdCgroup = true, certs.d enabled)"
    fail_msg: "ERROR!.. | containerd/runc 버전 불일치·hold 누락, 서비스 비활성, SystemdCgroup/certs.d 미반영(빈 config_path 잔존 포함), 또는 데몬이 옛 바이너리"

- name: "Assert insecure registry hosts.toml applied"
  assert:
    that:
      - item.stdout | int >= 1
    success_msg: "Good!.. | insecure registry applied: {{ item.item }}"
    fail_msg: "ERROR!.. | insecure registry NOT applied: {{ item.item }}"
  loop: "{{ registry_hosts_check.results }}"
  loop_control:
    label: "{{ item.item }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ containerd 설치 — 버전 고정 (멱등성 핵심)
- `containerd={{ containerd_version }}` 형식으로 인벤토리에 명시한 버전만 설치
- `allow_change_held_packages` + `allow_downgrade` → 버전 변수 변경 시 hold 상태여도 해당 버전으로 수렴
- 설치 후 `dpkg_selections`로 hold — 의도치 않은 업그레이드 방지
---
### 2️⃣ 설정 파일 생성 — SystemdCgroup 활성화 + certs.d 경로 지정
- `containerd config default` 출력을 `register`로 받아(`changed_when: false`)
`replace` 필터로 `SystemdCgroup = true` 치환 후 `copy`로 배포
- `config_path = "/etc/containerd/certs.d"`도 함께 치환 — 지정 없이는 hosts.toml을 읽지 않음
- ⚠ **2.x는 치환이 두 곳이다** — ① CRI 쪽 기본값은 **콜론 목록**
(`certs.d:/etc/docker/certs.d`)인데, 기본 pull 경로(transfer 플러그인,
`use_local_image_pull=false`)가 목록을 분리하지 않고 통째로 한 경로로 취급해 certs.d를
못 찾는다 → 단일 경로로 줄인다(**이쪽이 결정적** — 2026-08-12 실측). ② transfer 플러그인
자체의 `config_path`는 빈 값(홑따옴표)이라 함께 채운다. 어느 쪽이든 놓치면 HTTPS로 붙어
`server gave HTTP response to HTTPS client`로 pull이 죽는다
- 파이프+sed 방식은 비멱등이라 금지 — copy는 내용 동일 시 **changed=0** 보장
---
### 3️⃣ HTTP 사설 레지스트리 허용 — certs.d/hosts.toml
- 인벤토리 `containerd_insecure_registries` 목록으로 레지스트리별
`/etc/containerd/certs.d/<host:port>/hosts.toml` 배포
- `server = "http://..."`로 스킴을 박아 HTTPS 시도 자체를 차단
— TLS 없는 레지스트리 pull 시 `server gave HTTP response to HTTPS client` 방지
---
### 4️⃣ 서비스 기동 + 조건부 재시작
- `systemd` 모듈로 기동/자동시작 등록, 설정(config.toml/hosts.toml)이 **변경된 경우에만** 재시작
---
### 5️⃣ 검증
- 서비스 active + **설치 버전 = 고정 버전** + hold 상태 + `SystemdCgroup = true`
+ certs.d `config_path` + 레지스트리별 hosts.toml 존재를 `assert`로 검증
- **빈 값/콜론 목록 `config_path`가 0개**인 것도 함께 검증 — certs.d 경로 매치만 세면
빈 값도 콜론 목록도 통과하는 구멍이 있다(위 2️⃣의 실측 사례)
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert containerd active, version pinned and held]
ok: [ap] => {
    "msg": "Good!.. | containerd 1.7.12-0ubuntu4 active & held (SystemdCgroup = true, certs.d enabled)"
}

TASK [Assert insecure registry hosts.toml applied]
ok: [ap] => (item=data-layer-harbor) => {
    "msg": "Good!.. | insecure registry applied: data-layer-harbor"
}
```
---
