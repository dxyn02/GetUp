# 구현 계획: 제한 현황 Live Activity와 일회성 해제 코인

**기능 식별자**: `002-live-activity-coins` | **작성일**: 2026-09-02 | **명세**: [spec.md](spec.md)

**입력**: `/specs/002-live-activity-coins/spec.md`의 승인된 기능 명세

**상태**: 교차 산출물 분석 권장 조치 반영 완료

## 요약

기존 시간·위치 기반 제한에 읽기 전용 Live Activity, 현재 규칙 구간을 한 번 해제하는 월간 무료
해제권·구매 코인, StoreKit 2 소모성 인앱결제와 같은 iCloud 계정의 CloudKit 장부를 추가한다.

메인 앱은 foreground에서 활성 제한을 확인할 때 대표 규칙 하나의 Live Activity를 시작·조정한다.
시간은 시스템 동적 날짜로 표시하고 거리는 기존 위치 이벤트나 앱 실행 시 얻은 신뢰 가능한 값만
갱신한다. 새 Widget Extension은 표시만 담당하며 코인 행동은 제공하지 않는다.

코인 계층은 StoreKit 검증 거래, CloudKit private custom zone의 비교 후 교환 잔액·월간 버킷,
추가 전용 장부 이벤트를 사용한다. 해제는 CloudKit reservation과 App Group 해제 예외·Shield 합집합
재평가를 조정하는 명령으로 처리한다. Shield와 앱은 동일한 해제 서비스를 사용하며 무료분을 먼저
소모한다. 로컬 코인 데이터가 없는 재설치·새 기기는 동일 iCloud의 `current` 장부를 초기 fetch해
검증된 미사용 잔액과 내역을 복구한다. 원격 장부와 삭제 증거가 모두 없는 최초 활성화는
`setupRequired`, 삭제 증거가 있는 경우는 `deletionConfirmed`, 일시적 불확실성은 `stale` 또는
`unavailable`로 분리해 서로 다른 생성·복구·잠금 정책을 적용한다.
Shield 요청은 5초 안에 성공을 확인하지 못하면 제한을 유지하고 재조정한다. 월간 무료분은 새달 첫
앱 실행 또는 Shield 요청에서 지연 생성한다. 초기 범위에는 앱 서버·push-to-start·App Store Server
Notifications가 없다.

## 기술 컨텍스트

**언어/버전**: Swift 6.0, strict concurrency complete, Xcode 26 계열

**주요 의존성**: SwiftUI, Observation, ActivityKit, WidgetKit, StoreKit 2, CloudKit,
FamilyControls, ManagedSettings, ManagedSettingsUI, DeviceActivity, CoreLocation, Foundation;
외부 패키지 없음

**저장소**: 기존 App Group의 버전 있는 Codable JSON snapshot과 보호된 atomic write;
CloudKit private database의 `CoinLedgerZone`; CKSyncEngine 로컬 mirror; StoreKit 거래는 구매 증명

**테스트**: Swift Testing 도메인·저장소·조정 테스트, XCTest UI·확장·성능 테스트,
StoreKit Configuration과 StoreKit Test, CloudKit adapter fake·sandbox, ActivityKit preview·Simulator,
실기기 Shield·Live Activity·위치·다기기 iCloud 인수 테스트

**대상 플랫폼**: iPhone, iOS 26 이상; Shield에서 앱을 직접 여는 공식 응답은 iOS 26.5 이상;
실제 Screen Time, Live Activity, StoreKit sandbox,
iCloud 다기기 및 background 위치 이벤트 검증에는 물리 기기 필요

**프로젝트 유형**: SwiftUI iOS 앱 + 기존 Device Activity Monitor·Shield Configuration·Shield
Action 확장 + 새 Widget/Live Activity 확장

**성능 목표**: 지원 기기·권한 허용·유효한 활성 제한·foreground 조건의 100회 중 95회 이상에서
활성 제한 확인 후 30초 이내 Live Activity 시작; 메인 앱이 신뢰 위치를 받고 ActivityKit 조정이
가능해진 뒤 30초 이내 거리 반영; Shield CloudKit 성공 확인은 최대 5초; 동시 해제 100회에서 최대
1회 소모; 구매 거래 100회 중복 전달에서 1회 지급; 월별·계정별 무료분 최대 2회; 주입 시계 기준
남은 시간 오차 최대 60초와 종료 후 0 clamp; UI 상호작용은 main actor를 막지 않음

