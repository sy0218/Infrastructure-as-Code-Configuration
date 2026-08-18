# 🐚 시스템 기본 Shell 변경 (dash → bash)

- 시스템 기본 `/bin/sh`를 dash가 아닌 bash로 변경한다.
- dash로 인한 스크립트 호환성 문제를 방지하기 위한 설정이다.
- ⚠️ Ubuntu 24.04(dash 0.5.12+)부터 debconf `dash/sh` + `dpkg-reconfigure` 방식은
  `/bin/sh` 링크를 제어하지 못함 → **심볼릭 링크 직접 관리**로 전환

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 시스템 기본 shell 변경 (dash → bash)
# =====================================================


# -----------------------------------------------------
# 1. /bin/sh 를 bash 로 연결 (file: link 자체가 멱등 → 이미 bash면 changed=0)
# -----------------------------------------------------
- name: "Point /bin/sh to bash"
  file:
    src: /usr/bin/bash
    dest: /bin/sh
    state: link
    follow: false # 기존 링크(dash)를 따라가지 않고 링크 자체를 교체

# -----------------------------------------------------
# 2. 시스템 기본 shell 변경 검증 (타겟 서버에서 확인)
# -----------------------------------------------------
- name: "Check default /bin/sh target"
  command: readlink -f /bin/sh
  register: sh_check
  changed_when: false

- name: "Assert default /bin/sh points to bash"
  assert:
    that:
      - sh_check.stdout == '/usr/bin/bash'
    success_msg: "Good!.. | Default shell (/bin/sh) is set to bash"
    fail_msg: "ERROR!.. | Default shell (/bin/sh) is NOT bash (current: {{ sh_check.stdout }})"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ /bin/sh 심볼릭 링크 교체 (멱등성 핵심)
- `file: state=link`로 `/bin/sh → /usr/bin/bash` 직접 관리 — 이미 bash면 재실행 시 **changed=0** 보장
- `follow: false` 필수: 기존 링크(dash)를 따라가지 않고 링크 자체를 교체
- dash 패키지가 업그레이드되면 링크가 dash로 복원될 수 있음 (플레이북 재실행으로 복구)
---
### 2️⃣ 기본 shell 검증
- 타겟 서버에서 `readlink -f /bin/sh` 실행 결과가 `/usr/bin/bash`인지 `assert`
- ⚠️ `lookup('pipe', ...)`은 컨트롤 노드에서 실행되므로 검증에 사용 금지
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert default /bin/sh points to bash]
ok: [192.168.56.60] => {
    "msg": "Good!.. | Default shell (/bin/sh) is set to bash"
}
```
---
