# 제한 조건 설정 하이파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US1` |
| 관련 task | `T023`, `T024`, `T060`, `T061` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-23` |
| 문서 상태 | `승인됨 · 구현 기준` |
| 승인된 로우파이 | [제한 조건 설정 로우파이](../low-fidelity/US1-rule-configuration.md) — `2026-08-23` 승인 |
| 관련 명세·contract | [spec.md](../../specs/001-location-app-restriction/spec.md), [location-picker-ui-contract.md](../../specs/001-location-app-restriction/contracts/location-picker-ui-contract.md) |
| Figma node | [US1 / 하이파이 T023 · 검토용](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=50-1365) |
| 후보 비교 node | [US1 / 하이파이 후보 3안 · T024 검토](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=60-1960) |
| 선택안 재설계 node | [US1 / Dark Focus 재설계 · 첨부 기준](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=74-1959) |
| 논리 플로우 재검토 node | [US1 / Dark Focus 논리 플로우 · T024 재검토](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=79-1959) |
| 구현 대상 | `T031`, `T033`~`T035`, `T037`의 SwiftUI 화면과 component |

## 최종 사용자 흐름

1. 규칙 편집 화면의 `START` 또는 `END` 전체 행을 탭하면 편집 대상을 제목으로 명시한 전용 시각
   선택 화면으로 이동한다. 시·분·AM/PM은 독립적인 세로 wheel이며 분은 1분 단위다. 입력·요약·
   오류 상태의 시각은 `06:00 AM` 형식으로 통일하고 AM/PM은 시간 숫자보다 작게 표시한다.
2. `LOCATION` 행을 탭하면 화면 절반 이상을 차지하는 큰 지도에서 중심 핀과 실제 반경 원을 함께
   확인한다. 반경 slider 변경은 지도 원에 즉시 반영한다.
3. 지도 하단에서 D안의 `집`·`회사`·`직접 입력` 방식을 사용한다. `직접 입력`을 탭하면 현재 좌표와
   반경을 유지한 채 장소 이름 화면으로 이동하고, 저장 후 장소 설정으로 복귀한다.
4. 시스템 `FamilyActivityPicker`에서 제한 앱을 하나 이상 선택한다. 앱 UI는 선택 개수만 표시하고
   opaque app token의 이름이나 식별자를 해석하지 않는다.
5. 시간·요일·장소·앱이 모두 유효하면 저장 버튼이 활성화된다. 저장 실패 시 draft를 유지한 상태에서
   같은 값으로 다시 저장한다.
6. 저장된 비활성 규칙의 편집 화면 하단에서 `규칙 삭제`를 선택하면 시스템 Alert가 규칙만 삭제되고
   저장 장소는 보존됨을 안내한다. `취소`는 편집 화면을 유지하고, destructive `삭제`는 대상 규칙만
   제거한다. 같은 규칙이 활성 상태라면 정상 삭제 Alert 대신 US3의 종료 조건 guard Alert를 표시한다.

### 승인된 로우파이와의 차이

- 정보 구조와 제품 동작은 승인된 `D 보완`을 유지했다.
- 선택된 B 화면의 Dark Focus 구조, GetUp 전용 local token·text style, 오류 대비, 저장 실패 modal 및
  접근성 구현 인계 규격을 추가했다. 앱 소유 화면에는 iOS 26 Liquid Glass component를 사용하지 않는다.
- 실제 지도 tile, 실제 앱 이름·token 및 시스템 keyboard·`FamilyActivityPicker` 내부 재설계는
  포함하지 않았다.

## 하이파이 후보 3안

세 후보는 `출근 준비`, `06:00`~`09:00`, 월요일~금요일, `집 · 1km`, 제한 앱 3개로
내용을 통일했다. 이번 후보는 시각 방향을 선택하기 위한 대표 규칙 편집 화면이며, 기존 T023의
9개 상태와 제품 동작은 보존한다.

| 후보 | Figma frame | 참고 방향 | 핵심 특징 | 예상 trade-off |
|---|---|---|---|---|
| `A · Native Calm` | [규칙 편집](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=61-1962) | Jomo, Apple 설정 화면 | 수직 정보 흐름, 밝은 grouped surface, 익숙한 iOS 조작 구조 | 구현·학습 위험이 낮지만 브랜드 인상은 비교적 보수적 |
| `B · Dark Focus` | [규칙 편집](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=61-2005) | Opal | 깊은 다크 배경, 큰 시간 타이포, 제한 조건의 높은 대비 | 몰입감은 강하지만 일반 iOS 설정 문맥과 거리가 있음 |
| `C · Warm Behavioral` | [규칙 편집](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=61-2053) | one sec, GetUp 행동 목표 | 따뜻한 배경, 출발 행동 문구, 해제 조건을 전면에 노출 | 브랜드 차별성은 높지만 A의 정보 명료성을 함께 다듬어야 함 |

후보 선택 뒤 선택안의 색·타이포·surface 원칙을 기존 T023 전체 상태에 확장하고 접근성 대비를
재검증한다. 후보가 승인되기 전에는 SwiftUI 구현을 시작하지 않는다.

`2026-08-23` 사용자 검토에서 `B · Dark Focus`를 선택했다. 첫 전면 적용본은 기존 T023 form layout을
유지한 채 색과 시간 크기만 바꿔 선택한 B의 구조를 반영하지 못했다. 사용자 피드백과 첨부 screenshot을
시각 source of truth로 삼아 `editorial header → large focus card → circular selection → condition card →
bottom CTA` 구조로 9개 상태를 처음부터 다시 작성했다. 후보 A·C, 기존 T023과 잘못된 첫 전면 적용본은
비교·수정 이력으로만 보존한다.

## 화면과 상태 범위

최종 검토 대상은 규칙 설정 12개 화면과 홈 3개 화면, 총 15개다. 이전 하이파이 화면은 디자인 변경
이력으로 보존하되 구현 기준으로 사용하지 않는다.

| 화면 ID | Figma frame | 상태 | 발생 조건 | 표시 내용 | 가능한 행동 |
|---|---|---|---|---|---|
| `HF-FLOW-01` | [규칙 작성](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=80-1967) | `draft` | 규칙 생성·편집 | `START`·`END` 독립 disclosure, 요일·장소·앱 진행 상태 | 각 조건 편집 |
| `HF-FLOW-02` | [시작 시각](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=80-2010) | `선택` | `START` 탭 | 시·분·AM/PM wheel, 1분 단위 분 값, 선택 행 | 시작 시각 완료 |
| `HF-FLOW-03` | [종료 시각](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=80-2033) | `disabled` | `END` 탭 | 같은 wheel 구조와 최소 15분 안내 | 유효한 종료 시각 완료 |
| `HF-FLOW-05` | [장소와 반경](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=81-1967) | `기본` | `LOCATION` 탭 | 큰 지도, 중심 핀, 실제 반경 원, slider | 지도·반경·장소 선택 |
| `HF-FLOW-06` | [장소 이름 필요](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=63-8070) | `validation` | 저장 장소 이름 누락 | 지도·반경 유지와 이름 필요 안내 | 장소 이름 입력 |
| `HF-FLOW-07` | [직접 입력](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=81-2034) | `keyboard` | `직접 입력` 탭 | 선택 좌표·반경 유지, 장소 이름 field | 이름 저장 |
| `HF-FLOW-08` | [위치 권한](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=81-2071) | `권한 부족` | 현재 위치 권한 없음 | 사용 목적, 설정 이동, 나중에 | 설정 이동, 복귀 |
| `HF-FLOW-09` | [앱 선택](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=82-1965) | `시스템 소유 경계` | `BLOCKED` 탭 | 검색, 선택 상태와 선택 개수 예시 | 선택 완료 |
| `HF-FLOW-10` | [최종 검토](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=63-8169) | `ready` | 네 필수 조건 유효 | 12시간제 시간·요일·장소·앱 요약, 활성 저장 CTA | 조건 재편집, 저장 |
| `HF-FLOW-11` | [저장 실패](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=63-8217) | `오류` | repository 저장 실패 | 보존된 draft와 같은 화면의 오류 card | 재시도, 편집 복귀 |
| `HF-FLOW-12` | [규칙 삭제](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=147-2006) | `inactive / destructive entry` | 저장된 비활성 규칙 편집 | `GetUp Focus/color/error`를 사용하는 353×52pt bordered 삭제 버튼 | 삭제 확인 열기 |
| `HF-FLOW-13` | [규칙 삭제 확인](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=147-2049) | `confirmation` | 비활성 규칙 삭제 시도 | 규칙만 삭제되고 저장 장소는 보존된다는 iOS 26 공식 Alert | 취소, destructive 삭제 |
| `HOME-01` | [규칙 없음](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=86-2054) | `empty` | 저장 규칙 없음 | 제품 행동 원리, 문 아이콘, 새 규칙 CTA | 첫 규칙 생성 |
| `HOME-02` | [모든 규칙 1/3](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=88-1959) | `today` | 저장 규칙 중 오늘 적용 | `RULE 1 OF 3`, 오늘 적용일과 조건을 묶은 단일 swipe card | 좌우 swipe, 규칙 수정, 새 규칙 |
| `HOME-03` | [모든 규칙 2/3](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=89-1959) | `next` | 저장된 다른 유효 규칙 | `RULE 2 OF 3`, 해당 규칙의 다음 적용일과 조건을 묶은 단일 swipe card | 좌우 swipe, 규칙 수정, 새 규칙 |

## 시각 명세

### 색상과 token

선택된 B 방향의 앱 surface는 시스템 Dark Mode 여부와 무관하게 아래 브랜드 dark theme를 기본으로
사용한다. 시스템 picker·alert·keyboard처럼 iOS가 소유하는 경계는 시스템 appearance를 존중한다.

| 용도 | B theme token | 값 | 적용 |
|---|---|---|---|
| 최상위 배경 | `GetUp/Focus/Background` | `#08090B` | 규칙·장소·검증 화면 |
| 주요 surface | `GetUp/Focus/Surface` | `#15171B` | form card, picker, sheet |
| 보조 surface | `GetUp/Focus/SurfaceElevated` | `#202329` | control, keyboard key, 비선택 요일 |
| 집중 accent | `GetUp/Focus/Accent` | `#F4D600` | 종료 시각, 선택 요일, slider, 주요 행동 |
| 기본 text | `GetUp/Focus/TextPrimary` | `#FFFFFF` | 제목과 필수 정보 |
| 보조 text | `GetUp/Focus/TextSecondary` | `#A6A8AD` | 도움말과 비활성 정보 |
| 오류 text | `GetUp/Focus/Error` | `#FF6961` | 권한·저장 오류 |

