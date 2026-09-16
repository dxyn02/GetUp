---

description: "제한 현황 Live Activity와 일회성 해제 코인 구현 작업 목록"
---

# 작업: 제한 현황 Live Activity와 일회성 해제 코인

**입력 문서**: `/specs/002-live-activity-coins/`의 `spec.md`, `plan.md`, `research.md`,
`data-model.md`, `contracts/`, `quickstart.md`

**테스트 원칙**: 프로젝트 헌법에 따라 핵심 비즈니스 로직의 정상·경계·실패 경로 테스트를 구현보다
먼저 작성하고 실패를 확인한다. 각 단계 완료 전에 관련 자동 테스트를 통과시킨다.

**구성 원칙**: 사용자 스토리별로 독립 구현·검증할 수 있도록 구성한다. 공통 모델과 CloudKit/App
Group 경계뿐 아니라 US2의 무료 우선 해제에 필수인 월 계산·무료분 생성·원자적 예약 최소 기반도
Phase 2에 둔다. US4에는 잔액 UI·지역화·월 경계 인수 검증만 남긴다.

## 형식: `[ID] [P?] [Story?] 설명과 파일 경로`

- **[P]**: 선행 작업 완료 후 다른 파일에서 병렬 진행 가능
- **[US1]~[US4]**: 명세의 사용자 스토리 식별자
- 각 작업은 하나의 논리적 변경 단위로 구현·검증·커밋한다.

---

## Phase 1: 설정 및 타깃 구성

**목적**: Live Activity, CloudKit, StoreKit을 빌드할 수 있는 프로젝트·capability 기반을 만든다.

- [X] T001 `GetUpLiveActivity/` Widget Extension target과 앱 embed dependency를 `GetUp.xcodeproj/project.pbxproj`에 추가한다.
- [X] T002 [P] Live Activities 지원과 App Group을 `GetUp/Resources/Info.plist`, `GetUp/GetUp.entitlements`, `GetUpLiveActivity/Info.plist`, `GetUpLiveActivity/GetUpLiveActivity.entitlements`에 구성한다.
- [X] T003 CloudKit container와 iCloud capability를 `GetUp/GetUp.entitlements`, `GetUpShieldAction/GetUpShieldAction.entitlements`, `Configuration/Base.xcconfig`에 구성한다.
- [X] T004 코인 1개·3개·5개 상품의 build setting key와 허용 catalog 설정을 `Configuration/Base.xcconfig`, `GetUp/Resources/Info.plist`에 추가한다.
- [X] T005 [P] 코인 1개·3개·5개 consumable의 product ID, 표시명, 테스트 가격과 판매 상태를 `Configuration/GetUp.storekit`에 구성한다.
- [X] T006 새 Widget Extension과 StoreKit configuration을 공용 scheme·test plan에 연결하고 `GetUp.xcodeproj/xcshareddata/xcschemes/GetUp.xcscheme`, `GetUp.xctestplan`에서 target 목록을 검증한다.

**체크포인트**: 앱과 기존 세 Screen Time 확장, 새 Widget Extension이 코드 서명 없이 Simulator용으로 빌드된다.

---

## Phase 2: 공통 기반

**목적**: 모든 사용자 스토리가 공유하는 모델, 저장 계약, CloudKit 원자성, 테스트 대역을 구축한다.

**⚠️ 중요**: 이 단계가 완료되기 전에는 사용자 스토리 구현을 시작하지 않는다.

### 기반 테스트

- [X] T007 [P] occurrence·Live Activity·코인·해제 모델의 Codable, 불변 조건과 `current`의 monotonic 5분 freshness·프로세스 재시작·wall clock 변경 무관성·epoch/projection 일치·pending reconciliation 차단 및 월 ID·quota 2·비이월·첫 앱 지연 생성 실패 테스트를 `GetUpTests/Core/LiveActivityCoinModelTests.swift`, `GetUpTests/Core/MonthlyAllowancePolicyTests.swift`, `GetUpTests/Core/MonthlyAllowanceServiceTests.swift`에 작성한다.
- [X] T008 [P] 활성 occurrence·잔액 mirror·해제 예외의 file migration·atomic write·손상 schema와 `PendingAppRoute`의 생성 직후·정확히 5분·5분 초과·일회 소비·중복·종료 occurrence 폐기 테스트를 `GetUpTests/Persistence/LiveActivityCoinSnapshotRepositoryTests.swift`, `GetUpTests/Persistence/PendingAppRouteRepositoryTests.swift`에 작성한다.
- [X] T009 [P] CloudKit record 매핑, change-tag 충돌, atomic modify, timeout 결과 불명·결정적 ID와 allowance 생성+무료 1회 reservation의 단일 atomic modify·다기기 충돌 테스트를 `GetUpTests/Integration/CloudKitCoinLedgerRepositoryTests.swift`, `GetUpTests/Integration/CloudKitMonthlyAllowanceTests.swift`에 작성한다.

### 기반 구현

- [X] T010 [P] `RestrictionOccurrence`와 `ActiveRestrictionSnapshot` 모델 및 결정적 occurrence ID 생성을 `GetUp/Core/Models/RestrictionOccurrenceModels.swift`에 구현한다.
- [X] T011 [P] 4KB 미만 payload의 `RestrictionLiveActivityAttributes`와 거리 표시 상태를 `GetUp/Core/Models/RestrictionLiveActivityModels.swift`에 구현한다.
- [X] T012 [P] `LedgerEpoch`, `CoinAccount`, `MonthlyAllowance`, `PurchaseGrant`, `CoinLedgerEvent`와 `setupRequired`를 포함한 `CoinBalanceSnapshot` 상태를 `GetUp/Core/Models/CoinLedgerModels.swift`에 구현한다.
- [X] T013 [P] `ReleaseCommand`, funding source·5초 timeout 후 재조정 상태 전이, `ReleaseException`, `PendingAppRoute`를 `GetUp/Core/Models/RuleReleaseModels.swift`에 구현한다.
- [X] T014 ActivityKit·CloudKit·StoreKit·장부·해제 예외의 Sendable protocol과 안정 오류 코드를 `GetUp/Core/Contracts/LiveActivityCoinContracts.swift`에 정의한다.
- [X] T015 [P] App Group 파일명, CloudKit zone·record ID, 상품 catalog key를 `GetUp/Core/Configuration/SharedIdentifiers.swift`에 추가한다.
- [X] T016 활성 occurrence·잔액 mirror·해제 예외 repository, 기존 001 snapshot 비파괴 migration과 유효기간·활성 occurrence·미소비를 한 번에 검사해 성공 소비 또는 stale route 폐기를 atomic 수행하는 `PendingAppRouteRepository`를 `GetUp/Infrastructure/Persistence/SharedSnapshotRepository.swift`에 구현한다.
- [X] T017 [P] CloudKit record codec과 위치·Family Controls token 차단 검증을 `GetUp/Infrastructure/CloudKit/CoinLedgerRecordMapper.swift`에 구현한다.
- [X] T018 `ifServerRecordUnchanged` atomic modify, 결정적 event ID, 충돌·결과 불명 재조회와 allowance+freeGrant+무료 1회 reservation+ReleaseCommand 단일 저장이 포함된 장부 repository를 `GetUp/Infrastructure/CloudKit/CloudKitCoinLedgerRepository.swift`에 구현한다.
- [X] T019 account switch 격리, 로컬 빈 설치의 원격 장부 우선 fetch와 최초 `setupRequired`·기존 `current`·삭제 `deletionConfirmed` 구분, 비영속 `CoinLedgerSyncSession`의 monotonic 5분 freshness·프로세스 재시작·epoch/projection·reconciliation gate를 관리하는 동기화 adapter를 `GetUp/Infrastructure/CloudKit/CoinLedgerSyncAdapter.swift`에 구현한다.
- [X] T020 [P] ActivityKit·CloudKit·StoreKit·release 실패, current freshness의 monotonic 경과·wall clock 변경·프로세스 재시작과 Shield 4.9초·5초·late commit을 결정적으로 주입하는 clock fake와 fixture를 `GetUpTests/Support/LiveActivityCoinFixtures.swift`에 구현한다.
- [X] T021 서울 기준 monthID·quota 2·비이월·삭제 월 quota 0의 `MonthlyAllowancePolicy`와 기존 initial ledger의 새달 지연 생성·Shield 생성+예약 원자 명령을 담당하는 `MonthlyAllowanceService`를 `GetUp/Core/Evaluation/MonthlyAllowancePolicy.swift`, `GetUp/Core/StateMachine/MonthlyAllowanceService.swift`에 구현하고 첫 app foreground trigger와 공통 service·repository를 `GetUp/App/AppLifecycleCoordinator.swift`, `GetUp/App/DependencyContainer.swift`, `GetUp.xcodeproj/project.pbxproj`에 조립한 뒤 기반 테스트를 통과시킨다. `setupRequired` initial ledger 생성은 T072의 별도 setup service에 위임한다.

