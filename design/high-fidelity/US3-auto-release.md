# 조건 종료 시 자동 해제와 활성 중 편집 차단 하이파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US3` |
| 관련 task | `T058`, `T059` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-24` |
| 문서 상태 | `검토 대기` |
| 승인된 로우파이 | [US3 자동 해제 로우파이](../low-fidelity/US3-auto-release.md) |
| 관련 명세·contract | [spec.md](../../specs/001-location-app-restriction/spec.md), [restriction-evaluation-contract.md](../../specs/001-location-app-restriction/contracts/restriction-evaluation-contract.md), [platform-events-contract.md](../../specs/001-location-app-restriction/contracts/platform-events-contract.md) |
| Figma wrapper | [US3 · T058 하이파이](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=136-1988) |
| 구현 대상 | `T064`의 `RuleEditorModel.swift`·`RestrictionStatusView.swift`, `T065`의 `AppModel.swift` |

## 최종 사용자 흐름

1. 활성 `(ruleID, revision)`과 현재 규칙 revision이 일치하면 홈은 `RESTRICTION ACTIVE`와
   `조건 종료 후 수정 가능`을 표시한다.
2. 사용자가 활성 규칙의 편집·끄기·삭제를 시도하면 요청을 수행하지 않고 iOS 26 `Alert`를 표시한다.
3. Alert는 `집 1km 밖으로 이동` 또는 `09:00 AM 이후`라는 실제 종료 조건과 `확인` 한 개만 제공한다.
4. `확인` 뒤 활성 홈을 유지하며, 신뢰 가능한 위치 이탈 또는 시간 종료를 기다린다.
5. 조건 종료가 확인되면 활성 규칙의 앱 token 합집합을 다시 계산하고, 별도 완료 UI 없이 활성 표시와
   guard가 제거된 기존 예정·비활성 홈으로 복귀한다.

### 승인된 로우파이와의 차이

- 화면 구조와 제품 동작의 차이는 없다.
- 로우파이의 활성 홈을 승인된 US2 하이파이와 `GetUp Focus` token으로 교체했다.
- 편집 차단은 Apple iOS 26 공식 `Alert` component instance를 유지하고 접근성 annotation을 추가했다.
- 자동 해제 완료 전용 화면·배너·toast·VoiceOver announcement는 추가하지 않았다.

## 화면과 상태 범위

| 화면 ID | Figma frame | 상태 | 발생 조건 | 표시 내용 | 가능한 행동 |
|---|---|---|---|---|---|
| `US3-HF-01` | [활성 중 편집 진입점 차단](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=136-2115) | `active / guarded` | 현재 규칙 revision이 활성 집합과 일치 | 활성 상태, 규칙 이름, 시간, 장소·반경, 제한 앱 수, 변경 가능 조건 | 다른 규칙 탐색, 종료 대기 |
| `US3-HF-02` | [활성 중 편집 차단 Alert](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=136-2157) | `edit blocked` | 편집·끄기·삭제 시도 | 거부 이유, 위치 또는 시간 종료 조건, `확인` | Alert 닫기 |
| `US3-HF-SPEC` | [하이파이 규격](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=136-2091) | `handoff` | 디자인·개발 검토 | token, Dynamic Type, VoiceOver, focus, 자동 해제 계약 | 해당 없음 |

조건 종료 뒤 상태는 새로운 frame이 아니라 기존 예정·비활성 홈을 사용한다. 위치 `unavailable`과 권한
부족 안내는 US4 범위이며 T058에 별도 상태를 추가하지 않는다.

## 시각 명세

### 색상과 token

| 용도 | design token | 값 | 대비·동작 |
|---|---|---|---|
| 최상위 배경 | `GetUp Focus/color/background` | `#08090B` | 흰 text와 `19.92:1` |
| card surface | `GetUp Focus/color/surface` | `#15171B` | 보조 text와 `7.54:1` |
| 주요 text | `GetUp Focus/color/textPrimary` | `#FFFFFF` | 배경에서 AAA |
| 보조 text | `GetUp Focus/color/textSecondary` | `#A6A8AD` | surface에서 AAA |
| 활성 accent | `GetUp Focus/color/accent` | `#F4D600` | 배경에서 `13.72:1` |
| Alert | iOS semantic color·Liquid Glass | system-owned | Light·Dark, Increase Contrast 설정을 따름 |

