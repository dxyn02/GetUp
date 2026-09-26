# Live Activity 시각 개편 하이파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `002 / US1` |
| 관련 task | `T115`, `T116` |
| 작성일 | `2026-09-26` |
| 문서 상태 | `사용자 구현 검토 대기` |
| 기반 로우파이 | [US1-live-activity-refresh.md](../low-fidelity/US1-live-activity-refresh.md) |
| Figma 파일 | [T115 Live Activity 하이파이](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04/GetUp-%E2%80%94-US1-%EB%A1%9C%EC%9A%B0%ED%8C%8C%EC%9D%B4?node-id=395-2090) |
| 최상위 node | `395:2090` — `US1 / Live Activity Refresh · T115 하이파이 · 검토 대기` |

T114에서 승인된 정보 구조를 반복 설계하지 않고, 구현에 필요한 최종 색상·서체·간격·아이콘,
appearance, 최대 Dynamic Type, VoiceOver, motion과 ActivityKit 영역 제약만 보강했다. T116의 명시적
구현 승인 전에는 `T117~T119`와 제품 Live Activity UI 변경을 시작하지 않는다.

## 산출물 구성

| 영역 | Figma node | 내용 |
|---|---|---|
| 잠금화면 최종 상태 | `395:2107` | `known`, `unavailable`, `stale`, 다중 규칙의 최종 시각·간격 |
| Dynamic Island 최종 상태 | `395:2153` | 상태별 expanded·compact·minimal 정보 예산과 축약 |
| 접근성·ActivityKit 인계 | `395:2237` | VoiceOver 순서, 상태 계약, payload·행동 제약, 승인 게이트 |
| 시각 시스템 | `395:2249` | 실제 앱 color·typography·spacing·motion token |
| appearance·접근성 | `395:2269` | Light/Dark 동일 dark surface, AX5 잠금화면, VoiceOver |
| 구현 승인 게이트 | `395:2287` | ActivityKit 영역별 정보 예산과 T116 차단 조건 |

## 최종 시각 규칙

### 색상

- 배경: `color/background` — `#08090B`
- Live Activity surface: `color/surface` — `#15171B`
- 보조 카드: `color/surfaceElevated` — `#202329`
- 강조: `color/accent` — `#F4D600`
- 핵심 텍스트: `color/textPrimary` — `#FFFFFF`
- 보조 텍스트: `color/textSecondary` — `#A6A8AD`
- 시스템 appearance가 Light여도 다른 GetUp 화면과 같은 검은 배경·surface를 유지한다. 별도 Light
  시각형을 만들지 않되 T119에서 두 appearance의 동일성을 검증한다.

### 서체

- 제품 font family는 `SF Pro`다. Figma에서 `Regular`, `Semibold`, `Bold`의 사용 가능 여부를 확인했다.
- 대표 규칙: 17pt Semibold
- 카운트다운: 17pt Bold 또는 영역에 맞는 system text style, tabular/monospaced digits
- 거리·보조 상태: 15~17pt Regular 또는 Semibold
- compact·minimal 카운트다운은 한국어 `분`, 영어 `min`을 사용해 거리의 `m`와 구분한다.
- 숫자 축소가 필요하면 핵심 정보의 순서를 유지하고 최소 배율을 제한한다. 규칙명은 공간이 부족할 때
  한 줄 말줄임하되 VoiceOver label에는 전체 이름을 제공한다.

### 간격·모서리

- 잠금화면 좌우 inset: 16pt
- 잠금화면 행 간격: 12pt
- compact 내부 간격: 8pt 이하
- 상태 surface radius: 18pt, 큰 잠금화면·AX5 예시 radius: 28pt
- 카운트다운의 trailing은 잠금화면 가용 폭의 16pt inset에 맞춘다.

### 아이콘

- 거리는 선이 복잡한 조준선 대신 SF Symbol `location.fill`을 사용한다.
- 규칙명 앞에는 의미가 불명확한 대체 아이콘을 넣지 않는다.
- `location.fill`, compact의 `?`, 다중 규칙의 `+`는 시각적 축약이며 VoiceOver의 독립 요소가 아니다.

## 상태별 정보 구조

| 상태 | 잠금화면·expanded | compact | minimal |
|---|---|---|---|
| `known` | 규칙명, 카운트다운, `집 밖까지 320 m` | `320 m` + `42분` | `42분` |
| `unavailable` | 규칙명, 카운트다운, `거리 확인 불가` | `?` + `42분` | `42분` |
| `stale` | 이전 숫자를 제거하고 unavailable과 같은 문구 | `?` + `42분` | `42분` |
| 다중 규칙 | 대표 규칙 정보 + `다른 제한 있음` | 거리·시간 + `+` | `42분` |

Live Activity 내부에는 반올림·stale 원인·좌표/주소 미표시 같은 구현 주석을 표시하지 않는다. 해당
계약은 보드 바깥 설명과 이 문서에만 유지한다.

## appearance·Dynamic Type

- Light·Dark appearance 모두 GetUp dark surface를 사용하며 정보·간격·아이콘·대비가 동일하다.
- 최대 Dynamic Type에서는 잠금화면의 대표 규칙 → 카운트다운 → 거리 → 다른 제한 순서를 세로로
  유지한다. Figma `AX5 Lock Screen Sample`은 초기 27/32/23pt가 최대 접근성 크기를 충분히 전달하지
  못한다는 사용자 피드백에 따라 규칙명 61pt, 카운트다운 75pt, 거리·추가 제한 53pt로 확대했다.
  카드 높이는 콘텐츠에 맞춰 371pt로 늘어나며 서로 겹치거나 다음 영역에 잘리지 않는다.
