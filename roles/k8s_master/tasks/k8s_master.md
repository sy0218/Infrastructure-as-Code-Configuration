# 🎛 K8s 컨트롤플레인 초기화 + Calico 설치 (Ansible)
- kubeadm init으로 컨트롤플레인을 초기화하고 Calico(Tigera Operator)를 설치한다.
- **스왑을 끄지 않는 구성**: `failSwapOn: false` + `swapBehavior`(인벤토리 `kubernetes_swap_behavior`)를
KubeletConfiguration으로 적용 — 클러스터 ConfigMap으로 저장되어 join하는 워커에도 자동 적용된다.
- kubeadm init은 **1회성 부트스트랩** — `creates` 게이팅으로 재실행 시 스킵.
init 이후 `pod_subnet` 등 변수 변경은 재실행으로 반영되지 않는다 (k8s_reset 후 재구축 필요).
- kubectl 사용 계정은 인벤토리 `kubernetes_admin_user`로 관리한다.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# K8s 컨트롤플레인 초기화 + Calico 설치 (마스터 노드)
# -----------------------------------------------------
# [주의] kubeadm init은 1회성 부트스트랩 — creates 게이팅으로 재실행 시 스킵
#  - init 이후 pod_subnet/kubernetes_swap_behavior 등 변경은 재실행으로
#    반영되지 않음 → k8s_reset 후 재구축 필요
#  - init이 중간에 실패한 노드는 kubeadm reset -f 후 재실행
#  - kubectl 계정은 인벤토리 kubernetes_admin_user로 관리 (.kube/config 배포 대상)
#    롤 내부 kubectl 태스크는 계정과 무관하게 KUBECONFIG=admin.conf로 실행
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

# 7. Tigera Operator 매니페스트 다운로드
#    (파일명에 버전 포함 — calico_version 변경 시 새로 받고, 같으면 스킵되어 멱등)
- name: "Download tigera operator manifest"
  get_url:
    url: "https://raw.githubusercontent.com/projectcalico/calico/v{{ calico_version }}/manifests/tigera-operator.yaml"
    dest: "/root/tigera-operator-v{{ calico_version }}.yaml"
    mode: "0644"
  register: tigera_manifest

# 8. Operator 설치 여부 확인 (rc=0 설치됨, rc=1 미설치)
#    (kubectl diff는 대상 네임스페이스가 아직 없으면 rc=2 에러라 첫 설치 게이팅에 못 씀
#     → 존재 확인으로 게이팅, 버전 변경은 7번 매니페스트 다운로드 changed로 감지)
- name: "Check tigera operator deployment"
  command: kubectl get deployment tigera-operator -n tigera-operator
  register: tigera_check
  changed_when: false
  failed_when: tigera_check.rc not in [0, 1]
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 9. 미설치이거나 버전이 변경된 경우만 Operator 적용 — server-side apply 필수
#    (create는 재실행 시 실패, client-side apply는 CRD가 커서 annotation 한도 초과)
- name: "Apply tigera operator"
  command: "kubectl apply --server-side -f /root/tigera-operator-v{{ calico_version }}.yaml"
  when: tigera_check.rc == 1 or tigera_manifest.changed
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 10. Installation/APIServer CRD 등록 대기
#     (operator 적용 직후엔 CRD 오브젝트 자체가 API 서버에 아직 안 보일 수 있음
#      → kubectl wait는 대상이 없으면 대기 없이 즉시 NotFound라 until로 재시도)
- name: "Wait for tigera CRDs established"
  command: >-
    kubectl wait --for condition=established --timeout=60s
    crd/installations.operator.tigera.io crd/apiservers.operator.tigera.io
  register: tigera_crd_wait
  changed_when: false
  until: tigera_crd_wait.rc == 0
  retries: 3
  delay: 10
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 11. Calico Installation CR 배포 (template 자체가 멱등)
- name: "Deploy calico installation manifest"
  template:
    src: calico-install.yaml.j2
    dest: /root/calico-install.yaml
    owner: root
    group: root
    mode: "0644"

