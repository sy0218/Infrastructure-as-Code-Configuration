# 🖥 Control Node 기본 설정 (Ansible)

- Ansible **Control Node**에서
  password 기반 SSH 통신을 위해 필요한 **sshpass 설치 및 검증** 작업을 수행한다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Control Node 기본 설정
# =====================================================

# -----------------------------------------------------
# 1. sshpass 설치 (apt가 멱등 처리: 없으면 설치, 있으면 그대로)
# sshpass → ssh 접속을 자동화할 때 비밀번호를 명령어로 넘길 수 있게 해주는 도구
# -----------------------------------------------------
- name: "Install sshpass on Control node"
  apt:
    name: sshpass # 설치할 패키지 명
    state: present # 모듈 기반 멱등성(없으면 설치 / 있으면 그대로)
    update_cache: yes # apt update 먼저 수행
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략

# -----------------------------------------------------
# 2. sshpass 실행 검증 (실패하면 여기서 플레이 즉시 실패)
# -----------------------------------------------------
- name: "Verify sshpass version"
  command: sshpass -V
  register: sshpass_check
  changed_when: false

# -----------------------------------------------------
# 3. 검증 결과 출력 (assert 기반)
# ansible assert → 조건 맞는지 검사, 아니면 실행을 즉시 실패시키는 검증용 도구
# -----------------------------------------------------
- name: "Verify sshpass installation"
  assert:
    that:
      - sshpass_check.rc == 0
    fail_msg: "[FAIL] sshpass install failed"
    success_msg: "[SUCCESS] {{ sshpass_check.stdout_lines[0] | default('sshpass ok') }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ sshpass 설치 ( 멱등 )
- `apt: state=present` 자체가 멱등 → 사전 체크 불필요 (없으면 설치, 있으면 skip)
- `cache_valid_time: 3600` → 캐시가 1시간 이내면 apt update 생략 (재실행 속도 ↑)
---
### 2️⃣ sshpass 버전 확인
- 설치 정상 여부 확인, 실패 시 playbook 즉시 중단
```bash
sshpass -V
```
---
### 3️⃣ assert 검증
- 검증 결과 메시지 출력 (성공/실패)
```yaml
assert:
  that:
    - sshpass_check.rc == 0
```

---
<br>

## ✅ 실행 결과 예시
```bash
[SUCCESS] sshpass 1.09
```
---
