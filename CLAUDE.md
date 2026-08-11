# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Ubuntu 24.04 서버를 Ansible로 프로비저닝하는 IaC 저장소. Control Node(localhost)에서 3대 노드(ap=192.168.56.200, s1=.201, s2=.202)에 password 기반 SSH로 배포한다. OS 기본 설정(ubuntu) → K8s 클러스터(kubeadm + containerd + Calico) → Longhorn 사전 준비 / Terraform / Docker / Kafka(KRaft 로컬 클러스터) / PostgreSQL(TimescaleDB) / MinIO / Neo4j(Community Edition) / BuildKit(빌드 데몬) 설치 / Airflow 코드 저장소 부트스트랩(local_git)을 플레이북 11개로 나눠 담당한다. 모든 문서·주석은 한국어로 작성한다.

## 실행 명령어

빌드/테스트/린트 도구는 없다. 실행 = ansible-playbook 실행이다.

```bash
# 최초 1회 — Control Node에 Ansible 설치
sudo bin/ansible_setup.sh

# 2인자 스크립트 — <프로젝트 절대경로> <TARGET>. TARGET=all이면 플레이북 전체, 태그명이면 해당 롤만(--tags로 전달)
bin/start_ansible.sh <프로젝트 절대경로> all         # ubuntu_ansible.yml — OS 기본 프로비저닝
bin/start_ansible.sh <프로젝트 절대경로> etc_hosts   # 예: etc_hosts 롤만 단독 재실행
bin/start_kubernetes.sh <프로젝트 절대경로> all      # k8s_ansible.yml — K8s 클러스터 구성
bin/start_longhorn.sh <프로젝트 절대경로> all        # longhorn_ansible.yml — Longhorn 노드 사전 준비
bin/start_terraform.sh <프로젝트 절대경로> all       # terraform_ansible.yml — Terraform 설치
bin/start_kafka.sh <프로젝트 절대경로> all           # kafka_ansible.yml — Kafka 설치 (KRaft 로컬 클러스터)

# 1인자 스크립트 — <프로젝트 절대경로>만 전달
bin/start_docker.sh <프로젝트 절대경로>      # docker_ansible.yml — Docker 설치
bin/start_postgresql.sh <프로젝트 절대경로>  # postgresql_ansible.yml — PostgreSQL(TimescaleDB) 설치
bin/start_minio.sh <프로젝트 절대경로>       # minio_ansible.yml — MinIO(SNSD) 설치
bin/start_neo4j.sh <프로젝트 절대경로>       # neo4j_ansible.yml — Neo4j(Community Edition) 설치
bin/start_local_git.sh <프로젝트 절대경로>   # local_git_ansible.yml — Airflow 코드 저장소 부트스트랩
bin/start_buildkitd.sh <프로젝트 절대경로>   # buildkitd_ansible.yml — BuildKit(docker 없는 이미지 빌드/push 데몬) 설치

# 또는 프로젝트 루트에서 직접 실행 (ansible.cfg가 inventory=host.yml을 지정하므로 -i 불필요)
ansible-playbook ubuntu_ansible.yml
ansible-playbook ubuntu_ansible.yml --tags etc_hosts   # 롤 단독 재실행
```

- **반드시 프로젝트 루트에서 실행**해야 한다 — ansible.cfg의 inventory/roles_path/callback_plugins가 상대 경로 기준이다. start_*.sh가 `cd`를 대신 해주는 이유가 이것이다.
- ubuntu·k8s·kafka·longhorn·terraform 플레이북은 **모든 롤 항목에 롤명과 동일한 태그**가 있어 TARGET 인자(또는 `--tags`)로 어떤 롤이든 단독 재실행할 수 있다. docker·postgresql·minio·neo4j·local_git 플레이북에는 태그가 없다(롤 1개짜리).
- 실행 출력 끝에는 커스텀 콜백 [callback_plugins/summary_table.py](callback_plugins/summary_table.py)(ansible.cfg `callback_plugins = ./callback_plugins`)가 PLAY RECAP 뒤 롤·태스크·호스트별 요약 표를 덧붙인다. aggregate 타입이라 stdout_callback(yaml)을 대체하지 않으며, assert 태스크는 PASS/FAIL로 표기한다.
- 핀 버전 후보 확인: `apt-cache madison <패키지>` (저장소 등록 후)
- k8s 롤에는 `ansible.posix`, `community.general` 컬렉션이 필요하다. collection_check 롤은 **검증만 하고 설치하지 않는다** — 없으면 `ansible-galaxy collection install`로 직접 설치.

