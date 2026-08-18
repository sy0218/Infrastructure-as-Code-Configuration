# 🧹 Kafka 로컬 설치 제거 (kafka_remove)
- 구 Kafka 로컬(systemd) 설치를 노드에서 걷어내는 일회성 컷오버 롤 — 브로커는
  Terraform 저장소 **301-kafka**(Helm, KRaft StatefulSet — hostNetwork + hostPath 노드 고정)가 승계했다.
- 새 브로커가 같은 호스트 포트(9092/9093/9094/9404)를 쓰므로 **301-kafka helm install 전에 먼저 실행**해야 한다.
- 유닛·설정·설치본·**데이터(/data/kafka, 복구 불가)**·계정까지 지운다 — postgres 롤의 '중지 보존'과
  다른 이유: 같은 포트라 공존 자체가 불가능하다.
- 변수 없이 경로 리터럴로 동작한다 — 짝이 되는 group_vars/kafka.yml 이 kafka 롤과 함께 퇴역해서다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Kafka 로컬(systemd) 설치 제거
#   → 브로커가 K8s(Terraform 저장소 301-kafka, Helm)로 이관되어 구 설치를 걷어낸다.
#   → 새 브로커가 같은 호스트 포트(9092/9093/9094/9404)를 쓰므로
#     301-kafka 설치 전에 이 롤이 먼저 완료되어야 한다.
# =====================================================
# [주의] 데이터(/data/kafka)까지 지운다 — 복구 불가. 이관 결정에 포함된 사항이며,
#   새 클러스터는 새 CLUSTER_ID 로 포맷되므로 옛 데이터는 어차피 합류할 수 없다.
# [주의] 경로가 리터럴인 이유 — group_vars/kafka.yml 은 kafka 롤과 함께 퇴역해서
#   변수 출처가 없다. 값은 퇴역 시점의 group_vars 를 그대로 옮긴 것이다.
# =====================================================


# -----------------------------------------------------
# 1. 구 systemd 설치 흔적 확인 (조회만) → 이후 모든 파괴 작업의 가드
#    → 가드 기준이 '/data/kafka 존재'가 아닌 이유: 컷오버 후 그 경로는
#      K8s 브로커(301-kafka hostPath)의 실데이터다. 유닛/설치 루트가 있을 때만
#      구 설치로 판정해야 재실행이 가동 중인 새 브로커 3대의 데이터를 지우지 않는다.
#    → 설치 루트(stat 2개 중 하나라도 존재)를 함께 보는 이유: 직전 실행이 유닛 제거
#      직후 중단됐어도 재실행이 나머지를 이어서 지울 수 있어야 한다(재개 가능).
# -----------------------------------------------------
- name: "Check kafka systemd unit exists"
  stat:
    path: /etc/systemd/system/kafka.service
  register: kafka_unit

- name: "Check kafka install root exists"
  stat:
    path: /application/kafka # KAFKA_HOME 심볼릭 링크 (구 설치의 두 번째 흔적)
  register: kafka_install

- name: "Decide whether legacy kafka is present"
  set_fact:
    kafka_legacy_present: "{{ kafka_unit.stat.exists or kafka_install.stat.exists }}"

# -----------------------------------------------------
# 2. 서비스 중지 + 자동시작 해제
# -----------------------------------------------------
- name: "Stop and disable kafka service"
  systemd:
    name: kafka
    state: stopped
    enabled: false
  when: kafka_unit.stat.exists

# -----------------------------------------------------
# 3. 유닛 파일 제거 + systemd 반영
# -----------------------------------------------------
- name: "Remove kafka systemd unit file"
  file:
    path: /etc/systemd/system/kafka.service
    state: absent
  when: kafka_legacy_present

- name: "Reload systemd after unit removal"
  systemd:
    daemon_reload: true
  when: kafka_unit.stat.exists

# -----------------------------------------------------
# 4. 설정/데이터/로그/설치 경로 제거 (file 모듈 자체가 멱등)
#    → 반드시 kafka_legacy_present 가드 아래에서만 실행한다 — 컷오버 후 재실행 시
#      /data/kafka 는 K8s 브로커 3대의 실데이터라, 가드 없이 지우면 RF=3 도
#      막지 못하는 전 노드 동시 소실이 된다.
#    → /application/kafka 는 심볼릭 링크, 실체(kafka_<스칼라>-<버전>)와
#      tarball 은 버전이 파일명에 있어 5번에서 글롭으로 지운다
# -----------------------------------------------------
- name: "Remove kafka config, data, and log directories"
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - /etc/kafka # server.properties / jmx_exporter.yaml
    - /application/kafka # KAFKA_HOME 심볼릭 링크
    - /application/jmx # JMX javaagent jar
    - /data/kafka # 로그 세그먼트 (브로커 데이터 — 복구 불가)
    - /logs/kafka # 브로커 애플리케이션 로그
  when: kafka_legacy_present

