# 🛠 Ansible 기반 서버 구성 자동화 플랫폼 (IaC)

**Ansible 기반 IaC로 인프라를 코드로 선언하고,
OS 및 실행 환경을 자동으로 구성하는 프로젝트 입니다.**

**`Infrastructure as Code`** 기반으로 **인프라 환경을 코드로 정의하여 재현성을 확보**하고, **재사용성과 확장성**을 고려한 **표준화된 서버 구성 자동화**를 목표로 합니다.

---
</br>

## 🤔 왜 자동화 방식을 변경했는가?

> 초기에는 `Python/Shell` 등 프로그래밍 언어를 이용해 서버 구축을 자동화했습니다.

**반복 작업은 줄일 수 있었지만..** → 서버 구성이 변경될 때마다 **새로운 코드를 작성**해야 했고, 에러가 발생하면 **코드 내부를 직접 추적**하며 원인을 찾아야 했습니다.

결국 **운영을 자동화하기 위해 만든 자동화 코드 자체가 또 하나의 운영 대상**이 되었고, 유지보수 비용이 점점 증가했습니다.

이러한 문제를 해결하기 위해 범용 프로그래밍보다 **인프라 자동화에 특화된 IaC 도구**를 도입하여 유지보수성과 재사용성을 높였습니다.

---
</br>

## 🧐 Ansible로 해결가능한 문제

> **Ansible를 통해 프로그래밍 기반 자동화의 유지보수 문제를 해결할 수 있습니다.**

- 서버 구성이 변경되어도 **자동화 코드를 수정하지 않아도 됨** → `host.yml` 만 수정
- Role(역할) 단위로 재사용 가능
- `state`, `lineinfile` 등 **멱등성을 지원하는 Ansible 모듈**을 제공하여 동일한 작업을 여러 번 실행해도 원하는 상태를 쉽게 유지
- 사람이 작성한 **운영 절차서와 비슷한 형태**라 읽기 쉽고 유지보수가 쉬움
---
</br>

## ⚠️ Ansible 단점 및 고려사항

> 직접 구축은 엔지니어가 서버를 하나씩 확인하며 작업하기 때문에 설정에 대한 **신뢰성을 직접 검증**할 수 있습니다.

> **반면, `Ansible`은 잘못된 `Playbook`이나 설정이 있으면 동일한 오류가 여러 서버에 동시에 적용될 수 있으므로, 자동화 결과를 검증하는 체계가 반드시 필요합니다.**

> **또한, 서버가 많아지고 `Role`과 `Playbook`이 복잡해질수록 설정의 관리/문서화까지 함께 고려해야 합니다.**

### **즉, 도구의 장점만 보는 것이 아니라 → 운영 과정에서 발생할 수 있는 문제를 사전에 파악하고 대응 방안을 마련하는 것이 중요합니다.**


---

### ⚠️ 단점 1) 자동화 결과를 100% 신뢰하기 어렵다
- `Playbook`이 **성공적으로 실행되었다고 해서 서비스가 정상 동작하는 것은 아닙니다.**
- `Ansible`은 **설정을 적용하는 도구**이지, 애플리케이션의 정상 동작까지 모두 보장하는 것은 아닙니다.

**예를 들어,**
- 패키지는 설치되었지만 서비스가 실행되지 않음
- 설정 파일은 변경되었지만 설정 오류로 서비스가 기동되지 않음
- 즉, **"Playbook 실행 성공" ≠ "서비스 정상 운영"**

---

### **✅ 대응 방안**
#### **1. Role마다 최종 검증(assert) 추가 ✅**
- 각 `Role`의 마지막에 `assert` 모듈을 추가하여 설정뿐 아니라 실제 서비스 상태까지 확인합니다.
```yaml
- name: "Assert bash common environment applied"
  assert:
    that:
      - project_conf.stat.exists
      - item.rc == 0
    success_msg: "Good!.. | Common bash config applied: {{ item.item }}"
    fail_msg: "ERROR!.. | Common bash config NOT applied: {{ item.item }}"
  loop: "{{ bash_check.results }}"
```
#### 효과
- 설정 적용 여부 확인
- 서비스 정상 실행 여부 확인
- 문제가 있으면 **자동화 과정에서 즉시 실패**

---

#### **2. Custom Callback Plugin으로 실행 결과 가시화 ✅**
- Ansible 기본 출력인 `ok=20 changed=5 failed=0` 만으로는 **어떤 Role과 서버에서 문제가 발생했는지 한눈에 파악하기 어렵습니다.**
- 따라서, `Callback Plugin`을 이용하여 **`Role`별/`Host`별 실행 결과를 요약해서 표시합니다.**
```text
========== Ansible Summary ==========

Role Result
-------------
common     : OK 15 / Changed 3 / Failed 0
docker     : OK 10 / Changed 5 / Failed 0

Host Result
-------------
server01   : SUCCESS
server02   : SUCCESS

Total
-------------
Tasks       : 45
Changed     : 8
Failed      : 0
=====================================
```
#### 효과
- 어떤 Role에서 문제가 발생했는지 즉시 확인
- 서버별 실행 결과를 한눈에 확인
- 자동화 실행 결과를 **엔지니어가 빠르게 검증 가능**

---


### ⚠️ 단점 2) Playbook과 Role이 많아질수록 관리가 복잡해진다.
- 서버와 `Role`이 늘어나면 **어떤 `Role`이 어떤 설정을 담당하는지 파악하기 어려워질 수 있습니다.**
- 각 Role이 어떤 서버에 어떤 영향을 주는지 추적하기 어려워집니다.

**예를 들어,**
- `common` Role에서 어떤 설정을 관리하는지 알기 어려움
- 동일한 설정이 여러 `Role`에 중복 작성됨
- 특정 `Role`을 적용 시, 어느 서버에 영향을 주는지 파악하기 어려움

---

### **✅ 대응 방안**
#### **1. Ansible 구조 및 작성 규칙 문서화 ✅**
- 변수명, 디렉터리 구조, Task 작성 방식 등의 **공통 규칙을 문서화**합니다.

