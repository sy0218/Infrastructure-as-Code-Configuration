# ⎈ Helm 설치 (Helm)
- 배포 CLI 머신(helm 그룹)에 Helm CLI를 설치합니다 — 300-data-layer-base부터 워크로드 스택이 Terraform이 아니라 Helm 차트로 배포되기 때문입니다.
- apt 저장소(baltocdn) 대신 공식 CDN(get.helm.sh) tarball을 받습니다 — 랩 네트워크에서 baltocdn은 SSL 인증서 검증이 실패합니다.
- 버전·체크섬·설치 경로는 `group_vars/helm.yml` 변수로 관리 (롤은 범용, 인벤토리가 동작 결정)
- 클러스터 접속은 kubectl과 같은 `~/.kube/config`를 그대로 씁니다 — 이 롤은 CLI만 설치합니다.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# Helm 설치 → 공식 CDN 바이너리 + 버전 고정 링크
# -----------------------------------------------------
# 300-data-layer-base 부터 워크로드 스택이 Terraform 이 아니라 Helm 차트로 배포된다 —
#   terraform 롤과 같은 이유로 배포 CLI 머신(helm 그룹)에 설치한다.
# apt 저장소(baltocdn)를 쓰지 않는 이유: 이 랩 네트워크에서 SSL 인증서 검증이
#   실패한다(공식 CDN get.helm.sh 는 정상) → minio 롤과 같은 바이너리 설치 방식.
# 클러스터 접속은 kubectl 과 같은 ~/.kube/config 를 그대로 쓴다 — 이 롤은 CLI 만 설치한다.
# -----------------------------------------------------

# =========================================================================
# 1. 디렉토리 생성 (file 모듈 자체가 멱등)
#    → 버전별 보관 구조: dist/(tarball·압축 해제) + bin/(버전 붙은 실행 파일)
# =========================================================================
- name: "Create helm directories"
  file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - "{{ helm_install_root }}"
    - "{{ helm_install_root }}/bin"
    - "{{ helm_install_root }}/dist"
    - "{{ helm_install_root }}/dist/v{{ helm_version }}" # 버전별 압축 해제 자리

# =========================================================================
# 2. tarball 다운로드 (파일명에 버전 포함 → 버전 변경 시에만 새로 받음)
#    → checksum 핀: 불완전 다운로드/변조를 받는 즉시 잡는다.
#      값 확인: curl -fsSL https://get.helm.sh/helm-v<버전>-linux-amd64.tar.gz.sha256sum
# =========================================================================
- name: "Download helm tarball"
  get_url:
    url: "https://get.helm.sh/helm-v{{ helm_version }}-linux-amd64.tar.gz"
    dest: "{{ helm_install_root }}/dist/helm-v{{ helm_version }}-linux-amd64.tar.gz"
    checksum: "sha256:{{ helm_sha256 }}"
    owner: root
    group: root
    mode: '0644'
  register: helm_tarball
  retries: 3 # 외부망 다운로드 불안정 대비
  delay: 10
  until: helm_tarball is succeeded

# =========================================================================
# 3. 압축 해제 (버전별 디렉토리라 creates 가드가 버전 교체를 막지 않는다)
# =========================================================================
- name: "Extract helm tarball"
  unarchive:
    src: "{{ helm_install_root }}/dist/helm-v{{ helm_version }}-linux-amd64.tar.gz"
    dest: "{{ helm_install_root }}/dist/v{{ helm_version }}"
    remote_src: true
    creates: "{{ helm_install_root }}/dist/v{{ helm_version }}/linux-amd64/helm"

# =========================================================================
# 4. 실행 파일 배치 (copy 자체가 내용 비교로 멱등)
# =========================================================================
- name: "Install helm binary as versioned file"
  copy:
    src: "{{ helm_install_root }}/dist/v{{ helm_version }}/linux-amd64/helm"
    dest: "{{ helm_install_root }}/bin/helm-v{{ helm_version }}"
    remote_src: true
    owner: root
    group: root
    mode: '0755'

