# 📦 Longhorn 노드 사전 준비 (Ansible)
- Longhorn(분산 블록 스토리지) 설치 전 각 노드의 필수 환경을 준비한다.
- **open-iscsi**를 **인벤토리 `open_iscsi_version`으로 버전 고정** 설치 — Longhorn이 볼륨을
노드에 attach할 때 iSCSI를 사용하며, 없으면 attach 실패.
- **multipathd 차단** — multipathd가 Longhorn 디바이스(/dev/sd*)를 가로채 mount를
실패시키는 것을 방지 (블랙리스트 배포 + 서비스 중지/비활성화).
- **데이터 경로 생성** — 인벤토리 `longhorn_data_path` 기준
(Longhorn 설치 시 `defaultDataPath`와 일치시켜야 함).
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Longhorn 노드 사전 준비 (분산 블록 스토리지)
# =====================================================
# open-iscsi: Longhorn이 볼륨을 노드에 attach할 때 iSCSI 사용 → 없으면 attach 실패
# multipathd: Longhorn 디바이스(/dev/sd*)를 가로채 mount를 실패시키므로 차단
# =====================================================

# -----------------------------------------------------
# 1. open-iscsi 설치 → 인벤토리 open_iscsi_version으로 버전 고정
#    (버전 변경 시 hold 상태여도 해당 버전으로 수렴)
# -----------------------------------------------------
- name: "Install open-iscsi"
  apt:
    name: "open-iscsi={{ open_iscsi_version }}"
    state: present # 없으면 설치
    update_cache: yes # apt update 먼저 실행
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략
    allow_change_held_packages: true # hold 상태에서도 버전 변경 허용
    allow_downgrade: true # 하위 버전으로 고정 시 다운그레이드 허용

# -----------------------------------------------------
# 2. 버전 고정 → 의도치 않은 업그레이드 방지
#    (dpkg_selections 자체가 멱등)
# -----------------------------------------------------
- name: "Hold open-iscsi package"
  dpkg_selections:
    name: open-iscsi
    selection: hold

# -----------------------------------------------------
# 3. iscsid 기동 + 부팅 자동시작 (systemd 모듈 자체가 멱등)
# -----------------------------------------------------
- name: "Enable and start iscsid"
  systemd:
    name: iscsid
    enabled: true
    state: started

# -----------------------------------------------------
# 4. multipath 블랙리스트 배포 (multipathd가 재활성화돼도 Longhorn 디바이스는 제외)
#    (copy는 내용이 같으면 changed=0 보장)
# -----------------------------------------------------
- name: "Blacklist Longhorn devices in multipath"
  copy:
    content: |
      blacklist {
          devnode "^sd[a-z0-9]+"
      }
    dest: /etc/multipath.conf
    owner: root
    group: root
    mode: "0644"

# -----------------------------------------------------
# 5. multipathd 유닛 존재 확인 (조회 전용 → 미설치 환경에서 stop 실패 방지)
# -----------------------------------------------------
- name: "Check multipathd unit"
  command: systemctl list-unit-files multipathd.service
  register: multipathd_unit
  failed_when: false
  changed_when: false

# -----------------------------------------------------
# 6. multipathd 중지 + 비활성화 → socket이 서비스를 재기동하므로 socket부터 차단
# -----------------------------------------------------
- name: "Disable and stop multipathd"
  systemd:
    name: "{{ item }}"
    enabled: false
    state: stopped
  loop:
    - multipathd.socket
    - multipathd.service
  when: "'multipathd.service' in multipathd_unit.stdout"

# -----------------------------------------------------
# 7. Longhorn 데이터 경로 생성 (file 모듈 자체가 멱등)
#    → Longhorn 설치 시 defaultDataPath와 일치시켜야 함
# -----------------------------------------------------
- name: "Create Longhorn data directory"
  file:
    path: "{{ longhorn_data_path }}"
    state: directory
    owner: root
    group: root
    mode: "0755"

# ----------------------------------------------------- 
# 8. 데이터 경로 디스크 여유 확인 (확인용 출력만 / 실패 조건 없음)
# -----------------------------------------------------
- name: "Check data path disk space"
  command: df -h --output=target,size,avail,pcent {{ longhorn_data_path }}
  register: longhorn_disk
  changed_when: false

- name: "Show data path disk space"
  debug:
    msg: "{{ longhorn_disk.stdout_lines }}"

# -----------------------------------------------------
# 9. 검증
# -----------------------------------------------------
- name: "Check iscsid status"
  command: systemctl is-active iscsid
  register: iscsid_status
  failed_when: false
  changed_when: false

# 설치된 버전 확인
- name: "Check installed open-iscsi version"
  command: dpkg-query -W --showformat=${Version} open-iscsi
  register: open_iscsi_pkg_version
  changed_when: false

# hold 상태 확인
- name: "Check held packages"
  command: apt-mark showhold
  register: held_open_iscsi
  changed_when: false

# multipathd 상태 확인 (미설치 환경도 "active"만 아니면 통과)
- name: "Check multipathd status"
  command: systemctl is-active multipathd
  register: multipathd_status
  failed_when: false
  changed_when: false

# 데이터 경로 존재 확인
- name: "Check Longhorn data directory"
  stat:
    path: "{{ longhorn_data_path }}"
  register: longhorn_dir

- name: "Assert Longhorn node prerequisites"
  assert:
    that:
      - iscsid_status.stdout == "active"
      - open_iscsi_pkg_version.stdout == open_iscsi_version # 고정 버전 일치 (조건문 안에서는 {{ }} 금지)
      - '"open-iscsi" in held_open_iscsi.stdout_lines'
      - multipathd_status.stdout != "active"
      - longhorn_dir.stat.isdir | default(false)
    success_msg: "Good!.. | open-iscsi {{ open_iscsi_pkg_version.stdout }} active & held, multipathd off, {{ longhorn_data_path }} ready"
    fail_msg: "ERROR!.. | Longhorn prerequisites NOT satisfied"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ open-iscsi 설치 — 버전 고정 (멱등성 핵심)
- `open-iscsi={{ open_iscsi_version }}` 형식으로 인벤토리에 명시한 버전만 설치
- `allow_change_held_packages` + `allow_downgrade` → 버전 변수 변경 시 hold 상태여도 해당 버전으로 수렴
- 설치 후 `dpkg_selections`로 hold, `iscsid` 기동/자동시작 등록
---
### 2️⃣ multipathd 차단 — Longhorn 디바이스 가로채기 방지
- `/etc/multipath.conf`에 `devnode "^sd[a-z0-9]+"` 블랙리스트 배포 — 재활성화돼도 제외 유지
- 유닛 존재를 사전 체크(`changed_when: false`) 후 `multipathd.socket` → `multipathd.service`
순서로 중지/비활성화 (socket이 서비스를 재기동하므로 socket부터)
---
### 3️⃣ 데이터 경로 준비
- 인벤토리 `longhorn_data_path` 디렉토리 생성 (`file` 모듈 자체가 멱등)
- 디스크 여유는 `df`로 **확인용 출력만** — 실패 조건 없음
---
### 4️⃣ 검증
- `iscsid` active + **설치 버전 = 고정 버전** + hold 상태 + multipathd 미가동
+ 데이터 경로 존재를 `assert`로 검증
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert Longhorn node prerequisites]
ok: [ap] => {
    "msg": "Good!.. | open-iscsi 2.1.9-3ubuntu4 active & held, multipathd off, /data/longhorn ready"
}
```
---
