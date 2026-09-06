# 계약: CloudKit 코인 장부와 월간 무료 해제권

## 저장 범위

- `CKContainer`의 private database에 custom zone `CoinLedgerZone`을 사용한다.
- `LedgerEpoch`, `CoinAccount`, `MonthlyAllowance`, `PurchaseGrant`, `CoinLedgerEvent`,
  `ReleaseCommand`는 같은 zone에 둔다.
- 위치 좌표, 위치 정확도, Family Controls token, 앱·도메인 식별 정보는 저장하지 않는다.

## 계정 가용성

- iCloud account status와 최신 장부가 확인된 `current` 상태가 아니면 무료 지급·StoreKit 구매 시작·
  구매 지급·코인 사용을 확정하지 않는다.
- `current`는 iCloud 사용 가능, 현재 프로세스 private database 초기 fetch 완료, 주입 monotonic clock
  기준 마지막 성공 fetch 이후 5분 이내,
  mirror·`LedgerEpoch`·`CoinAccount` epoch 일치, fetch된 지급·사용·보정 projection 완료, 결과 불명
  command와 pending reconciliation 없음이 모두 성립할 때만 부여한다. 구매·사용 직전 최신 record를
  다시 fetch하며 monotonic 경과 시간이 5분을 넘으면 `stale`로 전환한다. wall-clock `syncedAt`은
  표시·진단 전용이고 프로세스 재시작 후 새 fetch 전에는 `current`를 복원하지 않는다.
- 초기 fetch가 끝난 뒤 원격 장부가 없고 삭제가 확인되지 않은 최초 활성화는 `setupRequired`로 두고,
  사용자가 복구 한계 고지와 활성화 action을 확인해야만 `CoinLedgerSetupService`가 initial epoch와
  현재 월 quota 2를 한 atomic modify로 만든다. 삭제 reset service와 이 entry point를 공유하지 않는다.
- 네트워크·계정 상태가 불명확하면 마지막 mirror는 참고용으로만 표시하고 구매·사용 버튼을
  비활성화한다.
- iCloud sign-out 또는 계정 전환 시 이전 계정의 local mirror, sync state, pending change를 즉시
  격리한다.

## 월간 무료분

- 월 ID는 `Asia/Seoul`의 `yyyy-MM`이며 record ID는 `allowance:{monthID}`다.
- 현재 월 record가 없으면 새달의 첫 앱 foreground 또는 Shield 해제 요청에서 quota 2, used 0,
  reserved 0으로 지연 생성한다. 매월 1일 00:00의 background 생성을 요구하지 않는다.
- Shield가 새달 첫 요청이면 allowance·freeGrant·무료 1회 reservation·ReleaseCommand를 하나의 atomic
  modify에 포함한다.
- 저장 뒤 CloudKit `creationDate`가 요청 monthID와 다른 서울 기준 월이면 지급을 무효로 처리한다.
- 이전 월 잔여분은 현재 잔액에 합산하지 않는다.
- 동일 record ID의 동시 생성 중 하나만 성공하며 충돌한 기기는 서버 record를 사용한다.

## 원자성·충돌

- 예약 repository의 `verifyReservationCompatibility(epochID)`는 기본 false다. 이 경계는 freshness와
  별개이며 기존 장부 전환·구버전 writer 배제가 검증되지 않으면 true를 공급하지 않는다. 이번 단계의
  허용 provider는 격리 테스트 전용이고 실제 migration·운영 활성화는 완료하지 않는다.
- 무료·구매 예약은 읽은 `LedgerEpoch`도 같은 CAS modify에 넣어 reset 경쟁을 막는다. 구매 fallback은
  소진된 allowance를 함께 CAS해 충돌 시 무료 우선 정책을 다시 평가한다. `reservePurchasedCoin`도
  최신 무료분이 있으면 monthlyFree reservation을 반환할 수 있다.
