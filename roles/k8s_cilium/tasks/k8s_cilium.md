# 🕸 CNI 설치 — Cilium (k8s_cilium)
- 마스터 노드에서 Helm으로 Cilium을 설치해 클러스터의 Pod 네트워크를 구성합니다 — 이 롤이 끝나야 노드가 `Ready`가 됩니다.
- 데이터플레인은 **eBPF**, 라우팅은 **Native Routing**(캡슐화 없음), Service 처리는 **kube-proxy Replacement**입니다. 즉 kube-proxy를 쓰지 않습니다.
- `kubeadm-config.yaml.j2`의 `skipPhases: [addon/kube-proxy]`와 **한 쌍**입니다 — 한쪽만 바꾸면 클러스터가 동작하지 않습니다.
- 버전·NIC·Hubble 사용 여부는 `group_vars/kubernetes.yml` 변수로 관리 (롤은 범용, 인벤토리가 동작 결정)
---
<br>

## 🧩 main.yml
```yaml
# =========================================================
# CNI: Cilium (eBPF + Native Routing + kube-proxy Replacement)
# =========================================================
# [주의]
#  - kubeadm-config의 skipPhases(addon/kube-proxy)와 한 쌍 — kube-proxy가 없으므로
#    values의 k8sServiceHost/Port를 반드시 지정한다 (누락 시 agent crashloop)
#  - Native Routing은 전 노드가 단일 L2에 있다는 전제 — 다른 서브넷 노드 합류 시 BGP 검토
#  - helm CLI 필요 → 인벤토리 helm 그룹에 마스터가 포함돼야 한다
#  - routingMode/ipam 변경은 helm upgrade로 반영돼도 기존 노드에 라우트·BPF 맵이 남는다
#    → k8s_reset 후 재구축 권장
# =========================================================

# ---------------------------------------------------------
# 1. Cilium helm 저장소 등록
# ---------------------------------------------------------
- name: "Add cilium helm repo"
  kubernetes.core.helm_repository:
    name: cilium
    repo_url: https://helm.cilium.io

# ---------------------------------------------------------
# 2. 저장소 인덱스 갱신
# ---------------------------------------------------------
- name: "Update cilium helm repo"
  command: helm repo update cilium
  changed_when: false

# ---------------------------------------------------------
# 3. values 배포 (template 자체가 멱등)
# ---------------------------------------------------------
- name: "Deploy cilium values"
  template:
    src: cilium-values.yaml.j2
    dest: /root/cilium-values.yaml
    owner: root
    group: root
    mode: "0644"
  register: cilium_values

# ---------------------------------------------------------
# 4. 설치 여부 확인 (rc=0 설치됨, rc≠0 미설치)
# ---------------------------------------------------------
- name: "Check cilium release"
  command: "helm status cilium -n {{ cilium_namespace }}"
  register: cilium_check
  changed_when: false
  failed_when: false
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# ---------------------------------------------------------
# 5. 미설치이거나 values가 바뀐 경우만 설치/갱신
# ---------------------------------------------------------
- name: "Install cilium"
  command: >-
    helm upgrade --install cilium cilium/cilium
    --version {{ cilium_version }}
    --namespace {{ cilium_namespace }}
    --values /root/cilium-values.yaml
    --wait --timeout 10m
  when: cilium_check.rc != 0 or cilium_values.changed
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# ---------------------------------------------------------
# 6. 검증 → CNI 설치 후에 노드가 Ready 가 된다.
# ---------------------------------------------------------
- name: "Wait for master node Ready"
  command: kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers
  register: cilium_node_status
  changed_when: false
  until:
    - cilium_node_status.stdout != ""
    - "'NotReady' not in cilium_node_status.stdout"
  retries: 30 # 최대 5분 대기 (30회 x 10초)
  delay: 10
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# kube-proxy 미설치 확인 (skipPhases 가 실제로 먹었는지 → rc≠0 이 정상)
- name: "Check kube-proxy absent"
  command: kubectl get daemonset kube-proxy -n kube-system
  register: kube_proxy_check
  changed_when: false
  failed_when: false
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 데이터플레인 모드 확인 (KPR / native routing 이 실제로 적용됐는지)
- name: "Check cilium status"
  command: >-
    kubectl -n {{ cilium_namespace }} exec ds/cilium -c cilium-agent --
    cilium-dbg status
  register: cilium_status
  changed_when: false
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

- name: "Assert cilium dataplane configured"
  assert:
    that:
      - "'NotReady' not in cilium_node_status.stdout" # CNI 기동 후 노드 Ready
      - kube_proxy_check.rc != 0 # kube-proxy 미설치 (skipPhases 검증)
      - cilium_status.stdout is search('KubeProxyReplacement:\s+True') # KPR 활성
      - cilium_status.stdout is search('Network:\s+Native') # 캡슐화 없음
    success_msg: "Good!.. | Cilium {{ cilium_version }} ready (native routing, kube-proxy replaced)"
    fail_msg: "ERROR!.. | Cilium not ready, kube-proxy still present or wrong routing mode"
```
---
<br>

