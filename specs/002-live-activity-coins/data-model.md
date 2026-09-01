# 데이터 모델: 제한 현황 Live Activity와 일회성 해제 코인

## 설계 목표

- 기존 규칙·위치·Shield 상태에서 현재 적용 구간과 대표 규칙을 결정론적으로 파생한다.
- Live Activity에 위치 좌표·앱 token 없이 필요한 최소 상태만 전달한다.
- 무료분과 구매 코인을 분리하고 구매·사용·보상·환불을 감사 가능한 장부로 보존한다.
- 같은 iCloud 계정의 여러 기기가 동시에 사용해도 무료분 2회와 구매 잔액을 초과 사용하지 않는다.
- CloudKit commit과 로컬 Shield 변경 사이의 부분 실패를 복구 가능한 상태로 표현한다.

## 핵심 엔티티

### RestrictionOccurrence

반복 규칙이 특정 날짜에 만든 한 번의 적용 구간이다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `id` | 결정적 문자열 | `ruleID + ruleRevision + startAt + endAt`에서 생성한다. |
| `ruleID` | UUID | 저장된 규칙을 참조한다. |
| `ruleRevision` | 정수 | 현재 규칙 revision과 일치해야 한다. |
| `startAt` | Date | DST 정책을 적용한 실제 시작 시각이다. |
| `endAt` | Date | `startAt`보다 뒤이며 기존 15분~12시간 규칙을 따른다. |
| `activatedAt` | Date | 시스템이 제한 활성 상태를 처음 확인한 시각이다. |

같은 occurrence ID는 재실행·재부팅 후에도 동일해야 한다. 해제 예외와 중복 사용 방지의 기준이다.

### ActiveRestrictionSnapshot

App Group에 저장하는 현재 활성 구간 collection이다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `schemaVersion` | 정수 | 지원 버전과 일치해야 한다. |
| `revision` | 단조 증가 정수 | 활성 집합·표시 근거 변경마다 증가한다. |
| `occurrences` | 배열 | 실제 적용된 규칙 revision에 대응하며 occurrence ID가 고유하다. |
| `observedAt` | Date | 마지막 조정 시각이다. |

대표 occurrence는 `activatedAt`, `startAt`, `ruleID` 순으로 가장 앞선 항목이다. 대표가 끝나면 같은
정렬의 다음 항목으로 교체한다.

### RestrictionLiveActivityAttributes

Live Activity의 정적·동적 데이터다. 전체 payload는 4KB보다 작아야 한다.

정적 필드:

| 필드 | 형식 | 규칙 |
|------|------|------|
| `activityID` | UUID | 앱이 관리하는 대표 Live Activity 식별자다. |
| `restrictionStartedAt` | Date | 최초 표시 대상 제한의 활성 확인 시각이다. |

`ContentState` 필드:

| 필드 | 형식 | 규칙 |
|------|------|------|
| `occurrenceID` | 문자열 | 현재 대표 구간이다. |
| `ruleDisplayName` | 문자열 | 사용자 규칙명 또는 지역화된 장소명이다. |
| `endsAt` | Date | 0 미만 카운트다운을 만들지 않는다. |
| `remainingDistance` | `known(meters)` / `unavailable` | 좌표와 정확도는 포함하지 않는다. |
| `distanceObservedAt` | Date? | known일 때 필수다. stale 판정에 사용한다. |
| `hasAdditionalRestrictions` | Bool | 다른 활성 규칙 존재 여부다. |

### CoinAccount

CloudKit `CoinLedgerZone`의 고정 record `coin-account`다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `schemaVersion` | 정수 | 지원 버전과 일치해야 한다. |
| `purchasedAvailable` | 0 이상 정수 | 구매 코인의 현재 사용 가능 수량이다. |
| `purchasedReserved` | 0 이상 정수 | 진행 중 해제 명령이 예약한 수량이다. |
| `revision` | 단조 증가 정수 | 모든 구매 잔액 변경마다 증가한다. |
| `updatedAt` | 서버 시각 | 마지막 확정 변경 시각이다. |

사용 가능한 구매 잔액은 `purchasedAvailable - purchasedReserved`이며 0 미만일 수 없다. 구매 코인은
월 변경이나 앱 재설치로 만료되지 않는다.

