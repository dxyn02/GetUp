# 제한 조건 설정 로우파이

## 기본 정보

| 항목 | 내용 |
|---|---|
| 사용자 스토리 | `US1` |
| 관련 task | `T021`, `T022` |
| 작성자 | `Codex` |
| 작성일 | `2026-08-21` |
| 문서 상태 | `승인됨` |
| 관련 명세 | [User Story 1 — 제한 조건 설정](../../specs/001-location-app-restriction/spec.md#user-story-1---제한-조건-설정-priority-p1) |
| 관련 contract | [location-picker-ui-contract.md](../../specs/001-location-app-restriction/contracts/location-picker-ui-contract.md) |
| Figma node | [US1 / 규칙 설정 흐름](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-4) |
| 후속 하이파이 | 작성 전 — 로우파이 승인 후 `T023`에서 작성 |

## 목표와 범위

### 해결할 사용자 문제

사용자가 제한 조건을 한 흐름에서 빠짐없이 구성하고, 저장 전에 시간·요일·위치·반경·제한 앱을
확인할 수 있게 한다. 유효한 여러 규칙과 재사용 가능한 저장 장소를 보존하고 다시 편집할 수 있는
상태가 성공 조건이다.

### 포함 범위

- 직접 설정 시간과 자정을 넘는 시간 범위, 15분 미만 DatePicker 선택 방지
- 요일, 500m·1km·2km·3km·4km·5km 반경, 저장 장소와 제한 앱 선택
- 지도 핀 선택과 현재 위치 바로가기, 현재 위치 권한 부족 안내
- 15분 미만 시간 오류, 저장 실패와 입력 보존·재시도
- 기존 여러 규칙의 불러오기와 수정, 저장 장소 재사용

### 제외 범위

- 실제 지도 타일, 실제 주소·좌표와 실제 선택 앱 정보
- 제한 활성 상태, shield, 자동 해제 및 권한 종합 안내 화면
- 색상·타이포그래피·간격의 최종 시각 규격과 SwiftUI 구현
- 시스템 `FamilyActivityPicker` 내부 UI의 재설계

## 사용자 흐름

1. 사용자가 규칙 편집 화면에서 시작·종료 시간을 직접 선택하고 선택적인 규칙 이름을 입력한다.
2. 요일을 선택하고 저장 장소·반경과 제한 앱 선택 흐름으로 이동한다.
3. 기준 위치는 지도 핀으로 확정하거나 현재 위치 바로가기를 사용한다. 현재 위치 권한이 없으면
   권한 안내를 확인하되 지도 핀 선택은 계속할 수 있다.
4. 시스템 `FamilyActivityPicker`에서 제한 앱을 선택하고 선택 개수만 규칙 편집 화면에서 확인한다.
5. 입력이 유효하면 저장한다. 저장 실패 시 입력을 유지한 채 재시도한다.
6. 저장된 규칙은 다음 진입 시 같은 값으로 열려 수정할 수 있고 장소는 다른 규칙에서 재사용한다.

## 화면 목록

| 화면 ID | 화면 이름 | 목적 | 진입 조건 | 주요 행동 |
|---|---|---|---|---|
| `LF-01` | 규칙 편집 · 직접 시간 | 기본 규칙 입력 구조와 직접 시간 확인 | 새 규칙 또는 저장된 규칙 진입 | 시간·요일·규칙 이름·저장 장소·반경·앱 선택, 저장 |
| `LF-02` | 사용자 지정 · 자정 초과 | 자정을 넘는 직접 시간 설정 확인 | 사용자 지정 선택 | 시작·종료 시간 변경, 저장 |
| `LF-03` | 종료 DatePicker · 15분 제한 | 15분 미만 종료 시각의 선택 방지 | 종료 시각 선택 | 유효한 종료 시각 선택 |
| `LF-04` | 장소 설정 · 지도 핀 | 지도 중심의 핀과 장소 이름을 저장 | 장소와 반경 행 선택 | 지도 이동, 장소 선택·입력, 위치 확인 |
| `LF-05` | 현재 위치 · 권한 안내 | 현재 위치 권한 부족과 대안 안내 | 권한 없이 현재 위치 선택 | 권한 안내 확인, 지도 핀 선택 지속 |
| `LF-06` | 제한 앱 선택 | 시스템 선택기에서 제한 대상 선택 | 제한 앱 행 선택 | 앱 선택·해제, 완료 |
| `LF-07` | 저장 실패 · 재시도 | 저장 실패 후 입력 보존과 복구 | 저장 처리 실패 | 다시 저장 |

## 화면 상태

| 화면 ID | 상태 | 발생 조건 | 표시 내용 | 가능한 행동 | 다음 결과 |
|---|---|---|---|---|---|
| `LF-01` | `기본` | 유효한 새 규칙 또는 기존 규칙 | 전체 입력값과 저장 행동 | 각 값 변경, 하위 선택 진입, 저장 | 저장 성공 또는 `LF-07` |
| `LF-02` | `자정 초과` | 종료 시간이 시작 시간보다 이른 사용자 지정 범위 | `23:00 ~ 06:00` 형태와 다음 날 종료 의미 | 시간 변경, 저장 | 유효성 재평가 |
| `LF-03` | `disabled` | 종료 시각이 시작 시각과 같거나 15분 미만 | 선택 불가능한 종료 시각과 최초 선택 가능 시각 | 유효한 시간 선택 | DatePicker 값 반영 |
| `LF-04` | `기본` | 지도 핀 방식으로 위치 선택 | 지도 중심 핀과 현재 위치 행동 | 지도 이동, 현재 위치, 확인 | 편집 화면에 위치 반영 |
| `LF-05` | `권한 부족` | 현재 위치 조회 권한이 없음 | 필요한 권한과 지도 핀 대안 | 권한 안내, 지도 핀으로 계속 | 설정 안내 또는 위치 확정 |
| `LF-06` | `시스템 선택` | `FamilyActivityPicker` 표시 | 일반화된 선택 항목과 선택 개수 | 선택·해제, 완료 | 편집 화면에 개수 반영 |
| `LF-07` | `오류` | 규칙 저장 실패 | 저장되지 않았다는 문구와 재시도 행동 | 다시 저장, 입력 수정 | 성공 시 완료 또는 오류 유지 |

## 와이어프레임

- 전체 흐름: [US1 / 규칙 설정 흐름](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-4)
- `LF-01`: [규칙 편집 · 직접 시간](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-5)
- `LF-02`: [사용자 지정 · 자정 초과](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-6)
- `LF-03`: [시간 검증 오류](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-7)
- `LF-04`: [기준 위치 · 지도 핀](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-8)
- `LF-05`: [현재 위치 · 권한 안내](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-9)
- `LF-06`: [제한 앱 선택](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-10)
- `LF-07`: [저장 실패 · 재시도](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=3-11)
- 구성 기준: iPhone 393×852 frame, Apple `iOS and iPadOS 26` 공식 Figma library component

## 상호작용과 검증 규칙

- 시간 프리셋은 제공하지 않고 시작·종료 시각을 DatePicker로 직접 설정한다.
- 사용자 지정 시간은 자정을 넘을 수 있으며 시작 요일의 다음 날 종료로 해석한다.
- 시작과 종료가 같거나 총 길이가 15분 미만이면 저장할 수 없다.
- 요일은 최소 1개를 선택해야 한다.
- 반경 slider는 `500m`, `1km`, `2km`, `3km`, `4km`, `5km`의 여섯 단계에 snap한다.
- 장소 이름과 좌표는 저장 장소로 보존해 다른 규칙에서 재사용하며 규칙 이름과 분리한다.
- 기준 위치는 지도 중심 핀 또는 현재 위치 바로가기로 정한다. 현재 위치 권한이 없어도 지도 핀
  선택은 차단하지 않는다.
- 제한 앱은 시스템 `FamilyActivityPicker`에서 최소 1개를 선택해야 한다. 로우파이와 제품 UI는
  opaque token을 해석하거나 임의의 앱 식별자로 대체하지 않는다.
- 저장 실패 시 현재 draft를 폐기하지 않고 오류를 표시하며 같은 값으로 재시도할 수 있다.
- 저장된 규칙은 편집할 수 있으며 새 규칙은 기존 규칙을 교체하지 않고 별도로 추가한다.

## 접근성 가설

- VoiceOver 읽기 순서: 화면 제목 → 시간 방식 → 시간 값 → 요일 → 기준 위치 → 반경 → 제한 앱 →
  오류 또는 저장 행동 순으로 묶는다.
- accessibility label·hint: 뒤로가기, 현재 위치, 지도 핀, 선택 개수와 segmented control에 목적과
  선택 결과를 함께 제공한다.
- Dynamic Type: 큰 글자 크기에서는 행 높이를 고정하지 않고 세로 scroll을 허용하며 label과 값이
  겹치면 두 줄로 재배치한다.
- 색상 외 상태 표현: 오류 문구와 저장 버튼의 활성 상태를 함께 사용하고 색상만으로 오류를
  전달하지 않는다.
- focus 이동: validation 실패 시 첫 오류 문구로, 하위 화면 복귀 시 해당 진입 행으로 focus를
  이동한다.
- touch target: 요일·segmented control·지도 행동을 최소 44×44pt 영역으로 제공한다.
- Reduce Motion: 화면 전환과 오류 표현은 필수 정보를 animation에 의존하지 않으며 기본 전환을
  줄여도 같은 상태를 전달한다.

## 검토 체크리스트

- [x] 관련 `spec.md`의 성공 조건과 예외 흐름을 반영했다.
- [x] 필요한 화면과 상태가 모두 연결된다.
- [x] 오류·권한 부족·위치 불확실 상태에서 잘못된 다음 행동을 유도하지 않는다.
- [x] 접근성 가설과 검증할 위험을 기록했다.
- [x] 실제 좌표나 app token 같은 민감 정보를 포함하지 않았다.
- [x] Figma 링크가 검토 대상 node를 직접 가리킨다.

## 검토 기록

| 날짜 | 검토자 | 결과 | 의견 | 반영 위치 또는 사유 |
|---|---|---|---|---|
| `2026-08-21` | 사용자 | `검토 대기` | 로우파이 초안 검토 요청 | `T022`에서 피드백과 승인 여부 반영 |
| `2026-08-23` | 사용자 | `수정 요청` | 직접 제작한 D안은 유지하고 별도의 보완안에 피드백 반영 요청 | `D안 보완`에 오늘·다음날 구분, 행동·해제 조건, 앱 요약, 수정 진입점을 추가함 |
| `2026-08-23` | 사용자 | `수정 요청` | 반경 6단계, 저장 장소 재사용, 직접 시간, 작은 AM/PM, DatePicker 15분 제한, 규칙 이름 반영 요청 | D안 home·규칙 설정·장소 설정·DatePicker 상태와 관련 제품 문서에 반영함 |
| `2026-08-23` | 사용자 | `승인` | 사용자가 직접 수정해 `D 보완` frame에 정리한 안으로 로우파이 확정 | `D 보완`을 US1 구현 기준 로우파이로 승인하고 `T022`를 완료함 |

## 변경 기록

| 날짜 | 작성자 | 변경 내용 | 관련 검토 의견 |
|---|---|---|---|
| `2026-08-21` | `Codex` | US1 규칙 설정 흐름 7개 화면의 최초 로우파이 작성 | 초안 검토 요청 |
| `2026-08-23` | 사용자·`Codex` | 사용자 D안을 원본으로 보존하고 onboarding·빈 home·오늘 규칙·다음날 규칙으로 구성한 `D안 보완` 작성 | D안 보완 요청 및 이전 검토 피드백 |
| `2026-08-23` | 사용자·`Codex` | D안 home의 12시간 표기, 규칙 직접 시간, 저장 장소, 여섯 단계 반경 slider, 15분 제한 DatePicker 및 `규칙 이름` 용어를 반영함 | 최신 D안 규칙 설정 피드백 |

## 로우파이 승인

| 항목 | 내용 |
|---|---|
| 승인 상태 | `승인됨` |
| 승인자 | 사용자 |
| 승인일 | `2026-08-23` |
| 미해결 항목 | 없음 |

승인된 기준은 사용자가 최종 수정해 Figma의 `D 보완` frame에 정리한 로우파이다. 후속 하이파이
작업은 사용자의 별도 시작 지시가 있을 때 진행한다.

## 앱 컨셉·onboarding·home 확장 후보

다중 규칙과 home 요구사항이 추가되어 `T022` 검토 범위를 onboarding과 home 컨셉까지 확장했다.
리서치와 선택 기준은 [alarm-focus-app-concept.md](../research/alarm-focus-app-concept.md)에 기록한다.

- 전체 비교: [앱 컨셉 / Onboarding + Home 후보](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-340)
- A — 침대에서 문까지: [onboarding](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-343), [home](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-344)
- B — 문턱: [onboarding](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-347), [home](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-348)
- C — 출발 티켓: [onboarding](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-351), [home](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-352)
- D — 사용자 제작안: [전체 흐름](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=15-346)
- D안 보완 — 행동 명확화: [전체 비교](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=29-911), [onboarding](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=29-913), [규칙 없음](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=29-921), [오늘 규칙](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=29-932), [다음날 규칙](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=29-951)
- D — 규칙 설정: [기본](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=25-1194), [설정 완료](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=27-2849), [장소 설정](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=27-3012), [위치 권한 안내](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=27-5846), [장소 직접 입력](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=27-4048), [15분 제한 DatePicker](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=40-863)

`D안 보완`은 기존 D안을 변경하지 않고 별도 비교 영역으로 작성했다. 이전 피드백에 따라 오늘 또는
다음날 맥락, 위치 범위를 벗어났을 때의 앱 사용 가능 조건, 시간·위치에 따른 해제 조건, 제한 앱
개수와 확인 진입점, 카드 수정 진입점을 명시했다. 이후 사용자가 직접 수정해 `D 보완` frame에
옮긴 안을 최종 로우파이로 승인했다.
