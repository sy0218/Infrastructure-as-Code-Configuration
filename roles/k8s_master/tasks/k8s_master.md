# 🎛 K8s 컨트롤플레인 초기화 (K8s Master)
- `kubeadm init`으로 마스터 노드(ap)의 컨트롤플레인을 부트스트랩하고, kubectl 계정에 kubeconfig(`~/.kube/config`)를 배포합니다.
- **CNI는 이 롤이 설치하지 않습니다** — Cilium 설치는 `k8s_cilium` 롤 담당이라, 이 롤이 끝난 시점의 노드는 **NotReady 가 정상**입니다(Ready 검증도 Cilium 롤이 합니다).
- **kube-proxy도 설치하지 않습니다** — `kubeadm-config.yaml.j2` 의 `skipPhases: [addon/kube-proxy]` 와 Cilium의 kube-proxy replacement 가 한 쌍입니다.
- **스왑을 끄지 않는 구성**: `failSwapOn: false` + `swapBehavior`(`kubernetes_swap_behavior`)를 KubeletConfiguration으로 적용 — 클러스터 ConfigMap(kubelet-config)으로 저장되어 join하는 워커에도 자동 적용됩니다.
- 버전·Pod CIDR·스왑 정책·kubectl 계정은 `group_vars/kubernetes.yml` 변수로 관리 (롤은 범용, 인벤토리가 동작 결정)
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# K8s 컨트롤플레인 초기화 (마스터 노드)
# -----------------------------------------------------
# [주의] kubeadm init은 1회성 부트스트랩 — creates 게이팅으로 재실행 시 스킵
#  - init 이후 pod_subnet/kubernetes_swap_behavior/skipPhases 등 변경은 재실행으로
#    반영되지 않음 → k8s_reset 후 재구축 필요
#  - init이 중간에 실패한 노드는 kubeadm reset -f 후 재실행
#  - kubectl 계정은 인벤토리 kubernetes_admin_user로 관리 (.kube/config 배포 대상)
#    롤 내부 kubectl 태스크는 계정과 무관하게 KUBECONFIG=admin.conf로 실행
#  - CNI는 이 롤이 설치하지 않는다 → k8s_cilium 롤 담당 (그래서 여기선 노드가 NotReady)
# -----------------------------------------------------

# 1. kubeadm init 설정 배포 (template 자체가 멱등)
- name: "Deploy kubeadm init config"
  template:
    src: kubeadm-config.yaml.j2
    dest: /root/kubeadm-config.yaml
    owner: root
    group: root
    mode: "0600"

# 2. 컨트롤플레인 초기화 (비멱등 명령 — creates 게이팅: 이미 init된 노드는 스킵)
#    (--ignore-preflight-errors=Swap: 사전 검사 통과용 — 실제 스왑 동작은
#     kubeadm-config의 KubeletConfiguration(failSwapOn/swapBehavior)이 담당)
- name: "Initialize control plane"
  command:
    cmd: kubeadm init --config /root/kubeadm-config.yaml --ignore-preflight-errors=Swap
    creates: /etc/kubernetes/admin.conf

# 3. kubectl 계정 홈 디렉토리 조회 (조회 전용 → 상태 변경 없음, 계정 없으면 즉시 실패)
- name: "Get kubectl user home"
  command: "getent passwd {{ kubernetes_admin_user }}"
  register: kube_user_passwd
  changed_when: false

# 4. 홈 디렉토리 변수화 (passwd 6번째 필드 = 홈 디렉토리)
- name: "Set kubeconfig home"
  set_fact:
    kube_user_home: "{{ kube_user_passwd.stdout.split(':')[5] }}"

# 5. kubectl 계정용 .kube 디렉토리 생성 (file 모듈 자체가 멱등)
- name: "Create .kube directory"
  file:
    path: "{{ kube_user_home }}/.kube"
    state: directory
    owner: "{{ kubernetes_admin_user }}"
    group: "{{ kubernetes_admin_user }}"
    mode: "0700"

# 6. kubectl 계정용 kubeconfig 복사 (copy 자체가 멱등)
- name: "Copy admin.conf to user kubeconfig"
  copy:
    src: /etc/kubernetes/admin.conf
    dest: "{{ kube_user_home }}/.kube/config"
    remote_src: true
    owner: "{{ kubernetes_admin_user }}"
    group: "{{ kubernetes_admin_user }}"
    mode: "0600"


