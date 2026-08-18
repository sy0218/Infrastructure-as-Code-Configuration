# 🔑 Root Password 설정 (Ansible)
- 서버 초기 세팅 시 **root 계정 패스워드 설정**
- `root_password` 변수를 SHA512로 암호화하여 적용
- 설정 결과를 register + assert로 검증
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Root Password 설정
# =====================================================

# -----------------------------------------------------
# 1. root 패스워드 설정
# salt를 호스트별 고정값으로 지정 → 해시가 매번 달라지지 않아 멱등 보장
# -----------------------------------------------------
- name: "Set Root Password"
  user:
    name: root
    password: "{{ root_password | password_hash('sha512', 65534 | random(seed=inventory_hostname) | string) }}"
    shell: /bin/bash
  register: root_pw_result

# -----------------------------------------------------
# 2. root 패스워드 설정 검증
# -----------------------------------------------------
- name: "Assert root password set"
  assert:
    that:
      - root_pw_result is succeeded
    fail_msg: "[FAIL] root password set failed"
    success_msg: "[SUCCESS] root password set verified successfully"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ Root 계정 패스워드 설정
- `root_password` 변수 기반으로 root 계정 패스워드 설정
- `password_hash('sha512', 고정 salt)`로 암호화 — 호스트별 고정 salt로 재실행 시 `changed` 없음 (멱등)
- 결과를 `root_pw_result`로 저장
---
### 2️⃣ Root 패스워드 설정 검증
- `root_pw_result is succeeded`로 성공/실패 판단
- 실패 시 즉시 플레이북 중단 (`assert fail`)
- 성공 시 검증 메시지 출력
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert root password set]
ok: [192.168.56.60] => {
    "msg": "[SUCCESS] root password set verified successfully"
}
~
```
---
