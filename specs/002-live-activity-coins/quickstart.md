# Quickstart: 구현 검증 가이드

이 문서는 구현 완료 뒤 Live Activity, 월간 무료 해제권, 코인 구매와 규칙 1회 해제를 end-to-end로
검증하는 실행 가이드다. 데이터 규칙은 [data-model.md](data-model.md), 타깃 간 동작은
[contracts](contracts/)를 참조한다.

## 준비 사항

- Xcode 26 계열과 iOS 26 이상 Simulator
- iOS 26 이상 테스트 iPhone 2대 또는 같은 iCloud 계정으로 다기기 충돌을 재현할 수 있는 환경
- 기존 앱과 세 Screen Time 확장의 Family Controls·App Group capability
- 새 Widget Extension과 앱의 Live Activities capability 및 `NSSupportsLiveActivities`
- 앱·Shield Action target에서 접근 가능한 CloudKit container와 iCloud capability
- CloudKit development schema의 `CoinLedgerZone`
- 코인 1개·3개·5개 consumable 상품을 등록한 App Store Connect 또는 로컬 StoreKit Configuration
- StoreKit sandbox tester

Simulator와 fake adapter는 도메인·UI 검증에 사용한다. 실제 Shield action, Live Activity lifecycle,
StoreKit sandbox, iCloud account switch와 background 위치 event의 최종 근거는 실기기에 남긴다.

## 빌드와 자동 테스트

scheme과 target을 확인한다.

```sh
xcodebuild -list -project GetUp.xcodeproj
```

Simulator에서 전체 자동 테스트를 실행한다.

