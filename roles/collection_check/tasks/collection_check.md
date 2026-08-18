# 📦 필수 Ansible 컬렉션 사전 검증 (Ansible)
- k8s 롤이 사용하는 컬렉션(`ansible.posix`, `community.general` 등)이
컨트롤 노드에 설치돼 있는지 플레이북 시작 전에 검증한다.
- 컬렉션이 없으면 이후 플레이가 무의미하므로 조기 중단시키기 위함이다.
- 검증 대상 목록은 인벤토리 변수 `required_collections`로 관리한다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 필수 Ansible 컬렉션 사전 검증 (컨트롤 노드)
# =====================================================
# k8s 롤이 사용하는 컬렉션(required_collections)이 컨트롤 노드에
# 없으면 이후 플레이가 무의미하므로 시작 전에 조기 중단시킴
# =====================================================

# -----------------------------------------------------
# 1. 설치된 컬렉션 목록 조회 (조회 전용 → 상태 변경 없음)
# -----------------------------------------------------
- name: "List installed collections"
  command: ansible-galaxy collection list
  register: collection_list
  changed_when: false

# -----------------------------------------------------
# 2. 검증
# -----------------------------------------------------
- name: "Assert required collections are installed"
  assert:
    that:
      - item in collection_list.stdout # 목록 출력에 컬렉션 이름 포함 여부 (조건문 안에서는 {{ }} 금지)
    success_msg: "Good!.. | Collection installed: {{ item }}"
    fail_msg: "ERROR!.. | Missing collection: {{ item }} -> run: ansible-galaxy collection install {{ item }}"
  loop: "{{ required_collections }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 설치된 컬렉션 목록 조회
- `ansible-galaxy collection list`로 컨트롤 노드의 컬렉션 목록 수집
- 조회 전용 명령이므로 `changed_when: false` → 재실행 시 **changed=0** 보장
---
### 2️⃣ 필수 컬렉션 존재 검증
- `required_collections` 목록을 loop 돌며 출력에 포함됐는지 `assert`로 검증
- 누락 시 설치 명령(`ansible-galaxy collection install <이름>`)을 안내하며 플레이북 중단
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert required collections are installed]
ok: [ap] => (item=ansible.posix) => {
    "msg": "Good!.. | Collection installed: ansible.posix"
}
ok: [ap] => (item=community.general) => {
    "msg": "Good!.. | Collection installed: community.general"
}
```
---