### LedgerEpoch

CloudKit 장부 한 세대의 생성·초기화 근거를 나타내는 고정 record다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `epochID` | UUID | 최초 장부 생성 또는 명시적 새 장부 시작마다 바뀐다. |
| `createdAt` | CloudKit 서버 시각 | 장부 세대의 시작 시각이다. |
| `reason` | `initialSetup` / `userConfirmedResetAfterDeletion` | 자동 reset 값은 허용하지 않는다. |
| `suppressedFreeMonthID` | 문자열? | 삭제 후 reset이면 당시 `Asia/Seoul` monthID, 최초 설정이면 nil이다. |
| `disclosureVersion` | 정수 | 사용자가 확인한 장부 삭제 불이익 문구 버전이다. |

`userConfirmedResetAfterDeletion` epoch는 CoinAccount를 0으로 만들고 `suppressedFreeMonthID`의
MonthlyAllowance quota를 0으로 생성한다. 다음 monthID부터 일반 quota 2를 적용한다.

### MonthlyAllowance

월별 무료 해제권 bucket이다. record ID는 `allowance:{yyyy-MM}`이며 연월은 `Asia/Seoul` 기준이다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `monthID` | `yyyy-MM` | record ID와 일치한다. |
| `quota` | 정수 | 초기 범위에서는 항상 2다. |
| `used` | 0...2 | 확정 사용 횟수다. |
| `reserved` | 0...2 | 진행 중 명령의 예약 횟수다. |
| `creationDate` | CloudKit 서버 시각 | `monthID`가 속한 서울 기준 월이어야 한다. |
| `updatedAt` | 서버 시각 | 마지막 변경 시각이다. |

현재 무료 사용 가능 수량은 `quota - used - reserved`다. 이전 월 bucket은 내역으로 남지만 현재
사용 가능 수량에 합산하지 않는다. 월 중간 신규 사용자도 현재 월 bucket을 생성한다.

### CoinLedgerEvent

CloudKit의 추가 전용 감사 이벤트다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `eventID` | 결정적 문자열 | zone 안에서 고유하며 같은 작업 재시도에 동일하다. |
| `kind` | 열거형 | `purchaseGrant`, `freeGrant`, `reservation`, `spend`, `release`, `refundAdjustment`, `reversal` |
| `source` | 열거형 | `monthlyFree`, `purchased` 또는 `none` |
| `quantity` | 양의 정수 | 변화 방향은 kind로 결정한다. |
| `relatedTransactionID` | UInt64? | 구매·환불 이벤트에 필요하다. |
| `relatedCommandID` | UUID? | 해제 관련 이벤트에 필요하다. |
| `occurrenceID` | 문자열? | 사용 이벤트에 필요하다. |
| `createdAt` | 서버 시각 | 장부 정렬과 감사에 사용한다. |

결정적 ID 예시:

- 구매 지급: `purchase:{environment}:{transactionID}`
- 무료 생성: `free:{monthID}`
- 예약: `reserve:{commandID}`
- 확정 사용: `spend:{commandID}`
- 예약 해제: `release:{commandID}:{attempt}`
- 환불: `refund:{transactionID}:{revocationDate}`

### PurchaseGrant

검증된 StoreKit 거래와 코인 지급을 연결한다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `transactionID` | UInt64 | 환경 안에서 지급 멱등 키다. |
| `environment` | sandbox / production | 서로 다른 환경을 혼합하지 않는다. |
| `productID` | 문자열 | 허용된 코인 팩 catalog에 있어야 한다. |
| `quantity` | 양의 정수 | 앱에 하드코딩한 허용 catalog와 일치해야 한다. |
| `purchaseDate` | Date | 검증 거래에서 읽는다. |
| `verificationState` | verified | unverified 상태는 저장·지급하지 않는다. |
| `adjustedQuantity` | 0...quantity | 환불로 회수한 미사용 수량이다. |

같은 environment·transaction ID는 한 번만 지급한다. CloudKit record가 구매의 새 증거는 아니며 최초
지급은 현재 기기에서 검증된 StoreKit 거래가 있어야 한다.

### ReleaseCommand