| 용도 | design token | Light | Dark | 대비 결과 |
|---|---|---|---|---|
| 화면 배경 | `Backgrounds/Primary` | `#FFFFFF` | `#000000` | 기본 본문과 21:1 |
| grouped card | `Backgrounds (Grouped)/Secondary` | `#F2F2F7` | `#1C1C1E` | semantic surface 사용 |
| 기본 label | `Labels/Primary` | `#000000` | `#FFFFFF` | 21:1 |
| 보조 label | `Labels/Secondary` | `#3C3C43` 60% | `#EBEBF5` 60% | 본문 외 보조 정보에만 사용 |
| 완료 행동 | `System/Blue` | `#007AFF` | `#0A84FF` | 흰 label과 큰 control 기준 충족 |
| 선택 강조 | `GetUp/Accent/Yellow` | `#FFD60A` | `#FFD60A` | 검정 label과 약 14.8:1 |
| 권한 오류 본문 | `GetUp/Error/Text` | `#B42518` | `#FF6961` | Light 배경에서 6.52:1 |

원격 `iOS and iPadOS 26` 색상 variable의 `Light`·`Dark` mode를 사용한다. 기존 승인 frame에서 서로
다른 library import ID로 남은 소수의 Dark 보조 label은 동일 semantic token의 resolved 값으로
정규화하며, 구현에서는 `Color.primary`, `Color.secondary`, system background와 asset token으로
매핑한다.

