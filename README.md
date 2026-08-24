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
├── ansible.cfg              # Ansible 공통 설정
├── host.yml                 # 관리 대상 서버 목록 및 그룹
├── group_vars/              # 그룹별 설정값
│   ├── Ubuntu_Servers.yml   # 공통 서버 설정
│   ├── kubernetes.yml       # Kubernetes / containerd / runc 버전
│   ├── longhorn.yml         # Longhorn 설정
│   ├── kafka.yml            # Kafka Local PV 경로
│   ├── terraform.yml        # Terraform 버전
│   ├── helm.yml             # Helm 버전
│   └── buildkitd.yml        # BuildKit 버전 및 설정
│
├── ubuntu_ansible.yml       # 기본 서버 구성
├── k8s_ansible.yml          # Kubernetes 클러스터 구성
├── longhorn_ansible.yml     # Longhorn 노드 사전 준비
├── kafka_prereq_ansible.yml # Kafka Local PV 사전 준비
├── terraform_ansible.yml    # Terraform 설치
├── helm_ansible.yml         # Helm 설치
├── buildkitd_ansible.yml    # BuildKit 설치
│
├── bin/                     # 플레이북 실행 스크립트
│   ├── ansible_setup.sh
│   ├── start_configuration.sh
│   ├── start_kubernetes.sh
│   ├── start_longhorn.sh
│   ├── start_kafka_prereq.sh
│   ├── start_terraform.sh
│   ├── start_helm.sh
│   └── start_buildkitd.sh
│
├── callback_plugins/
│   └── summary_table.py     # 실행 결과 요약 출력
│
├── CLAUDE.md                # 작업 규칙
├── COMMIT_CONVENTION.md     # Git 커밋 규칙
├── README.md                # 사용 가이드
│
└── roles/                   # 실제 서버 설정 작업
    ├── [OS 공통]            # 기본 OS 설정 및 공통 패키지
    ├── [Kubernetes]         # Kubernetes 클러스터 구성
    ├── [선행작업]           # Longhorn / Kafka 사전 준비
    └── [도구]               # Terraform / Helm / BuildKit 설치
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
> **`Ansible` 기본 출력은** 실행 성공/실패 정도만 보여주기 때문에 **운영자가 전체 결과를 빠르게 판단하기 어렵습니다.**

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

- **롤은 모든 변수가 `group_vars/`에 모여 있습니다.**
- **그룹 = 플레이북 단위** → 그룹에 서버를 추가/제거하는 것만으로 대상 확장
- `host.yml`에는 구조와 호스트 고유값(`ansible_host`)만 둡니다
- **`group_vars/`는 인벤토리와 같은 디렉토리에 있어 자동으로 로드됩니다**
  - **`[주의]` 파일명은 그룹명과 대소문자까지 같아야 합니다**(`Ubuntu_Servers.yml`)

| 그룹 | 대상 | 쓰는 플레이북 |
|------|------|----------------|
| `Ubuntu_Servers` | ap / s1 / s2 | ubuntu |
| `kubernetes` (`kubernetes_master`=ap / `kubernetes_workers`=s1, s2) | ap / s1 / s2 | k8s |
| `longhorn`  | ap / s1 / s2 | longhorn  |
| `terraform` / `helm` / `buildkitd` | s2 | terraform / helm / buildkitd |

---
</br>

## 🚀 Ansible 실행
> **`[중요]`** **Ansible 프로젝트 홈 디렉토리의 절대 경로 + tag** 를 인자로 전달하여 실행합니다.

> ⚠️ **반드시 Ansible 프로젝트의 절대 경로와 태그를 인자로 전달해서 실행하세요.**

> **`start_*.sh`가 `cd`를 대신 해줍니다.**

