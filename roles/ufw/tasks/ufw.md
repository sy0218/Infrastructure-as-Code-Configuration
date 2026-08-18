# 🔥 방화벽(UFW) 비활성화 (Ansible)
- Ubuntu 기본 방화벽인 UFW(Uncomplicated Firewall) 를 비활성화한다.
- 서버 간 통신, 테스트 환경, 내부망 구성 시
방화벽으로 인한 포트 차단 이슈를 방지하기 위함이다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 방화벽(UFW) 비활성화
# =====================================================

# -----------------------------------------------------                   
# 1. UFW 서비스 중지 + 부팅 자동시작 해제 (systemd 모듈 자체가 멱등 → 사전 체크 불필요)
# -----------------------------------------------------
- name: "Disable UFW firewall"
  systemd:
    name: ufw
    enabled: false
    state: stopped

# -----------------------------------------------------
# 2. 방화벽 비활성화 검증
# -----------------------------------------------------
- name: "Check UFW status"
  command: systemctl is-active ufw
  register: ufw_status
  failed_when: false
  changed_when: false

- name: "Assert UFW disabled"
  assert:
    that:
      - ufw_status.stdout != "active"
    success_msg: "Good!.. | UFW is disabled ({{ ufw_status.stdout }})"
    fail_msg: "[FAIL] UFW is still active"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ UFW 서비스 중지 + 자동 시작 해제 (멱등성 핵심)
- `systemd` 모듈로 서비스 중지(`state: stopped`) + 부팅 자동 실행 방지(`enabled: false`)
- 모듈 자체가 멱등 → 이미 중지돼 있으면 재실행 시 **changed=0** 보장
---
### 2️⃣ 방화벽 상태 검증
- `systemctl is-active ufw`로 상태 확인 (`failed_when: false`로 inactive여도 흐름 유지)
- `assert`로 `active`가 아님을 검증 — 실패 시 플레이북 중단
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert UFW disabled]
ok: [192.168.56.60] => {
    "msg": "Good!.. | UFW is disabled (inactive)"
}
```
---
