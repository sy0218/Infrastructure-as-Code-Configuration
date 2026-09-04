# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Ubuntu 24.04 서버를 Ansible로 프로비저닝하는 IaC 저장소. Control Node(localhost)에서 3대 노드(ap=192.168.56.38, s1=.39, s2=.40 — 정본은 host.yml 의 `ansible_host`)에 password 기반 SSH(`ansible_user: project`)로 배포한다. OS 기본 설정(ubuntu) → K8s 클러스터(kubeadm + containerd + Cilium) → Longhorn 노드 사전 준비 / Terraform / Helm / BuildKit(빌드 데몬) 설치 / Kafka·Hadoop 로컬 PV 디렉토리·Airflow DAG hostPath 선행작업을 **플레이북 9개 · 롤 36종**(플레이북 미등록 2종 포함)으로 나눠 담당한다. 모든 문서·주석은 한국어로 작성한다.

**이 저장소가 담당하는 범위는 "노드까지"다.** 데이터 스토어(Kafka·MinIO·PostgreSQL·HDFS)와 Harbor·인그레스는 전부 `Infrastructure-as-Code-Terraform.kubernetes/` 저장소로 이관됐고(이름과 달리 100~200 만 Terraform, 300 이상은 전부 Helm 차트 — 공통값은 그 루트의 `values.common.yaml`), 여기 남은 것은 그 차트들이 전제하는 **노드 선행작업**(디렉토리·드라이브·커널·hosts·레지스트리 신뢰)뿐이다. Neo4j 만 여전히 노드 로컬 설치인데 이 저장소에 설치 롤은 없다(etc_hosts 의 이름 등록뿐).

## 실행 명령어

빌드/테스트/린트 도구는 없다. 실행 = ansible-playbook 실행이다. 문법 확인은 `ansible-playbook --syntax-check <플레이북>`.

```bash
# 최초 1회 — Control Node에 Ansible 설치
sudo bin/ansible_setup.sh

# 실행 스크립트는 전부 2인자 — <프로젝트 절대경로> <TARGET>.
# TARGET=all 이면 플레이북 전체, 태그명이면 해당 롤만(--tags 로 전달)
bin/start_configuration.sh <프로젝트 절대경로> all         # ubuntu_ansible.yml     — OS 기본 프로비저닝
bin/start_configuration.sh <프로젝트 절대경로> etc_hosts   # 예: etc_hosts 롤만 단독 재실행
bin/start_kubernetes.sh   <프로젝트 절대경로> all          # k8s_ansible.yml        — K8s 클러스터 구성
bin/start_longhorn.sh     <프로젝트 절대경로> all          # longhorn_ansible.yml   — Longhorn 노드 사전 준비
bin/start_terraform.sh    <프로젝트 절대경로> all          # terraform_ansible.yml  — Terraform 설치
bin/start_helm.sh         <프로젝트 절대경로> all          # helm_ansible.yml       — Helm 설치 (Helm 차트 스택 배포용 CLI)
bin/start_buildkitd.sh    <프로젝트 절대경로> all          # buildkitd_ansible.yml  — BuildKit(docker 없는 이미지 빌드/push 데몬) 설치
bin/start_kafka_prereq.sh <프로젝트 절대경로> all          # kafka_prereq_ansible.yml — Kafka(301-kafka) 로컬 PV 디렉토리 준비 (K8s 301-kafka 선행)
bin/start_hadoop_prereq.sh <프로젝트 절대경로> all         # hadoop_prereq_ansible.yml — Hadoop(301-hadoop) 로컬 PV 디렉토리 준비 (K8s 301-hadoop 선행)
bin/start_airflow_repo_prereq.sh <프로젝트 절대경로> all   # airflow_repo_prereq_ansible.yml — Airflow(304-airflow) DAG hostPath 디렉토리 + rsync (K8s 304-airflow 선행)
bin/start_airflow_repo_prereq.sh <프로젝트 절대경로> sync  # DAG 수정 반영 — rsync + 검증 태스크만 (sync 태그)

# 또는 프로젝트 루트에서 직접 실행 (ansible.cfg가 inventory=host.yml을 지정하므로 -i 불필요)
ansible-playbook ubuntu_ansible.yml
ansible-playbook ubuntu_ansible.yml --tags etc_hosts   # 롤 단독 재실행
```