# =========================================================================
# 5. 심볼릭 링크 (file 모듈 자체가 멱등 / 버전 변경 시 링크만 교체되어 롤백이 쉽다)
# =========================================================================
- name: "Link helm into PATH"
  file:
    src: "{{ helm_install_root }}/bin/helm-v{{ helm_version }}"
    path: /usr/local/bin/helm
    state: link
    force: true # 수동 설치된 실파일이 있어도 링크로 교체(없으면 파일→링크 전환 거부로 실패)

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
# 바이너리 동작 + PATH 노출 확인 (--short 는 클러스터에 접속하지 않는다)
- name: "Check helm binary"
  command: helm version --short
  register: helm_bin_check
  changed_when: false

# 링크가 핀 버전을 가리키는지 확인 (stat 은 조회 전용)
- name: "Check helm link target"
  stat:
    path: /usr/local/bin/helm
  register: helm_link

- name: "Assert helm installed and version pinned"
  assert:
    that:
      - helm_bin_check.stdout.startswith("v" ~ helm_version) # 고정 버전 일치 (조건문 안에서는 {{ }} 금지)
      - helm_link.stat.islnk # PATH 의 helm 이 링크다
      - helm_link.stat.lnk_target == helm_install_root ~ "/bin/helm-v" ~ helm_version # 링크가 핀 버전을 가리킨다
    success_msg: "Good!.. | helm {{ helm_bin_check.stdout }} installed & linked"
    fail_msg: "ERROR!.. | helm version mismatch or link broken"
```
---
<br>

## 📌 group_vars 예시
```yaml
# =======================================
# Helm 설치 버전 고정 (helm 그룹 사용)
# =======================================
helm_version: "3.19.0" # get.helm.sh 태그 (v 접두어 제외)
helm_sha256: "a7f81ce08007091b86d8bd696eb4d86b8d0f2e1b9f6c714be62f82f96a594496" # 버전을 올리면 함께 갱신
helm_install_root: /application/helm # 버전별 바이너리 보관 루트(minio·buildkit 과 같은 컨벤션) → /usr/local/bin/helm 은 여기로의 링크
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 디렉토리 생성
- `dist/`(tarball·압축 해제)와 `bin/`(버전 붙은 실행 파일)을 분리 — minio 롤과 같은 버전별 보관 구조
- 압축 해제 자리를 버전별 디렉토리(`dist/v<버전>`)로 두는 이유는 3️⃣의 `creates=` 가드 때문
---
### 2️⃣ tarball 다운로드 (멱등성 핵심)
- 파일명에 버전이 들어가 재실행 시 재다운로드가 없고, 버전을 올리면 새 파일만 받는다
- `checksum: sha256` 핀으로 불완전 다운로드·변조를 받는 즉시 잡는다 — 값의 출처는 공식 CDN의 `.sha256sum` 파일
- 외부망 불안정 대비 `retries: 3` (minio·terraform 롤과 같은 선례)
---
### 3️⃣ 압축 해제
- `creates=` 가드로 재실행 시 건너뛴다 — 해제 대상이 **버전별 디렉토리**라서 버전을 올려도 가드가 새 버전 해제를 막지 않는다
  (해제 자리를 공유하면 옛 버전의 `linux-amd64/helm`이 가드에 걸려 새 버전이 영영 안 풀린다)
---
### 4️⃣ 실행 파일 배치
- `copy`(remote_src)는 내용 비교로 멱등 — 같은 바이너리면 changed가 나지 않는다
- `bin/helm-v<버전>`으로 버전을 파일명에 남긴다 — 어떤 버전이 설치돼 있는지 파일 목록만으로 보인다
---
### 5️⃣ 심볼릭 링크 (PATH 노출)
- `/usr/local/bin/helm` → `bin/helm-v<버전>` 링크 — 버전 교체·롤백이 링크 교체 하나로 끝난다
- `force: true`를 두는 이유: 수동 설치된 실파일이 그 자리에 있으면 file 모듈이 파일→링크 전환을 거부한다 — force가 있어야 롤이 어떤 사전 상태에서도 같은 결과로 수렴한다
---
### 6️⃣ 검증
- `helm version --short`(클러스터 접속 없음) 출력이 핀 버전으로 시작하는지 + PATH의 helm이 핀 버전을 가리키는 링크인지 `assert`
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert helm installed and version pinned]
ok: [192.168.56.202] => {
    "msg": "Good!.. | helm v3.19.0+g3d8990f installed & linked"
}
```
