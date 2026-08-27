# 권한 및 위치 문제 안내 하이파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US4` |
| 관련 task | `T070`, `T071`, `T095`, `T096` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-24` |
| 문서 상태 | `승인됨 · 구현 기준` |
| 승인된 로우파이 | [US4 권한 및 위치 문제 안내 로우파이](../low-fidelity/US4-permission-location-errors.md) |
| 관련 명세·contract | [spec.md](../../specs/001-location-app-restriction/spec.md), [restriction-evaluation-contract.md](../../specs/001-location-app-restriction/contracts/restriction-evaluation-contract.md), [platform-events-contract.md](../../specs/001-location-app-restriction/contracts/platform-events-contract.md) |
| Figma wrapper | [US4 · T070 하이파이](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=174-2090) |
| 승인된 권한 요청 frame | [US4 / 권한 요청 클릭 유도 · 하이파이 제안 · 승인 대기](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=204-2014) |
| 구현 대상 | `T076`의 `PermissionGuideModel.swift`, `T077`의 `PermissionGuideView.swift`, `T079`의 `AppLifecycleCoordinator.swift` |

## 최종 사용자 흐름

1. 필수 권한 중 하나 이상이 부족하면 권한 점검 화면이 앱 사용 제한, Always 위치 접근,
   Full Accuracy와 Background App Refresh 상태를 서로 다른 표시로 보여준다.
2. 개요의 `다음`부터 Family Controls → 위치 → Background App Refresh 순서로 각 상태를 확인한다.
3. 권한이 `notDetermined`이면 시스템 alert를 본뜬 중앙 목업을 먼저 표시한다. 사용자가 목업 안의
   `계속` 또는 `앱을 사용하는 동안 허용`을 누른 뒤에만 Family Controls 또는 Core Location 시스템
   요청을 실행한다. 위치가 `.whenInUse`이면 별도 `항상 허용으로 변경` 목업 버튼으로 Always 요청을
   실행한다.
4. 권한이 허용되면 온보딩에서는 다음 권한 화면으로 자동 이동하고, 일반 사용 중 복구 화면에서는
   안내를 닫는다.
5. 권한이 거부되었거나 요구 수준보다 낮으면 같은 권한 화면을 유지하되 다음 주요 행동을
   `설정 열기`로 변경한다. 온보딩의 마지막 Background App Refresh 화면은 상태와 관계없이
   `시작하기`로 완료하고, 일반 복구의 제한 안내만 `확인`으로 닫는다.
6. `시작하기`를 누르기 전에 앱을 이탈하면 완료 상태를 저장하지 않고 다음 실행에서 온보딩 개요부터
   다시 시작한다. 누른 뒤에는 완료 상태를 영구 저장하고 홈으로 이동한다.
7. 위치가 `unavailable`이고 제한이 비활성이면 새 제한을 시작하지 않는다. 제한이 활성이면 위치
   실패만으로 shield를 해제하지 않으며, 시간 종료는 위치와 무관하게 제한을 해제한다.
8. 나서로 돌아오거나 위치를 다시 확인하면 최신 권한·일정·region·snapshot으로 상태를 재평가하고
   갱신된 상태 heading으로 focus를 이동한다.

### 승인된 로우파이와의 차이

- 사용자가 승인한 화면 순서, 문구와 하단 action baseline을 유지했다.
- 제목을 `GetUp Focus/Title`, eyebrow·subtitle·button을 각 전용 text style로 정규화해 정보 위계를
  강화했다.
- 권한 점검 목록의 `🛡️`, `📍`, `🎯`, `🔄` 표시는 승인된 로우파이대로 유지하고, 사용자가 최종
  수정본에서 제거한 화면 우측 상단 badge는 추가하지 않는다.
- 위치 확인 불가 화면의 `위치 다시 확인`은 보조 행동, `설정 열기`는 주요 행동으로 token과 layer
  이름을 정규화했다.
- Family Controls와 위치 최초·Always 요청은 system alert 형태의 중앙 목업을 제공하고 실제 요청을
  실행하는 버튼을 목업 안에 배치한다. 위치와 Background App Refresh 복구는 Settings row 형태의
  비대화형 목업을 유지하며 실제로 선택할 값·toggle만 accent로 강조한다.
- 위치 복구 본문의 `‘항상 허용’으로 변경해 주세요.`와 `‘정확한 위치’를 켜 주세요.` 문구는
  GetUp Focus accent를 사용한다.
- Figma handoff panel에 안전 계약, 접근성, 플랫폼 소유 경계, 개인정보 보호와 구현 identifier를
  기록했다.

## 화면과 상태 범위

### 권한 결정 상태 행렬

| 상태 묶음 | Figma frame | Family Controls | 위치 | Background App Refresh |
|---|---|---|---|---|
| 결정되지 않음 | [승인된 요청 frame](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=204-2014) | alert 목업의 `계속` 탭 후 시스템 요청 | alert 목업의 `앱을 사용하는 동안 허용` 탭 후 시스템 요청 | 별도 시스템 prompt가 없어 실제 조회 상태를 허용·거부 규칙으로 정규화 |
| 허용됨 | [approved](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2182) | 온보딩은 다음 단계, 복구는 닫기 | `.whenInUse`는 Always 요청, `.always/full`은 온보딩 다음 단계·복구 닫기 | 온보딩 `시작하기` |
| 거부됨 | [denied](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2247) | 다음 주요 행동 `설정 열기` | 다음 주요 행동 `설정 열기` | 온보딩 `시작하기`, 일반 복구 `확인` |

Background App Refresh의 플랫폼 상태는 `available`, `denied`, `restricted`만 제공되므로 Figma의
`notDetermined` 시각 상태를 별도 도메인 값으로 추정하지 않는다. `available`은 허용됨, `denied`와
`restricted`는 거부됨 복구 화면으로 표시한다.

| 화면 ID | Figma frame | 상태 | 발생 조건 | 표시 내용 | 가능한 행동 |
|---|---|---|---|---|---|
| `US4-HF-01` | [권한 점검](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2104) | `permission required` | 하나 이상의 필수 권한 부족 | 네 권한의 용도와 자동 제한 영향 | 다음 |
| `US4-HF-02A` | [Family Controls 요청](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=204-2017) | `notDetermined` | 최초 승인 전 | 중앙 alert 목업과 설명 skeleton | 목업 `계속` |
| `US4-HF-02B` | [Family Controls 허용](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2194) | `approved` | 승인 완료 | 후속 권한 확인 가능 | 다음 |
| `US4-HF-02C` | [Family Controls 거부](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2259) | `denied` | 거부·철회 | 시스템 설정 복구 | 설정 열기 |
| `US4-HF-03A` | [위치 사용 중 요청](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=204-2018) | `notDetermined` | 최초 위치 요청 전 | 정확한 위치 안내, 중앙 alert·지도 preview | 목업 `앱을 사용하는 동안 허용` |
| `US4-HF-03A2` | [위치 Always 요청](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=212-2014) | `whenInUse/full accuracy` | 사용 중 위치 승인 후 | Always 필요 안내, 중앙 alert·지도 preview | 목업 `항상 허용으로 변경` |
| `US4-HF-03B` | [위치 허용](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2200) | `always/full accuracy` | 요구 수준 충족 | 후속 권한 확인 가능 | 다음 |
| `US4-HF-03C` | [위치 거부](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2265) | `denied/insufficient` | Always 또는 Full Accuracy 부족 | 시스템 설정 경로와 위치 추정 금지 | 설정 열기 |
| `US4-HF-04B` | [Background App Refresh 허용](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2209) | `available` | 사용 가능 | 안내 완료 가능 | 온보딩 `시작하기` |
| `US4-HF-04C` | [Background App Refresh 거부](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=194-2274) | `denied/restricted` | 시스템 제한 | 복구 지연 가능성과 저전력 모드 제약 | 온보딩 `시작하기`, 일반 복구 `확인` |
| `US4-HF-05` | [위치 확인 불가 · 비활성](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=174-2138) | `location unavailable / inactive` | 제한 비활성 + 위치 `unavailable` | 새 제한 미적용과 확인 항목 | 위치 다시 확인, 설정 열기 |
| `US4-HF-06` | [위치 확인 불가 · 활성](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=174-2150) | `location unavailable / active` | 제한 활성 + 위치 `unavailable` | shield 보존과 시간 종료 우선 | 위치 다시 확인, 설정 열기 |
| `US4-HF-SPEC` | [접근성·구현 인계](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=174-2160) | `handoff` | 디자인·개발 검토 | 위계, 안전 계약, 접근성, 플랫폼·개인정보 경계 | 해당 없음 |

## 시각 명세

### 색상과 token

앱 소유 화면은 시스템 appearance와 무관하게 승인된 GetUp Focus dark theme를 사용한다. 시스템 설정,
Family Controls 승인 UI와 권한 prompt는 iOS appearance를 그대로 따른다.

| 용도 | design token | 값 | 대비·상태 표현 |
|---|---|---|---|
| 최상위 배경 | `GetUp Focus/color/background` | `#08090B` | 주요 text와 약 `19.92:1` |
| card surface | `GetUp Focus/color/surface` | `#15171B` | 보조 text와 약 `7.54:1` |
| 주요 text | `GetUp Focus/color/textPrimary` | `#FFFFFF` | 제목·상태·핵심 원인 |
| 목업 선택 항목·설정 강조 | `GetUp Focus/color/accent` | `#F4D600` | 눌러야 할 버튼·설정 값·toggle과 위치 복구 핵심 문구 |
| 보조 text | `GetUp Focus/color/textSecondary` | `#A6A8AD` | 설명·안전 안내 |
| 주요 action | `GetUp Focus/color/accent` | `#F4D600` | `onAccent`와 약 `13.64:1` |
| 오류 eyebrow | `GetUp Focus/color/error` | `#FF6961` | `LOCATION UNAVAILABLE` 문구와 함께 사용 |
| 보조 action | `GetUp Focus/color/disabled` | `#40434B` | label과 button 이름으로 주요 행동과 구분 |