---

#### **2. Claude Skill을 활용한 문서 자동화 및 동기화 ✅**
- `Role`의 `main.yml`이 변경될 때마다 **`Role`별 문서를 함께 생성/갱신하도록 `Claude Skill`을 정의합니다.**
- `main.yml`의 전체 소스와 작업 목적, 사용 변수, 실행 결과 등을 정해진 문서 양식으로 관리합니다.
- 이를 통해 **코드와 문서가 서로 다른 상태로 유지되는 문제를 줄입니다.**

```text
Claude Skill 주요 규칙

roles/<롤이름>/tasks/main.yml
        │
        ├── handlers/
        ├── templates/
        └── group_vars/
                ↓
        Claude Skill
                ↓
roles/<롤이름>/tasks/<롤이름>.md

- main.yml 전체 내용을 문서에 자동 반영
- group_vars에서 실제 참조 변수만 발췌
- Task의 단계별 목적과 멱등성·가드·주의사항 설명
- handlers가 있으면 함께 문서화
- 마지막 assert 결과를 실행 결과 예시로 기록
- main.yml 변경 시 기존 문서와 비교하여 변경된 내용을 갱신
```

#### 효과
- **코드와 문서의 불일치 방지**
- 신규 엔지니어도 Role 구조를 빠르게 이해
- 반복적인 문서 작성 작업 감소

---


### **🎯 대응 핵심**
- 검증 모듈(`assert`)로 실제 적용 상태를 확인하여 **자동화 결과의 신뢰성을 높입니다.**
- `Custom Callback Plugin`으로 Role별/Host별 **실행 결과를 가시화하여 자동화 결과를 한눈에 파악**할 수 있도록 합니다.
- **문서화 규칙을 정의**하여 `Role`별 책임과 설정 범위를 명확하게 관리하고 **유지보수성을 확보**합니다.
- **Claude Skill을 활용하여 Role 신규 생성 및 변경 → Role 문서 자동 생성/갱신** 흐름을 구축함으로써, 코드와 문서가 서로 다른 상태로 유지되는 문제를 줄이고 **​문서 관리의 지속성을 확보**합니다.




---
</br>

## ❓ 왜 Configuration은 Ansible인가?
> **테라폼도 `remote-exec`를 이용하면 서버에서 명령을 실행할 수 있습니다.**

> **하지만, `remote-exec`로 수행되는 작업은 **Terraform State**의 관리 대상이 아닙니다.**

```text
즉, 패키지를 설치하거나 사용자를 생성해도 Configuration은 State에 기록되지 않으며,
→ 이후 변경 여부나 현재 설정 상태를 Terraform이 추적할 수 없습니다.
```
```text
반면, Ansible은 Configuration Management를 목적으로 설계된 도구입니다.

모듈을 통해 현재 서버 상태를 확인한 뒤 필요한 작업만 수행하므로,
→ 플레이북을 여러 번 실행해도 원하는 상태를 일관되게 유지할 수 있습니다.
```

### 예를 들어
```text
사용자를 생성하거나 패키지를 설치하는 작업을 remote-exec로 수행하면,
이미 존재하는지 여부를 직접 스크립트에서 확인해야 하며
→ 특정 로직에서는 멱등성을 보장하기 어렵습니다.
```

### 반면 `Ansible`은 **모듈 기반**으로 동작합니다.
- 패키지가 이미 설치되어 있는지
- 사용자가 이미 존재하는지
- 설정 파일이 변경되었는지

> **현재 서버 상태를 먼저 확인한 후 필요한 작업만 수행합니다.**

> 즉, 플레이북을 여러 번 실행해도 변경이 필요한 경우에만 작업이 수행되므로 안정적인 **Configuration Management**가 가능합니다.



---
</br>

## ❓ 왜 Provisioning은 Terraform인가?
> **Ansible도 서버나 Kubernetes 클러스터를 생성할 수 있습니다.**

> 하지만, 인프라 운영은 **생성보다 변경과 유지가 더 많습니다.**

```text
테라폼은 생성한 인프라를 "State"로 관리합니다.

State를 기반으로 현재 환경과 코드의 차이를 비교하여 필요한 변경만 안전하게 적용하며,
어떤 리소스가 존재하는지, 무엇이 변경될 예정인지도 Plan 단계에서 직관적으로 확인 할 수 있습니다.

또한 리소스 간 의존성을 자동으로 처리하므로 대규모 인프라의 생명주기를 일관되고 안정적으로 관리할 수 있습니다.
```
```text
반면 Ansible은 별도의 State를 관리하지 않습니다.

실행 시 모듈 기반으로, 현재 서버 상태를 확인하여 필요한 작업만 수행하는 Configuration Management 도구이며
인프라 전체의 생명주기와 변경 이력을 관리하는 것이 목적은 아닙니다.
```

> 따라서, 이 프로젝트에서는 **인프라의 생성/변경/삭제 등 생명주기 관리는 Terraform**으로 관리하고

> **생성된 서버의 환경과 운영은 Ansible**이 담당하도록 역할을 분리했습니다.


### 애플리케이션은 운영체제만으로 실행되지 않습니다. 실제 서비스를 운영하려면 다음과 같은 기반 인프라가 함께 준비되어야 합니다.
- 서버
- 네트워크
- 스토리지
- `Load Balancer` 등 운영 환경
- `Kubernetes` 클러스터

> 즉, **애플리케이션이 실행될 기반 환경 전체를 준비하는 과정**이 바로 **`Provisioning`** 입니다.

### Kubernetes도 프로비저닝 대상인가?
쿠버네티스는 클러스터 환경에서 컨테이너를 관리하는 **오케스트레이션 플랫폼**이지만, **운영 관점에서는 단순히 하나의 애플리케이션을 설치하는 수준이 아닙니다.**