```bash
# 서버 프로비저닝 (ubuntu_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_configuration.sh /my_project/Infrastructure-as-Code-Ansible all

# Longhorn 노드 사전 준비 (longhorn_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_longhorn.sh /my_project/Infrastructure-as-Code-Ansible all

# Terraform 설치 (terraform_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_terraform.sh /my_project/Infrastructure-as-Code-Ansible all

# Helm 설치 (helm_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_helm.sh /my_project/Infrastructure-as-Code-Ansible all

# Kafka 노드 선행작업 (kafka_prereq_ansible.yml)
#   → 로컬 PV 디렉토리 2종(/data/kafka-controller, /data/kafka-broker)을 
#   → root:root 0770 으로 만들고 권한까지 검증한다.
/my_project/Infrastructure-as-Code-Ansible/bin/start_kafka_prereq.sh /my_project/Infrastructure-as-Code-Ansible all

# BuildKit 설치 (buildkitd_ansible.yml) → docker 없는 이미지 빌드/push 데몬
/my_project/Infrastructure-as-Code-Ansible/bin/start_buildkitd.sh /my_project/Infrastructure-as-Code-Ansible all

# K8s 클러스터 구성 (k8s_ansible.yml)
/my_project/Infrastructure-as-Code-Ansible/bin/start_kubernetes.sh /my_project/Infrastructure-as-Code-Ansible all
```

---
</br>

## 📜 플레이북 (`ubuntu_ansible.yml`)

> **Ubuntu 서버의 기본 환경을 구성하는 메인 Ansible 플레이북입니다.**

---

### 주요 역할

- **Play 1 → Control Node**
  - `localhost`에 `sshpass` 설치
  - 패스워드 기반 SSH(`ansible_ssh_pass`) 사용을 위한 사전 설정

- **Play 2 → Ubuntu Servers**
  - `ap / s1 / s2` 서버에 필요한 Role을 순서대로 적용
  - 실행할 Role은 `roles:`에서 선택
  - 계정, 패키지, Swap 등의 설정값은 `group_vars/Ubuntu_Servers.yml`에서 관리

---

### 실행 시 주의사항

- **Role 순서**
  - `java` → `package_version_lock` → `bash_common`
  - Java 설치 후 버전 고정 및 `JAVA_HOME` 설정이 이루어짐

- **Swap**
  - Swap은 **켜진 상태로 운영**
  - `disable_swap`은 주석 처리하고 `enable_swap`을 사용
  - Kubernetes의 LimitedSwap 구성을 위한 설정

- **`etc_hosts`**
  - `/etc/hosts`를 **전체 재생성**
  - `data_layer_dns_names`와 `data_layer_vip_dns_names`에 **같은 이름을 중복 등록하지 않음**

---

### 특정 Role만 다시 실행

```bash
ansible-playbook ubuntu_ansible.yml --tags etc_hosts
```

---
</br>


## 📜 Longhorn 플레이북 (`longhorn_ansible.yml`)

> **Longhorn을 설치하기 전에 각 Kubernetes 노드를 미리 준비하는 플레이북입니다.**

---

### 주요 역할

- `ap / s1 / s2` 노드에 **Longhorn 필수 환경 구성**
  - `open-iscsi` 설치 및 버전 고정
  - `iscsid` 실행
  - `multipathd` 비활성화
  - Longhorn 데이터 디렉토리 생성
- 마지막에 **필수 설정이 정상인지 검증**

---

### 주의사항

- 설정값은 `group_vars/longhorn.yml`에서 관리
  - `open_iscsi_version` → iSCSI 버전
  - `longhorn_data_path` → Longhorn 데이터 저장 경로
- `longhorn_data_path`는 **Longhorn의 `defaultDataPath`와 동일해야 함**
- 데이터 경로는 **디렉토리만 생성**하며, 전용 디스크 마운트는 별도로 구성
- 이 플레이북은 **노드 준비까지만 담당**하며, Longhorn 설치는 별도로 진행

---
</br>

## 📜 Terraform 플레이북 (`terraform_ansible.yml`)

> **Terraform을 설치하고 버전을 고정하는 플레이북입니다.**

---

### 주요 역할

- `s2` 배포용 머신에 **Terraform 설치**
- HashiCorp 저장소 등록
- 지정된 Terraform 버전 설치 및 **버전 고정(hold)**
- 설치 후 버전 정상 여부 검증

---

### 주의사항

- 대상 서버는 `host.yml`에서 관리
- Terraform 버전은 `group_vars/terraform.yml`의 `terraform_version`으로 관리
- `terraform_version`은 **APT 패키지 버전 형식**을 사용
  - 예: `1.15.8-1`