## 🧩 templates/cilium-values.yaml.j2
```yaml
# Cilium helm values (k8s_cilium 롤이 배포 — 값은 group_vars/kubernetes.yml 에서 관리)
# eBPF 데이터플레인 + Native Routing + kube-proxy Replacement

# --- kube-proxy 대체 ---
# kube-proxy가 없으면 apiserver를 ClusterIP로 찾을 수 없다 → 주소 직접 지정 필수
kubeProxyReplacement: true
k8sServiceHost: {{ hostvars[groups['kubernetes_master'][0]].ansible_host }}
k8sServicePort: 6443

# --- Native Routing (캡슐화 없음) ---
# 전 노드가 단일 L2(192.168.56.0/24)라 Pod CIDR을 노드 IP로 직접 라우팅 가능
# → VXLAN 캡슐화 비용 제거, Pod MTU 1500 온전히 사용
routingMode: native
ipv4NativeRoutingCIDR: {{ pod_subnet }}
autoDirectNodeRoutes: true # 노드 추가/삭제 시 라우트 자동 관리 (BGP 불필요)

# --- BPF 마스커레이딩 (iptables masquerade 대신) ---
bpf:
  masquerade: true

# --- BPF 프로그램 부착 NIC 고정 ---
# VirtualBox NAT NIC(eth0, 전 노드 동일 IP 10.0.2.15) 오인 방지
devices: {{ cilium_device }}

# --- IPAM: kubeadm이 노드별로 할당한 podCIDR 사용 ---
ipam:
  mode: kubernetes

# --- 리소스 (2 vCPU 노드 기준) ---
operator:
  replicas: 1

# --- 관측성 ---
hubble:
  enabled: {{ cilium_hubble_enabled | lower }}
  relay:
    enabled: {{ cilium_hubble_enabled | lower }}
  ui:
    enabled: {{ cilium_hubble_ui_enabled | lower }}
```
---
<br>

## 📌 group_vars 예시
```yaml
# group_vars/kubernetes.yml
pod_subnet: "10.244.0.0/16"    # kubeadm podSubnet 과 동일해야 함 (ipv4NativeRoutingCIDR 로 사용)

cilium_version: "1.20.1"       # Cilium Helm Chart 버전
cilium_namespace: "kube-system"
cilium_device: "eth1"          # BPF 부착 NIC → host-only 고정 (NAT NIC eth0는 전 노드가 10.0.2.15로 동일)
cilium_hubble_enabled: true    # 네트워크 관측성 (끄면 hubble-relay 미기동)
cilium_hubble_ui_enabled: true # Hubble UI (웹 대시보드) → hubble_enabled 가 true 여야 동작

required_collections:
  - kubernetes.core            # helm_repository 모듈 (k8s_cilium)
```
---
<br>

## 🛠 작업 내용
### 1️⃣ Helm 저장소 등록
- `kubernetes.core.helm_repository` 모듈은 저장소가 이미 있으면 `changed=0`이라 별도 가드가 필요 없다.
- 이 모듈 때문에 `required_collections`에 `kubernetes.core`가 들어간다 — `collection_check` 롤이 플레이북 첫 단계에서 미설치를 잡아준다.
---
<br>

### 2️⃣ 저장소 인덱스 갱신
- `helm repo update`는 로컬 캐시만 갱신하는 조회성 작업이라 `changed_when: false`로 고정한다. 이걸 빼면 매 실행마다 `changed`로 잡혀 멱등성 판단이 흐려진다.
---
<br>