- compact·minimal은 시스템 영역이 좁으므로 임의로 모든 정보를 넣지 않는다. compact는 거리 상태와
  시간을, minimal은 시간 하나를 우선한다. 확대 환경에서도 동일한 정보 예산을 유지한다.

## VoiceOver 인계

- 잠금화면·expanded 읽기 순서: 대표 규칙 → 남은 시간 → 남은 거리 또는 확인 불가 → 다른 제한 있음
- 규칙명: `제한 규칙: {전체 규칙명}`
- 카운트다운: label `남은 시간`, value는 동적 timer의 전체 값
- known 거리: `남은 거리 {meters}미터`
- unavailable·stale: `남은 거리 확인 불가`
- compact `?`: `거리 확인 불가`, compact `+`: `다른 제한 있음`
- minimal은 남은 시간을 하나의 의미 단위로 읽는다.
- SF Symbol, padding, spacing, surface container는 별도 접근성 요소로 노출하지 않는다.
- 시각적 순서와 접근성 순서를 같게 유지하며 아이콘 이름·`heading`·`padding` 같은 구현 정보가
  발표에 섞이지 않게 한다.

## motion·Reduce Motion

- 초 단위 Activity update나 장식 animation을 추가하지 않는다. 카운트다운은 `endsAt` 기반 시스템
  timer가 표시를 갱신한다.
- 대표 규칙·거리 availability·다중 규칙 상태 변경은 ActivityKit의 시스템 전환을 사용하며 제품
  고유 이동·확대 motion을 추가하지 않는다.
- Reduce Motion에서도 동일한 정보와 읽기 순서를 유지한다. 별도 animation을 생략해도 상태 문구와
  색상·위치 변화만으로 결과를 이해할 수 있어야 한다.

## ActivityKit 구현 제약

- expanded: 규칙·시간·거리·추가 제한
- compact: 거리 상태·시간, 다중 규칙은 공간이 허용될 때 `+`
- minimal: 남은 시간
- content state와 attributes 합계는 4KB 미만을 유지한다.
- 버튼·토글·코인 잔액·구매 진입을 추가하지 않는다.
- 위치 좌표·정확도·주소·앱 token을 표시하거나 payload에 넣지 않는다.
- 5분을 초과한 거리 근거는 기존 숫자를 유지하지 않고 `unavailable`로 수렴한다.
- 대표 occurrence가 끝나고 다른 규칙이 남으면 같은 Activity를 다음 대표 규칙으로 갱신하고, 모두
  끝나면 즉시 종료한다.

## SwiftUI 구현 인계

- 대상: `GetUpLiveActivity/RestrictionLiveActivity.swift`
- fixture: `GetUpLiveActivity/RestrictionLiveActivityPreviews.swift`
- 잠금화면 배경과 주요 색상은 앱의 `HomeColor` 값과 같은 상수로 extension 내부에 정의한다.
- 기존 `RestrictionRuleLabel`의 `lock.fill`은 제거하고 규칙명 텍스트와 접근성 label만 유지한다.
- 거리 아이콘은 `location.fill`을 유지하고 accent를 `mint`에서 `#F4D600`으로 변경한다.
- `.keylineTint`도 accent와 일치시킨다.
- 최대 Dynamic Type에서 고정 높이를 두지 않고 세로 재배치·축약 우선순위를 사용한다.
- preview·presentation test는 한국어·영어, 두 appearance, 최대 Dynamic Type과 네 상태를 고정한다.

## 검증 결과

- 최상위 Figma node `395:2090`의 2080×2001 전체 렌더를 확인했다.
- 잠금화면 4상태와 Dynamic Island expanded·compact·minimal 4상태를 확인했다.
- 앱의 local semantic variable과 SF Pro local text style 연결을 확인했다.
- SF Pro Regular·Semibold·Bold 누락 0개
- 최대 Dynamic Type 샘플의 잘림·겹침 0개
- 최종 전체 보드의 잘림·겹침 0개
- 규칙명 임시 아이콘과 사용자 영역의 구현 주석 0개
- Light appearance는 별도 흰 화면을 만들지 않고 승인된 GetUp dark surface 계약으로 명시했다.

## 사용자 피드백 반영

2026-09-26 사용자는 AX5 샘플의 세로 배치는 적절하지만 글자 크기가 최대 Dynamic Type을 나타내기에는
작다고 지적했다. 규칙명·카운트다운·거리·추가 제한을 각각 61/75/53/53pt로 확대하고 auto layout의
세로 hug sizing으로 카드와 전체 보드가 함께 늘어나도록 수정했다. 최종 렌더에서 네 정보가 모두
표시되고 다음 승인 게이트와 겹치지 않음을 확인했다.

## T116 구현 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `검토 대기` |
| 승인자 | 미승인 |
| 승인일 | 미승인 |
| 검토 대상 | Figma node `395:2090`의 전체 잠금화면·Dynamic Island 하이파이와 본 구현 인계 |
| 미해결 항목 | 사용자의 명시적 구현 승인 |

사용자가 T116에서 명시적으로 승인하기 전에는 `T117~T119` 또는 제품 Live Activity UI 변경을
시작하지 않는다. 승인 과정에서 정보 구조나 제품 동작이 바뀌면 T114 계약도 함께 갱신한다.