- Ubuntu 24.04라면 HashiCorp 저장소 suite는 **`noble`**
- 설치 가능한 버전 확인: `apt-cache madison terraform`

---
</br>

## 📜 Helm 플레이북 (`helm_ansible.yml`)

> **배포용 머신에 Helm CLI를 설치하는 플레이북입니다.**

---

### 주요 역할

- `s2` 배포용 머신에 **Helm 설치**
- 공식 `Helm CDN`에서 바이너리 다운로드
- `SHA256` 체크섬으로 파일 검증
- `/usr/local/bin/helm`에 설치 및 버전 고정

---

### 주의사항

- 버전 / 체크섬 / 설치 경로는 `group_vars/helm.yml`에서 관리
  - `helm_version`
  - `helm_sha256`
  - `helm_install_root`
- **Helm 버전을 변경하면 `helm_sha256`도 함께 변경**
- APT 저장소가 아닌 **공식 바이너리 방식으로 설치**
- Helm CLI만 설치하며 **kubeconfig는 자동으로 설정하지 않음**
- `s2`에서 Helm을 사용하려면 처음 한 번 **`ap`의 kubeconfig를 `s2`로 복사**해야 함

---
</br>

## 📜 Kafka 플레이북 (`kafka_prereq_ansible.yml`)

> **Kafka 브로커는 Kubernetes의 Strimzi가 관리하고, 이 플레이북은 Kafka가 사용할 노드의 저장공간만 미리 준비합니다.**

---

### 주요 역할

- `ap / s1 / s2`에 `Kafka`용 디렉토리 생성
  - `/data/kafka-controller` → KRaft 컨트롤러 데이터
  - `/data/kafka-broker` → Kafka 토픽 로그
- 디렉토리의 **소유자와 권한을 검증**
- 경로 / 소유 / 권한은 `group_vars/kafka.yml`에서 관리

---

### 주의사항

- 디렉토리 권한은 **`0770`이 중요**
  - Strimzi Kafka 컨테이너가 비루트 사용자로 실행되므로 그룹 쓰기 권한이 필요함
  - 권한이 없으면 Kafka가 디렉토리를 생성하지 못해 `CrashLoopBackOff`가 발생할 수 있음

- **설치 순서**
```text
kafka_prereq
    ↓
105-strimzi (Operator)
    ↓
301-kafka (Kafka)
```

- **[중요] 노드를 추가할 때도 반드시 이 플레이북을 먼저 실행**
  - **디렉토리 준비 없이 Kafka 노드만 추가하면 PV 마운트에 실패할 수 있음**
- Kafka 설정과 토픽은 `301-kafka`에서 관리
  - `kafka.nodes` → 브로커와 노드 배치
  - `KafkaTopic` → **Kafka 토픽**

---
</br>

## 📜 BuildKit 플레이북 (`buildkitd_ansible.yml`)

> **Docker 없이 컨테이너 이미지를 빌드하고 Harbor에 Push하기 위한 BuildKit 환경을 구성합니다.**

---

### 주요 역할

- `s2` 빌드 머신에 **BuildKit 설치**
- `runc` 설치 여부 확인 및 필요 시 설치
- BuildKit 데몬(`buildkitd`)을 **systemd 서비스로 등록·실행**
- `buildctl` 명령어 설치
- Harbor Push를 위한 인증 정보 설정
- 설치 및 서비스 상태 검증

---

### 주의사항

- 버전 / 설치 경로 / Harbor 인증 정보는 `group_vars/buildkitd.yml`에서 관리
- BuildKit은 버전별 디렉토리에 설치하고 **심볼릭 링크만 변경**
  - 버전 변경 및 롤백이 간단함
- `buildkit_registry_password`는 Harbor 관리자 비밀번호와 **동일해야 함**
- `buildkit_registry`에는 **`:80` 포트를 반드시 포함**
  - 예: `harbor.example.com:80`
  - 빠지면 Docker Hub로 잘못 Push될 수 있음
- Harbor는 **HTTP 환경**
  - 이 플레이북은 인증 정보만 설정
  - 수동 `buildctl` Push 시 `registry.insecure=true` 필요