### 서체와 Dynamic Type

| 용도 | text style 또는 token | 굵기 | 줄 수·축약 규칙 | 큰 글자 대응 |
|---|---|---|---|---|
| navigation title | `Headline/Regular` | SF Pro Semibold 17/22 | 1줄 | 접근성 크기에서 system toolbar 규칙 유지 |
| 시간 label·주요 값 | `GetUp/Focus/Time`, `Body/Emphasized` | 20pt Semibold 이상 | 값 축약 금지, 종료 시각 accent | 두 열이 겹치면 세로 stack |
| form row title | `Subheadline/Regular` | 15/20 | 최대 2줄 | label과 detail을 세로 배치 |
| detail·선택 개수 | `Caption1/Regular` | 12/16 | 의미 손실 축약 금지 | 별도 줄로 이동 |
| 도움말·오류 | `Footnote/Regular` 상당 | 13/18~20 | 자연 줄바꿈 | 고정 높이 금지, scroll 허용 |

제품 UI는 `SF Pro`·`SF Pro Rounded` 계열만 사용한다. Apple 시스템 keyboard 내부의
`SF Compact Rounded`는 시스템 소유 예외다. Dynamic Type `AX1`~`AX5`에서 전체 화면을 세로
scroll하며 label·값이 겹치면 행을 두 줄로 재배치한다.