# 12. Installation 적용 여부 확인 (rc=0 적용됨, rc=1 미적용)
#     (적용 후에는 operator가 spec 기본값을 채우며 필드 소유권을 가져가
#      server-side diff가 Conflict(rc=2)를 내므로 8번과 동일한 존재 확인 게이팅
#      — 설정 변경 반영은 어차피 재구축 영역: 상단 [주의] 참고)
- name: "Check calico installation"
  command: kubectl get installation.operator.tigera.io default
  register: calico_check
  changed_when: false
  failed_when: calico_check.rc not in [0, 1]
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 13. 미적용인 경우만 Installation 적용
- name: "Apply calico installation"
  command: kubectl apply --server-side -f /root/calico-install.yaml
  when: calico_check.rc == 1
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# -----------------------------------------------------
# 검증 — Calico 기동까지 수 분 걸릴 수 있어 재시도 대기
# -----------------------------------------------------
# 마스터 노드 Ready 대기 (control-plane 라벨로 조회 — 워커 상태와 무관하게 검증)
- name: "Wait for master node Ready"
  command: kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers
  register: master_node_status
  changed_when: false
  until:
    - master_node_status.stdout != ""
    - "'NotReady' not in master_node_status.stdout"
  retries: 30 # 최대 5분 대기 (30회 x 10초)
  delay: 10
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf

# 마스터 노드 INTERNAL-IP 확인 (NAT IP(10.0.2.15) 오인 사고 검출)
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

- name: "Assert control plane ready with swap on"
  assert:
    that:
      - "'NotReady' not in master_node_status.stdout" # 마스터 Ready 재확인
      - master_internal_ip.stdout == ansible_host # host-only IP 사용 확인 (조건문 안에서는 {{ }} 금지)
      - swap_file_path in master_swap_check.stdout_lines # 스왑 활성 유지 확인
    success_msg: "Good!.. | Control plane Ready ({{ master_internal_ip.stdout }}, swap on)"
    fail_msg: "ERROR!.. | Control plane NOT ready, wrong node IP or swap off"
```
---
<br>

## 🧩 templates
### kubeadm-config.yaml.j2
- `advertiseAddress: {{ ansible_host }}` — host-only IP로 API 서버 광고
- `kubernetesVersion` — `kubernetes_package_version`에서 추출 (버전 고정 일관성)
- `podSubnet: {{ pod_subnet }}` + KubeletConfiguration(failSwapOn/swapBehavior)

### calico-install.yaml.j2
- `linuxDataplane: Iptables` 명시, `cidr: {{ pod_subnet }}` (podSubnet과 일치)
- `nodeAddressAutodetectionV4.cidrs: [{{ node_cidr }}]` — host-only NIC 자동감지
---
<br>

## 🛠 작업 내용
### 1️⃣ kubeadm init — 부트스트랩 게이팅 (멱등성 핵심)
- 설정은 `template`으로 배포 후 `--config`로 init (플래그 나열 대신 선언적 관리)
- `creates: /etc/kubernetes/admin.conf` → 이미 init된 노드는 **스킵** 보장
- `--ignore-preflight-errors=Swap`은 사전 검사 통과용 — 실제 스왑 동작은 KubeletConfiguration이 담당
---
### 2️⃣ kubectl 계정 설정
- `getent passwd`로 `kubernetes_admin_user`의 홈 디렉토리 조회 (하드코딩 없음, 계정 없으면 즉시 실패)
- `.kube/config`에 admin.conf 복사 + 소유권 부여 (file/copy 멱등)
---
### 3️⃣ Calico 설치 — 사전 체크 게이팅 + server-side apply
- Operator 매니페스트는 `get_url` 다운로드 (파일명에 버전 포함 → 버전 변경 시에만 재다운로드)
- **둘 다 존재 확인으로 게이팅** (diff 게이팅 불가): Operator는 대상 네임스페이스가 없으면
`kubectl diff`가 rc=2 에러, Installation CR은 적용 후 operator가 spec 기본값을 채우며
필드 소유권을 가져가 server-side diff가 Conflict(rc=2) 발생
→ 존재 확인(rc=0/1) 후 **미설치일 때만** apply → 재실행 시 **changed=0**
- 설정 변경(pod_subnet 등) 반영은 재실행이 아닌 재구축 영역 (k8s_reset 후 재실행)
- **server-side apply 필수**: `create`는 재실행 실패, client-side apply는 CRD가 커서 annotation 한도 초과
- Operator 적용 직후 CRD 등록 대기(`kubectl wait --for condition=established`) 후 Installation CR 적용
---
### 4️⃣ 검증
- 마스터 노드 `Ready` 대기 — control-plane 라벨 조회 + `until`/`retries` (최대 5분)
- INTERNAL-IP == `ansible_host` 확인 (NAT IP 오인 검출), `swapon`으로 스왑 활성 유지 확인
- 하나라도 실패 시 `assert`로 플레이북 중단
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert control plane ready with swap on]
ok: [ap] => {
    "msg": "Good!.. | Control plane Ready (192.168.56.200, swap on)"
}
```
---