색상만으로 상태를 전달하지 않는다. 권한 필요와 위치 확인 불가는 eyebrow, 제목, 현재 상태 card와
복구 행동의 조합으로 구분한다.

### 서체와 Dynamic Type

| 용도 | text style | 기본 규격 | 줄바꿈·큰 글자 대응 |
|---|---|---|---|
| 상태 eyebrow | `GetUp Focus/Eyebrow` | `SF Pro Bold 12/15pt` | 대문자 상태 문구 유지 |
| 원인 title | `GetUp Focus/Title` | `SF Pro Bold 34/39pt` | 축약 금지, 2줄 이상 허용 |
| 영향 subtitle | `GetUp Focus/Subtitle` | `SF Pro Regular 15/21pt` | 자연 줄바꿈, 고정 높이 금지 |
| card 핵심 내용 | `GetUp Focus/Body` 상당 | `SF Pro Semibold 17/22pt` | 권한명·현재 상태를 우선 보존 |
| action label | `GetUp Focus/Button` | `SF Pro Bold 15/20pt` | 축약 금지 |

제품 text는 `SF Pro Bold`·`Regular`·`Semibold`만 사용한다. emoji glyph는 OS fallback rendering을
따르되 의미는 같은 행의 권한명·상태 문구로 중복 제공한다. Dynamic Type `AX1`~`AX5`에서는 전체
화면을 세로 scroll하고 title·card·action 사이 고정 간격을 풀어 내용 손실을 막는다.

