# 커밋 컨벤션 (Commit Convention)

일관된 커밋 메시지로 변경 이력을 한눈에 파악하기 위한 규칙입니다.

## 기본 형식

```
type(scope): subject

(선택) 본문 - 무엇을, 왜 변경했는지
```

- **type**: 변경의 종류 (아래 표 참고)
- **scope**: 변경 대상 (예: `containerd`, `inventory`, `playbook`) — 생략 가능
- **subject**: 변경 내용 한 줄 요약

## Type 종류

| Type | 설명 | 예시 |
|------|------|------|
| `feat` | 새로운 기능 추가 | `feat(docker): Docker 설치 롤 추가` |
| `fix` | 버그 수정 | `fix(k8s): kubelet 재시작 누락 수정` |
| `docs` | 문서 수정 (README 등) | `docs: README에 Longhorn 롤 반영` |
| `refactor` | 기능 변화 없는 코드 정리 | `refactor(roles): 중복 태스크 통합` |
| `style` | 포맷팅, 들여쓰기 등 (동작 무관) | `style: yaml 들여쓰기 정리` |
| `test` | 테스트 추가/수정 | `test: molecule 테스트 추가` |
| `chore` | 빌드, 설정 등 기타 잡무 | `chore(playbook): K8s 롤 임시 비활성화` |
| `ci` | CI/CD 파이프라인 수정 | `ci: gitlab-ci 린트 단계 추가` |

## 작성 규칙

1. **제목은 50자 이내**, 끝에 마침표(`.`) 붙이지 않기
2. **명령형/현재형**으로 작성 — "추가함", "추가했음" ❌ → "추가" ⭕
3. **한 커밋에는 한 가지 변경만** 담기 (여러 작업을 섞지 않기) → "반드시 지키기"
4. 본문이 필요하면 제목과 **한 줄 띄우고** 작성 — "왜" 변경했는지 위주로

## GitLab 이슈 연동

커밋 메시지에 이슈 번호를 넣으면 자동으로 연결됩니다.

```
fix(containerd): 레지스트리 인증 오류 수정 #12      ← 이슈 #12에 커밋 연결
feat(longhorn): 스토리지 클래스 추가

Closes #12                                          ← 머지 시 이슈 #12 자동 종료
```

## 좋은 예 / 나쁜 예

```
⭕ feat(inventory): containerd 사설 레지스트리 그룹 변수 추가
⭕ docs(containerd): certs.d 사설 레지스트리 문서 반영

❌ 수정                          ← 무엇을 수정했는지 알 수 없음
❌ feat: 레지스트리 추가하고 README 수정하고 버그 고침   ← 여러 변경이 섞임
```