- **반드시 프로젝트 루트에서 실행**해야 한다 — ansible.cfg의 inventory/roles_path/callback_plugins가 상대 경로 기준이다. start_*.sh가 `cd`를 대신 해주는 이유가 이것이다. 이 랩의 체크아웃 경로는 `/project/Infrastructure-as-Code-Ansible`(문서 곳곳의 `/my_project` 는 구 경로).
- **플레이북 9개의 롤 항목 35개 전부에 롤명과 동일한 태그**가 붙어 있다(helm 롤은 helm_ansible.yml 과 k8s_ansible.yml 두 곳에 등록) — TARGET 인자(또는 `--tags`)로 어떤 롤이든 단독 재실행할 수 있다. 롤이 하나뿐인 플레이북(longhorn·terraform·helm·buildkitd·kafka_prereq·hadoop_prereq·airflow_repo_prereq)도 예외가 아니라 같은 2인자 형식으로 실행한다. 롤명이 아닌 태그는 airflow_repo_prereq 의 `sync` 하나뿐이다.
- 실행 출력 끝에는 커스텀 콜백 [callback_plugins/summary_table.py](callback_plugins/summary_table.py)(ansible.cfg `callback_plugins = ./callback_plugins`)가 PLAY RECAP 뒤 롤·태스크·호스트별 요약 표를 덧붙인다. aggregate 타입이라 stdout_callback(yaml)을 대체하지 않으며, assert 태스크는 PASS/FAIL로 표기한다. `callback_plugins/__pycache__/` 는 실행 부산물이다.
- ansible.cfg: `forks = 2`, `force_handlers = True`(롤이 실패해도 notify 된 handler 는 실행 — 설정 반쯤 바뀐 서비스가 재시작 없이 남지 않게), `pipelining`, `host_key_checking = False`, `retry_files_enabled = False`.
- 핀 버전 후보 확인: `apt-cache madison <패키지>` (저장소 등록 후)
- k8s 롤에는 `ansible.posix`(sysctl)·`community.general`(modprobe)·`kubernetes.core`(k8s_cilium 의 helm_repository) 컬렉션이 필요하다(`group_vars/kubernetes.yml` 의 `required_collections`). collection_check 롤은 **검증만 하고 설치하지 않는다** — 없으면 `ansible-galaxy collection install`로 직접 설치.

## 아키텍처

### 변수는 전부 group_vars/에 (롤에는 defaults/vars 없음)

- 롤 어디에도 `defaults/`, `vars/`가 없다. 모든 변수는 그룹별 [group_vars/](group_vars/) **9개 파일**(`Ubuntu_Servers`, `kubernetes`, `longhorn`, `terraform`, `helm`, `kafka`, `hadoop`, `airflow`, `buildkitd` — 그룹당 파일 하나)에 중앙 집중되어 있고, 버전 핀·CIDR·경로 등 운영 지식이 주석으로 함께 기록되어 있다. 접속 자격(`ansible_user`·`ansible_ssh_pass`·`ansible_become_password`)도 `Ubuntu_Servers.yml` 에 있다.
- 인벤토리 [host.yml](host.yml)에는 호스트/그룹 구조와 호스트 고유값(`ansible_host`), localhost의 접속 설정(`ansible_connection: local`, `ansible_become_password`)만 남긴다. `group_vars/`는 인벤토리 파일과 같은 디렉토리에 있어 Ansible이 자동으로 읽는다 — 플레이북·ansible.cfg·bin 스크립트는 이를 위해 아무것도 지정하지 않는다.
- **파일명은 그룹명과 대소문자까지 정확히 일치해야 한다**(`group_vars/Ubuntu_Servers.yml`). 어긋나면 조용히 로드되지 않아 변수 미정의로 실패한다.
- 그룹 구성: `Ubuntu_Servers`·`kubernetes`(master=ap, workers=s1·s2)·`longhorn`·`kafka`·`hadoop`·`airflow` 는 3노드 전부, `terraform`·`helm`·`buildkitd` 는 ap·s2(배포/빌드 머신). 롤이 어떤 변수를 보는지는 플레이북의 `hosts:` 그룹이 결정한다. 예: k8s_ansible.yml Play 1은 `hosts: kubernetes_master` + `connection: local` — 실행은 컨트롤 노드에서 되지만 kubernetes 그룹 변수를 상속받기 위한 구성이다.
- 새 롤 추가 = `roles/<이름>/tasks/main.yml` 작성 + `group_vars/<그룹>.yml`에 변수 추가 + 플레이북 `roles:` 목록에 **롤명 태그와 함께** 등록. 새 그룹이면 host.yml에 그룹과 멤버를 먼저 정의한다.

