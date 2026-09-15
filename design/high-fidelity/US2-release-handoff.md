# Shield 해제 메인 앱 handoff 하이파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `002 / US2` |
| 관련 task | `T104` |
| 작성일 | `2026-09-15` |
| 문서 상태 | 구현 승인 대기 — `T105` |
| 기반 로우파이 | [US2-release-handoff.md](../low-fidelity/US2-release-handoff.md) |
| Figma 파일 | [GetUp 디자인](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=288-2014) |
| 최상위 node | `288:2014` — `US2 / Release Handoff · T104 하이파이 · 검토 대기` |

T104는 하이파이와 구현 인계만 완료한다. 사용자가 T105에서 명시적으로 승인하기 전에는
`T106~T113`의 제품 코드와 UI를 구현하지 않는다.

## 산출물 구성

| 영역 | Figma node | 내용 |
|---|---|---|
| 재사용 컴포넌트 | `288:2016` | 상태 카드와 주 행동 component set |
| Dark | `288:2017` | 신규 네 상태의 393×852 화면 |
| Light | `288:2018` | 동일 정보 구조의 Light 화면 |
| Dynamic Type AX5 | `288:2019` | 393×1180 세로 확장 검증 화면 |
| 접근성·구현 인계 | `288:2020` | VoiceOver, retryAfter, 복구 연결, SwiftUI 규칙 |

### 화면 node

| 상태 | Dark | Light | AX5 |
|---|---|---|---|
| `processing` | `294:2039` | `296:2039` | `297:2064` |
| `completed` | `294:2061` | `296:2064` | `297:2086` |
| `retryable` | `294:2082` | `296:2082` | `297:2100` |
| `insufficient` | `294:2104` | `296:2101` | `297:2115` |

## 재사용 컴포넌트

### `GetUp / Release Status Card`

- component set: `289:2028`
- variant: `Theme=Dark|Light`, `Tone=Neutral|Accent|Error`, `Size=Standard|AX5`
- text property: `Eyebrow`, `Title`, `Detail`
- 총 12개 variant이며 화면별 대상·구간·차감 또는 보존 결과를 같은 구조로 전달한다.
- Dark variant는 기존 `GetUp Focus / Semantic`, `GetUp Focus / Layout` variable에 바인딩한다.
  Light variant는 전역 Dark semantic mode를 변경하지 않는 검토용 Apple semantic light 값이다.

### `GetUp / Primary Action`

- component set: `295:2068`
- variant: `Theme=Dark|Light`, `State=Default|Disabled`, `Size=Standard|AX5`
- text property: `Label`
- 총 8개 variant이며 GetUp accent와 `onAccent`, `disabled` token을 사용한다.
- 표준 높이는 52pt, AX5 높이는 64pt다. 보조 행동도 44pt 투명 터치 프레임을 사용한다.
- `retryAfter` 전 상태는 `State=Disabled`와 `30초 뒤 다시 시도` 예시로 인계한다.

Code Connect는 T111 구현 전이므로 T104에서 연결하지 않는다. SwiftUI 컴포넌트가 생긴 뒤 실제 타입과
property가 확정된 상태에서 별도 매핑한다.

## 시각 규칙

- 배경: `background` (`#08090B`), Light 검증 배경은 Apple semantic system background 계열
- 카드: `surface`·`surfaceElevated`, 성공은 `accent` outline, 재시도는 `error` outline
- 강조: `accent` (`#F4D600`), 주 행동 text는 `onAccent`
- 본문: `textPrimary`, `textSecondary`, 오류 결과는 `error`
- 간격: `xs 8`, `sm 12`, `md 16`, `lg 20`, `xl 24`, `xxl 32`
- 모서리: 카드 `radius.md 18`, 주 행동 `radius.full`
- 서체: SF Pro의 기존 Eyebrow·Title·Subtitle·Body·Label·Button 체계를 재사용한다.
- 정보 순서는 상태 → 설명 → 대상·구간 → 결과 → 남은 제한 → 행동으로 모든 테마에서 동일하다.

