# 📨 Kafka 노드 선행작업 (kafka_prereq)
- K8s 로 이관된 Kafka(Terraform 저장소 `301-kafka`, Strimzi)가 정적 local PV 로 쓰는 **노드 디렉토리 2개**를 만든다 — `/data/kafka-controller`(KRaft 메타데이터) · `/data/kafka-broker`(로그 세그먼트).
- 서버 설치가 아니다: 구 kafka 롤(systemd 설치)은 퇴역했고, 이 롤은 `minio_prereq`·`longhorn_prereq` 와 같은 성격의 '도구가 모델링 못 하는 노드 선행작업'만 남긴 것이다.
- 멱등이라 재실행이 안전하다 — 디렉토리가 이미 맞으면 아무것도 바꾸지 않는다.
- ⚠ 경로는 `group_vars/kafka.yml` 이 결정하며, `301-kafka` values(`kafka.broker.dataPath`·`kafka.controller.dataPath`)와 글자 그대로 같아야 한다.
- ⚠ **구 `/data/kafka` 와 겹치면 안 된다** — `kafka_remove` 롤이 그 경로를 통째로 지우므로, 겹치면 롤 재실행 한 번이 전 노드 데이터 동시 소실이다. 이 롤의 마지막 assert 가 그 사고를 막는다.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# Kafka 노드 선행작업 → Strimzi 로컬 PV 디렉토리 준비
# -----------------------------------------------------
# 브로커는 K8s(Terraform 저장소 301-kafka, Strimzi)로 이관됐다 — 이 롤은 그 차트의
# 정적 local PV 가 가리키는 노드 디렉토리만 만든다(minio_prereq 의 드라이브,
# longhorn_prereq 의 /data/longhorn 과 같은 성격의, 도구가 모델링 못 하는 수동 단계).
#
# [구조] 노드당 2개 — 컨트롤러(KRaft 메타데이터)와 브로커(로그 세그먼트)가 분리돼 있다
#   /data/kafka-controller ──local PV──→ data-layer-controller-10N
#   /data/kafka-broker     ──local PV──→ data-layer-broker-N
#
# ⚠ 구 /data/kafka 는 건드리지 않는다 — 그건 systemd 브로커의 데이터이고
#   정리 주체는 kafka_remove 롤이다. 두 경로가 겹치지 않는 것이 이 설계의 핵심이다.
#
# [주의] minio_prereq 와 달리 **소유·모드를 지정한다** — Strimzi 컨테이너는 비루트(uid 1001)라
#   그룹 쓰기 권한이 없으면 로그 디렉토리를 못 만들고 CrashLoopBackOff 가 된다.
#
# 멱등이라 재실행이 안전하다 — 디렉토리가 이미 맞으면 아무것도 바꾸지 않는다.
# -----------------------------------------------------

# =========================================================================
# 1. 디렉토리 생성 (file 모듈 자체가 멱등)
# =========================================================================
- name: "Create kafka local PV directories"
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ kafka_data_owner }}"
    group: "{{ kafka_data_group }}"
    mode: "{{ kafka_data_mode }}"
  loop:
    - "{{ kafka_controller_data_dir }}" # KRaft 쿼럼 로그
    - "{{ kafka_broker_data_dir }}" # 토픽 로그 세그먼트

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
# 디렉토리가 실제로 존재하고 그룹 쓰기가 열려 있는지 — 둘 중 하나만 어긋나도
# 증상이 "파드가 안 뜬다" 로만 보여서 원인을 찾는 데 시간이 걸린다.
- name: "Check kafka local PV directories"
  stat:
    path: "{{ item }}"
  loop:
    - "{{ kafka_controller_data_dir }}"
    - "{{ kafka_broker_data_dir }}"
  register: kafka_dirs
  changed_when: false
  failed_when: false

