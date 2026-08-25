# Data Model: 시간·위치 기반 앱 사용 제한

## Design Goals

- 사용자 기기 안에서 여러 제한 규칙과 재사용 가능한 저장 장소를 저장한다.
- 앱과 확장이 동일한 규칙 및 최근 위치 판정을 읽는다.
- 시간·위치·권한 판정을 순수 입력과 출력으로 표현해 결정론적으로 테스트한다.
- 위치 좌표와 앱 선택 토큰을 서버로 전송하거나 사람이 해석할 수 있는 식별자로 변환하지 않는다.

## Core Entities

### RestrictionRuleSnapshot

저장 가능한 독립 규칙 aggregate다.

| Field | Type | Rules |
|-------|------|-------|
| `schemaVersion` | Positive integer | 현재 스키마 버전과 일치해야 한다. |
| `revision` | Monotonic integer | 규칙을 저장할 때마다 증가한다. |
| `id` | Stable identifier | 규칙 collection 안에서 고유해야 한다. |
| `name` | Optional string | 사용자가 지정한 규칙 이름이며 장소 이름과 분리한다. |
| `isEnabled` | Boolean | 비활성 규칙은 일정과 위치 모니터링을 중단한다. |
| `weekdays` | Set of `Weekday` | 1개 이상, 최대 7개다. |
| `startTime` | `TimeOfDay` | 현지 시각 기준이다. |
| `endTime` | `TimeOfDay` | 시작과 같을 수 없다. |
| `savedPlaceID` | Stable identifier | 존재하는 `SavedPlaceSnapshot`을 참조해야 한다. |
| `radius` | `RadiusOption` | `500m`, `1km`, `2km`, `3km`, `4km`, `5km` 중 하나다. |
| `activitySelection` | Opaque codable selection | 앱 토큰이 1개 이상이어야 한다. |
| `createdAt` | Timestamp | 최초 생성 시각이다. |
| `updatedAt` | Timestamp | 마지막 저장 시각이며 `createdAt`보다 빠를 수 없다. |

#### Aggregate validation

- 현지 달력에서 계산한 시작부터 종료까지의 반복 구간은 15분 이상, 12시간 이하여야 한다.
- 종료 시각이 시작 시각보다 이르면 다음 날 종료로 계산한다.
- 자정 초과 구간은 시작 시각의 `Weekday`에 귀속된다.
- DST 전환으로 시작·종료 현지 시각이 존재하지 않으면 다음 유효 시각을 경계로 사용한다. 같은
  현지 시각이 반복되면 시작은 첫 번째 발생, 종료는 두 번째 발생을 사용하며 구간은 시작 포함·종료
  미포함이다.
- `isEnabled == true`인 규칙은 요일, 위치, 반경, 앱 선택이 모두 유효해야 한다.
- MVP 저장소에는 이 aggregate가 0개 이상 존재할 수 있다.
- 활성 제한 중에는 aggregate를 수정하거나 삭제할 수 없다.

### Weekday

월요일부터 일요일까지의 안정적인 도메인 값이다. 화면 표시 순서와 `Calendar`의 숫자 표현을
도메인 모델에서 분리하고, 일정 adapter에서 현지 달력 값으로 변환한다.

### TimeOfDay

| Field | Type | Rules |
|-------|------|-------|
| `hour` | Integer | 0...23 |
| `minute` | Integer | 0...59 |

초와 시간대는 저장하지 않는다. 평가 시점의 기기 현지 `Calendar`와 `TimeZone`을 명시적으로
주입한다.

### SavedPlaceSnapshot

| Field | Type | Rules |
|-------|------|-------|
| `id` | Stable identifier | 저장 장소 collection 안에서 고유해야 한다. |
| `name` | 1...10 characters | 앞뒤 공백을 제거한 사용자 지정 이름이다. |
| `latitude` | Decimal degrees | -90...90 |
| `longitude` | Decimal degrees | -180...180 |
| `createdAt` | Timestamp | 최초 생성 시각이다. |
| `updatedAt` | Timestamp | 마지막 저장 시각이다. |

주소 문자열은 핵심 판정 데이터가 아니다. 표시용 장소 이름을 추가하더라도 좌표와 분리하고,
판정은 좌표만 사용한다.

저장 장소 collection의 이름은 앞뒤 공백을 제거하고 대소문자를 구분하지 않은 key가 고유해야 한다.
`집`과 `회사`는 별도 타입이 아니라 항상 노출되는 UI 프리셋이며, 최초 적용 시 현재 지도 핀 좌표와
각 이름으로 일반 `SavedPlaceSnapshot`을 만든다.

### RadiusOption

허용 값이 `meters500`, `meters1000`, `meters2000`, `meters3000`, `meters4000`, `meters5000`인
닫힌 집합이다. slider는 이 여섯 단계에 snap하며 임의 반경 입력은 지원하지 않는다.

### LocationConditionSnapshot

메인 앱의 위치 adapter가 쓰고 앱 및 시간 확장이 읽는 최근 위치 판정이다.

| Field | Type | Rules |
|-------|------|-------|
| `ruleID` | Stable identifier | 판정 대상 규칙을 고유하게 식별해야 한다. |
| `ruleRevision` | Integer | 판정에 사용한 규칙 revision과 일치해야 한다. |
| `state` | `inside`, `outside`, `unavailable` | 경계 중첩은 `unavailable`이다. |
| `observedAt` | Timestamp | 근거가 확인된 시각이다. |
| `distanceMeters` | Optional decimal | 기준 위치까지 계산 거리다. |
| `horizontalAccuracyMeters` | Optional decimal | 음수이면 무효다. |
| `source` | `freshFix`, `regionEvent`, `restoration` | 판정 출처다. |