활성 상태는 accent만 사용하지 않고 `RESTRICTION ACTIVE`와 종료 조건 문구를 함께 표시한다. Alert의
배경·label·divider·pressed 상태는 시스템 component를 고정 색으로 덮어쓰지 않는다.

### 서체와 Dynamic Type

| 용도 | text style | 기본 규격 | 큰 글자 대응 |
|---|---|---|---|
| 규칙 제목 | `GetUp Focus/Title` | `SF Pro Bold 34/39pt` | 홈 scroll과 pager 높이 확장, 축약 금지 |
| 상태·section label | `GetUp Focus/Eyebrow`, `Label` | `SF Pro Bold 12/15pt`, `11/14pt` | 색상 외 상태 문구 유지 |
| 조건 설명 | `GetUp Focus/Body` | `SF Pro Semibold 17/22pt` | 고정 높이 금지, 자연 줄바꿈 |
| Alert 제목 | iOS preferred headline | `SF Pro Semibold 17/22pt` | AX1–AX5 자연 줄바꿈 |
| Alert 설명 | iOS preferred body | `SF Pro Regular 17/22pt` | 종료 조건 축약 금지 |
| Alert 행동 | iOS preferred label | `SF Pro Medium 17/22pt` | `확인` 축약 금지 |

제품 UI는 `SF Pro` 계열만 사용한다. Figma의 기본 화면은 기본 글자 크기를 표현하며, AX1–AX5의 실제
Alert 배치와 system-owned 크기는 구현 후 물리 기기에서 다시 검증한다.

### 간격과 layout

- 기준 화면은 iPhone `393×852pt` 세로 방향이다.
- 홈 좌우 margin은 20pt, 새 규칙 control은 `48×48pt`, 규칙 수정 control은 `321×42pt` 시각 영역과
  최소 `44×44pt` 접근성 hit area를 유지한다.
- Alert는 `300×216pt` 기본 component로 중앙에 배치하며, system rendering에서는 content와 Dynamic
  Type에 따른 자체 높이 확장을 허용한다.
- 별도 완료 화면 전환이나 필수 animation은 없고 기존 홈의 상태만 갱신한다.

## component 상태

| component | 기본 | pressed·selected | disabled | 오류·loading | 접근성 동작 |
|---|---|---|---|---|---|
| 활성 규칙 card | `RESTRICTION ACTIVE`와 조건 표시 | pager swipe 유지 | `조건 종료 후 수정 가능` | US4에서 별도 정의 | 상태부터 변경 가능 조건까지 한 흐름으로 읽음 |
| 편집·끄기·삭제 guard | 활성 revision 일치 시 요청 거부 | 해당 없음 | 조건 종료 전 유지 | stale 상태는 최신 active set 재확인 | 세 행동에 동일 종료 조건 안내 |
| iOS 26 `Alert` | 제목·설명·`확인` | system pressed state | 해당 없음 | 표시 실패 시 활성 상태 유지 | 제목 → 설명 → 확인, dismiss 뒤 시도 control로 focus 복귀 |
| 자동 해제 전환 | 기존 홈 상태 재계산 | 해당 없음 | 해당 없음 | 위치 `unavailable`만으로 해제하지 않음 | 완료 전용 focus·announcement 없음 |

## 문구와 현지화

| 문자열 ID | 한국어 문구 | 변수 | 줄바꿈 규칙 |
|---|---|---|---|
| `restriction_status.active` | `RESTRICTION ACTIVE` | 없음 | 색상 외 상태 표현으로 유지 |
| `restriction_status.edit_disabled` | `조건 종료 후 수정 가능` | 없음 | 최대 두 줄 허용 |
| `restriction_guard.title` | `제한 중에는 수정할 수 없어요` | 없음 | 자연 줄바꿈, 축약 금지 |
| `restriction_guard.message` | `%@ %@ 밖으로 이동하거나 %@이 지나면 규칙을 수정·끄기·삭제할 수 있어요.` | 장소 이름, 반경, 종료 시각 | 핵심 조건 모두 보존 |
| `restriction_guard.confirm` | `확인` | 없음 | 축약 금지 |

좌표, 주소, 앱 이름, bundle identifier와 `FamilyActivitySelection` token을 문구·접근성 값·로그에
포함하지 않는다.

## 접근성 검증

