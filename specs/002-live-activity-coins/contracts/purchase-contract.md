# 계약: StoreKit 2 코인 구매

## 상품

- App Store Connect의 consumable IAP만 지원한다.
- 초기 catalog는 코인 1개·3개·5개 consumable 세 상품으로 고정한다. 실제 product ID는 번들 설정의
  허용 목록에 두고 각각 지급 수량 1·3·5와 정확히 매핑한다.
- 상품명·설명·가격은 StoreKit이 제공하는 현지화 값을 사용하며 가격 문자열을 하드코딩하지 않는다.
- 상품 로드 실패 시 이전 가격을 현재 가격처럼 표시하지 않는다.

## 구매 결과

구매 버튼과 `Product.purchase()` 호출의 사전 조건은 iCloud 계정과 최신 CloudKit 장부가 확인된
`current` 상태다. `current`는 현재 프로세스 monotonic clock 기준 5분 이내 성공 fetch, 일치하는
epoch·완료된 projection, 미해결 reconciliation 없음까지 확인하고 구매 직전 최신 record를 다시
fetch한 상태여야 한다. 프로세스 재시작 후 새 fetch 전에는 `current`가 아니다. `syncing`,
`stale`, `unavailable`, `deletionConfirmed`, `resetRequired`에서는 버튼을
비활성화하고 구매 API를 호출하지 않는다. 원격 장부가 없는 `setupRequired`도 사용자가 최초 활성화
고지를 확인하고 initial epoch를 만들기 전에는 같은 방식으로 비활성화한다. 이미 시작되어 전달된 unfinished transaction은 별도
재조정 경로에서 보존한다.

| StoreKit 결과 | 동작 |
|----------------|------|
| verified success | CloudKit 구매 지급을 멱등 commit한 뒤 transaction을 finish한다. |
| unverified | 지급하지 않고 검증 실패를 안내한다. |
| pending | 지급하지 않고 대기 상태를 표시하며 `Transaction.updates`를 기다린다. |
| userCancelled | 잔액을 변경하지 않고 구매 화면으로 돌아간다. |
| error | 잔액을 보존하고 재시도 가능한 오류를 표시한다. |

## 지급 멱등성

- 지급 키는 `environment + transaction.id`다.
- product ID가 허용 catalog에 없거나 catalog 수량과 일치하지 않으면 지급하지 않는다.
- 같은 transaction이 purchase 결과, `Transaction.updates`, 재실행 복구에서 반복돼도 PurchaseGrant와
  purchaseGrant event는 한 번만 생성한다.
- CloudKit 지급 commit 전에는 `finish()`하지 않는다.
- commit 성공 뒤 finish가 실패하면 다음 실행에서 동일 거래를 다시 받아 중복 지급 없이 finish한다.

## 수명주기 복구

- 앱 시작 때 `Transaction.updates` listener를 먼저 시작한다.
- unfinished 거래를 조회해 미완료 지급·finish를 재조정한다.
- 소모성 구매를 `currentEntitlements` 복원 대상으로 취급하지 않는다.
- 초기 범위는 App Store Server API·Server Notifications를 사용하지 않는다.

## iCloud 잔액 동기화

- 로컬 코인 데이터가 없는 재설치·새 기기에서는 동일 iCloud의 `current` CloudKit 장부에 있는 기존
  PurchaseGrant와 사용·보정 event를 읽어 미사용 잔액과 내역 projection을 복구한다.
- 이 흐름은 `Product.purchase()`를 호출하거나 `currentEntitlements`에서 소모성 상품을 복원하거나
  새 PurchaseGrant를 만드는 StoreKit `구매 복원`이 아니다.
- 각 복구 지급은 기존의 검증된 transaction ID와 연결돼야 하며, 기존 장부가 없거나 삭제됐거나
  `current`가 아니면 자동 복구하지 않는다. 초기 fetch 뒤 원격 장부·삭제 증거가 모두 없는 경우는
  잔액 복구가 아닌 `setupRequired` 최초 활성화로만 진행한다.
- 동일 App Store 계정은 복구 gate로 요구하지 않지만 계정 불일치 시 향후 환불·거래 재검증 한계가
  있음을 구매 전에 고지한다.

## 환불·철회

- 앱이 검증된 StoreKit 거래 변경에서 환불·철회를 확인하면 원 PurchaseGrant를 찾아
  `refundAdjustment` event를 한 번 추가한다.
- 미사용 구매 코인 범위에서만 차감하고 전체 잔액을 0 미만으로 만들지 않는다.
- 이미 사용한 수량은 소급해 규칙 해제를 취소하지 않는다.
- 환불 취소 상태를 확인하면 별도 reversal event로 이전 adjustment를 되돌린다.
- 앱이 실행되지 않는 동안의 실시간 환불 반영은 보장하지 않는다.

## 구매 전 고지

코인 기능을 처음 활성화할 때와 매 구매 확정 전에 다음 내용을 한국어·영어로 표시한다.

- 코인은 선택한 규칙의 현재 구간 한 번 해제에 사용한다.
- 같은 앱에 다른 활성 규칙이 있으면 제한이 남을 수 있다.
- 구매 코인은 만료되지 않는다.
- 잔액 복구에는 같은 iCloud 계정이 필요하며 App Store 구매 계정과 다를 수 있다.
- private iCloud 장부를 삭제하면 구매 잔액·내역과 당월 무료 해제권을 복구하지 못할 수 있다.
- 삭제가 확정되면 구매와 사용이 잠기며, 명시적으로 새 장부를 시작하면 구매 잔액과 당월 무료분은
  0에서 시작하고 다음 서울 기준 월부터 무료 2회를 다시 받는다.
- 서버 없는 초기 버전은 새 설치에서 과거 장부 삭제를 최초 설정과 완전히 구분하지 못할 수 있고 앱
  미실행 중 환불 반영에도 한계가 있다.

## 필수 테스트

- 현지 가격·상품 판매 불가·상품 로드 실패
- 1개·3개·5개 상품 ID와 지급 수량의 정확한 매핑
- `current`에서만 구매 가능하며 다른 sync 상태에서는 `Product.purchase()` 미호출
- verified/unverified/pending/cancel/error
- 동일 transaction 100회 중복 처리
- CloudKit commit 실패 뒤 미finish와 재시도
- commit 성공·finish 실패 뒤 중복 없는 완료
- 앱 재실행 pending 승인
- 환불·환불 취소·미사용 수량 부족과 0 clamp
- 최초 코인 활성화 및 매 구매의 한국어·영어 삭제 불이익 고지와 가격·수량 정확성
- 동일 iCloud `current` 장부의 새 설치 잔액·내역 복구, 새 grant 0개와 `iCloud 잔액 복구` 문구