- name: "Assert kafka local PV directories are usable"
  assert:
    that:
      - item.stat.exists
      - item.stat.isdir
      - item.stat.wgrp # 그룹 쓰기 — 컨테이너가 gid 0 으로 붙는다
    success_msg: "Good!.. | dir ready: {{ item.item }} (mode {{ item.stat.mode | default('?') }})"
    fail_msg: "ERROR!.. | dir NOT usable: {{ item.item }} → 301-kafka 파드가 local PV 마운트/쓰기에 실패해 기동하지 못한다"
  loop: "{{ kafka_dirs.results }}"
  loop_control:
    label: "{{ item.item }}"

# 구 브로커 데이터와 경로가 겹치지 않는지 — 겹치면 kafka_remove 재실행 한 번이
# 전 노드의 Strimzi 데이터를 동시에 지운다. 사람이 values 를 잘못 고쳤을 때 여기서 걸린다.
- name: "Assert kafka data dirs do not collide with legacy /data/kafka"
  assert:
    that:
      - not (kafka_broker_data_dir == '/data/kafka' or kafka_broker_data_dir.startswith('/data/kafka/'))
      - not (kafka_controller_data_dir == '/data/kafka' or kafka_controller_data_dir.startswith('/data/kafka/'))
    success_msg: "Good!.. | 구 /data/kafka 와 경로가 분리돼 있다 (kafka_remove 재실행 안전)"
    fail_msg: "ERROR!.. | 경로가 /data/kafka 아래다 → kafka_remove 롤이 Strimzi 데이터를 지운다. group_vars/kafka.yml 과 301-kafka values 를 함께 고칠 것"
```
---
<br>

## 📌 설계 근거
- **소유자를 root 로 두고 그룹 쓰기(0770)를 연다.** Strimzi 파드는 `fsGroup: 0` + `fsGroupChangePolicy: OnRootMismatch` 로 뜨는데, 최상위 소유가 이미 맞으면 재귀 chown 을 건너뛴다 — 데이터가 쌓인 뒤에도 기동이 느려지지 않는다. (`minio_prereq` 가 소유자를 안 건드리는 것은 304-minio 파드가 root 라서다 — 전제가 다르다.)
- **컨트롤러와 브로커 디렉토리를 나눈다.** `301-kafka` 가 KafkaNodePool 을 둘로 나눴고, PV 도 역할별로 크기가 다르다(브로커 10Gi / 컨트롤러 2Gi). 같은 디렉토리를 쓰면 두 PV 가 같은 경로를 가리켜 데이터가 섞인다.
- **경로 충돌 assert 를 롤 안에 둔다.** 같은 규칙을 `301-kafka/values.schema.json` 이 `not` 패턴으로도 막지만, 두 저장소가 따로 움직이므로 양쪽에서 막는다.

## 🔗 실행 순서
```
1) kafka_remove_ansible.yml   — 구 systemd 브로커 제거 (⚠ /data/kafka 삭제 — 백업 먼저)
2) 이 플레이북                 — 로컬 PV 디렉토리 준비(멱등)
3) helm install strimzi 105-strimzi   — 오퍼레이터 + CRD
4) helm install kafka 301-kafka       — Kafka CR / 노드풀 / 토픽
```
⚠ 1) 과 2) 의 순서를 바꾸면 `kafka_remove` 가 방금 만든 디렉토리를 지우지는 않지만(경로가 다르다), 구 브로커가 살아 있는 채로 새 브로커가 떠서 클라이언트가 어느 쪽에 붙었는지 알 수 없게 된다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [kafka_prereq : Assert kafka local PV directories are usable] ****
ok: [ap] => (item=/data/kafka-controller) => {
    "msg": "Good!.. | dir ready: /data/kafka-controller (mode 0770)"
}
ok: [ap] => (item=/data/kafka-broker) => {
    "msg": "Good!.. | dir ready: /data/kafka-broker (mode 0770)"
}

TASK [kafka_prereq : Assert kafka data dirs do not collide with legacy /data/kafka] ****
ok: [ap] => {
    "msg": "Good!.. | 구 /data/kafka 와 경로가 분리돼 있다 (kafka_remove 재실행 안전)"
}
```