- 같은 command의 진입 표면이 달라져도 최초 감사 정보를 유지한다. claim·reservation event가 없는
  기존 command는 성공으로 재사용하지 않는다. 결과 불명 예약 재조회가 실패하면 새 쓰기 없이
  reconciliationRequired로 남기며, 성공 확인에는 제안 값이 아니라 재조회한 잔액을 사용한다.

- `ReleaseOccurrenceClaim`은 epoch·occurrence별 고유 record로 무료·구매 경로가 공유한다.
  schema 1 필드는 `schemaVersion`, `epochID`, `occurrenceID`, `commandID`, `state`, `updatedAt`이며
  record name은 `release-claim:{소문자 epoch UUID}:{occurrenceID UTF-8 SHA-256 소문자 hex}`다.
- claim의 `held` 획득을 reservation·command·잔액 변경과 같은 atomic modify에 포함한다.
  `committed`와 결과 불명에서는 held를 유지하며, `compensated`·잔액 보상과 같은 atomic modify에서만
  `released`로 바꾼다. 삭제하지 않고 CAS로 재획득하며 시간만으로 해제하지 않는다.
- 기존 여섯 record type의 schema 1은 그대로 읽는다. claim 없는 기존 진행·완료 command를
  새 예약 가능으로 간주하지 않는다. 구버전 writer 공존·기존 장부 전환의 안전성 검증 전 새 예약을
  차단하며 데이터 삭제·자동 reset을 migration 수단으로 사용하지 않는다.

- mutable record는 `ifServerRecordUnchanged`로 저장한다.
- balance 또는 allowance 변경과 대응 ledger event·command 변경은 같은 atomic modify operation에
  포함한다.
- `serverRecordChanged`이면 최신 server record를 읽고 잔액·occurrence 상태를 다시 검증한 뒤 같은
  event/command ID로 제한 횟수 안에서 재시도한다.
- timeout 또는 결과 불명은 새 command를 만들지 않고 기존 ID의 서버 존재 여부를 먼저 조회한다.

## 잔액 파생

```text
freeAvailable = currentAllowance.quota - used - reserved
purchasedUsable = coinAccount.purchasedAvailable - purchasedReserved
```

- 두 값은 0보다 작을 수 없다.
- `freeAvailable > 0`이면 무료분을 예약한다.
- 무료분이 없을 때만 구매 코인을 예약한다.
- 월 변경은 구매 잔액을 수정하지 않는다.

## 동기화

- CKSyncEngine은 remote changes와 local mirror를 background에서 동기화한다.
- 코인 사용의 승인 경로는 자동 sync 결과만 믿지 않고 최신 record fetch와 atomic save를 수행한다.
- confirmed server state만 App Group `CoinBalanceSnapshot`에 기록한다.
- extension이 local mirror를 수정하지 않으며 CloudKit command 결과 뒤 전용 writer가 갱신한다.

## 장부 삭제와 새 장부

- `CKSyncEngine`의 zone 삭제 event 또는 `CKError.userDeletedZone`을 받았거나, 이전에 동기화된 장부
  표식이 있는 설치에서 zone 부재를 서버 응답으로 확인한 경우에만 `deletionConfirmed`로 전환한다.
- 일시적 네트워크 장애, iCloud account 상태 조회 실패, timeout은 삭제로 간주하지 않고
  `unavailable` 또는 `stale`로 유지한다.
- `deletionConfirmed`와 `resetRequired`에서는 구매·사용·무료 지급을 모두 잠그며 local mirror로
  zone을 자동 복구하거나 잔액을 재업로드하지 않는다.
- 새 장부 시작은 메인 앱에서만 제공한다. 사용자가 삭제 불이익 고지를 확인하고 명시적으로 동의하면
  새 zone과 `LedgerEpoch`를 만들고 구매 잔액 0, 현재 서울 기준 월 무료 quota 0인 계정을 atomic하게
  생성한다. Shield는 reset을 시작할 수 없다.