### 3️⃣ values 배포
- `template` 모듈은 내용이 같으면 `changed=0`이므로 그 자체가 멱등 가드 역할을 한다.
- `register: cilium_values`로 변경 여부를 잡아 5️⃣의 재설치 조건으로 쓴다 — **값을 바꿨을 때만** helm이 다시 돌게 하는 장치다.
- `k8sServiceHost`는 `hostvars[groups['kubernetes_master'][0]].ansible_host`로 인벤토리에서 끌어온다. kube-proxy가 없어 apiserver를 ClusterIP(`10.96.0.1`)로 찾을 수 없기 때문에 **이 값이 비면 cilium-agent가 crashloop에 빠진다.**
- `devices: eth1`은 VirtualBox NAT NIC(`eth0`, 전 노드가 동일하게 `10.0.2.15`)를 잡는 사고를 막는 장치다. kubelet `--node-ip` 고정과 같은 목적이다.
- **Hubble UI는 relay에 의존한다** — `cilium_hubble_ui_enabled: true` 인데 `cilium_hubble_enabled: false` 면
  차트 검증(`validate.yaml`)에 걸려 `helm` 설치가 **실패**한다:
  `Hubble UI requires .Values.hubble.relay.enabled=true`. UI를 켜둘 거면 `cilium_hubble_enabled` 도 반드시 `true` 여야 한다.
---
<br>

### 4️⃣ 설치 여부 확인
- `helm status`는 릴리스가 없으면 `rc≠0`이다. `failed_when: false`로 실패를 흡수하고 `rc` 값만 5️⃣의 게이팅에 쓴다.
- `kubectl`/`helm`은 계정과 무관하게 `KUBECONFIG=/etc/kubernetes/admin.conf`로 실행한다 (`kubernetes_admin_user` 홈의 kubeconfig와 별개).
---
<br>

### 5️⃣ 설치 / 갱신
- `helm upgrade --install`은 없으면 설치, 있으면 갱신이라 명령 자체는 안전하지만 **항상 `changed`로 보고**된다. 그래서 `when: cilium_check.rc != 0 or cilium_values.changed`로 실제 필요한 때만 실행한다.
- `--wait`를 붙이는 이유: CNI DaemonSet이 떠야 노드가 `Ready`가 되고, 그 다음 워커 조인(k8s_worker)이 의미를 갖기 때문이다.
- `routingMode`·`ipam` 같은 근본 설정은 helm upgrade로 반영되더라도 **기존 노드에 라우트와 BPF 맵이 남는다** → `k8s_reset` 후 재구축을 권장한다.
---
<br>

### 6️⃣ 검증
- **노드 Ready 대기** — CNI 설치 전에는 `NotReady`가 정상이므로, Ready 검증은 k8s_master가 아니라 이 롤의 책임이다. Cilium 기동에 수 분이 걸릴 수 있어 `until` + `retries`로 대기한다.
- **kube-proxy 미설치 확인** — `kubeadm-config`의 `skipPhases`가 실제로 먹었는지 확인한다. 여기서는 `rc≠0`(DaemonSet 없음)이 **정상**이다. kube-proxy가 남아 있으면 Cilium의 KPR과 규칙이 충돌한다.
- **데이터플레인 모드 확인** — `cilium-dbg status` 출력에서 `KubeProxyReplacement: True`와 `Network: Native`를 정규식으로 확인한다. values가 잘못 렌더링돼 조용히 터널 모드로 떨어지는 상황을 여기서 잡는다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [k8s_cilium : Assert cilium dataplane configured] *************************
ok: [ap] => {
    "changed": false,
    "msg": "Good!.. | Cilium 1.20.1 ready (native routing, kube-proxy replaced)"
}
```
---
<br>

## 🔍 설치 후 확인
```bash
# 데이터플레인 모드 (KPR / Native 여야 정상)
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status \
  | grep -E "KubeProxyReplacement|Routing|Masquerading"

# kube-proxy 미설치 확인 (NotFound 가 정상)
kubectl -n kube-system get daemonset kube-proxy

# Native Routing 증명 — 상대 노드 Pod CIDR이 eth1로 직행, cilium_vxlan 없음
ip route | grep 10.244
ip -br link | grep -E "cilium|vxlan"

# Hubble — 흐름 조회 / UI 접속
kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe --last 20
kubectl -n kube-system port-forward svc/hubble-ui 12000:80 --address 0.0.0.0
#   → http://192.168.56.200:12000
```
