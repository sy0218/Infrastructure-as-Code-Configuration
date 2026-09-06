# 🗂 /etc/hosts 생성 및 관리 (Ansible)
- 서버 초기 세팅 시 **/etc/hosts 파일을 인벤토리 기준으로 자동 생성**
- 기존 `/etc/hosts` 파일을 **전체 덮어쓰기**하여 서버 간 호스트명 통일
- data-layer 이름을 **두 계열로 나눠** 등록 — 노드 IP 계열(`data_layer_dns_names`)과
  인그레스 VIP 계열(`data_layer_vip_dns_names`). 나눈 기준은 **장애 전환을 누가 하느냐**다
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# /etc/hosts 생성 (인벤토리 기반 전체 관리)
# =====================================================


# -----------------------------------------------------
# 1. /etc/hosts 생성 (copy: content 자체가 멱등 → 내용이 같으면 changed=0)
# -----------------------------------------------------
- name: "Create /etc/hosts from inventory"
  copy:
    dest: /etc/hosts
    owner: root
    group: root
    mode: '0644'
    content: |
      127.0.0.1   localhost
      ::1         localhost

      {% for host in groups['server_configuration'] %}
      {{ hostvars[host]['ansible_host'] }} {{ host }}
      {% endfor %}

      {% for host in groups['server_configuration'] %}
      {{ hostvars[host]['ansible_host'] }} {{ data_layer_dns_names | join(' ') }}
      {% endfor %}

      {{ ingress_vip }} {{ data_layer_vip_dns_names | join(' ') }}


# -----------------------------------------------------
# 2. /etc/hosts 설정 검증 (타겟 서버 파일에서 서버별 항목 확인)
# -----------------------------------------------------
- name: "Check /etc/hosts entries"
  command: "grep -F '{{ hostvars[item].ansible_host }} {{ item }}' /etc/hosts"
  loop: "{{ groups['server_configuration'] }}"
  register: hosts_check
  changed_when: false
  failed_when: false

- name: "Assert /etc/hosts entries present"
  assert:
    that:
      - item.rc == 0
    success_msg: "Good!.. | /etc/hosts entry present: {{ item.item }}"
    fail_msg: "ERROR!.. | /etc/hosts entry missing: {{ item.item }}"
  loop: "{{ hosts_check.results }}"

# -----------------------------------------------------
# 3. data-layer DNS 이름 검증 (node 계열)
# -----------------------------------------------------
- name: "Check /etc/hosts data-layer DNS entries"
  command: "grep -F '{{ hostvars[item].ansible_host }} {{ data_layer_dns_names | join(' ') }}' /etc/hosts"
  loop: "{{ groups['server_configuration'] }}"
  register: dns_hosts_check
  changed_when: false
  failed_when: false

- name: "Assert /etc/hosts data-layer DNS entries present"
  assert:
    that:
      - item.rc == 0
    success_msg: "Good!.. | /etc/hosts DNS entry present: {{ hostvars[item.item].ansible_host }} {{ data_layer_dns_names | join(' ') }}"
    fail_msg: "ERROR!.. | /etc/hosts DNS entry missing/incomplete: {{ hostvars[item.item].ansible_host }} {{ data_layer_dns_names | join(' ') }}"
  loop: "{{ dns_hosts_check.results }}"

# -----------------------------------------------------
# 4. 이름 출현 횟수까지 확인 → 기대값은 '이름 개수 × 노드 수'다.
# -----------------------------------------------------
- name: "Count /etc/hosts data-layer DNS name occurrences"
  shell: "grep -owE '{{ data_layer_dns_names | join('|') }}' /etc/hosts | wc -l"
  register: dns_hosts_count
  changed_when: false
  failed_when: false

- name: "Assert /etc/hosts data-layer DNS name occurrence count"
  assert:
    that:
      - dns_hosts_count.stdout | int == (data_layer_dns_names | length) * (groups['server_configuration'] | length)
    success_msg: "Good!.. | data-layer DNS name occurrences: {{ dns_hosts_count.stdout }} (names: {{ data_layer_dns_names | length }} x nodes: {{ groups['server_configuration'] | length }})"
    fail_msg: "ERROR!.. | data-layer DNS name occurrences={{ dns_hosts_count.stdout }} (expected {{ (data_layer_dns_names | length) * (groups['server_configuration'] | length) }} = names {{ data_layer_dns_names | length }} x nodes {{ groups['server_configuration'] | length }})"

# -----------------------------------------------------
# 5. data-layer DNS 이름 검증 (VIP 계열)
# -----------------------------------------------------
- name: "Check /etc/hosts ingress VIP DNS entry"
  command: "grep -F '{{ ingress_vip }} {{ data_layer_vip_dns_names | join(' ') }}' /etc/hosts"
  register: vip_hosts_check
  changed_when: false
  failed_when: false

- name: "Assert /etc/hosts ingress VIP DNS entry present"
  assert:
    that:
      - vip_hosts_check.rc == 0
    success_msg: "Good!.. | /etc/hosts VIP entry present: {{ ingress_vip }} {{ data_layer_vip_dns_names | join(' ') }}"
    fail_msg: "ERROR!.. | /etc/hosts VIP entry missing/incomplete: {{ ingress_vip }} {{ data_layer_vip_dns_names | join(' ') }}"

# -----------------------------------------------------     
# 6. 이름 출현 횟수까지 확인
# -----------------------------------------------------
- name: "Count /etc/hosts ingress VIP DNS name occurrences"
  shell: "grep -owE '{{ data_layer_vip_dns_names | join('|') }}' /etc/hosts | wc -l"
  register: vip_hosts_count
  changed_when: false
  failed_when: false

