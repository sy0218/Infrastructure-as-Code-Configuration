# ☁️ cloud-init 비활성화 (Ansible)
- 부팅 시 cloud-init이 네트워크/hostname/사용자 설정을 자동 변경하지 못하도록 차단
- `/etc/cloud/cloud-init.disabled` 플래그 파일 존재 시 cloud-init 실행 skip
- `copy + force:no` 자체 멱등성 + **사후 검증(assert)** 흐름
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# cloud-init 비활성화 (플래그 파일 생성)
# =====================================================

# -----------------------------------------------------
# 1. /etc/cloud 디렉토리 보장 (file: directory 자체가 멱등)
# -----------------------------------------------------
- name: "Ensure /etc/cloud directory exists"
  file:
    path: /etc/cloud
    state: directory
    owner: root
    group: root
    mode: '0755'

# -----------------------------------------------------
# 2. 플래그 파일 생성 (copy + force:no → 없을 때만 생성되는 자체 멱등, touch처럼 mtime 갱신 없음)
# -----------------------------------------------------
- name: "Create cloud-init disabled flag"
  copy:
    content: ""
    dest: /etc/cloud/cloud-init.disabled
    force: false
    owner: root
    group: root
    mode: '0644'

# -----------------------------------------------------
# 3. cloud-init 비활성화 검증
# -----------------------------------------------------
- name: "Check cloud-init disabled flag"
  stat:
    path: /etc/cloud/cloud-init.disabled
  register: cloud_init_check

- name: "Assert cloud-init disabled"
  assert:
    that:
      - cloud_init_check.stat.exists
    success_msg: "Good!.. | cloud-init is disabled (flag file present)"
    fail_msg: "ERROR!.. | cloud-init.disabled flag file is missing"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 디렉토리 보장
- `file: state=directory`는 자체 멱등 → 있으면 아무것도 안 함
---
### 2️⃣ 플래그 파일 생성 (멱등성 핵심)
- `copy + force: false` → 파일이 없을 때만 생성, 있으면 그대로 둠
- `state: touch`와 달리 mtime 갱신이 없어 사전 체크 없이도 재실행 시 **changed=0** 보장
---
### 3️⃣ 비활성화 검증
- 플래그 파일 존재 여부를 `stat`으로 확인 후 `assert`
- 실패 시 플레이북 중단
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Create cloud-init disabled flag]
ok: [192.168.56.60]

TASK [Assert cloud-init disabled]
ok: [192.168.56.60] => {
    "msg": "Good!.. | cloud-init is disabled (flag file present)"
}
```
---