### 간격과 layout

- 기준 frame은 iPhone `393×852pt` 세로 방향이다.
- 화면 좌우 margin은 20pt, card와 action 폭은 353pt다.
- 주요·보조 action은 `353×56pt`이며 최소 `44×44pt` touch target을 충족한다.
- 단일 action은 `y=768`, 두 action 화면은 보조 행동 `y=692`, 주요 행동 `y=768` baseline을 사용한다.
- AX1~AX5에서는 고정 `y` 구현을 사용하지 않고 `safeAreaInset` 또는 scroll content의 하단 action
  영역으로 변환한다. Figma 좌표는 기본 글자 크기의 시각 기준이다.

### 아이콘과 이미지

| 자산 | 표시 | 용도 | 접근성 처리 |
|---|---|---|---|
| 앱 사용 제한 | `🛡️` | Family Controls 승인과 선택 앱 제한 | 아이콘 숨김, 행 전체 label로 grouping |
| 위치 접근 | `📍` | Always 위치 접근 | 아이콘 숨김, 권한명·설명을 함께 읽음 |
| 정확한 위치 | `🎯` | Full Accuracy와 반경 판정 | 아이콘 숨김, 권한명·설명을 함께 읽음 |
| Background App Refresh | `🔄` | 앱이 닫힌 동안 상태 복구 가능성 | 아이콘 숨김, 권한명·설명을 함께 읽음 |

