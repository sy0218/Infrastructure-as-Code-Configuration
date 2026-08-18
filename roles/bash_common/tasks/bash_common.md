# 🧑‍💻 시스템 공통 Bash 환경 설정 (Common Bash)
- 모든 서버에 공통 Bash 환경 설정을 적용하여 운영 일관성을 유지하고
- 사용자 실수 방지를 위해 alias와 프롬프트를 통일합니다.
- 파일 경로/적용 대상/환경변수는 `host.yml` 변수로 관리 (롤은 범용, 인벤토리가 동작 결정)
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 시스템 공통 Bash 환경 설정
# =====================================================


# -----------------------------------------------------
# 1. project 환경변수 파일 생성 (copy 자체가 멱등 → 경로/변수는 host.yml에서 관리)
# -----------------------------------------------------
- name: "Create project env file from inventory variables"
  copy:
    dest: "{{ project_conf_path }}"
    owner: root
    group: root
    mode: '0644'
    content: |
      {% for env in project_envs %}
      export {{ env }}
      {% endfor %}

# -----------------------------------------------------
# 2. bashrc 에 공통 설정 적용 (blockinfile 자체가 멱등 → 대상은 host.yml의 bashrc_targets)
# -----------------------------------------------------
- name: "Apply common bash settings to system targets"
  blockinfile:
    path: "{{ item }}"
    marker: "# {mark} ANSIBLE COMMON BASH CONFIG"
    block: |
      # Load project environment variables
      if [ -f {{ project_conf_path }} ]; then
          source {{ project_conf_path }}
      fi

      if [ -z "${BASH_COMPLETION_VERSINFO-}" ] && [ -f /usr/share/bash-completion/bash_completion ]; then
          source /usr/share/bash-completion/bash_completion
      fi

      # Safe aliases
      alias rm='rm -i'
      alias cp='cp -i'
      alias mv='mv -i'

      # Prompt
      PS1='[\h:\w] '
    create: yes
  loop: "{{ bashrc_targets }}"

# -----------------------------------------------------
# 3. 검증
# -----------------------------------------------------
- name: "Verify project env file exists"
  stat:
    path: "{{ project_conf_path }}"
  register: project_conf

- name: "Verify bash common config applied"
  command: 'grep -q "ANSIBLE COMMON BASH CONFIG" {{ item }}'
  loop: "{{ bashrc_targets }}"
  register: bash_check
  changed_when: false
  failed_when: false

- name: "Assert bash common environment applied"
  assert:
    that:
      - project_conf.stat.exists
      - item.rc == 0
    success_msg: "Good!.. | Common bash config applied: {{ item.item }}"
    fail_msg: "ERROR!.. | Common bash config NOT applied: {{ item.item }}"
  loop: "{{ bash_check.results }}"
```
---
<br>

## 📌 host.yml 예시
```yaml
# project 환경변수 파일 경로
project_conf_path: /etc/project.conf
# 공통 bash 설정 적용 대상 파일
bashrc_targets:
  - /root/.bashrc
  - /etc/skel/.bashrc
# project 환경 변수
project_envs:
  - JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  - KAFKA_HOME=/application/kafka
  - PATH=$JAVA_HOME/bin:$KAFKA_HOME/bin:$PATH
```
---
<br>

## 🛠 작업 내용
### 1️⃣ project 환경변수 파일 생성 (멱등성 핵심)
- `project_conf_path` 경로에 `project_envs` 리스트를 export 구문으로 생성
- `copy: content` 자체가 멱등 — 내용이 같으면 재실행 시 **changed=0** 보장
---
### 2️⃣ Bash 공통 설정 적용
- `bashrc_targets`의 각 파일에 `blockinfile`로 공통 블록 적용 — 자체 멱등
- 환경 파일 source, bash 탭 완성 활성화, rm/cp/mv `-i` alias, 프롬프트(PS1) 통일
- 탭 완성의 활성화 경로는 셸 종류에 따라 갈린다 (ap 노드 실측 기준):
  - **로그인 셸** (`ssh`, `su -`, `sudo -i`) — `bash-completion` 패키지가 함께 깔아주는
    `/etc/profile.d/bash_completion.sh` 가 이미 켠다. 이 롤이 할 일이 없다.
  - **비로그인 인터랙티브 셸** (`sudo su`, `su`, 중첩 `bash`) — Ubuntu 24.04 가 `/etc/bash.bashrc`(34~40행)와
    `/root/.bashrc`(97~98행)의 스탠자를 **주석 상태로 배포**해서 안 켜진다. **이 구멍을 이 롤이 메운다.**
- 패키지 설치는 `install_packages`(packages 롤)가, source 는 이 롤이 담당한다 — 둘 다 필요하다.
- `BASH_COMPLETION_VERSINFO` 가드를 두는 이유: `/etc/skel/.bashrc` 는 스탠자가 이미 활성(108~116행)이라
  가드 없이 넣으면 76KB 완성 스크립트를 두 번 읽는다(스크립트 자체에 재진입 가드가 없다).
  같은 가드를 배포판의 `/etc/profile.d/bash_completion.sh` 도 쓴다 — 관용구를 그대로 따른 것.
---
### 3️⃣ 설정 검증
- 환경변수 파일 존재(`stat`) + 대상 파일별 설정 블록 존재(`grep`)를 `assert`
- 대상별 loop 검증으로 누락 파일 식별 가능
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert bash common environment applied]
ok: [192.168.56.60] => (item=...) => {
    "msg": "Good!.. | Common bash config applied: /root/.bashrc"
}
```