Shield 또는 앱에서 발생한 하나의 해제 시도를 조정한다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `commandID` | UUID | 클라이언트가 최초 시도 때 만들고 모든 재시도에 유지한다. |
| `occurrenceID` | 문자열 | 현재 활성 occurrence여야 한다. |
| `ruleID` | UUID | occurrence의 규칙과 일치한다. |
| `requestedFrom` | `shield` / `app` | 감사용이며 동작 차이를 만들지 않는다. |
| `fundingSource` | `monthlyFree` / `purchased` | reservation 때 무료 우선 정책으로 확정한다. |
| `state` | 상태 열거형 | 아래 전이를 따른다. |
| `createdAt`, `updatedAt` | 서버 시각 | timeout·재조정에 사용한다. |
| `failureCode` | 문자열? | 개인정보가 없는 안정 코드만 저장한다. |

상태 전이:

```text
requested
  ├─ reserve 실패 → rejected
  └─ reserve 성공 → reserved
                      ├─ 로컬 예외+Shield 조정 성공 → applied → committed
                      ├─ 로컬 적용 실패 → compensating → compensated
                      └─ 결과 불명 → reconciliationRequired

reconciliationRequired
  ├─ 로컬 예외 존재 → committed
  └─ 로컬 예외 없음 → compensated
```

동일 occurrence에 이미 `reserved | applied | committed` 명령이 있으면 새 예약을 만들지 않는다.

### ReleaseException

App Group에 저장해 Device Activity·Shield·앱이 공통으로 읽는 현재 구간 예외다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `schemaVersion` | 정수 | 지원 버전과 일치해야 한다. |
| `commandID` | UUID | CloudKit ReleaseCommand를 참조한다. |
| `occurrenceID` | 문자열 | 정확히 한 반복 구간에만 적용한다. |
| `ruleID`, `ruleRevision` | 식별자 | 현재 규칙과 일치해야 한다. |
| `effectiveAt` | Date | Shield 재평가 전에 저장한다. |
| `expiresAt` | Date | occurrence 종료 시각과 같다. |

만료됐거나 rule revision이 불일치하는 예외는 무시하고 정리한다. 다음 반복 구간에는 적용하지 않는다.

### CoinBalanceSnapshot

App Group에 저장하는 읽기 전용 로컬 mirror다. Shield Configuration은 네트워크 없이 버튼과 설명을
구성할 때 사용한다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `purchasedAvailable` | 0 이상 정수 | CloudKit confirmed 값이다. |
| `currentMonthID` | 문자열 | 서울 기준 현재 월이다. |
| `freeAvailable` | 0...2 | 현재 월의 confirmed 값이다. |
| `syncState` | `current`, `syncing`, `stale`, `unavailable`, `deletionConfirmed`, `resetRequired` | `current`일 때만 구매 또는 Shield 차감을 허용한다. Shield 버튼은 비가용 상태에서 복구 route로 사용할 수 있다. |
| `syncedAt` | Date | stale 판정 근거다. |
| `ledgerEpochID` | UUID? | 현재 CloudKit LedgerEpoch와 일치해야 한다. |
| `hadConfirmedLedger` | Bool | 이전 동기화 후 zone 부재를 삭제로 판단하는 로컬 근거다. |

로컬 mirror는 표시·진입 가능성 판단용이며 실제 사용 권한은 CloudKit의 최신 비교 후 교환 결과가
결정한다.

### PendingAppRoute

Shield Action이 메인 앱을 열기 전에 App Group에 기록하는 일회성 진입 목적이다.

| 필드 | 형식 | 규칙 |
|------|------|------|
| `routeID` | UUID | 같은 Shield action의 중복 처리를 막는다. |
| `destination` | `coinStore` / `iCloudRecovery` / `ledgerReset` / `reconciliation` | 최신 실패 원인으로 결정한다. |
| `createdAt` | Date | 앱이 소비한 뒤 삭제하며 오래된 route는 무시한다. |
| `occurrenceID` | 문자열? | 사용자에게 돌아갈 활성 제한 맥락이 있을 때만 기록한다. |

잔액 부족이면서 장부가 `current`일 때만 `coinStore`를 사용한다. iCloud·장부 불가, 삭제 확정,
재조정 상태를 구매 화면으로 보내지 않는다. iOS 26.0~26.4 fallback에서도 route를 남겨 사용자가 앱을
직접 열면 같은 목적지로 이동하게 한다.

