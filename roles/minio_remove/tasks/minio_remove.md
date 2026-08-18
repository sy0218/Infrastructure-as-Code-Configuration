# 🧹 MinIO 로컬 설치 제거 (minio_remove)
- 구 MinIO 로컬(systemd) 설치를 걷어낸다 — K8s(Terraform 저장소 `304-minio`, Helm) 컷오버의 선행 단계. 새 서버가 같은 호스트 포트(9000/9001)를 써서 공존이 불가능하다.
- 유닛·환경 파일·바이너리(`/application/minio`)·mc 설정·전용 계정을 제거하고, 드라이브 **내용물**을 비운다(복구 불가 — 새 클러스터가 빈 드라이브를 새로 포맷하고 버킷·시드는 `304-minio` 의 init Job 이 재생성한다).
- 드라이브 **자체**(루프 이미지·마운트·fstab)는 남긴다 — `304-minio` 가 같은 마운트를 hostPath 로 이어받는다(`minio_prereq` 롤이 관리).
- 멱등 — 재실행이 안전하다. 특히 드라이브 비우기는 유닛이 있던 노드에서만 실행되어, 컷오버 후 재실행이 K8s MinIO 의 데이터를 지우지 않는다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# MinIO 로컬(systemd) 설치 제거
#   → 서버가 K8s(Terraform 저장소 304-minio, Helm)로 이관되어 구 설치를 걷어낸다.
#   → 새 서버가 같은 호스트 포트(9000/9001)를 쓰므로
#     304-minio 설치 전에 이 롤이 먼저 완료되어야 한다.
# =====================================================
# [주의] 드라이브 내용물(오브젝트)까지 비운다 — 복구 불가. 이관 결정에 포함된
#   사항이다: 옛 데이터를 인수하지 않고 새 클러스터가 빈 드라이브를 새로 포맷하며,
#   버킷·시드는 304-minio 의 init Job 이, 루트 계정은 300 의 Secret 값이 재생성한다.
# [주의] 드라이브 자체(루프 이미지·마운트·fstab)는 지우지 않는다 — 304-minio 가
#   같은 마운트(/data/minio/diskN)를 hostPath 로 쓴다(minio_prereq 롤이 관리).
# [주의] 일부 경로가 리터럴인 이유 — 서버 설치 변수(설치 루트·계정·시드 스테이징)는
#   구 minio 롤과 함께 퇴역해서 변수 출처가 없다. 값은 퇴역 시점의 group_vars 를
#   그대로 옮긴 것이다(드라이브 변수만 group_vars/minio.yml 에 남아 있어 그것을 쓴다).
# =====================================================


# -----------------------------------------------------
# 1. 유닛 존재 확인 (조회만)
#    → 이미 제거된 노드에서 재실행해도 실패하지 않게 모든 작업의 가드로 쓴다
# -----------------------------------------------------
- name: "Check minio systemd unit exists"
  stat:
    path: /etc/systemd/system/minio.service
  register: minio_unit

# -----------------------------------------------------
# 2. 서비스 중지 + 자동시작 해제
# -----------------------------------------------------
- name: "Stop and disable minio service"
  systemd:
    name: minio
    state: stopped
    enabled: false
  when: minio_unit.stat.exists

# -----------------------------------------------------
# 3. 유닛 파일 제거 + systemd 반영
# -----------------------------------------------------
- name: "Remove minio systemd unit file"
  file:
    path: /etc/systemd/system/minio.service
    state: absent

- name: "Reload systemd after unit removal"
  systemd:
    daemon_reload: true
  when: minio_unit.stat.exists

# -----------------------------------------------------
# 4. 설정/설치/스테이징 경로 제거 (file 모듈 자체가 멱등)
#    → /application/minio 아래에 버전 포함 바이너리(minio.<태그>, mc.<태그>)와
#      심볼릭 링크가 전부 있어 루트째 지운다 (kafka 와 달리 글롭이 필요 없다)
# -----------------------------------------------------
- name: "Remove minio config, install, and staging directories"
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - /etc/default/minio # 자격증명·MINIO_VOLUMES 환경 파일
    - /application/minio # 설치 루트 (bin/minio.<버전>, bin/mc.<버전>, 링크)
    - /data/minio-seed # 시드 스테이징 (시드 주입은 304-minio Job 이 승계)
    - /root/.mc # mc alias 설정 (자격증명 포함)

# -----------------------------------------------------
# 5. 드라이브 내용물 비우기 — 새 클러스터의 빈 드라이브 전제(복구 불가)
#    → 마운트 지점 자체는 남긴다(-mindepth 1). 유닛이 있던 노드에서만 실행:
#      컷오버 후 재실행 시 K8s MinIO 가 쓰고 있는 데이터를 지우지 않기 위한 가드다.
# -----------------------------------------------------
- name: "Wipe minio drive contents"
  shell: "find {{ minio_data_dir }}/{{ item }} -mindepth 1 -print -delete"
  loop: "{{ minio_drives }}"
  register: minio_wipe
  changed_when: minio_wipe.stdout | trim != ""
  when: minio_unit.stat.exists