클러스터를 구성하려면
- Control Plane과 Worker 노드 구성
- CNI(Network) 설치
- CSI(Storage) 구성
- ingress(L7)
- Load Balancer(L2, L3)
- 인증서 및 클러스터 기본 설정

> **운영 환경을 이루는 핵심 인프라**가 함께 준비되어야 합니다.

> **따라서 해당 프로젝트에서는 `Kubernetes`를 하나의 인프라 리소스로 보고 `Terraform`을 이용해 생성 및 관리했습니다.**

---
</br>

## 🛠 역할 분담
| 구분 | Terraform | Ansible |
|------|-----------|----------|
| **역할** | **무엇을 만들 것인가**를 관리 | **어떻게 구성할 것인가**를 관리 |
| **대상** | 서버(VM), Kubernetes, 네트워크, 스토리지 등 인프라 | OS 설정, 패키지 설치, 사용자, 서비스 구성 |
| **관리 방식** | Infrastructure Provisioning | Configuration Management |
| **주요 특징** | State 기반으로 인프라 생성/변경/삭제 관리 | 현재 상태를 모듈 기반으로 확인한 후 필요한 작업만 수행(멱등성) |
| **결과** | 실행 가능한 운영 환경을 준비 | 운영 환경을 원하는 상태로 표준화 |

---
</br>

## ✨ 주요 특징
- **Role 기반 모듈 구조** : 기능 단위로 분리된 38개 롤을 조합해 서버 구성
- **단계별 플레이북** : OS 기본/K8s/부가 도구/데이터 스토어까지 10개 플레이북으로 분리 실행
- **중앙 집중 변수** : 버전/경로/계정을 `group_vars/`의 그룹별 파일에서 관리 (인벤토리 `host.yml`은 구조만)
- **멱등성 보장** : 재실행해도 안전, 변경이 필요한 항목만 적용
- **멀티서버 확장성** : 인벤토리에 서버만 추가하면 N대 동시 프로비저닝

---
</br>

## 📋 요구 사항
| 항목 | 내용 |
|------|------|
| **`OS`** | Ubuntu 24.04 |
| **`Control Node`** | 1대 (`Ansible` 설치 대상) |
| **`Managed Node`** | N대 (`Control Node`에서 `SSH` 접근 가능해야 함) |
| **`User Account`** | 모든 서버에서 **sudo 사용 가능한 사용자 (필수)** |
---
</br>

## 📂 디렉토리 구조
```bash
Infrastructure-as-Code-Ansible/
├── ansible.cfg            # Ansible 공통 설정
├── host.yml               # 인벤토리 (호스트/그룹 구조)
├── group_vars/            # 그룹별 변수 (그룹당 파일 하나, 자동 로드)
│   ├── Ubuntu_Servers.yml
│   ├── kubernetes.yml
│   ├── longhorn.yml
│   ├── local_git.yml
│   ├── terraform.yml
│   ├── helm.yml
│   ├── docker.yml
│   ├── kafka.yml
│   ├── postgres.yml
│   ├── minio.yml
│   ├── neo4j.yml
│   └── buildkitd.yml
├── ubuntu_ansible.yml     # 운영 서버 Configuration 플레이북
├── k8s_ansible.yml        # K8s 클러스터 구성 플레이북
├── longhorn_ansible.yml   # Longhorn 사전 준비 플레이북
├── local_git_ansible.yml  # Airflow Git 저장소 부트스트랩 플레이북
├── terraform_ansible.yml  # Terraform 설치 플레이북
├── helm_ansible.yml       # Helm 설치 플레이북
├── docker_ansible.yml     # Docker 설치 플레이북
├── kafka_ansible.yml      # Kafka(KRaft) 설치 플레이북
├── postgresql_ansible.yml # PostgreSQL(TimescaleDB) 설치 플레이북
├── minio_ansible.yml      # MinIO(SNSD) 설치 플레이북
├── neo4j_ansible.yml      # Neo4j 설치 플레이북
├── buildkitd_ansible.yml  # BuildKit(빌드 데몬) 설치 플레이북
├── bin/
│   ├── ansible_setup.sh       # Ansible 설치 (Control Node용)
│   ├── start_ansible.sh       # 운영 서버 Configuration 실행
│   ├── start_kubernetes.sh    # Kubernetes 구성 실행
│   ├── start_longhorn.sh      # Longhorn 사전 준비 실행
│   ├── start_local_git.sh     # Git 저장소 부트스트랩 실행
│   ├── start_terraform.sh     # Terraform 설치 실행
│   ├── start_helm.sh          # Helm 설치 실행
│   ├── start_docker.sh        # Docker 설치 실행
│   ├── start_kafka.sh         # Kafka 설치 실행
│   ├── start_postgresql.sh    # PostgreSQL 설치 실행
│   ├── start_minio.sh         # MinIO 설치 실행
│   ├── start_neo4j.sh         # Neo4j 설치 실행
│   └── start_buildkitd.sh     # BuildKit 설치 실행
├── COMMIT_CONVENTION.md  # Git 커밋 규칙
├── callback_plugins/
│   └── summary_table.py  # 실행 결과 요약 표 callback 플러그인
└── roles/                # 기능별 Ansible Role (39종)
    ├── control/
    ├── packages/
    ├── java/
    └── ...
```
> **roles/ 디렉토리는 기능별 모듈 구조로 구성되며, 각 role은 tasks/main.yml을 기준으로 실행됩니다.**

---
</br>

## ⚙️ Ansible 설치 (Control Node만)
> **`[중요]`** **Ansible은 Control Node에만 설치합니다.**
```bash
sudo /my_project/Infrastructure-as-Code-Ansible/bin/ansible_setup.sh
```

---
</br>

## 🚀 Ansible 실행
> **`[중요]`** **Ansible 프로젝트 홈 디렉토리의 절대 경로 + tag** 를 인자로 전달하여 실행합니다.