- name: "Assert /etc/hosts ingress VIP DNS name occurrence count"
  assert:
    that:
      - vip_hosts_count.stdout | int == (data_layer_vip_dns_names | length)
    success_msg: "Good!.. | VIP DNS name occurrences: {{ vip_hosts_count.stdout }} (names: {{ data_layer_vip_dns_names | length }} x 1 line)"
    fail_msg: "ERROR!.. | VIP DNS name occurrences={{ vip_hosts_count.stdout }} (expected {{ data_layer_vip_dns_names | length }} — VIP 는 노드 수만큼 반복하지 않는다)"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ /etc/hosts 파일 생성 (멱등성 핵심)
- `copy: content`로 파일 전체를 선언형 관리 — 내용이 같으면 재실행 시 **changed=0** 보장
- localhost, IPv6 localhost 기본 항목 포함, 소유자 root / 권한 0644
---
### 2️⃣ 인벤토리 기반 호스트 등록
- 인벤토리 그룹 server_configuration 기준
- 각 서버의 ansible_host(IP)와 호스트명을 매핑하여 자동 추가
- 모든 서버에서 동일한 /etc/hosts 파일 유지
---
### 3️⃣ data-layer 이름을 두 계열로 나눠 등록
공통 규칙 — 구분자가 밑줄이 아니라 하이픈인 이유는 DNS 호스트명 라벨이 영문/숫자/하이픈만
허용하기 때문(RFC 1123). 특히 레지스트리는 Docker 이미지 참조 파서의 domain 규칙
(`[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?`) 때문에 밑줄이 들어가면 **이미지 참조로 파싱조차
되지 않는다**. `.local` 을 뗀 이유는 mDNS 전용 예약 도메인(RFC 6762)이라
systemd-resolved/Avahi 가 질의를 가로챌 수 있어서다.

#### ① 노드 IP 계열 — `data_layer_dns_names` (이름 1개 × 노드 수 = 3줄)
- 이름 하나가 **노드 IP 전부**를 A 레코드로 갖는다 (`<노드IP> 이름1 이름2 ...`)
- **장애 전환 주체는 클라이언트다** — 죽은 IP 로 먼저 붙으면 TCP 타임아웃을 기다린 뒤
  다음 IP 로 넘어간다. glibc 가 여러 주소를 반환하려면 `/etc/host.conf` 에
  `multi on`(Ubuntu 기본값)이 있어야 한다
- 여기 남은 이유: **K8s 밖 노드 로컬 설치**라 Service 객체가 없어 인그레스를 끼울
  대상 자체가 없다 — `data-layer-neo4j` 는 `ap` 노드의 systemd 서비스다
  (K8s 로 복귀한 postgres 의 외부 접속은 hosts 이름 없이
  전용 VIP — Terraform 102-ingress `postgres_vip`:5432 — 로 한다.
  `data-layer-minio-console` 은 MinIO 가 301-minio(클러스터 내부 전용, 콘솔 off)로 옮겨 가며 뺐다 —
  노드가 여는 :9001 이 더는 없다)

#### ② VIP 계열 — `data_layer_vip_dns_names` (이름 7개, 총 1줄)
- 이름 전부가 **인그레스 VIP 하나**(`ingress_vip`)를 가리킨다
- **장애 전환 주체는 MetalLB 다** — 노드가 죽으면 VIP 가 살아 있는 노드로 옮겨가므로
  클라이언트는 타임아웃을 기다릴 일이 없고 주소도 그대로다
- 이름별 구분은 hosts 가 아니라 **인그레스가 Host 헤더로** 한다
- 대상: `harbor` · `kafka-ui` · `airflow` · `api` · `grafana` · `prometheus` · `headlamp`
- ⚠ `harbor` 는 특별하다 — 사람이 치는 주소일 뿐 아니라 **이미지 이름의 첫 마디**라서
  `containerd_insecure_registries` · Terraform 전 스택 `harbor_registry` 와 글자 그대로 같아야 한다

> ⚠ 한 이름을 두 계열에 동시에 넣지 말 것 — 클라이언트가 노드 IP 와 VIP 중 아무 데나
> 붙어서 증상이 접속할 때마다 달라진다.
---
### 4️⃣ /etc/hosts 검증
- 타겟 서버 파일에서 서버별 `IP 호스트명` 항목을 `grep -F`로 확인 후 `assert`
- 노드 IP 계열: 줄마다 이름이 **전부** 있는지 노드별로 확인 + 출현 횟수가
  **이름 개수 × 노드 수** 인지 `assert`
- VIP 계열: 줄 존재 확인 + 출현 횟수가 **이름 개수 × 1** 인지 `assert`
  (노드 수를 곱하지 않는다 — VIP 는 총 1줄이다. 그래서 태스크를 나눴다)
- 누락/중복/옛 이름 잔존을 서버별로 식별 가능
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert /etc/hosts entries present]
ok: [192.168.56.200] => (item=...) => {
    "msg": "Good!.. | /etc/hosts entry present: ap"
}

TASK [Assert /etc/hosts data-layer DNS name occurrence count]
ok: [192.168.56.200] => {
    "msg": "Good!.. | data-layer DNS name occurrences: 6 (names: 2 x nodes: 3)"
}

TASK [Assert /etc/hosts ingress VIP DNS name occurrence count]
ok: [192.168.56.200] => {
    "msg": "Good!.. | VIP DNS name occurrences: 7 (names: 7 x 1 line)"
}
```
---
