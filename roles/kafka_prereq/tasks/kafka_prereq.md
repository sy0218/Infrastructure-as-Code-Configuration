# 📨 Kafka 노드 선행작업 (kafka_prereq)
- K8s 로 이관된 Kafka(Terraform 저장소 `301-kafka`, StatefulSet)가 정적 local PV 로 쓰는 **노드 디렉토리 2개**를 만든다 — `/data/kafka-controller`(KRaft 메타데이터) · `/data/kafka-broker`(로그 세그먼트).
- 서버 설치가 아니다: 구 kafka 롤(systemd 설치)은 퇴역했고, 이 롤은 `minio_prereq`·`longhorn_prereq` 와 같은 성격의 '도구가 모델링 못 하는 노드 선행작업'만 남긴 것이다.
- 멱등이라 재실행이 안전하다 — 디렉토리가 이미 맞으면 아무것도 바꾸지 않는다.
- ⚠ 경로는 `group_vars/kafka.yml` 이 결정하며, `301-kafka` values(`kafka.data.path`·`kafka.metadata.path`)와 글자 그대로 같아야 한다.
---
<br>

## 🧩 main.yml
```yaml
# =========================================================================
# Kafka 노드 선행작업 → 301-kafka(StatefulSet) 로컬 PV 디렉토리 준비
# =========================================================================


# -------------------------------------------------------------------------
# 1. 디렉토리 생성 (file 모듈 자체가 멱등)
# -------------------------------------------------------------------------
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

# -------------------------------------------------------------------------
# 2. 검증
# -------------------------------------------------------------------------
# 디렉토리가 실제로 존재하고 그룹 쓰기가 열려 있는지
# 둘 중 하나만 어긋나도
# → 증상이 "파드가 안 뜬다" 로만 보여서 원인을 찾는 데 시간이 걸린다.
# -------------------------------------------------------------------------
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
```
---
<br>

## 📌 설계 근거
- **소유자를 root 로 두고 그룹 쓰기 + setgid(2770)를 연다.** setgid 는 kubelet 이 fsGroup 처리 때 켜는 비트라, 여기서 0770 으로 되돌리면 재실행마다 벗겨져 다음 파드 재기동 때 재귀 chown 이 다시 일어난다. Kafka 파드는 `fsGroup: 0` + `fsGroupChangePolicy: OnRootMismatch` 로 뜨는데, 최상위 소유가 이미 맞으면 재귀 chown 을 건너뛴다 — 데이터가 쌓인 뒤에도 기동이 느려지지 않는다. (`minio_prereq` 가 소유자를 안 건드리는 것은 304-minio 파드가 root 라서다 — 전제가 다르다.)
- **세그먼트와 KRaft 메타데이터 디렉토리를 나눈다.** `301-kafka` 가 `log.dirs`(/data/kafka-broker) 와 `metadata.log.dir`(/data/kafka-controller) 을 분리하고, PV 도 둘이며 크기가 다르다(데이터 10Gi / 메타데이터 2Gi). 같은 디렉토리를 쓰면 두 PV 가 같은 경로를 가리켜 데이터가 섞인다.

## 🔗 실행 순서
```
1) 이 플레이북 — 로컬 PV 디렉토리 준비(멱등)
```
Kafka 차트(`301-kafka`) 설치는 Ansible 범위 밖이다 — 엔지니어가 수동으로 한다. 다만 **디렉토리가 먼저**여야 한다 — 없으면 그 노드의 PV 가 마운트에 실패해 파드가 멈춘다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [kafka_prereq : Assert kafka local PV directories are usable] ****
ok: [ap] => (item=/data/kafka-controller) => {
    "msg": "Good!.. | dir ready: /data/kafka-controller (mode 2770)"
}
ok: [ap] => (item=/data/kafka-broker) => {
    "msg": "Good!.. | dir ready: /data/kafka-broker (mode 2770)"
}
```
