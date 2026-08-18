# ⏱ NTP 설정 (Ansible)

- 시스템 시간 동기화를 위해  
  **systemd-timesyncd 기반 NTP 서버를 설정**한다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# NTP 설정
# =====================================================


# -----------------------------------------------------
# 1. NTP 서버 설정 (lineinfile 자체가 멱등)
# -----------------------------------------------------
- name: "Set NTP server to 0.kr.pool.ntp.org"
  lineinfile:
    path: /etc/systemd/timesyncd.conf
    regexp: '^#?NTP='
    line: 'NTP=0.kr.pool.ntp.org'
    state: present
  notify: Restart timesyncd # 변경 시에만 재시작

# -----------------------------------------------------
# 2. NTP 설정 검증 (타겟 서버 파일 확인)
# -----------------------------------------------------
- name: "Check NTP server setting"
  command: "grep '^NTP=' /etc/systemd/timesyncd.conf"
  register: ntp_check
  changed_when: false

- name: "Assert NTP server is set"
  assert:
    that:
      - "'NTP=0.kr.pool.ntp.org' in ntp_check.stdout"
    success_msg: "Good!.. | NTP server is set to 0.kr.pool.ntp.org"
    fail_msg: "ERROR!.. | NTP server is NOT set"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ NTP 서버 설정 (멱등성 핵심)
- `lineinfile`로 `/etc/systemd/timesyncd.conf`의 `NTP=` 라인 관리 — 자체 멱등
- 주석(`#NTP=`) 상태여도 자동으로 치환, 재실행 시 **changed=0** 보장
---
### 2️⃣ 시간 동기화 서비스 재시작 (handler)
- 설정이 변경된 경우에만 `Restart timesyncd` handler 실행
- 매 실행마다 무조건 재시작하던 비멱등 태스크를 handler로 전환
---
### 3️⃣ NTP 설정 검증
- 타겟 서버에서 `grep`으로 실제 설정 값 확인 후 `assert`
- ⚠️ `lookup('file', ...)`은 컨트롤 노드 파일을 읽으므로 검증에 사용 금지
---
<br>

## 🧩 handlers/main.yml
```yaml
# NTP 설정 변경 시에만 timesyncd 재시작
- name: Restart timesyncd
  systemd:
    name: systemd-timesyncd
    state: restarted
```
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert NTP server is set]
ok: [192.168.56.60] => {
    "msg": "Good!.. | NTP server is set to 0.kr.pool.ntp.org"
}
```
