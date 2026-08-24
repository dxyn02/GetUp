# 제한 활성 상태와 Restricted App Shield 하이파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US2` |
| 관련 task | `T040`, `T041` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-24` |
| 문서 상태 | `승인됨` |
| 승인 로우파이 | [US2 제한 활성 상태 로우파이](../low-fidelity/US2-active-restriction.md) |
| 관련 contract | [shield-ui-contract.md](../../specs/001-location-app-restriction/contracts/shield-ui-contract.md) |
| Figma wrapper | [US2 · T040 하이파이](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=113-1966) |

## 목표와 범위

승인된 기존 홈의 활성 상태를 유지하면서 제한 대상 앱에서 사용자가 저장 장소, 이탈 반경과 종료
시각을 즉시 이해할 수 있는 시스템 shield를 정의한다. MVP는 모든 지원 버전에서 secondary action과
임시 우회를 제공하지 않고 primary `앱 닫기`만 제공한다.

포함 범위는 기본 글자 크기의 활성 홈과 shield, Dynamic Type `AX5` shield 비교 상태, GetUp Focus
색상·타이포·간격 token, VoiceOver 순서, 명암과 구현 인계다. 실제 좌표·주소·앱 식별 정보, shield
내부 지도, `오늘만 허용`, 인앱결제 및 최종 시스템 rendering 검증은 포함하지 않는다.

## 화면과 상태

| 화면 ID | Figma frame | 상태 | 표시 내용 | 가능한 행동 |
|---|---|---|---|---|
| `US2-HF-01` | [기존 홈 활성 상태](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=113-1983) | `active` | `RESTRICTION ACTIVE`, `집 · 1km`, `09:00 AM`, 제한 앱 3개 | 상태 확인; 조건 종료 전 규칙 수정·삭제 불가 |
| `US2-HF-02` | [Restricted App Shield 기본](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=113-2025) | `shielded/default` | 정적 GetUp 아이콘, 장소·반경 제목, 해제 조건 설명 | `앱 닫기` |
| `US2-HF-03` | [Restricted App Shield AX5](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=113-2045) | `shielded/AX5` | 확대된 제목·설명의 자연 줄바꿈과 같은 해제 정보 | `앱 닫기` |
| `US2-HF-SPEC` | [구현 규격](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=113-2033) | `handoff` | component 치수, Dynamic Type, VoiceOver, 명암 결과 | 해당 없음 |

기준 frame은 iPhone `393×852pt` 세로 방향이다. `US2-HF-01`은 별도 화면이 아니라 승인된
`HOME-02`의 활성 상태이며, 현재 보이는 card와 무관하게 활성 규칙 전체가 독립 적용된다는 기존 홈
계약을 유지한다.

## 시각 명세

### 색상과 명암

| 용도 | token | 값 | 대비 |
|---|---|---|---|
| 최상위 배경 | `GetUp Focus/color/background` | `#08090B` | 흰 text와 `19.92:1` |
| shield surface | `GetUp Focus/color/surface` | `#15171B` | 보조 text와 `7.54:1` |
| 주요 text | `GetUp Focus/color/textPrimary` | `#FFFFFF` | 배경에서 AAA |
| 보조 text | `GetUp Focus/color/textSecondary` | `#A6A8AD` | surface에서 AAA |
| 활성 accent | `GetUp Focus/color/accent` | `#F4D600` | 배경에서 `13.72:1` |
| accent 위 text | `GetUp Focus/color/onAccent` | `#090A0C` | accent에서 `13.64:1` |

shield primary action의 실제 blue와 Liquid Glass 재질은 iOS 26 `Button - Liquid Glass - Text`
component instance를 사용한다. 구현에서는 시스템이 제공하는 button rendering과 Increase Contrast
설정을 존중하고 색을 고정해 덮어쓰지 않는다.

### 타이포와 Dynamic Type

| 상태·용도 | 서체 | 크기/행간 | 줄바꿈 규칙 |
|---|---|---|---|
| 기본 shield 제목 | `SF Pro Semibold` | `26/32pt` | 305pt 안에서 자연 줄바꿈, 축약 금지 |
| 기본 shield 설명 | `SF Pro Semibold` | `17/22pt` | 장소·반경·종료 시각을 모두 보존 |
| AX5 비교 제목 | `SF Pro Semibold` | `34/41pt` | 두 줄 이상 허용 |
| AX5 비교 설명 | `SF Pro Semibold` | `23/30pt` | 고정 높이 금지, 자연 줄바꿈 |
| primary button | iOS system preferred label | 기본 `17pt` | `앱 닫기` 축약 금지 |

제품 UI는 `SF Pro` 계열만 사용한다. `US2-HF-03`은 구현 기대치를 확인하기 위한 비교 상태이며,
`ManagedSettingsUI`가 소유하는 실제 글자 크기와 layout은 구현 후 `AX1`~`AX5`에서 다시 검증한다.

### 간격과 component

- shield 좌우 화면 margin은 20pt, 내부 surface 좌우 padding은 24pt다.
- 정적 GetUp 아이콘은 `88×88pt`, primary action은 기본 `305×48pt`다.
- 기본 content 간격은 24pt, AX5 비교 상태는 28pt다.
- 모든 사용자 행동의 touch target은 최소 `44×44pt`를 유지한다.
- `ShieldConfiguration`의 icon, title, subtitle, primary label과 primary background만 사용한다.
- secondary button, submenu, 지도 진입, 규칙 변경과 일시 해제 행동을 구성하지 않는다.

## 문구와 현지화

