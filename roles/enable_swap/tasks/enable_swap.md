# ⏱ Swap 생성 및 활성화 (Ansible)

- 스왑 파일을 **생성(dd) → 포맷(mkswap) → 활성화(swapon) → fstab 등록**하여 스왑을 구성합니다.
- 경로/크기는 인벤토리 변수(`swap_file_path`, `swap_size_mb`)로 결정합니다.
- `swap_size_mb` 변경 시 **스왑 파일을 재생성**하여 목표 크기로 수렴합니다.
- ⚠️ 활성 스왑 재생성은 `swapoff`를 동반 — 메모리 사용량이 높은 운영 장비에서는 주의가 필요합니다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 스왑(Swap) 파일 생성 및 활성화
# =====================================================
# [주의] swap_size_mb 변경 시 스왑 파일을 재생성하여 크기를 수렴시킴
#   - 활성 스왑이면 먼저 swapoff 후 재생성 
#   — 메모리 사용량이 높은 운영 장비에서는 swapoff가 오래 걸리거나 실패할 수 있으므로 주의
# =====================================================


# -----------------------------------------------------
# 1. 스왑 파일 상태 확인 (stat 모듈 자체가 멱등)
# -----------------------------------------------------
- name: "Check swap file status"
  stat:
    path: "{{ swap_file_path }}"
  register: swap_file_stat

# -----------------------------------------------------
# 2. 재생성 필요 여부 판단 → 파일이 없거나 크기가 목표(swap_size_mb)와 다르면 재생성
# -----------------------------------------------------
- name: "Determine swap file rebuild"
  set_fact:
    swap_rebuild_needed: >-
      {{ not swap_file_stat.stat.exists
         or swap_file_stat.stat.size != (swap_size_mb | int) * 1024 * 1024 }}

# -----------------------------------------------------
# 3. 활성 swap 사전 확인 (swapoff/swapon은 비멱등 → 상태 기반 게이팅용)
# -----------------------------------------------------
- name: "Check active swap"
  command: swapon --noheadings --show=NAME
  register: swap_active_check
  changed_when: false

# -----------------------------------------------------
# 4. 재생성 대상 스왑이 활성 상태면 먼저 끄기 (활성 상태의 스왑 파일은 재생성 불가)
# -----------------------------------------------------
- name: "Disable swap file before rebuild"
  command: "swapoff {{ swap_file_path }}"
  when:
    - swap_rebuild_needed | bool
    - swap_file_path in swap_active_check.stdout_lines

# -----------------------------------------------------
# 5. 스왑 파일 (재)생성 → swap_size_mb 변경 시에도 여기서 목표 크기로 수렴
#    - (fallocate는 파일시스템에 따라 hole 문제로 swapon이 거부할 수 있어 dd 사용u)
# -----------------------------------------------------
- name: "Create swap file"
  command: "dd if=/dev/zero of={{ swap_file_path }} bs=1M count={{ swap_size_mb }}"
  when: swap_rebuild_needed | bool

# -----------------------------------------------------
# 6. 스왑 파일 권한 설정 (file 모듈 자체가 멱등)
# -----------------------------------------------------
- name: "Set swap file permissions"
  file:
    path: "{{ swap_file_path }}"
    owner: root
    group: root
    mode: "0600"

# -----------------------------------------------------
# 7. 스왑 시그니처 사전 확인 (mkswap은 비멱등 → 시그니처 없을 때만 실행하도록 게이팅)
#    (시그니처가 없으면 blkid가 rc=2를 반환 → 정상 케이스이므로 실패로 처리하지 않음.
#     재생성 직후엔 시그니처가 없으므로 이 조건이 재생성 케이스도 포함)
# -----------------------------------------------------
- name: "Check swap signature"
  command: "blkid -o value -s TYPE {{ swap_file_path }}"
  register: swap_sig_check
  changed_when: false
  failed_when: swap_sig_check.rc not in [0, 2]

# ----------------------------------------------------- 
# 8. 스왑 시그니처가 없을 때만 포맷
# -----------------------------------------------------
- name: "Format swap file"
  command: "mkswap {{ swap_file_path }}"
  when: swap_sig_check.stdout | trim != "swap"

# -----------------------------------------------------
# 9. 스왑 활성화 → 미활성 상태거나 재생성한 경우만 켜기
# -----------------------------------------------------
- name: "Enable swap file"
  command: "swapon {{ swap_file_path }}"
  when: swap_rebuild_needed | bool
        or swap_file_path not in swap_active_check.stdout_lines

# -----------------------------------------------------
# 10. fstab에 스왑 등록 → 재부팅 후에도 유지
#     - (lineinfile 자체가 멱등 → disable_swap이 주석 처리한 라인도 활성 라인으로 복원)
# -----------------------------------------------------
- name: "Persist swap in /etc/fstab"
  lineinfile:
    path: /etc/fstab
    regexp: '^#?\s*{{ swap_file_path | regex_escape }}\s'
    line: "{{ swap_file_path }} none swap sw 0 0"

# -----------------------------------------------------
# 11. Swap 활성화 검증
# -----------------------------------------------------
- name: "Check active swap devices"
  command: swapon --noheadings --show=NAME
  register: swap_status
  changed_when: false

- name: "Check final swap file size"
  stat:
    path: "{{ swap_file_path }}"
  register: swap_file_final

- name: "Assert swap is enabled with desired size"
  assert:
    that:
      - swap_file_path in swap_status.stdout_lines
      - swap_file_final.stat.size == (swap_size_mb | int) * 1024 * 1024
    success_msg: "Good!.. | Swap is enabled"
    fail_msg: "ERROR!.. | Swap is not active or size mismatch"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 재생성 필요 여부 판단 (크기 수렴 핵심)
- `stat`으로 파일 존재/크기 확인 → 없거나 `swap_size_mb`와 다르면 `swap_rebuild_needed` 셋
- 크기 비교 기준: `swap_size_mb × 1024 × 1024` 바이트
---
### 2️⃣ 재생성 전 스왑 끄기
- 재생성 대상이 활성 목록에 있을 때만 `swapoff` (활성 스왑 파일은 재생성 불가)
---
### 3️⃣ 스왑 파일 (재)생성 + 권한
- `dd if=/dev/zero bs=1M count={{ swap_size_mb }}`로 목표 크기 생성 (fallocate는 hole 문제로 미사용)
- `file` 모듈로 `root:root`, `0600` 보장 — 모듈 자체 멱등
---
### 4️⃣ 스왑 포맷 (멱등성 핵심)
- `blkid`로 스왑 시그니처 사전 확인 (시그니처 없으면 rc=2 → 정상 처리)
- `mkswap`은 비멱등이라 시그니처가 없을 때만 실행 — 재생성 직후도 이 조건에 포함
---
### 5️⃣ 스왑 활성화
- 미활성이거나 재생성한 경우만 `swapon` → 재실행 시 **changed=0** 보장
---
### 6️⃣ 재부팅 후에도 유지
- `lineinfile`로 `/etc/fstab`에 스왑 라인 등록
- `disable_swap`이 주석 처리한 라인도 활성 라인으로 복원 (자체 멱등)
---
### 7️⃣ 활성화 + 크기 검증
- 활성 스왑 목록에 `swap_file_path`가 있고, 파일 크기가 목표와 일치하는지 `assert`
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Create swap file]
skipping: [192.168.56.200]

TASK [Assert swap is enabled with desired size]
ok: [192.168.56.200] => {
    "msg": "Good!.. | Swap is enabled"
}
```
---
