# 🔐 SSH Key 생성 및 상호 공유 (Ansible)
- 서버 초기 세팅 시 **모든 서버 간 SSH 무비밀번호 접속 구성**
- 각 서버에서 SSH Key를 생성하고, 모든 서버의 공개키를 상호 교환하여 `authorized_keys`에 등록
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 모든 서버 SSH Key 생성 및 상호 공유
# =====================================================


# -----------------------------------------------------
# 1. SSH 키 쌍 생성 (openssh_keypair 자체가 멱등 → force:no로 기존 키 유지)
# -----------------------------------------------------
- name: "Create Ed25519 key pair"
  openssh_keypair:
    path: /root/.ssh/id_ed25519
    type: ed25519 # 키 길이 고정이라 size 불필요
    owner: root
    group: root
    mode: '0600'
    force: no
  register: ssh_key

# -----------------------------------------------------
# 2. 공개키를 host fact로 저장
# -----------------------------------------------------
- name: "Save public key as host fact"
  set_fact:
    my_public_key: "{{ ssh_key.public_key }}"

# -----------------------------------------------------
# 3. 모든 서버 공개키를 리스트로 수집
# -----------------------------------------------------
- name: "Collect all server public keys"
  set_fact:
    all_public_keys: >-
      {{
        groups['Ubuntu_Servers']
        | map('extract', hostvars, 'my_public_key')
        | list
      }}

# -----------------------------------------------------
# 4. authorized_keys에 모든 서버 공개키 배포
#    (authorized_key 자체가 멱등 + 파일 생성/0600 권한까지 모듈이 관리 → 별도 권한 태스크 불필요)
# -----------------------------------------------------
- name: "Distribute all server public keys"
  authorized_key:
    user: root
    key: "{{ item }}"
    state: present
  loop: "{{ all_public_keys }}"

# -----------------------------------------------------
# 5. ssh_keygen 검증 (타겟 서버 파일 확인)
# -----------------------------------------------------
- name: "Check authorized_keys entries"
  command: "grep -F '{{ item }}' /root/.ssh/authorized_keys"
  loop: "{{ all_public_keys }}"
  register: authkey_check
  changed_when: false
  failed_when: false

- name: "Assert SSH key exchange completed"
  assert:
    that:
      - item.rc == 0
    success_msg: "Good!.. | SSH key exchange completed"
    fail_msg: "ERROR!.. | SSH key missing in authorized_keys"
  loop: "{{ authkey_check.results }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ SSH 키 쌍 생성 (멱등성 핵심)
- `openssh_keypair` 모듈로 **Ed25519** 키 생성 (`/root/.ssh/id_ed25519`)
- RSA 4096 대비 짧고 빠르며 현대 권장 방식, 키 길이 고정이라 `size` 불필요
- `force: no` → 기존 키가 있으면 유지, 재실행 시 **changed=0** 보장
---
### 2️⃣ 공개키 Fact 저장
- 생성된 공개키를 `my_public_key` 변수로 저장
- 이후 서버 간 공개키 수집에 사용
---
### 3️⃣ 모든 서버 공개키 수집
- 인벤토리 그룹 Ubuntu_Servers 기준
- `hostvars`를 사용하여 모든 서버의 공개키를 리스트로 취합
---
### 4️⃣ 공개키 상호 배포
- 모든 서버의 공개키를 각 서버의 `authorized_keys`에 등록
- `authorized_key` 모듈이 파일 생성과 0600 권한까지 관리 (별도 권한 보정 불필요)
- 결과적으로 모든 서버 ↔ 모든 서버 간 SSH 무비밀번호 접속 가능
---
### 5️⃣ SSH 키 교환 검증
- 타겟 서버의 `authorized_keys`에서 **모든 서버의 공개키**를 `grep -F`로 확인 후 `assert`
- ⚠️ `lookup('file', ...)`은 컨트롤 노드 파일을 읽으므로 검증에 사용 금지
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert SSH key exchange completed]
ok: [192.168.56.60] => (item=...) => {
    "msg": "Good!.. | SSH key exchange completed"
}
```
---