### 간격과 layout

- 기준 frame: iPhone `393×852pt`, 세로 방향.
- Grid: 8pt 기반. 주요 간격은 8, 12, 16, 24, 32pt를 사용한다.
- 규칙 편집 좌우 margin: 28pt. sheet 내부 margin: 16~20pt.
- grouped card: 336pt 폭, 약 28pt corner radius. 입력 행은 내용에 따라 늘어나며 최소 48pt다.
- interactive element와 요일·slider thumb의 hit area는 최소 `44×44pt`다.
- safe area와 system toolbar를 침범하지 않고, keyboard 표시 시 입력 field가 가려지지 않게 scroll한다.

### 아이콘과 이미지

| 자산 | 이름 또는 SF Symbol | 용도 | 접근성 처리 |
|---|---|---|---|
| 뒤로가기 | `chevron.backward` | 상위 화면 복귀 | `뒤로` label |
| 완료 | `checkmark` | 유효 입력 저장·sheet 확정 | disabled·enabled trait와 hint 제공 |
| 현재 위치 | `location` 계열 | 현재 위치 바로가기 | 현재 권한 상태와 결과를 value로 제공 |
| 지도 핀 | `mappin` | 지도 중심 기준점 | 장식 핀은 숨기고 지도에 별도 label 제공 |

실제 지도 tile은 MapKit 구현에서 제공한다. Figma의 단색 지도 영역은 구조와 contrast를 검증하기
위한 placeholder이며 출시 asset이 아니다.

## component 상태

| component | 기본 | pressed·selected | disabled | 오류 | loading | 접근성 동작 |
|---|---|---|---|---|---|---|
| 주요 CTA | yellow fill + black label | opacity·scale feedback | elevated gray, 저장 불가 사유 | 동일 화면 오류 card | 중복 tap 방지 | label, enabled state, 저장 hint |
| 요일 chip | neutral circle | yellow + 검정 label | 해당 없음 | 최소 1개 안내 | 해당 없음 | 요일명, 선택됨 trait, 44pt hit area |
| 시간 wheel picker | 시·분·AM/PM 세 열 | 중앙 선택 행 강조, 분 1분 snap | 저장 가능한 구간이 15분 미만이면 완료 차단 | 최초 유효 종료 시각 안내 | 해당 없음 | 시작·종료, AM/PM과 다음 날 여부를 value로 제공 |
| 반경 slider | 1km 기본 | 여섯 단계에 snap | 위치 미선택 시 저장만 비활성 | 값 집합 밖 저장 금지 | 해당 없음 | `500m`~`5km` value, adjustable action |
| 저장 장소 chip | neutral | yellow selected | 해당 없음 | 권한 부족은 지도 핀 대안 유지 | 해당 없음 | 장소 이름과 선택 상태 제공 |
| disclosure row | title + detail + chevron | system highlight | 필수 값 누락 detail | 첫 오류로 focus 이동 | 저장 중 입력 유지 | 하나의 button으로 grouping |
| 저장 실패 alert | 설명 + 두 action | primary `다시 저장` | 해당 없음 | draft 유지 명시 | 재시도 중 action 잠금 | modal focus, title부터 읽기 |

## 문구와 현지화