**제약**: 앱 서버·APNs push-to-start·App Store Server Notifications 없음; Live Activity 시작은
foreground 확인 기준; 지속 background location update 없음; 코인 지급·사용은 iCloud와 네트워크를
확인할 수 있을 때만 가능; 무료분은 `Asia/Seoul` 월 기준 비이월; 구매 코인은 만료 없음; 장부가
`current`는 iCloud 사용 가능, 현재 프로세스 초기 fetch 완료, 주입 monotonic clock 기준 5분 이내
성공 fetch, epoch·projection 일치, 미해결 reconciliation 없음의 교집합이며 프로세스 재시작 시
재사용하지 않고 구매·해제 직전 서버 재확인 필수; `current`가 아니면 구매
시작 금지; 구매 계정과 iCloud 계정 불일치·private zone 삭제·앱 비실행 중
환불 지연을 코인 기능 활성화와 구매 확정 전에 고지; 삭제 확인 시 사용자 동의 전 코인 기능 잠금;
Shield는 5초 안에 성공이 확인되지 않으면 제한 유지; 월 1일 00:00 background 실행 보장 없음;
위치 좌표와 Family Controls token은 CloudKit·StoreKit·로그에 기록하지 않음

**규모/범위**: 기기 소유자 1명과 같은 iCloud 계정의 소수 기기, 여러 활성 규칙, 대표 Live
Activity 1개, 월간 무료 해제권 2회, 코인 1개·3개·5개의 consumable 코인 팩 세 개,
개인 장부와 자신의 규칙 해제만 지원

## 헌법 점검

*게이트: Phase 0 조사 전과 Phase 1 설계 후 모두 통과해야 한다.*

| 원칙 | 사전 점검 | 설계 근거 및 필수 조치 |
|------|-----------|------------------------|
| I. 명세 기반 구현 | PASS | BLK-013·BLK-014와 DEC-071~DEC-077로 대표 규칙, 사용 표면, iCloud 복구·삭제, 월 정책, 상품 catalog, Shield 해제·앱 진입, 5초 timeout과 서버 없는 경계를 명세에 반영했다. 모든 계약은 FR·SC를 역추적한다. |
| II. 핵심 비즈니스 로직 테스트 | PASS | 대표 규칙 선택, 거리·남은 시간 상태, 무료 우선 차감, 월 경계, 구매·사용 멱등성, CloudKit 충돌, 해제 보상 전이와 PendingAppRoute의 5분·일회 소비·종료 구간 폐기를 순수 로직과 adapter fake로 검증한다. |
| III. 구조 변경 문서화 | PASS | 새 Widget Extension, ActivityKit coordinator, StoreKit adapter, CloudKit zone·장부, App Group 해제 예외의 책임과 흐름을 `research.md`, `data-model.md`, `contracts/`에 기록한다. |
| IV. 완료 전 테스트 게이트 | PASS | 자동 테스트, StoreKit sandbox, CloudKit 다기기, Simulator preview, 실기기 Shield·Live Activity 인수 결과가 모두 기록되기 전에는 기능 완료로 표시하지 않는다. |

**사전 설계 게이트 결과**: PASS. Phase 0에서 발견한 플랫폼·운영 충돌은 BLK-014로 기록하고 사용자
결정 후 해결했다.

**설계 후 재점검**: PASS.

- ActivityKit·StoreKit·CloudKit을 protocol adapter 뒤에 두어 도메인 테스트를 결정적으로 만든다.
- CloudKit 잔액 변경과 장부 이벤트는 custom zone 원자적 저장 및 change-tag 비교로 동시성을 다룬다.
- CloudKit reservation, App Group 해제 예외, Managed Settings 재평가 사이의 실패는 명시적
  보상·재조정 상태로 남겨 유료 재화 유실을 방지한다.
- 서버 없는 보안·복구 한계를 명세와 구매 전 UI 계약에 노출하며 이를 구현 완료 조건으로 둔다.

## 프로젝트 구조

### 이 기능의 문서

```text
specs/002-live-activity-coins/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── live-activity-contract.md
│   ├── coin-ledger-contract.md
│   ├── purchase-contract.md
│   ├── rule-release-contract.md
│   └── shield-coin-ui-contract.md
└── tasks.md                 # $speckit-tasks에서 생성
```

### 소스 코드