새 규칙 revision, 재부팅 후 첫 잠금 해제, 권한 변경 또는 손상된 파일을 만나면 `unavailable`로
초기화한다. 직접 위치 fix는 최신성 검사를 통과해야 하며, 오래된 fix는 `unavailable`이다.

`LocationConditionCollectionSnapshot`은 rule ID별 최신 판정을 하나씩 보존하는 schema 2
collection이다. rule ID가 없는 기존 schema 1 단일 snapshot은 특정 규칙에 안전하게 귀속할 수
없으므로 빈 collection으로 migration하고 새 근거가 기록될 때까지 `unavailable`로 평가한다.

#### Accuracy classification

중심 거리 `d`, 반경 `R`, 정확도 반경 `a`에 대해 다음 순서로 판정한다.

1. `a < 0` 또는 위치 오류면 `unavailable`.
2. `d + a <= R`이면 `inside`.
3. `max(0, d - a) > R`이면 `outside`.
4. 나머지는 오차 원이 경계와 겹치므로 `unavailable`.

### AuthorizationSnapshot

현재 실행 시점에 합성하는 값이며 장기 저장의 권위 있는 근거로 사용하지 않는다.

| Field | Values |
|-------|--------|
| `familyControls` | `approved`, `denied`, `notDetermined` |
| `locationAuthorization` | `always`, `whenInUse`, `denied`, `restricted`, `notDetermined` |
| `locationAccuracy` | `full`, `reduced` |
| `backgroundRefresh` | `available`, `denied`, `restricted` |

자동 제한을 새로 적용하려면 Family Controls 승인, Always 위치 권한, Full Accuracy가 모두
필요하다. 권한의 실제 상태는 매 평가 전에 시스템에서 다시 확인한다.

### AppliedRestrictionState

named Managed Settings store에 현재 반영된 활성 `(ruleID, revision)` 집합을 보존한다. 적용 여부는
집합이 비어 있는지로 파생하며, 모든 활성 규칙의 application token 합집합은 규칙 collection에서
재구성한다. 동일한 활성 revision 집합은 idempotent한 무효과다.

### RestrictionPresentationState

사용자에게 표시할 정규화된 상태다.

- `configurationRequired`
- `inactive`
- `active`
- `permissionRequired(missingPermissions)`
- `locationUnavailable`

`locationUnavailable`은 현재 shield의 실제 적용 여부를 함께 보존할 수 있다. 즉 위치 확인 실패가
이미 적용된 제한을 자동으로 해제하지 않는다.

## State Evaluation

### Inputs

- 유효한 모든 `RestrictionRuleSnapshot`
- 현재 현지 시각과 달력
- rule ID별 `LocationConditionCollectionSnapshot`
- `AuthorizationSnapshot`
- 현재 shield에 반영된 활성 `(ruleID, revision)` 집합

### Decision table

| Priority | Condition | Presentation | Effect |
|----------|-----------|--------------|--------|
| 1 | 규칙 없음 또는 비활성 | `configurationRequired` 또는 `inactive` | shield 제거 |
| 2 | 시간 구간 종료 | `inactive` | shield 제거 |
| 3 | 필수 권한 부족 | `permissionRequired` | 새 shield 적용 금지; 실제 시스템 상태와 동기화 |
| 4 | 시간 활성 + 위치 `outside` | `inactive` | shield 제거 |
| 5 | 시간 활성 + 위치 `unavailable` | `locationUnavailable` | 기존 shield 상태 보존 |
| 6 | 시간 활성 + 위치 `inside` + 권한 유효 | `active` | 선택 앱 shield 적용 |

각 규칙을 독립 평가한 뒤 `active` 규칙과 위치 불가로 기존 상태를 보존해야 하는 규칙을 합성한다.
최종 활성 규칙들의 application token 합집합을 한 번 적용하고, 동일한 활성 rule revision 집합에는
효과를 다시 발생시키지 않는다.

## Persistence Boundaries

| Artifact | Writer | Readers | Protection |
|----------|--------|---------|------------|
| `restriction-rules.json` | Main app | Main app, Device Activity extension | Atomic replace + complete-until-first-unlock |
| `saved-places.json` | Main app | Main app, Device Activity extension | Atomic replace + complete-until-first-unlock |
| `location-conditions.json` | Main app location adapter | Main app, Device Activity extension | Atomic replace + complete-until-first-unlock |
| Named Managed Settings store | Main app or Device Activity extension | Operating system | System-managed |
| Regenerable flags | Owning target | App/extension as required | App Group UserDefaults |

규칙과 위치 파일은 각각 단일 writer를 유지한다. decode 실패, 알 수 없는 `schemaVersion`, revision
불일치 또는 파일 보호로 읽을 수 없는 상태는 안전한 `configurationRequired` 또는
`locationUnavailable`로 변환하며 추정값을 만들지 않는다.

## Lifecycle

1. 사용자가 유효한 규칙을 저장한다.
2. 앱이 보호된 규칙 파일을 원자적으로 교체하고 요일별 시스템 일정을 등록한다.
3. 앱이 원형 위치 조건을 등록하고 신뢰 가능한 초기 위치 판정을 기록한다.
4. 시간 또는 위치 이벤트가 상태 평가를 호출한다.
5. 상태 머신이 shield 적용·제거·무효과 중 하나를 반환한다.
6. 활성 제한 동안 편집·끄기·삭제 요청은 거부된다.
7. 시간 종료 또는 확인된 범위 이탈 후 shield를 제거하고 편집을 허용한다.
8. 권한 철회 시 새 제한을 적용하지 않고 권한 안내 상태로 전환한다.
9. 재부팅 후 첫 잠금 해제 시 저장 파일과 시스템 등록을 복구하고, 신뢰 가능한 위치가 확인될
   때까지 위치 상태를 `unavailable`로 유지한다.
