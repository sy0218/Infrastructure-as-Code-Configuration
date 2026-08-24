# ⚙️ K8s 사전 준비 — 커널 모듈 + sysctl (Ansible)
- K8s 노드에 필요한 커널 모듈(`overlay`, `br_netfilter`)을 로드하고
브리지/포워딩 sysctl 파라미터를 적용한다.
- `br_netfilter` + `bridge-nf-call-iptables`는 **kubeadm preflight가 요구하는 항목**이라 켠다 —
CNI는 Cilium(eBPF)이라 실제 데이터플레인은 iptables를 타지 않는다.
- 스왑은 끄지 않는다 — kubelet `failSwapOn: false` + `LimitedSwap` 구성 전제 (k8s_master 롤 참고).
- 마지막에 모듈 로드 / sysctl 적용 / **cgroup v2** 여부를 검증한다.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# K8s 사전 준비 — 커널 모듈 + sysctl
# -----------------------------------------------------
# overlay: containerd의 overlayfs 스토리지 드라이버용
# br_netfilter: 브리지 트래픽을 iptables가 보도록 함 (kubeadm preflight 요구 항목 —
#               CNI는 Cilium eBPF라 데이터플레인은 iptables를 타지 않는다)
# [주의] 스왑은 끄지 않음 — kubelet failSwapOn: false + LimitedSwap 구성 (k8s_master 롤 참고)
# -----------------------------------------------------

# 1. 부팅 시 커널 모듈 자동 로드 등록 (copy 자체가 멱등)
- name: "Persist kernel modules"
  copy:
    content: |
      overlay
      br_netfilter
    dest: /etc/modules-load.d/k8s.conf
    owner: root
    group: root
    mode: "0644"

# 2. 커널 모듈 즉시 로드 (modprobe 모듈 자체가 멱등 — 이미 로드돼 있으면 changed=0)
#    (community.general 컬렉션 필요 — collection_check 롤이 사전 검증)
- name: "Load kernel modules"
  community.general.modprobe:
    name: "{{ item }}"
    state: present
  loop:
    - overlay
    - br_netfilter

# 3. sysctl 파라미터 영구 등록 + 즉시 적용 (sysctl 모듈 자체가 멱등)
#    (ansible.posix 컬렉션 필요 — collection_check 롤이 사전 검증)
- name: "Set sysctl params for K8s"
  ansible.posix.sysctl:
    name: "{{ item }}"
    value: "1"
    sysctl_file: /etc/sysctl.d/k8s.conf
    sysctl_set: true # /proc/sys 런타임 값도 즉시 반영
    reload: true
  loop:
    - net.bridge.bridge-nf-call-iptables
    - net.bridge.bridge-nf-call-ip6tables
    - net.ipv4.ip_forward

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
# 커널 모듈 로드 확인 (/sys/module 디렉토리 존재 여부)
- name: "Check loaded kernel modules"
  stat:
    path: "/sys/module/{{ item }}"
  register: module_stat
  loop:
    - overlay
    - br_netfilter

- name: "Assert kernel modules loaded"
  assert:
    that:
      - item.stat.exists
    success_msg: "Good!.. | Module loaded: {{ item.item }}"
    fail_msg: "ERROR!.. | Module NOT loaded: {{ item.item }}"
  loop: "{{ module_stat.results }}"
  loop_control:
    label: "{{ item.item }}"

# sysctl 런타임 값 확인
- name: "Check sysctl runtime values"
  command: "sysctl -n {{ item }}"
  register: sysctl_check
  changed_when: false
  loop:
    - net.bridge.bridge-nf-call-iptables
    - net.bridge.bridge-nf-call-ip6tables
    - net.ipv4.ip_forward

- name: "Assert sysctl values applied"
  assert:
    that:
      - item.stdout == "1"
    success_msg: "Good!.. | sysctl applied: {{ item.item }} = 1"
    fail_msg: "ERROR!.. | sysctl NOT applied: {{ item.item }}"
  loop: "{{ sysctl_check.results }}"
  loop_control:
    label: "{{ item.item }}"

# cgroup v2 확인 (스왑 LimitedSwap은 cgroup v2 전제)
- name: "Check cgroup version"
  command: stat -fc %T /sys/fs/cgroup
  register: cgroup_check
  changed_when: false

- name: "Assert cgroup v2 enabled"
  assert:
    that:
      - cgroup_check.stdout == "cgroup2fs"
    success_msg: "Good!.. | cgroup v2 enabled"
    fail_msg: "ERROR!.. | cgroup v2 NOT enabled ({{ cgroup_check.stdout }})"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 커널 모듈 등록 + 즉시 로드 (멱등성 핵심)
- `/etc/modules-load.d/k8s.conf` 배포로 재부팅 후에도 자동 로드 (copy 멱등)
- `modprobe` 모듈로 즉시 로드 — 이미 로드돼 있으면 **changed=0** 보장
- `overlay`는 containerd의 overlayfs 스토리지 드라이버가 쓰므로 런타임 필수
- `br_netfilter`는 **kubeadm preflight 통과용**이다 — CNI를 Cilium(eBPF)으로 바꾼 뒤에도
  빼지 않는 이유가 이것이다. 데이터플레인은 eBPF라 iptables를 타지 않지만,
  모듈이 없으면 2️⃣의 `net.bridge.*` sysctl 키 자체가 존재하지 않아 3️⃣ 검증에서 먼저 깨진다
  (모듈 로드가 sysctl 등록보다 앞서야 하는 순서 의존)
---
### 2️⃣ sysctl 파라미터 적용
- 브리지 iptables 처리 2종 + `ip_forward`를 `/etc/sysctl.d/k8s.conf`에 영구 등록
- `sysctl_set: true`로 런타임 값 즉시 반영 (모듈 자체가 멱등)
- `bridge-nf-call-iptables`는 kubeadm이 preflight에서 값을 확인하는 항목이라 1로 둔다 —
  Cilium은 eBPF로 처리하므로 이 값에 기대지 않는다(끈다고 파드 통신이 살아나지도, 켠다고
  eBPF 경로가 iptables로 바뀌지도 않는다)
- `ip_forward`는 노드가 Pod 트래픽을 포워딩해야 하므로 CNI 종류와 무관하게 필요하다 —
  Cilium은 Native Routing(캡슐화 없음)이라 노드 간 Pod 라우팅이 커널 포워딩 경로를 그대로 쓴다
---
### 3️⃣ 검증
- `/sys/module` 존재로 모듈 로드 확인, `sysctl -n`으로 런타임 값 확인
- `stat -fc %T /sys/fs/cgroup`이 `cgroup2fs`인지 확인 — LimitedSwap 전제 조건
- 하나라도 실패 시 `assert`로 플레이북 중단 — 이 롤이 깨진 채로 containerd·k8s_packages가
  이어지면 원인이 kubeadm init 단계에서야 드러나 진단이 멀어진다
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert cgroup v2 enabled]
ok: [ap] => {
    "msg": "Good!.. | cgroup v2 enabled"
}
```
---