## 관계

```text
RestrictionRuleSnapshot 1 ── * RestrictionOccurrence
RestrictionOccurrence 1 ── 0..1 ReleaseException
ReleaseCommand 1 ── 0..1 ReleaseException
ReleaseCommand 1 ── 0..1 PendingAppRoute
ReleaseCommand 1 ── * CoinLedgerEvent
PurchaseGrant 1 ── 1..* CoinLedgerEvent
CoinAccount 1 ── * purchased CoinLedgerEvent
MonthlyAllowance 1 ── * monthlyFree CoinLedgerEvent
LedgerEpoch 1 ── 1 CoinAccount
LedgerEpoch 1 ── * MonthlyAllowance
ActiveRestrictionSnapshot 1 ── 0..1 RestrictionLiveActivityAttributes.ContentState
```

## 불변 조건

- 무료 사용 가능 수량과 구매 사용 가능 수량은 항상 0 이상이다.
- 현재 월 무료분이 있으면 구매 코인을 예약하지 않는다.
- 같은 transaction ID는 최대 한 번 지급한다.
- 같은 occurrence는 최대 한 번 committed 해제된다.
- CloudKit reservation 성공 전에는 App Group 예외와 Shield를 변경하지 않는다.
- App Group 예외가 없는데 command가 committed일 수 없다.
- 보상되지 않은 결과 불명 명령은 새 차감보다 먼저 재조정한다.
- 위치 좌표, horizontal accuracy, Family Controls token은 CloudKit record에 포함하지 않는다.
- 서버 없는 초기 범위에서 CloudKit 장부를 StoreKit 구매의 독립 증명으로 사용하지 않는다.
- 구매는 CoinBalanceSnapshot과 CloudKit LedgerEpoch가 일치하는 `current` 상태에서만 시작한다.
- `deletionConfirmed | resetRequired`에서는 구매·사용·무료 지급을 허용하지 않는다.
- 삭제 후 새 epoch의 구매 잔액과 삭제 월 무료 quota는 모두 0이며 다음 월부터 quota 2다.

## 영속성 경계

| 데이터 | 작성자 | 독자 | 저장 위치 |
|--------|--------|------|----------|
| 활성 occurrence | 앱·Device Activity 조정 경로 | 앱·세 Screen Time 확장 | App Group atomic JSON |
| Live Activity 상태 | 메인 앱 ActivityKit coordinator | Widget Extension | ActivityKit |
| LedgerEpoch·CoinAccount·MonthlyAllowance·이벤트·명령 | 앱 또는 Shield Action의 coin service | 같은 iCloud 계정의 앱·Shield Action | CloudKit private custom zone |
| ReleaseException | 성공한 release coordinator | 앱·Device Activity·Shield 확장 | App Group atomic JSON |
| CoinBalanceSnapshot | CKSyncEngine mirror writer | 앱·Shield 확장 | App Group atomic JSON |
| PendingAppRoute | Shield Action | 메인 앱 | App Group atomic JSON |
| StoreKit 거래 | App Store | 앱 StoreKit adapter | StoreKit |

## 마이그레이션

- 기존 규칙·장소·위치 snapshot schema와 파일은 유지한다.
- 활성 occurrence, release exception, coin balance mirror는 새 파일로 추가해 기존 설치에서 파일 없음이
  정상 빈 상태가 되게 한다.
- 최초 설치에서 장부 존재 이력이 없고 CloudKit zone이 없으면 계정 상태 확인 후 initialSetup epoch와
  zone을 한 번 생성한다. zone 생성 전에는 구매·지급·사용을 허용하지 않는다.
- `userDeletedZone` event 또는 `hadConfirmedLedger == true`인 설치의 zone 부재는 삭제로 확정하고
  자동 재생성하지 않는다. 사용자가 새 장부 시작을 확인하면 reset epoch를 생성한다.
- 서버 없는 구조에서는 새 설치가 과거 삭제 event와 로컬 marker를 모두 잃은 경우를 완전히 판별할
  수 없으며, 이 한계는 사전 고지에 포함한다.
- iCloud 계정 전환 또는 sign-out 시 이전 계정 mirror·sync token·pending command를 격리하고 새
  계정의 초기 sync 완료 전 사용 버튼을 비활성화한다.