## 아키텍처

### 변수는 전부 group_vars/에 (롤에는 defaults/vars 없음)

- 38개 롤 어디에도 `defaults/`, `vars/`가 없다. 모든 변수는 그룹별 [group_vars/](group_vars/)(`Ubuntu_Servers`, `kubernetes`, `longhorn`, `local_git`, `terraform`, `docker`, `kafka`, `postgres`, `minio`, `neo4j` — 그룹당 파일 하나)에 중앙 집중되어 있고, 버전 핀·CIDR·경로 등 운영 지식이 주석으로 함께 기록되어 있다.
- 인벤토리 [host.yml](host.yml)에는 호스트/그룹 구조와 호스트 고유값(`ansible_host`, `kafka_node_id`), localhost의 접속 설정(`ansible_connection: local`, `ansible_become_password`)만 남긴다. `group_vars/`는 인벤토리 파일과 같은 디렉토리에 있어 Ansible이 자동으로 읽는다 — 플레이북·ansible.cfg·bin 스크립트는 이를 위해 아무것도 지정하지 않는다.
- **파일명은 그룹명과 대소문자까지 정확히 일치해야 한다**(`group_vars/Ubuntu_Servers.yml`). 어긋나면 조용히 로드되지 않아 변수 미정의로 실패한다.
- 롤이 어떤 변수를 보는지는 플레이북의 `hosts:` 그룹이 결정한다. 예: k8s_ansible.yml Play 1은 `hosts: kubernetes_master` + `connection: local` — 실행은 컨트롤 노드에서 되지만 kubernetes 그룹 변수를 상속받기 위한 구성이다.
- 새 롤 추가 = `roles/<이름>/tasks/main.yml` 작성 + `group_vars/<그룹>.yml`에 변수 추가 + 플레이북 `roles:` 목록 등록. 새 그룹이면 host.yml에 그룹과 멤버를 먼저 정의한다.

### 롤 구조와 문서 동기화

- 각 롤은 `tasks/main.yml` 하나로 실행되며, 같은 디렉토리의 `tasks/<롤이름>.md` 한국어 문서가 main.yml 소스를 그대로 포함한다. **태스크를 수정하면 해당 .md와 README.md의 롤 설명도 함께 갱신**할 것 — 안 하면 문서와 코드가 어긋난다.
- `handlers/`는 nicname·ntp·ssh_root_login·kafka·postgres·minio·neo4j만, `templates/`는 k8s_master만 사용한다.

### 롤 작성 규칙 (기존 롤 주석에 명문화된 하우스 스타일)

