# 조건 종료 시 자동 해제 로우파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US3` |
| 관련 task | `T056`, `T057` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-24` |
| 문서 상태 | `검토 대기` |
| 관련 명세 | [User Story 3 — 조건 종료 시 자동 해제](../../specs/001-location-app-restriction/spec.md#user-story-3---조건-종료-시-자동-해제-priority-p2) |
| 관련 contract | [restriction-evaluation-contract.md](../../specs/001-location-app-restriction/contracts/restriction-evaluation-contract.md), [platform-events-contract.md](../../specs/001-location-app-restriction/contracts/platform-events-contract.md) |
| Figma node | [US3 / 자동 해제 + 활성 중 편집 차단](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=126-1976) |
| 후속 하이파이 | 로우파이 승인 후 `T058`에서 작성 |

## 목표와 범위

### 해결할 사용자 문제

활성 제한 중에는 GetUp 내부에서 규칙을 우회할 수 없음을 분명히 알리고, 사용자가 실제 종료 조건을
이해한 상태로 기다릴 수 있게 한다. 시간 종료 또는 신뢰 가능한 위치 이탈이 확인되면 제한이
자동으로 해제되고 규칙 편집이 다시 가능해졌음을 같은 홈 흐름에서 확인할 수 있게 한다.

### 포함 범위

- 활성 규칙의 편집·끄기·삭제를 같은 guard로 거부하는 흐름
- 차단 Alert의 종료 조건 안내와 확인 행동
- 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 자동 해제 완료 상태
- 해제 뒤 선택 앱 사용 가능 상태와 규칙 수정 control 재활성화
- VoiceOver 읽기 순서, Dynamic Type, Reduce Motion 가설

### 제외 범위

- 시스템 설정의 Family Controls 권한 철회 또는 앱 삭제 자체를 차단하는 동작
- 위치 확인 불가와 권한 부족 안내. 해당 상태는 US4에서 설계한다.
- 해제 지연 측정 UI와 실제 30초 계측 구현
- 최종 색상·명암·전환 motion·Dynamic Type 규격과 SwiftUI 구현
- 실제 좌표·주소·앱 이름·bundle identifier·`FamilyActivitySelection` token

## 사용자 흐름

1. 시간과 위치 조건이 모두 충족된 규칙이 홈에서 활성 상태로 표시된다.
2. 사용자가 활성 규칙의 편집·끄기·삭제를 시도한다.
3. GetUp은 요청을 수행하지 않고, 현재 제한이 끝날 때까지 수정할 수 없다는 Alert를 표시한다.
4. Alert는 `집 1km 밖` 또는 `09:00 AM 이후`라는 실제 종료 조건을 안내한다.
5. 사용자가 `확인`을 누르면 활성 홈 상태를 그대로 유지한다.
6. 신뢰 가능한 위치 이탈 또는 시간 종료가 확인되면 제한 앱 합집합을 다시 계산해 더 이상 필요한
   shield를 제거한다.
7. 홈은 자동 해제 완료와 근거를 표시하고 `규칙 수정` control을 다시 활성화한다.

## 화면 목록

| 화면 ID | 화면 이름 | 목적 | 진입 조건 | 주요 행동 |
|---|---|---|---|---|
| `US3-LF-01` | 활성 중 편집 진입점 차단 | 활성 중 변경 불가와 종료 조건을 홈에서 미리 알림 | 현재 규칙의 `(ruleID, revision)`이 활성 집합과 일치 | 비활성 수정 control 확인; 편집·끄기·삭제 시도 |
| `US3-LF-02` | 활성 중 편집 차단 Alert | 요청 거부 이유와 다시 가능한 조건 안내 | 활성 규칙에 변경 요청 | `확인` |
| `US3-LF-03` | 자동 해제 완료 | 제한 해제와 규칙 수정 재활성화 확인 | 시간 종료 또는 신뢰 가능한 위치 이탈 확인 | 선택 앱 사용; `규칙 수정` |

## 화면 상태

| 화면 ID | 상태 | 발생 조건 | 표시 내용 | 가능한 행동 | 다음 결과 |
|---|---|---|---|---|---|
| `US3-LF-01` | `active / guarded` | 현재 규칙 revision이 활성 집합과 일치 | `RESTRICTION ACTIVE`, 장소·반경, 종료 시각, `조건 종료 후 수정 가능` | 다른 규칙 탐색, 종료 대기 | 변경 요청 시 `US3-LF-02` |
| `US3-LF-02` | `edit blocked` | 활성 규칙 편집·끄기·삭제 요청 | `제한 중에는 수정할 수 없어요`, 위치 또는 시간 종료 조건, `확인` | Alert 닫기 | `US3-LF-01` 유지 |
| `US3-LF-03` | `auto released` | 시간 종료 또는 신뢰 가능한 위치 이탈 확인 | `AUTO RELEASE COMPLETE`, 해제 근거, 앱 사용 가능, `규칙 수정` | 앱 사용, 규칙 편집 | 비활성 규칙 홈 또는 편집 화면 |

## 와이어프레임

- 전체 보드: [T056 로우파이](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=126-1976)
- 흐름: [활성 → 수정 시도 → 차단 안내 → 자동 해제](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=126-1980)
- `US3-LF-01`: [활성 중 편집 진입점 차단](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=127-1977)
- `US3-LF-02`: [활성 중 편집 차단 Alert](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=128-1976)
- `US3-LF-03`: [자동 해제 완료](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=128-2056)
- 상태·계약 설명: [로우파이 상태 설명](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=128-2098)
- 기준 frame: iPhone `393×852pt`

## 상호작용과 검증 규칙

- 활성 `(ruleID, revision)`과 현재 규칙 revision이 정확히 일치할 때 해당 규칙의 편집·끄기·삭제를
  모두 거부한다.
- 차단 Alert는 요청한 변경을 수행하지 않으며, `확인` 뒤 기존 활성 상태를 유지한다.
- Alert는 규칙의 저장 장소·반경과 종료 시각을 사용해 실제 종료 조건을 안내한다.
- 위치 `unavailable`만으로 활성 제한을 해제하지 않는다.
- 신뢰 가능한 위치 이탈 또는 시간 종료는 자동 해제 경로로 합류한다.
- 시간 종료는 위치 상태와 무관하게 적용되며, 현재 활성 규칙의 앱 token 합집합을 다시 계산한다.
- 다른 활성 규칙도 같은 앱을 제한 중이면 해당 앱의 shield는 유지한다.
- 자동 해제 뒤 `규칙 수정`을 다시 활성화하고 최신 규칙 상태로 편집을 시작한다.
- 시스템 권한 철회나 앱 삭제까지 막는다고 안내하지 않는다.

## 접근성 가설

- 활성 홈의 VoiceOver 순서는 상태 → 규칙 이름 → 시간 → 종료 조건 → 제한 앱 개수 → 변경 가능
  조건이다.
- 차단 Alert의 VoiceOver 순서는 제목 → 거부 이유와 종료 조건 → `확인`이다.
- 자동 해제 완료의 VoiceOver 순서는 상태 → 제목 → 해제 근거 → 앱 사용 가능 → `규칙 수정`이다.
- 활성·차단·해제 상태는 색상뿐 아니라 `RESTRICTION ACTIVE`, Alert 제목,
  `AUTO RELEASE COMPLETE` 문구로 구분한다.
- Dynamic Type 확대에서는 Alert 설명과 완료 근거가 자연스럽게 줄바꿈하며 중요 조건을 축약하지 않는다.
- Alert의 `확인`과 해제 뒤 `규칙 수정`은 최소 `44×44pt` touch target을 유지한다.
- Alert가 닫히면 focus는 변경을 시도한 control로, 자동 해제 완료 시에는 상태 제목으로 이동한다.
- Reduce Motion에서는 카드 전환 animation 없이 상태·해제 근거 문구만 갱신한다.

## 검토 체크리스트

- [x] 활성 중 편집·끄기·삭제를 같은 guard로 차단한다.
- [x] 차단 Alert가 실제 위치 또는 시간 종료 조건을 안내한다.
- [x] 시간 종료와 신뢰 가능한 위치 이탈이 같은 자동 해제 완료 상태로 합류한다.
- [x] 위치 `unavailable`을 해제 조건으로 표현하지 않는다.
- [x] 자동 해제 뒤 앱 사용 가능과 규칙 수정 재활성화를 표시한다.
- [x] 다른 활성 규칙의 앱 제한을 보존해야 하는 합집합 계약을 기록했다.
- [x] 시스템 권한 철회나 앱 삭제까지 차단한다고 약속하지 않는다.
- [x] VoiceOver, Dynamic Type, focus, touch target과 Reduce Motion 가설을 기록했다.
- [x] 실제 좌표·주소·앱 이름·bundle identifier·token을 포함하지 않았다.
- [x] Figma 링크가 전체 보드와 각 상태 node를 직접 가리킨다.

## 자동 감사 결과

2026-08-24 Figma wrapper와 세 화면을 렌더링해 검수했다. 전체 85개 text node는 `SF Pro Bold`,
`Semibold`, `Regular`, `Medium`만 사용하며 누락 font, 빈 text, 임시 placeholder와 화면 경계 overflow가
모두 0건이었다. `US3-LF-02`는 iOS 26 공식 `Alert` component를 사용하고, 입력 field와 불필요한
버튼을 숨겨 `확인` 행동 하나만 제공한다.

이 task는 디자인·문서 작업이므로 code test는 실행하지 않았다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-24` | 사용자 | `검토 대기` | T056 로우파이 초안 검토 요청 | `T057`에서 피드백과 승인 여부 반영 |

## 변경 기록

| 날짜 | 작성자 | 변경 내용 | 관련 검토 의견 |
|---|---|---|---|
| `2026-08-24` | `Codex` | 활성 홈, 편집 차단 Alert, 자동 해제 완료와 상태 설명 패널 초안 작성 | 최초 초안 |

## 로우파이 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `검토 대기` |
| 승인자 | `<미승인>` |
| 승인일 | `<미승인>` |
| 미해결 항목 | 차단 안내 문구, 완료 상태의 지속 시간, 위치 이탈·시간 종료 표현 검토 |

승인 상태가 `승인됨`이 되기 전에는 `T058` 하이파이 작업이나 US3 UI 구현을 시작하지 않는다.