권한 목록의 emoji는 같은 행의 권한명·설명과 함께 사용하고 아이콘만으로 권한 종류나 현재 상태를
전달하지 않는다. 위치 요청 목업의 추상 지도 preview는 승인된 Figma frame을
`LocationWhenInUsePreview`, `LocationAlwaysPreview` imageset으로 export하며 접근성에서는 숨긴다.

## component 상태

| component | 기본 | pressed·selected | disabled | 오류·loading | 접근성 동작 |
|---|---|---|---|---|---|
| 권한 목록 | 네 권한명과 용도 | 해당 권한 상세로 이동 | 이미 충족한 항목은 상태 text 병행 | 상태 조회 중 skeleton 대신 이전 상태 유지 | 각 행을 하나의 button 또는 static group으로 읽음 |
| 주요 action | accent fill + onAccent label | opacity·scale feedback | 실행 불가 사유를 text로 제공 | 중복 tap 차단, 실패 시 같은 화면 유지 | action 결과와 외부 설정 이동을 hint로 제공 |
| 보조 action | disabled surface + primary label | system highlight | 해당 없음 | 위치 재확인 중 중복 실행 차단 | `위치 다시 확인` 목적을 그대로 읽음 |
| 현재 상태 card | 비활성 유지 또는 활성 shield 유지 | 해당 없음 | 해당 없음 | 위치 `unavailable` 원인 목록 표시 | 상태 → 영향 → 다음 행동 순서로 grouping |
| foreground 복귀 | 최신 snapshot 재평가 | 해당 없음 | 해당 없음 | 실패하면 안전한 이전 상태 보존 | 갱신된 heading으로 focus 이동 |

## 문구와 현지화

| 문자열 ID | 한국어 기본값 | 변수 | 줄바꿈 규칙 |
|---|---|---|---|
| `permission_guide.overview.title` | `원활한 사용을 위해 아래 권한이 필요해요` | 없음 | 자연 줄바꿈, 축약 금지 |
| `permission_guide.family_controls.title` | `앱 사용 제한 권한이 필요해요` | 없음 | 최대 2줄 우선 |
| `permission_guide.location.title` | `정확한 위치 접근 권한이 필요해요` | 없음 | 최대 2줄 우선 |
| `permission_guide.background_refresh.title` | `백그라운드 새로 고침을 확인해 주세요` | 없음 | 자연 줄바꿈 |
| `permission_guide.location_unavailable.inactive.title` | `현재 위치를 확인할 수 없어요` | 없음 | 축약 금지 |
| `permission_guide.location_unavailable.active.title` | `위치를 확인할 수 없어 제한이 유지돼요` | 없음 | 제한 유지 정보 보존 |
| `permission_guide.action.open_settings` | `설정 열기` | 없음 | 축약 금지 |
| `permission_guide.action.next` | `다음` | 없음 | 축약 금지 |
| `permission_guide.action.retry_location` | `위치 다시 확인` | 없음 | 축약 금지 |
| `permission_guide.action.confirm` | `확인` | 없음 | 축약 금지 |
| `permission_guide.action.complete_onboarding` | `시작하기` | 없음 | 축약 금지 |