```text
GetUp.xcodeproj/
Configuration/

GetUp/
├── App/
├── Features/
│   ├── RestrictionStatus/
│   └── Coins/
├── Core/
│   ├── Models/
│   ├── Evaluation/
│   ├── StateMachine/
│   └── Contracts/
├── Infrastructure/
│   ├── ActivityKit/
│   ├── CloudKit/
│   ├── StoreKit/
│   ├── Persistence/
│   └── ScreenTime/
└── Resources/

GetUpLiveActivity/             # 새 Widget Extension
├── GetUpLiveActivityBundle.swift
├── RestrictionLiveActivity.swift
├── Info.plist
├── GetUpLiveActivity.entitlements
└── Resources/

GetUpDeviceActivityMonitor/
GetUpShieldConfiguration/
GetUpShieldAction/

GetUpTests/
├── Core/
├── Persistence/
├── Integration/
└── StoreKit/

GetUpUITests/
design/
docs/
```

**구조 결정**: 하나의 Xcode 프로젝트 안에 기존 앱·세 Screen Time 확장과 Widget Extension 하나를
둔다. `ActivityAttributes`, 장부·해제 모델과 protocol 계약은 필요한 타깃이 공유할 수 있는
`GetUp/Core` 소스로 유지한다. 시스템 framework 접근은 Infrastructure adapter로 격리한다.
CloudKit이 권위 있는 계정 범위 장부이며 App Group은 Shield와 Device Activity가 빠르게 읽는 로컬
mirror·해제 예외를 보관한다. 별도 서버와 외부 패키지는 도입하지 않는다.

## 구현 단계

### 1. 공유 도메인과 저장 계약

- 활성 규칙 구간, 대표 규칙 선택, Live Activity content state, 거리 표시 상태를 도메인 모델로 둔다.
- 무료 버킷, 구매 잔액, 장부 이벤트, 구매 지급, 해제 명령·reservation·예외 상태를 추가한다.
- App Group snapshot schema를 올리고 이전 001 데이터는 그대로 읽으며 새 필드 부재를 빈 코인·예외
  상태로 migration한다.
- CloudKit과 StoreKit, ActivityKit, release persistence를 protocol로 추상화한다.
- 월 ID·quota 2·비이월 정책, 새달 첫 상호작용의 지연 생성과 Shield의 allowance 생성+무료 1회
  reservation 원자성을 공통 기반에서 구현한다. 이 최소 기반이 완료되기 전에는 Shield·앱 코인
  해제를 구현하지 않는다.
- `PendingAppRoute` repository는 생성 후 5분, 활성 occurrence 일치, 미소비 조건을 한 정책으로
  평가하고 성공 시 한 번만 소비하며 만료·중복·종료된 route를 atomic하게 삭제한다.

### 2. Live Activity 표시

- Widget Extension과 app target에 ActivityKit capability·`NSSupportsLiveActivities`를 구성한다.
- foreground 제한 조정 coordinator가 가장 먼저 활성화된 규칙을 대표로 선택하고 활동 1개를
  request/update/end한다.
- 종료 예정 시각은 동적 카운트다운으로 렌더링하고 거리 stale은 `확인 불가`로 표시한다.
- 종료 예정 시각은 주입 시계 기반 policy에서 0으로 clamp하고, 종료 전·경계·종료 후 표시 오차가
  60초를 넘지 않는 자동 테스트를 UI 구현 전에 통과시킨다.
- 남은 거리는 기존 위치 판정이 `.inside`인 5분 이내 근거만 사용해 10m 단위·미터로 표시한다.
- 앱 복귀 때 `Activity.activities`와 공유 제한 snapshot을 멱등 조정한다. 사용자가 활동을 제거해
  activity가 없더라도 활성 제한이 남아 있으면 같은 occurrence에서 다시 request한다.
- 시작 성능은 지원 기기·권한 허용·유효한 활성 제한·foreground 사례만 모집단으로 삼고, 활성 제한
  확인 시점부터 측정한다. 거리 갱신은 메인 앱이 신뢰 위치를 받아 ActivityKit 조정이 가능해진
  시점부터 측정하며 extension-only 위치는 저장 후 다음 foreground 조정에서 반영한다.

### 3. CloudKit 장부와 월간 무료분

- private database의 `CoinLedgerZone`과 고정 account record, 월별 allowance, 이벤트, 구매,
  release command record를 생성한다.
- `ifServerRecordUnchanged`와 atomic modify로 무료 우선 reservation을 만들고 충돌 시 최신 서버
  record로 다시 평가한다.
