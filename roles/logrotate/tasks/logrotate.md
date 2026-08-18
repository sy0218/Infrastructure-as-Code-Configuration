# 🗂 logrotate 기본 설정
- 시스템 로그 파일의 회전 주기 및 보관 정책을 설정한다.
- 로그 파일 무한 증가로 인한 디스크 고갈을 방지하기 위한 설정이다.
- 설정 항목은 `host.yml`의 `logrotate_options` 변수로 관리 (롤은 범용, 인벤토리가 동작 결정)
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# logrotate 기본 설정
# =====================================================


# -----------------------------------------------------
# 1. logrotate.conf 설정 적용 (lineinfile 자체가 멱등 → 항목은 host.yml의 logrotate_options로 관리)
# -----------------------------------------------------
- name: "Apply logrotate configuration"
  lineinfile:
    path: /etc/logrotate.conf
    regexp: "{{ item.regexp }}"
    line: "{{ item.line }}"
    state: present
  loop: "{{ logrotate_options }}"

# -----------------------------------------------------
# 2. logrotate 설정 검증 (타겟 서버 파일 확인)
# -----------------------------------------------------
- name: "Check logrotate configuration"
  command: "grep -Fx '{{ item.line }}' /etc/logrotate.conf"
  loop: "{{ logrotate_options }}"
  register: logrotate_check
  changed_when: false
  failed_when: false

- name: "Assert logrotate configuration is correctly set"
  assert:
    that:
      - item.rc == 0
    success_msg: "Good!.. | logrotate setting applied: {{ item.item.line }}"
    fail_msg: "ERROR!.. | logrotate setting missing: {{ item.item.line }}"
  loop: "{{ logrotate_check.results }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ logrotate.conf 설정 적용 (멱등성 핵심)
- `host.yml`의 `logrotate_options` 리스트를 `lineinfile`로 loop 적용 — 자체 멱등, 재실행 시 **changed=0** 보장
- 항목 추가/변경은 롤 수정 없이 인벤토리에서만

예시:
```yaml
# host.yml
logrotate_options:
  - { regexp: '^(daily|weekly|monthly|yearly)$', line: 'weekly' } # 회전 주기
  - { regexp: '^rotate\s+\d+', line: 'rotate 4' } # 보관 개수
  - { regexp: '^create$', line: 'create' } # 회전 후 새 파일 생성
  - { regexp: '^su\s+', line: 'su root adm' } # 실행 사용자/그룹
  - { regexp: '^include\s+/etc/logrotate.d', line: 'include /etc/logrotate.d' } # 개별 설정 포함
```
---
### 2️⃣ 설정 검증
- 타겟 서버에서 `grep -Fx`(라인 전체 일치)로 항목별 확인 후 `assert` — 누락 항목 식별 가능
- ⚠️ `lookup('file', ...)`은 컨트롤 노드 파일을 읽으므로 검증에 사용 금지
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert logrotate configuration is correctly set]
ok: [192.168.56.60] => (item=...) => {
    "msg": "Good!.. | logrotate setting applied: weekly"
}
```
---
