# 🐘 Hadoop 노드 선행작업 (hadoop_prereq)
- K8s 로 올라가는 HDFS HA(Terraform 저장소 `301-hadoop`, StatefulSet 4종)가 정적 local PV 로 쓰는 **노드 디렉토리 4개**를 만든다 — `/data/hadoop-zookeeper`(HA 쿼럼) · `/data/hadoop-journalnode`(공유 edits) · `/data/hadoop-namenode`(fsimage) · `/data/hadoop-datanode`(블록).
- 서버 설치가 아니다: `kafka_prereq` 와 똑같은 성격의 '차트가 모델링 못 하는 노드 선행작업'만 담당한다. Hadoop 기동·설정은 전부 차트가 한다.
- 멱등이라 재실행이 안전하다 — 디렉토리가 이미 맞으면 아무것도 바꾸지 않는다.
- ⚠ 경로는 `group_vars/hadoop.yml` 이 결정하며, `301-hadoop` values(`hadoop.<구성요소>.path`)와 글자 그대로 같아야 한다.
---
<br>

## 🧩 main.yml
```yaml
# =========================================================================
# Hadoop 노드 선행작업 → 301-hadoop(StatefulSet) 로컬 PV 디렉토리 준비
# =========================================================================


# -------------------------------------------------------------------------
# 1. 디렉토리 생성 (file 모듈 자체가 멱등)
# -------------------------------------------------------------------------
- name: "Create hadoop local PV directories"
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ hadoop_data_owner }}"
    group: "{{ hadoop_data_group }}"
    mode: "{{ hadoop_data_mode }}"
  loop:
    - "{{ hadoop_zookeeper_data_dir }}" # ZooKeeper 앙상블 데이터 (HA 쿼럼)
    - "{{ hadoop_journalnode_data_dir }}" # NameNode 공유 edits 로그
    - "{{ hadoop_namenode_data_dir }}" # fsimage / edits
    - "{{ hadoop_datanode_data_dir }}" # HDFS 블록

# -------------------------------------------------------------------------
# 2. 검증
# -------------------------------------------------------------------------
# 디렉토리가 실제로 존재하고 그룹 쓰기가 열려 있는지
# 둘 중 하나만 어긋나도
# → 증상이 "파드가 안 뜬다" 로만 보여서 원인을 찾는 데 시간이 걸린다.
# -------------------------------------------------------------------------
- name: "Check hadoop local PV directories"
  stat:
    path: "{{ item }}"
  loop:
    - "{{ hadoop_zookeeper_data_dir }}"
    - "{{ hadoop_journalnode_data_dir }}"
    - "{{ hadoop_namenode_data_dir }}"
    - "{{ hadoop_datanode_data_dir }}"
  register: hadoop_dirs
  changed_when: false
  failed_when: false

- name: "Assert hadoop local PV directories are usable"
  assert:
    that:
      - item.stat.exists
      - item.stat.isdir
      - item.stat.wgrp # 그룹 쓰기 — 컨테이너가 uid 1000 + gid 0 으로 붙는다
    success_msg: "Good!.. | dir ready: {{ item.item }} (mode {{ item.stat.mode | default('?') }})"
    fail_msg: "ERROR!.. | dir NOT usable: {{ item.item }} → 301-hadoop 파드가 local PV 마운트/쓰기에 실패해 기동하지 못한다"
  loop: "{{ hadoop_dirs.results }}"
  loop_control:
    label: "{{ item.item }}"
```
---
<br>