# -----------------------------------------------------
# 7. 검증
#      - CNI 미설치 상태라 노드는 NotReady 가 정상
#      - Ready 검증은 Cilium 롤이 담당
# -----------------------------------------------------
# 마스터 노드가 API에 등록됐는지 대기
- name: "Wait for master node registered"
  command: kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers
  register: master_node_status
  changed_when: false
  until: master_node_status.stdout != ""
  retries: 18 # 최대 3분 대기 (18회 x 10초)
  delay: 10
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 마스터 노드 INTERNAL-IP 확인
- name: "Check master node internal IP"
  command: >-
    kubectl get nodes -l node-role.kubernetes.io/control-plane -o
    'jsonpath={.items[0].status.addresses[?(@.type=="InternalIP")].address}'
  register: master_internal_ip
  changed_when: false
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 스왑 활성 유지 확인 (LimitedSwap 구성 전제)
- name: "Check active swap"
  command: swapon --noheadings --show=NAME
  register: master_swap_check
  changed_when: false

- name: "Assert control plane bootstrapped with swap on"
  assert:
    that:
      - master_internal_ip.stdout == ansible_host # host-only IP 사용 확인 (조건문 안에서는 {{ }} 금지)
      - swap_file_path in master_swap_check.stdout_lines # 스왑 활성 유지 확인
    success_msg: "Good!.. | Control plane bootstrapped ({{ master_internal_ip.stdout }}, swap on) → CNI 미설치라 NotReady 정상"
    fail_msg: "ERROR!.. | Wrong node IP or swap off"
```
---
<br>

## 🧩 templates/kubeadm-config.yaml.j2
```yaml
# kubeadm init 설정 (k8s_master 롤이 배포 — 값은 인벤토리 host.yml에서 관리)
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: {{ ansible_host }}
nodeRegistration:
  taints: []          # control-plane NoSchedule taint 미적용 (ap도 워크로드 스케줄링 → 필요 시 삭제)
skipPhases:
  - addon/kube-proxy # kube-proxy 미설치 — Cilium kube-proxy replacement가 대체 (k8s_cilium 롤과 한 쌍)
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v{{ kubernetes_package_version.split('-')[0] }}
networking:
  podSubnet: {{ pod_subnet }}
---
# 스왑 켠 채 kubelet 기동 허용 + 스왑 사용 정책
# (클러스터 전역 ConfigMap(kubelet-config)으로 저장되어 join하는 워커에도 자동 적용)
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
failSwapOn: false
memorySwap:
  swapBehavior: {{ kubernetes_swap_behavior }}
```
- `advertiseAddress: {{ ansible_host }}` — API 서버를 host-only IP(192.168.56.x)로 광고. 모든 플레이가 `gather_facts: false` 라 facts 대신 인벤토리 값을 쓴다.
- `skipPhases: [addon/kube-proxy]` — kube-proxy addon 자체를 만들지 않는다. Service 처리는 Cilium eBPF(kube-proxy replacement)가 대신한다.
- `kubernetesVersion` — `kubernetes_package_version`(예: `1.34.4-1.1`)에서 `-` 앞을 잘라 `v1.34.4` 로 만든다. 패키지 핀 버전과 컨트롤플레인 이미지 태그가 어긋나지 않게 하기 위함.
- `podSubnet: {{ pod_subnet }}` — Cilium values의 IPAM CIDR과 같은 값이어야 한다.
---
<br>

## 📌 group_vars 예시
```yaml
# group_vars/kubernetes.yml
kubernetes_package_version: "1.34.4-1.1"      # kubernetes 패키지 버전 (kubeadm-config의 kubernetesVersion 원본)