## 상태·문구·행동 계약

### `processing`

- 제목: `해제 상태를 확인하고 있어요`
- 장부와 제한 read-back이 확인되기 전에는 성공·차감 결과를 추측하지 않는다.
- 진행 표시는 Apple iOS progress indicator를 사용하고, VoiceOver에서는 반복 읽지 않는다.
- 닫기·뒤로가기·재시도·추가 해제 요청을 제공하지 않는다.
- 앱 종료 뒤 같은 command를 이어서 확인한다는 설명을 항상 표시한다.

### `completed`

- 제목: `해제가 완료됐어요`
- 실제 funding source와 다른 활성 규칙의 남은 제한을 확정 결과로 표시한다.
- 단일 주 행동 `확인` 뒤 terminal handoff를 확인 처리하고 삭제한다.

### `retryable`

- 제목: `해제를 완료하지 못했어요`
- `코인은 차감되지 않았어요`와 제한 유지 결과를 먼저 전달한다.
- 준비되면 같은 command ID로 `다시 시도`한다. `retryAfter` 전에는 남은 시간을 표시한 비활성
  action을 사용한다. `닫기`는 재시도를 끝내는 명시적 terminal action이다.

### `insufficient`

- 제목: `사용할 수 있는 해제권이 없어요`
- 최신 장부의 `무료 0회 · 구매 0개`와 제한 유지를 함께 표시한다.
- `코인 구매`는 terminal handoff를 확인한 뒤 기존 `CoinStoreView`로 이동한다. 구매 완료 뒤 이전
  command를 자동 재실행하지 않는다.

### `recoveryRequired`

신규 결과 화면을 만들지 않는다. `PendingAppRouteDestination.iCloudRecovery`로 연결해 기존 iCloud
복구 경험을 재사용하고 구매 CTA를 표시하지 않는다.

## 접근성·motion 인계

- VoiceOver 읽기 순서: 상태 제목 → 상태 설명 → 대상 규칙·구간 → 차감/미차감 결과 → 남은 제한 →
  주 행동 → 보조 행동
- terminal 전환 시 접근성 focus를 새 상태 제목으로 이동한다.
- `processing`은 한 번만 live announcement하고 spinner 자체는 접근성에서 숨긴다.
- `retryAfter` 종료 시 `다시 시도할 수 있어요`를 한 번 알리되 자동 실행하지 않는다.
- 색상 외에 상태 아이콘·제목·결과 문구를 함께 사용한다.
- 최대 Dynamic Type은 `ScrollView` 본문과 `safeAreaInset(edge: .bottom)` action을 사용해 겹침을
  방지한다. 하이파이 AX5 화면은 이 구조를 나타내기 위해 393×1180으로 확장했다.
- Reduce Motion에서는 spinner를 정적 진행 아이콘으로 대체할 수 있고 상태 전환은 cross-fade 또는
  즉시 교체한다.

## 검증 결과

- Dark 4개, Light 4개, AX5 4개 — 총 12개 화면 렌더 확인
- 누락 폰트 0개
- 화면 경계를 벗어난 텍스트 0개
- 44pt 미만 주·보조 행동 0개
- `Release Status Card` 12개 variant와 `Primary Action` 8개 variant의 property 연결 확인
- Dark 화면의 자체 색상은 기존 semantic variable에 바인딩했으며 유일한 비바인딩 항목은 Apple
  라이브러리의 내부 progress indicator다.

## T105 검토 항목

1. 완료 뒤 다른 규칙 제한이 남을 때 `확인`으로 현재 제한 화면 또는 홈으로 돌아가는 흐름
2. 재시도 화면의 `닫기`가 요청 종료와 제한 유지 의미를 충분히 전달하는지
3. 부족 화면에서 구매 뒤 자동 재시도하지 않고 새 해제를 요청하게 하는 흐름
4. 처리 중 화면에 앱 종료 뒤 복원 설명을 항상 노출하는 방식

**구현 승인 상태**: 대기. 사용자의 명시적 승인과 의견을 T105에서 기록한다.
