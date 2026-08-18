# ☕ Java 설치 (변수 기반)

- host.yml 변수 기반으로 Java 버전을 선택하여 설치한다.
- 서버 환경에 따라 Java 8 / 11 / 17 / 21 등 유연하게 적용 가능하다.

---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Java 설치 (변수 기반)
# =====================================================


# -----------------------------------------------------
# 1. OpenJDK 설치 (apt 자체가 멱등)
# -----------------------------------------------------
- name: "Install OpenJDK (version {{ java_version }})"
  apt:
    name: "openjdk-{{ java_version }}-jdk"
    state: present
    update_cache: yes # apt update 먼저 실행
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략

# -----------------------------------------------------
# 2. Java 설치 검증 (타겟 서버에서 확인)
# -----------------------------------------------------
- name: "Check installed Java version"
  command: java -version # 버전 정보는 stderr로 출력됨
  register: java_check
  changed_when: false

- name: "Assert Java {{ java_version }} is installed"
  assert:
    that:
      - "'openjdk' in java_check.stderr"
      - java_version in java_check.stderr # 조건문 안에서는 {{ }} 없이 변수 직접 참조
    success_msg: "Good!.. | Java {{ java_version }} installed successfully"
    fail_msg: "ERROR!.. | Java {{ java_version }} is NOT installed"
```
---
<br>

## 📌 host.yml 예시
```yaml
# 설치할 자바 버전 (Kafka 4.0+ 브로커는 Java 17 필수)
java_version: "17"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ Java 버전 선택 설치 (멱등성 핵심)
- host.yml 의 `java_version` 변수로 `openjdk-{{ java_version }}-jdk` 패키지 설치
- `apt: state=present` 자체가 멱등 → 재실행 시 **changed=0** 보장 (캐시 1시간 유효)
---
### 2️⃣ Java 설치 검증
- 타겟 서버에서 `java -version` 실행 결과로 설치 여부 확인 후 `assert`
- 버전 정보는 **stderr**로 출력되므로 `java_check.stderr` 기준 검증
- ⚠️ `lookup('pipe', ...)`은 컨트롤 노드에서 실행되므로 검증에 사용 금지
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert Java 11 is installed]
ok: [192.168.56.60] => {
    "msg": "Good!.. | Java 11 installed successfully"
}
```
---
