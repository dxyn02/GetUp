# 제한 활성 상태와 Restricted App Shield 로우파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US2` |
| 관련 task | `T038`, `T039` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-24` |
| 문서 상태 | `승인됨` |
| 관련 명세 | [User Story 2 — 조건 충족 시 선택 앱 제한](../../specs/001-location-app-restriction/spec.md#user-story-2---조건-충족-시-선택-앱-제한-priority-p1) |
| 관련 contract | [shield-ui-contract.md](../../specs/001-location-app-restriction/contracts/shield-ui-contract.md) |
| Figma node | [US2 / 제한 활성 상태와 Restricted App Shield](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=101-1959) |
| 후속 하이파이 | 로우파이 승인 후 `T040`에서 작성 |

## 목표와 범위

### 해결할 사용자 문제

사용자가 GetUp 앱에서 제한이 활성화된 이유와 자동 해제 조건을 이해하고, 제한 대상 앱을 열었을
때 표시되는 시스템 shield에서 우회 없이 앱을 닫을 수 있게 한다.

### 포함 범위

- 시간과 신뢰 가능한 내부 위치 조건이 모두 충족된 제한 활성 상태
- 기존 홈 카드에 표시하는 제한 중인 앱 개수와 시간·위치 자동 해제 조건
- restricted-app shield의 정적 GetUp 아이콘, 제목, 설명과 단일 `앱 닫기` 행동
- 조건 충족부터 제한 앱 종료까지의 닫기 흐름
- VoiceOver 읽기 순서와 색상 외 상태 전달 가설

### 제외 범위

- 실제 `FamilyActivitySelection` token, 앱 이름, bundle identifier, 좌표와 주소
- 제한 해제, 규칙 변경, GetUp 앱 자동 실행 또는 우회 허용 행동
- 비대상 앱 화면과 실제 `ManagedSettingsStore` 적용
- 최종 색상·명암·Dynamic Type 규격과 SwiftUI·ManagedSettingsUI 구현
- shield 내부 지도 UI와 secondary action
- `오늘만 허용` 및 인앱결제를 통한 일시 해제. 후속 기능에서 별도 명세와 정책 검토가 필요하다.

## 사용자 흐름

1. 선택 요일의 시간대와 신뢰 가능한 내부 위치가 모두 충족되면 기존 GetUp 홈 카드가 제한 활성 상태로 바뀐다.
2. 홈 카드는 제한 중인 앱 개수와 `집 · 1km`, `09:00 AM` 같은 자동 해제 조건을 안내한다.
3. 사용자가 제한 대상으로 선택한 앱을 열려고 하면 GetUp shield가 표시된다.
4. shield는 정적 GetUp 아이콘, `집 1km 밖으로 이동하세요` 제목, 저장 장소 중심·반경·종료 시각 설명과
   `앱 닫기` 버튼만 제공한다.
5. 사용자가 `앱 닫기`를 선택하면 제한 앱을 닫고 사용 권한이나 일시적 우회를 부여하지 않는다.
6. 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 제한이 제거되면 같은 앱을 정상적으로 열 수 있다.

## 화면 목록

| 화면 ID | 화면 이름 | 목적 | 진입 조건 | 주요 행동 |
|---|---|---|---|---|
| `US2-LF-01` | 기존 홈의 제한 활성 상태 | 별도 화면 없이 제한 이유와 자동 해제 조건 이해 | 시간 활성 + 신뢰 가능한 내부 위치 + 필수 권한 유효 | 상태 확인; 조건 종료 전 규칙 수정 차단 |
| `US2-LF-02` | Restricted App Shield | 제한 앱 접근을 막고 종료 이유 안내 | 제한 적용 중 대상 앱 열기 시도 | `앱 닫기` |

## 화면 상태

| 화면 ID | 상태 | 표시 내용 | 금지 행동 | 다음 결과 |
|---|---|---|---|---|
| `US2-LF-01` | `active` | 기존 홈 카드의 `RESTRICTION ACTIVE`, `집 · 1km`, 종료 시각, 제한 앱 개수 | 즉시 해제, 조건 종료 전 규칙 변경·삭제 | 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 제한 제거 |
| `US2-LF-02` | `shielded` | 정적 GetUp 아이콘, `집 1km 밖으로 이동하세요`, `집` 중심에서 `1km` 밖 또는 `09:00 AM` 자동 해제 설명, `앱 닫기` | secondary action, 우회 허용, 규칙 변경, GetUp 자동 실행 약속 | 제한 앱 종료 |

## 와이어프레임

- 전체 보드: [T039 피드백 반영본](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=101-1959)
- 닫기 흐름: [조건 충족 → 앱 닫기](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=101-1961)
- `US2-LF-01`: [기존 홈의 제한 활성 상태](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=109-1966)
- `US2-LF-02`: [Restricted App Shield](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=102-1973)
- 상태·계약 설명: [로우파이 상태 설명](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=102-1974)
- 기준 frame: iPhone `393×852pt`

## 상호작용과 검증 규칙

- 새 제한은 시간과 신뢰 가능한 내부 위치 조건이 모두 참이고 필수 권한이 유효할 때만 활성화한다.
- 활성 상태는 제한 중인 앱 개수와 사용자가 이해할 수 있는 자동 해제 조건을 함께 표시한다.
- `US2-LF-01`은 별도 화면을 만들지 않고 기존 홈 카드의 활성 상태로 통합한다.
- shield 설명은 실제 좌표나 주소 대신 사용자가 저장한 장소 이름, 설정 반경과 종료 시각을 표시한다.
- `ShieldConfiguration`에는 임의의 지도 UI를 삽입할 수 없으므로 shield 내부 지도는 제공하지 않는다.
- shield는 앱 이름이나 bundle identifier를 GetUp이 직접 해석하거나 표시하지 않는다.
- shield의 primary action은 `앱 닫기` 하나이며 secondary action은 제공하지 않는다.
- `앱 닫기`는 제한 앱을 닫을 뿐 사용 권한이나 일시적 우회를 부여하지 않는다.
- 제한 해제나 규칙 변경 버튼을 shield에 제공하지 않고 GetUp 앱 자동 실행을 약속하지 않는다.
- 비대상 앱은 GetUp shield의 적용 범위에 포함하지 않는다.
- 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 shield가 제거되어야 한다.

## 접근성 가설

- 제한 활성 화면의 VoiceOver 순서는 상태 → 제목 → 이유 → 제한 앱 개수 → 자동 해제 조건이다.
- shield의 VoiceOver 순서는 정적 아이콘 → 제목 → 설명 → `앱 닫기` 버튼이다.
- 활성 상태는 `ACTIVE` 문구, 제목과 설명을 함께 사용해 색상만으로 전달하지 않는다.
- 제목·설명은 Dynamic Type 확대에서 자연스럽게 줄바꿈하며 중요 문구가 축약되지 않아야 한다.
- `앱 닫기` 버튼은 최소 `44×44pt` touch target과 구체적인 accessibility label을 제공해야 한다.
- Reduce Motion 상태에서도 제한 이유와 닫기 행동은 animation 없이 동일하게 이해할 수 있어야 한다.

## 검토 체크리스트

- [x] US2의 시간·위치 AND 조건과 대상 앱 shield 흐름을 반영했다.
- [x] `shield-ui-contract.md`의 아이콘·제목·설명·단일 버튼 요구사항을 반영했다.
- [x] 제한 해제·규칙 변경·우회 허용과 secondary action을 제공하지 않는다.
- [x] 앱 이름·bundle identifier·좌표·앱 token 같은 민감 정보를 포함하지 않았다.
- [x] VoiceOver 읽기 순서와 색상 외 상태 표현 가설을 기록했다.
- [x] LF-01을 기존 홈의 활성 상태로 통합했다.
- [x] LF-02에 저장 장소 이름·설정 반경·종료 시각을 직접 안내한다.
- [x] Figma 링크가 전체 보드와 두 화면 node를 직접 가리킨다.
- [x] MVP에서 지도 진입을 포함한 secondary action을 제공하지 않기로 결정했다. (`BLK-007`)

## 자동 감사 결과

2026-08-24 피드백 반영 뒤 Figma wrapper와 두 화면을 다시 렌더링해 검수했다. LF-01 21개 text
node와 LF-02 5개 text node에서 누락 font, 빈 text, 임시 placeholder와 육안상 화면 경계 overflow가
모두 0건이었다. LF-02의 행동 instance는 `Primary Action · 앱 닫기` 하나만 존재한다.

이 task는 디자인·문서 작업이므로 code test는 실행하지 않았다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-24` | 사용자 | `검토 대기` | T038 로우파이 초안 검토 요청 | `T039`에서 피드백과 승인 여부 반영 |
| `2026-08-24` | 사용자 | `수정 요청·부분 반영` | LF-01은 홈으로 대체하고, LF-02에서 벗어날 위치·거리를 문구 또는 지도로 확인하고 싶음 | LF-01을 기존 홈 활성 상태로 교체하고 LF-02에 `집`·`1km`·`09:00 AM`을 직접 표시함. 지도 진입은 `BLK-007` 결정 대기 |
| `2026-08-24` | 사용자 | `승인` | MVP는 앱을 여는 secondary 버튼 없이 구현함. 향후 `오늘만 허용`과 인앱결제를 통한 해제를 검토함 | 현재 로우파이의 단일 `앱 닫기` 행동을 확정함. 향후 아이디어는 현재 범위에서 제외 |

## 로우파이 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `승인됨` |
| 승인자 | 사용자 |
| 승인일 | `2026-08-24` |
| 미해결 항목 | 없음 |