**체크포인트**: 공통 모델·저장·CloudKit adapter를 fake로 독립 실행할 수 있고 기존 001 snapshot을 그대로 읽으며, 월 정책·무료분 생성·Shield 원자 예약과 PendingAppRoute 일회 소비가 US2 전에 검증된다.

---

## Phase 3: 사용자 스토리 1 — 제한 상태와 남은 해제 조건 확인 (Priority: P1) 🎯 MVP

**목표**: foreground에서 대표 활성 규칙 하나의 남은 시간·거리 Live Activity를 시작·갱신·종료한다.

**독립 테스트**: 코인·StoreKit·월간 무료분 없이 규칙을 활성화해 foreground 시작, 거리 갱신,
대표 교체, 수동 제거 후 재생성, 모든 제한 종료를 검증한다.

### 사용자 스토리 1 테스트

- [X] T022 [P] [US1] 대표 occurrence의 `activatedAt`·`startAt`·`ruleID` 정렬과 대표 교체 테스트를 `GetUpTests/Core/RestrictionOccurrenceEvaluatorTests.swift`에 먼저 작성한다.
- [X] T023 [P] [US1] 기존 위치 평가가 `.inside`이고 5분 이내일 때만 `max(0, radius - centerDistance)`를 항상 미터·10m 단위 half-up으로 표시하며 5m 경계·0 clamp·stale·unavailable을 검증하는 테스트를 `GetUpTests/Core/LiveActivityDistancePolicyTests.swift`에 먼저 작성한다.
- [X] T024 [P] [US1] foreground 시작, background 미시작, 중복 조정, 수동 제거 후 재생성, 즉시 종료, ActivityKit 실패 격리와 주입 시계의 종료 전·경계·종료 후 남은 시간 오차 60초 이내·0 clamp 테스트를 `GetUpTests/Integration/LiveActivityCoordinatorTests.swift`, `GetUpTests/Core/LiveActivityTimePolicyTests.swift`에 먼저 작성한다.
- [X] T025 [P] [US1] 지원·권한 허용·활성 제한·foreground 100회 중 95회 이상이 활성 확인 뒤 30초 안에 표시되고 권한 거부·미지원은 제한 기능에 영향을 주지 않는 계측 테스트를 `GetUpTests/Performance/LiveActivityStartMeasurementTests.swift`에 먼저 작성한다.
- [X] T026 [P] [US1] 메인 앱의 신뢰 위치 수신 기산점과 extension-only 근거 저장 후 다음 foreground 기산점부터 각각 30초 안에 거리가 반영되는 테스트를 `GetUpTests/Integration/LiveActivityLocationBridgeTests.swift`에 먼저 작성한다.
- [X] T027 [P] [US1] Lock Screen·Dynamic Island minimal·compact·expanded의 known·unavailable·다중 규칙 preview fixture를 `GetUpLiveActivity/RestrictionLiveActivityPreviews.swift`에 먼저 작성한다.

### 사용자 스토리 1 구현

- [X] T028 [P] [US1] 대표 occurrence 선택과 종료·revision 불일치 정리를 `GetUp/Core/Evaluation/RestrictionOccurrenceEvaluator.swift`에 구현한다.
- [X] T029 [P] [US1] 기존 `LocationEvidenceEvaluator`의 `.inside` 결과와 5분 유효기간을 재사용하고 남은 거리를 항상 미터·10m 단위 half-up으로 만드는 좌표 없는 content state를 `GetUp/Core/Evaluation/LiveActivityContentPolicy.swift`에 구현한다.
- [X] T030 [US1] 제한 적용 결과에서 활성 occurrence snapshot을 결정적으로 기록하도록 `GetUp/Infrastructure/ScreenTime/RestrictionCoordinator.swift`를 확장한다.
- [X] T031 [US1] 앱 비실행 callback에서는 occurrence만 갱신하고 ActivityKit을 호출하지 않도록 `GetUpDeviceActivityMonitor/DeviceActivityMonitorExtension.swift`를 연결한다.
- [X] T032 [P] [US1] request·update·end·authorization 조회를 감싸는 system adapter를 `GetUp/Infrastructure/ActivityKit/SystemLiveActivityAdapter.swift`에 구현한다.
- [X] T033 [US1] 대표 활동 하나를 멱등 조정하고 수동 제거를 suppression 없이 재생성하는 `GetUp/Infrastructure/ActivityKit/LiveActivityCoordinator.swift`를 구현한다.
- [X] T034 [US1] 앱 launch·foreground 복구와 신뢰 가능한 기존 위치 근거 변경 시 Live Activity를 조정하도록 `GetUp/App/AppLifecycleCoordinator.swift`, `GetUp/App/GetUpApp.swift`를 연결한다.
- [X] T035 [US1] extension-only 위치 근거를 App Group에 저장하고 다음 foreground에서 소비하되 extension에서는 ActivityKit을 직접 호출하지 않도록 `GetUp/Infrastructure/Persistence/SharedSnapshotRepository.swift`, `GetUp/App/AppLifecycleCoordinator.swift`를 연결한다.
- [X] T036 [US1] 0 clamp된 `endsAt` content policy를 사용해 Lock Screen과 Dynamic Island UI에 규칙명·60초 이내 동적 카운트다운·거리·추가 제한만 표시하도록 `GetUpLiveActivity/GetUpLiveActivityBundle.swift`, `GetUpLiveActivity/RestrictionLiveActivity.swift`를 구현한다.
- [X] T037 [US1] 한국어·영어 Live Activity 문자열과 VoiceOver label을 `GetUp/Resources/Localizable.xcstrings`, `GetUpLiveActivity/Resources/Localizable.xcstrings`에 추가한다.
- [X] T038 [US1] 새 US1 파일의 target membership을 `GetUp.xcodeproj/project.pbxproj`에 연결하고 `GetUpTests/Integration/LiveActivityCoordinatorTests.swift` 및 Widget Extension 빌드를 통과시킨다.

