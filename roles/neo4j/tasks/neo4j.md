# 🕸 Neo4j 설치 (Community Edition · 로컬 systemd)

- ADR 0(Kafka)와 같은 판단 — **K8s 가 아니라 서버 로컬(systemd)**. compose 의 `data_layer-graph` 서비스(`neo4j:5-community` 이미지)를 이 롤이 대체한다.
- Terraform `300-data-layer-base` 의 `neo4j_bolt_uri`(`bolt://192.168.56.200:7687`)가 여기서 연 주소를 가리키고, `308-pipeline` 의 `cdm-consumer-graph` 가 그 주소로 붙어 MERGE 로 적재한다.
  | 포트 | 용도 | 계약 지점 |
  |---|---|---|
  | `7687` | Bolt — neo4j 파이썬 드라이버 접속 | `300` 의 `neo4j_bolt_uri` → `PLATFORM_NEO4J_URI` |
  | `7474` | HTTP — Neo4j Browser (`data-layer-neo4j:7474`) | `etc_hosts` 롤의 `data_layer_dns_names` |
- **Community Edition 은 DB 가 `neo4j` 하나뿐이다.** 기존 그래프와의 분리는 DB 가 아니라 **라벨 접두어**(`GRAPH_LABEL_PREFIX`)로 한다 — 그 값은 `300` 스택이 주입한다(`Test` → `TestBatch`/`TestUnit`/...).
- **UNIQUE 제약 27종은 이 롤이 만들지 않는다** — 컨슈머가 기동 시 1회 생성한다(`cdm_consumer_graph/constraints.py`). 서버를 세우는 것까지가 이 롤의 책임이다.
- **플러그인(APOC/GDS)은 넣지 않는다** — 컨슈머가 쓰는 건 `MERGE`/`MATCH` + UNIQUE 제약뿐이라 필요가 없고, 기동 시간만 늘어난다(compose 시절 Dockerfile 의 판단 승계).
- ⚠️ **계정·비밀번호가 곧 계약이다** — `neo4j_user` / `neo4j_password` 는 `300-data-layer-base` 의 `secrets.auto.tfvars`(`platform_neo4j_user` / `platform_neo4j_password`)와 **글자 그대로** 같아야 한다. 갈리면 서버는 멀쩡한데 `cdm-consumer-graph` 만 조용히 인증 실패한다.
- ⚠️ **비밀번호는 최초 기동 전에 1회 각인된다**(`neo4j-admin dbms set-initial-password`, `creates=auth.ini` 가드). 각인 뒤에 `host.yml` 값을 바꿔도 **재실행으로는 반영되지 않는다** — 검증이 인증 실패로 알려주며, 바꾸려면 직접 실행한다:
  `cypher-shell -a bolt://192.168.56.200:7687 -u neo4j -p <현재값> "ALTER USER neo4j SET PASSWORD '<새값>'"`
- ⚠️ `server.default_listen_address` 는 **`0.0.0.0` 이어야 한다** — 로컬 설치라 Service 가 없어서 클러스터 파드가 노드 IP 로 직접 붙는다. 패키지 기본값(`localhost`)으로 두면 **서버는 정상 기동하는데 컨슈머만 연결 거부**를 맞는다.
- ⚠️ **버전 핀은 되돌릴 수 없다** — Neo4j 는 상위 버전이 연 스토어를 하위 버전으로 다시 열지 못한다. 마이너를 올리기 전에 백업 여부를 먼저 판단할 것. 사용 가능 버전:
  `curl -s https://debian.neo4j.com/dists/stable/5/binary-amd64/Packages | awk '/^Package: /{p=$2} /^Version: /{if(p=="neo4j") print $2}' | sort -V | tail`
- ⚠️ **메모리** — `ap` 는 이미 Kafka 브로커(JVM)·PostgreSQL·MinIO·K8s 컨트롤플레인을 함께 지고 있다. 힙 1G + 페이지캐시 512M 는 이 노드 단일 최대 소비자다. 파드가 Pending/OOM 으로 밀리면 `neo4j_heap_size`/`neo4j_pagecache_size` 를 `512M`/`256M` 로 내리는 것이 첫 수다.
- 설정은 `blockinfile` 로 덧붙이지 않고 **`lineinfile` 로 키마다 치환**한다 — 패키지가 배포한 `neo4j.conf` 에 같은 키가 주석으로 이미 있어서, 덧붙이면 한 파일에 같은 설정이 두 번 나타난다. `/etc/neo4j/neo4j.conf` 는 conffile 이라 이 편집이 패키지 업그레이드에도 보존된다.
- systemd 설정은 **드롭인**(`/etc/systemd/system/neo4j.service.d/10-data-layer.conf`)으로 넣는다. `/etc/default/neo4j` 는 쓰지 않는다 — 그 파일 자체가 "sysvinit 전용이며 systemd 는 `systemctl edit` 을 쓰라"고 적고 있다.

