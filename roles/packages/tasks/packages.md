# 📦 Packages 설치 (Ansible)

- 서버 초기 세팅용 기본 패키지 설치
- `install_packages` 변수로 패키지 동적 관리
- 설치 후 `dpkg -s` 기반으로 실제 설치 여부 검증

---

## 🧩 main.yml

```yaml
# =====================================================
# 우분투 기본  Packages 설치
# =====================================================

# -----------------------------------------------------
# 1. 기본 유틸리티 패키지 설치
# -----------------------------------------------------
- name: "Install base packages"
  apt:
    name: "{{ install_packages }}"
    state: present # 없으면 설치
    update_cache: yes # apt update 먼저 실행
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략


# -----------------------------------------------------
# 2. 패키지 설치 검증
# -----------------------------------------------------
- name: "Check installed packages"
  command: "dpkg -s {{ item }}"
  loop: "{{ install_packages }}"
  register: packages_check
  changed_when: false
  failed_when: false

- name: "Assert packages installed"
  assert:
    that:
      - item.rc == 0
    fail_msg: "[FAIL] Some packages are missing"
    success_msg: "Good!.. | Packages installed successfully"
  loop: "{{ packages_check.results }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 패키지 설치
- `install_packages`에 정의된 패키지 설치
- `apt` 기반 설치 (update_cache 포함)

예시:
```yaml
# host.yml
install_packages:
  - net-tools
  - curl
  - wget
```
---
### 2️⃣ 패키지 설치 검증
- `dpkg -s <package>`로 설치 여부 확인
- `rc == 0`이면 정상 설치
- `rc != 0`이면 설치 실패
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert packages installed]
ok: [192.168.56.60] => {
    "msg": "Good!.. | Packages installed successfully"
}
~
```
---