# -----------------------------------------------------
# 5. 버전 포함 설치 디렉토리/tarball 제거
#    → kafka_2.13-4.0.1/ · kafka_2.13-4.0.1.tgz 처럼 이름에 버전이 박혀 있다
# -----------------------------------------------------
- name: "Find versioned kafka installs under /application"
  find:
    paths: /application
    patterns: "kafka_*"
    file_type: any
    recurse: false
  register: kafka_versioned
  when: kafka_legacy_present

- name: "Remove versioned kafka installs"
  file:
    path: "{{ item.path }}"
    state: absent
  loop: "{{ kafka_versioned.files | default([]) }}"
  loop_control:
    label: "{{ item.path }}"
  when: kafka_legacy_present

# -----------------------------------------------------
# 6. 전용 계정 제거
# -----------------------------------------------------
- name: "Remove kafka system user"
  user:
    name: kafka
    state: absent
  when: kafka_legacy_present

# -----------------------------------------------------
# 7. 검증
#    → 포트(9092 등)는 확인하지 않는다 — K8s 브로커(hostNetwork)가 먼저 떠 있으면
#      정당한 점유라 거짓 실패가 된다. 확인 대상은 systemd 경로의 잔재뿐이다.
# -----------------------------------------------------
- name: "Check kafka service is gone"
  command: systemctl is-active kafka
  register: kafka_status
  failed_when: false
  changed_when: false

- name: "Check leftover local kafka broker process"
  # K8s 파드의 브로커는 컨테이너 경로(/opt/kafka)로 보인다 —
  # 구 로컬 설치(/application/kafka) 경로의 프로세스만 잔재로 취급한다
  shell: "pgrep -af 'kafka.Kafka' | grep '/application/kafka' || true"
  register: kafka_leftover
  changed_when: false

- name: "Check kafka install root is gone"
  stat:
    path: /application/kafka
  register: kafka_install_after

- name: "Assert local kafka is fully removed"
  assert:
    that:
      - kafka_status.stdout != "active"
      - kafka_leftover.stdout | trim == ""
      - not kafka_install_after.stat.exists
    success_msg: "Good!.. | local kafka removed (unit: {{ kafka_status.stdout }}, legacy_found: {{ kafka_legacy_present }})"
    fail_msg: "ERROR!.. | local kafka still present → unit={{ kafka_status.stdout }} / process={{ kafka_leftover.stdout }} / install_root={{ kafka_install_after.stat.exists }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 구 설치 흔적 확인 → 파괴 작업 가드
- 유닛 파일과 설치 루트(/application/kafka) 둘 중 하나라도 있어야 `kafka_legacy_present` 가 참이 된다.
- **`/data/kafka` 존재를 가드로 쓰지 않는 것이 핵심** — 컷오버 후 그 경로는 가동 중인
  K8s 브로커(301-kafka hostPath)의 실데이터라, 잘못 판정하면 재실행 한 번에 3노드
  데이터가 동시에 사라진다(RF=3 도 못 막는다).
- 흔적을 둘 보는 이유는 재개 가능성 — 직전 실행이 유닛 제거 직후 끊겨도 이어서 지운다.
---
### 2️⃣ 서비스 중지 + 자동시작 해제
- systemd 모듈 자체가 멱등. 유닛이 없는 노드에서는 건너뛴다(`when` 가드).
---
### 3️⃣ 유닛 파일 제거 + systemd 반영
- file 모듈(absent)은 멱등. daemon-reload 는 유닛이 실제로 있던 노드에서만 실행한다.
---
### 4️⃣ 설정/데이터/로그/설치 경로 제거
- 전부 `kafka_legacy_present` 가드 아래 — 구 설치가 없던 노드(=컷오버 완료 노드)에서는
  아무것도 지우지 않는다. 재실행 안전(멱등)이 이 가드로 성립한다.
---
### 5️⃣ 버전 포함 설치 디렉토리/tarball 제거
- 버전이 파일명에 박혀 있어(`kafka_2.13-4.0.1*`) 고정 경로로는 못 지운다 → find 글롭.
- `recurse: false` 라 /application 바로 아래만 보고, 다른 애플리케이션 디렉토리는 건드리지 않는다.
---
### 6️⃣ 전용 계정 제거
- user 모듈(absent) 멱등. 계정이 이미 없으면 아무 일도 없다.
---
### 7️⃣ 검증
- 유닛이 active 가 아니고, `/application/kafka` 경로의 브로커 프로세스와 설치 루트가
  없어야 통과. **포트는 검사하지 않는다** — K8s 브로커(hostNetwork)가 이미 떠 있으면
  9092 점유가 정당해서 거짓 실패가 되기 때문이다.
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [kafka_remove : Assert local kafka is fully removed] *********************
ok: [ap] => {
    "msg": "Good!.. | local kafka removed (unit: inactive, legacy_found: True)"
}
ok: [s1] => { "msg": "Good!.. | local kafka removed (unit: inactive, legacy_found: True)" }
ok: [s2] => { "msg": "Good!.. | local kafka removed (unit: inactive, legacy_found: True)" }
```
