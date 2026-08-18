# ⚙️ 시스템 Locale 한국어 설정 (Ansible)
- 시스템 기본 Locale을 ko_KR.UTF-8 로 설정한다.
- 한글 출력, 로그, 터미널 메시지 깨짐 현상을 방지한다.
- 서버 전역 Locale 설정으로 모든 사용자에게 동일하게 적용된다.
---
<br>

## 🧩 main.yml
```yaml
# =====================================================
# Korean Locale 설정
# =====================================================


# -----------------------------------------------------
# 1. 한국어 언어팩 설치 (apt 자체가 멱등)
# -----------------------------------------------------
- name: "Install Korean language package"
  apt:
    name: language-pack-ko
    state: present
    update_cache: yes
    cache_valid_time: 3600 # 캐시가 1시간 이내면 update 생략

# -----------------------------------------------------
# 2. ko_KR.UTF-8 로케일 생성 (locale_gen 모듈 자체가 멱등)
# -----------------------------------------------------
- name: "Create ko_KR.UTF-8 locale"
  locale_gen:
    name: ko_KR.UTF-8
    state: present

# -----------------------------------------------------
# 3. 시스템 기본 로케일을 한국어로 설정 (lineinfile 자체가 멱등)
# -----------------------------------------------------
- name: "Set default language to Korean"
  lineinfile:
    path: /etc/default/locale
    regexp: '^LANG='
    line: 'LANG=ko_KR.UTF-8'

# -----------------------------------------------------
# 4. Korean Locale 검증 (타겟 서버 파일 확인)
# -----------------------------------------------------
- name: "Check system default locale"
  command: "grep '^LANG=' /etc/default/locale"
  register: locale_check
  changed_when: false

- name: "Assert system default locale is Korean"
  assert:
    that:
      - "'LANG=ko_KR.UTF-8' in locale_check.stdout"
    success_msg: "Good!.. | System default locale is set to Korean (ko_KR.UTF-8)"
    fail_msg: "ERROR!.. | System locale is NOT Korean"
```
---
<br>

## 🛠 작업 내용
### 1️⃣ 한국어 언어 패키지 설치
- `language-pack-ko` 패키지 설치 (`apt` 자체 멱등, 캐시 1시간 유효)
---
### 2️⃣ ko_KR.UTF-8 Locale 생성 (멱등성 핵심)
- `locale_gen` 모듈 사용 — 이미 생성돼 있으면 재실행 시 **changed=0** 보장
- `command: locale-gen`은 매번 changed 유발이라 모듈로 대체
---
### 3️⃣ 시스템 기본 Locale 변경 (멱등성 핵심)
- `lineinfile`로 `/etc/default/locale`의 `LANG=` 라인 관리 — 자체 멱등
- `command: update-locale`은 매번 changed 유발이라 모듈로 대체
---
### 4️⃣ Locale 설정 검증
- 타겟 서버에서 `grep`으로 `/etc/default/locale` 실제 값 확인 후 `assert`
- ⚠️ `lookup('file', ...)`은 컨트롤 노드 파일을 읽으므로 검증에 사용 금지
- 새 기본 Locale은 **다음 로그인 세션부터** 적용됨
---
<br>

## ✅ 실행 결과 예시
```bash
TASK [Assert system default locale is Korean]
ok: [192.168.56.60] => {
    "msg": "Good!.. | System default locale is set to Korean (ko_KR.UTF-8)"
}
```
---