## 📌 group_vars 예시
```yaml
# -----------------------------------------------------
# Hadoop 데이터 저장 경로 (구성요소 4종 = STS 4종)
# hadoop_zookeeper_data_dir    → ZooKeeper 앙상블 데이터(myid·스냅샷)
# hadoop_journalnode_data_dir  → NameNode 공유 edits 로그
# hadoop_namenode_data_dir     → fsimage / edits (ap·s1 에만 PV 가 있다)
# hadoop_datanode_data_dir     → HDFS 블록
# -----------------------------------------------------
hadoop_zookeeper_data_dir: /data/hadoop-zookeeper
hadoop_journalnode_data_dir: /data/hadoop-journalnode
hadoop_namenode_data_dir: /data/hadoop-namenode
hadoop_datanode_data_dir: /data/hadoop-datanode


# -----------------------------------------------------
# 디렉토리 권한
# Hadoop 컨테이너가 비루트(uid 1000 hadoop)로 실행되므로 root 소유 + 그룹 쓰기 권한 적용
# 2770(setgid): 하위 파일/디렉토리도 root 그룹 권한을 유지
# -----------------------------------------------------
hadoop_data_owner: root
hadoop_data_group: root
hadoop_data_mode: '2770'
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 디렉토리 생성
- `file` 모듈은 그 자체가 멱등이라 가드가 필요 없다 — 경로·소유·모드가 이미 맞으면 `changed=0` 이다.
- **네 경로를 절대 합치지 않는다.** `301-hadoop` 은 구성요소마다 PV 를 따로 만들고(namenode 2 + journalnode 3 + zookeeper 3 + datanode 3 = 11개) 용량도 다르다(5Gi / 2Gi / 2Gi / 20Gi). 같은 디렉토리를 가리키면 PV 여러 개가 한 경로를 공유해 메타데이터와 블록이 섞인다.
- `namenode` 는 차트의 `nodeNames` 가 `["ap", "s1"]` 이라 s2 에는 PV 가 없다. 그래도 디렉토리는 3노드에 똑같이 만든다 — 빈 디렉토리는 무해하고, NameNode 를 옮기거나 늘릴 때 선행작업을 다시 챙기지 않아도 된다.
---
### 2️⃣ 검증
- `stat` 으로 조회하고(`changed_when: false`) `assert` 로 판정하는 하우스 패턴. `failed_when: false` 를 준 이유는 경로가 없을 때 stat 이 먼저 죽어 버리면 **어느 디렉토리가 문제인지** 가 assert 메시지로 안 나오기 때문이다.
- 판정 조건은 존재·디렉토리 여부에 더해 **그룹 쓰기(`wgrp`)** 다. 이 셋 중 하나만 어긋나도 증상은 "파드가 안 뜬다" 하나로만 보여서 원인을 찾는 데 시간이 걸린다.
---
<br>

## 📌 설계 근거
- **소유자를 root 로 두고 그룹 쓰기 + setgid(2770)를 연다** — `kafka_prereq` 와 같은 값·같은 이유다. 301-hadoop 파드 4종이 전부 `fsGroup: 0` + `fsGroupChangePolicy: OnRootMismatch` 로 뜨는데, 최상위 소유가 이미 맞으면 kubelet 이 재귀 chown 을 건너뛴다 — 블록이 쌓인 DataNode 도 기동이 느려지지 않는다. setgid 는 kubelet 이 fsGroup 처리 때 켜는 비트라 여기서 0770 으로 되돌리면 재실행마다 벗겨진다.
- 컨테이너는 비루트 **uid 1000(hadoop)** 으로 뜬다 — 그룹 쓰기가 없으면 디렉토리를 못 만들어 CrashLoopBackOff 가 된다. DataNode 는 자기 데이터 디렉토리에 chmod 를 시도하는데(소유자가 root 라 실패한다) 차트가 `dfs.datanode.data.dir.perm=770` 으로 노드 디렉토리 모드와 같게 맞춰 두어 chmod 자체가 일어나지 않는다 — **이 모드를 바꾸면 차트 값도 같이 바꿔야 한다**.

## 🔗 실행 순서
```
1) 이 플레이북 — 로컬 PV 디렉토리 준비(멱등)
```
Hadoop 차트(`301-hadoop`) 설치는 Ansible 범위 밖이다 — 엔지니어가 수동으로 한다. 다만 **디렉토리가 먼저**여야 한다 — 없으면 그 노드의 PV 가 마운트에 실패해 파드가 멈춘다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [hadoop_prereq : Assert hadoop local PV directories are usable] ****
ok: [ap] => (item=/data/hadoop-zookeeper) => {
    "msg": "Good!.. | dir ready: /data/hadoop-zookeeper (mode 2770)"
}
ok: [ap] => (item=/data/hadoop-journalnode) => {
    "msg": "Good!.. | dir ready: /data/hadoop-journalnode (mode 2770)"
}
ok: [ap] => (item=/data/hadoop-namenode) => {
    "msg": "Good!.. | dir ready: /data/hadoop-namenode (mode 2770)"
}
ok: [ap] => (item=/data/hadoop-datanode) => {
    "msg": "Good!.. | dir ready: /data/hadoop-datanode (mode 2770)"
}
```