# -----------------------------------------------------
# 6. 전용 계정 제거
#    → 304-minio 파드는 root 로 뜬다 — 비루트 계정은 systemd 시절의 산물이다
# -----------------------------------------------------
- name: "Remove minio system user"
  user:
    name: minio
    state: absent

# -----------------------------------------------------
# 7. 검증
#    → 포트(9000/9001)는 확인하지 않는다 — K8s 서버(hostNetwork)가 먼저 떠 있으면
#      정당한 점유라 거짓 실패가 된다. 확인 대상은 systemd 경로의 잔재와,
#      304-minio 가 이어받을 드라이브 마운트가 살아 있는지다.
# -----------------------------------------------------
- name: "Check minio service is gone"
  command: systemctl is-active minio
  register: minio_status
  failed_when: false
  changed_when: false

- name: "Check leftover local minio process"
  # K8s 파드의 서버는 컨테이너 이미지 경로(/usr/bin/minio)로 뜬다 —
  # 구 로컬 설치(/application/minio) 경로의 프로세스만 잔재로 취급한다
  shell: "pgrep -af 'minio server' | grep '/application/minio' || true"
  register: minio_leftover
  changed_when: false

# 드라이브가 여전히 마운트돼 있어야 한다 — 304-minio 의 hostPath 가 이어받는다
- name: "Check minio drives are still mounted"
  command: "findmnt -no SOURCE {{ minio_data_dir }}/{{ item }}"
  loop: "{{ minio_drives }}"
  register: minio_mounts
  changed_when: false
  failed_when: false

- name: "Assert local minio is fully removed"
  assert:
    that:
      - minio_status.stdout != "active"
      - minio_leftover.stdout | trim == ""
    success_msg: "Good!.. | local minio removed (unit: {{ minio_status.stdout }})"
    fail_msg: "ERROR!.. | local minio still present → unit={{ minio_status.stdout }} / process={{ minio_leftover.stdout }}"

- name: "Assert minio drives survived the removal"
  assert:
    that:
      - item.stdout | trim != ""
    success_msg: "Good!.. | drive kept for 304-minio: {{ item.item }} ← {{ item.stdout | trim }}"
    fail_msg: "ERROR!.. | drive NOT mounted: {{ item.item }} → minio_ansible.yml(minio_prereq)로 복구할 것"
  loop: "{{ minio_mounts.results }}"
  loop_control:
    label: "{{ item.item }}"
```
---
<br>

## 📌 group_vars 예시
```yaml
# 드라이브 변수만 남았다 — 서버 설치 변수는 구 minio 롤과 함께 퇴역(304-minio 로 이관)
minio_data_dir: /data/minio # 드라이브 마운트 지점의 부모 (/data/minio/disk1, /disk2)
minio_drives:
  - disk1
  - disk2
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 유닛 존재 확인 (가드)
- `stat` 조회 결과를 이후 모든 파괴적 작업의 `when:` 가드로 쓴다 — 이미 제거된 노드에서 재실행해도 실패하지 않고, 드라이브 비우기가 두 번 돌지 않는다.
---
### 2️⃣ 3️⃣ 서비스 중지·해제 + 유닛 제거
- systemd 모듈 자체가 멱등. 유닛 파일 제거 후 `daemon_reload` 로 반영한다.
---
### 4️⃣ 설정/설치/스테이징 경로 제거
- `/application/minio` 는 버전 포함 바이너리와 링크가 전부 아래에 있어 루트째 지운다 — kafka_remove 처럼 글롭(find)이 필요 없다.
- `/root/.mc` 는 구 롤의 `mc alias set` 이 남긴 자격증명 파일이라 함께 지운다.
---
### 5️⃣ 드라이브 내용물 비우기
- `find -mindepth 1 -delete` — 마운트 지점 자체는 남긴다(304-minio 의 hostPath 가 이어받는다).
- 유닛이 있던 노드에서만(`when`) — 컷오버 뒤 재실행이 K8s MinIO 의 라이브 데이터를 지우는 사고를 막는 가드다.
- `changed_when` 은 삭제된 목록(-print) 유무로 판단한다 — 빈 드라이브 재실행은 changed 가 아니다.
---
### 6️⃣ 전용 계정 제거
- 304-minio 파드는 root 로 떠서 비루트 계정이 더 이상 필요 없다.
---
### 7️⃣ 검증
- 포트는 확인하지 않는다 — K8s 서버(hostNetwork)가 떠 있으면 정당한 점유라 거짓 실패가 된다(kafka_remove 와 같은 판단).
- 대신 드라이브 마운트 생존을 추가로 assert 한다 — 이 롤이 실수로 마운트를 걷어냈다면 304-minio 가 기동하지 못하기 때문이다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [minio_remove : Assert local minio is fully removed] ****
ok: [ap] => {
    "msg": "Good!.. | local minio removed (unit: inactive)"
}
TASK [minio_remove : Assert minio drives survived the removal] ****
ok: [ap] => (item=disk1) => {
    "msg": "Good!.. | drive kept for 304-minio: disk1 ← /var/lib/minio-drives/disk1.img"
}
```