- CKSyncEngine local mirror, account change 격리, pending change 재시도와 App Group 읽기 snapshot을
  연결한다.
- `current`는 iCloud 계정 사용 가능, 현재 프로세스의 private database 초기 fetch 완료, 주입 가능한
  monotonic clock 기준 마지막 성공 fetch 이후 5분 이내,
  `LedgerEpoch`·`CoinAccount`·mirror epoch 일치, fetch된 지급·사용·보정 projection 완료, 미해결
  release reconciliation 없음이 모두 성립할 때만 부여한다. 구매·해제 직전 서버 record를 다시
  확인하고 monotonic 경과 시간이 5분을 넘으면 `stale`로 전환한다. wall-clock `syncedAt`은 표시·
  진단에만 사용하며 프로세스가 다시 시작되면 새 fetch 전까지 `current`로 복원하지 않는다.
- `Asia/Seoul` 월 ID와 서버 `creationDate` 검증으로 월간 2회를 한 번만 생성한다. 매월 1일 자정의
  background 실행을 예약하지 않고 새달의 첫 앱 실행 또는 Shield 요청에서 지연 생성한다. Shield가
  첫 요청이면 생성과 무료 1회 reservation을 같은 atomic command로 처리한다.
- `userDeletedZone` 또는 기존 동기화 흔적 뒤 zone 부재를 삭제 확인 상태로 구분해 코인 기능을
  잠근다. 사용자 확인 후 새 ledger epoch를 0 잔액·현재 월 quota 0으로 만들고 다음 월부터 2회를
  재개한다.
- 초기 fetch 뒤 원격 장부와 삭제 증거가 모두 없으면 `setupRequired`로 두고, US3의
  `CoinLedgerSetupService`가 최초 활성화 고지와 action 확인 뒤 initial epoch와 현재 월 quota 2를
  하나의 원자적 명령으로 생성한다. `CoinLedgerResetService`와 API·상태 전이를 분리한다. 기존
  `current` 장부는 그대로 복구하고,
  삭제가 확인된 장부만 0 reset 정책을 적용한다. 서버 없는 새 설치가 원격 장부와 삭제 증거를 모두
  잃은 경우를 완전히 구분할 수 없는 한계는 최초 활성화·구매 전 고지한다.

### 4. StoreKit 구매와 복구

- 1개·3개·5개 consumable 상품을 조회해 현지 가격을 표시하고 검증 성공 거래만 결정적 구매
  이벤트로 지급한다.
- iCloud 계정·CloudKit 초기 sync·pending reconciliation이 모두 정상인 `current` 상태에서만 구매
  버튼을 활성화하고, 그 외에는 `Product.purchase()`를 호출하지 않는다.
- 장부 commit 뒤 transaction을 finish하고 `Transaction.updates`·unfinished 거래를 앱 수명주기에서
  처리한다.
- 앱에서 확인한 환불·철회는 역분개 이벤트로 반영하고 0 미만 잔액은 만들지 않는다.
- 로컬 코인 데이터가 없는 재설치·새 기기에서는 동일 iCloud 계정의 private zone을 초기 fetch하고,
  현재 `LedgerEpoch`와 모든 검증된 PurchaseGrant·사용·보정 내역이 `current`로 수렴한 경우에만
  미사용 구매 잔액과 내역을 복구한다. 원격 장부·삭제 증거가 없는 최초 활성화는 `setupRequired`,
  삭제 확인은 `deletionConfirmed`, 그 밖의 불확실 상태는 재시도로 보내며 로컬 mirror나 StoreKit
  내역만으로 복원하지 않는다.
- 코인 기능 최초 활성화와 구매 확정 전에 동일 iCloud 계정 유지, 장부 삭제 시 잔액·현재 월 무료분
  복구 불가, 서버 없는 환불 지연 한계를 표시한다.
- 소모성 코인의 이 흐름은 `구매 복원`이 아니라 `iCloud 잔액 동기화` 또는 `iCloud 잔액 복구`로
  지역화한다.

### 5. 규칙 1회 해제와 Shield

- US1의 공유 attributes·system adapter·coordinator 구현이 완료된 뒤 Shield Action extension이 메인
  앱에서 시작한 ActivityKit 활동을 직접 조회·갱신·종료할 수 있는지 지원 OS별 실기기 probe로
  확인하고 증적을 남긴다. 성공한 경로만 직접 조정에 사용하며,
  미지원·실패·timeout이면 앱 진입 또는 다음 foreground 재조정을 기본 경로로 확정한다. 이 게이트를
  통과하기 전에는 직접 ActivityKit 조정 코드를 제품 흐름에 연결하지 않는다.
