# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Ubuntu 24.04 노드 3대(ap=192.168.56.38, s1=.39, s2=.40 — 정본은 [host.yml](host.yml) 의 `ansible_host`)를 Control Node(localhost = ap)에서 password SSH(`ansible_user: project`)로 프로비저닝하는 Ansible IaC 저장소. **플레이북 11개 · 롤 39종**(플레이북 미등록 2종 포함). 모든 문서·주석은 한국어.

**담당 범위는 "노드까지"다.** OS 기본 설정 → K8s 클러스터(kubeadm + containerd + Cilium) → 도구 설치(Terraform·Helm·BuildKit) → 노드 선행작업(Longhorn OS 준비, Kafka·Hadoop·Elasticsearch·RustFS 로컬 PV 디렉토리, Airflow DAG hostPath). 데이터 스토어(Kafka·RustFS·PostgreSQL·HDFS·Elasticsearch·Neo4j)와 Harbor·인그레스는 전부 `/project/Infrastructure-as-Code-Terraform.kubernetes/`(100~200 번대 Terraform, 300 번대 이상 Helm 차트, 공통값 `values.common.yaml`)가 담당하고, 여기에는 그 차트들이 전제하는 노드 쪽 준비만 있다.

## 실행 명령어

빌드/테스트/린트 도구는 없다. 문법 확인은 `ansible-playbook --syntax-check <플레이북>`.

```bash
# 최초 1회 — Control Node에 Ansible 설치
sudo bin/ansible_setup.sh

# 실행 스크립트는 전부 2인자 — <프로젝트 절대경로> <TARGET>. TARGET=all 이면 전체, 태그명이면 해당 롤만(--tags)
bin/start_server_configuration.sh <경로> all   # server_configuration_ansible.yml — OS 기본 프로비저닝 (롤 21개)
bin/start_kubernetes.sh           <경로> all   # k8s_ansible.yml                 — K8s 클러스터 구성
bin/start_longhorn.sh             <경로> all   # longhorn_ansible.yml            — Longhorn 노드 사전 준비
bin/start_terraform.sh            <경로> all   # terraform_ansible.yml           — Terraform 설치
bin/start_helm.sh                 <경로> all   # helm_ansible.yml                — Helm 설치
bin/start_buildkitd.sh            <경로> all   # buildkitd_ansible.yml           — BuildKit(docker 없는 빌드/push 데몬) 설치
bin/start_kafka_prereq.sh         <경로> all   # kafka_prereq_ansible.yml        — 301-kafka 로컬 PV 디렉토리
bin/start_hadoop_prereq.sh        <경로> all   # hadoop_prereq_ansible.yml       — 301-hadoop 로컬 PV 디렉토리
bin/start_elasticsearch_prereq.sh <경로> all   # elasticsearch_prereq_ansible.yml — 301-elasticsearch 로컬 PV 디렉토리
bin/start_rustfs_prereq.sh        <경로> all   # rustfs_prereq_ansible.yml        — 301-rustfs 로컬 PV 디렉토리
bin/start_airflow_repo_prereq.sh  <경로> all   # airflow_repo_prereq_ansible.yml — 304-airflow DAG hostPath 디렉토리 + rsync
bin/start_airflow_repo_prereq.sh  <경로> sync  # DAG 수동 반영 — rsync + 검증만 (sync 태그)

# 또는 프로젝트 루트에서 직접 (ansible.cfg 가 inventory=host.yml 을 지정하므로 -i 불필요)
ansible-playbook server_configuration_ansible.yml --tags etc_hosts   # 롤 단독 재실행
```