```sh
xcodebuild test \
  -project GetUp.xcodeproj \
  -scheme GetUp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

필수 자동 검증 결과:

- 활성 occurrence와 대표 규칙 선택이 재실행에도 결정적이다.
- 기존 위치 평가가 `.inside`이고 5분 이내일 때만 남은 거리를 항상 미터·10m 단위 half-up으로
  표시하며 5m 반올림 경계, 0 clamp, stale·unavailable 전환이 일치한다.
- 앱 비실행 제한 시작에는 Live Activity를 만들지 않고 다음 foreground 확인에서 한 개만 시작한다.
- 지원 기기·권한 허용·유효한 활성 제한·foreground 100회 중 95회 이상에서 활성 제한 확인 후
  30초 안에 Live Activity를 표시한다. 권한 거부·미지원은 별도 안전 실패로 검증한다.
- 메인 앱이 신뢰 위치를 받고 ActivityKit 조정이 가능해진 뒤 30초 안에 거리를 반영한다.
  extension-only 위치는 저장하고 다음 foreground 기산점부터 30초 안에 반영한다.
- 주입 시계의 종료 전·경계·종료 후 사례에서 남은 시간 오차가 60초 이내이고 종료 후 0으로 clamp된다.
- 사용자가 Live Activity를 직접 제거해도 제한이 활성인 다음 foreground에서 다시 한 개를 만든다.
- 무료분 2회가 서울 기준 월에만 유효하고 다음 달로 이월되지 않는다.
- 무료분을 먼저 예약하며 같은 occurrence 동시 요청 100회에서 최대 한 번만 소모한다.
- 당월 무료분이 아직 없을 때 첫 Shield action은 quota 2 생성과 무료 1회 예약을 원자적으로 처리한다.
- StoreKit verified 거래만 지급하고 같은 transaction 100회에서 한 번만 지급한다.
- 최신 CloudKit 장부가 `current`일 때만 1개·3개·5개 상품 구매를 시작하며 그 밖의 상태에서는 구매
  API를 호출하지 않는다.
- `current`는 현재 프로세스의 monotonic clock 기준 5분 이내 성공 fetch, epoch·projection 일치,
  미해결 reconciliation 없음까지 만족하고 구매·해제 직전 서버 record를 다시 확인한다. 기기 wall
  clock 변경은 freshness를 늘리지 않으며 프로세스 재시작 후 새 fetch 전에는 `current`가 아니다.
- CloudKit conflict·timeout·부분 실패가 보상 또는 reconciliation 상태로 끝난다.
- 장부 삭제 확정 뒤 구매·사용·무료 지급이 잠기고, 명시적 새 장부는 구매 0·당월 무료 0으로
  시작하며 다음 서울 기준 월에 무료 2회를 지급한다.
- 로컬 데이터가 없는 동일 iCloud 새 설치는 기존 `current` 장부의 정확한 미사용 잔액·내역을
  복구하고 새 PurchaseGrant를 만들지 않는다.
- Shield는 4.9초 안에 확인된 성공만 적용하며 5초 안에 성공을 확인하지 못하면 제한을 유지하고
  늦은 결과를 재조정해 미적용 차감을 0으로 만든다.
- 환불 조정은 구매 잔액을 0 미만으로 만들지 않는다.

## Preview와 지역화

1. Widget Extension의 Lock Screen, Dynamic Island minimal·compact·expanded preview를 연다.
2. 거리 known, unavailable, 다른 규칙 존재, 종료 임박 상태를 한국어·영어로 확인한다.
3. 앱의 활성 제한·코인 구매·내역·확인 dialog와 Shield configuration fixture를 두 언어로 확인한다.
4. 가장 큰 Dynamic Type, VoiceOver, Light/Dark를 적용한다.

기대 결과:

- Live Activity에는 거리와 시간 외 코인 버튼이 없다.
- 가격·무료분·구매 코인·대상 규칙·남을 제한의 의미가 두 언어에서 같다.
- 위치 좌표나 Family Controls token이 preview·접근성 label·로그에 나타나지 않는다.

## StoreKit 검증

### 로컬 Configuration

1. 코인 팩 성공, 취소, pending, unverified fixture를 차례로 실행한다.
2. 코인 1개·3개·5개 상품의 product ID, 표시 수량과 실제 지급 수량을 비교한다.
3. CloudKit adapter를 `current`·동기화 중·stale·불가·삭제 확정으로 전환한다.
4. 비`current` 상태에서 구매 버튼이 비활성이고 `Product.purchase()`가 호출되지 않는지 확인한다.
5. 앱을 transaction finish 전후에 종료하고 재실행한다.

기대 결과:

- verified + CloudKit commit 성공만 코인을 지급한다.
- 1개·3개·5개 상품만 catalog와 동일한 수량을 지급한다.
- `current`가 아닌 장부에서는 새 구매를 시작하지 않되 기존 unfinished 거래는 보존한다.
- pending·취소·unverified는 잔액을 변경하지 않는다.
- CloudKit 실패 거래는 finish하지 않고 다음 실행에 같은 transaction ID로 재처리한다.
- commit 성공 뒤 finish 실패는 재실행에서 중복 지급 없이 finish된다.

### Sandbox

1. App Store Connect sandbox의 1개·3개·5개 상품 수량과 현지 가격을 확인한다.
2. 구매를 완료하고 CloudKit PurchaseGrant·ledger event·mirror를 확인한다.
3. refund 테스트 뒤 앱을 다시 실행해 조정 시점을 확인한다.

기대 결과:

- 가격과 구매 결과가 App Store 환경과 일치한다.
- 앱 서버가 없으므로 앱 비실행 중 환불 실시간 반영을 표시하거나 약속하지 않는다.

## CloudKit·월간 무료분 검증

1. 빈 private database로 월 중간에 최초 실행한다.
2. 같은 iCloud 계정의 두 기기에서 동시에 현재 월 지급을 요청한다.
3. 두 기기에서 무료 해제를 동시에 요청한다.
4. 기기 날짜·시간대를 미래·과거로 바꿔 다른 monthID를 요청한다.
5. 서울 기준 월 경계를 통과하고 남은 무료분·구매 코인을 비교한다.
6. iCloud sign-out, account switch, network 단절과 private zone 삭제를 각각 재현한다.
7. 일시적 network·account 조회 실패가 장부 삭제로 확정되지 않는지 확인한다.
8. 삭제 확정 상태에서 구매·사용·무료 지급이 잠기고 local mirror가 자동 업로드되지 않는지 확인한다.
9. 삭제 불이익 고지에 동의해 새 장부를 시작하고 구매 잔액·현재 월 무료분을 확인한다.
10. 서울 기준 다음 월 경계를 통과해 무료분을 확인한다.
11. 기존 `current` 장부와 구매·사용·보정 내역이 있는 동일 iCloud 계정으로 로컬 데이터가 없는 새
    설치를 시작해 초기 sync를 완료한다.
12. 별도 fixture에서 원격 zone 부재·삭제·schema 불일치·초기 fetch 미완료를 각각 재현한다.
13. 월 경계에서 앱과 Shield를 모두 실행하지 않은 채 자정을 지난 뒤 record 생성 여부를 확인하고,
    첫 앱 foreground와 별도 첫 Shield 요청 경로를 각각 실행한다.
14. 원격 장부·삭제 증거가 모두 없는 최초 활성화, 기존 `current` 장부 복구, 삭제 증거가 있는 zone
    부재를 별도 fixture로 실행한다.
15. 최초 활성화 고지에서 취소해 장부가 생기지 않음을 확인한 뒤 동의 action을 실행하고 initial
    epoch와 당월 quota 2가 같은 atomic 결과로 생성되는지 확인한다.

기대 결과:

- 현재 월 무료분은 계정 전체 최대 2회다.
- 이전 월 무료분은 이월되지 않고 구매 코인은 그대로다.
- 서버 creationDate와 맞지 않는 월 지급은 확정되지 않는다.
- iCloud 불가·mirror stale에서는 Shield와 앱이 코인을 차감하지 않으며, Shield 버튼은 구매가 아닌
  해당 복구 화면 안내로만 동작한다.
- 장부가 `current`가 아니면 구매도 시작할 수 없다.
- 계정 전환 시 이전 계정 잔액을 표시하거나 사용하지 않는다.
- 삭제 확정 뒤 자동 복원·자동 reset은 없고, 명시적 새 장부는 구매 잔액 0·당월 무료분 0으로
  시작하며 다음 서울 기준 월부터 무료 2회를 지급한다.
- 동일 iCloud의 기존 `current` 장부가 있으면 잔액·내역 projection이 정확히 복구되고 새 grant는
  0개다. 부재·삭제·불확실 장부는 자동 복구하지 않는다.
- 원격 장부·삭제 증거가 모두 없는 최초 활성화는 고지 확인 뒤 initial ledger와 당월 무료 2회를
  하나의 setup action으로 받고, 동의 전에는 장부가 생기지 않는다. 삭제가 확인된 reset은 별도
  entry point에서 구매 0·당월 무료 0을 받는다.
- 자정에는 background 생성을 요구하지 않고 첫 앱 foreground에서 quota 2를 생성한다. 별도 첫 Shield
  요청은 quota 2 생성과 무료 1회 사용을 한 command로 확정해 freeAvailable 1이 된다.

## Live Activity end-to-end

1. 앱 foreground에서 시간·위치 조건을 만족시켜 제한을 시작한다.
2. Live Activity의 대표 규칙·거리·카운트다운을 확인한다.
3. 다른 규칙을 활성화하고 추가 제한 안내를 확인한다.
4. 신뢰 가능한 위치 event와 stale 위치를 차례로 주입한다.
5. 대표 규칙을 종료하고 다음 대표로 바뀌는지 확인한다.
6. 모든 규칙을 종료해 즉시 사라지는지 확인한다.
7. 앱을 종료한 상태에서 새 제한을 시작한 뒤 앱을 foreground로 연다.
8. 활성 제한 중 Live Activity를 직접 제거하고 같은 occurrence가 끝나기 전에 앱을 foreground로
   연다.
9. 지원·권한·활성 제한·foreground fixture 100회에서 활성 제한 확인과 실제 표시 시각을 기록한다.
10. 메인 앱 신뢰 위치 수신과 ActivityKit 조정 가능 시각을 기록해 거리 반영을 확인한다.
11. extension에만 위치를 전달해 즉시 갱신되지 않음을 확인한 뒤 앱을 foreground로 열고 반영 시각을
    기록한다.

기대 결과:

- foreground 확인 뒤 30초 이내 활동 한 개가 표시된다.
- 앱 비실행 상태에서는 Shield만 적용되고 Live Activity가 자동 시작되지 않는다.
- 다음 foreground에서 현재 활성 제한으로 활동이 시작된다.
- 오래된 거리는 숫자로 남지 않고 확인 불가가 된다.
- 대표 교체는 새 활동을 중복 생성하지 않고 모든 제한 종료 때 즉시 끝난다.
- 수동 제거한 활동은 같은 occurrence가 활성인 다음 foreground에서 다시 한 개만 생성된다.
- 적격 100회 중 95회 이상이 활성 제한 확인 후 30초 안에 표시되고, 권한 거부·미지원에서는 제한
  동작만 안전하게 유지된다.
- 메인 앱 위치는 조정 가능 시점부터 30초 안에, extension-only 위치는 다음 foreground 조정 가능
  시점부터 30초 안에 반영된다.

## Shield·앱 내 해제

### 선행 실기기 게이트

1. T011·T032·T033으로 공유 attributes·system adapter·coordinator를 준비한 뒤 Shield Action
   extension에서 메인 앱이 시작한 ActivityKit 활동을 조회·갱신·종료하는 최소 probe를 지원 OS
   실기기에서 실행한다.
2. 성공·미지원·실패·timeout 결과와 OS 버전을 기록한다.
3. 성공이 재현된 환경만 직접 조정 경로를 활성화하고, 그 밖에는 앱 진입 또는 다음 foreground
   재조정을 기본 경로로 선택한다.

#### T039 실행 결과 (2026-09-04)

| 항목 | 결과 |
|------|------|
| 기기 | iPhone 17 (`iPhone18,3`) |
| OS | iOS 26.6.1 (23G83) |
| 빌드 | Debug, Family Controls·App Group entitlement가 적용된 실기기 서명 빌드 |
| 선행 상태 | 메인 앱이 만든 Live Activity 표시 후 제한 앱 Shield primary action 실행 |
| 조회 | `Activity<RestrictionLiveActivityAttributes>.activities`에서 앱 활동을 찾지 못함 |
| 갱신·종료 | 조회 실패로 실행하지 않음 |
| 최종 결과 | `unsupported` (`activityFound=false`, `updateVerified=false`, `endRequested=false`) |

Shield Action extension에서 앱이 만든 활동을 직접 열거하는 경로는 이 지원 OS 실기기에서 재현되지
않았다. T055 production 흐름에는 직접 ActivityKit adapter를 연결하지 않는다. 해제·차감 성공은
유지하고 iOS 26.5 이상에서는 `openParentalControlsApp`으로 앱에 진입한 뒤 foreground coordinator가
재조정하며, iOS 26.0~26.4에서는 다음 앱 foreground에서 재조정한다.

### 무료분

1. 당월 무료분이 아직 생성되지 않은 상태와 무료 해제권이 2회인 상태에서 각각 제한 앱 Shield를
   연다.
2. 기존 Shield 내용, `해제권 1회 사용`, `앱 닫기`를 확인하고 primary 버튼을 누른다.
3. 앱 내역과 CloudKit·App Group snapshot을 확인한다.

### 구매 코인

1. 무료분을 모두 사용하고 구매 코인을 준비한다.
2. 앱의 활성 제한 화면과 Shield에서 각각 해제를 실행한다.
3. 같은 occurrence의 버튼을 빠르게 반복하고 다른 기기에서도 동시에 요청한다.

### 실패·복구

1. reservation 뒤 App Group write, Managed Settings write, CloudKit commit을 각각 실패시킨다.
2. 각 지점에서 앱 또는 extension을 종료하고 다시 실행한다.
3. 무료분과 구매 코인이 모두 0인 `current` 장부에서 Shield 버튼을 누른다.
4. iCloud unavailable·장부 삭제 확정·재조정 중인 상태에서 같은 버튼을 누른다.
5. iOS 26.5 이상과 iOS 26.0~26.4 기기에서 잔액 부족·복구 route를 각각 실행한다.
6. 주입 시계와 CloudKit fake로 4.9초 성공, 정확히 5초까지 성공 미확인, 5초 초과 뒤 late commit을
   각각 실행한다.
7. `PendingAppRoute`를 생성 직후, 정확히 5분 경계, 5분 초과, 중복 소비, occurrence 종료 뒤 각각
   앱에서 소비한다.

기대 결과:

- 무료분이 구매 코인보다 먼저 사용된다.
- 버튼 하나가 무료 우선 사용과 무료분 소진 시 구매 코인 1개 fallback에 대한 동의로 동작한다.
- 당월 allowance가 없고 장부가 `current`이면 quota 2 생성과 첫 무료 사용이 한 command로 확정된다.
- 같은 occurrence는 최대 한 번만 해제·소모된다.
- 다른 규칙이 같은 앱을 제한하면 안내대로 Shield가 남는다.
- 실패한 해제는 확정 차감으로 남지 않고 보상되거나 `처리 확인 중`에서 재조정된다.
- 4.9초 안에 확인된 성공은 적용할 수 있지만 5초 안에 성공을 확인하지 못한 요청은 Shield를
  유지하고 상태 확인 route로 이동한다. 늦은 commit은 같은 command ID로 재조정돼 제한이 해제되지
  않았다면 최종 차감 0으로 수렴한다.
- `current` 장부의 잔액 부족만 coin store로 이동하며 iCloud·장부 불확실 상태는 결제를 시작하지
  않고 해당 복구 화면으로 이동한다.
- iOS 26.5 이상은 공식 응답으로 앱을 직접 열고, iOS 26.0~26.4는 Shield를 닫은 뒤 표시된 안내에
  따라 사용자가 앱을 열면 저장된 route가 소비된다.
- route는 생성 후 5분 이내의 활성 occurrence에서 한 번만 소비되고 만료·중복·종료 route는 이동 없이
  삭제된다.
- 해제 성공 직후 대표 Live Activity가 갱신되거나 모든 제한 종료 시 즉시 끝나며, ActivityKit 실패는
  이미 성공한 해제와 차감을 되돌리지 않는다.
- 재실행·재부팅 후 현재 occurrence 예외는 유지되고 다음 occurrence는 정상 제한된다.

## 개인정보·운영 점검

- CloudKit Dashboard, App Group 파일, diagnostics에서 좌표·앱 token이 장부에 포함되지 않았는지 확인한다.
- 최초 코인 기능 활성화와 매 구매 확인 전에 동일 iCloud 계정 요구, private 장부 삭제 시 구매
  잔액·내역·당월 무료분을 잃을 수 있음, 새 장부의 초기값과 서버 없는 복구·환불 한계가
  표시되는지 확인한다.
- App Store Connect의 IAP 계약·세금·상품 상태와 CloudKit production schema 배포를 확인한다.
- 실제 유료 판매 전에 서버 도입 재평가 조건과 지원 문의 대응 절차를 운영 문서에 기록한다.

## 완료 증적

| 영역 | 필수 증적 |
|------|-----------|
| 자동 테스트 | 전체 관련 test 통과, 실패·skip 0 또는 명시된 사유 |
| Live Activity | 적격 100회 시작 성공률 원시 결과, 위치 수신 주체별 기산·반영 시각, 남은 시간 60초 정확도·0 clamp, 대표 교체·즉시 종료 실기기 기록 |
| Shield 해제 | 선행 ActivityKit 실기기 probe, 무료·구매·다중 규칙·중복 tap, route 5분·일회 소비, 4.9초·5초·late commit과 실패 보상 기록 |
| StoreKit | local configuration 및 sandbox 거래 ID를 비식별화한 결과 |
| CloudKit | 같은 계정 두 기기 충돌, 로컬 빈 새 설치 복구, 월간 첫 앱·Shield 지연 생성, account switch 결과 |
| 지역화·접근성 | 한국어·영어, VoiceOver, Dynamic Type, Light/Dark 결과 |
| 한계 고지 | 최초 활성화·매 구매 전 iCloud 삭제 불이익과 서버 없는 복구/환불 문구 캡처 |

위 증적과 관련 자동 테스트가 모두 완료되기 전에는 기능을 완료로 표시하지 않는다.