---
<br>

## 🧩 main.yml
```yaml
# -----------------------------------------------------
# Neo4j 설치 → Community Edition 5.x (apt) + Bolt/HTTP 공개
# -----------------------------------------------------
# ADR 0 (Kafka)와 같은 판단을 데이터 스토어에도 적용한다 — K8s 가 아니라 서버 로컬(systemd).
#   compose 의 data_layer-graph 서비스(neo4j:5-community 이미지)를 이 롤이 대체한다.
#   300-data-layer-base 의 neo4j_bolt_uri 가 여기서 연 Bolt 주소를 가리킨다.
#
# [주의] Community Edition 은 DB 가 `neo4j` 하나뿐이다 — 기존 그래프와의 분리는 DB 가
#   아니라 라벨 접두어(GRAPH_LABEL_PREFIX)로 한다. 그 값은 300 스택이 주입한다.
# [주의] UNIQUE 제약 27종은 이 롤이 만들지 않는다 — 컨슈머가 기동 시 1회 생성한다
#   (cdm_consumer_graph/constraints.py). 서버를 세우는 것까지가 이 롤의 책임이다.
# [주의] 플러그인(APOC/GDS)은 넣지 않는다 — 컨슈머가 쓰는 건 MERGE/MATCH + UNIQUE 제약뿐이라
#   필요가 없고, 기동 시간만 늘어난다(compose 시절 Dockerfile 의 판단 승계).
# -----------------------------------------------------

# =========================================================================
# 1. Neo4j apt 저장소 등록 (deb822_repository 자체가 멱등)
#    → gpg --dearmor 파이프 금지(하우스 스타일) — 모듈의 signed_by 로 키를 직접 받는다
#    → components 가 메이저 계열이다(`5`) — 6.x 로 올릴 땐 이 값도 함께 바꿔야 한다
# =========================================================================
- name: "Add neo4j apt repository"
  deb822_repository:
    name: neo4j
    types: [deb]
    uris: "https://debian.neo4j.com"
    suites: "{{ neo4j_repo_suite }}"
    components: ["{{ neo4j_repo_component }}"]
    signed_by: "https://debian.neo4j.com/neotechnology.gpg.key"
    state: present
    enabled: true
  register: neo4j_repo
  retries: 3 # 외부 저장소 조회 불안정 대비
  delay: 10
  until: neo4j_repo is succeeded

# =========================================================================
# 2. 패키지 설치 (버전 고정 — host.yml 이 단일 출처)
#    → cypher-shell 은 선택이 아니다: 이 롤의 검증(RETURN 1)과 운영 중 수동 조회가 쓴다.
#      neo4j 패키지가 `cypher-shell (>= 1:5.0)` 을 의존하므로 어차피 함께 들어온다 —
#      버전을 같이 박아 둘이 따로 노는 상황을 막는다.
#    → 버전 문자열에 epoch(`1:`)가 있다. 빼면 apt 가 그런 버전이 없다며 실패한다.
#    → allow_change_held_packages: 아래 3번 hold 가 걸린 뒤에도 핀 변경이 수렴하도록
#    ⚠ Neo4j 5 는 Java 17 이상 필수(패키지 의존성이 java17-runtime|jdk-17) —
#      java 롤(java_version)이 먼저 적용돼 있어야 한다. Kafka 와 같은 JDK 를 쓴다.
# =========================================================================
- name: "Install neo4j and cypher-shell"
  apt:
    name:
      - "neo4j={{ neo4j_package_version }}"
      - "cypher-shell={{ neo4j_package_version }}"
    state: present
    update_cache: true
    allow_change_held_packages: true
    allow_downgrade: true
  register: neo4j_install
  retries: 3
  delay: 10
  until: neo4j_install is succeeded

# =========================================================================
# 3. 버전 고정 (dpkg_selections 자체가 멱등)
#    → apt upgrade 가 조용히 마이너를 올리면 스토어 포맷이 업그레이드되어 되돌릴 수 없다
#      (Neo4j 는 상위 버전이 연 스토어를 하위 버전으로 다시 열지 못한다)
# =========================================================================
- name: "Hold neo4j packages"
  dpkg_selections:
    name: "{{ item }}"
    selection: hold
  loop:
    - neo4j
    - cypher-shell

# =========================================================================
# 4. 서버 설정 (lineinfile — 키마다 한 줄씩 '치환')
#    → blockinfile 로 끝에 덧붙이지 않는 이유: 패키지가 배포한 neo4j.conf 에 같은 키가
#      주석으로 이미 들어 있어서, 덧붙이면 한 파일에 같은 설정이 두 번 나타난다.
#      주석 여부(^#?)까지 포함해 치환하면 중복 없이 한 줄만 남는다.
#    → owner/mode 를 지정하지 않는다 — 패키지가 설정한 소유/권한을 그대로 보존한다.
#    ⚠ default_listen_address 는 0.0.0.0 이어야 한다: 클러스터 파드가 Service DNS 없이
#      노드 IP 로 직접 붙는다(로컬 설치라 Service 가 없다). 기본값 localhost 로 두면
#      서버는 정상 기동하는데 컨슈머만 연결 거부를 맞는다.
#    ⚠ 포트를 바꾸면 Terraform 300-data-layer-base 의 neo4j_bolt_uri 도 함께 고칠 것.
# =========================================================================
- name: "Apply neo4j server settings"
  lineinfile:
    path: "{{ neo4j_conf_file }}"
    regexp: "^#?\\s*{{ item.key | regex_escape }}\\s*="
    line: "{{ item.key }}={{ item.value }}"
    state: present
  loop:
    # 접속 — 광고 주소는 노드 IP 로 둔다(neo4j:// 라우팅 드라이버가 이 값을 받아 재접속한다)
    - { key: server.default_listen_address, value: "0.0.0.0" }
    - { key: server.default_advertised_address, value: "{{ ansible_host }}" }
    # Bolt — 컨슈머(neo4j 파이썬 드라이버)가 붙는 포트. 내부망 전제라 TLS 없음(compose 계약 승계)
    - { key: server.bolt.enabled, value: "true" }
    - { key: server.bolt.listen_address, value: ":{{ neo4j_bolt_port }}" }
    - { key: server.bolt.tls_level, value: "DISABLED" }
    # HTTP — Neo4j Browser(data-layer-neo4j:7474). HTTPS 는 인증서가 없어 끈다
    - { key: server.http.enabled, value: "true" }
    - { key: server.http.listen_address, value: ":{{ neo4j_http_port }}" }
    - { key: server.https.enabled, value: "false" }
    # 메모리 — 힙은 initial=max 로 고정한다(가변 힙은 GC 중 재조정으로 지연이 튄다)
    - { key: server.memory.heap.initial_size, value: "{{ neo4j_heap_size }}" }
    - { key: server.memory.heap.max_size, value: "{{ neo4j_heap_size }}" }
    - { key: server.memory.pagecache.size, value: "{{ neo4j_pagecache_size }}" }
    # 인증 — 끄면 비밀번호 각인이 무의미해진다. 명시해서 되돌리기 어렵게 둔다
    - { key: dbms.security.auth_enabled, value: "true" }
  loop_control:
    label: "{{ item.key }}"
  notify: restart neo4j

# =========================================================================
# 5. systemd 드롭인 (copy 자체가 멱등)
#    → 패키지가 배포한 neo4j.service 를 건드리지 않는다 — 드롭인이라 패키지 업그레이드가
#      유닛을 덮어써도 이 설정은 남는다. /etc/default/neo4j 는 쓰지 않는다:
#      그 파일 자체가 "sysvinit 전용이며 systemd 는 systemctl edit 을 쓰라"고 적고 있다.
#    → JAVA_HOME 을 박는 이유: PATH 의 java 가 무엇인지에 기대지 않기 위해서다
#      (kafka 롤과 같은 JDK 를 같은 방식으로 가리킨다).
#    → Restart 를 덮는 이유: 패키지 기본값이 on-abnormal 이라 '0 이 아닌 종료코드'로 죽으면
#      되살아나지 않는다. kafka/minio 롤과 같은 on-failure 로 통일한다.
#    → LimitNOFILE 은 건드리지 않는다 — 패키지 유닛이 이미 60000(권장값)으로 준다.
# =========================================================================
- name: "Create neo4j systemd drop-in directory"
  file:
    path: /etc/systemd/system/neo4j.service.d
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: "Create neo4j systemd drop-in"
  copy:
    dest: /etc/systemd/system/neo4j.service.d/10-data-layer.conf
    owner: root
    group: root
    mode: '0644'
    content: |
      # Ansible neo4j 롤이 관리한다 — 수동 수정 금지
      [Service]
      Environment=JAVA_HOME={{ neo4j_java_home }}
      Restart=on-failure
      RestartSec=5
  notify: restart neo4j

# =========================================================================
# 6. 초기 비밀번호 각인 (비멱등 명령 가드 / creates= 로 재실행 시 스킵)
#    → 서버가 '한 번도 뜨기 전'에만 각인된다. 한 번 기동해 system DB 가 만들어지면
#      이 명령은 효과가 없다 — 그래서 기동(8번)보다 앞에 둔다.
#    → 패키지 postinst 는 서비스를 자동 기동하지 않는다(update-rc.d 로 sysvinit 링크만
#      건다). 그래도 앞선 실행이나 수동 조작으로 떠 있을 수 있어 auth.ini 가 없을 때만
#      한 번 멈춘다 — 각인이 조용히 무효가 되는 것을 막는다.
#    → /usr/bin/neo4j-admin 래퍼가 NEO4J_HOME·NEO4J_CONF 를 스스로 박으므로 환경변수를
#      따로 넘기지 않는다(JAVA_HOME 만 준다).
#    ⚠ 각인 뒤에 host.yml 의 비밀번호를 바꿔도 재실행으로는 반영되지 않는다.
#      바꾸려면 cypher-shell 로 `ALTER USER neo4j SET PASSWORD '<새값>'` 을 직접 실행한다
#      (아래 검증이 실패로 알려준다).
# =========================================================================
- name: "Check neo4j initial password file"
  stat:
    path: "{{ neo4j_home }}/data/dbms/auth.ini"
  register: neo4j_auth_ini

- name: "Stop neo4j before seeding the initial password"
  systemd:
    name: neo4j
    state: stopped
  when: not neo4j_auth_ini.stat.exists

- name: "Set initial neo4j password"
  command: "neo4j-admin dbms set-initial-password {{ neo4j_password }}"
  args:
    creates: "{{ neo4j_home }}/data/dbms/auth.ini"
  become_user: "{{ neo4j_service_user }}"
  environment:
    JAVA_HOME: "{{ neo4j_java_home }}"
  no_log: true # 비밀번호가 인자로 들어간다 — 로그에 남기지 않는다

# =========================================================================
# 7. 포트 선점 확인 (조회만 / changed_when: false)
#    → 노드 포트를 직접 쓰기 때문에 kafka 롤과 같은 사고(JMX 9098 충돌) 재발을 막는다.
#      neo4j 자신이 이미 물고 있는 경우(재실행)는 정상이므로 MainPID 를 제외한다.
# =========================================================================
- name: "Get neo4j service main pid"
  command: systemctl show neo4j -p MainPID --value
  register: neo4j_mainpid
  changed_when: false
  failed_when: false # 최초 설치라 유닛이 아직 없을 수 있다

- name: "Check processes holding the neo4j ports"
  shell: "ss -lntpH 'sport = :{{ item }}' | grep -v 'pid={{ neo4j_mainpid.stdout | default('0', true) }},' || true"
  loop:
    - "{{ neo4j_bolt_port }}"
    - "{{ neo4j_http_port }}"
  register: neo4j_port_owner
  changed_when: false

- name: "Assert neo4j ports are not taken by another process"
  assert:
    that:
      - item.stdout | trim == "" # neo4j 외 점유자가 없어야 한다
    success_msg: "Good!.. | neo4j port available"
    fail_msg: "ERROR!.. | neo4j port taken by another process → {{ item.stdout }}"
  loop: "{{ neo4j_port_owner.results }}"
  loop_control:
    label: "{{ item.item }}"

# =========================================================================
# 8. 서비스 기동 + 부팅 자동시작 (systemd 모듈 자체가 멱등)
#    → 패키지는 유닛을 enable 하지 않는다 — 여기서 켜지 않으면 재부팅 후 그래프만 사라진다
# =========================================================================
- name: "Enable and start neo4j"
  systemd:
    name: neo4j
    enabled: true
    state: started
    daemon_reload: true # 드롭인 반영 (최초 설치 시 유닛 인식용)

# =========================================================================
# 9. 설정 변경분을 검증 전에 반영한다
#    → 핸들러는 기본적으로 플레이 끝에 실행되는데, 아래 검증이 이미 접속을 시도한다
# =========================================================================
- name: "Flush handlers before verification"
  meta: flush_handlers

# -----------------------------------------------------
# 검증
# -----------------------------------------------------
# 기동 직후 상태부터 확인한다 — 설정 오타면 strict validation 이 기동을 거부해
# 'activating' 이 반복된다(아래 Bolt 대기에서 1분을 버리기 전에 여기서 끊는다).
- name: "Check neo4j service status"
  command: systemctl is-active neo4j
  register: neo4j_status
  changed_when: false
  failed_when: false
  retries: 6 # Neo4j 는 기동이 느리다 — 최대 30초
  delay: 5
  until: neo4j_status.stdout == "active"

- name: "Assert neo4j service is active"
  assert:
    that:
      - neo4j_status.stdout == "active"
    success_msg: "Good!.. | neo4j.service active"
    fail_msg: "ERROR!.. | neo4j.service is {{ neo4j_status.stdout }} → 노드에서 journalctl -u neo4j -n 50 확인 (설정 오타(strict validation) / 힙 부족 / 포트 충돌 순으로 의심)"

- name: "Check installed neo4j package version"
  command: "dpkg-query -W -f=${Version} neo4j"
  register: neo4j_version_check
  changed_when: false

# Bolt 대기 — 서비스가 active 여도 스토어 복구/인덱스 기동이 끝나야 쿼리를 받는다.
# 클러스터 파드가 실제로 붙는 경로(노드 IP + 계정)로 확인한다 — 127.0.0.1 만 보면
# default_listen_address 가 localhost 로 남은 사고를 못 잡는다.
- name: "Wait for neo4j bolt to accept queries"
  command: >-
    cypher-shell --non-interactive --format plain
    -a bolt://{{ ansible_host }}:{{ neo4j_bolt_port }}
    -d {{ neo4j_database }} "RETURN 1"
  environment:
    NEO4J_USERNAME: "{{ neo4j_user }}"
    NEO4J_PASSWORD: "{{ neo4j_password }}"
  register: neo4j_bolt
  changed_when: false
  failed_when: false
  retries: 12 # 최대 1분
  delay: 5
  until: neo4j_bolt.rc == 0

# 접속한 DB 의 이름 확인 — 컨슈머의 NEO4J_DATABASE 와 같아야 한다(CE 라 사실상 `neo4j` 고정).
# SHOW DATABASES(system DB 명령) 대신 db.info() 를 쓴다 — 현재 DB 컨텍스트에서 그대로 돌아
# '지금 붙은 그 DB' 의 이름을 돌려주므로, 확인하려는 것과 확인하는 방법이 어긋나지 않는다.
- name: "Check connected database name"
  command: >-
    cypher-shell --non-interactive --format plain
    -a bolt://{{ ansible_host }}:{{ neo4j_bolt_port }}
    -d {{ neo4j_database }} "CALL db.info() YIELD name RETURN name"
  environment:
    NEO4J_USERNAME: "{{ neo4j_user }}"
    NEO4J_PASSWORD: "{{ neo4j_password }}"
  register: neo4j_db_list
  changed_when: false
  failed_when: false

# HTTP(Neo4j Browser) 응답 확인 — data-layer-neo4j:7474 로 접속하는 경로
- name: "Check neo4j http endpoint"
  command: "curl -s -o /dev/null -w %{http_code} -H 'Accept: application/json' http://{{ ansible_host }}:{{ neo4j_http_port }}/"
  register: neo4j_http
  changed_when: false
  failed_when: false

- name: "Assert neo4j is ready for the data layer"
  assert:
    that:
      - neo4j_status.stdout == "active"
      - neo4j_package_version == neo4j_version_check.stdout # 고정 버전 일치 (조건문 안에서는 {{ }} 금지)
      - neo4j_bolt.rc == 0 # 노드 IP + 계정으로 Bolt 쿼리 성공
      - neo4j_database in neo4j_db_list.stdout # 컨슈머가 지정하는 DB 가 실재
      - neo4j_http.stdout == "200" # Browser(HTTP) 도 노드 IP 로 응답
    success_msg: "Good!.. | neo4j {{ neo4j_package_version }} active — bolt :{{ neo4j_bolt_port }} / http :{{ neo4j_http_port }} / db {{ neo4j_database }} 접속 OK"
    fail_msg: "ERROR!.. | neo4j NOT ready → 노드에서 journalctl -u neo4j -n 50 확인. 인증 실패(Bolt rc!=0)면 각인된 비밀번호와 host.yml 이 갈린 것이다 — cypher-shell 로 ALTER USER {{ neo4j_user }} SET PASSWORD '<host.yml 값>' 실행"
```

---
<br>

## 🔔 handlers/main.yml
```yaml
# -----------------------------------------------------
# neo4j 재시작 핸들러 → neo4j.conf / systemd 드롭인 변경 시에만 실행
# -----------------------------------------------------
- name: restart neo4j
  systemd:
    name: neo4j
    state: restarted
    daemon_reload: true # 드롭인 변경분 반영
```
