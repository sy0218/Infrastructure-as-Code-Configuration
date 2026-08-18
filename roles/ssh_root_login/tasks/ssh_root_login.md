# 🔐 SSH Root Login 설정 (Ansible)

- SSH 설정을 통해  
  **root 계정의 SSH 로그인(PermitRootLogin)** 을 허용한다.
- 일반적인 운영 방식인 `/etc/ssh/sshd_config` 파일을 직접 수정한다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# SSH Root Login 허용 설정
# =====================================================


# -----------------------------------------------------
# 1. SSH 설정 (Root Login 허용)
# -----------------------------------------------------
- name: "Set SSH PermitRootLogin yes"
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin yes'
    state: present
  notify: Reload sshd

# -----------------------------------------------------
# 2. SSH 설정 검증 (타겟 서버 파일 확인 → lookup은 컨트롤 노드를 읽으므로 사용 금지)
# -----------------------------------------------------
- name: "Check PermitRootLogin setting"
  command: "grep '^PermitRootLogin' /etc/ssh/sshd_config"
  register: root_login_check
  changed_when: false

- name: "Assert PermitRootLogin is enabled"
  assert:
    that:
      - "'PermitRootLogin yes' in root_login_check.stdout"
    success_msg: "Good!.. | SSH root login is enabled (PermitRootLogin yes)"
    fail_msg: "ERROR!.. | SSH root login is NOT enabled"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ SSH Root Login 허용 설정 (멱등성 핵심)
- `lineinfile`로 `/etc/ssh/sshd_config`의 `PermitRootLogin` 설정 관리 — 자체 멱등
- 주석(`#PermitRootLogin`) 상태여도 자동으로 치환
- 이미 설정되어 있으면 재실행 시 **changed=0** 보장
---
### 2️⃣ SSH 데몬 설정 반영
- 설정이 변경된 경우에만 `Reload sshd` handler 실행
- 불필요한 서비스 재시작 방지
---
### 3️⃣ SSH 설정 검증
- 타겟 서버에서 `grep`으로 실제 설정 값 확인 후 `assert`
- ⚠️ `lookup('file', ...)`은 컨트롤 노드 파일을 읽으므로 검증에 사용 금지
---
<br>

## 🧩 handlers/main.yml
```yaml
# Ubuntu의 SSH 유닛 이름은 ssh (sshd는 별칭 → 24.04 소켓 활성화 환경에선 못 찾음)
- name: Reload sshd
  systemd:
    name: ssh
    state: reloaded
```
- SSH 설정 변경 시에만 호출되는 handler
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert PermitRootLogin is enabled]
ok: [192.168.56.60] => {
    "msg": "Good!.. | SSH root login is enabled (PermitRootLogin yes)"
}
```