### 롤 구조와 문서 동기화

- 각 롤은 `tasks/main.yml` 하나로 실행되며, 같은 디렉토리의 `tasks/<롤이름>.md` 한국어 문서가 **main.yml 소스를 그대로 포함한다**(` ```yaml ` 블록에 전문 복사 — 요약하지 않는다). 36개 롤 전부 .md 가 있다.
- 이 문서는 [.claude/skills/role-doc/SKILL.md](.claude/skills/role-doc/SKILL.md) 스킬이 정의한 양식을 따른다: 제목 → `## 🧩 main.yml` → `## 📌 group_vars 예시` → `## 🛠 작업 내용` → `## 🧩 handlers/main.yml` → `## ✅ 실행 결과 예시`. **태스크를 수정하면 해당 .md와 README.md의 롤 설명도 함께 갱신**할 것 — 안 하면 문서와 코드가 어긋난다.
- `handlers/`는 **nicname·ntp·ssh_root_login·buildkitd** 4개 롤만, `templates/`는 **k8s_master**(`kubeadm-config.yaml.j2`)·**k8s_cilium**(`cilium-values.yaml.j2`) 둘만 사용한다.
- 플레이북에 등록되지 않은 롤은 **disable_swap·k8s_reset 둘뿐이고 둘 다 의도된 비활성**이다(아래 실행 흐름 참조). 그 외에 미참조 롤이 생겼다면 정리 누락이다.

### 롤 작성 규칙 (기존 롤 주석에 명문화된 하우스 스타일)

- 멱등 모듈 우선: apt / copy / lineinfile / blockinfile / dpkg_selections / systemd / sysctl / modprobe / deb822_repository / file. 비멱등 shell 명령 금지 — 기존 주석이 명시적으로 금지한 것들: `apt-mark hold`(→ `dpkg_selections`), `sed` 파이프(→ `copy`/`replace`), `gpg --dearmor`(→ `deb822_repository`). locale/timezone도 `update-locale`·`timedatectl set-timezone` 대신 멱등 모듈(lineinfile·timezone)을 쓴다 — 검증용 읽기(`timedatectl show`)는 사용해도 된다.
- 비멱등 명령은 반드시 가드를 건다: `creates=`(k8s_master → admin.conf, k8s_worker → kubelet.conf, helm·buildkitd → 버전별 바이너리), `removes=`(k8s_reset → kubelet.conf), 또는 사전 상태 조회 + `when:`. rsync 처럼 출력으로만 변경을 알 수 있는 명령은 `changed_when: stdout != ''`(airflow_repo_prereq).
- **모든 롤은 검증 블록으로 끝난다**: 상태 조회(`changed_when: false`) → `assert`. 메시지는 대부분 success_msg `"Good!.. |"` / fail_msg `"ERROR!.. |"` 형식(control·root_password는 `[SUCCESS]`/`[FAIL]` 쌍, packages·ufw는 success만 `"Good!.. |"`이고 fail은 `[FAIL]`인 혼합형). assert 조건 안에 `{{ }}` 금지, 검증에 `lookup()` 금지(컨트롤 노드에서 읽으므로 대상 노드 검증이 안 됨).
- 조회 태스크는 결과를 반드시 아래 assert에서 소비한다 — 쓰지 않을 `register:`는 남기지 않는다.
- 버전 고정 패턴: hold는 `dpkg_selections`로 걸고(longhorn_prereq·package_version_lock·terraform·containerd·k8s_packages), apt 설치에는 `allow_change_held_packages` + `allow_downgrade`를 함께 줘서 group_vars의 핀 버전 변경이 hold 상태에서도 수렴하게 한다. **containerd·runc는 반드시 한 apt 트랜잭션에서 짝 버전(`containerd_version`·`runc_version`)으로 설치·hold** — 짝이 어긋나면 AppArmor가 runc의 종료 신호를 막아 파드가 Terminating에서 안 사라진다(Ubuntu 버그 #2065423). 현재 핀: K8s 1.34.4 / containerd 2.2.1 / runc 1.3.4 / Cilium 1.20.1 / Helm 3.19.0 / BuildKit 0.32.2 / Terraform 1.15.8.
- retries는 apt 재시도 외에 **외부 다운로드·저장소 조회에 3회**(helm·buildkitd·terraform·k8s_packages), **기동 대기에 10초 간격**으로 k8s_master 18회(마스터 노드 등록 — CNI 전이라 NotReady 가 정상)·k8s_cilium 30회·k8s_worker 30회(노드 Ready)를 쓴다. 새 롤에서 기동 대기가 필요하면 이 선례를 따른다.
- 모든 플레이가 `gather_facts: false` — ansible_facts를 쓸 수 없다. 노드 IP는 인벤토리의 `ansible_host`를 사용한다.

### 플레이북 실행 흐름과 롤 간 결합

- **ubuntu_ansible.yml**: control(localhost, sshpass) → Ubuntu_Servers에 롤 19개 순차 적용. 순서 의존: java → package_version_lock(openjdk hold 대상) / bash_common(JAVA_HOME). java 17 은 원래 로컬 Kafka 브로커 근거였으나 K8s 이관 후 노드 공용 JDK 로만 남아 있다(제거하려면 java 롤·package_version_lock·`project_envs` 의 JAVA_HOME 을 함께).
- **k8s_ansible.yml**: collection_check(localhost) → kubernetes 그룹 전체에 [k8s_prereq, containerd, k8s_packages] → 컨트롤플레인(ap)에 [helm, k8s_master, k8s_cilium] → k8s_worker(s1, s2 — join 과 클러스터 검증은 `delegate_to` 마스터). 해체용 k8s_reset 플레이는 평소 주석 상태로 두고 해체 시에만 활성화한다. **Common Setup 플레이에 `serial`은 없다** — containerd 설정/버전이 바뀌면 여러 노드의 containerd가 동시에(forks=2) 재시작될 수 있으니 운영 중 클러스터에는 `--limit`으로 한 대씩 돌릴 것.
- **스왑은 켠 채로 K8s를 운영한다(LimitedSwap)**: disable_swap이 주석 처리되고 enable_swap이 활성인 것은 의도다. k8s_master/k8s_worker가 `swap_file_path` 활성 상태를 assert하므로 disable_swap을 켜면 k8s 플레이 검증이 실패한다.
- **kubeadm init/join은 1회성**(`creates=` 가드): `pod_subnet` 등 클러스터 설정을 바꿔도 재실행으로 반영되지 않는다 → k8s_reset으로 해체 후 재구축. Cilium 의 `routingMode`/ipam 도 helm upgrade 로는 기존 노드의 라우트·BPF 맵이 남아 재구축 대상이다.
- **kafka_prereq_ansible.yml**: ⚠ **Kafka 브로커는 K8s 로 이관됐다** — Helm 차트 `301-kafka`(StatefulSet, hostNetwork + 노드 로컬 디스크 — 오퍼레이터 없음)가 구 kafka·kafka_topics 롤을 승계했다. 이 플레이북에 남은 범위는 **그 차트의 정적 local PV가 가리키는 노드 디렉토리 생성뿐**이다(`/data/kafka-broker` = log.dirs · `/data/kafka-controller` = metadata.log.dir — longhorn_prereq의 데이터 경로와 같은 성격의, 차트가 모델링하지 못하는 수동 단계). 소유·모드를 명시하는 이유는 apache/kafka 컨테이너가 비루트(appuser, fsGroup 0)로 떠서 그룹 쓰기가 없으면 로그 디렉토리를 못 만들고 CrashLoopBackOff가 되기 때문이고, 모드가 `2770`(setgid)인 이유는 kubelet 의 fsGroup 처리가 켜는 비트와 같게 두어 재실행마다 재귀 chown 이 반복되지 않게 하기 위함이다. **노드를 늘릴 때도 이 플레이북이 먼저다** — 디렉토리 없이 `values.common.yaml` 의 `global.kafka.brokers` 표에만 추가하면 그 노드의 PV가 마운트에 실패해 파드가 멈춘다. 실행 순서: **kafka_prereq → helm install 301-kafka**. 토픽은 301-kafka의 hook Job `kafka-topics`가, 브로커↔노드 고정표(ID·노드·IP)는 저장소 루트 `values.common.yaml` 의 `global.kafka.brokers`가 승계했다 — 그 IP 는 이 저장소 `host.yml` 과 같아야 한다.
- **hadoop_prereq_ansible.yml**: `kafka_prereq` 와 같은 성격 — Helm 차트 `301-hadoop`(HDFS HA, StatefulSet 4종 = zookeeper·journalnode·namenode+zkfc·datanode, hostNetwork + 노드 로컬 디스크)이 정적 local PV 로 가리키는 **노드 디렉토리 4종 생성뿐**이다(`/data/hadoop-zookeeper`·`/data/hadoop-journalnode`·`/data/hadoop-namenode`·`/data/hadoop-datanode`). 소유·모드(`root:root 2770`)를 kafka 와 같게 두는 이유도 같다 — 컨테이너가 비루트(uid 1000 hadoop, fsGroup 0)라 그룹 쓰기가 필요하고, setgid 를 유지해야 kubelet 의 `OnRootMismatch` 가 재귀 chown 을 건너뛴다. ⚠ 이 모드는 차트의 `dfs.datanode.data.dir.perm=770` 과 **한 쌍**이라 한쪽만 바꾸면 DataNode 가 chmod 에 실패한다. 디렉토리는 3노드 전부에 만들지만 NameNode PV 는 `global.hadoop.namenode.nodeNames`(`ap`·`s1`) 2개뿐이다 — s2 의 namenode 디렉토리는 의도적으로 비어 있다. 실행 순서: **hadoop_prereq → helm install 301-hadoop**.
- **airflow_repo_prereq_ansible.yml**: 304-airflow 가 **읽기 전용 hostPath** 로 마운트하는 DAG/코드 디렉토리 `/data/airflow-repo`(root:root **0755** — 컨테이너는 uid 50000 으로 읽기만 하므로 kafka/hadoop 의 2770 이 아니다) 생성 + 컨트롤 노드 원본(`airflow_repo_src` = `/project/data_pipeline/data_layer_airflow`)의 3노드 rsync. **DAG 반영 = `sync` 태그**(재빌드·helm upgrade 없음; 태스크 파드는 자기가 뜬 노드를 읽으므로 3노드 전부 끝나야 반영 완료). rsync 는 `synchronize` 가 아니라 `command` + `delegate_to: localhost` 다 — synchronize 는 rsync 가 스스로 접속해 비밀번호 SSH(ansible_user=project)를 못 타고, 이 랩은 root 키 SSH 가 노드 간에 열려 있다(Ubuntu_Servers 간 교환은 ssh_keygen 롤 — 컨트롤 노드가 그 그룹 밖이면 노드 `authorized_keys` 에 컨트롤 노드 root 키를 따로 넣어야 rsync 가 붙는다). `--chmod=Da+rx,Fa+r`(원본 0700 이 노드로 옮겨 오면 DAG 0개) · `--delay-updates`/`--delete-delay`(반쯤 바뀐 트리를 30초 파서가 보는 창 제거) · `*.env`·`logs/`·`.git/` 제외(Secret 값 원본·WebHDFS 로그)는 롤이 소유한다. 경로는 `group_vars/airflow.yml` 의 `airflow_repo_dir` ↔ `304-airflow/values.yaml` 의 `repo.hostPath` 가 글자 그대로 같아야 한다. 검증은 `dags/` 의 존재 + 타인 읽기·실행 비트(없으면 파드는 뜨는데 DAG 0개). 실행 순서: **airflow_repo_prereq → helm install 304-airflow**.
- **buildkitd_ansible.yml**: `buildkitd` 그룹(ap·s2 — 빌드 머신)에 buildkitd + buildctl 설치(`/application/buildkit/v<버전>` + `/usr/local/bin` 링크 — helm 롤의 `/application/helm` 과 같은 컨벤션). K8s 노드에 docker 를 깔지 않는 방침이라 data_pipeline `build_and_push.sh` 의 buildctl 경로(BUILDER 자동 감지)가 이 데몬으로 빌드+push 한다. runc 는 없으면 설치·있으면 그대로(state=present — containerd 롤이 hold 한 짝 버전을 건드리지 않는다), push 인증은 `/root/.docker/config.json`(⚠ `buildkit_registry_password` 는 Terraform 200-harbor `secrets.auto.tfvars` 의 `harbor_admin_password` 와 글자 그대로 같아야 한다). ⚠ `buildkit_registry` 는 `data-layer-harbor:80` — 포트 없는 이름은 이미지 참조 파서가 docker.io 네임스페이스로 정규화해 push 가 Docker Hub 로 가므로 `:80` 이 필수고, build_and_push.sh 의 REGISTRY 기본값·`values.common.yaml` 의 `global.harborRegistry` 와 글자 그대로 같아야 한다. HTTP Harbor 는 스크립트가 `registry.insecure=true` 로 처리하므로 이 롤은 인증 파일만 만든다. 사용 시점은 200-harbor apply 이후다.
- `containerd_insecure_registries` 값은 certs.d 디렉토리명이 되므로 이미지 주소의 host:port(`data-layer-harbor:80`)와 **글자 그대로** 일치해야 하고, `data-layer-harbor` 이름은 etc_hosts 롤이 /etc/hosts에 등록해야 풀린다(etc_hosts는 /etc/hosts를 통째로 재생성). harbor는 VIP 계열이므로 이미지 pull은 MetalLB 인그레스 VIP를 경유한다. 노드 containerd 는 이 목록만 신뢰하므로 docker.io 직접 pull 은 불가능하다 — data_pipeline 이 FROM 한 줄짜리 미러 이미지까지 Harbor 로 올리는 이유.
- **etc_hosts 롤의 data-layer 이름은 두 계열로 갈린다 — 기준은 '장애 전환을 누가 하느냐'다.** `data_layer_dns_names`(현재 `data-layer-neo4j` 하나 — minio-console 은 MinIO 가 301-minio 로 옮겨 가며 뺐다)는 이름 하나가 노드 IP 전부를 갖고 전환을 클라이언트가 한다(죽은 IP면 TCP 타임아웃 대기). `data_layer_vip_dns_names`(harbor·kafka-ui·airflow·api·grafana·prometheus·headlamp)는 전부 `ingress_vip` 하나를 가리키고 전환은 MetalLB가 한다. (postgres 외부 접속은 hosts 이름 없이 전용 VIP — Terraform 102-ingress `postgres_vip`:5432 — 로 한다.) **한 이름을 두 계열에 동시에 넣지 말 것** — 클라이언트가 아무 데나 붙어 증상이 매번 달라진다. 검증 assert도 기대 개수가 달라(이름 수 × 노드 수 vs 이름 수 × 1줄) 태스크가 분리돼 있으니 합치지 말 것. `ingress_vip`(192.168.56.240)는 Terraform `102-ingress` 의 `ingress_vip`·Helm `values.common.yaml` 의 `global.ingressVip`(305-api hostAliases 가 쓴다)와 **글자 그대로** 같아야 한다.
- /etc/hosts는 인그레스 전환·노드 IP 변경 때 `--tags etc_hosts`(또는 `start_configuration.sh <경로> etc_hosts`)로 단독 갱신한다. **접속하는 PC의 hosts는 이 롤의 관리 대상이 아니다**(대상은 노드 3대뿐) — 수동 관리이며 형식은 README 참조.
- kubelet `--node-ip`와 Cilium의 `devices`(`cilium_device`=eth1)는 host-only NIC(192.168.56.x)에 고정 — VirtualBox NAT IP(10.0.2.15)가 잡히는 것을 방지한다.
- CNI는 Cilium(eBPF + Native Routing + kube-proxy replacement, Hubble·Hubble UI 활성)이며 `k8s_cilium` 롤이 담당한다. kubeadm-config의 `skipPhases: addon/kube-proxy`와 Cilium values의 `kubeProxyReplacement: true`는 **한 쌍**이라 한쪽만 바꾸면 클러스터가 동작하지 않는다.

## 커밋 컨벤션 ([COMMIT_CONVENTION.md](COMMIT_CONVENTION.md))

- `type(scope): subject` — 제목은 한국어, 50자 이내, 마침표 없음, 명령형("추가" ⭕ / "추가함" ❌). 한 커밋에는 한 가지 변경만.
- type: feat / fix / docs / refactor / style / test / chore / ci. scope 예: containerd, inventory, playbook (생략 가능).
- GitLab 이슈 연동: 제목에 `#번호`, 머지 시 자동 종료는 본문에 `Closes #번호`.
- 원격은 GitHub(`sy0218/Infrastructure-as-Code-Ansible`, main). 2026-09-04 현재 airflow_repo_prereq 롤·플레이북·bin 스크립트·`group_vars/airflow.yml` 은 **아직 커밋되지 않은 untracked** 상태이고 host.yml·Ubuntu_Servers.yml·README·etc_hosts.md 도 수정분이 미커밋이다.