시스템 설정 경로는 OS 버전에 따라 달라질 수 있으므로 화면 본문은 지원 iOS 26의 실제 경로를 기준으로
검증한다. 좌표·주소·앱 이름·bundle identifier와 `FamilyActivitySelection` token은 문구, 접근성 값과
진단 log에 포함하지 않는다.

## 접근성 검증

- [x] VoiceOver 순서를 상태 → 원인 → 현재 제한 영향 → 복구 행동으로 정의했다.
- [x] 권한 목록 emoji는 접근성에서 숨기고 권한명과 설명을 하나의 label로 묶는다.
- [x] `AX1`~`AX5`에서 scroll, 자연 줄바꿈과 하단 action 재배치 규칙을 정의했다.
- [x] 주요 text·보조 text·accent action의 기본 contrast가 AA 이상임을 확인했다.
- [x] 권한 필요와 위치 확인 불가가 색상만으로 전달되지 않는다.
- [x] Reduce Motion에서도 같은 상태·복구 행동을 유지하고 필수 animation을 사용하지 않는다.
- [x] 외부 설정·picker 복귀 뒤 갱신된 상태 heading으로 focus를 이동한다.
- [x] 모든 action에 최소 `44×44pt` touch target을 정의했다.

사용자가 직접 수정하고 승인한 Figma를 최종 감사해 여섯 화면, text node 48개와 action frame 10개를
검사했다. 권한 점검 목록의 `🛡️`, `📍`, `🎯`, `🔄` 표시는 유지되고 화면 우측 상단 badge는 0개다.
제품 text는 `SF Pro Bold`·`Regular`·`Semibold`만 사용하며 빈 text, placeholder, shimmer와 각
393×852pt 화면의 직접 자식 overflow는 모두 0건이었다. 실제 Accessibility Inspector, VoiceOver,
AX1~AX5, Increase Contrast와 시스템 설정 복귀 focus는 구현 후 물리 기기에서 검증한다.

## 플랫폼 동작과 제약

- Family Controls 승인 UI, 시스템 권한 prompt와 Settings 화면은 iOS가 소유하며 나서가 재설계하지
  않는다.
- Family Controls가 `notDetermined`이면 alert 목업의 `계속`을 누른 뒤
  `AuthorizationCenter.requestAuthorization(for: .individual)`을 호출하고, `denied`이면 같은 화면의
  다음 주요 행동을 Settings 이동으로 변경한다.
- 앱은 개인 사용자가 시스템 설정에서 권한을 철회하거나 앱을 삭제하는 플랫폼 우회를 막는다고
  안내하지 않는다.
- 위치는 alert 목업의 `앱을 사용하는 동안 허용`을 누른 뒤 첫 요청을 실행하고, `.whenInUse`와
  Full Accuracy를 얻으면 별도 alert 목업의 `항상 허용으로 변경`을 눌러 Always 요청을 실행한다.
  최초 요청의 `한 번만 허용` 때문에 Always 요청이 무시되거나 요청 뒤에도 `.whenInUse`가 유지되면
  callback을 무기한 기다리지 않고 `‘한 번만 허용’을 선택했거나 ‘항상 허용’으로 변경하지 않았다면,
  설정에서 위치 접근을 ‘항상’으로 바꿔 주세요.`와 Settings 복구를 제공한다.
