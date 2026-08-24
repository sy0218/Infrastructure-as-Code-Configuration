# 💥 K8s 클러스터 해체 (Ansible)
- `kubeadm reset`으로 노드를 클러스터에서 제거하고 K8s 구성을 삭제한다.
- **파괴적 작업** — 평소엔 플레이북에서 주석 상태로 두고,
해체할 때만 K8s 롤 전부 주석 처리 + 이 플레이 주석 해제 후 실행한다.
- 패키지(kubeadm/kubelet/kubectl, containerd)와 스왑은 남긴다 — 재구축은 k8s 롤 재실행으로.
- `kubeadm reset`이 손대지 않는 **CNI(Cilium) 잔여물**까지 함께 정리한다 — 상태 디렉토리와 가상 인터페이스.
- kubeadm reset은 iptables 규칙과 BPF 맵을 정리하지 않으므로 **해체 후 노드 재부팅 권장**.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# K8s 클러스터 해체 (kubeadm reset)
# -----------------------------------------------------
# [주의] 파괴적 작업 — 노드를 클러스터에서 제거하고 K8s 구성을 삭제함
#  - kubelet.conf 존재 게이팅(removes)으로 이미 해체된 노드는 스킵
#  - 패키지(kubeadm/kubelet/kubectl, containerd)와 스왑은 남겨둠 — 재구축은 k8s 롤 재실행
#  - kubeadm reset은 iptables 잔여 규칙을 정리하지 않음 → 해체 후 노드 재부팅 권장
# -----------------------------------------------------

# 1. 클러스터 구성 노드만 해체 (비멱등 명령 — removes 게이팅: creates의 반대)
- name: "Reset kubernetes node"
  command:
    cmd: kubeadm reset -f
    removes: /etc/kubernetes/kubelet.conf

# 2. kubelet 중지 — 구성이 사라진 상태의 재시작 반복(crashloop) 방지
#    (enabled는 유지 — 재구축 시 init/join이 다시 시작시킴, systemd 모듈 자체가 멱등)
- name: "Stop kubelet service"
  systemd:
    name: kubelet
    state: stopped

# 3. CNI 설정 정리 — kubeadm reset이 지우지 않는 잔여물 (file 모듈 자체가 멱등)
- name: "Remove CNI config"
  file:
    path: /etc/cni/net.d
    state: absent

# 3-1. Cilium 잔여물 정리 (kubeadm reset이 지우지 않음)
- name: "Remove cilium state"
  file:
    path: /var/lib/cilium
    state: absent

# 3-2. Cilium 가상 인터페이스 삭제 (없으면 rc≠0 → 실패 처리하지 않음)
- name: "Delete cilium interfaces"
  command: "ip link del {{ item }}"
  register: cilium_link_del
  changed_when: cilium_link_del.rc == 0
  failed_when: false
  loop:
    - cilium_host
    - cilium_net
    - cilium_vxlan

# 4. kubectl 계정 홈 디렉토리 조회 (조회 전용 → 상태 변경 없음)
- name: "Get kubectl user home"
  command: "getent passwd {{ kubernetes_admin_user }}"
  register: kube_user_passwd
  changed_when: false

# 5. kubeconfig 정리 — 죽은 클러스터를 가리키는 설정 잔류 방지
#    (마스터에만 존재하지만 file absent는 없어도 changed=0이라 전 노드 공통 실행)
- name: "Remove kubeconfig"
  file:
    path: "{{ kube_user_passwd.stdout.split(':')[5] }}/.kube"
    state: absent

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
- name: "Check kubernetes leftovers"
  stat:
    path: "{{ item }}"
  register: reset_check
  loop:
    - /etc/kubernetes/kubelet.conf
    - /etc/cni/net.d

- name: "Assert node reset complete"
  assert:
    that:
      - not item.stat.exists
    success_msg: "Good!.. | Removed: {{ item.item }}"
    fail_msg: "ERROR!.. | Still exists: {{ item.item }}"
  loop: "{{ reset_check.results }}"
  loop_control:
    label: "{{ item.item }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ kubeadm reset — removes 게이팅 (멱등성 핵심)
- `removes: /etc/kubernetes/kubelet.conf` → 클러스터 구성 노드에서만 실행, 이미 해체된 노드는 **스킵**
- `-f`로 확인 프롬프트 생략
---
### 2️⃣ 잔여물 정리
- kubelet 중지 (구성 없는 상태의 crashloop 방지, enabled는 유지)
- `/etc/cni/net.d`(CNI 설정), kubectl 계정의 `.kube` 삭제 — file 모듈이라 없으면 changed=0
- **Cilium 잔여물** — `kubeadm reset`은 CNI가 만든 것을 지우지 않는다. 상태 디렉토리 `/var/lib/cilium`과
  가상 인터페이스 `cilium_host`/`cilium_net`(터널 모드였다면 `cilium_vxlan`)이 남아, 그대로 두면
  재구축 시 남은 인터페이스와 충돌한다. `ip link del`은 대상이 없으면 `rc≠0`이라
  `failed_when: false` + `changed_when: rc == 0`으로 "있으면 지우고 없으면 조용히 통과"를 만든다.
- **BPF 맵은 이 롤로 지워지지 않는다** — 커널에 남으므로 완전 초기화하려면 재부팅해야 한다.
- 패키지·스왑은 유지 → `k8s_ansible.yml` 재실행만으로 재구축 가능
---
### 3️⃣ 검증
- kubelet.conf / CNI 설정이 삭제됐는지 `stat` + `assert`로 확인
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert node reset complete]
ok: [ap] => (item=/etc/kubernetes/kubelet.conf) => {
    "msg": "Good!.. | Removed: /etc/kubernetes/kubelet.conf"
}
ok: [ap] => (item=/etc/cni/net.d) => {
    "msg": "Good!.. | Removed: /etc/cni/net.d"
}
```
---
