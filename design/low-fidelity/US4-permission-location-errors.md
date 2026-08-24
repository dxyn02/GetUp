# 권한 및 위치 문제 안내 로우파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US4` |
| 관련 task | `T068`, `T069` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-24` |
| 문서 상태 | `검토 대기` |
| 관련 명세 | [User Story 4 — 권한 및 위치 문제 안내](../../specs/001-location-app-restriction/spec.md#user-story-4---권한-및-위치-문제-안내-priority-p2) |
| 관련 contract | [restriction-evaluation-contract.md](../../specs/001-location-app-restriction/contracts/restriction-evaluation-contract.md), [platform-events-contract.md](../../specs/001-location-app-restriction/contracts/platform-events-contract.md) |
| Figma node | [US4 / 권한 + 위치 오류 복구](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2014) |
| 후속 하이파이 | 로우파이 승인 후 `T070`에서 작성 |

## 목표와 범위

### 해결할 사용자 문제

필수 권한이나 위치 근거가 부족할 때 사용자가 자동 제한이 동작하지 않는 원인을 이해하고, 잘못된
위치 추정이나 제한 상태 변경 없이 필요한 설정을 복구할 수 있게 한다.

### 포함 범위

- Family Controls, Always location, Full Accuracy, Background App Refresh 상태별 원인과 복구 행동
- Family Controls 재승인 뒤 제한 앱 재선택이 필요한 흐름
- 시스템 설정 이동과 GetUp foreground 복귀 뒤 재평가 흐름
- 위치 확인 불가에서 비활성 제한을 새로 적용하지 않는 상태
- 위치 확인 불가에서 기존 활성 shield를 보존하되 시간 종료는 적용하는 상태
- VoiceOver, Dynamic Type, 색상 외 상태 표현과 focus 복귀 가설

### 제외 범위

- 실제 시스템 설정 화면과 OS 권한 prompt의 재현
- 실제 좌표·주소·앱 이름·bundle identifier·`FamilyActivitySelection` token
- 최종 icon, 색상 대비, AX5 layout과 SwiftUI 구현 규격
- 권한을 강제로 유지하거나 시스템 설정의 권한 철회를 차단하는 동작
- Background App Refresh가 항상 특정 시각에 실행된다는 보장

## 사용자 흐름

1. 사용자가 규칙 설정 또는 상태 확인 중 필수 권한 부족을 발견한다.
2. `US4-LF-01`은 누락된 권한 종류와 자동 제한에 미치는 영향을 한 목록에서 보여준다.
3. Family Controls가 없으면 `US4-LF-02`에서 개인용 앱 사용 제한을 다시 승인하고 제한 앱을 다시
   선택한 뒤 저장 규칙을 재평가한다.
4. Always 또는 Full Accuracy가 없으면 `US4-LF-03`에서 시스템 설정 경로와 상태 보존 원칙을 확인하고
   설정으로 이동한다.
5. Background App Refresh가 제한되면 `US4-LF-04`에서 복구 지연 가능성과 설정 경로를 확인한다.
6. 사용자가 GetUp으로 돌아오면 권한·일정·region·위치 snapshot을 다시 평가해 안내 상태를 갱신한다.
7. 신뢰 가능한 위치가 없고 제한이 비활성이면 `US4-LF-05`에서 새 제한을 적용하지 않는다.
8. 신뢰 가능한 위치가 없고 제한이 활성이면 `US4-LF-06`에서 기존 shield를 보존한다. 단, 시간 종료는
   위치와 무관하게 제한을 해제한다.

## 화면 목록

| 화면 ID | 화면 이름 | 목적 | 진입 조건 | 주요 행동 |
|---|---|---|---|---|
| `US4-LF-01` | 권한 점검 | 누락 권한과 복구 순서 이해 | 하나 이상의 필수 권한 부족 | 가장 먼저 복구할 항목 선택 |
| `US4-LF-02` | Family Controls 복구 | 재승인과 앱 재선택 요구 이해 | Family Controls 미승인·철회 | 다시 승인하고 앱 선택 |
| `US4-LF-03` | 위치 권한 복구 | Always·Full Accuracy 설정 복구 | Always 또는 Full Accuracy 부족 | 설정 열기, 나중에 |
| `US4-LF-04` | Background App Refresh | background 복구 제한 원인 이해 | Background App Refresh 제한 | 설정 열기, 나중에 |
| `US4-LF-05` | 위치 확인 불가 · 비활성 | 잘못된 신규 제한을 막고 현재 상태 설명 | 제한 비활성 + 위치 `unavailable` | 위치 다시 확인, 설정 열기 |
| `US4-LF-06` | 위치 확인 불가 · 활성 | 기존 shield 보존과 시간 종료 우선 설명 | 제한 활성 + 위치 `unavailable` | 위치 다시 확인, 설정 열기 |

## 화면 상태

| 화면 ID | 상태 | 표시 내용 | 가능한 행동 | 다음 결과 |
|---|---|---|---|---|
| `US4-LF-01` | `permission required` | 권한 네 종류와 자동 제한 영향 | 첫 복구 항목 선택 | 해당 상세 화면 |
| `US4-LF-02` | `family controls denied` | 재승인 → 앱 재선택 → 규칙 재평가 | 승인과 앱 선택 | foreground 재평가 |
| `US4-LF-03` | `always/full accuracy denied` | 시스템 설정 경로, Reduced Accuracy 안전 원칙 | 설정 열기, 나중에 | foreground 재평가 또는 상태 유지 |
| `US4-LF-04` | `background refresh restricted` | 복구 지연 가능성, 저전력 모드의 시스템 제한 | 설정 열기, 나중에 | foreground 재평가 또는 상태 유지 |
| `US4-LF-05` | `location unavailable / inactive` | 새 제한 미적용, 원인 점검 항목 | 재시도, 설정 열기 | 신뢰 가능한 fix에서 재평가 |
| `US4-LF-06` | `location unavailable / active` | shield 유지, 위치만으로 해제하지 않음, 시간 종료 우선 | 재시도, 설정 열기 | 위치 회복 또는 시간 종료 |

## 와이어프레임

- 전체 보드: [T068 로우파이](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2014)
- `US4-LF-01`: [권한 점검](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2019)
- `US4-LF-02`: [Family Controls 복구](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2020)
- `US4-LF-03`: [위치 권한 복구](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2021)
- `US4-LF-04`: [Background App Refresh](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2022)
- `US4-LF-05`: [위치 확인 불가 · 비활성](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2023)
- `US4-LF-06`: [위치 확인 불가 · 활성](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=159-2024)
- 상태·계약·접근성: [검토 panel](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=166-2014)
- 기준 frame: iPhone `393×852pt`

## 상호작용과 검증 규칙

- Family Controls, Always location, Full Accuracy 중 하나라도 부족하면 새로운 제한을 적용하지 않는다.
- Family Controls 재승인 뒤 이전 opaque token이 유효하다고 가정하지 않고 제한 앱 재선택을 요구한다.
- `설정 열기`는 시스템 설정으로 이동하며, 복귀 시 최신 권한 상태를 다시 읽는다.
- Background App Refresh 제한은 복구 지연 가능성을 설명하되 특정 실행 시각을 보장하지 않는다.
- 위치 오류, 오래된 fix, 음수 accuracy, Reduced Accuracy, 반경 경계와 오차 범위 중첩은
  `unavailable`로 표시한다.
- 위치 `unavailable`에서는 좌표를 추정하지 않고 위치만을 근거로 제한 상태를 변경하지 않는다.
- 비활성 상태의 위치 `unavailable`은 새 shield를 적용하지 않는다.
- 활성 상태의 위치 `unavailable`은 기존 shield를 보존한다.
- 시간 종료는 위치 상태와 무관하게 활성 제한을 해제한다.
- 위치가 다시 신뢰 가능해지면 내부·외부 판정과 현재 시간 조건을 함께 재평가한다.

## 접근성 가설

- VoiceOver 순서는 상태 → 원인 → 현재 제한 영향 → 복구 행동이다.
- 권한 부족과 위치 확인 불가는 색상뿐 아니라 eyebrow, 제목, 현재 상태 문구로 구분한다.
- Dynamic Type AX5에서는 제목·본문을 축약하지 않고 자연스럽게 줄바꿈하며 화면 전체를 세로 scroll한다.
- 모든 복구 버튼은 최소 `44×44pt` touch target을 유지한다.
- 시스템 설정이나 Family Controls picker에서 돌아오면 갱신된 상태 heading으로 focus를 이동한다.
- `나중에`를 선택하면 현재 상태를 바꾸지 않고 이전 화면으로 돌아간다.
- Reduce Motion에서도 상태 전환 의미를 animation에 의존하지 않는다.

## 검토 체크리스트

- [x] 권한 네 종류의 원인과 복구 행동을 반영했다.
- [x] Family Controls 재승인 뒤 앱 재선택 흐름을 포함했다.
- [x] 시스템 설정 이동과 foreground 복귀 뒤 재평가를 연결했다.
- [x] 위치 `unavailable`의 비활성·활성 상태 보존 차이를 구분했다.
- [x] 위치 확인 불가 중에도 시간 종료가 우선함을 표시했다.
- [x] 실제 좌표·앱 token 같은 민감 정보를 포함하지 않았다.
- [x] VoiceOver, Dynamic Type, 색상 외 상태, focus와 touch target 가설을 기록했다.
- [x] Figma 링크가 wrapper와 각 검토 frame을 직접 가리킨다.

## 자동 감사 결과

2026-08-24 Figma wrapper와 여섯 화면을 렌더링하고 text node 52개를 검사했다. SF Pro 외 서체,
빈 text, placeholder, shimmer와 각 393×852pt 화면 경계 밖 text overflow가 모두 0건이었다. 색상,
간격과 반경은 기존 `GetUp Focus` local variable을 재사용했다.

이 task는 디자인·문서 작업이므로 code test는 실행하지 않았다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-24` | 사용자 | `검토 대기` | T068 로우파이 초안 검토 요청 | `T069`에서 피드백과 승인 여부 반영 |

## 변경 기록

| 날짜 | 작성자 | 변경 내용 | 관련 검토 의견 |
|---|---|---|---|
| `2026-08-24` | `Codex` | 권한 점검, Family Controls 재승인·앱 재선택, Always·Full Accuracy, Background App Refresh, 위치 확인 불가의 비활성·활성 상태를 하나의 검토 wrapper로 제작 | 최초 작성 |

## 로우파이 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `검토 대기` |
| 승인자 | 미승인 |
| 승인일 | 미승인 |
| 미해결 항목 | T069 사용자 검토와 승인 |

승인 상태가 `승인됨`이 되기 전에는 T070 하이파이와 US4 UI 구현을 시작하지 않는다.
