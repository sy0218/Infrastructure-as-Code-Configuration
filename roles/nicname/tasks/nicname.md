# 🌐 NIC 이름 설정 (Ansible)
- 예측 가능한 NIC 이름(`ens33` 등) 비활성화 → 전통적 이름(`eth0`) 사용
- GRUB 커널 파라미터 `net.ifnames=0 biosdevname=0`로 시스템 전역 적용
- `lineinfile` 자체 멱등성 + **사후 검증(assert)** 흐름
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# GRUB NIC 이름 고정 (eth*)
# =====================================================


# -----------------------------------------------------
# 1. GRUB NIC 파라미터 설정 (lineinfile 자체가 멱등 → 사전 체크 불필요)
# -----------------------------------------------------
- name: "Configure GRUB NIC parameter (fix to eth*)"
  lineinfile:
    path: /etc/default/grub
    regexp: '^GRUB_CMDLINE_LINUX_DEFAULT='
    line: 'GRUB_CMDLINE_LINUX_DEFAULT="net.ifnames=0 biosdevname=0"'
  notify: update-grub # 변경 시에만 grub-mkconfig 실행

# -----------------------------------------------------
# 2. GRUB NIC 설정 검증
# -----------------------------------------------------
- name: "Check applied GRUB NIC parameter"
  command: "grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub"
  register: grub_check
  changed_when: false

- name: "Assert GRUB NIC parameter applied"
  assert:
    that:
      - "'net.ifnames=0' in grub_check.stdout"
      - "'biosdevname=0' in grub_check.stdout"
    success_msg: "Good!.. | NIC name configuration applied: {{ grub_check.stdout }}"
    fail_msg: "ERROR!.. | GRUB NIC parameter NOT applied"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ GRUB NIC 파라미터 설정 (멱등성 핵심)
- `lineinfile`이 목표 라인과 동일하면 아무것도 안 함 → 재실행 시 **changed=0** 보장
- 변경 발생 시에만 `update-grub` handler가 호출되어 `grub-mkconfig` 재생성
---
### 2️⃣ 설정 검증
- `grep`으로 현재 라인 다시 읽어 `assert`
- `net.ifnames=0`, `biosdevname=0` 두 토큰이 모두 포함됐는지 검증
---
<br>

## 🧩 handlers/main.yml
```yaml
# GRUB 설정 적용
- name: update-grub
  command: grub-mkconfig -o /boot/grub/grub.cfg
```
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Configure GRUB NIC parameter (fix to eth*)]
ok: [192.168.56.60]

TASK [Assert GRUB NIC parameter applied]
ok: [192.168.56.60] => {
    "msg": "Good!.. | NIC name configuration applied: GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0 biosdevname=0\""
}
```
> ⚠️ GRUB 변경 시 커널 파라미터는 **다음 부팅부터** 실제 NIC 이름에 반영됨
---