- 다음 서울 기준 월부터 새 `MonthlyAllowance`에 quota 2를 적용한다.
- 장부 동기화 이력이 없는 최초 설정에서는 명시적 코인 기능 활성화 뒤 초기 epoch를 만들 수 있다. 새 설치에서 삭제 event와
  이전 동기화 표식이 모두 사라진 경우에는 최초 설정과 과거 삭제를 서버 없이 완전히 구분할 수
  없으며, 이 한계를 최초 코인 기능 활성화와 구매 확인 전에 고지한다.

## 복구 한계

- CloudKit은 같은 iCloud 계정의 잔액·사용 내역 복구 수단이며 구매의 독립 증명이 아니다.
- 동일 App Store 계정은 복구 전제 조건이 아니다. App Store 구매 계정과 iCloud 계정이 다르면 향후
  거래 재검증·환불 재조정에 한계가 생길 수 있음을 고지한다.
- private zone 삭제와 앱 장기 미실행 중 환불 반영 지연은 초기 범위의 알려진 한계다. 삭제가 확정된
  장부의 구매 잔액·내역·당월 무료분은 복구되지 않는다.
- zone 재생성 시 CloudKit 데이터나 local mirror만 보고 구매 지급을 새로 만들지 않는다.

## 재설치·새 기기 iCloud 잔액 복구

- 로컬 코인 데이터가 비어 있으면 동일 iCloud private database의 zone과 현재 epoch를 먼저 초기
  fetch한다.
- zone·epoch·CoinAccount가 `current`이고 모든 PurchaseGrant가 기존 검증 StoreKit transaction ID와
  연결되며 event projection이 일치하면 미사용 구매 잔액과 관련 내역 mirror를 재생성한다.
- 복구는 새 PurchaseGrant·ledger event·StoreKit 구매를 만들지 않으며 UI에는 `구매 복원`이 아니라
  `iCloud 잔액 동기화` 또는 `iCloud 잔액 복구`로 표시한다.
- zone 부재·삭제·불확실·schema 불일치에서는 local mirror나 StoreKit history만으로 잔액을 만들지
  않는다. 삭제 증거가 없고 초기 fetch가 완료된 최초 활성화는 `setupRequired`, 삭제 확인은
  `deletionConfirmed`, 그 밖의 불확실성은 `stale` 또는 `unavailable`로 분리한다.

## 필수 테스트

- 월 중간 최초 지급, 월 변경 비이월, 서울 자정 경계
- 자정에 앱·Shield가 실행되지 않은 상태에서 record를 요구하지 않고 다음 첫 앱 실행에서 quota 2를
  생성하며, 별도 첫 Shield 요청에서는 생성과 무료 1회 예약을 atomic 처리함
- 기기 날짜·시간대 변경 및 잘못된 monthID 거부
- 두 기기 동시 월 record 생성과 무료분 동시 사용
- 무료 우선·구매 fallback·잔액 부족
- change-tag 충돌, 4.9초 성공, 5초 성공 미확인, 5초 초과 late commit의 조회·보상과 retry idempotency
- iCloud 없음·sign-out·switch account·zone 삭제
- local mirror stale·손상·지원하지 않는 schema
- 일시 장애와 삭제 확정 구분, 삭제 상태의 구매·사용·무료 지급 차단
- `current`의 monotonic 5분 freshness, 프로세스 재시작 후 재조회, 기기 wall clock 변경 무관성,
  epoch·projection 일치, pending reconciliation 차단과 명령 직전 재조회
- 원격 장부·삭제 증거가 없는 최초 활성화의 initial epoch·당월 quota 2와 확인된 삭제의 당월 quota 0
- 명시적 새 장부 시작 시 구매 잔액 0·당월 quota 0 및 다음 서울 기준 월 quota 2
- 로컬 데이터가 없는 동일 iCloud 새 설치의 `current` 장부 복구에서 잔액·내역이 일치하고 새 grant가
  0개이며, 부재·삭제·불확실 장부는 자동 복구되지 않음