- **반드시 프로젝트 루트(`/project/Infrastructure-as-Code-Ansible`)에서 실행** — ansible.cfg 의 inventory/roles_path/callback_plugins 가 상대 경로다. start_*.sh 가 `cd` 를 대신 한다.
- **모든 롤 항목에 롤명과 같은 태그**가 붙어 있어 어떤 롤이든 `--tags` 로 단독 재실행 가능(helm 롤은 helm_ansible.yml·k8s_ansible.yml 두 곳 등록). 롤명이 아닌 태그는 airflow_repo_prereq 의 `sync` 하나뿐.
- 실행 끝에 커스텀 콜백 [callback_plugins/summary_table.py](callback_plugins/summary_table.py)(aggregate 타입 — stdout_callback=yaml 유지)가 PLAY RECAP 뒤 롤·태스크·호스트별 요약 표를 붙인다. assert 는 PASS/FAIL 로 표기.
- ansible.cfg: `forks = 3`, `force_handlers = True`(롤이 실패해도 notify 된 handler 실행), `pipelining`, `host_key_checking = False`, `retry_files_enabled = False`, `remote_tmp = ~/.ansible/tmp`.
- k8s 롤은 `ansible.posix`·`community.general`·`kubernetes.core` 컬렉션 필요(`group_vars/kubernetes.yml` 의 `required_collections`). collection_check 롤은 **검증만** 한다 — 없으면 `ansible-galaxy collection install` 로 직접 설치.
- 핀 버전 후보 확인: `apt-cache madison <패키지>` (저장소 등록 후).

## 아키텍처

### 변수는 전부 group_vars/ (롤에 defaults/vars 없음)

- 모든 변수는 [group_vars/](group_vars/) **11개 파일**(`server_configuration`·`kubernetes`·`longhorn`·`terraform`·`helm`·`buildkitd`·`kafka`·`hadoop`·`elasticsearch`·`rustfs`·`airflow` — 그룹당 하나)에 있고 버전 핀·CIDR·경로 근거가 주석으로 함께 있다. 접속 자격(`ansible_user`·`ansible_ssh_pass`·`ansible_become_password`)도 `server_configuration.yml`.
- [host.yml](host.yml) 은 호스트/그룹 구조와 `ansible_host`, localhost 접속 설정만 갖는다. `group_vars/` 는 인벤토리와 같은 디렉토리라 자동 로드 — **파일명은 그룹명과 대소문자까지 정확히 일치**해야 하고 어긋나면 조용히 미정의로 실패한다.
- 그룹: `server_configuration`·`kubernetes`(master=ap, workers=s1·s2)·`longhorn`·`kafka`·`hadoop`·`elasticsearch`·`rustfs`·`airflow` 는 3노드 전부, `terraform`·`helm`·`buildkitd` 는 **ap 만**(배포/빌드 머신). 롤이 보는 변수는 플레이북 `hosts:` 그룹이 결정한다 — k8s_ansible.yml Play 1 이 `hosts: kubernetes_master` + `connection: local` 인 이유(컨트롤 노드 실행 + kubernetes 그룹 변수 상속).
- 새 롤 = `roles/<이름>/tasks/main.yml` + `group_vars/<그룹>.yml` 변수 + 플레이북 `roles:` 에 **롤명 태그와 함께** 등록. 새 그룹이면 host.yml 에 먼저 정의.

### 롤 구조와 문서 동기화

- 각 롤은 `tasks/main.yml` 하나로 실행되고, 같은 디렉토리의 `tasks/<롤이름>.md` 한국어 문서가 **main.yml 전문을 그대로 포함**한다(39개 롤 전부). 양식은 [.claude/skills/role-doc/SKILL.md](.claude/skills/role-doc/SKILL.md): 제목 → `## 🧩 main.yml` → `## 📌 group_vars 예시` → `## 🛠 작업 내용` → `## 🧩 handlers/main.yml` → `## ✅ 실행 결과 예시`.
- **태스크를 수정하면 해당 .md 와 README.md 의 롤 설명도 함께 갱신**한다.
- `handlers/` 는 **nicname·ntp·ssh_root_login·buildkitd** 4개, `templates/` 는 **k8s_master**(`kubeadm-config.yaml.j2`)·**k8s_cilium**(`cilium-values.yaml.j2`) 2개만.
- 플레이북 미등록 롤은 **disable_swap·k8s_reset 둘뿐이고 의도된 비활성**이다. 그 외 미참조 롤이 생기면 정리 누락.