- Background App Refresh는 진단·복구 지연 정보이며 특정 background 실행 시각을 보장하지 않는다.
  앱별 Settings에서 변경할 수 없으므로 시스템 전체 `설정 > 일반 > 백그라운드 앱 새로 고침` 경로를
  설명하고 앱별 Settings action을 제공하지 않는다. 이 진단만 제한된 foreground 복귀에서는 권한
  화면을 자동으로 다시 열지 않는다.
- 위치 오류, 오래된 fix, 음수 accuracy, Reduced Accuracy와 반경 경계 중첩은 좌표를 추정하지 않고
  `unavailable`로 처리한다.
- `unavailable / inactive`는 새 shield를 적용하지 않고, `unavailable / active`는 기존 shield를
  보존한다. 시간 종료는 위치와 무관하게 shield를 해제한다.

## 구현 인계

- `T076`: `PermissionGuideModel.swift`에서 권한별 `notDetermined`·허용·거부 행동과 위치 확인 불가의
  비활성·활성 상태를 합성한다.
- `T077`: `PermissionGuideView.swift`에서 이 문서의 hierarchy, token, scroll과 focus 규칙을 구현한다.
- `T079`: foreground 진입과 권한 변경 뒤 권한·일정·region·snapshot을 재평가하고 갱신 heading으로
  접근성 focus를 이동한다.
- `Localizable.xcstrings`에는 `permission_guide.*` 문자열을 추가한다.
- UI test identifier는 `permissionGuide.screen`, `permissionGuide.title`, `permissionGuide.permissionList`,
  `permissionGuide.next`, `permissionGuide.openSettings`, `permissionGuide.retryLocation`,
  `permissionGuide.confirm`, `permissionGuide.completeOnboarding`, `permissionGuide.requestFamilyControlsAuthorization`,
  `permissionGuide.requestLocationAuthorization`, `permissionGuide.requestAlwaysLocationAuthorization`을 사용한다.
- 설명용 목업은 `permissionGuide.mockup.familyControls`, `permissionGuide.mockup.locationPrompt`,
  `permissionGuide.mockup.locationAlwaysPrompt`, `permissionGuide.mockup.locationSettings`,
  `permissionGuide.mockup.backgroundRefresh`를 사용하고,
  위치 강조 문구는 `permissionGuide.location.alwaysInstruction`,
  `permissionGuide.location.accuracyInstruction`으로 검증한다.
- 위치 요청 목업의 추상 지도는 Figma export imageset을 사용하고 권한 목록 emoji는 같은 행의 text와
  함께 구현한다.

## 검토 체크리스트