**체크포인트**: US1은 코인 기능 없이 독립적으로 시연·검증 가능하다.

---

## Phase 4: 사용자 스토리 2 — 코인으로 현재 규칙 1회 해제 (Priority: P1)

**목표**: Shield 또는 앱에서 선택한 현재 occurrence를 무료분 또는 구매 코인 하나로 정확히 한 번
해제하고, 실패 시 차감을 보상한다.

**독립 테스트**: fake CloudKit 장부에 무료 또는 구매 잔액을 주입해 앱·Shield에서 해제하고 같은
occurrence만 예외 처리되는지, 중복 100회에서 최대 1회만 소모되는지 검증한다.

### 사용자 스토리 2 테스트

- [X] T039 [US2] T011·T032·T033 완료 후 DEBUG 전용 `GetUpShieldAction/ActivityKitFeasibilityProbe.swift`를 추가·target 연결해 Shield Action extension이 메인 앱에서 시작한 Live Activity를 직접 조회·갱신·종료할 수 있는지 지원 OS 실기기에서 실행하고 성공·미지원·실패·timeout 결과를 `specs/002-live-activity-coins/quickstart.md`, `docs/STATUS.md`에 기록해 직접 조정 또는 foreground fallback을 확정한다.
- [X] T040 [P] [US2] 무료 우선·구매 fallback·잔액 부족·비`current`·epoch 불일치 reservation, 같은 occurrence 100회 요청과 requested→reserved→applied→committed·보상·결과 불명 전이 테스트를 `GetUpTests/Core/CoinReservationPolicyTests.swift`, `GetUpTests/Core/RuleReleaseServiceTests.swift`에 먼저 작성한다.
- [X] T041 [P] [US2] 예외의 재실행·재부팅 유지, 만료·revision 불일치 정리, 다음 occurrence 미적용 테스트를 `GetUpTests/Persistence/ReleaseExceptionRepositoryTests.swift`에 먼저 작성한다.
- [X] T042 [P] [US2] App Group write·Managed Settings write·CloudKit commit 각 실패 지점의 보상, 성공 직후 대표 Live Activity 갱신·종료와 ActivityKit 실패 비치명 처리를 `GetUpTests/Integration/RuleReleaseCoordinatorTests.swift`에 먼저 작성한다.
- [X] T043 [P] [US2] 단일 `해제권 1회 사용` 버튼의 무료 우선·구매 fallback, 잔액 부족 coin store route, stale·삭제·조정 중 장부의 recovery route, 다중 규칙과 iOS 26.5·이전 호환 응답 테스트를 `GetUpTests/Integration/ShieldCoinActionTests.swift`에 먼저 작성한다.
- [X] T044 [P] [US2] primary action 전달부터 4.9초 성공, 5초 성공 미확인, late commit·extension 종료의 fail-closed와 최종 미적용 차감 0을 `GetUpTests/Integration/ShieldReleaseDeadlineTests.swift`에 먼저 작성한다.
- [X] T045 [P] [US2] 현재 Shield 요소·`해제권 1회 사용`·`앱 닫기` 구성과 앱 내 대상·비용·종료·남을 제한 확인 및 중복 tap UI 테스트를 `GetUpUITests/UserStory2CoinReleaseUITests.swift`에 먼저 작성한다.

### 사용자 스토리 2 구현

- [X] T046 [P] [US2] 무료 우선 funding source 선택과 사용 가능 잔액 검증을 `GetUp/Core/Evaluation/CoinReservationPolicy.swift`에 구현한다.
- [X] T047 [US2] 최신 occurrence·epoch·잔액을 fetch하고 Phase 2 `MonthlyAllowanceService`로 allowance 생성+무료 예약 또는 구매 fallback을 결정적 command ID의 atomic reservation으로 실행하는 `GetUp/Core/StateMachine/RuleReleaseService.swift`를 구현한다.
  - [X] T047a [US2] BLK-015 승인에 따라 epoch·occurrence별 `ReleaseOccurrenceClaim` 모델, 결정적 record ID, 엄격한 codec과 호환 정책·테스트를 추가한다.
  - [X] T047b [US2] 무료·구매 예약과 claim 획득, 보상과 claim 해제를 같은 atomic modify로 연결하고 실제 repository·공유 database fake에서 앱·Shield 동시 100회, 충돌·결과 불명·보상 재시도를 검증한다. 기존 command의 claim 부재와 구버전 writer 공존은 안전성이 검증되기 전 fail-closed하며 epoch 확인·무료 우선 충돌 재평가도 검증한다.
  - [X] T047c [US2] 최신 컨텍스트·월간 서비스·예약 repository를 `RuleReleaseService`에 연결하고 종료·revision·epoch·기존 예외 검증과 관련 회귀를 통과시켜 T047을 완료한다.
- [X] T048 [P] [US2] release exception의 atomic 저장·조회·만료 정리를 `GetUp/Infrastructure/Persistence/ReleaseExceptionRepository.swift`에 구현한다.
- [X] T049 [US2] reservation→App Group 예외→제한 합집합 재평가→CloudKit commit→대표 Live Activity 조정 순서와 보상을 구현하고 ActivityKit 실패는 해제 성공을 되돌리지 않도록 `GetUp/Infrastructure/ScreenTime/RuleReleaseCoordinator.swift`를 구현한다.
  - [X] T049a [US2] BLK-016 승인에 따라 명령별 원자 예외 추가·조건부 제거 API와 실제 파일 저장소 구현, 멱등·소유자 충돌·동시 추가·한쪽 제거·지연 재시도·실패 보존 테스트를 추가한다.
  - [X] T049b [US2] 새 예외 API를 사용하는 coordinator를 구현하고 최신 규칙·예외 기반 제한 재평가의 로컬 적용 경합, 확정 실패 보상·결과 불명 보존·ActivityKit 실패 격리를 검증해 T049를 완료한다.