```bash
# 서버 프로비저닝 (ubuntu_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_ansible.sh /my_project/Infrastructure-as-Code-Ansible all

# K8s 클러스터 구성 (k8s_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_kubernetes.sh /my_project/Infrastructure-as-Code-Ansible all

# Longhorn 노드 사전 준비 (longhorn_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_longhorn.sh /my_project/Infrastructure-as-Code-Ansible all

# Terraform 설치 (terraform_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_terraform.sh /my_project/Infrastructure-as-Code-Ansible all

# Helm 설치 (helm_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_helm.sh /my_project/Infrastructure-as-Code-Ansible all

# Docker 설치 (docker_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_docker.sh /my_project/Infrastructure-as-Code-Ansible all

# Kafka 설치 (kafka_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_kafka.sh /my_project/Infrastructure-as-Code-Ansible all

# PostgreSQL 설치 (postgresql_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_postgresql.sh /my_project/Infrastructure-as-Code-Ansible all

# MinIO 설치 (minio_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_minio.sh /my_project/Infrastructure-as-Code-Ansible all

# Neo4j 설치 (neo4j_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_neo4j.sh /my_project/Infrastructure-as-Code-Ansible all

# BuildKit 설치 (buildkitd_ansible.yml) — docker 없는 이미지 빌드/push 데몬
# ⚠ push 는 200-harbor apply 이후에나 가능하다 (설치 자체는 언제든 무방)
/my_project/Infrastructure-as-Code-Ansible/bin/start_buildkitd.sh /my_project/Infrastructure-as-Code-Ansible

# Airflow 코드 저장소 부트스트랩 (local_git_ansible.yml)
# ⚠ Terraform 303-git apply 뒤, 304-airflow apply 앞에서만 실행
/my_project/Infrastructure-as-Code-Ansible/bin/start_local_git.sh /my_project/Infrastructure-as-Code-Ansible all
```
> ⚠️ **반드시 Ansible 프로젝트의 절대 경로와 태그를 인자로 전달해서 실행하세요.**

> `ansible.cfg`의 inventory/roles_path가 상대 경로라 프로젝트 루트에서 실행돼야 합니다

> **`start_*.sh`가 `cd`를 대신 해줍니다.**

---
</br>

## 🔧 공통 설정 (ansible.cfg)
> **실행 옵션을 한 곳에 모아 `CLI` 옵션 없이 동일한 동작을 보장**합니다.
- `inventory = host.yml` → 인벤토리 자동 지정 (`-i` 불필요)
- `roles_path = ./roles` → 롤 경로 (**상대 경로 → 프로젝트 루트에서 실행 필수**)
- `host_key_checking = False` → 최초 `SSH` 접속 시 호스트 키 확인 생략
- `pipelining = True` → `SSH` 파이프라이닝으로 실행 속도 향상
- `forks = 2` → 동시 실행 호스트 수
- `stdout_callback = yaml` → 출력 가독성
- `callback_plugins = ./callback_plugins` → 커스텀 callback 플러그인 경로 (`summary_table` → 실행 결과 요약 표)

---
</br>

## ⚙️ Custom Callback Plugin
> `Ansible` 기본 출력은 실행 성공/실패 정도만 보여주기 때문에 운영자가 전체 결과를 빠르게 판단하기 어렵습니다.

### `Custom Callback Plugin`을 사용하면 `Playbook` 종료 후 → 자동화 전체 결과를 한눈에 확인할 수 있습니다.
- `Role / Task` 별 실행 결과
- `Host` 별 성공 여부
- 전체 실행 통계

<details>
<summary><strong>📄 summary_table.py 전체 코드 보기 (Custom Callback)</strong></summary>

