# 📂 Open Files 설정 (nofile)

- root 계정이 동시에 열 수 있는 파일 수 제한을 증가시킨다.
- 시스템 기본 제한으로 인한 서비스 장애를 방지하기 위한 설정이다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Open files ulimit 설정
# → 프로세스가 동시에 열 수 있는 파일 개수 제한을 조정하는 설정
# =====================================================

# -----------------------------------------------------
# 1. Open files 설정 (nofile)
# -----------------------------------------------------
# root 사용자의 open files 제한 증가
- name: "Set open files limit for root"
  lineinfile:
    path: /etc/security/limits.conf
    regexp: '^root\s+-\s+nofile'
    line: 'root - nofile 65536'
    state: present

# -----------------------------------------------------
# 2. Open files 설정 검증 (타겟 서버 파일 확인)
# -----------------------------------------------------
- name: "Check open files limit setting"
  command: "grep '^root - nofile' /etc/security/limits.conf"
  register: nofile_check
  changed_when: false

- name: "Assert open files limit is set for root"
  assert:
    that:
      - "'root - nofile 65536' in nofile_check.stdout"
    success_msg: "Good!.. | Open files limit for root is set to 65536"
    fail_msg: "ERROR!.. | Open files limit for root is NOT set"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ Open Files 제한 설정 (멱등성 핵심)
- `lineinfile`로 `/etc/security/limits.conf`의 `root - nofile` 라인 관리 — 자체 멱등
- root 계정의 nofile 제한을 65536 으로 설정, 재실행 시 **changed=0** 보장
---
### 2️⃣ 설정 검증
- 타겟 서버에서 `grep`으로 실제 설정 값 확인 후 `assert`
- ⚠️ `lookup('file', ...)`은 컨트롤 노드 파일을 읽으므로 검증에 사용 금지
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert open files limit is set for root]
ok: [192.168.56.60] => {
    "msg": "Good!.. | Open files limit for root is set to 65536"
}
```