- [X] T050 [US2] 결과 불명 command를 새 해제보다 먼저 조회해 committed 또는 compensated로 수렴시키는 `GetUp/Infrastructure/CloudKit/RuleReleaseReconciler.swift`를 구현한다.
- [X] T051 [US2] 주입 가능한 monotonic clock으로 Shield CloudKit 성공 확인을 5초로 제한하고 timeout 시 reconciliation route와 같은 command ID 재조정을 만드는 `GetUp/Infrastructure/ScreenTime/ShieldReleaseDeadlinePolicy.swift`를 구현한다.
- [X] T052 [US2] release exception occurrence를 제한 대상 합집합에서 제외하고 다른 규칙 제한은 유지하도록 `GetUp/Infrastructure/ScreenTime/RestrictionCoordinator.swift`를 확장한다. T049b의 최신 상태 적용 provider를 연결하고 공통 로컬 잠금 안에서 재평가·read-back을 검증한다.
- [X] T053 [US2] interval 시작·종료에서 유효 예외를 적용하고 만료 예외를 정리하도록 `GetUpDeviceActivityMonitor/DeviceActivityMonitorExtension.swift`를 확장한다. 해제 coordinator와 같은 App Group 로컬 잠금에 참여해 적용 경합을 검증한다.
- [X] T054 [US2] 현재 Shield 내용에 대표 규칙·종료·남을 제한, 무료 우선·구매 fallback에 동의하는 단일 `해제권 1회 사용` primary와 기존 `앱 닫기` secondary를 구성하도록 `GetUp/Infrastructure/ScreenTime/ShieldContentProvider.swift`를 확장한다.
- [X] T055 [US2] Shield primary action에서 최신 occurrence·장부를 검증해 무료 우선으로 안정 command를 실행하고, 성공·남은 제한·timeout과 coin store·iCloud recovery route를 기록하며 iOS 26.5 이상은 `.openParentalControlsApp`, 이전은 안내 후 `.close`로 응답하도록 `GetUpShieldAction/ShieldActionExtension.swift`, `GetUp/Infrastructure/ScreenTime/ShieldActionResponsePolicy.swift`를 구현한다. Live Activity 직접 조정은 T039에서 실기기 성공이 확인된 경로에만 production adapter로 연결하고 그 외에는 앱 진입·다음 foreground fallback을 사용하며 DEBUG feasibility probe가 release build에 포함되지 않음을 검증한다.
- [X] T056 [P] [US2] 앱 내 활성 occurrence·잔액·pending reconciliation 상태와 확인 action을 `GetUp/Features/Coins/ActiveRestrictionReleaseModel.swift`에 구현한다.
- [X] T057 [US2] 활성 제한 카드의 해제 확인 dialog와 `PendingAppRouteRepository.consumeIfEligible` 결과에 따른 잔액 부족 coin store·장부 복구 진입을 `GetUp/Features/RestrictionStatus/RestrictionStatusView.swift`, `GetUp/Features/Coins/ActiveRestrictionReleaseView.swift`에 구현한다.
- [X] T058 [US2] 한국어·영어 비용·대상·유효 기간·다중 규칙·처리 확인 문구를 `GetUp/Resources/Localizable.xcstrings`, `GetUpShieldConfiguration/Resources/Localizable.xcstrings`에 추가하고 US2 관련 자동 테스트를 통과시킨다.

**DEC-114·DEC-115 대체 표시**: T008·T016·T043·T044·T055·T057·T076은 Shield 안에서 CloudKit
해제를 완료하거나 route를 즉시 소비·삭제하던 이전 제품 경로의
구현·회귀 기록이다. T044의 deadline fixture는 진단 회귀로 유지하지만 production Shield의 직접
CloudKit 호출은 T109가 대체한다. T100의 앱 장부 조립은 재사용하고 Shield 직전 전체 refresh 연결은
T109~T110이 대체한다. 기존 `consumeIfEligible` 삭제 방식은 T106·T108·T110의 영속
`pending → processing → terminal` handoff와 migration이 대체한다.

**체크포인트**: fake 장부 잔액만으로 Shield·앱의 현재 구간 1회 해제와 모든 실패 보상을 검증할 수 있다.

---

## Phase 5: 사용자 스토리 3 — 코인 구매와 잔액 확인 (Priority: P2)

**목표**: 1개·3개·5개 상품과 현지 가격을 표시하고 검증된 구매만 CloudKit 장부에 한 번 지급하며,
장부 삭제 시 구매·사용을 잠그고 명시적 새 장부 흐름을 제공한다.

**독립 테스트**: 규칙 해제를 수행하지 않고 StoreKit 성공·취소·pending·unverified·중복 결과를
처리해 성공한 거래만 잔액과 내역에 한 번 반영되는지 검증한다.

### 사용자 스토리 3 테스트

- [x] T059 [P] [US3] 1개·3개·5개 product ID·수량 매핑, 현지 가격, 판매 불가·로드 실패 테스트를 `GetUpTests/StoreKit/CoinProductCatalogTests.swift`에 먼저 작성한다.
- [x] T060 [P] [US3] verified·unverified·pending·cancel·error와 같은 transaction 100회 멱등 지급 테스트를 `GetUpTests/StoreKit/CoinPurchaseServiceTests.swift`에 먼저 작성한다.
- [x] T061 [P] [US3] CloudKit commit 전 미finish, commit 후 finish 실패, 재실행 unfinished·updates 복구 테스트를 `GetUpTests/StoreKit/StoreKitTransactionObserverTests.swift`에 먼저 작성한다.
- [x] T062 [P] [US3] 환불·철회·취소 reversal, 미사용분 한도와 0 clamp 테스트를 `GetUpTests/Core/PurchaseRefundReconcilerTests.swift`에 먼저 작성한다.
- [x] T063 [P] [US3] `current` 외 구매 API 미호출, 일시 장애와 삭제 확정 구분, 자동 복원 금지, 명시적 reset 테스트를 `GetUpTests/Integration/CoinLedgerLifecycleTests.swift`에 먼저 작성한다.
- [x] T064 [P] [US3] 로컬 데이터가 없는 동일 iCloud 새 설치의 기존 `current` 장부 잔액·내역 복구와 새 grant 0개, 원격 장부·삭제 증거가 없는 최초 `setupRequired`에서 명시적 setup action 뒤 initial epoch+당월 무료 2회 atomic 생성, 확인된 삭제 reset의 구매 0·당월 무료 0, 불확실 장부 잠금을 `GetUpTests/Integration/CoinLedgerFreshInstallRecoveryTests.swift`에 먼저 작성한다.
- [x] T065 [P] [US3] 최초 활성화 고지·동의 전 무변경·동의 action 후 무료 2회 표시, 삭제 reset과 구분, 매 구매 삭제 불이익 고지, 구매 상태·잔액·내역 UI 테스트를 `GetUpUITests/UserStory3CoinPurchaseUITests.swift`에 먼저 작성한다.

### 사용자 스토리 3 구현