- 멱등 모듈 우선: apt / copy / lineinfile / blockinfile / dpkg_selections / systemd / sysctl / modprobe / deb822_repository. 비멱등 shell 명령 금지 — 기존 주석이 명시적으로 금지한 것들: `apt-mark hold`, `sed` 파이프, `gpg --dearmor`. locale/timezone도 `update-locale`·`timedatectl set-timezone` 대신 멱등 모듈(lineinfile·timezone)을 쓴다 — 검증용 읽기(`timedatectl show`)는 사용해도 된다.
- 비멱등 명령은 반드시 가드를 건다: `creates=`(kubeadm init → admin.conf), `removes=`(kubeadm reset), 또는 사전 상태 조회 + `when:`.
- **모든 롤은 검증 블록으로 끝난다**: 상태 조회(`changed_when: false`) → `assert`. 메시지는 대부분 success_msg `"Good!.. |"` / fail_msg `"ERROR!.. |"` 형식(control·root_password는 `[SUCCESS]`/`[FAIL]` 쌍, packages·pip_packages·ufw는 success만 `"Good!.. |"`이고 fail은 `[FAIL]`인 혼합형). assert 조건 안에 `{{ }}` 금지, 검증에 `lookup()` 금지(컨트롤 노드에서 읽으므로 대상 노드 검증이 안 됨).
- 버전 고정 패턴: hold는 `dpkg_selections`로 걸고, apt 설치에는 `allow_change_held_packages` + `allow_downgrade`를 함께 줘서 group_vars의 핀 버전 변경이 hold 상태에서도 수렴하게 한다(k8s_packages·docker·terraform은 retries도 추가). **containerd·runc는 반드시 한 apt 트랜잭션에서 짝 버전(`containerd_version`·`runc_version`)으로 설치·hold** — 짝이 어긋나면 AppArmor가 runc의 종료 신호를 막아 파드가 Terminating에서 안 사라진다(Ubuntu 버그 #2065423).
- retries는 apt 재시도 외에도 외부 다운로드·저장소 조회(3회)와 서비스 기동 대기(kafka·postgres·minio·neo4j 6~12회, k8s 노드 Ready 30회)에 쓴다 — 새 롤에서 기동 대기가 필요하면 이 선례를 따른다.
- 모든 플레이가 `gather_facts: false` — ansible_facts를 쓸 수 없다. 노드 IP는 인벤토리의 `ansible_host`를 사용한다.

### 플레이북 실행 흐름과 롤 간 결합

- **ubuntu_ansible.yml**: control(localhost, sshpass) → Ubuntu_Servers에 롤 20개 순차 적용. 순서 의존: java → package_version_lock(openjdk hold 대상) / bash_common(JAVA_HOME).
- **k8s_ansible.yml**: collection_check → kubernetes 그룹 전체에 [k8s_prereq, containerd, k8s_packages] → k8s_master(ap) → k8s_worker(s1, s2). 해체용 k8s_reset 플레이는 평소 주석 상태로 두고 해체 시에만 활성화한다. Common Setup 플레이의 `serial: 1`은 제거된 상태 — containerd 설정/버전 변경 시 여러 노드의 containerd가 동시에 재시작될 수 있으니(forks=2) 운영 중 클러스터에는 `--limit`으로 한 대씩 돌릴 것(containerd 롤 주석은 아직 serial: 1 전제).
- **스왑은 켠 채로 K8s를 운영한다(LimitedSwap)**: disable_swap이 주석 처리되고 enable_swap이 활성인 것은 의도다. k8s_master/k8s_worker가 `swap_file_path` 활성 상태를 assert하므로 disable_swap을 켜면 k8s 플레이 검증이 실패한다.
- **kubeadm init/join은 1회성**(`creates=` 가드): `pod_subnet` 등 클러스터 설정을 바꿔도 재실행으로 반영되지 않는다 → k8s_reset으로 해체 후 재구축.
- **docker 롤은 docker-ce가 아니라 docker.io를 쓴다**: docker-ce의 containerd.io 패키지가 K8s용 containerd 패키지를 대체해 런타임이 깨지기 때문. docker와 K8s는 containerd 하나를 공유한다.
- **kafka_ansible.yml**: kafka 그룹(ap·s1·s2)에 KRaft 3노드 로컬 클러스터(ADR 0 — K8s가 아니라 systemd) → ap에서 토픽 생성. **Kafka 4.0+ 브로커는 Java 17 필수** — `java_version`·project_envs의 JAVA_HOME·`kafka_java_home`은 항상 함께 움직인다. CLUSTER_ID는 최초 포맷 시 각인(`creates=meta.properties` 가드)이라 변경해도 재실행으로 반영되지 않는다. 리스너 포트(9092/9093/9094 + JMX 9404)를 바꾸면 Terraform 300-data-layer-base의 `kafka_bootstrap_servers`, 302-monitoring의 `kafka_jmx_targets`도 같이 고칠 것.
- **postgresql_ansible.yml / minio_ansible.yml**: `postgres` 그룹(ap)에 postgresql-16 + TimescaleDB, `minio` 그룹(ap)에 MinIO(SNSD) + mc — 둘은 서로 의존하지 않으므로 따로 돌려도 되고, Terraform 300 이전에 둘 다 떠 있으면 된다. ADR 0(Kafka)의 판단을 데이터 스토어에도 적용한 것으로, compose의 `initdb.d/01·02·03`과 `minio-init` 서비스를 이 두 플레이북이 대체한다(이미지가 사라졌으므로 **여기가 DDL·버킷의 단일 원본**). PG는 DB 3종(`airflow`/`data_layer`/`iceberg_catalog`)을 한 인스턴스에 담고, `shared_preload_libraries='timescaledb'`가 없으면 `CREATE EXTENSION`이 실패한다(reload 아님 — restart 여야 반영). `listen_addresses='*'` + `pg_hba`에 `pod_subnet`·`node_cidr` 둘 다 필요하다(hostNetwork 파드는 노드 IP로 온다). **계정·버킷 이름이 곧 계약** — `postgres_superuser`/`minio_root_user`는 Terraform 300-data-layer-base·304-airflow의 `secrets.auto.tfvars`와 글자 그대로 같아야 하고, 포트를 바꾸면 300의 `postgres_port`·`minio_endpoint`도 함께 고칠 것. MinIO 바이너리는 `latest`가 아니라 `archive/<태그>`를 받으므로 핀을 올리기 전 실존 확인이 필요하다(최신 릴리스가 archive에 아직 없을 수 있다).
- **neo4j_ansible.yml**: `neo4j` 그룹(ap)에 Neo4j Community Edition + cypher-shell(apt, `debian.neo4j.com stable 5`) — PG/MinIO와 같은 판단(ADR 0)이고 서로 의존하지 않으므로 따로 돌려도 된다. compose의 `data_layer-graph` 서비스를 대체하며, **CE는 DB가 `neo4j` 하나뿐이라** 기존 그래프와의 분리는 DB가 아니라 라벨 접두어(`GRAPH_LABEL_PREFIX`, 300 스택이 주입)로 한다. **UNIQUE 제약 27종은 이 롤이 만들지 않는다** — 컨슈머(`cdm_consumer_graph/constraints.py`)가 기동 시 1회 생성한다. `server.default_listen_address=0.0.0.0`이 아니면 서버는 정상 기동하는데 컨슈머만 연결 거부를 맞는다. **비밀번호는 최초 기동 전 1회 각인**(`neo4j-admin dbms set-initial-password`, `creates=auth.ini` 가드)이라 `group_vars/neo4j.yml` 값을 나중에 바꿔도 재실행으로 반영되지 않는다(`ALTER USER` 직접 실행). 설정은 `blockinfile`이 아니라 **`lineinfile`로 키마다 치환**한다 — 배포된 `neo4j.conf`에 같은 키가 주석으로 이미 있어 덧붙이면 중복된다. systemd 설정은 드롭인(`neo4j.service.d/10-data-layer.conf`)으로 넣는다(`/etc/default/neo4j`는 sysvinit 전용). Java 17 필수(패키지 의존성 `java17-runtime|jdk-17`)이고, **버전 핀은 되돌릴 수 없다** — 상위 버전이 연 스토어를 하위 버전이 못 연다.
- **local_git_ansible.yml**: `local_git` 그룹(s2)에 Airflow 코드 저장소(`data_layer_airflow`)를 부트스트랩한다 — `git init` + `.gitignore` + origin + 최초 커밋/push. **이 저장소에서 유일하게 Terraform 중간에 끼어드는 플레이북이다**: push 대상이 Terraform `303-git` 의 파드라서 `303 apply → 이 플레이북 → 304-airflow apply` 순서여야 한다(저장소가 비면 airflow 파드의 git-sync 가 init 에서 멈춘다). **부트스트랩 전용** — 커밋이 하나라도 있으면 최초 커밋·push 를 건너뛴다(매 실행마다 WIP 를 임의 메시지로 커밋하지 않기 위함). `airflow.env`·`scripts/airflow.conf` 는 `.gitignore` 고정 대상이다(저장소는 인증 없이 clone 되므로 비밀번호·fernet 키가 그대로 노출된다). `local_git_branch` 는 Terraform `304-airflow` 의 `git_ref` 와, `local_git_remote_url`(NodePort)은 `git_repo`(ClusterIP FQDN)와 같은 저장소를 가리켜야 한다.
- **buildkitd_ansible.yml**: `buildkitd` 그룹(s2 — data_pipeline 소스가 있는 빌드 머신)에 buildkitd + buildctl 설치. K8s 노드에 docker 를 깔지 않는 방침이라 data_pipeline `build_and_push.sh` 의 buildctl 경로(BUILDER 자동 감지)가 이 데몬으로 빌드+push 한다. runc 는 없으면 설치·있으면 그대로(state=present — containerd 롤이 hold 한 짝 버전을 건드리지 않는다), push 인증은 `/root/.docker/config.json`(⚠ `buildkit_registry_password` 는 Terraform 200-harbor `secrets.auto.tfvars` 의 `harbor_admin_password` 와 글자 그대로 같아야 한다). ⚠ `buildkit_registry` 는 `data-layer-harbor:80` — 포트 없는 이름은 이미지 참조 파서가 docker.io 네임스페이스로 정규화해 push 가 Docker Hub 로 가므로 `:80` 이 필수고, build_and_push.sh 의 REGISTRY 기본값과 글자 그대로 같아야 한다. HTTP Harbor 는 스크립트가 `registry.insecure=true` 로 처리하므로 이 롤은 인증 파일만 만든다. 사용 시점은 200-harbor apply 이후다.
- `containerd_insecure_registries` 값은 certs.d 디렉토리명이 되므로 이미지 주소의 host:port와 **글자 그대로** 일치해야 하고, `data-layer-harbor` 이름은 etc_hosts 롤이 /etc/hosts에 등록해야 풀린다(etc_hosts는 /etc/hosts를 통째로 재생성). harbor는 VIP 계열이므로 이미지 pull은 MetalLB 인그레스 VIP를 경유한다.
- **etc_hosts 롤의 data-layer 이름은 두 계열로 갈린다 — 기준은 '장애 전환을 누가 하느냐'다.** `data_layer_dns_names`(git·minio-console·neo4j)는 이름 하나가 노드 IP 전부를 갖고 전환을 클라이언트가 한다(죽은 IP면 TCP 타임아웃 대기). `data_layer_vip_dns_names`(harbor·kafka-ui·airflow·api·grafana·prometheus)는 전부 `ingress_vip` 하나를 가리키고 전환은 MetalLB가 한다. **한 이름을 두 계열에 동시에 넣지 말 것** — 클라이언트가 아무 데나 붙어 증상이 매번 달라진다. 검증 assert도 기대 개수가 달라(노드 수 곱하기 vs ×1) 태스크가 분리돼 있으니 합치지 말 것. `ingress_vip`는 Terraform `102-ingress`·`305-api`의 `ingress_vip`와 **글자 그대로** 같아야 한다.
- /etc/hosts는 인그레스 전환·노드 IP 변경 때 `--tags etc_hosts`(또는 `start_ansible.sh <경로> etc_hosts`)로 단독 갱신한다. **접속하는 PC의 hosts는 이 롤의 관리 대상이 아니다**(대상은 노드 3대뿐) — 수동 관리이며 형식은 README 참조.
- kubelet `--node-ip`와 Calico 감지(`node_cidr`)는 host-only NIC(192.168.56.x)에 고정 — VirtualBox NAT IP(10.0.2.15)가 잡히는 것을 방지한다.

## 커밋 컨벤션 ([COMMIT_CONVENTION.md](COMMIT_CONVENTION.md))

- `type(scope): subject` — 제목은 한국어, 50자 이내, 마침표 없음, 명령형("추가" ⭕ / "추가함" ❌). 한 커밋에는 한 가지 변경만.
- type: feat / fix / docs / refactor / style / test / chore / ci. scope 예: containerd, inventory, playbook (생략 가능).
- GitLab 이슈 연동: 제목에 `#번호`, 머지 시 자동 종료는 본문에 `Closes #번호`.