- BuildKit 설치와 Harbor 설치는 별개지만, **이미지 Push는 Harbor 설치 후 가능**
- BuildKit 소켓이 root 전용이므로 `buildctl`은 **root 권한으로 실행**

---
</br>


## 📜 K8s 플레이북 (`k8s_ansible.yml`)

> **kubeadm + containerd + Cilium 기반의 Kubernetes 클러스터를 구성하는 플레이북입니다.**

---

### 주요 역할
- `Kubernetes` 노드 사전 준비
  - `k8s_prereq`
  - `containerd`
  - `k8s_packages`
- **Control Plane 초기화** (`k8s_master`)
  - `kubeadm init` 시 **kube-proxy를 설치하지 않음** (`skipPhases: addon/kube-proxy`)
  - 이 시점에는 CNI가 없어 노드가 `NotReady` 인 것이 정상
- **CNI 구성 — Cilium** (`k8s_cilium`)
  - eBPF 데이터플레인 + Native Routing(캡슐화 없음) + kube-proxy Replacement
  - Helm으로 설치하므로 `helm` 롤이 먼저 실행됨 (인벤토리 `helm` 그룹에 `ap` 포함)
  - 관측성으로 **Hubble + Hubble UI** 함께 설치 (`cilium_hubble_enabled`, `cilium_hubble_ui_enabled`)
  - 여기서 노드가 `Ready` 가 된다
- Worker Node를 → 클러스터에 **Join**
- 마지막에 클러스터 상태 검증

---

### 실행 전

- 반드시 **`ubuntu_ansible.yml`을 먼저 실행**
- 특히 Swap이 활성화되어 있어야 함
  - Kubernetes Role의 검증 과정에서 `/swap.img` 활성 여부를 확인함

---

### 주의사항

- `Kubernetes/containerd/runc/Cilium` 버전과 네트워크 설정은
  `group_vars/kubernetes.yml`에서 관리
- **kube-proxy 미설치는 `kubeadm init` 시점의 결정**이라 Cilium 설정만 바꿔서는 되돌릴 수 없음
  - `skipPhases`(kubeadm-config)와 `kubeProxyReplacement`(Cilium values)는 한 쌍으로 움직인다
- **`cilium_hubble_ui_enabled: true` 로 두려면 `cilium_hubble_enabled` 도 반드시 `true` 여야 함**
  - UI는 `hubble.relay` 를 통해 흐름을 받으므로, relay가 꺼진 상태로 UI만 켜면
    차트 검증에 걸려 `helm` 설치 자체가 실패한다
    (`Hubble UI requires .Values.hubble.relay.enabled=true`)
- `kubeadm init/join`은 **1회성 작업**
  - `pod_subnet` 등을 변경해도 재실행만으로 반영되지 않음
  - 클러스터를 다시 구성하려면 `k8s_reset`으로 기존 클러스터를 먼저 제거

- `collection_check`는 **설치가 아니라 존재 여부만 확인**
  - 없으면 직접 설치: `ansible-galaxy collection install ansible.posix community.general`
- `containerd`와 `runc`는 **호환되는 버전으로 함께 설치/고정**
  - 버전을 변경한 경우 노드 재부팅 필요
  - 운영 중인 클러스터에서는 `--limit`으로 **한 노드씩 순차 적용 권장**

---
</br>


## 📋 Ansible Role `tasks/main.yml` 작성 규칙

---

### 1. 작업 순서
> **모든 `Role`은 아래 순서를 기본으로 작성한다.**

1. 작업 목적 주석 작성
2. **Ansible Module을 사용하여 작업 수행 (멱등성 유지)**
   - 필요한 경우 `command` 또는 `shell`로 동작 확인
3. **`assert`를 이용하여 결과 검증**
4. 실패 시 즉시 `Playbook` 종료

---

### 2. 주석 작성
> **섹션을 구분하는 주석을 사용한다.**

```yaml
# =====================================================
# Control Node 기본 설정
# =====================================================

# -----------------------------------------------------
# 1. sshpass 설치
# sshpass → SSH 비밀번호 인증 자동화를 위한 도구
# -----------------------------------------------------
...
```

---

### 3. Module 우선 사용

