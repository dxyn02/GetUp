# Phase 0 조사: 제한 현황 Live Activity와 일회성 해제 코인

## 1. Live Activity 구성과 데이터 경계

**결정**: 앱과 새 Widget Extension이 공유하는 `RestrictionLiveActivityAttributes`를 두고,
메인 앱의 coordinator가 ActivityKit의 시작·갱신·종료를 소유한다. Widget Extension은
WidgetKit·SwiftUI로 읽기 전용 UI만 표시한다. 정적 속성에는 대표 규칙 식별 정보와 제한 시작
시각을, 동적 상태에는 종료 예정 시각, 남은 거리 상태, 다른 활성 규칙 존재 여부를 둔다.

**근거**: Apple은 앱에서 ActivityKit으로 수명주기를 관리하고 Widget Extension에서 UI를
구성하도록 정의한다. Live Activity는 자체 sandbox에서 네트워크나 위치 업데이트를 직접 받을 수
없고 정적·동적 데이터 합계는 4KB 이하여야 한다.

**검토한 대안**:

- Widget Extension이 App Group이나 Core Location을 직접 읽는 방식은 ActivityKit 실행 모델과
  위치 수신 제약에 맞지 않아 제외한다.
- 규칙마다 별도 Live Activity를 만드는 방식은 대표 규칙 하나만 표시한다는 제품 결정과 맞지 않아
  제외한다.

