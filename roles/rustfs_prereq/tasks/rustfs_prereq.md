# 🪣 RustFS 노드 선행작업 (rustfs_prereq)
- K8s 로 올라가는 RustFS 3노드(Terraform 저장소 `301-rustfs`, StatefulSet — EC 2+1)가 정적 local PV 로 쓰는 **노드 디렉토리 1개**를 만든다 — `/data/rustfs`(EC 조각 + 객체 메타데이터).
- 서버 설치가 아니다: `kafka_prereq`·`hadoop_prereq`·`elasticsearch_prereq` 와 똑같은 성격의 '차트가 모델링 못 하는 노드 선행작업'만 담당한다. RustFS 기동·설정은 전부 차트가 한다.
- 멱등이라 재실행이 안전하다 — 디렉토리가 이미 맞으면 아무것도 바꾸지 않는다.
- ⚠ 경로는 `group_vars/rustfs.yml` 이 결정하며, `301-rustfs` values(`data.path`)와 글자 그대로 같아야 한다.
---
<br>

## 🧩 main.yml
```yaml
# =========================================================================
# RustFS 노드 선행작업 → 301-rustfs(StatefulSet) 로컬 PV 디렉토리 준비
# =========================================================================


# -------------------------------------------------------------------------
# 1. 디렉토리 생성 (file 모듈 자체가 멱등)
# -------------------------------------------------------------------------
- name: "Create rustfs local PV directory"
  file:
    path: "{{ rustfs_data_dir }}"
    state: directory
    owner: "{{ rustfs_data_owner }}"
    group: "{{ rustfs_data_group }}"
    mode: "{{ rustfs_data_mode }}"

# -------------------------------------------------------------------------
# 2. 검증
# -------------------------------------------------------------------------
# 디렉토리가 실제로 존재하고 그룹 쓰기가 열려 있는지
# 둘 중 하나만 어긋나도
# → 증상이 "파드가 안 뜬다" 로만 보여서 원인을 찾는 데 시간이 걸린다.
# -------------------------------------------------------------------------
- name: "Check rustfs local PV directory"
  stat:
    path: "{{ rustfs_data_dir }}"
  register: rustfs_dir
  changed_when: false
  failed_when: false

- name: "Assert rustfs local PV directory is usable"
  assert:
    that:
      - rustfs_dir.stat.exists
      - rustfs_dir.stat.isdir
      - rustfs_dir.stat.wgrp # 그룹 쓰기 — 컨테이너가 uid 10001 + 보조 그룹 0(fsGroup) 으로 붙는다
    success_msg: "Good!.. | dir ready: {{ rustfs_data_dir }} (mode {{ rustfs_dir.stat.mode | default('?') }})"
    fail_msg: "ERROR!.. | dir NOT usable: {{ rustfs_data_dir }} → 301-rustfs 파드가 local PV 마운트/쓰기에 실패해 기동하지 못한다"
```
---
<br>

## 📌 group_vars 예시
```yaml
# -----------------------------------------------------
# RustFS 데이터 저장 경로 (EC 조각 + 객체 메타데이터) — 301-rustfs values 의 data.path 와 같은 값
# -----------------------------------------------------
rustfs_data_dir: /data/rustfs


# -----------------------------------------------------
# 디렉토리 권한
# RustFS 컨테이너가 비루트(uid 10001 rustfs)로 뜨고 파드가 보조 그룹 0(fsGroup)을 붙이므로 root 소유 + 그룹 쓰기 권한 적용
# 2770(setgid): 하위 파일/디렉토리도 root 그룹 권한을 유지
# -----------------------------------------------------
rustfs_data_owner: root
rustfs_data_group: root
rustfs_data_mode: '2770'
```
---
<br>

## 📌 설계 근거
- **소유자를 root 로 두고 그룹 쓰기 + setgid(2770)를 연다** — `kafka_prereq`·`hadoop_prereq`·`elasticsearch_prereq` 와 같은 값·같은 이유다. 301-rustfs 파드가 `fsGroup: 0` + `fsGroupChangePolicy: OnRootMismatch` 로 뜨는데, 최상위 소유가 이미 맞으면 kubelet 이 재귀 chown 을 건너뛴다. setgid 는 kubelet 이 fsGroup 처리 때 켜는 비트라 여기서 0770 으로 되돌리면 재실행마다 벗겨진다.
- 컨테이너는 비루트 **uid 10001(rustfs)** 로 뜨고, 파드가 보조 그룹 0(fsGroup)을 붙여 그룹 권한으로 쓴다 — 그룹 쓰기가 없으면 데이터 디렉토리에 아무것도 못 써서 CrashLoopBackOff 가 된다.
- 디렉토리는 3노드 전부에 만든다 — 차트 `nodeNames` 가 3노드라 PV 도 3개이고, EC 2+1 이 노드마다 조각을 하나씩 둔다. RustFS 는 풀 단위로만 늘어나 기존 풀에 노드 1대를 끼워 넣을 수 없다 — 노드를 늘리면 차트에 새 풀을 설계하고, 그때도 이 플레이북이 먼저다.
- ⚠ etcd·Kafka 와 같은 디스크다 — 설정·로그는 쓰기량이 아주 작아 그대로 두지만, 이 디렉토리로 대량 쓰기·벤치를 하지 않는다(쓰기 부하가 etcd fsync 를 늦춘 사고가 있었다).

## 🔗 실행 순서
```
1) 이 플레이북 — 로컬 PV 디렉토리 준비(멱등)
```
RustFS 차트(`301-rustfs`) 배포는 Ansible 범위 밖이다 — Argo CD 앱이라 첫 설치는 MR 단계에서 손으로 1회, 이후는 GitLab CD 가 한다. 다만 **디렉토리가 먼저**여야 한다 — 없으면 그 노드의 PV 가 마운트에 실패해 파드가 멈춘다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [rustfs_prereq : Assert rustfs local PV directory is usable] **************
ok: [ap] => {
    "msg": "Good!.. | dir ready: /data/rustfs (mode 2770)"
}
```
