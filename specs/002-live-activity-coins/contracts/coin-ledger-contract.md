# 계약: CloudKit 코인 장부와 월간 무료 해제권

## 저장 범위

- `CKContainer`의 private database에 custom zone `CoinLedgerZone`을 사용한다.
- `LedgerEpoch`, `CoinAccount`, `MonthlyAllowance`, `PurchaseGrant`, `CoinLedgerEvent`,
  `ReleaseCommand`는 같은 zone에 둔다.
- 위치 좌표, 위치 정확도, Family Controls token, 앱·도메인 식별 정보는 저장하지 않는다.

## 계정 가용성

- iCloud account status와 최신 장부가 확인된 `current` 상태가 아니면 무료 지급·StoreKit 구매 시작·
  구매 지급·코인 사용을 확정하지 않는다.
- 네트워크·계정 상태가 불명확하면 마지막 mirror는 참고용으로만 표시하고 구매·사용 버튼을
  비활성화한다.
- iCloud sign-out 또는 계정 전환 시 이전 계정의 local mirror, sync state, pending change를 즉시
  격리한다.

## 월간 무료분

- 월 ID는 `Asia/Seoul`의 `yyyy-MM`이며 record ID는 `allowance:{monthID}`다.
- 현재 월 record가 없으면 quota 2, used 0, reserved 0으로 생성한다.
- 저장 뒤 CloudKit `creationDate`가 요청 monthID와 다른 서울 기준 월이면 지급을 무효로 처리한다.
- 이전 월 잔여분은 현재 잔액에 합산하지 않는다.
- 동일 record ID의 동시 생성 중 하나만 성공하며 충돌한 기기는 서버 record를 사용한다.

## 원자성·충돌

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
- 장부 동기화 이력이 없는 최초 설정에서는 초기 epoch를 만들 수 있다. 새 설치에서 삭제 event와
  이전 동기화 표식이 모두 사라진 경우에는 최초 설정과 과거 삭제를 서버 없이 완전히 구분할 수
  없으며, 이 한계를 최초 코인 기능 활성화와 구매 확인 전에 고지한다.

## 복구 한계

- CloudKit은 같은 iCloud 계정의 잔액·사용 내역 복구 수단이며 구매의 독립 증명이 아니다.
- private zone 삭제, iCloud와 App Store 구매 계정 불일치, 앱 장기 미실행 중 환불 반영 지연은 초기
  범위의 알려진 한계다. 삭제가 확정된 장부의 구매 잔액·내역·당월 무료분은 복구되지 않는다.
- zone 재생성 시 CloudKit 데이터나 local mirror만 보고 구매 지급을 새로 만들지 않는다.

## 필수 테스트

- 월 중간 최초 지급, 월 변경 비이월, 서울 자정 경계
- 기기 날짜·시간대 변경 및 잘못된 monthID 거부
- 두 기기 동시 월 record 생성과 무료분 동시 사용
- 무료 우선·구매 fallback·잔액 부족
- change-tag 충돌, timeout 결과 불명, retry idempotency
- iCloud 없음·sign-out·switch account·zone 삭제
- local mirror stale·손상·지원하지 않는 schema
- 일시 장애와 삭제 확정 구분, 삭제 상태의 구매·사용·무료 지급 차단
- 명시적 새 장부 시작 시 구매 잔액 0·당월 quota 0 및 다음 서울 기준 월 quota 2