**출처**: [ActivityKit](https://developer.apple.com/documentation/activitykit),
[Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities),
[ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration)

## 2. Live Activity 자동 시작 경계

**결정**: 초기 범위에서는 서버와 ActivityKit push-to-start를 도입하지 않는다. 앱이 foreground에서
제한 시작 또는 현재 활성 제한을 확인했을 때 `Activity.request`로 시작한다. 앱 비실행 상태에서
자동 제한이 시작되면 Shield만 정상 적용하고, Live Activity는 다음 foreground 확인 때 시작한다.

**근거**: Apple이 문서화한 background 시작 경로는 ActivityKit push notification 또는 사용자가
실행하는 `LiveActivityIntent`다. Device Activity extension callback에서 메인 앱의 로컬
`Activity.request`를 대신 수행하는 공식 경로는 없다.

**검토한 대안**:

- push-to-start는 자동 시작을 지원하지만 서버, APNs 토큰, 전송 실패·만료 처리가 추가된다.
- `LiveActivityIntent`는 Shortcut·Control 등의 사용자 실행에는 적합하지만 자동 제한 callback의
  대체 수단은 아니다.
- 시간 경계에 미리 시작하면 미래의 위치 충족 여부를 알 수 없어 잘못된 활동을 표시할 수 있다.

**출처**: [Activity](https://developer.apple.com/documentation/activitykit/activity),
[Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)

## 3. 시간·거리 갱신 방식

**결정**: 남은 시간은 종료 예정 시각을 전달하고 Widget의 동적 날짜 텍스트로 표시해 초 단위
ActivityKit 업데이트를 만들지 않는다. 남은 거리는 앱이 신뢰 가능한 위치를 받은 경우에만
`max(0, 설정 반경 - 중심까지 직선거리)`로 계산하고, 신뢰할 수 없거나 stale이면 확인 불가로
전환한다.

**결정**: 기존 기능과 같이 지속 background location update를 사용하지 않는다. 시스템 위치 이벤트나
앱 실행 때 얻은 마지막 신뢰 거리만 표시하고, 신뢰 기준을 벗어나면 확인 불가로 전환한다. 이동 중
연속 거리 갱신은 보장하지 않는다.

**결정**: 거리 갱신 30초는 메인 앱이 신뢰 가능한 위치를 전달받아 ActivityKit을 조정할 수 있게 된
시점부터 측정한다. extension만 위치를 받으면 근거를 공유 저장소에 남기되 수신 시점의 ActivityKit
갱신을 보장하지 않고, 다음 앱 foreground에서 coordinator가 조정 가능해진 시점부터 측정한다.

**검토한 대안**:

- 초 단위 시간 업데이트는 불필요한 실행·전력 비용 때문에 제외한다.
- Widget Extension 내부 거리 계산은 위치 업데이트를 받을 수 없어 제외한다.
- APNs 거리 갱신은 서버로 정밀 위치를 전송해야 하므로 `FR-026`과 개인정보 최소화 원칙에 맞지
  않아 제외한다.

**출처**: [Displaying dynamic dates in widgets](https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates),
[Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background),
[Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)

## 4. Live Activity 복구·종료

**결정**: 시작 전 `ActivityAuthorizationInfo.areActivitiesEnabled`를 확인하고 실패나 비활성화는
제한 동작과 분리된 비치명적 결과로 기록한다. 앱 진입 때 논리적 제한 상태와
`Activity.activities`를 조정해 중복·고아 활동을 정리한다. 대표 규칙이 바뀌면 같은 활동의 내용을
갱신하고, 활성 규칙이 없으면 최종 상태를 보낸 뒤 `.immediate`로 종료한다.

**근거**: 사용자는 Live Activities를 끌 수 있고 시스템 한도 때문에 시작이 실패할 수 있다.
기본 종료 정책은 종료된 UI를 계속 남길 수 있어 제한 해제와 동시에 사라져야 하는 요구에는 즉시
종료가 맞다.

**검토한 대안**:

- 대표 규칙 교체마다 새 활동을 시작하면 foreground 제약과 화면 깜박임 문제가 있어 제외한다.
- 기본 dismissal은 해제 뒤에도 화면에 남을 수 있어 제외한다.

**출처**: [ActivityAuthorizationInfo](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo),
[ActivityState.stale](https://developer.apple.com/documentation/activitykit/activitystate/stale),
[ActivityUIDismissalPolicy.immediate](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/immediate)

## 5. StoreKit 2 구매 처리

**결정**: 코인 팩은 consumable IAP로 구성하고 `Product.products(for:)`의 현지 가격을 표시한다.
`Product.purchase()` 결과 중 검증된 거래만 `transaction.id`를 멱등 키로 지급 장부에 반영한 뒤
`finish()`한다. 취소·실패·검증 실패·pending은 지급하지 않으며 `Transaction.updates`와 미완료
거래를 앱 수명주기에서 재처리한다.

**근거**: 거래 완료보다 장부 커밋을 먼저 해야 지급 유실을 막을 수 있다. 소모성 구매는
`currentEntitlements`에 포함되지 않고 StoreKit 거래만으로 이미 사용한 코인을 재구성할 수 없으므로
별도 원장이 필요하다.

**검토한 대안**:

- 현재 잔액 숫자만 저장하면 중복 지급, 사용, 환불의 근거를 재구성할 수 없어 제외한다.
- 구매 버튼 결과만 처리하면 Ask to Buy 등 나중에 완료된 거래를 놓칠 수 있어 제외한다.
- 일반 구매 복원 흐름은 소모성 상품의 잔여 수량을 복원하지 못해 제외한다.

**출처**: [Product](https://developer.apple.com/documentation/storekit/product),
[Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates),
[Transaction.currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements),
[SKIncludeConsumableInAppPurchaseHistory](https://developer.apple.com/documentation/bundleresources/information-property-list/skincludeconsumableinapppurchasehistory)

## 6. iCloud 장부와 동시성

**2026-09-04 승인 보강**: BLK-015·DEC-087에 따라 요청 ID의 멱등성과 occurrence의 배타성을 분리한다.
`ReleaseOccurrenceClaim`을 무료·구매 경로가 공유하며 잔액 예약과 같은 atomic modify로 획득한다.
보상 완료와 같은 modify로만 released로 전환하고 결과 불명·committed에서는 유지한다. 프로세스 내
Set만으로는 다기기·extension 경쟁을 막을 수 없고 occurrence별 command ID 고정은 보상 뒤 새 시도와
감사 이력을 혼합하므로 제외한다. 기존 장부·구버전 writer 호환 검증 전 원격 사용을 활성화하지 않는다.

**결정**: 같은 iCloud 계정의 CloudKit private database에 custom record zone을 만들고 구매 잔액,
월간 무료 해제권, 추가 전용 장부 이벤트를 같은 zone에 둔다. 결정적 이벤트 ID를 사용하고,
mutable 잔액·월간 버킷은 `ifServerRecordUnchanged`로 비교 후 교환한다. 잔액 변경과 장부 이벤트는
원자적으로 저장하며 충돌 시 최신 서버 값을 다시 읽어 같은 command ID로 재평가한다.

`CKSyncEngine`은 장부의 background 복제와 로컬 mirror에 사용하되, 실제 해제 전에는 최신 레코드를
확인하고 원자적 저장이 성공한 뒤에만 Shield를 갱신한다. iCloud 계정이 없거나 상태를 확인할 수
없으면 지급·사용을 보류한다. 계정 전환 시 이전 계정의 로컬 mirror와 sync state를 격리한다.

**근거**: private database는 현재 iCloud 사용자 범위이며 custom zone은 관련 레코드의 원자적
변경을 지원한다. change tag를 확인하지 않는 덮어쓰기는 여러 기기에서 잔액 손실이나 초과 사용을
만들 수 있다.

**검토한 대안**:

- 이벤트만 추가하면 두 기기가 같은 잔액을 보고 동시에 초과 사용할 수 있어 제외한다.
- 자동 sync 시점만 신뢰하면 stale 잔액으로 제한을 해제할 수 있어 제외한다.
- 오프라인 선차감 후 병합은 이중 해제를 막을 수 없어 제외한다.

**출처**: [CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer),
[CKRecordZone](https://developer.apple.com/documentation/cloudkit/ckrecordzone),
[ifServerRecordUnchanged](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged),
[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)

## 7. 월간 무료 해제권 식별·생성 시점

**결정**: `free:{yyyy-MM}` 형태의 결정적 레코드 ID와 CloudKit 서버 생성 시각을 사용해 같은
계정·월의 중복 지급을 막는다. 월 경계는 `Asia/Seoul` 시간대의 매월 1일 00:00으로 고정한다.
실제 record는 자정 background 작업으로 만들지 않고 새달 첫 앱 foreground 또는 Shield 해제 요청에서
지연 생성한다. Shield가 첫 요청이면 quota 2 생성과 무료 1회 reservation을 하나의 원자적·멱등 장부
명령으로 처리한다.

**근거**: 기기 달력만 사용하면 날짜·시간대 변경으로 미래 월 지급을 반복 요청할 수 있다.
CloudKit `creationDate`는 서버가 기록한 시각이므로 요청한 연월을 검증하는 보조 근거가 된다.
`BGTaskRequest.earliestBeginDate`는 지정 시각보다 이른 실행만 막을 뿐 해당 시각 실행을 보장하지
않으므로 자정 생성을 정책 완료 조건으로 둘 수 없다.

**검토한 대안**:

- 사용자 현재 시간대 기준은 직관적이지만 서버 없는 구조에서 시간대 변경 악용을 완전히 막기
  어렵다.
- `Asia/Seoul`은 한국의 월 경계와 일치하지만 해외 사용자에게 현지 1일이 아니다.
- `UTC`는 전 세계에서 단일하지만 한국에서는 매월 1일 오전 9시에 갱신된다.

**출처**: [CKRecord.creationDate](https://developer.apple.com/documentation/cloudkit/ckrecord/creationdate),
[BGTaskRequest.earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)

## 8. 구매 장부의 보안·환불 경계

**결정**: 초기 범위에서는 앱 서버와 App Store Server Notifications를 도입하지 않는다. 검증된
StoreKit 거래와 CloudKit private database 장부를 사용하고 앱 실행 시 거래 변경을 재조정한다.
private zone 삭제, iCloud와 App Store 계정이 다를 때 향후 거래 재검증·환불 조정의 한계, 앱 장기
미실행 동안 환불 반영 지연을 구매 전에 고지한다. 동일 App Store 계정은 iCloud 잔액 복구의 gate로
요구하지 않는다. 실제 유료 판매 규모나 부정 사용 위험이 커지면 서버 도입을 별도 기능으로
재검토한다.

**근거**: App Store Server API는 소모성 및 환불 거래 내역을 제공하고 Server Notifications는
환불과 consumption request를 전달한다. CloudKit private database는 앱 서버가 사용자의 private
record를 권위 있게 관리하는 용도가 아니며 App Store 구매 계정과 iCloud 계정도 다를 수 있다.

**검토한 대안**:

- StoreKit 2 + CloudKit만 사용하는 방식은 서버 운영 없이 MVP가 가능하지만 완전한 부정 사용
  방지와 실시간 환불 반영을 보장하지 못한다.
- StoreKit 2 + CloudKit + 앱 서버는 요구사항 신뢰도를 높이지만 별도 인증·운영·개인정보·비용
  범위가 추가된다.

**출처**: [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi/),
[Get Transaction History](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-history),
[App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype),
[Handling refund notifications](https://developer.apple.com/documentation/storekit/handling-refund-notifications)

## Phase 0 1차 결론

ActivityKit 표시 구조, foreground 시작 경계, StoreKit 구매 처리, CloudKit 장부, 저전력 거리 갱신,
`Asia/Seoul` 월 경계와 서버 없는 초기 범위를 모두 결정했다. Phase 0의 미확정 항목은 없으며 Phase 1
설계를 진행할 수 있다.

## 9. 명확화 후 장부 가용성·삭제 복구·상품 catalog

**결정**: StoreKit 구매는 iCloud 계정과 최신 CloudKit 장부가 모두 확인된 `current` 상태에서만
시작한다. 초기 상품 catalog는 코인 1개·3개·5개 consumable 세 개로 고정하고 StoreKit의 현지 가격을
사용한다. 사용자가 Live Activity를 제거해 현재 activity가 없더라도 foreground에서 활성 제한을
확인하면 다시 생성한다.

`current`는 iCloud 사용 가능, 현재 프로세스 private database 초기 fetch 완료, 주입 가능한 monotonic
clock 기준 마지막 성공 fetch 이후 5분 이내, mirror·`LedgerEpoch`·`CoinAccount` epoch 일치,
fetch된 지급·사용·보정 projection 완료, 미해결 release reconciliation 없음이 모두 확인된 상태다.
구매·해제 직전 최신 record를 다시 조회하며 monotonic 경과 시간이 5분을 넘으면 `stale`로 내린다.
wall-clock `syncedAt`은 표시·진단에만 사용하고 프로세스 재시작 후 새 fetch 전에는 `current`를
복원하지 않는다.

CloudKit `userDeletedZone`, 삭제 event 또는 이전 동기화 흔적이 있는 설치에서 zone 부재가 확인되면
장부를 자동 복원하지 않고 `deletionConfirmed`로 잠근다. 사용자가 사전 고지된 불이익을 확인하고
새 장부 시작을 명시적으로 선택한 경우 새 ledger epoch를 생성한다. 새 epoch의 구매 잔액은 0이고,
삭제가 발생한 서울 기준 월의 무료 quota는 0으로 억제하며 다음 월부터 2회를 재개한다.

로컬 코인 데이터가 없는 재설치·새 기기에서는 zone 부재를 최초 설정으로 단정하지 않고 먼저 동일
iCloud private database를 초기 fetch한다. 기존 zone과 현재 epoch가 `current`로 확인되면 검증된
StoreKit transaction ID와 연결된 PurchaseGrant, 사용·환불·보정 event로 미사용 구매 잔액과 내역
projection을 복구한다. 이 동기화는 새 PurchaseGrant를 만들거나 StoreKit의 일반 `구매 복원`을
수행하지 않으며 `iCloud 잔액 동기화` 또는 `iCloud 잔액 복구`로 안내한다.

초기 fetch가 끝났고 원격 장부와 삭제 증거가 모두 없으면 `setupRequired`로 두고 고지와 활성화 action
확인 뒤 `CoinLedgerSetupService`가 initial epoch와 당월 무료 2회를 한 번의 atomic modify로 만든다.
삭제 후 0으로 시작하는 `CoinLedgerResetService`와 분리한다. 기존 장부는 복구하고, 삭제 증거가 있는 경우만
구매 0·삭제 월 무료 0 reset을 적용하며, 일시적 불확실성은 생성 없이 재시도한다. 서버 없는 새
설치가 원격 장부와 삭제 증거를 모두 잃은 경우를 최초 사용자와 완전히 구분할 수 없는 한계도
고지한다.

**근거**: CloudKit commit 가능성을 확인하지 않고 결제를 시작하면 결제 성공과 코인 지급이 분리될
수 있다. 삭제된 권위 장부를 오래된 로컬 mirror로 복구하면 이미 사용한 코인이 되살아난다. 반대로
자동 0 초기화는 사용자 동의 없이 유료 잔액을 잃게 한다. reset epoch와 현재 월 억제는 사용자의
명시적 새 시작을 기록하면서 같은 달 무료분의 즉시 중복 지급을 막는다.

**검토한 대안**:

- iCloud 불가 상태에서 구매 후 나중에 지급하는 방식은 사용자가 결제 직후 재화를 받지 못하므로
  제외한다.
- 마지막 local mirror를 zone에 다시 올리는 방식은 stale·다기기 상태를 판별할 서버가 없어 제외한다.
- 장부 삭제를 감지하면 자동 0 초기화하는 방식은 데이터 손실을 숨기므로 제외한다.
- Live Activity 수동 제거를 같은 occurrence 동안 존중하는 방식은 사용자가 활성 제한 중 재생성을
  선택했으므로 제외한다.
- 동일 App Store 계정까지 복구 전제 조건으로 요구하는 방식은 서버·자체 앱 계정이 없는 현재
  구조에서 신뢰성 있게 확인할 수 없고, 동일 iCloud 장부 기준이라는 제품 결정과 달라 제외한다.

**출처**: [Persisting a purchase](https://developer.apple.com/documentation/storekit/persisting-a-purchase),
[CloudKit Remote Records](https://developer.apple.com/documentation/cloudkit/remote-records),
[CKSyncEngine account change](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/event/accountchange),
[CKError.userDeletedZone](https://developer.apple.com/documentation/cloudkit/ckerror/userdeletedzone),
[Product](https://developer.apple.com/documentation/storekit/product)

## 10. Shield 단일 해제 버튼과 앱 진입 가능성

**결정**: Shield Configuration은 현재 제목·설명 등 기존 요소를 유지하고 primary button 하나를
`해제권 1회 사용`으로 구성한다. 이 버튼은 최신 장부에서 무료 해제권을 먼저 사용하고, 무료분이
없으면 구매 코인 1개를 사용하는 데 대한 단일 동의다. 당월 무료분이 아직 생성되지 않았고 장부가
`current`이면 quota 2 생성과 1회 예약을 같은 원자적 command로 처리한다.

잔액이 실제로 부족하면 App Group의 `PendingAppRoute.coinStore`를 기록하고 앱의 코인 상점으로
유도한다. iCloud 계정·장부가 unavailable·stale·삭제 확정·재조정 중이면 구매를 유도하지 않고
해당 복구 route를 기록한다. Shield primary action이 release service에 전달된 시점부터 5초 안에
CloudKit 성공을 확인하지 못하면 제한을 유지하는 fail-closed 결과로 끝내고 앱에서 상태를 확인하게
한다. 5초는 제품이 정한 내부 상한이며 Apple이 보장하는 extension 실행 시간은 아니다. timeout은
서버 미반영을 뜻하지 않으므로 같은 command ID를 다음 foreground에서 조회해 늦은 commit을 판별하고,
제한이 적용되지 않은 reservation은 보상한다.

iOS 26.5 이상에서는 `ShieldActionResponse.openParentalControlsApp`으로 containing parental
controls app을 여는 공식 경로를 사용한다. 프로젝트 최소 지원 버전인 iOS 26.0~26.4에는 이 case가
없으므로 Shield 문구로 앱 실행을 안내하고 `.close`를 반환한 뒤 사용자가 GetUp을 직접 열면 저장된
`PendingAppRoute`를 소비한다. custom URL을 임의로 실행하거나 비공개 extension API를 사용하는
방식은 채택하지 않는다. 실제 가격·상품·결제 버튼은 Shield가 아니라 앱 안에서만 표시한다.

route는 생성 후 5분 이내이고 연결 occurrence가 활성이고 아직 소비되지 않은 경우에만 repository가
한 번 반환한 뒤 atomic 삭제한다. 만료·중복·종료 occurrence route는 자동 이동 없이 폐기한다.

**근거**: `ShieldConfiguration`은 primary·secondary button을 구성할 수 있고,
`ShieldActionDelegate`는 선택된 button action에 비동기 완료 응답을 반환한다. 설치된 iOS 26.5 SDK의
Swift interface에서 `openParentalControlsApp`은 iOS 26.5부터 사용 가능함을 확인했다. 따라서 제안한
무료 우선 해제와 잔액 부족 시 앱 유도는 공식 API만으로 구현할 수 있지만, 최소 지원 버전 전체에서
자동 앱 열기를 동일하게 보장할 수는 없다. 또한 extension 내부에 IAP 제안을 직접 두지 않고 실제
구매를 containing app에 한정하는 것이 App Extension과 인앱결제 경계를 명확히 한다.

**검토한 대안**:

- 무료·구매 버튼을 분리하면 사용자가 선택한 무료 우선 정책과 충돌하고 stale 잔액을 UI가 미리
  단정할 수 있어 제외한다.
- 장부 상태가 불명확할 때 바로 코인 상점으로 보내면 구매 성공 뒤 지급을 확정하지 못할 수 있어
  복구 경로로 분리한다.
- iOS 26.0~26.4에서 custom URL 또는 `UIApplication`으로 앱을 강제 실행하는 방식은 공개된 Shield
  extension 계약이 아니므로 제외한다.
- Shield가 종료될 때까지 무제한 대기하는 방식은 extension이 빠르게 완료돼야 하는 실행 경계와
  사용자의 예측 가능한 실패 처리 요구에 맞지 않아 제외한다.

**출처**: [ShieldConfiguration](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration),
[ShieldActionDelegate](https://developer.apple.com/documentation/managedsettings/shieldactiondelegate),
[ShieldActionResponse](https://developer.apple.com/documentation/managedsettings/shieldactionresponse),
[ShieldActionResponse.defer](https://developer.apple.com/documentation/managedsettings/shieldactionresponse/defer),
[CKOperation.Configuration.timeoutIntervalForRequest](https://developer.apple.com/documentation/cloudkit/ckoperation/configuration-swift.class/timeoutintervalforrequest),
[openParentalControlsApp](https://developer.apple.com/documentation/managedsettings/shieldactionresponse/openparentalcontrolsapp)

## 11. Live Activity 성공 기준의 계측 모집단

**결정**: 시작 성공률은 Live Activity 지원 기기, 권한 허용, 유효한 활성 제한, 앱 foreground를 모두
만족하는 100회만 모집단으로 삼고, 활성 제한을 확인한 시점부터 30초 안에 95회 이상 표시되는지
측정한다. 권한 거부와 미지원 기기는 성공률 분모에 섞지 않고 제한 판정·적용·해제가 영향을 받지
않는 별도 안전 실패 테스트로 검증한다.

거리 갱신은 메인 앱이 신뢰 위치를 받고 ActivityKit coordinator가 조정 가능한 시점을 기준으로
30초를 측정한다. extension-only 위치는 공유 근거 저장 성공을 검증하고, 다음 foreground에서 같은
coordinator 기준 시점부터 30초 안에 반영되는지 측정한다. 테스트는 주입 가능한 시계와 adapter
fixture를 사용하고 실기기 결과와 Simulator 결과를 분리해 기록한다.

남은 시간은 주입 시계로 `max(0, endsAt - now)`를 검증하며 종료 전·경계·종료 후 표시 오차를 60초
이내로 제한한다. 마감 성능 suite는 전용 계측을 다시 구현하지 않고 이 결과를 집계한다.

**근거**: 시스템 권한 거부·미지원 사례를 시작 성공률에 포함하면 앱이 제어할 수 없는 상태가 구현
성능을 왜곡한다. 반대로 안전 실패를 제외하면 제한 기능 독립성 요구를 놓치므로 별도 모집단이
필요하다. 위치 수신 주체별로 ActivityKit 접근 가능 시점이 다르므로 동일한 기산점을 쓰지 않는다.

**검토한 대안**:

- 모든 기기·권한 상태를 하나의 성공률로 계산하는 방식은 플랫폼 비가용성과 구현 실패를 구분하지
  못해 제외한다.
- extension 위치 수신 즉시 30초를 측정하는 방식은 extension이 메인 앱의 ActivityKit 조정을 보장할
  수 없어 제외한다.

## 최종 Phase 0 결론

명확화된 Live Activity 계측 모집단·위치 갱신 기산점, 동일 iCloud `current` 장부의 새 설치 복구,
Shield 5초 fail-closed·늦은 결과 재조정, 새달 첫 앱·Shield 요청의 무료분 지연 생성까지 결정했다.
공식 앱 진입 API의 iOS 26.5 가용성과 iOS 26.0~26.4 호환 경로도 검증 항목에 반영했으며 남은 제품
미확정 항목은 없다.
