# ⏱ Swap 비활성화 (Ansible)

- 시스템에서 **스왑(Swap) 사용을 비활성화**하여 메모리 관리 및 성능 최적화를 수행합니다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 스왑(Swap) 비활성화
# =====================================================


# -----------------------------------------------------
# 1. 활성 swap 사전 확인 (swapoff는 비멱등 → 활성 상태일 때만 실행하도록 게이팅)
# -----------------------------------------------------
- name: "Check active swap"
  command: swapon --noheadings
  register: swap_pre_check
  changed_when: false

# -----------------------------------------------------
# 2. 활성 swap이 있을 때만 끄기
# -----------------------------------------------------
- name: "Disable all swap"
  command: swapoff -a
  when: swap_pre_check.stdout | trim | length > 0

# -----------------------------------------------------
# 3. fstab에서 swap 주석 처리 → 재부팅 시 활성화 방지
#    (replace 자체가 멱등 → 이미 주석 처리된 라인은 regexp에 안 걸림)
# -----------------------------------------------------
- name: "Comment out swap in /etc/fstab"
  replace:
    path: /etc/fstab
    regexp: '^([^#].*swap.*)$'
    replace: '# \1'

# -----------------------------------------------------
# 4. Swap 비활성화 검증
# -----------------------------------------------------
- name: "Check active swap devices"
  command: swapon --noheadings
  register: swap_status
  changed_when: false

- name: "Assert swap is disabled"
  assert:
    that:
      - swap_status.stdout_lines | length == 0
    success_msg: "Good!.. | Swap is disabled"
    fail_msg: "ERROR!.. | Swap is still enabled"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 활성 swap 사전 확인 (멱등성 핵심)
- `swapon --noheadings`로 현재 활성 스왑 조회 (`changed_when: false`)
- `swapoff`는 비멱등 명령이라 사전 체크 결과로 게이팅
---
### 2️⃣ 활성 시에만 스왑 끄기
- `when: swap_pre_check.stdout | trim | length > 0` → 이미 꺼져 있으면 skip
- 재실행 시 **changed=0** 보장
---
### 3️⃣ 재부팅 후 활성화 방지
- `/etc/fstab` 내 swap 항목을 `replace`로 주석 처리 — 주석된 라인은 regexp에 안 걸려 자체 멱등
---
### 4️⃣ 비활성화 검증
- `swapon --noheadings`로 활성 스왑 장치가 없는지 `assert`
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Disable all swap]
skipping: [192.168.56.60]

TASK [Assert swap is disabled]
ok: [192.168.56.60] => {
    "msg": "Good!.. | Swap is disabled"
}
```
---