| 문자열 ID | 한국어 문구 | 변수·복수형 | 축약 또는 줄바꿈 규칙 |
|---|---|---|---|
| `rule_editor.title` | 규칙 설정 | 없음 | 1줄 |
| `rule_editor.minimum_duration_hint` | 종료 시각은 시작 시각으로부터 최소 15분 이후만 선택할 수 있어요. | 없음 | 2줄 허용 |
| `rule_editor.optional_name` | 규칙 이름 (선택 사항) | 없음 | detail은 별도 줄 가능 |
| `rule_editor.selected_apps_count` | %lld개 앱 선택됨 | 개수 | 축약 금지 |
| `location_picker.title` | 장소 설정 | 없음 | 1줄 |
| `location_picker.permission_missing` | 현재 위치를 사용할 수 없어요. 지도 핀으로 직접 설정할 수 있어요. | 없음 | 2줄 이상 허용 |
| `location_picker.reuse_hint` | 이 장소는 다른 규칙에서도 다시 사용할 수 있어요. | 없음 | 자연 줄바꿈 |
| `rule_save_error.title` | 저장하지 못했어요 | 없음 | 1줄 우선 |
| `rule_save_error.message` | 입력한 내용은 그대로 유지돼요. 잠시 후 다시 시도해 주세요. | 없음 | 자연 줄바꿈 |
| `rule_save_error.retry` | 다시 저장 | 없음 | 축약 금지 |

## 접근성 검증

- [x] VoiceOver 읽기 순서, grouping, label, value, hint와 focus 이동 규칙을 정의했다.
- [x] `AX1`~`AX5`의 scroll·행 재배치·고정 높이 금지 규칙을 정의했다.
- [x] 기본 text와 권한 오류 본문의 contrast를 확인했다.
- [x] selected·disabled·오류를 색상뿐 아니라 문구·trait·component 상태로 표현했다.
- [x] Reduce Motion에서 같은 정보와 focus 이동을 유지하도록 정의했다.
- [x] alert·하위 화면 복귀·validation 실패 뒤 focus 목적지를 정의했다.
- [x] interactive element의 최소 `44×44pt` hit area를 정의했다.

검증 결과: 최종 논리 플로우 보드의 규칙 설정 12개와 홈 3개, 총 15개 화면을 검사했다. 시작·종료
wheel은 `58`·`59`·`00`·`01`·`02` 순서로 1분 간격을 표현하고, 홈과 규칙 요약은 시간과 작은
AM/PM을 같은 그룹으로 구성한다. 임시 placeholder 문구와 SF Pro 외 제품 font는 0건이었다.
Dark Focus 화면은 GetUp Focus token을 사용한다. 실제 Accessibility Inspector와
최대 Dynamic Type 실행 검증은 `T080` 및 SwiftUI 구현 뒤 수행한다.

T060에서 추가한 `HF-FLOW-12`, `HF-FLOW-13`과 [삭제 UI 규격 panel](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=151-2014)의
text node 70개를 별도로 감사했다. SF Pro 외 서체, 빈 text, placeholder와 직접 자식 overflow는
0건이며, 확인 화면은 Apple iOS 26 `Alert`의 `Type=Side-by-Side`와
`Mode=Light, Type=Destructive` 행동 variant를 사용한다.

## 플랫폼 동작과 제약

- `FamilyActivityPicker` 내부 목록, 앱 icon·이름 표시와 선택 UI는 시스템이 소유한다. Figma frame은
  앱과 시스템 사이의 정보 경계와 완료 결과만 설명한다.
- 시스템 keyboard 내부 font와 key layout은 재설계하지 않는다.
- MapKit 실제 지도 tile, 위치 blue dot과 권한 prompt는 구현·실기기 상태를 따른다.
- 앱은 실제 좌표, 주소, 앱 token을 Figma·log·analytics에 저장하지 않는다.

## 구현 인계

- layout·flow·token: [Dark Focus 논리 플로우 wrapper](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=79-1959)와 이 문서의 시각 명세를 함께 사용한다. 기존 [구조 재설계 wrapper](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=74-1959), [T023 wrapper](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=50-1365), [잘못된 첫 B 적용본](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=65-1959)은 비교·수정 이력이다.
- 홈 pager의 한 page는 시간 card와 행동 card 두 개가 아니라 `Swipeable rule card` 하나다. 시간,
  위치·반경, 제한 앱과 수정 행동을 같은 accessibility element group으로 묶고 page indicator에는
  현재 rule index와 전체 rule count를 제공한다.
- 홈 pager는 오늘 또는 다음 규칙 하나를 선택하는 filter가 아니다. 저장된 모든 유효 규칙을 표시하며
  현재 보이는 card와 무관하게 각 규칙은 독립적으로 적용된다. card 상단의 `TODAY`·`NEXT`는 해당
  규칙의 다음 실행 시점만 설명한다.