| 문자열 ID | 한국어 기본값 | 변수 | 줄바꿈 규칙 |
|---|---|---|---|
| `shield.title.outside_radius` | `%@ %@ 밖으로 이동하세요` | 장소 이름, 반경 | 자연 줄바꿈, 축약 금지 |
| `shield.subtitle.release_condition` | `현재 ‘%@’의 %@ 범위 안에 있어요. %@의 중심에서 %@ 밖으로 이동하거나 %@이 되면 자동으로 다시 사용할 수 있어요.` | 장소 이름, 반경, 종료 시각 | 고정 높이 금지 |
| `shield.primary.close` | `앱 닫기` | 없음 | 축약 금지 |
| `restriction_status.active` | `RESTRICTION ACTIVE` | 없음 | 색상 외 상태 문구로 유지 |
| `restriction_status.edit_disabled` | `조건 종료 후 수정 가능` | 없음 | 최대 두 줄 허용 |

장소 이름과 반경은 사용자가 저장한 표시 값만 사용한다. 좌표, 주소, 앱 이름, bundle identifier와
`FamilyActivitySelection` token을 문구나 접근성 값에 포함하지 않는다.

## 접근성 명세

- VoiceOver 순서는 정적 아이콘 제외 → 제목 → 설명 → `앱 닫기`다.
- primary action의 label은 `제한된 앱 닫기`, hint는 `현재 앱을 종료합니다`로 정의한다.
- 홈 활성 상태는 상태 → 규칙 제목 → 시간 → 장소·반경 → 제한 앱 개수 → 수정 불가 안내 순서다.
- 활성 상태는 `RESTRICTION ACTIVE`와 설명을 함께 사용해 노란색만으로 전달하지 않는다.
- Dynamic Type에서 제목·설명은 축약하지 않고 자연 줄바꿈하며 실제 system shield layout은 실기기에서
  `AX1`~`AX5`로 검증한다.
- Increase Contrast와 Differentiate Without Color에서 같은 문구와 행동을 유지한다.
- Reduce Motion에서도 정보 순서와 닫기 행동을 유지하며 필수 animation은 없다.
- 구현 후 Accessibility Inspector, VoiceOver, 최대 글자 크기와 명암 증가를 물리 기기에서 확인한다.

## 플랫폼 제약

- shield의 전체 layout은 `ManagedSettingsUI`가 소유하며 앱은 임의의 SwiftUI·MapKit view를 삽입하지
  않는다.
- 실제 앱 이름과 아이콘은 GetUp이 token에서 해석하지 않는다. shield의 GetUp 아이콘은 정적 자산이다.
- primary action은 `.close`만 반환하고 사용 권한, 임시 우회 또는 GetUp 앱 진입을 제공하지 않는다.
- 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 restriction coordinator가 shield를 제거한다.

## 구현 인계

- `T052`: `GetUpShieldConfiguration/ShieldConfigurationExtension.swift`에 정적 아이콘, 동적 장소·반경
  제목, 종료 시각 설명과 primary label을 구현한다.
- `T053`: `GetUpShieldAction/ShieldActionExtension.swift`에서 primary action을 `.close`로 처리하고
  나머지 action은 우회 없이 닫힌 동작으로 유지한다.
- `T055`: `GetUp/Features/RestrictionStatus/RestrictionStatusView.swift`에 승인된 홈 활성 상태와
  종료 조건, 조건 종료 전 편집 불가 상태를 연결한다.
- 필요한 자산은 정적 GetUp shield 아이콘 하나이며 별도 지도·raster 배경은 없다.
- 실제 App Group snapshot에서 장소 이름·반경·종료 시각만 읽고 민감 식별 정보를 로그에 남기지 않는다.
- T041 사용자 승인 전에는 T052·T053·T055 UI 구현을 시작하지 않는다.

## 자동 감사 결과

2026-08-24 Figma wrapper와 네 frame을 개별 렌더링하고 50개 text node를 검사했다. 제품 font는
`SF Pro Bold`·`Semibold`·`Regular`·`Medium`만 존재하며 누락 font, 빈 text, 임시 placeholder,
shimmer와 화면 경계 overflow가 모두 0건이었다. 행동 instance는 기본·AX5 shield의
`Primary Action · 앱 닫기` 두 개뿐이고 secondary action은 없었다. GetUp Focus semantic token과
iOS 26 Liquid Glass button component 연결도 유지됐다.

이 task는 디자인·문서 작업이므로 code test는 실행하지 않았다. 실제 system shield rendering,
Accessibility Inspector와 실기기 VoiceOver·Dynamic Type 검증은 구현 후 수행한다.

## 검토 체크리스트

- [x] 승인된 US2 로우파이와 `shield-ui-contract.md`를 반영했다.
- [x] 기존 홈 활성 상태와 기본·AX5 shield 상태를 직접 연결했다.
- [x] 색상 token, 타이포, 간격, component 치수와 명암 결과를 정의했다.
- [x] VoiceOver, Dynamic Type, Increase Contrast와 Reduce Motion 규칙을 정의했다.
- [x] secondary action, 지도 진입과 임시 우회를 포함하지 않았다.
- [x] 실제 좌표·주소·앱 식별 정보와 token을 포함하지 않았다.
- [x] Figma 링크가 wrapper와 각 검토 frame을 직접 가리킨다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-24` | 사용자 | `검토 대기` | T040 하이파이 초안 검토 요청 | `T041`에서 피드백과 구현 승인 여부 반영 |
| `2026-08-24` | 사용자 | `최종 승인` | 기본·AX5 shield, 단일 `앱 닫기`, 접근성·명암·구현 인계를 현재 하이파이대로 승인 | Figma 승인 주석과 구현 승인 상태 반영, T042부터 선행 테스트 진행 가능 |

## 구현 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `승인됨` |
| 승인자 | 사용자 |
| 승인일 | `2026-08-24` |
| 미해결 항목 | 없음 |
