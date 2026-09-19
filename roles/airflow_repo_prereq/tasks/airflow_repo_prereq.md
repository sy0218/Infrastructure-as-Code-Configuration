# 🌬️ Airflow 노드 선행작업 (airflow_repo_prereq)
- K8s 의 Airflow(Terraform 저장소 `304-airflow`, Helm 차트)가 **읽기 전용 hostPath 로 마운트하는 노드 디렉토리** `/project/data_pipeline/data_layer_airflow` 를 만들고, 컨트롤 노드의 `data_pipeline/data_layer_airflow` 원본을 3노드에 rsync 한다.
- DAG·커스텀 패키지는 이미지에 없다 — 코드 반영은 재빌드가 아니라 **이 롤의 `sync` 태그**다(dag-processor 가 30초마다 다시 훑는다).
- 멱등이라 재실행이 안전하다. `kafka_prereq`·`hadoop_prereq` 와 같은 성격의 '차트가 모델링 못 하는 노드 선행작업'이다.
- ⚠ 경로는 `group_vars/airflow.yml` 이 결정하며, `304-airflow/values.yaml` 의 `repo.hostPath` 와 글자 그대로 같아야 한다.
---
<br>

## 🧩 main.yml
1. `/project/data_pipeline/data_layer_airflow` 생성 — root:root **0755**(kafka/hadoop 의 2770 과 다르다: 컨테이너는 uid 50000 으로 읽기만 하고 쓰는 주체는 rsync 뿐이라 그룹 쓰기가 필요 없다).
2. `sync` 태그 — 컨트롤 노드에서 `rsync --archive --delete --delay-updates --delete-delay --chmod=Da+rx,Fa+r` 로 `root@<노드>:/project/data_pipeline/data_layer_airflow/` 에 뿌린다(`synchronize` 모듈은 rsync 가 스스로 접속해야 해서 비밀번호 SSH 를 못 타므로 `command` + `delegate_to: localhost` 다 — 컨트롤 노드 → 노드 root 키 SSH 가 전제).
3. 검증 — `dags/` 가 있고 남 읽기(o+rx)가 열려 있는지. 없으면 파드가 `hostPath type check failed` 로 안 뜨고, 못 읽으면 파드는 뜨는데 **DAG 만 0개**가 된다.

## 📌 설계 근거
- **`--chmod=Da+rx,Fa+r` 를 빼지 말 것.** `--archive` 는 원본 모드를 그대로 옮긴다 — 원본이 0700 이면 노드도 0700 이 되어 uid 50000 이 진입조차 못 한다. 더하기만 하므로 원본은 건드리지 않는다.
- **`--delay-updates` 를 빼지 말 것.** 파일을 하나씩 갈아 끼우면 반쯤 바뀐 순간을 dag-processor 가 파싱해 DAG 이 잠깐 통째로 사라진다.
- **`*.env` 는 제외.** `airflow.env` 는 Secret `airflow-env` 의 값 원본 문서라 노드 디스크에 평문으로 남길 이유가 없다.
- **전 노드에 마쳐야 끝난 것이다.** 태스크 파드는 자기가 뜬 노드의 디렉토리를 읽는다 — 일부만 동기화된 동안에는 파서와 실행 주체가 다른 코드를 본다.

## 🔗 실행 순서
```
1) 이 플레이북 all  — 디렉토리 + 첫 동기화
2) helm install 304-airflow (Ansible 범위 밖)
3) DAG 수정 때마다 — 이 플레이북 sync
```

## ✅ 실행 예시
```bash
bin/start_airflow_repo_prereq.sh /my_project/Infrastructure-as-Code-Ansible all    # 최초
bin/start_airflow_repo_prereq.sh /my_project/Infrastructure-as-Code-Ansible sync   # DAG 반영
```