> **가능한 모든 작업은 `Ansible Module`을 사용한다.**

#### ✔ 권장

```yaml
apt:
  name: sshpass
  state: present
```

#### ❌ 비권장

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

- 성공 → 다음 `Task` 실행
- 실패 → `Playbook` 즉시 종료(`Fail Fast`)

`success_msg`와 `fail_msg`를 함께 작성한다.

```yaml
success_msg: "[SUCCESS] sshpass installed"
fail_msg: "[FAIL] sshpass install failed"
```

---
</br>

## 📚 Roles 설명
> **롤 33종 → 플레이북 실행 순서대로 정리했습니다.**

- 변수로 동작이 갈리는 롤은 그 값이 `group_vars/<그룹>.yml` 에 있고
- 나머지는 값이 롤 안에 고정돼 있습니다. `disable_swap`·`k8s_reset` 둘은 평소 주석 상태(의도된 비활성)입니다.

---
</br>

## **▸ `ubuntu_ansible.yml` → Control Node + 운영 서버 Configuration (롤 20개)**
- Control Node 1 + Ubuntu_Servers 19 + 주석 처리된 `disable_swap`

---

### 🔹 control → [`📂 control.md`](./roles/control/tasks/control.md)
- Control Node에서 password 기반 SSH 통신을 위해 sshpass 설치 및 검증 수행
---

### 🔹 root_password → [`📂 root_password.md`](./roles/root_password/tasks/root_password.md)
- root 계정 비밀번호 설정 (`group_vars/Ubuntu_Servers.yml` 의 `root_password` 기준)
---

### 🔹 packages → [`📂 packages.md`](./roles/packages/tasks/packages.md)
- 기본 패키지 일괄 설치 (`group_vars/Ubuntu_Servers.yml` 의 `install_packages` 기준)
---

### 🔹 nicname → [`📂 nicname.md`](./roles/nicname/tasks/nicname.md)
- 네트워크 인터페이스 이름을 `eth*` 로 고정 (GRUB `net.ifnames=0 biosdevname=0`, 재부팅 후 적용)
---

### 🔹 cloud_init → [`📂 cloud_init.md`](./roles/cloud_init/tasks/cloud_init.md)
- cloud-init 비활성화 — 부팅 시 네트워크/hostname 을 되돌리는 간섭 차단
---

### 🔹 ufw → [`📂 ufw.md`](./roles/ufw/tasks/ufw.md)
- UFW 방화벽 비활성화 (서비스 중지 + 부팅 자동시작 해제)
---

### 🔹 locale_ko → [`📂 locale_ko.md`](./roles/locale_ko/tasks/locale_ko.md)
- 한국어 로케일 설정 (ko_KR.UTF-8 — 새 로그인 세션부터 적용)
---

### 🔹 ssh_root_login → [`📂 ssh_root_login.md`](./roles/ssh_root_login/tasks/ssh_root_login.md)
- root SSH 로그인 허용 (`PermitRootLogin yes`)
---

### 🔹 timezone → [`📂 timezone.md`](./roles/timezone/tasks/timezone.md)
- 타임존 설정 (Asia/Seoul)
---

### 🔹 ntp → [`📂 ntp.md`](./roles/ntp/tasks/ntp.md)
- NTP 시간 동기화 설정 (systemd-timesyncd, `0.kr.pool.ntp.org`)
---

### 🔹 open_files → [`📂 open_files.md`](./roles/open_files/tasks/open_files.md)
- open files(ulimit `nofile`) 제한 상향
---

### 🔹 logrotate → [`📂 logrotate.md`](./roles/logrotate/tasks/logrotate.md)
- 로그 로테이션 설정 (`group_vars/Ubuntu_Servers.yml` 의 `logrotate_options` 기준)
---

### 🔹 shell_default → [`📂 shell_default.md`](./roles/shell_default/tasks/shell_default.md)
- 기본 쉘 설정 (`/bin/sh` → bash, 심볼릭 링크 직접 교체)
---

### 🔹 java → [`📂 java.md`](./roles/java/tasks/java.md)
- OpenJDK 설치 (`group_vars/Ubuntu_Servers.yml` 의 `java_version` 기준)
---