# =======================================
# K8s 클러스터 구성 (k8s_master 사용)
# → init 이후 변경해도 재실행으로 반영되지 않음 (k8s_reset 후 재구축 필요)
# =======================================
pod_subnet: "10.244.0.0/16"   # 노드망(192.168.56.x)과 겹치면 안 됨
kubernetes_swap_behavior: "LimitedSwap"
kubernetes_admin_user: "root" # 마스터에서 kubectl 사용할 계정 (.kube/config 배포 대상)
```
```yaml
# group_vars/server_configuration.yml — 스왑 검증에만 참조 (enable_swap 롤이 만든 경로)
swap_file_path: /swap.img
```
- 노드 IP(`ansible_host`)는 인벤토리 `host.yml` 값이다 — `gather_facts: false` 라 facts로는 얻을 수 없다.
---
<br>

## 🛠 작업 내용
### 1️⃣ kubeadm init 설정 배포
- 플래그를 길게 나열하는 대신 `--config` 파일 하나로 선언적으로 관리한다 — `template` 모듈 자체가 멱등이라 값이 그대로면 changed가 나지 않는다.
- 파일에 클러스터 부트스트랩 정보가 들어가므로 `mode: "0600"` (root 전용).
- ⚠ **이 파일이 바뀌어도 2️⃣가 다시 돌지는 않는다** — 파일만 갱신되고 클러스터는 옛 설정 그대로다. `pod_subnet`·`kubernetes_swap_behavior`·`skipPhases` 를 바꿨다면 `k8s_reset` 후 재구축해야 반영된다.
---
### 2️⃣ 컨트롤플레인 초기화 (멱등성 핵심)
- `kubeadm init` 은 **1회성 비멱등 명령**이다. 그래서 `creates: /etc/kubernetes/admin.conf` 로 게이팅해 이미 init된 노드에서는 명령 자체를 실행하지 않는다 — 재실행 시 **changed=0**.
- 이 가드가 곧 "설정 변경은 재실행으로 반영되지 않는다"의 이유다. 되돌리려면 클러스터 해체(`k8s_reset`)가 유일한 경로다.
- init이 중간에 실패해 `admin.conf` 만 남으면 다음 실행이 조용히 스킵되어 반쪽 클러스터가 된다 — 그 노드는 `kubeadm reset -f` 로 지운 뒤 재실행한다.
- `--ignore-preflight-errors=Swap` 은 **사전 검사만 통과**시키는 플래그다. 실제로 스왑을 켠 채 kubelet이 뜨는 건 kubeadm-config의 `failSwapOn: false` + `swapBehavior: LimitedSwap` 이 담당한다. 이 저장소는 `enable_swap` 롤이 활성, `disable_swap` 롤이 비활성인 것이 의도된 구성이라 두 축이 모두 필요하다.
- **kube-proxy 는 여기서 설치되지 않는다**(`skipPhases`). 따라서 이 롤만 돌린 상태의 클러스터는 Service VIP 를 처리할 주체가 없다 — `k8s_cilium` 롤이 kube-proxy replacement 로 그 자리를 메울 때까지는 미완성 상태로 보는 것이 맞다. 플레이북에서 두 롤이 같은 플레이에 연달아 등록된 이유다.
---
### 3️⃣ kubectl 계정 kubeconfig 배포
- 홈 디렉토리를 하드코딩하지 않고 `getent passwd` 로 조회한다 — 계정이 없으면 여기서 즉시 실패해 원인이 드러난다(조회 전용이라 `changed_when: false`).
- passwd 6번째 필드가 홈 디렉토리라 `split(':')[5]` 로 뽑아 `set_fact` 한다.
- `.kube` 디렉토리(`file`)와 `admin.conf` 복사(`copy`, `remote_src`)는 모듈 자체가 멱등이다. 관리자 자격증명 파일이므로 `0700`/`0600` + 계정 소유로 배포한다.
- 롤 내부의 kubectl 태스크들은 이 사본을 쓰지 않고 `KUBECONFIG=/etc/kubernetes/admin.conf` 를 직접 지정한다 — `kubernetes_admin_user` 를 무엇으로 바꾸든 검증 동작이 흔들리지 않게 하기 위함이다.
---
### 4️⃣ 검증 — "등록"까지만 확인한다
- **Ready 를 기다리지 않는다.** CNI가 없으면 kubelet이 `NetworkPluginNotReady` 로 NotReady를 유지하는 것이 정상이므로, 여기서 Ready를 기다리면 반드시 타임아웃한다. 노드가 API 서버에 **등록**됐는지까지만 확인하고, Ready 검증은 `k8s_cilium` 롤에 넘긴다.
- 라벨 셀렉터에 매칭되는 노드가 없으면 `kubectl get` 은 rc=0 에 빈 stdout을 낸다 — 그래서 rc가 아니라 `stdout != ""` 를 `until` 조건으로 쓴다. 대기는 18회 × 10초(최대 3분)로, kubelet 기동 + 노드 등록까지만 커버하면 되므로 Ready 대기(30회)보다 짧다.
- `control-plane` 라벨로 조회하는 이유는 워커 상태와 무관하게 마스터만 검증하기 위해서다(이 시점엔 워커가 아직 join 전이다).
- **INTERNAL-IP == `ansible_host` 검증은 VirtualBox NAT IP 오인 사고를 잡는 가드다.** VM의 첫 NIC은 NAT(모든 노드가 동일한 `10.0.2.15`)이라 노드 IP가 그쪽으로 잡히면 노드 3대가 같은 주소를 광고하게 되어 통신이 조용히 깨진다. `k8s_packages` 롤의 kubelet `--node-ip` 고정과 이 롤의 `advertiseAddress` 가 host-only IP로 걸려 있는지를 결과값으로 되짚는 것이다.
- `swapon --show` 로 `swap_file_path` 가 여전히 활성인지 확인한다 — LimitedSwap 구성의 전제라, 누군가 `disable_swap` 롤을 켜거나 수동으로 swapoff 했다면 여기서 잡힌다.
- assert 조건 안에서는 `{{ }}` 를 쓰지 않는다(하우스 규칙). 성공 메시지에 "CNI 미설치라 NotReady 정상" 을 남겨, 이 시점의 NotReady를 장애로 오인하지 않게 한다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert control plane bootstrapped with swap on]
ok: [ap] => {
    "msg": "Good!.. | Control plane bootstrapped (192.168.56.200, swap on) → CNI 미설치라 NotReady 정상"
}
```
