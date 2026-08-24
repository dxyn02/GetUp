# Agent Development Rules

## 1. Source of Truth

구현 시 다음 우선순위를 따른다.

1. specs/*/spec.md
2. specs/*/plan.md
3. specs/*/tasks.md
4. docs/DECISIONS.md
5. 기존 구현

문서와 코드가 충돌하면 임의로 판단하지 않는다.

---

## 2. Before Starting Work

작업 시작 전 반드시 다음 문서를 확인한다.

- 관련 spec.md
- 관련 plan.md
- 관련 tasks.md
- docs/STATUS.md
- docs/BLOCKERS.md
- docs/DECISIONS.md

현재 진행 상태와 미완료 작업을 파악한 후 작업을 시작한다.

---

## 3. Task Execution

tasks.md의 작업을 기준으로 구현한다.

작업이 완료되면:

- 해당 task를 [x]로 변경한다.
- 테스트를 실행한다.
- STATUS.md를 갱신한다.

한 번에 지나치게 많은 task를 구현하지 않는다.

가능하면 하나의 논리적 task 또는 작은 task group 단위로 진행한다.

---

## 4. Unknown / Ambiguous Decisions

다음 상황에서는 임의로 결정하지 않는다.

- spec에 정의되지 않은 핵심 비즈니스 규칙
- 데이터 손실 가능성이 있는 결정
- API contract 변경
- DB schema의 중대한 변경
- 인증 / 보안 방식 변경
- 외부 서비스 또는 유료 API 선택
- 기존 기능과 충돌하는 요구사항
- 여러 구현 방식 중 제품 동작이 달라지는 경우

이 경우:

1. 현재 task를 중단한다.
2. BLOCKERS.md에 기록한다.
3. STATUS.md의 Blocked 항목을 갱신한다.
4. 사용자에게 결정을 요청한다.

---

## 5. Decisions Agent May Make

다음은 합리적인 범위에서 에이전트가 판단할 수 있다.

- 변수명
- 함수명
- 내부 helper 구조
- 단순 refactoring
- formatting
- lint 수정
- 명백한 bug fix
- 테스트 코드 구조
- 제품 동작에 영향을 주지 않는 구현 세부사항

중요한 architectural decision은 DECISIONS.md에 기록한다.

---

## 6. Blocker Resolution

사용자가 blocker에 답변하면:

1. BLOCKERS.md의 상태를 RESOLVED로 변경한다.
2. 결정 사항을 DECISIONS.md에 기록한다.
3. STATUS.md를 갱신한다.
4. 중단했던 task부터 작업을 재개한다.

---

## 7. Testing

구현 완료를 판단하기 전에 관련 테스트를 실행한다.

테스트가 실패하면 task를 완료 처리하지 않는다.

다음 중 하나라도 존재하면 STATUS.md에 기록한다.

- failing tests
- skipped tests
- known issues
- unverified behavior

---

## 8. Status Updates

다음 상황에서 STATUS.md를 반드시 갱신한다.

- task 완료
- blocker 발생
- blocker 해결
- 테스트 실패
- 중요한 architecture 변경
- feature 완료
- 작업 세션 종료

---

## 9. Session Handoff

작업을 종료하기 전에 STATUS.md에 최소한 다음 내용을 남긴다.

- 현재 phase
- 마지막 완료 task
- 현재 작업 중인 task
- 다음 task
- blocker
- 테스트 상태

## 10. Documentation Language

모든 프로젝트 운영 문서는 한국어로 작성한다.

다음 파일은 반드시 한국어로 작성하고 업데이트한다.

- docs/STATUS.md
- docs/BLOCKERS.md
- docs/DECISIONS.md
- docs/HANDOFF.md

규칙:
- 제목과 섹션명도 한국어로 작성한다.
- 상태 설명, 차단 사유, 선택지, 권장안, 결정 사유도 한국어로 작성한다.
- 코드 식별자, 파일명, 클래스명, 함수명, API 경로 등은 원래 표기를 유지한다.
- 라이브러리명, 프레임워크명, 기술 용어는 필요하면 영어 원문을 유지할 수 있다.
- 기존 문서가 영어로 작성되어 있다면 다음 업데이트 시 한국어 형식으로 변환한다.

## 11. GitHub Flow 및 커밋 전략

- 모든 작업은 최신 `main`에서 분기한 기능 브랜치에서 진행한다. `main`에 직접 구현하거나
  커밋하지 않는다.
- 브랜치 이름은 기본적으로 `codex/` 접두사를 사용하고, 하나의 기능 또는 함께 검증할 수 있는
  작은 task group을 나타내도록 작성한다.
- 같은 사용자 스토리와 의존 관계를 공유해 함께 검토·검증할 수 있는 task는 같은 브랜치로 묶는다.
  서로 독립적인 기능이나 별도 배포·리뷰가 필요한 task는 별도 브랜치로 분리한다.
- 같은 브랜치에 여러 task를 포함하더라도 커밋은 task 또는 하나의 논리적 변경 단위별로 분리한다.
  각 커밋은 가능한 한 독립적으로 이해하고 검증할 수 있어야 한다.
- 커밋 전에 해당 변경과 관련된 테스트 및 문서 상태를 확인하고, 커밋 메시지에는 변경 목적이
  드러나도록 작성한다.
- 기능 브랜치가 검증되면 Pull Request로 `main`에 병합하며, 후속 작업은 병합된 최신 `main`에서
  새 브랜치를 만든다.