### 🔹 disable_swap → [`📂 disable_swap.md`](./roles/disable_swap/tasks/disable_swap.md)
- 스왑 비활성화 → **평소 플레이북에서 주석 상태**. K8s 를 스왑 켠 채(LimitedSwap) 운영하므로 활성화하면 K8s 검증이 실패한다
---

### 🔹 enable_swap → [`📂 enable_swap.md`](./roles/enable_swap/tasks/enable_swap.md)
- 스왑 파일 생성 및 활성화 (`group_vars/Ubuntu_Servers.yml` 의 `swap_file_path`, `swap_size_mb` 기준 → 크기를 바꾸면 파일을 재생성한다)
---

### 🔹 package_version_lock → [`📂 package_version_lock.md`](./roles/package_version_lock/tasks/package_version_lock.md)
- 커널/Java 패키지 버전 고정(hold) → `java_version` 기준이라 java 롤 뒤에 와야 한다
---

### 🔹 package_update_lock → [`📂 package_update_lock.md`](./roles/package_update_lock/tasks/package_update_lock.md)
- 자동 업데이트 잠금 (unattended-upgrades + 주기적 목록 갱신 차단)
---

### 🔹 bash_common → [`📂 bash_common.md`](./roles/bash_common/tasks/bash_common.md)
- bash 공통 환경 설정 (환경변수 파일 + 탭 완성 + alias + 프롬프트)
---

### 🔹 ssh_keygen → [`📂 ssh_keygen.md`](./roles/ssh_keygen/tasks/ssh_keygen.md)
- Ed25519 키 생성 + 전 노드 공개키 상호 배포 (노드 간 비밀번호 없는 `SSH`)
---

### 🔹 etc_hosts → [`📂 etc_hosts.md`](./roles/etc_hosts/tasks/etc_hosts.md)
- `/etc/hosts` 를 인벤토리 호스트 목록 + `group_vars/Ubuntu_Servers.yml` 기준으로 **통째로 재생성** → 노드 IP 계열(`data_layer_dns_names`)과 인그레스 VIP 계열(`data_layer_vip_dns_names` → `ingress_vip`) 두 갈래로 등록

---
</br>

## **▸ `k8s_ansible.yml` → 클러스터 구성 (롤 6개 + 해체용 `k8s_reset`)**

---

### 🔹 collection_check → [`📂 collection_check.md`](./roles/collection_check/tasks/collection_check.md)
- k8s 롤에 필요한 Ansible 컬렉션 사전 검증 (`group_vars/kubernetes.yml` 의 `required_collections` 기준) → **검증만 하고 설치하지 않는다** (없으면 `ansible-galaxy collection install`)
---

### 🔹 k8s_prereq → [`📂 k8s_prereq.md`](./roles/k8s_prereq/tasks/k8s_prereq.md)
- K8s 사전 준비 → 커널 모듈(overlay/br_netfilter) + sysctl + cgroup v2 검증 (스왑은 끄지 않는다)
---

### 🔹 containerd → [`📂 containerd.md`](./roles/containerd/tasks/containerd.md)
- 컨테이너 런타임 containerd + runc 설치 (버전 고정) + SystemdCgroup 활성화 + HTTP 사설 레지스트리 허용(certs.d) + 파드 샌드박스(pause) 이미지 사전 확보 (`group_vars/kubernetes.yml` 의 `containerd_version`, `runc_version`, `containerd_insecure_registries`, `sandbox_image` 기준)
- **[주의]** `containerd / runc` 는 **짝 버전**으로 함께 설치 + hold 한다(짝이 깨지면 파드가 Terminating 에서 안 사라짐). 버전 변경 후에는 노드 재부팅 필요
---

### 🔹 k8s_packages → [`📂 k8s_packages.md`](./roles/k8s_packages/tasks/k8s_packages.md)
- pkgs.k8s.io 저장소 등록 + kubeadm/kubelet/kubectl 설치 (버전 고정) + node-ip 고정 (`group_vars/kubernetes.yml` 의 `kubernetes_version`, `kubernetes_package_version` 기준)
---