```python3
# ==================================================
# summary_table — 실행 결과 요약 표 callback 플러그인
# ==================================================
# aggregate 타입 — stdout_callback(yaml)을 대체하지 않고
# 기존 출력을 유지한 채 PLAY RECAP 뒤에 요약 표만 덧붙인다.
# assert 태스크는 SUCCESS/FAILED 대신 PASS/FAIL로 표기해
# '검증 블록으로 끝나는 롤' 하우스 스타일과 맞춘다.
from unicodedata import east_asian_width

from ansible import constants as C
from ansible.plugins.callback import CallbackBase


def _disp_w(text):
    """터미널 표시 폭 — 한글 등 동아시아 전각 문자는 2칸으로 계산한다."""
    return sum(2 if east_asian_width(ch) in 'WF' else 1 for ch in text)


def _pad(text, width):
    """표시 폭 기준 왼쪽 정렬 (str.ljust는 글자 수 기준이라 한글이 밀린다)."""
    return text + ' ' * max(0, width - _disp_w(text))

DOCUMENTATION = '''
    name: summary_table
    type: aggregate
    short_description: 롤/태스크/호스트별 실행 결과 요약 표
    description:
      - 플레이북 종료 시 롤·태스크별 결과 표, 호스트별 통계, 총계를 출력한다.
      - assert 태스크는 PASS/FAIL, 일반 태스크는 SUCCESS/FAILED로 표기한다.
    author: Infrastructure-as-Code-Ansible
'''


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'summary_table'

    # 상태별 출력 색 (파이프로 내보내면 Ansible이 색을 자동 제거)
    _COLORS = {
        'SUCCESS': C.COLOR_OK, 'PASS': C.COLOR_OK,
        'FAILED': C.COLOR_ERROR, 'FAIL': C.COLOR_ERROR,
        'UNREACHABLE': C.COLOR_UNREACHABLE,
        'SKIPPED': C.COLOR_SKIP, 'IGNORED': C.COLOR_WARN,
        'RESCUED': C.COLOR_WARN,
    }

    def __init__(self):
        super().__init__()
        self._tasks = {}   # task_uuid → {'role', 'task', 'is_assert', 'hosts': {host: 상태}}
        self._order = []   # 실행 순서 보존용 task_uuid 목록

    # ---------- 결과 수집 ----------
    def _record(self, result, status):
        task = result._task
        uuid = task._uuid
        if uuid not in self._tasks:
            role = task._role.get_name() if task._role else '-'
            name = task.get_name()
            # 롤 소속 태스크는 이름이 "롤명 : 태스크명"이라 롤 컬럼과 중복 — 접두어 제거
            prefix = '%s : ' % role
            if name.startswith(prefix):
                name = name[len(prefix):]
            self._order.append(uuid)
            self._tasks[uuid] = {
                'role': role,
                'task': name,
                'is_assert': task.action.rsplit('.', 1)[-1] == 'assert',
                'hosts': {},
            }
        self._tasks[uuid]['hosts'][result._host.get_name()] = status

    def v2_runner_on_ok(self, result):
        self._record(result, 'ok')

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._record(result, 'ignored' if ignore_errors else 'failed')

    def v2_runner_on_skipped(self, result):
        self._record(result, 'skipped')

    def v2_runner_on_unreachable(self, result):
        # ignore_unreachable 태스크는 PLAY RECAP과 동일하게 통과(ignored)로 집계
        ignore = getattr(result._task, 'ignore_unreachable', False)
        self._record(result, 'ignored' if ignore else 'unreachable')

    # ---------- 표기 결정 ----------
    @staticmethod
    def _task_result(entry):
        statuses = set(entry['hosts'].values())
        if 'unreachable' in statuses:
            return 'UNREACHABLE'
        if 'failed' in statuses:
            return 'FAIL' if entry['is_assert'] else 'FAILED'
        if 'rescued' in statuses:
            return 'RESCUED'
        if statuses == {'skipped'}:
            return 'SKIPPED'
        if 'ignored' in statuses:
            return 'IGNORED'
        return 'PASS' if entry['is_assert'] else 'SUCCESS'

    # ---------- 요약 표 출력 ----------
    def v2_playbook_on_stats(self, stats):
        if not self._order:
            return
        entries = [self._tasks[u] for u in self._order]

        # block/rescue 보정: PLAY RECAP 기준 실제 실패(stats.failures)보다 많은
        # 'failed' 기록은 rescue로 구제된 것 — 실행 순서 앞쪽부터 재라벨한다
        # (구제되지 않은 fatal 실패는 해당 호스트의 마지막 failed일 수밖에 없다)
        for host in {h for e in entries for h in e['hosts']}:
            failed_entries = [e for e in entries if e['hosts'].get(host) == 'failed']
            rescued_n = len(failed_entries) - stats.failures.get(host, 0)
            for e in failed_entries[:rescued_n]:
                e['hosts'][host] = 'rescued'
        role_w = max(_disp_w('Role'), max(_disp_w(e['role']) for e in entries))
        task_w = max(_disp_w('Task'), max(_disp_w(e['task']) for e in entries))
        line_w = role_w + task_w + len('UNREACHABLE') + 4
        bar = '=' * line_w
        d = self._display.display

        d('')
        d(bar)
        d(' Ansible Execution Summary')
        d(bar)
        d('')
        d('%s  %s  %s' % (_pad('Role', role_w), _pad('Task', task_w), 'Result'))
        d('-' * line_w)
        prev_role = None
        for e in entries:
            if prev_role is not None and e['role'] != prev_role:
                d('')   # 롤 그룹 사이 빈 줄
            prev_role = e['role']
            res = self._task_result(e)
            d('%s  %s  %s' % (_pad(e['role'], role_w), _pad(e['task'], task_w), res),
              color=self._COLORS.get(res))

        # 호스트별 집계 (ignored는 통과로 계산, skipped는 분모 제외)
        per_host = {}
        for e in entries:
            for host, st in e['hosts'].items():
                c = per_host.setdefault(
                    host, {'ok': 0, 'failed': 0, 'skipped': 0,
                           'unreachable': 0, 'rescued': 0})
                c['ok' if st == 'ignored' else st] += 1

        d('')
        d(bar)
        d('HOST SUMMARY')
        d('')
        host_w = max(_disp_w(h) for h in per_host)
        for host in sorted(per_host):
            c = per_host[host]
            executed = c['ok'] + c['failed'] + c['rescued']
            if c['unreachable']:
                label = 'UNREACHABLE'
            elif c['failed']:
                label = 'FAIL'
            elif executed == 0:
                label = 'SKIPPED'   # 실행 0건 — 통과(PASS)로 오해하지 않게 구분
            else:
                label = 'PASS'
            d('%s : %s (%d/%d)' % (_pad(host, host_w), label, c['ok'], executed),
              color=self._COLORS.get(label))

        # 총계 (호스트 x 태스크 실행 건수 기준)
        passed = sum(c['ok'] for c in per_host.values())
        failed = sum(c['failed'] for c in per_host.values())
        skipped = sum(c['skipped'] for c in per_host.values())
        unreach = sum(c['unreachable'] for c in per_host.values())
        rescued = sum(c['rescued'] for c in per_host.values())
        d('')
        d('TOTAL')
        d('Tasks : %d' % (passed + failed + skipped + unreach + rescued))
        d('Passed: %d' % passed)
        d('Failed: %d' % failed)
        if skipped:
            d('Skipped: %d' % skipped)
        if rescued:
            d('Rescued: %d' % rescued)
        if unreach:
            d('Unreachable: %d' % unreach)
        d(bar)
```
</details>

---
</br>

## 📑 인벤토리 (host.yml + group_vars/)
- **대상 서버 목록과 그룹 구조는 → `host.yml`**
- **롤에서 사용하는 변수는 → `group_vars/<그룹>.yml`**

- **롤에는 `defaults/`, `vars/`가 없어 모든 변수가 `group_vars/`에 모여 있습니다.**
- **그룹 = 플레이북 단위** → 그룹에 서버를 추가/제거하는 것만으로 대상 확장
- `host.yml`에는 구조와 호스트 고유값(`ansible_host`, `kafka_node_id`)만 둡니다
- 접속 계정, sudo 비밀번호, 설치 패키지 목록, 버전 핀, 포트, 계정, 버킷 이름 등은 해당 그룹의 `group_vars/` 파일에서 관리
- `group_vars/`는 인벤토리와 같은 디렉토리에 있어 **자동으로 로드**됩니다
  - **`[주의]` 파일명은 그룹명과 대소문자까지 같아야 합니다**(`Ubuntu_Servers.yml`)

