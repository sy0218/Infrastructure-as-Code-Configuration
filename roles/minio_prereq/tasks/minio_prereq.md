# 💾 MinIO 드라이브 선행작업 (minio_prereq)
- K8s 로 이관된 MinIO(Terraform 저장소 `304-minio`, Helm)가 hostPath 로 쓰는 드라이브를 노드에 준비한다 — 루프 이미지 2장 생성 → xfs 포맷 → `/data/minio/diskN` 마운트(fstab 등록).
- 서버 설치가 아니다: 구 minio 롤(systemd 설치)은 퇴역했고, 이 롤은 `longhorn_prereq`(/data/longhorn)와 같은 성격의 '도구가 모델링 못 하는 노드 선행작업'만 남긴 것이다.
- 멱등이라 재실행이 안전하다 — 이미지·포맷·마운트가 살아 있으면 아무것도 바꾸지 않는다.
- 드라이브 수·크기·경로는 `group_vars/minio.yml`이 결정하며, `304-minio` values(`minio.dataDir`·`minio.drives`)와 글자 그대로 같아야 한다.
---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# MinIO 드라이브 선행작업 → 루프 이미지 2장 생성/포맷/마운트
# -----------------------------------------------------
# 서버는 K8s(Terraform 저장소 304-minio, Helm)로 이관됐다 — 이 롤은 그 차트가
# 전제하는 노드 드라이브만 준비한다(longhorn_prereq 의 /data/longhorn 과 같은
# 성격의, 도구가 모델링 못 하는 수동 단계).
#
# [구조] 파일 하나를 리눅스가 디스크로 취급하게 만든다(근거 전문은 group_vars/minio.yml)
#   /var/lib/minio-drives/diskN.img ──리눅스──→ /dev/loopN ──마운트──→ /data/minio/diskN
#
# [주의] 구 minio 롤과 달리 마운트 지점의 소유자를 바꾸지 않는다 — 304-minio
#   파드는 root 로 뜬다(구 systemd 는 비루트 minio 계정이라 chown 이 필요했다).
#
# 멱등이라 재실행이 안전하다 — 마운트가 살아 있으면 아무것도 바꾸지 않는다.
# 필요 컬렉션: community.general(filesystem) · ansible.posix(mount)
# -----------------------------------------------------

# =========================================================================
# 1. 디렉토리 생성 (file 모듈 자체가 멱등)
# =========================================================================
- name: "Create minio drive directories"
  file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - "{{ minio_data_dir }}" # 드라이브 마운트 지점의 부모
    - "{{ minio_image_dir }}" # 드라이브 실체(루프 이미지 파일)

# =========================================================================
# 2. 드라이브 준비 — 파일 하나를 디스크로 만들어 마운트한다
# =========================================================================

# creates 로 멱등 — 이미 있으면 건드리지 않는다(있는 이미지를 다시 만들면 데이터가 날아간다)
- name: "Create minio drive images"
  command: "truncate -s {{ minio_drive_size }} {{ minio_image_dir }}/{{ item }}.img"
  args:
    creates: "{{ minio_image_dir }}/{{ item }}.img"
  loop: "{{ minio_drives }}"

# filesystem 모듈은 이미 포맷돼 있으면 건너뛴다(force 를 주지 않는 한 덮어쓰지 않는다)
- name: "Format minio drive images"
  community.general.filesystem:
    fstype: "{{ minio_drive_fstype }}"
    dev: "{{ minio_image_dir }}/{{ item }}.img"
  loop: "{{ minio_drives }}"

# state: mounted → 지금 마운트하고 /etc/fstab 에도 등록한다(재부팅 후에도 유지).
# ⚠ fstab 등록이 빠지면 재부팅 시 마운트가 풀리는데, 그 자리(루트 디스크의 빈 폴더)로
#   기동하는 사고는 304-minio 의 check-drives initContainer 가 막는다(RequiresMountsFor 승계).
- name: "Mount minio drives"
  ansible.posix.mount:
    path: "{{ minio_data_dir }}/{{ item }}"
    src: "{{ minio_image_dir }}/{{ item }}.img"
    fstype: "{{ minio_drive_fstype }}"
    opts: loop
    state: mounted
  loop: "{{ minio_drives }}"

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
# 드라이브가 진짜 마운트돼 있는지 — 값이 비면 루트 디스크의 빈 폴더를 보고 있다는 뜻이다
# (fstab 등록이 빠졌거나 재부팅 후 마운트가 풀린 경우).
- name: "Check minio drives are mounted"
  command: "findmnt -no SOURCE {{ minio_data_dir }}/{{ item }}"
  loop: "{{ minio_drives }}"
  register: minio_mounts
  changed_when: false
  failed_when: false

- name: "Assert minio drives are mounted filesystems"
  assert:
    that:
      - item.stdout | trim != ""
    success_msg: "Good!.. | drive mounted: {{ item.item }} ← {{ item.stdout | trim }}"
    fail_msg: "ERROR!.. | drive NOT mounted: {{ item.item }} → 304-minio 파드가 기동하지 못한다 (mount -a 후 재확인)"
  loop: "{{ minio_mounts.results }}"
  loop_control:
    label: "{{ item.item }}"
```
---
<br>

## 📌 group_vars 예시
```yaml
minio_data_dir: /data/minio # 드라이브 마운트 지점의 부모 (/data/minio/disk1, /disk2)
minio_image_dir: /var/lib/minio-drives # 드라이브 실체(루프 이미지 파일)가 놓이는 곳
minio_drives:
  - disk1
  - disk2
minio_drive_size: "15G" # truncate 는 sparse 파일이라 만드는 즉시 소비되지 않는다
minio_drive_fstype: xfs # MinIO 권장 파일시스템
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 디렉토리 생성
- 마운트 지점의 부모(`/data/minio`)와 이미지 보관소(`/var/lib/minio-drives`)를 만든다. file 모듈이라 멱등.
- 구 minio 롤과 달리 소유자는 root 로 둔다 — `304-minio` 파드가 root 로 떠서 비루트 계정·chown 이 필요 없어졌다.
---
### 2️⃣ 드라이브 준비 (이미지 → 포맷 → 마운트)
- MinIO 는 드라이브가 '진짜 마운트된 파일시스템'인지 검사해 루트 디스크 위 폴더를 거부한다(실측). 이 랩엔 빈 블록 디바이스가 없어 루프 이미지가 유일한 방법이다.
- `truncate + creates=` 가드 — 이미지를 다시 만들면 데이터가 날아가므로 존재하면 건드리지 않는다. sparse 파일이라 만드는 즉시 디스크를 소비하지 않는다.
- `filesystem` 모듈은 이미 포맷된 이미지를 건너뛰고, `mount state: mounted` 는 fstab 까지 등록해 재부팅에도 유지된다.
- 마운트가 풀린 채 기동하는 사고는 `304-minio` 의 check-drives initContainer 가 막는다 — 구 systemd 유닛의 `RequiresMountsFor` 를 K8s 쪽에서 승계한 것.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [minio_prereq : Assert minio drives are mounted filesystems] ****
ok: [ap] => (item=disk1) => {
    "msg": "Good!.. | drive mounted: disk1 ← /var/lib/minio-drives/disk1.img"
}
ok: [ap] => (item=disk2) => {
    "msg": "Good!.. | drive mounted: disk2 ← /var/lib/minio-drives/disk2.img"
}
```