- [x] T066 [P] [US3] bundle catalog를 1개·3개·5개 허용 상품으로 검증하는 `GetUp/Infrastructure/StoreKit/CoinProductCatalog.swift`를 구현한다.
- [x] T067 [P] [US3] `Product.products(for:)`, 현지 가격과 purchase 결과를 감싸는 `GetUp/Infrastructure/StoreKit/StoreKitPurchaseAdapter.swift`를 구현한다.
- [x] T068 [US3] `current` 사전 조건, 검증 거래, CloudKit PurchaseGrant commit 후 finish를 조정하는 `GetUp/Core/StateMachine/CoinPurchaseService.swift`를 구현한다.
- [x] T069 [US3] 앱 시작 시 listener를 먼저 열고 unfinished·`Transaction.updates`를 같은 지급 키로 재처리하는 `GetUp/Infrastructure/StoreKit/StoreKitTransactionObserver.swift`를 구현한다.
- [x] T070 [US3] 검증된 환불·철회를 미사용 구매 코인 범위에서 역분개하는 `GetUp/Core/StateMachine/PurchaseRefundReconciler.swift`를 구현한다.
- [x] T071 [US3] zone 삭제 event·`userDeletedZone`·기존 장부 표식을 구분하고 구매·사용을 잠그도록 `GetUp/Infrastructure/CloudKit/CoinLedgerSyncAdapter.swift`를 확장한다.
- [x] T072 [US3] 원격 장부·삭제 증거가 없는 `setupRequired`에서 사용자 동의 뒤 initial epoch+당월 quota 2를 atomic 생성하는 `GetUp/Infrastructure/CloudKit/CoinLedgerSetupService.swift`와, 삭제 확인 뒤 새 epoch+구매 0+당월 quota 0을 atomic 생성하고 local mirror 자동 복원을 금지하는 `GetUp/Infrastructure/CloudKit/CoinLedgerResetService.swift`를 서로 다른 entry point와 허용 상태로 구현한다.
- [x] T073 [US3] 초기 fetch의 epoch·PurchaseGrant transaction 연결·사용·보정 projection을 검증해 기존 장부는 mirror와 내역만 재생성하고, 장부·삭제 증거가 모두 없는 최초 활성화와 확인된 삭제를 분리하며 새 지급을 만들지 않는 `GetUp/Infrastructure/CloudKit/CoinLedgerRecoveryService.swift`를 구현한다.
- [x] T074 [P] [US3] 상품·구매·pending·잔액·장부 삭제 상태를 관리하는 `GetUp/Features/Coins/CoinStoreModel.swift`를 구현한다.
- [x] T075 [US3] `setupRequired` 최초 활성화 화면의 고지·명시적 동의 action을 `CoinLedgerSetupService`에 연결하고, 상품 1·3·5개·현지 가격·구매 확인·내역 및 삭제 reset 화면을 분리하며 StoreKit `구매 복원`과 구분되는 `iCloud 잔액 동기화·복구` 상태를 `GetUp/Features/Coins/CoinStoreView.swift`, `GetUp/Features/Coins/CoinLedgerHistoryView.swift`에 구현한다.
- [x] T076 [US3] app launch와 scene foreground에 transaction·CloudKit 재조정을 연결하고 Shield route는 생성 후 5분 이내·미소비·활성 occurrence 조건을 만족할 때 atomic하게 한 번 소비한 뒤 coin store·장부 복구로 이동하며 stale·중복·종료 route를 폐기하도록 `GetUp/App/GetUpApp.swift`, `GetUp/App/DependencyContainer.swift`를 확장한다.
- [X] T077 [US3] 최초 활성화·매 구매의 한국어·영어 삭제 불이익·복구·환불 한계 문구를 `GetUp/Resources/Localizable.xcstrings`에 추가하고 StoreKit Configuration 자동 테스트를 통과시킨다.

**체크포인트**: CloudKit `current` 상태에서만 구매를 시작하며 성공 거래 한 건이 정확히 한 번 지급된다.

---

## Phase 6: 사용자 스토리 4 — 매월 무료 해제권 사용 (Priority: P2)

**목표**: 같은 iCloud 계정에 서울 기준 매월 무료 해제권 2회를 최대 한 번 지급하고, 비이월·무료
우선 사용과 구매 코인 분리 표시를 보장한다.

**독립 테스트**: StoreKit 구매 없이 월 중간 최초 사용, 서울 월 경계, 다기기 동시 생성·사용,
기기 날짜 변경을 재현해 해당 월 무료분이 2회를 초과하지 않는지 검증한다.

### 사용자 스토리 4 테스트

- [X] T078 [P] [US4] Phase 2의 월 정책을 사용해 서울 월 경계·자정 background 미생성·기기 시간대 변경·reset 억제 월의 app lifecycle 인수 테스트를 `GetUpTests/Integration/MonthlyAllowanceLifecycleTests.swift`에 먼저 작성한다.
- [X] T079 [P] [US4] 새달 첫 앱 foreground·첫 Shield 요청의 지연 생성, 월 중간 최초 2회, 비이월, 구매 잔액 보존, 무료 우선 사용의 사용자 스토리 회귀 테스트를 `GetUpTests/Integration/MonthlyAllowanceUserStoryTests.swift`에 먼저 작성한다.
- [X] T080 [P] [US4] Phase 2 CloudKit 월간 suite를 같은 record ID 다기기 100회와 server creationDate 불일치·account 불가 재시도 조건으로 실행·집계하는 인수 harness를 `GetUpTests/Performance/MonthlyAllowanceAcceptanceTests.swift`에 작성한다.
- [X] T081 [P] [US4] 앱의 무료분·구매 코인 분리 표시와 Shield 단일 버튼의 무료 우선 사용 및 월 경계 갱신 UI 테스트를 `GetUpUITests/UserStory4MonthlyAllowanceUITests.swift`에 먼저 작성한다.

### 사용자 스토리 4 구현

- [X] T082 [US4] 최초 `setupRequired` 사용자의 당월 무료 2회, 일반 `current` 잔액, 삭제 확인 reset 사용자의 당월 무료 0 상태를 구분하는 월간 표시 모델을 `GetUp/Features/Coins/CoinStoreModel.swift`에 구현한다.
- [X] T083 [US4] 이번 달 무료 잔여 수량·비이월·다음 서울 월 경계 안내와 구매 코인 잔액을 분리 표시하도록 `GetUp/Features/Coins/CoinStoreView.swift`를 확장한다.
- [X] T084 [US4] 월간 무료 지급·사용·월 종료와 구매 지급·사용·보정 event를 구분해 표시하도록 `GetUp/Features/Coins/CoinLedgerHistoryView.swift`를 확장한다.
- [X] T085 [US4] 월 경계·첫 앱·첫 Shield·최초 setup·삭제 reset fixture를 app과 Shield UI test seam에 연결하도록 `GetUp/App/DependencyContainer.swift`, `GetUp/Infrastructure/ScreenTime/ShieldContentProvider.swift`를 확장한다.
- [X] T086 [US4] 무료·구매 잔액의 loading·empty·stale·current 상태와 VoiceOver 읽기 순서를 `GetUp/Features/Coins/CoinStoreView.swift`, `GetUp/Features/Coins/CoinLedgerHistoryView.swift`에 구현한다.
- [X] T087 [US4] Shield에는 funding source를 미리 단정하지 않는 단일 해제 버튼과 무료 우선·구매 fallback 설명을 표시하고 실제 source는 tap 뒤 최신 장부에서 결정하도록 `GetUp/Infrastructure/ScreenTime/ShieldContentProvider.swift`를 확장한다.
- [X] T088 [US4] 한국어·영어 월간 무료분·비이월·무료 우선 문구와 접근성 label을 `GetUp/Resources/Localizable.xcstrings`, `GetUpShieldConfiguration/Resources/Localizable.xcstrings`에 추가한다.
- [ ] T089 [US4] T103~T113의 승인된 메인 앱 release route를 완료한 뒤 US4 자동 테스트를 통과시키고 다기기·서울 월 경계 Shield 첫 탭 수동 검증 결과를 `specs/002-live-activity-coins/quickstart.md`, `docs/STATUS.md`에 기록한다.

**체크포인트**: 월간 무료분은 계정·월 전체에서 2회를 넘지 않고 구매 잔액과 독립적으로 동작한다.

---

## Phase 7: 마감 및 교차 관심사 *(Phase 9 완료 뒤 실행)*

