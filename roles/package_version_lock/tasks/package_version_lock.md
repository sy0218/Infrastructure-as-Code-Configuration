# 📦 패키지 버전 고정 (Kernel & Java)

- 커널(Kernel) 및 Java 패키지의 버전을 고정하여  자동 업그레이드로 인한 장애를 방지한다.
- `dpkg_selections` 모듈로 hold 상태를 관리하여 패키지 업그레이드를 차단한다.
- Java 버전은 변수(`java_version`) 기반으로 동적 제어한다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# 패키지 버전 고정
# =====================================================


# -----------------------------------------------------
# 1. 커널 버전 수집
# -----------------------------------------------------
- name: "Get kernel version"
  command: uname -r
  register: kernel_version
  changed_when: false

# -----------------------------------------------------
# 2. 고정 대상 패키지 목록 구성 (hold/검증에서 공용)
# -----------------------------------------------------
- name: "Build hold package list"
  set_fact:
    hold_packages:
      - "linux-image-{{ kernel_version.stdout }}"
      - "openjdk-{{ java_version }}-jdk"
      - "openjdk-{{ java_version }}-jdk-headless"
      - "openjdk-{{ java_version }}-jre"
      - "openjdk-{{ java_version }}-jre-headless"

# -----------------------------------------------------
# 3. 커널 및 Java 패키지 hold (dpkg_selections 자체가 멱등 → command apt-mark hold는 매번 changed)
# -----------------------------------------------------
- name: "Hold kernel and Java packages"
  dpkg_selections:
    name: "{{ item }}"
    selection: hold
  loop: "{{ hold_packages }}"

# -----------------------------------------------------
# 4. 검증
# -----------------------------------------------------
- name: "Check held packages"
  command: apt-mark showhold
  register: held_packages
  changed_when: false

- name: "Assert kernel and Java packages are held"
  assert:
    that:
      - item in held_packages.stdout_lines # 라인 단위 정확 일치 (조건문 안에서는 {{ }} 금지)
    success_msg: "Good!.. | Package held: {{ item }}"
    fail_msg: "ERROR!.. | Package NOT held: {{ item }}"
  loop: "{{ hold_packages }}"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 커널 버전 자동 수집
- `uname -r` 명령어로 현재 실행 중인 커널 버전을 수집
---
### 2️⃣ 고정 대상 목록 구성
- `set_fact`로 hold 대상 패키지 리스트를 한 곳에서 정의 — hold와 검증이 같은 목록 공유
---
### 3️⃣ 커널 및 Java 패키지 버전 고정 (멱등성 핵심)
- `dpkg_selections: selection=hold` — 이미 hold 상태면 재실행 시 **changed=0** 보장
- `command: apt-mark hold`는 매번 changed 유발 + `args: warn`은 최신 ansible-core에서 제거되어 에러 발생 → 모듈로 대체
---
### 4️⃣ 설정 검증
- `apt-mark showhold` 결과의 **라인 단위 정확 일치**(`stdout_lines`)로 패키지별 `assert`
- 누락된 패키지를 항목별로 식별 가능
---
<br>

## 🧩 변수 설명
```yaml
# host.yml
java_version: "17"
```
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert kernel and Java packages are held]
ok: [192.168.56.60] => (item=openjdk-17-jdk) => {
    "msg": "Good!.. | Package held: openjdk-17-jdk"
}
```
---
