# 🔒 패키지 자동 업데이트 비활성화 (APT)

- 시스템 패키지의 **자동 업데이트를 비활성화**하여 예기치 않은 업그레이드로 인한 서비스 장애를 방지한다.
- `unattended-upgrades` 및 주기적 패키지 목록 업데이트를 차단한다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 패키지 자동 업데이트 비활성화
# =====================================================


# ----------------------------------------------------- 
# 1. APT 패키지 목록 자동 업데이트 비활성화
# -----------------------------------------------------
- name: "Disable APT periodic package list update"
  lineinfile:
    path: /etc/apt/apt.conf.d/20auto-upgrades
    regexp: '^APT::Periodic::Update-Package-Lists'
    line: 'APT::Periodic::Update-Package-Lists "0";'
    state: present
    create: yes

# -----------------------------------------------------
# 2. Unattended Upgrade 비활성화
# -----------------------------------------------------
- name: "Disable unattended upgrades"
  lineinfile:
    path: /etc/apt/apt.conf.d/20auto-upgrades
    regexp: '^APT::Periodic::Unattended-Upgrade'
    line: 'APT::Periodic::Unattended-Upgrade "0";'
    state: present
    create: yes

# -----------------------------------------------------
# 3. 자동 업데이트 비활성화 검증
# -----------------------------------------------------
- name: "Check auto-upgrade configuration"
  command: cat /etc/apt/apt.conf.d/20auto-upgrades
  register: auto_upgrade_conf
  changed_when: false

- name: "Assert auto-upgrade is disabled"
  assert:
    that:
      - "'APT::Periodic::Update-Package-Lists \"0\";' in auto_upgrade_conf.stdout"
      - "'APT::Periodic::Unattended-Upgrade \"0\";' in auto_upgrade_conf.stdout"
    success_msg: "Good!.. | APT automatic updates are disabled"
    fail_msg: "ERROR!.. | APT automatic updates are NOT disabled"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 패키지 목록 자동 업데이트 비활성화
- APT::Periodic::Update-Package-Lists 값을 0으로 설정
- 주기적인 apt update 자동 실행 차단
---
### 2️⃣ Unattended Upgrade 비활성화
- APT::Periodic::Unattended-Upgrade 값을 0으로 설정
- 백그라운드 자동 패키지 업그레이드 방지
---
### 3️⃣ 설정 검증
- /etc/apt/apt.conf.d/20auto-upgrades 파일 내용을 직접 확인
- 설정값이 정확히 적용되었는지 assert로 검증
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert auto-upgrade is disabled]
ok: [192.168.56.60] => {
    "msg": "Good!.. | APT automatic updates are disabled"
}
~
```
---