- [x] 승인된 US4 로우파이와 관련 명세·contract를 참조했다.
- [x] 네 권한과 위치 `unavailable`의 비활성·활성 상태를 구분했다.
- [x] 오류별 hierarchy, icon, 문구, action과 접근성 규격을 정의했다.
- [x] GetUp Focus token, SF Pro style, layout과 Dynamic Type 대응을 기록했다.
- [x] 플랫폼 소유 UI, Background App Refresh와 시스템 우회 한계를 기록했다.
- [x] 실제 좌표·주소·앱 식별 정보와 token을 포함하지 않았다.
- [x] Figma 링크가 wrapper와 각 화면·handoff panel을 직접 가리킨다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-24` | 사용자 | `검토 대기` | T070 하이파이 초안 검토 요청 | `T071`에서 피드백과 구현 승인 여부 반영 |
| `2026-08-24` | 사용자 | `승인됨` | 사용자가 직접 수정한 현재 Figma를 구현 기준으로 승인 | `T071` 완료, T072~T074 선행 테스트 진행 가능 |
| `2026-08-25` | 사용자 | `승인됨` | `US4 / 권한 요청 클릭 유도 · 하이파이 제안 · 승인 대기` frame을 새 권한 요청 UI 구현 기준으로 승인 | `T095`에서 UI·상태 전환·테스트 반영 |

## 변경 기록

| 날짜 | 작성자 | 변경 내용 | 관련 검토 의견 |
|---|---|---|---|
| `2026-08-24` | `Codex` | 승인된 로우파이를 GetUp Focus text style·semantic token으로 정규화하고 권한별 icon badge, 상태 위계, 접근성·구현 인계 panel을 추가 | 최초 초안 |
| `2026-08-24` | 사용자 | 화면 우측 상단 badge를 제거하고 권한 점검 목록 emoji와 기존 문구·action 구조를 유지한 최종안을 확정 | 최종 승인 |
| `2026-08-25` | `Codex` | 실기기 검증에서 Family Controls가 앱별 Settings에 노출되지 않음을 확인해 `US4-HF-02`의 action을 `권한 허용하기`로 보정 | 실기기 결함 보고 |
| `2026-08-25` | 사용자·`Codex` | 권한 흐름을 `notDetermined`·허용·거부 세 묶음으로 확장하고, 자동 시스템 요청·활성 `다음`·설정 복구 상태를 구현 기준으로 반영 | 수정 하이파이 반영 요청 |
| `2026-08-25` | 사용자·`Codex` | 위치의 `앱을 사용하는 동안 허용` → `항상 허용` 순서를 명시하고, 앱별 Settings에 없는 Background App Refresh action과 foreground 자동 재등장을 제거 | 실기기 권한 복구 결함 보정 |
| `2026-08-25` | 사용자·`Codex` | 전체 권한 개요와 정상 승인 화면은 온보딩에만 유지하고, 이후에는 거부·요구 수준 미달 권한의 상세 복구 화면으로 직접 진입하도록 라우팅 분리 | 정상 권한 화면 재등장 제거 |
| `2026-08-25` | 사용자·`Codex` | 권한 온보딩을 설치 후 최초 실행 1회로 한정하고 표시 여부를 영구 저장해 앱 종료·재실행 뒤에는 복구 대상 화면만 표시 | 프로세스 재실행 시 온보딩 재등장 결함 보정 |
| `2026-08-25` | 사용자·`Codex` | 위치 권한 복구 화면의 `나중에`를 제거하고 Background App Refresh 제한 안내의 종료 문구를 `확인`으로 변경 | 권한 화면 행동 문구 보정 |
| `2026-08-25` | 사용자·`Codex` | 첨부 실기기 화면을 참고해 Family Controls·위치·Background App Refresh에 설명용 alert·Settings 목업을 추가하고 눌러야 할 항목과 Always·정확한 위치 문구를 accent로 강조 | 권한 복구 행동의 시각적 이해 보강 |
| `2026-08-25` | 사용자·`Codex` | 승인된 `204:2014` frame에 맞춰 Family Controls·위치 사용 중·Always alert 목업을 중앙 배치하고, 강조 버튼의 명시적 요청과 허용·거부 후 문맥별 전환을 구현 기준으로 확정 | 권한 요청 클릭 유도 하이파이 최종 승인 |
| `2026-08-25` | 사용자·`Codex` | 마지막 Background App Refresh 행동을 `시작하기`로 바꾸고, 이 행동에서만 완료를 저장해 중단 재실행은 온보딩을 반복하고 완료 재실행은 홈으로 진입하도록 확정 | 온보딩 완료 시점 보정 |
| `2026-08-27` | 사용자·`Codex` | `한 번만 허용` 뒤 무시되는 Always 요청과 callback 없는 미승격 결과를 bounded fallback으로 종료하고 Settings 수동 변경 안내로 전환 | 위치 온보딩 무한 대기 회귀 수정 |

## 구현 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `승인됨` |
| 승인자 | 사용자 |
| 승인일 | `2026-08-25` |
| 미해결 항목 | 없음 |

T095에서 승인된 `204:2014` frame과 T096의 마지막 `시작하기` 완료 계약을 기준으로 권한 요청 UI와 결과 전환을 구현한다. 제품 동작이나
화면 구조가 바뀌면 로우파이 또는 하이파이 검토를 다시 수행한다.