### 롤 작성 규칙 (하우스 스타일)

- 멱등 모듈 우선: apt / copy / lineinfile / blockinfile / replace / dpkg_selections / systemd / sysctl / modprobe / deb822_repository / file / template. 금지: `apt-mark hold`(→ dpkg_selections), `sed` 파이프(→ copy/replace), `gpg --dearmor`(→ deb822_repository), `update-locale`·`timedatectl set-timezone`(→ lineinfile·timezone). 검증용 읽기 명령은 허용.
- 비멱등 명령은 반드시 가드: `creates=`(k8s_master → admin.conf, k8s_worker → kubelet.conf, helm·buildkitd → 버전별 바이너리), `removes=`(k8s_reset → kubelet.conf), 또는 사전 조회 + `when:`. 출력으로만 변경을 아는 명령은 `changed_when: stdout != ''`(airflow_repo_prereq rsync).
- **모든 롤은 검증 블록으로 끝난다**: 조회(`changed_when: false`) → `assert`. 메시지는 success `"Good!.. |"` / fail `"ERROR!.. |"`(예외: control·root_password 는 `[SUCCESS]`/`[FAIL]`, packages·ufw 는 fail 만 `[FAIL]`). assert 조건 안에 `{{ }}` 금지, `lookup()` 금지(컨트롤 노드에서 읽어 대상 노드 검증이 안 됨). 쓰지 않을 `register:` 는 남기지 않는다.
- 버전 고정: hold 는 `dpkg_selections`(containerd·k8s_packages·terraform·longhorn_prereq·package_version_lock), apt 설치에는 `allow_change_held_packages` + `allow_downgrade` 를 함께 줘서 핀 변경이 hold 상태에서도 수렴하게 한다. **containerd·runc 는 한 apt 트랜잭션에서 짝 버전으로 설치·hold** — 짝이 어긋나면 AppArmor 가 runc 종료 신호를 막아 파드가 Terminating 에서 안 사라진다(Ubuntu 버그 #2065423).
- 현재 핀: K8s 1.34.4 / containerd 2.2.1 / runc 1.3.4 / Cilium 1.20.1 / Helm 3.19.0(`helm_sha256` 체크섬 함께 갱신) / BuildKit 0.32.2 / Terraform 1.15.8 / open-iscsi 2.1.9 / Java 17.
- retries: 외부 다운로드·저장소 조회 3회(helm·buildkitd·terraform·k8s_packages), 기동 대기는 10초 간격으로 k8s_master 18회(노드 등록 — CNI 전이라 NotReady 정상)·k8s_cilium 30회·k8s_worker 30회(전체 Ready).
- 모든 플레이가 `gather_facts: false` — ansible_facts 사용 불가, 노드 IP 는 `ansible_host`.

### 플레이북 흐름과 롤 간 결합

- **server_configuration_ansible.yml**: control(localhost, sshpass) → 3노드에 롤 20개 순차. 순서 의존: java → package_version_lock(openjdk hold)·bash_common(JAVA_HOME), etc_hosts → hostname(검증이 /etc/hosts 를 getent 로 읽음). java 17 은 노드 공용 JDK 로만 남아 있다.
- **hostname 롤은 k8s_ansible.yml 전에**: kubeadm 이 OS 호스트명을 노드명으로 등록하므로 인벤토리 이름(ap/s1/s2 = `values.common.yaml` 의 `global.nodes[].name`)을 init/join 전에 적용. init 후 바꾸면 k8s_reset 후 재구축.
- **k8s_ansible.yml**: collection_check(localhost) → kubernetes 전체 [k8s_prereq, containerd, k8s_packages] → 마스터 ap [helm, k8s_master, k8s_cilium] → 워커 s1·s2 [k8s_worker](join·클러스터 검증은 `delegate_to` 마스터). 해체용 k8s_reset 플레이는 주석 상태 — 해체 시에만 활성화. Common Setup 에 `serial` 이 없어 containerd 변경 시 여러 노드가 동시(forks=3) 재시작될 수 있으니 운영 중엔 `--limit` 으로 한 대씩.
- **스왑은 켠 채 운영(LimitedSwap, cgroup v2 전제)**: disable_swap 주석 + enable_swap 활성은 의도. k8s_master/k8s_worker 가 `swap_file_path` 활성을 assert 하므로 disable_swap 을 켜면 k8s 검증이 실패한다.
- **kubeadm init/join 은 1회성**(`creates=`): `pod_subnet` 등 클러스터 설정 변경은 재실행으로 반영되지 않는다 → k8s_reset 후 재구축. Cilium `routingMode`/ipam 도 기존 노드에 라우트·BPF 맵이 남아 재구축 대상.
- **CNI = Cilium**(eBPF + Native Routing + kube-proxy replacement, Hubble·UI 활성). kubeadm-config 의 `skipPhases: addon/kube-proxy` 와 Cilium values 의 `kubeProxyReplacement: true` 는 **한 쌍**. kubelet `--node-ip` 와 Cilium `devices`(`cilium_device`=eth1)는 host-only NIC 고정 — VirtualBox NAT IP(10.0.2.15) 오인 방지. 컨트롤플레인 taint 는 비움(ap 도 워크로드 스케줄).
- **kafka_prereq / hadoop_prereq / elasticsearch_prereq / rustfs_prereq**: 같은 성격 — Helm 차트(301-kafka·301-hadoop·301-elasticsearch 는 hostNetwork, 301-rustfs 는 파드 네트워크 — 넷 다 정적 local PV)가 가리키는 **노드 디렉토리 생성뿐**. kafka `/data/kafka-broker`·`/data/kafka-controller`, hadoop `/data/hadoop-{zookeeper,journalnode,namenode,datanode}`, elasticsearch `/data/elasticsearch`, rustfs `/data/rustfs`. 전부 `root:root 2770` — 컨테이너가 비루트(gid 0, 또는 rustfs 처럼 uid 10001 + fsGroup 0 보조 그룹)라 그룹 쓰기가 필요하고, setgid 를 유지해야 kubelet `OnRootMismatch` 가 재귀 chown 을 건너뛴다. hadoop 의 2770 은 차트 `dfs.datanode.data.dir.perm=770` 과 한 쌍. hadoop 디렉토리는 3노드 전부 만들지만 NameNode PV 는 ap·s1 뿐(s2 의 namenode 디렉토리는 의도적으로 빈 채). **노드를 늘릴 때도 이 플레이북이 먼저** — 디렉토리 없이 차트 노드 표에만 추가하면 PV 마운트 실패로 파드가 멈춘다. 순서: prereq → 차트 배포(helm install 또는 Argo 첫 sync). rustfs 는 풀 단위로만 늘어나 기존 풀에 노드를 끼워 넣지 못한다 — 노드 증설은 차트의 새 풀 설계가 먼저다.
- **airflow_repo_prereq**: 304-airflow 가 **읽기 전용 hostPath** 로 마운트하는 `/project/data_pipeline/data_layer_airflow`(root:root **0755** — 컨테이너 uid 50000 이 읽기만) 생성 + 컨트롤 노드 원본의 3노드 rsync. rsync 는 `synchronize` 가 아니라 `command` + `delegate_to: localhost`(비밀번호 SSH 를 못 타고 root 키 SSH 가 노드 간 열려 있음 — ssh_keygen 롤). `--chmod=Da+rx,Fa+r`(원본 0700 이면 DAG 0개) · `--delay-updates`/`--delete-delay`(반쯤 바뀐 트리 노출 방지) · `*.env`·`logs/`·`.git/` 제외. 상시 동기화는 Helm `304-airflow-rsync`(Sync Pod)가 맡고, `sync` 태그는 수동 반영 경로다 — 디렉토리 **생성**은 여전히 이 롤. 검증은 `dags/` 존재 + 타인 읽기·실행 비트.
- **buildkitd_ansible.yml**: ap 에 buildkitd + buildctl(`/application/buildkit/v<버전>` + `/usr/local/bin` 링크 — helm 의 `/application/helm` 과 같은 컨벤션). K8s 노드에 docker 를 깔지 않으므로 data_pipeline `scripts/build_and_push.sh` 의 buildctl 경로가 이 데몬으로 빌드+push. runc 는 `state=present`(containerd 롤이 hold 한 짝 버전을 건드리지 않음). push 인증은 `/root/.docker/config.json`. 사용 시점은 200-harbor apply 이후.
- **etc_hosts**: /etc/hosts 를 통째로 재생성. data-layer 이름은 두 계열 — 기준은 '장애 전환을 누가 하느냐'. `data_layer_dns_names`(현재 `data-layer-neo4j` 하나)는 이름 하나가 노드 IP 전부를 갖고 전환은 클라이언트가, `data_layer_vip_dns_names`(harbor·kafka-ui·airflow·api·grafana·prometheus·headlamp)는 전부 `ingress_vip` 하나를 가리키고 전환은 MetalLB 가. **한 이름을 두 계열에 동시에 넣지 말 것.** 검증 assert 는 기대 개수가 달라(이름 수 × 노드 수 vs 이름 수 × 1줄) 분리돼 있으니 합치지 말 것. 갱신은 `--tags etc_hosts` 단독. 접속 PC 의 hosts 는 관리 대상이 아니다(수동, README 참조).
- `containerd_insecure_registries` 는 certs.d 디렉토리명이 되므로 이미지 주소 host:port(`data-layer-harbor:80`)와 글자 그대로 일치해야 하고, 이름은 etc_hosts 가 등록해야 풀린다. 노드 containerd 는 이 목록만 신뢰하므로 docker.io 직접 pull 은 불가 — data_pipeline 이 미러 이미지까지 Harbor 로 올리는 이유.

### 교차 저장소 계약 — 글자 그대로 같아야 하는 값

| 이 저장소 | 상대 |
|---|---|
| `host.yml` 의 `ansible_host` / 인벤토리 이름 ap·s1·s2 | TF/Helm `values.common.yaml` 의 `global.nodes`·`global.kafka.brokers` |
| `ingress_vip`(192.168.56.240) | Terraform 102-ingress `ingress_vip`, `values.common.yaml` 의 `global.ingressVip` |
| `data_layer_vip_dns_names` | `values.common.yaml` 의 `global.hosts`, 200-harbor `harbor_host`(headlamp 는 TF/Helm 스택 없음) |
| `containerd_insecure_registries`·`buildkit_registry`(`data-layer-harbor:80`) | `global.harborRegistry`, `build_and_push.sh` 의 `REGISTRY` 기본값 — `:80` 없으면 docker.io 로 정규화 |
| `buildkit_registry_password` | 200-harbor `secrets.auto.tfvars` 의 `harbor_admin_password` |
| `longhorn_data_path`(`/data/longhorn`) | 100-base `longhorn_data_path`(defaultDataPath) |
| kafka·hadoop·elasticsearch·rustfs 데이터 경로 | `global.kafka.data/metadata.path`, 301-hadoop 경로, 301-elasticsearch·301-rustfs `data.path` |
| `airflow_repo_dir` · `airflow_repo_sync_excludes` | 304-airflow `repo.hostPath`, 304-airflow-rsync `repoPath`·`sync.excludes` |

## 커밋 컨벤션 ([COMMIT_CONVENTION.md](COMMIT_CONVENTION.md))

- `type(scope): subject` — 제목은 한국어, 50자 이내, 마침표 없음, 명령형("추가" ⭕ / "추가함" ❌). 한 커밋에는 한 가지 변경만.
- type: feat / fix / docs / refactor / style / test / chore / ci. scope 예: containerd, inventory, playbook (생략 가능).
- 이슈 연동: 제목에 `#번호`, 머지 시 자동 종료는 본문에 `Closes #번호`.
- 원격은 GitHub(`sy0218/Infrastructure-as-Code-Ansible`, main).
