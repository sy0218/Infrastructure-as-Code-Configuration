# 🕒 Time Zone 설정 (Ansible)

- 시스템 Time Zone을 한국 기준인 **Asia/Seoul** 로 설정한다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Server Time zone 설정
# =====================================================


# -----------------------------------------------------
# 1. 타임존 설정 (timezone 모듈 자체가 멱등)
# -----------------------------------------------------
- name: "Set Time zone to Asia/Seoul"
  timezone:
    name: Asia/Seoul

# -----------------------------------------------------
# 2. 타임존 설정 검증 (타겟 서버에서 확인)
# -----------------------------------------------------
- name: "Check current time zone"
  command: timedatectl show -p Timezone --value
  register: timezone_check
  changed_when: false

- name: "Assert Time zone is Asia/Seoul"
  assert:
    that:
      - timezone_check.stdout == "Asia/Seoul"
    success_msg: "Good!.. | Time zone is set to Asia/Seoul"
    fail_msg: "ERROR!.. | Time zone is NOT Asia/Seoul (current: {{ timezone_check.stdout }})"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ Time Zone 설정 (멱등성 핵심)
- `timezone` 모듈로 시스템 Time Zone 변경 — 이미 Asia/Seoul이면 재실행 시 **changed=0** 보장
- `command: timedatectl set-timezone`은 매번 changed 유발이라 모듈로 대체
---
### 2️⃣ Time Zone 검증
- 타겟 서버에서 `timedatectl show -p Timezone --value`로 현재 값 확인 후 `assert`
- ⚠️ `lookup('pipe', ...)`은 컨트롤 노드에서 실행되므로 검증에 사용 금지
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert Time zone is Asia/Seoul]
ok: [192.168.56.60] => {
    "msg": "Good!.. | Time zone is set to Asia/Seoul"
}
```