- 필요한 asset: 별도 raster asset 없음. SF Symbols와 MapKit/system UI를 사용한다.
- `Localizable.xcstrings` key: `rule_editor.*`, `location_picker.*`, `rule_save_error.*`.
- UI test identifier: `ruleEditor.startTime`, `ruleEditor.endTime`, `ruleEditor.weekday.*`,
  `ruleEditor.locationRow`, `ruleEditor.applicationRow`, `ruleEditor.save`,
  `locationPicker.radius`, `locationPicker.currentLocation`, `ruleSaveError.retry`,
  `home.rulePager`, `home.ruleCard.<ruleID>`, `home.rulePageIndicator`, `ruleEditor.delete`.
- 삭제 문구: `규칙을 삭제할까요?`, `규칙만 삭제되며 저장한 장소는 다른 규칙에서 계속 사용할 수 있어요.`,
  `취소`, `삭제`. VoiceOver hint는 `확인 후 이 규칙을 삭제합니다.`로 제공한다.
- 구현 대상: `T031`, `T033`, `T034`, `T035`, `T037`. 활성 중 같은 삭제 진입점을 US3 guard로
  전환하는 판정은 `T066`, 정상·활성 삭제 UI test는 `T063`에서 검증한다.
- 알려진 차이: 실제 지도·시스템 picker·keyboard와 실기기 Dynamic Type은 구현 후 검증한다.

## 검토 체크리스트