### 🔹 k8s_master → [`📂 k8s_master.md`](./roles/k8s_master/tasks/k8s_master.md)
- 컨트롤플레인 초기화(kubeadm init) → 스왑 유지(LimitedSwap) 구성 + kube-proxy 미설치(`skipPhases`). `admin.conf` 는 마스터의 `kubernetes_admin_user` 홈에만 배포된다. CNI가 없어 이 롤이 끝난 시점에는 노드가 `NotReady` 다
---

### 🔹 k8s_cilium → [`📂 k8s_cilium.md`](./roles/k8s_cilium/tasks/k8s_cilium.md)
- CNI 설치 — Cilium (eBPF + Native Routing + kube-proxy Replacement) + Hubble 관측성. Helm으로 배포하며 노드가 `Ready` 가 되는 것까지 검증한다 (`group_vars/kubernetes.yml` 의 `cilium_version`, `cilium_device`, `cilium_hubble_enabled`, `cilium_hubble_ui_enabled` 기준)
- Hubble UI 접속: `kubectl -n kube-system port-forward svc/hubble-ui 12000:80 --address 0.0.0.0` → `http://192.168.56.200:12000`
---

### 🔹 k8s_worker → [`📂 k8s_worker.md`](./roles/k8s_worker/tasks/k8s_worker.md)
- 워커 노드 kubeadm join + 전체 클러스터 검증 (노드 수/Ready/INTERNAL-IP/스왑 유지)
---

### 🔹 k8s_reset → [`📂 k8s_reset.md`](./roles/k8s_reset/tasks/k8s_reset.md)
- 클러스터 해체(kubeadm reset) + 잔여물 정리 → 평소 주석 상태, 해체 시에만 활성화 (패키지 / 스왑은 남긴다)

---
</br>

## **▸ 노드 선행작업 / 도구 설치 (플레이북 1개당 롤 1개)**
- `longhorn_ansible.yml`
- `terraform_ansible.yml`
- `helm_ansible.yml`
- `kafka_prereq_ansible.yml`
- `buildkitd_ansible.yml`

---

### 🔹 longhorn_prereq → [`📂 longhorn_prereq.md`](./roles/longhorn_prereq/tasks/longhorn_prereq.md)
- Longhorn 노드 사전 준비 → open-iscsi 설치/버전 고정 + multipathd 차단 + 데이터 경로 생성 (`group_vars/longhorn.yml` 의 `open_iscsi_version`, `longhorn_data_path` 기준)
---

### 🔹 terraform → [`📂 terraform.md`](./roles/terraform/tasks/terraform.md)
- HashiCorp 저장소 등록 + Terraform 설치/버전 고정 (`group_vars/terraform.yml` 의 `terraform_version` 기준)
---

### 🔹 helm → [`📂 helm.md`](./roles/helm/tasks/helm.md)
- Helm CLI 설치 → 공식 CDN tarball + sha256 검증 + 버전 고정 링크(`/usr/local/bin/helm`) (`group_vars/helm.yml` 의 `helm_version`, `helm_sha256` 기준)
---

### 🔹 kafka_prereq → [`📂 kafka_prereq.md`](./roles/kafka_prereq/tasks/kafka_prereq.md)
- Strimzi(Terraform `301-kafka`)가 정적 local PV 로 쓰는 노드 디렉토리 2종 생성 + 권한 검증 → `/data/kafka-controller` + `/data/kafka-broker` (`group_vars/kafka.yml` 기준, 멱등)
- **[주의]** 모드 `0770`(그룹 쓰기)이 없으면 Strimzi 파드가 CrashLoopBackOff. 브로커 설치 자체는 이 저장소 범위 밖이다
---

### 🔹 buildkitd → [`📂 buildkitd.md`](./roles/buildkitd/tasks/buildkitd.md)
- docker 없이 이미지를 빌드 + push 하는 BuildKit 데몬 설치 → buildkitd(systemd) + buildctl + Harbor push 인증 파일(`/root/.docker/config.json`) (`group_vars/buildkitd.yml` 기준)
- **[주의]** `buildkit_registry_password` 는 Terraform 200-harbor 의 `harbor_admin_password` 와 글자 그대로 같아야 하고, push 는 200-harbor apply 이후에 가능하다
---