**목적**: 네 스토리를 통합 검증하고 개인정보·접근성·출시 운영 조건을 닫는다.

- [ ] T090 [P] 한국어·영어, VoiceOver, 최대 Dynamic Type, Light/Dark의 Live Activity·앱·Shield 회귀를 `GetUpUITests/AccessibilityUITests.swift`, `GetUpUITests/LiveActivityCoinLocalizationUITests.swift`에 추가한다.
- [ ] T091 [P] 위치 좌표·정확도·Family Controls token·상품 이외 앱 식별 정보가 CloudKit record·로그에 없는지 `GetUpTests/Integration/PrivacyLoggingTests.swift`, `GetUpTests/Integration/CoinLedgerPrivacyTests.swift`로 검증한다.
- [ ] T092 [P] T024~T026의 SC-001 적격 모집단 100회·95회 시작, SC-002 위치 수신 주체별 30초, SC-003 남은 시간 60초·0 clamp와 기존 중복 해제·구매 100회 suite를 재실행해 결과만 집계·보고하도록 `GetUpTests/Performance/LiveActivityCoinPerformanceTests.swift`를 구성하고 동일 계측 로직을 중복 구현하지 않는다.
- [ ] T093 전체 `GetUpTests`·`GetUpUITests`와 앱·네 확장 Simulator build를 `GetUp.xctestplan`로 실행하고 실패·skip·경고를 `docs/STATUS.md`에 기록한다.
- [ ] T094 StoreKit sandbox에서 1·3·5개 구매, pending 승인, 중복 전달, 환불·철회 결과를 검증하고 비식별 증적을 `specs/002-live-activity-coins/quickstart.md`, `docs/HANDOFF.md`에 기록한다.
- [ ] T095 같은 iCloud 계정 두 실기기에서 장부 충돌·로컬 빈 새 설치 복구·account switch·zone 삭제·명시적 reset·첫 상호작용 다음 달 지급을 검증하고 결과를 `specs/002-live-activity-coins/quickstart.md`, `docs/HANDOFF.md`에 기록한다.
- [ ] T096 T039의 Shield Action ActivityKit 선행 probe 결과를 회귀 확인하고 실기기에서 Live Activity foreground 시작·위치 수신 주체별 30초·10m 거리·5분 stale·대표 교체·수동 제거 재생성·메인 앱 코인 해제 직후 갱신/종료, iOS 26.5 release route 직접 앱 진입·iOS 26.0~26.4 호환 경로를 검증해 `specs/002-live-activity-coins/quickstart.md`, `docs/HANDOFF.md`에 기록한다.
- [ ] T097 App Store Connect IAP 계약·세금·상품 판매 상태, CloudKit production schema, capability·privacy manifest를 점검하고 `docs/HANDOFF.md`, `docs/BLOCKERS.md`를 갱신한다.
- [ ] T098 T113·T119 완료 뒤 모든 FR-001~FR-045·SC-001~SC-015의 구현·검증 추적성을 확인하고 특히 FR-041~FR-045 release route·승인 기반 UI와 SC-003 시간 정확도의 자동 테스트 증적을 연결한 뒤 `specs/002-live-activity-coins/tasks.md`, `docs/STATUS.md`, `docs/DECISIONS.md`를 완료 상태로 갱신한다.

---

## 의존성과 실행 순서

### 단계 의존성

- **Phase 1 설정**: 즉시 시작할 수 있다.
- **Phase 2 공통 기반**: Phase 1 완료 후 진행하며 모든 사용자 스토리를 차단한다.
- **US1**: Phase 2 완료 후 독립적으로 시작할 수 있다.
- **US2**: 장부·해제 core 테스트와 구현은 Phase 2 뒤 시작할 수 있다. T039·T055의 Shield 직접
  조정 경로는 완료된 과거 feasibility·회귀 증적으로만 유지한다. 현재 제품 경로는 T103~T113이며,
  T105 하이파이 승인 뒤 T106~T113을 순서대로 수행한다.
- **US3**: Phase 2 완료 후 US1·US2와 기능적으로 독립 개발할 수 있지만
  `CoinLedgerSyncAdapter`·`DependencyContainer` 변경은 US2와 파일 단위로 순차 적용한다.
- **US4**: 월 정책·원자 예약 구현은 Phase 2에서 이미 완료한다. US4의 app lifecycle·Shield UI·인수
  연결은 US2의 `RuleReleaseService`·`ShieldContentProvider` 완료 후 진행하며 US3의
  `CoinStoreModel` 변경과도 파일 단위로 순차 적용한다.
- **Phase 7 마감**: 번호는 기존 문서 이력을 유지하지만 실행은 Phase 9와 T089 완료 후 진행한다.
  T098은 T113·T119의 승인 UI·실기기 증적까지 포함한 최종 추적성 gate다.
- **Phase 9 승인 기반 후속 작업**: BLK-018 해결 경로를 먼저 구현·검증한 뒤 T089을 재개한다. US2의
  T106~T113은 T105 해제 UI 하이파이 승인 뒤에만 시작한다. US1의 T117~T119는 T116 Live Activity
  하이파이 승인 뒤에만 시작한다. 두 승인 게이트는 서로 독립적으로 진행할 수 있다.

### 사용자 스토리 의존성 그래프

```text
Phase 1 설정 → Phase 2 공통 기반·월 최소 기반 ┬→ US1 기존 Live Activity ─→ T114~T116 승인 → T117~T119 ─┐
                                               ├→ US2 기존 해제 core ─→ T103~T105 승인 → T106~T113 ─┐    │
                                               └→ US3 StoreKit 구매·복구 → US4 월 UI·인수 ──────────┴→ T089
                                                                                                      │    │
                                                                                                      └────┴→ Phase 7·T098
```

- US1은 코인 계층을 사용하지 않는다.
- US2 해제 core는 Phase 2에서 검증된 무료분·fixture 구매 잔액과 ActivityKit fake로 독립 검증한다.
  완료된 T039 결과와 T055 직접 ActivityKit 경로는 회귀 증적으로만 보존하며, DEC-114 이후 production
  해제는 T109의 app handoff와 T110~T112의 메인 앱 실행·UI가 담당한다.
- US3은 규칙 해제를 수행하지 않고 구매 지급·복구만 독립 검증한다.
- US4는 StoreKit 없이 월간 무료 지급·비이월을 검증하지만 Shield UI 연결은 US2 뒤에 수행한다.

### 스토리 내부 순서

1. 해당 스토리의 테스트를 먼저 작성하고 예상대로 실패하는지 확인한다.
2. 순수 모델·정책을 구현한다.
3. system framework adapter와 영속 경계를 구현한다.
4. app·extension UI와 수명주기를 연결한다.
5. 해당 스토리 자동 테스트와 build를 통과시킨 뒤 체크포인트를 닫는다.

## 병렬 실행 예시

### US1

```text
T022 대표 occurrence 테스트 || T023 거리 정책 테스트 || T024 coordinator 테스트 || T025 시작 계측 테스트 || T026 위치 bridge 테스트 || T027 preview fixture
T028 occurrence evaluator || T029 content policy || T032 ActivityKit adapter
```

### US2