- [x] 승인된 로우파이와 관련 `spec.md`를 참조한다.
- [x] 기본·disabled·권한 부족·keyboard·시스템 소유·오류·Dark 상태를 다룬다.
- [x] Light·Dark Mode와 Dynamic Type 규칙을 정의했다.
- [x] 접근성 검증 결과와 후속 실기기 검증을 기록했다.
- [x] component 상태, 문구, asset과 구현 대상을 연결했다.
- [x] 실제 좌표나 app token 같은 민감 정보를 포함하지 않았다.
- [x] Figma 링크가 검토 대상 node를 직접 가리킨다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-23` | 사용자 | `검토 대기` | T023 하이파이 초안 검토 요청 | `T024`에서 피드백과 승인 여부 반영 |
| `2026-08-23` | 사용자 | `후보 검토 중` | 디자인 레퍼런스를 바탕으로 하이파이 후보 3안 요청 | A·B·C 비교 보드 제작, 방향 선택 대기 |
| `2026-08-23` | 사용자 | `B 방향 선택` | 세 후보 중 B가 가장 적합하며 전반적인 하이파이를 B 무드로 재작성 요청 | 9개 상태와 접근성 인계 패널에 B theme 적용, 최종 검토 대기 |
| `2026-08-23` | 사용자 | `구조 재설계 요청` | 첫 적용본은 예전 UI의 색상 변경에 불과하며 첨부한 B 화면과 같은 UI 구조를 요구 | iOS 26 component 제외, 첨부 screenshot 기준 9개 화면 전면 재작성 |
| `2026-08-23` | 사용자 | `논리 플로우 재설계 요청` | 시간 편집 진입, 표기 혼용, 작은 지도·반경 누락, 장소 이름 진입과 전체 흐름을 수정 요청 | 24시간제와 명시적 START/END 편집, 큰 지도·반경 원, D안의 직접 입력을 연결한 11개 화면 작성 |
| `2026-08-23` | 사용자 | `타임 피커·홈 보완 요청` | 첨부 이미지처럼 시·분·AM/PM wheel을 사용하고 분을 1분 단위로 조정하며 홈 UI 추가 요청 | 사용자 수정본을 보존하고 두 time picker와 홈 3개 상태를 Dark Focus로 추가 |
| `2026-08-23` | 사용자 | `홈 카드 통합 요청` | swipe 대상 규칙의 시간과 조건이 두 카드로 분리되어 하나의 규칙으로 읽히지 않음 | 하나의 외곽 container, rule index, divider, page indicator와 swipe 안내로 통합 |
| `2026-08-23` | 사용자 | `모든 규칙 적용 요청` | 여러 규칙이 저장된 경우 일부 대표 규칙만이 아니라 모두 적용 | 모든 저장 규칙을 pager에 표시하고 각 규칙을 독립 적용, 동시 충족 시 합집합 유지 |
| `2026-08-23` | 사용자 | `최종 승인` | 사용자가 직접 다듬은 최종 하이파이를 확인하고 이대로 구현 기준으로 승인 | 최종 Figma 감사 통과, `T024` 완료 및 `T025`부터 구현 선행 테스트 진행 가능 |
| `2026-08-24` | `Codex` | `검토 대기` | T037 구현 뒤 누락이 확인된 정상 삭제 버튼·확인 Alert를 최종 wrapper에 동기화 | `T061`에서 사용자 피드백과 승인 여부 반영 |
| `2026-08-24` | 사용자 | `승인됨` | T060에서 동기화한 정상 삭제 버튼·확인 Alert를 구현 기준으로 승인 | `T061` 완료 및 `T062` 테스트 작성 가능 |

## 변경 기록

| 날짜 | 작성자 | 변경 내용 | 관련 검토 의견 |
|---|---|---|---|
| `2026-08-23` | `Codex` | 승인된 D 보완을 기반으로 9개 상태, Light·Dark, iOS 26 component, 저장 실패 alert와 접근성 인계 규격을 작성 | 최초 하이파이 검토 요청 |
| `2026-08-23` | `Codex` | 동일 규칙 데이터로 `Native Calm`, `Dark Focus`, `Warm Behavioral` 후보와 비교 카드를 별도 Figma 보드에 작성 | 후보 3안 요청 |
| `2026-08-23` | `Codex` | B의 다크 surface·대형 시간 위계·노란 accent를 규칙, 장소, 권한, keyboard, DatePicker, 시스템 선택, 저장 실패 상태 전체에 확장 | B 방향 선택 |
| `2026-08-23` | `Codex` | 첫 B 적용본의 구조적 오류를 인정하고 GetUp Focus local token 30개·text style 7개를 만든 뒤 editorial header, large focus card, circular selection, condition card, bottom CTA 구조로 9개 화면을 처음부터 다시 작성 | 구조 재설계 요청 |
| `2026-08-23` | `Codex` | Dark Focus 시각 언어를 유지하면서 규칙 작성부터 저장 오류까지 11개 화면을 순서대로 재구성하고, 24시간 표기·큰 지도·반경 원·D안 직접 입력 진입·초안 보존 규칙을 명시 | 논리 플로우 재설계 요청 |
| `2026-08-23` | `Codex` | 시작·종료 화면을 시·분·AM/PM 세로 wheel로 교체하고 분 1분 단위를 명시했다. 규칙 없음·오늘·다음 예정 홈 3개 상태를 Dark Focus로 추가하고 12시간 표기를 전체 구현 기준으로 정리했다. | 타임 피커·홈 보완 요청 |
| `2026-08-23` | `Codex` | 홈의 시간과 행동·조건 영역을 하나의 `Swipeable rule card` 외곽선 안에 연결하고 `RULE n OF 3`, page indicator와 좌우 swipe 안내를 추가했다. | 홈 카드 통합 요청 |
| `2026-08-23` | `Codex` | 홈 pager에 모든 유효 규칙을 `RULE n OF 3`과 page indicator로 표시하고 오늘 적용 규칙 우선·나머지 다음 적용 시점 순 정렬, 현재 card와 무관한 독립 적용 원칙을 명시했다. | 모든 규칙 적용 요청 |
| `2026-08-23` | `Codex` | 사용자 수정 최종본의 13개 제품 화면을 다시 감사했다. SF Pro 외 서체, 임시 문구, text overflow가 없고 시·분·AM/PM wheel, 1분 단위 분 전환, 큰 지도·반경 원, 장소 이름 진입, 통합 swipe card와 모든 규칙 pager가 유지됨을 확인했다. | 최종 승인 |
| `2026-08-24` | `Codex` | T037의 실제 SwiftUI를 기준으로 `HF-FLOW-12` 삭제 버튼, `HF-FLOW-13` 공식 iOS 26 삭제 확인 Alert와 T060 상태·문구·접근성·구현 인계 panel을 최종 wrapper에 추가했다. | 규칙 삭제 UI 누락 보완 |

## 구현 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `승인됨` |
| 승인자 | 사용자 |
| 승인일 | `2026-08-24` |
| 미해결 항목 | 없음 |

이 문서와 연결된 최종 Figma node를 US1 SwiftUI 구현 기준으로 사용한다.