- [x] VoiceOver 읽기 순서, Alert grouping과 dismiss 뒤 focus 복귀를 Figma 규격·annotation에 정의했다.
- [x] Dynamic Type에서 고정 높이와 조건 축약을 금지하고 AX1–AX5 후속 검증 범위를 정의했다.
- [x] 기존 GetUp Focus token의 텍스트 대비가 AA 이상임을 확인했다.
- [x] 활성·차단 상태가 색상만으로 전달되지 않는다.
- [x] Reduce Motion에서도 별도 완료 전환 없이 동등한 상태 갱신을 유지한다.
- [x] Alert의 `확인`과 홈 control에 최소 `44×44pt` touch target을 정의했다.

Figma 자동 감사에서 64개 text node가 `SF Pro Bold`·`Semibold`·`Regular`·`Medium`만 사용하고, 누락
font·빈 text·placeholder·shimmer·화면 경계 overflow가 모두 0건임을 확인했다. 실제 Accessibility
Inspector, VoiceOver, AX1–AX5와 Increase Contrast는 구현 후 물리 기기에서 검증한다.

## 플랫폼 동작과 제약

- `Alert`의 실제 material, 색상, button state와 Dynamic Type layout은 SwiftUI·iOS가 소유한다.
- 활성 중 변경 차단은 앱 내부 guard이며, 시스템 설정의 권한 철회나 앱 삭제를 막는다고 안내하지 않는다.
- 시간 종료는 위치 상태와 관계없이 해제하며, 신뢰 가능한 위치 이탈도 같은 합집합 재계산 경로를
  사용한다.
- 다른 활성 규칙이 같은 앱을 제한 중이면 그 앱의 shield는 유지한다.
- 위치 `unavailable`만으로 제한을 해제하지 않는다.

## 구현 인계

- `T064`: `RuleEditorModel.swift`와 `RestrictionStatusView.swift`에서 활성 revision을 기준으로
  편집·끄기·삭제를 같은 guard로 거부하고 종료 조건 Alert를 연결한다.
- `T065`: `AppModel.swift`에서 자동 해제 뒤 active set을 다시 읽고 기존 홈·편집 흐름을 재활성화한다.
- `Localizable.xcstrings`에는 `restriction_guard.title`, `restriction_guard.message`,
  `restriction_guard.confirm`을 추가한다.
- UI test identifier는 `restrictionStatus.editDisabled`, `restrictionGuard.alert`,
  `restrictionGuard.confirm`을 사용한다.
- 별도 image·raster asset은 필요하지 않으며 기존 `GetUp Focus` 변수·text style과 Apple iOS 26
  `Alert` component를 재사용한다.

## 검토 체크리스트

- [x] 승인된 로우파이, `spec.md`, restriction·platform event contract를 참조했다.
- [x] 활성 guard, 편집 차단 Alert와 조건 종료 뒤 기존 홈 복귀를 다룬다.
- [x] 자동 해제 완료 전용 화면·배너·toast·announcement를 포함하지 않았다.
- [x] token, Dynamic Type, VoiceOver, focus, 명암과 touch target을 정의했다.
- [x] 위치 `unavailable`, 다중 규칙 합집합과 플랫폼 우회 한계를 정확히 기록했다.
- [x] 실제 좌표·주소·앱 식별 정보·token을 포함하지 않았다.
- [x] Figma 링크가 wrapper와 각 검토 대상 node를 직접 가리킨다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-24` | 사용자 | `검토 대기` | T058 하이파이 초안 검토 요청 | `T059`에서 피드백과 승인 여부 반영 |

## 변경 기록

| 날짜 | 작성자 | 변경 내용 | 관련 검토 의견 |
|---|---|---|---|
| `2026-08-24` | `Codex` | 승인된 활성 홈과 iOS 26 Alert를 재사용해 T058 하이파이·접근성 규격 작성 | 최초 초안 |

## 구현 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `검토 대기` |
| 승인자 | `<미승인>` |
| 승인일 | `<미승인>` |
| 미해결 항목 | T059 사용자 검토와 승인 |

T059에서 승인 상태가 `승인됨`이 되기 전에는 T064·T065 UI 구현을 시작하지 않는다. 승인 뒤 제품
동작이나 화면 구조가 바뀌면 로우파이 또는 하이파이 검토를 다시 수행한다.