| 그룹 | 대상 | 쓰는 플레이북 |
|------|------|----------------|
| `Ubuntu_Servers` | ap / s1 / s2 | ubuntu |
| `kubernetes` (`kubernetes_master`=ap / `kubernetes_workers`=s1, s2) | ap / s1 / s2 | k8s |
| `longhorn` / `docker` / `kafka` | ap / s1 / s2 | longhorn / docker / kafka |
| `postgres` / `minio` / `neo4j` | ap | postgresql / minio / neo4j |
| `terraform` / `helm` / `local_git` | s2 | terraform / helm / local_git |

---
</br>

## 📜 플레이북 (ubuntu_ansible.yml)
> **Ubuntu 서버의 기본 패키지 설치, 시스템 설정, 런타임 환경 구성을 담당하는 메인 Ansible 플레이북입니다.**
- **Play 1** → `Control Node` 설정 (`localhost`, `sshpass`)
- **Play 2** → `Ubuntu_Servers` 그룹에 운영 서버 `Configuration` 롤 순차 적용
- **적용할 롤은 `roles:` 목록에서 선택**
- 순서 의존: `java` → `package_version_lock` / `bash_common`
- ⚠ **스왑은 켠 채로 운영한다** → `disable_swap` 주석 / `enable_swap` 활성은 의도다(K8s LimitedSwap). 뒤집으면 K8s 플레이의 스왑 검증이 실패한다.
- **태그를 통해 단독 재실행 가능(예시): `ansible-playbook ubuntu_ansible.yml --tags all/etc_hosts`**

---
</br>

## 📜 K8s 플레이북 (k8s_ansible.yml)
> **K8s 클러스터(kubeadm + containerd + Calico) 구성 플레이북입니다.**
- **Play 1** → 필수 Ansible 컬렉션 사전 검증 (Control Node)
- **Play 2** → kubernetes 그룹 공통 사전 준비 (k8s_prereq → containerd → k8s_packages)
- **Play 3~4** → 컨트롤플레인 초기화(kubernetes_master) → 워커 조인(kubernetes_workers)
- **해체용 `k8s_reset`** 플레이는 평소 **주석 상태** → 해체할 때만 위 K8s 롤을 주석 처리하고 이 플레이를 활성화
- ⚠ **kubeadm init/join 은 1회성이다** → `pod_subnet` 등을 바꿔도 재실행으로 반영되지 않는다(k8s_reset 으로 해체 후 재구축)

---
</br>

## 📜 Longhorn 플레이북 (longhorn_ansible.yml)
> **Longhorn(분산 블록 스토리지) 설치 전 노드 사전 준비 플레이북입니다.**
- **Play 1** → longhorn 그룹 전 노드에 open-iscsi 설치 + multipathd 차단 + 데이터 경로 생성
- 버전과 데이터 경로는 인벤토리 `longhorn` 그룹에서 관리 (`open_iscsi_version`, `longhorn_data_path`)

---
</br>

## 📜 Terraform 플레이북 (terraform_ansible.yml)
> **Terraform 설치 플레이북입니다.**
- **Play 1** → terraform 그룹에 HashiCorp 저장소 등록 + Terraform 설치/버전 고정
- 대상 호스트와 버전은 인벤토리 `terraform` 그룹에서 관리

---
</br>

## 📜 Helm 플레이북 (helm_ansible.yml)
> **Helm 설치 플레이북입니다.**
- **Play 1** → helm 그룹에 공식 CDN(get.helm.sh) 바이너리 설치 + sha256 검증 + 버전 고정 링크
- 버전·체크섬·설치 경로는 인벤토리 `helm` 그룹에서 관리 (`helm_version`, `helm_sha256`, `helm_install_root`)
- apt 저장소(baltocdn) 대신 바이너리 설치 — 랩 네트워크에서 SSL 인증서 검증이 실패한다(롤 주석 참조)

---
</br>

## 📜 Docker 플레이북 (docker_ansible.yml)
> **Docker(docker.io + compose 플러그인) 설치 플레이북입니다.**
- **Play 1** → docker 그룹에 docker.io/compose 설치 + 버전 고정 + 서비스 기동 + docker 그룹 추가
- 버전과 대상 계정은 인벤토리 `docker` 그룹에서 관리 (`docker_version`, `docker_compose_version`, `docker_users`)

---
</br>

## 📜 Kafka 플레이북 (kafka_ansible.yml)
> **Kafka(KRaft 3노드 로컬 클러스터) 설치 플레이북입니다.**
- **Play 1** → kafka 그룹 전 노드에 tarball 설치 + KRaft 구성 + systemd 기동 + JMX exporter
- **Play 2** → 한 노드(`ap`)에서 파이프라인 토픽 생성(`--if-not-exists`)
- 버전/포트/토픽 목록은 인벤토리 `kafka` 그룹에서 관리 (`kafka_version`, `kafka_cluster_id`, `kafka_topic_list` 등)
- **⚠️ Kafka 4.0+ 브로커는 Java 17 필수 → java 롤(`java_version: "17"`) 선행 적용 필요**

---
</br>