- Shield와 앱의 해제 요청을 동일한 command service에 전달한다.
- Shield에는 기존 제한 정보·닫기 행동과 `해제권 1회 사용` 버튼을 제공한다. 이 버튼은 최신 장부에서
  현재 월 무료분을 확인·생성한 뒤 무료분을 우선 사용하고, 없을 때 구매 코인 1개를 사용하는 데 대한
  명시적 확정이다.
- CloudKit reservation이 성공한 뒤 App Group에 규칙 구간 예외를 기록하고 현재 활성 규칙 합집합을
  다시 계산한다. 실패 시 보상 이벤트 또는 pending reconciliation으로 잔액 유실을 막는다.
- Shield Action은 주입 가능한 연속 시계로 CloudKit 성공 확인을 최대 5초 기다린다. 5초 안에 성공을
  확인하지 못하면 예외를 적용하지 않고 제한을 유지하며 reconciliation route를 기록한다. 늦게
  완료되거나 결과가 불명확한 같은 command는 서버 상태를 조회해 미적용 reservation을 보상한다.
- 제한 read-back 성공 뒤 앱이 foreground이면 Live Activity 대표를 교체하거나 종료한다. ActivityKit
  실패는 해제·장부 commit을 취소하지 않는 비치명적 실패로 기록한다.
- Shield는 가장 먼저 활성화된 대표 규칙, 무료 우선·없으면 구매 코인 1개라는 비용 순서, 구간 종료
  시각과 겹친 규칙으로 남는 제한을 버튼 전에 표시한다. 실제 funding source는 tap 뒤 최신 장부에서
  결정하고 버튼 label 자체를 명시적 확정으로 사용한다.
- 해제 예외는 다음 반복 구간에 적용하지 않으며 종료 후 정리한다.
- 최신 장부가 정상이고 잔액만 부족하면 App Group에 구매 화면 route를 기록한 뒤 iOS 26.5 이상에서
  `openParentalControlsApp`으로 앱을 연다. 장부 불가 상태는 복구 route로 분리한다. iOS 26.0~26.4는
  안내 후 차단 앱을 닫는 공식 fallback을 사용하고 비공개 URL 우회는 사용하지 않는다.
- 앱은 `PendingAppRoute`를 생성 후 5분 이내이고 연결 occurrence가 여전히 활성이며 아직 소비되지
  않았을 때만 한 번 사용한다. 소비 성공과 폐기는 atomic하게 처리하고 만료·중복·종료 route는
  목적지 이동 없이 삭제한다.

### 6. 검증과 출시 준비

- 한국어·영어 String Catalog, VoiceOver, Dynamic Type, Light/Dark, Lock Screen·Dynamic Island
  preview를 검증한다.
- StoreKit Configuration과 sandbox 구매, CloudKit development 환경·다기기 충돌, iCloud sign-out,
  동일 iCloud 새 설치 복구, 장부 삭제·명시적 0 초기화·다음 달 첫 상호작용 무료 지급 재개,
  Shield의 5초 성공·timeout·늦은 commit 재조정을 검증한다.
- Live Activity 시작 100회 모집단과 30초 기준 시점, 메인 앱 위치 수신 후 30초 갱신,
  extension-only 위치의 다음 foreground 반영을 기존 전용 테스트에서 자동 계측하고, 마감 단계는
  그 결과를 중복 구현하지 않고 집계·보고한다. 남은 시간 60초 정확도와 0 clamp도 함께 보고한다.
- iOS 26.5의 `openParentalControlsApp` 구매·복구 route와 iOS 26.0~26.4 fallback을 각각 실기기에서
  검증한다.
- 실제 유료 판매 전 App Store Connect 상품·세금·계약·가격, iCloud container production schema,
  privacy disclosure와 서버 없는 한계 문구를 검토한다.

## 복잡성 추적

헌법 위반은 없다. 새 Widget Extension은 Live Activity UI를 제공하는 플랫폼 필수 경계다.
CloudKit custom zone과 reservation 상태 머신은 유료 재화의 여러 기기 동시 사용 및 Shield 적용 실패
시 유실을 막기 위해 필요하다. 단순 잔액 파일은 동일 요구사항을 안전하게 충족하지 못한다.
