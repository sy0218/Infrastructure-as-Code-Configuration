# 🏷 호스트명 설정 (hostname)
- 서버 초기 세팅 시 **OS 호스트명을 인벤토리 이름(`inventory_hostname` = `ap` / `s1` / `s2`)으로 통일**
- kubeadm 이 OS 호스트명을 **K8s 노드명으로 등록**하므로, Terraform 저장소 `values.common.yaml` 의 노드명과 맞추려면 **`k8s_ansible.yml` 전에** 적용돼야 한다
- 적용 후 `/etc/hosts` 로 그 이름이 **노드 IP(`ansible_host`)로 풀리는지**까지 검증 → `etc_hosts` 롤 **뒤**에 실행
- 참조 변수는 인벤토리 값(`inventory_hostname`·`ansible_host`)뿐 — `group_vars` 에 추가할 값은 없다. 롤은 범용, 인벤토리가 동작 결정
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 호스트명 설정 (인벤토리 이름 기준)
# =====================================================
# kubeadm 은 OS 호스트명을 노드명으로 등록한다 → values.common.yaml 의 ap/s1/s2 와
# 맞추려면 kubeadm init/join 전에 적용돼야 한다 (init 이후 변경은 k8s_reset 후 재구축)


# -----------------------------------------------------
# 1. 호스트명 설정 (hostname 모듈 자체가 멱등)
#    use: systemd → hostnamectl 이 /etc/hostname 영속 + 커널 호스트명 즉시 반영 (재부팅 불필요)
# -----------------------------------------------------
- name: "Set hostname to inventory name"
  hostname:
    name: "{{ inventory_hostname }}"
    use: systemd

# -----------------------------------------------------
# 2. 호스트명 설정 검증 (타겟 서버에서 확인)
#    getent 는 etc_hosts 롤이 쓴 "<ansible_host> <이름>" 줄을 읽는다 → etc_hosts 뒤에 실행
# -----------------------------------------------------
- name: "Check current hostname"
  command: hostname
  register: hostname_check
  changed_when: false

- name: "Check hostname resolves to node IP"
  command: "getent hosts {{ inventory_hostname }}"
  register: hostname_resolve
  changed_when: false
  failed_when: false

- name: "Assert hostname applied"
  assert:
    that:
      - hostname_check.stdout == inventory_hostname
      - ansible_host in hostname_resolve.stdout
    success_msg: "Good!.. | Hostname {{ hostname_check.stdout }} → {{ ansible_host }}"
    fail_msg: "ERROR!.. | Hostname NOT applied (current: {{ hostname_check.stdout }}, resolve: {{ hostname_resolve.stdout }})"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 호스트명 설정 (멱등성 핵심)
- `hostname` 모듈은 현재 이름과 같으면 아무것도 하지 않는다 → 재실행 시 **changed=0**
- `use: systemd` → `hostnamectl` 경로로 **`/etc/hostname` 영속 + 커널 호스트명 즉시 반영**이 한 번에 된다 (재부팅 불필요, `hostnamectl set-hostname` 을 shell 로 치는 비멱등 방식 금지)
- 이름은 인벤토리의 `inventory_hostname` 을 그대로 쓴다 → `host.yml` 의 이름을 바꾸면 이 롤 재실행만으로 노드 이름이 따라간다
- ⚠️ kubeadm init/join 은 **1회성**이라 클러스터 구성 후 호스트명을 바꾸면 노드 등록이 어긋난다 → `k8s_reset` 후 재구축
- VM 은 재부팅해도 유지된다 — `cloud_init` 롤이 cloud-init 을 꺼 두었고, DHCP 예약 이름은 static hostname 보다 우선순위가 낮다
---
### 2️⃣ 호스트명 설정 검증
- `hostname` 명령으로 **커널 호스트명**이 인벤토리 이름과 같은지 확인 (`/etc/hostname` 파일이 아니라 실제 적용 상태를 본다)
- `getent hosts <이름>` 으로 그 이름이 `ansible_host` 로 풀리는지 확인 → `etc_hosts` 롤이 쓴 `"<IP> <이름>"` 줄을 읽는 것이므로 **etc_hosts 뒤에 실행**해야 통과한다
- `getent` 는 이름이 없으면 rc=2 로 끝나므로 `failed_when: false` 로 넘겨 **assert 가 메시지로 알리게** 한다
- `changed_when: false` → 조회 태스크는 변경으로 집계하지 않는다
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [hostname : Assert hostname applied]
ok: [ap] => {
    "msg": "Good!.. | Hostname ap → 192.168.56.38"
}
ok: [s1] => {
    "msg": "Good!.. | Hostname s1 → 192.168.56.39"
}
ok: [s2] => {
    "msg": "Good!.. | Hostname s2 → 192.168.56.40"
}
```
---
