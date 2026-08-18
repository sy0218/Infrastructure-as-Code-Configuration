# 📦 Terraform 설치 (Ansible)
- HashiCorp 공식 apt 저장소를 등록하고 **인벤토리 `terraform_version`으로 버전 고정** 설치한다.
- 저장소 등록은 `deb822_repository` 모듈로 키 다운로드/변환까지 한 태스크로 처리
— `gpg --dearmor` 수동 실행은 비멱등이라 금지.
- 설치 후 hold로 고정해 의도치 않은 업그레이드를 방지한다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Terraform 설치
# =====================================================
# HashiCorp apt 저장소 + 버전 고정
# 저장소 등록 → 설치 → 버전 고정(hold)
# =====================================================


# -----------------------------------------------------
# 1. deb822_repository 모듈 의존성 설치 (apt 모듈 자체가 멱등)
#    (다른 롤에 기대지 않고 롤이 자기 의존성을 직접 보장)
# -----------------------------------------------------
- name: "Install python3-debian"
  apt:
    name: python3-debian
    state: present
    update_cache: yes # apt update 먼저 실행
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략

# -----------------------------------------------------
# 2. HashiCorp apt 저장소 등록
#      - 키 다운로드/변환 + 저장소 등록을 한 태스크로 처리
#      - (deb822_repository 모듈 자체가 멱등)
# -----------------------------------------------------
- name: "Add hashicorp apt repository"
  deb822_repository:
    name: hashicorp
    uris: "https://apt.releases.hashicorp.com"
    suites: "{{ hashicorp_repo_release }}"
    components: main
    architectures: amd64
    signed_by: "https://apt.releases.hashicorp.com/gpg"
  register: hashicorp_repo

# -----------------------------------------------------
# 3. 저장소가 새로 등록/변경된 경우만 apt 캐시 갱신
# -----------------------------------------------------
- name: "Update apt cache"
  apt:
    update_cache: yes
  when: hashicorp_repo.changed

# -----------------------------------------------------
# 4. Terraform 설치
#      — 인벤토리 terraform_version으로 버전 고정 (apt 모듈 자체가 멱등)
#      - 버전 변경 시 hold 상태여도 해당 버전으로 수렴
#      - CDN 연결 불안정 대비 재시도 (이미 받은 .deb는 apt 캐시에 남아 실패분만 다시 받음)
- name: "Install terraform"
  apt:
    name: "terraform={{ terraform_version }}"
    state: present
    allow_change_held_packages: true # hold 상태에서도 버전 변경 허용
    allow_downgrade: true # 하위 버전으로 고정 시 다운그레이드 허용
  register: terraform_install
  retries: 3 # 실패 시 재시도 횟수
  delay: 10 # 재시도 간격(초)
  until: terraform_install is succeeded
# -----------------------------------------------------

# -----------------------------------------------------
# 5. 버전 고정 → 의도치 않은 업그레이드 방지
#    (dpkg_selections 자체가 멱등)
# -----------------------------------------------------
- name: "Hold terraform package"
  dpkg_selections:
    name: terraform
    selection: hold

# -----------------------------------------------------
# 6. 검증
# -----------------------------------------------------
# 설치된 패키지 버전 확인
- name: "Check installed terraform version"
  command: dpkg-query -W --showformat=${Version} terraform
  register: terraform_pkg_version
  changed_when: false

# 바이너리 동작 확인
- name: "Check terraform binary"
  command: terraform version
  register: terraform_bin_check
  changed_when: false

# hold 상태 확인
- name: "Check held packages"
  command: apt-mark showhold
  register: held_terraform
  changed_when: false

- name: "Assert terraform installed, version pinned and held"
  assert:
    that:
      - terraform_pkg_version.stdout == terraform_version # 고정 버전 일치 (조건문 안에서는 {{ }} 금지)
      - terraform_bin_check.stdout_lines[0] == "Terraform v" ~ terraform_version.split("-")[0] # 바이너리 버전 일치
      - '"terraform" in held_terraform.stdout_lines' # 라인 단위 정확 일치
    success_msg: "Good!.. | terraform {{ terraform_pkg_version.stdout }} installed & held"
    fail_msg: "ERROR!.. | terraform version mismatch or NOT held"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ HashiCorp apt 저장소 등록 (멱등성 핵심)
- `deb822_repository` 모듈로 GPG 키 등록 + 저장소 추가를 한 태스크로 처리
- 롤이 `python3-debian` 의존성을 직접 설치 — 다른 롤(packages)에 기대지 않음
- 저장소가 **새로 등록/변경된 경우에만** apt 캐시 갱신
---
### 2️⃣ Terraform 설치 — 버전 고정
- `terraform={{ terraform_version }}` 형식으로 인벤토리에 명시한 버전만 설치
- `allow_change_held_packages` + `allow_downgrade` → 버전 변수 변경 시 hold 상태여도 해당 버전으로 수렴
- CDN 연결 불안정 대비 `retries: 3` 재시도
- 설치 후 `dpkg_selections`로 hold — 의도치 않은 업그레이드 방지
---
### 3️⃣ 검증
- **설치 버전 = 고정 버전** + 바이너리 동작(`terraform version`) + hold 상태를 `assert`로 검증
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert terraform installed, version pinned and held]
ok: [ap] => {
    "msg": "Good!.. | terraform 1.15.8-1 installed & held"
}
```
---