```text
T040 reservation·상태 머신 테스트 || T041 예외 저장 테스트 || T042 조정 테스트 || T043 Shield 테스트 || T044 deadline 테스트 || T045 UI 테스트
T046 reservation policy || T048 release exception repository || T056 앱 model
US1 T011·T032·T033 완료 → T039 실기기 feasibility gate
DEC-114 이후: T103~T105 설계·승인 → T106·T107 실패 테스트 → T108~T112 구현 → T113 실기기 검증
```

### US3

```text
T059 catalog 테스트 || T060 구매 테스트 || T061 observer 테스트 || T062 환불 테스트 || T063 장부 lifecycle 테스트 || T064 새 설치 복구 테스트 || T065 UI 테스트
T066 product catalog || T067 StoreKit adapter || T074 CoinStoreModel
```

### US4

```text
US2 ShieldContentProvider 완료 후 T078 lifecycle 인수 테스트 || T079 사용자 스토리 회귀 || T080 다기기 인수 집계 || T081 UI 테스트
US3 CoinStoreModel 변경과 순차 적용: T082 setup/reset 표시 → T086 잔액·내역 표시
T088 지역화
```

## 구현 전략

### MVP 우선

1. Phase 1 설정과 Phase 2 공통 기반을 완료한다.
2. US1만 구현해 코인 없이 Live Activity를 독립 검증한다.
3. 첫 유료 기능 범위를 검증하려면 US2까지 추가해 fixture 장부로 안전한 해제 흐름을 닫는다.
4. 각 체크포인트에서 중단해도 기존 001 제한 기능은 계속 독립 동작해야 한다.

### 점진적 제공

1. **MVP A**: US1 — 읽기 전용 제한 현황 Live Activity
2. **MVP B**: US2 — confirmed fixture 잔액으로 현재 구간 1회 해제
3. **수익 경로**: US3 — StoreKit 구매와 iCloud 복구·삭제 정책
4. **안전장치**: US4 — 월간 무료 해제권 2회
5. **출시 후보**: Phase 7의 자동·sandbox·다기기·실기기 증적 완료

## 참고

- `[P]`는 파일 충돌과 미완료 선행 의존성이 없는 작업에만 표시했다.
- 실제 유료 판매 전 App Store Connect·CloudKit production 상태와 실기기 증적이 없으면 기능을
  완료로 표시하지 않는다.
- 새 구조·상태 전이·복구 정책이 변경되면 같은 변경 단위에서 `docs/DECISIONS.md`와 설계 문서를
  갱신한다.
- 각 task 완료 시 체크박스, 관련 테스트 결과와 다음 작업을 `docs/STATUS.md`에 함께 갱신한다.

## Phase 8: Convergence

- [X] T099 **CRITICAL** 실제 `CKContainer.privateCloudDatabase`와 `CoinLedgerZone`을 사용하는 `CoinLedgerCloudDatabase` adapter를 추가하고 zone 생성·record fetch·server `creationDate` 보존·`ifServerRecordUnchanged` atomic modify·부분 실패 및 CloudKit 오류 매핑을 자동 테스트와 함께 구현한다. T089·T094·T095 실기기 검증 전에 완료한다. per FR-036, plan: CloudKit 장부와 월간 무료분 (missing)
- [X] T100 **CRITICAL** 앱과 Shield Action의 live 환경에 실제 CloudKit repository와 월 지급·구매 지급·해제 예약·setup/reset/recovery/reconciliation 서비스를 조립하고, launch·foreground·Shield 요청 직전 최신 장부 확인 및 App Group snapshot 갱신을 통합 테스트로 검증한다. 기본 복구 closure를 우회하지 말고 T099·T101·T102의 검증된 provider만 주입한다. per FR-012, FR-019, FR-027, FR-030, FR-041
- [X] T101 `CKSyncEngine` 기반 private database 동기화 provider를 구현해 iCloud account 상태·account switch 격리·프로세스별 initial fetch·pending change 재시도·zone 삭제 evidence·원격 projection과 App Group mirror 저장을 `CoinLedgerSyncAdapter`에 연결하고 수명주기·재설치·삭제·불가 상태 테스트를 추가한다. T100 전에 완료한다. per FR-024, FR-037, FR-040, plan: CKSyncEngine local mirror (partial)
- [X] T102 기존 epoch와 claim 없는 command를 자동 허용하거나 삭제·reset하지 않는 reservation 호환성 검사 및 명시적 migration provider를 구현하고, 검증된 epoch에만 `verifyReservationCompatibility`를 허용하도록 앱·Shield의 동일 CloudKit 경계에 연결한다. 구버전 writer 공존·중단·재시도·migration 완료 테스트와 운영 결정을 함께 기록한다. T100 전에 완료한다. per FR-014, FR-015, plan: reservation migration compatibility (missing)

---

## Phase 9: 승인 기반 Shield 해제 handoff와 Live Activity 시각 개편

**목적**: Shield extension의 실행 시간 제약을 피하면서 서버 권위 해제를 메인 앱에서 완료하고,
결과 화면과 Live Activity를 사용자 승인 하이파이에 맞춰 구현한다.

**승인 게이트**: T105가 완료되기 전에는 T106~T113의 제품 코드·UI를 시작하지 않는다. T116이
완료되기 전에는 T117~T119의 Live Activity UI 코드를 시작하지 않는다. 검토 의견으로 화면 구조나
제품 동작이 바뀌면 해당 설계 task로 돌아가 재승인을 받는다.

### 사용자 스토리 2 후속 — Shield 요청을 메인 앱에서 완료

**독립 테스트**: iOS 26.5 이상에서 Shield `해제권 1회 사용`을 한 번 누르면 메인 앱의 처리 중 화면이
열리고, 성공 시 현재 occurrence만 해제·1회 차감·완료 화면으로 수렴한다. 재시도 가능한 오류 또는
foreground에서 확인된 중단 command는 차감 없이 동일 command 재시도, 잔액 부족은 제한 유지와
코인 구매 CTA로 수렴한다.