## 📜 코드 저장소 플레이북 (local_git_ansible.yml)
> **Airflow 코드(`data_layer_airflow`)를 담는 **클라이언트 쪽 git 저장소**를 한 번 만들어 주는 플레이북입니다.**
- **Play 1** → `local_git` 그룹(s2)에 `git init` → `.gitignore` → origin → 최초 커밋 → 최초 push
- ⚠️ **실행 시점이 다른 플레이북과 다르다** → 노드 준비 단계가 아니라 Terraform **`303-git` apply 뒤, `304-airflow` apply 앞**이다. push 대상이 클러스터 안 파드라서, 저장소가 비어 있으면 airflow 파드의 git-sync 가 init 에서 멈춘다.
- ⚠️ **부트스트랩 전용이다** → 커밋이 하나라도 있으면 최초 커밋/push 를 건너뛴다. 매 실행마다 작업 중이던 변경분을 임의 메시지로 커밋해 이력을 오염시키지 않기 위함이다.
- ⚠️ **`airflow.env`·`scripts/airflow.conf` 는 `.gitignore` 고정 대상** → 저장소는 클러스터 안에서 인증 없이 clone 되므로(`git daemon --export-all`) 비밀번호·fernet 키가 그대로 노출된다. 런타임 값은 Secret `airflow-env` 에서 온다.
- ⚠️ 선행 조건: `303-git` 파드 Running + `etc_hosts` 롤 적용(`data-layer-git` 이름 해석). 둘 중 하나라도 없으면 첫 태스크에서 원인을 알려주며 멈춘다.
- 이후 수정은 사람이 한다: `git add -A && git commit && git push` → 약 10초 뒤 파드에 반영

---
</br>

## 📋 Ansible Role `tasks/main.yml` 작성 규칙

---

### 1. 작업 순서
> **모든 `Role`은 아래 순서를 기본으로 작성한다.**

1. 작업 목적 주석 작성
2. **Ansible Module을 사용하여 작업 수행 (멱등성 유지)**
3. 필요한 경우 `command` 또는 `shell`로 동작 확인
4. **`assert`를 이용하여 결과 검증**
5. 실패 시 즉시 Playbook 종료

---

### 2. 주석 작성
> 섹션을 구분하는 주석을 사용한다.

```yaml
# =====================================================
# Control Node 기본 설정
# =====================================================

# -----------------------------------------------------
# 1. sshpass 설치
# sshpass → SSH 비밀번호 인증 자동화를 위한 도구
# -----------------------------------------------------
```

---

### 3. Module 우선 사용

> **가능한 모든 작업은 `Ansible Module`을 사용한다.**

✔ 권장

```yaml
apt:
  name: sshpass
  state: present
```

❌ 비권장

```yaml
shell: apt install -y sshpass
```

**`Module`은 멱등성(`Idempotency`)을 제공하므로 동일한 `Playbook`을 여러 번 실행해도 불필요한 변경이 발생하지 않는다.**

---

### 4. 검증은 assert 사용

> **모든 작업은 최종적으로 `assert`로 성공 여부를 확인한다.**

```yaml
assert:
  that:
    - sshpass_check.rc == 0
```

- 성공 → 다음 Task 실행
- 실패 → Playbook 즉시 종료(Fail Fast)

`success_msg`와 `fail_msg`를 함께 작성한다.

```yaml
success_msg: "[SUCCESS] sshpass installed"
fail_msg: "[FAIL] sshpass install failed"
```

---
</br>

## 📚 Roles 설명
---
### 🔹 control → [`📂 control.md`](./roles/control/tasks/control.md)
- Control Node에서 password 기반 SSH 통신을 위해 sshpass 설치 및 검증 수행
---

### 🔹 root_password → [`📂 root_password.md`](./roles/root_password/tasks/root_password.md)
- root 계정 비밀번호 설정
---

### 🔹 packages → [`📂 packages.md`](./roles/packages/tasks/packages.md)
- 기본 패키지 일괄 설치 (인벤토리 `install_packages` 기준)
---

### 🔹 pip_packages → [`📂 pip_packages.md`](./roles/pip_packages/tasks/pip_packages.md)
- Python 패키지 설치 (인벤토리 `pip_packages` 기준)
---

### 🔹 nicname → [`📂 nicname.md`](./roles/nicname/tasks/nicname.md)
- 네트워크 인터페이스 이름을 `eth*` 로 고정 (GRUB `net.ifnames=0 biosdevname=0`, 재부팅 후 적용)
---

### 🔹 cloud_init → [`📂 cloud_init.md`](./roles/cloud_init/tasks/cloud_init.md)
- cloud-init 설정 (초기화 간섭 방지)
---

### 🔹 ufw → [`📂 ufw.md`](./roles/ufw/tasks/ufw.md)
- UFW 방화벽 비활성화 (서비스 중지 + 부팅 자동시작 해제)
---

### 🔹 locale_ko → [`📂 locale_ko.md`](./roles/locale_ko/tasks/locale_ko.md)
- 한국어 로케일 설정
---

### 🔹 ssh_root_login → [`📂 ssh_root_login.md`](./roles/ssh_root_login/tasks/ssh_root_login.md)
- root SSH 로그인 허용 (`PermitRootLogin yes`)
---

### 🔹 timezone → [`📂 timezone.md`](./roles/timezone/tasks/timezone.md)
- 타임존 설정 (Asia/Seoul)
---

### 🔹 ntp → [`📂 ntp.md`](./roles/ntp/tasks/ntp.md)
- NTP 시간 동기화 설정 (`0.kr.pool.ntp.org`)
---

### 🔹 open_files → [`📂 open_files.md`](./roles/open_files/tasks/open_files.md)
- open files(ulimit) 제한 설정
---

### 🔹 logrotate → [`📂 logrotate.md`](./roles/logrotate/tasks/logrotate.md)
- 로그 로테이션 설정
---

### 🔹 shell_default → [`📂 shell_default.md`](./roles/shell_default/tasks/shell_default.md)
- 기본 쉘 설정 (`/bin/sh` → bash)
---

### 🔹 java → [`📂 java.md`](./roles/java/tasks/java.md)
- OpenJDK 설치 (인벤토리 `java_version` 기준)
---

### 🔹 disable_swap → [`📂 disable_swap.md`](./roles/disable_swap/tasks/disable_swap.md)
- 스왑 비활성화 — ⚠ **평소 플레이북에서 주석 상태**. K8s 를 스왑 켠 채(LimitedSwap) 운영하므로 활성화하면 K8s 검증이 실패한다
---