- [X] T103 [US2] 신규 처리 중·해제 완료·재시도 가능한 실패 또는 중단 command 확인 후 재시도·잔액 부족 후 코인 구매 유도의 네 흐름과 기존 iCloud 장부 복구 화면 연결, 상태·초점 이동을 `design/low-fidelity/US2-release-handoff.md`에 작성하고 사용자 검토 결과를 승인 상태로 기록한다.
- [X] T104 [US2] T103 승인 뒤 신규 네 해제 상태의 Light/Dark, 최대 Dynamic Type, VoiceOver, Reduce Motion, loading·중복 tap·앱 재실행 상태와 기존 `recoveryRequired` 화면 연결을 포함한 하이파이를 제작하고 Figma node·시각 token·문구·구현 인계를 `design/high-fidelity/US2-release-handoff.md`에 기록한다.
- [X] T105 [US2] T104 하이파이를 사용자에게 제시해 명시적 구현 승인을 받고 결과·의견·승인일을 `design/high-fidelity/US2-release-handoff.md`, `docs/DECISIONS.md`, `docs/STATUS.md`에 기록한다. 승인 전에는 T106~T113을 시작하지 않는다.
- [X] T106 [P] [US2] `releaseProcessing` route의 안정 command ID, 5분 pending 유효성, `pending → processing → terminal`과 `terminal(retryable) → processing` 원자 전이, claim 전 만료·종료 폐기, processing 보존·중복 claim·단순 제시 후 보존·명시적 terminal action 뒤 삭제와 앱 종료 뒤 동일 command 재조정 실패 테스트를 `GetUpTests/Core/RuleReleaseRouteTests.swift`, `GetUpTests/Persistence/PendingAppRouteRepositoryTests.swift`에 먼저 작성한다.
- [X] T107 [P] [US2] 처리 중→완료·재시도·잔액 부족·복구 필요 상태 전이, 실행 중 재시도 비노출, transient·결과 불명·계정/장부 복구·잔액 부족 안정 오류 분류와 `retryAfter`, foreground 중단 command에서만 동일 command 재시도 활성화, 완료 전 제한 유지와 승인 하이파이 식별자 UI 테스트를 `GetUpTests/Integration/AppReleaseHandoffTests.swift`, `GetUpUITests/UserStory2ReleaseResultUITests.swift`에 먼저 작성한다.
- [X] T108 [US2] `PendingAppRoute.releaseProcessing`의 `pending | processing | terminal`, claim·terminal outcome·제시·명시적 확인 필드와 command ID codec, legacy 미소비→`pending`·유효한 소비 중 release→`processing`·그 외 fail-closed 폐기 migration, 메인 앱 release 상태 모델을 `GetUp/Core/Models/RuleReleaseModels.swift`, `GetUp/Infrastructure/Persistence/SharedSnapshotRepository.swift`, `GetUp/Features/Coins/ActiveRestrictionReleaseModel.swift`에 구현한다.
- [X] T109 [US2] Shield primary가 CloudKit을 호출하지 않고 release route를 원자 저장한 뒤 iOS 26.5 이상에서 즉시 `.openParentalControlsApp`, iOS 26.0~26.4에서 공식 fail-closed fallback을 반환하도록 `GetUpShieldAction/ShieldActionExtension.swift`, `GetUp/Infrastructure/ScreenTime/ShieldActionResponsePolicy.swift`를 변경한다.
- [X] T110 [US2] 메인 앱이 release route를 `processing`으로 원자 claim하고 앱 종료 뒤 남은 handoff를 먼저 재조정한 뒤 FR-037 전체 refresh·occurrence 재검증·동일 command 재조정·무료 우선 원자 해제·Managed Settings read-back·commit·terminal 결과 영속화와 명시적 결과 action의 삭제 또는 재시작을 수행하도록 `GetUp/App/AppLifecycleCoordinator.swift`, `GetUp/App/DependencyContainer.swift`, `GetUp/Infrastructure/ScreenTime/RuleReleaseCoordinator.swift`를 연결한다.
- [X] T111 [US2] T105에서 승인된 하이파이만 기준으로 신규 처리 중·완료·재시도·잔액 부족 화면과 재시도·코인 구매 CTA를 구현하고 `recoveryRequired`는 기존 복구 화면으로 연결하도록 `GetUp/Features/Coins/ActiveRestrictionReleaseView.swift`, `GetUp/Features/Coins/CoinStoreView.swift`를 변경한다.
- [X] T112 [US2] 승인된 신규 네 상태와 기존 복구 연결의 한국어·영어 문구, VoiceOver 진행 상태·focus 이동, 최대 Dynamic Type·Light/Dark·Reduce Motion 회귀를 `GetUp/Resources/Localizable.xcstrings`, `GetUpUITests/UserStory2ReleaseResultUITests.swift`, `GetUpUITests/AccessibilityUITests.swift`에 구현하고 관련 자동 테스트를 통과시킨다.
- [ ] T113 [US2] 동일 iCloud 계정의 iPhone 15 Pro Max와 iPhone 17에서 일반 활성 occurrence의 Shield 첫 탭 한 번 앱 진입, 처리 중·완료·재시도·잔액 부족·기존 복구 화면 연결, 앱 강제 종료 뒤 동일 command 복원, 제한·잔액·내역 다기기 수렴을 검증하고 release handoff 결과를 `specs/002-live-activity-coins/quickstart.md`, `docs/STATUS.md`, `docs/HANDOFF.md`에 기록한다. 월 경계의 allowance 지연 생성·비이월 판정은 T089에서 별도로 검증한다.

**체크포인트**: 해제 UI 하이파이 승인 증적과 두 실기기의 첫 탭 해제·실패 안전성 증적이 모두
있을 때만 US2 후속과 T089을 완료한다.

### 사용자 스토리 1 후속 — Live Activity 앱 무드 정합화

**독립 테스트**: 동일한 content fixture로 잠금화면과 Dynamic Island minimal·compact·expanded를
표시했을 때 승인된 하이파이의 정보 우선순위와 앱 무드를 유지하고 핵심 시간·거리·다중 규칙 정보가
잘리거나 누락되지 않는다.

- [ ] T114 [P] [US1] 기존 Live Activity의 known·unavailable·stale·다중 규칙 상태와 잠금화면·Dynamic Island minimal·compact·expanded 정보 구조를 `design/low-fidelity/US1-live-activity-refresh.md`에 작성하고 사용자 검토 결과를 승인 상태로 기록한다.
- [ ] T115 [US1] T114 승인 뒤 나서 앱 무드의 색상·서체·간격·아이콘·motion, Light/Dark, 최대 Dynamic Type, VoiceOver와 각 ActivityKit 영역 제약을 포함한 하이파이를 제작하고 Figma node·구현 인계를 `design/high-fidelity/US1-live-activity-refresh.md`에 기록한다.
- [ ] T116 [US1] T115의 잠금화면·Dynamic Island 전체 하이파이를 사용자에게 제시해 명시적 구현 승인을 받고 결과·의견·승인일을 `design/high-fidelity/US1-live-activity-refresh.md`, `docs/DECISIONS.md`, `docs/STATUS.md`에 기록한다. 승인 전에는 T117~T119를 시작하지 않는다.
- [ ] T117 [P] [US1] 승인된 하이파이의 known·unavailable·stale·다중 규칙, 한국어·영어, Light/Dark, 최대 Dynamic Type 상태를 고정하는 preview·snapshot fixture를 `GetUpLiveActivity/RestrictionLiveActivityPreviews.swift`, `GetUpTests/Integration/LiveActivityPresentationTests.swift`에 먼저 작성한다.
- [ ] T118 [US1] T116에서 승인된 하이파이만 기준으로 잠금화면과 Dynamic Island minimal·compact·expanded UI를 `GetUpLiveActivity/RestrictionLiveActivity.swift`, `GetUpLiveActivity/GetUpLiveActivityBundle.swift`, `GetUpLiveActivity/Resources/Localizable.xcstrings`에 구현하고 4KB payload·60초 시간 정확도 계약을 보존한다.
- [ ] T119 [US1] 잠금화면·Dynamic Island 각 영역의 승인 하이파이 대조, VoiceOver·최대 Dynamic Type·Light/Dark·Reduce Motion·대표 교체·종료를 preview와 지원 실기기에서 검증하고 결과를 `specs/002-live-activity-coins/quickstart.md`, `docs/STATUS.md`, `docs/HANDOFF.md`에 기록한다.

**체크포인트**: Live Activity 하이파이 승인과 preview·실기기 대조가 끝나기 전에는 시각 개편을
완료로 표시하지 않는다.