### 🔹 enable_swap → [`📂 enable_swap.md`](./roles/enable_swap/tasks/enable_swap.md)
- 스왑 파일 생성 및 활성화 (인벤토리 `swap_file_path`, `swap_size_mb` 기준)
---

### 🔹 package_version_lock → [`📂 package_version_lock.md`](./roles/package_version_lock/tasks/package_version_lock.md)
- 커널·Java 패키지 버전 고정 (hold) — `java_version` 기준이라 java 롤 뒤에 와야 한다
---

### 🔹 package_update_lock → [`📂 package_update_lock.md`](./roles/package_update_lock/tasks/package_update_lock.md)
- 자동 업데이트 잠금
---

### 🔹 bash_common → [`📂 bash_common.md`](./roles/bash_common/tasks/bash_common.md)
- bash 공통 환경 설정 (환경변수 파일 + 탭 완성 + alias + 프롬프트)
---

### 🔹 ssh_keygen → [`📂 ssh_keygen.md`](./roles/ssh_keygen/tasks/ssh_keygen.md)
- Ed25519 키 생성 + 전 노드 공개키 상호 배포 (노드 간 비밀번호 없는 SSH)
---

### 🔹 etc_hosts → [`📂 etc_hosts.md`](./roles/etc_hosts/tasks/etc_hosts.md)
- /etc/hosts 호스트 등록
---

### 🔹 collection_check → [`📂 collection_check.md`](./roles/collection_check/tasks/collection_check.md)
- k8s 롤에 필요한 Ansible 컬렉션 사전 검증 (인벤토리 `required_collections` 기준) — **검증만 하고 설치하지 않는다**(없으면 `ansible-galaxy collection install`)
---

### 🔹 k8s_prereq → [`📂 k8s_prereq.md`](./roles/k8s_prereq/tasks/k8s_prereq.md)
- K8s 사전 준비 — 커널 모듈(overlay/br_netfilter) + sysctl + cgroup v2 검증
---

### 🔹 containerd → [`📂 containerd.md`](./roles/containerd/tasks/containerd.md)
- 컨테이너 런타임 containerd + runc 설치·버전 고정 + SystemdCgroup 활성화 + HTTP 사설 레지스트리 허용(certs.d) + 파드 샌드박스(pause) 이미지 사전 확보 (인벤토리 `containerd_version`, `runc_version`, `containerd_insecure_registries`, `sandbox_image` 기준)

---

### 🔹 k8s_packages → [`📂 k8s_packages.md`](./roles/k8s_packages/tasks/k8s_packages.md)
- kubeadm/kubelet/kubectl 설치·버전 고정 + node-ip 고정 (인벤토리 `kubernetes_package_version` 기준)
---

### 🔹 k8s_master → [`📂 k8s_master.md`](./roles/k8s_master/tasks/k8s_master.md)
- 컨트롤플레인 초기화(kubeadm init) + Calico 설치 → 스왑 유지(LimitedSwap) 구성
---

### 🔹 k8s_worker → [`📂 k8s_worker.md`](./roles/k8s_worker/tasks/k8s_worker.md)
- 워커 노드 kubeadm join + 전체 클러스터 검증 (노드 수/Ready/INTERNAL-IP/스왑 유지)
---

### 🔹 k8s_reset → [`📂 k8s_reset.md`](./roles/k8s_reset/tasks/k8s_reset.md)
- 클러스터 해체(kubeadm reset) + 잔여물 정리 → 평소 주석 상태, 해체 시에만 활성화
---

### 🔹 longhorn_prereq → [`📂 longhorn_prereq.md`](./roles/longhorn_prereq/tasks/longhorn_prereq.md)
- Longhorn 노드 사전 준비 → open-iscsi 설치·버전 고정 + multipathd 차단 + 데이터 경로 생성 (인벤토리 `open_iscsi_version`, `longhorn_data_path` 기준)
---

### 🔹 terraform → [`📂 terraform.md`](./roles/terraform/tasks/terraform.md)
- HashiCorp 저장소 등록 + Terraform 설치·버전 고정 (인벤토리 `terraform_version` 기준)
---

### 🔹 helm → [`📂 helm.md`](./roles/helm/tasks/helm.md)
- Helm CLI 설치 → 공식 CDN tarball + sha256 검증 + 버전 고정 링크(`/usr/local/bin/helm`) (인벤토리 `helm_version`, `helm_sha256` 기준)
---

### 🔹 docker → [`📂 docker.md`](./roles/docker/tasks/docker.md)
- Docker(docker.io) + compose 플러그인 설치·버전 고정 + docker 그룹 추가 → docker-ce 대신 docker.io로 K8s containerd와 공존 (인벤토리 `docker_version`, `docker_compose_version`, `docker_users` 기준)
---

### 🔹 kafka → [`📂 kafka.md`](./roles/kafka/tasks/kafka.md)
- Kafka tarball 설치 + KRaft 3노드 클러스터 구성 + systemd 기동 + JMX Prometheus exporter + Java 17 필수 (인벤토리 `kafka_version`, `kafka_cluster_id`, `kafka_data_dir` 등 기준)
---

### 🔹 kafka_topics → [`📂 kafka_topics.md`](./roles/kafka_topics/tasks/kafka_topics.md)
- 파이프라인 계약 토픽 16종 생성(`--if-not-exists`) + 존재 검증 → 한 노드에서만 실행, 파티션 수는 운영 중 변경 금지 (인벤토리 `kafka_topic_list`, `kafka_topic_partitions` 기준)
---


### 🔹 local_git → [`📂 local_git.md`](./roles/local_git/tasks/local_git.md)
- Airflow 코드 저장소 부트스트랩  `git init -b master` + `.gitignore`(비밀값 제외) + origin 설정 + 최초 커밋/push. 서버 쪽 bare 저장소는 Terraform `303-git` 이 만들고 이 롤은 클라이언트만 준비한다. 커밋이 있으면 아무것도 하지 않는다 (인벤토리 `local_git_repo_dir`, `local_git_remote_url`, `local_git_branch`, `local_git_ignore` 등 기준)
---
