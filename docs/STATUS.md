# 프로젝트 상태

## 현재 기능
001-location-app-restriction

## 현재 단계
Phase 3 사용자 스토리 1 — T027 실패 UI test 작성 완료

## 진행 중
없음

## 마지막 완료 작업
T027 — 규칙 설정과 모든 규칙 home pager의 실패 UI test를 먼저 작성하고 red 상태를 확인함

## 다음 작업
T028 — T025를 통과하도록 `ScheduleEvaluator`를 구현함

## 차단 상태
없음

## 계획 갱신 필요
`DEC-015`~`DEC-019`에 따라 `spec.md`, `plan.md`, `data-model.md`, `tasks.md`와 관련 contract는 다중
규칙, 저장 장소, 직접 시간 설정, 여섯 단계 반경 기준으로 갱신했다. 기존 단일 규칙 저장소와
500m·1km 모델 구현은 후속 core task에서 collection·저장 장소 구조로 migration해야 하며, 해당
구현 전까지 현재 로우파이 검토를 계속한다.

## 테스트 상태
명세 품질 체크리스트 16/16개 항목을 통과함. 계획 산출물의 구조 검증을 통과함.
T025 착수 전 `xcodebuild -list -project GetUp.xcodeproj`로 6개 target과 공유 scheme을 확인했으나,
로컬 CoreSimulator service 연결 실패 경고가 발생했다. 이후 사용자가 BLK-006의 1안을 선택해 DST의
존재하지 않는 경계는 다음 유효 시각, 반복 시작은 첫 번째 발생, 반복 종료는 두 번째 발생으로
확정했다. `ScheduleEvaluatorTests.swift`에 14/15분, 선택·비선택 요일, 같은 날·자정 초과, DST 시작·
종료 보정과 반복 시각 경계를 작성하고, `RestrictionRuleValidatorTests.swift`에 요일·저장 장소·여섯
반경·앱 token·같은 시작/종료·14/15분 validation을 작성했다. 두 파일은 임시 계약 stub을 사용한
Swift 6 strict concurrency type-check를 통과했으며, 실제 production module에 대해서는 계획대로
`ScheduleEvaluator`, `RestrictionRuleValidator`, `RestrictionRuleValidationInput` 미구현 오류로
red 상태를 확인했다. `xcodebuild build-for-testing`은 앱 target에 실행 entry point가 아직 없어
linker 단계에서 실패했고 CoreSimulator service 경고도 계속 발생했다. `project.pbxproj` 문법과
`git diff --check`는 통과했으며, red 테스트는 T028·T029 구현 전까지 예상된 미완료 테스트다.
T026에서 `LocationPickerModelTests.swift`에 지도 이동, 현재 위치 바로가기, When In Use 권한 부족과
위치 조회 실패 시 pin 보존, 저장 장소 draft 생성·재사용, 확인·취소 상태를 작성했다.
`CurrentLocationProviderTests.swift`에는 When In Use 성공, denied·restricted·notDetermined 권한 흐름,
권한 요청 거절, 단발성 위치 실패 정규화를 작성했다. 두 파일과 test fake는 임시 계약 stub을 사용한
Swift 6 strict concurrency type-check를 통과했다. 실제 production module에서는 계획대로
`LocationPickerModel`, `SavedPlaceSnapshot`, `CurrentLocationProvider`, `CurrentLocationSession` 등
T030 대상 타입의 미구현 오류로 red 상태를 확인했다. 새 테스트의 `GetUpTests` target membership,
`project.pbxproj` 문법과 `git diff --check`를 확인했으며, red 테스트는 T030 구현 전까지 예상된
미완료 테스트다.
T027에서 `UserStory1RuleConfigurationUITests.swift`에 필수 입력 validation과 요일·저장 장소·앱
선택, 유효 규칙 저장 후 process 재실행 재로딩, 세 저장 규칙의 양방향 card swipe, 선택 card 편집 시
값 보존을 작성했다. 승인된 하이파이의 accessibility identifier를 사용하고, 시스템 소유
`FamilyActivityPicker` 결과는 `--ui-test-family-picker-result` launch argument로 test seam에서만
주입하도록 계약했다. UI test source는 Swift 6 strict concurrency standalone type-check와
`xcodebuild build-for-testing`의 arm64·x86_64 compile을 통과했다. 전체 test build는 app entry point가
아직 없어 GetUp linker 단계에서 실패했고 CoreSimulator service도 사용할 수 없었으므로 UI assertion은
실행되지 않았다. 이는 T035~T037 UI·app 구현 전의 예상 red 상태다. `project.pbxproj` 문법과
`git diff --check`는 통과했다.
`tasks.md`의 87개 task가 연속 ID, 체크박스 및 파일 경로 형식 검증을 통과함.
T001 검증으로 `project.pbxproj` plist 문법, 공유 scheme XML 및 `xcodebuild -list -json`을 실행해
Debug/Release 구성, 6개 target과 6개 scheme 인식을 확인함. Simulator service와 기본 DerivedData
접근 경고가 있었으나 프로젝트 목록 검증 명령은 성공함. 아직 앱 source가 없어 build/test는
후속 task 완료 뒤 실행함. T002 검증으로 Xcode 26.6의 Swift 6.3.3 toolchain을 확인하고,
`project.pbxproj` plist 문법과 `xcodebuild -list -json`을 재검증했으며, 6개 target의 Debug build
settings에서 `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`,
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` 및 기대한 bundle identifier 상속 결과를 확인함. 로컬
Simulator service와 일부 provisioning profile 경고가 있었으나 build settings 검증은 성공함.
T003 검증으로 네 entitlements와 `project.pbxproj`의 plist 문법을 확인하고, Family Controls 값이
모두 `true`이며 App Group 항목이 공통 `GETUP_APP_GROUP_IDENTIFIER` build setting을 참조하는지
검증함. Debug·Release의 앱과 세 확장 build settings에서 각 `CODE_SIGN_ENTITLEMENTS` 경로와
`GETUP_APP_GROUP_IDENTIFIER = group.com.getup.GetUp` 상속을 확인함. 실제 개발·배포 서명 및
entitlement 승인은 T080과 실기기 검증 전까지 미검증 상태임.
T004 검증으로 앱과 세 extension `Info.plist`, `project.pbxproj`의 plist 문법을 확인하고 위치 권한
문구, `NSExtensionPointIdentifier`, `NSExtensionPrincipalClass` 값을 Xcode 26.6 템플릿과 대조함.
Debug·Release의 네 target에서 수동 `INFOPLIST_FILE` 경로와 version 상속을 확인했으며,
`UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers` 및 관련 build setting이 없음을 검증함.
principal class의 실제 로딩은 각 extension source 구현 후 build 및 실기기 테스트 전까지 미검증
상태임.
T005 검증으로 `GetUp.xctestplan` JSON과 공유 scheme XML 문법을 확인하고,
`GetUpTests` → `GetUpUITests` 순서 및 두 target의 `parallelizable = false`를 확인함.
`xcodebuild -showTestPlans`에서 공유 scheme이 `GetUp` test plan을 인식하는 것을 검증함. 아직 앱과
테스트 source가 없으므로 실제 test 실행 결과는 없으며, 최초 실행은 관련 source task 완료 뒤
수행해야 함.
T006 검증으로 세 UI 설계 문서가 존재하며 Figma node 링크, 화면 상태, 접근성, 검토 기록과 승인
게이트 항목을 포함하는지 확인함. 이 task는 문서 scaffold 작업이므로 실행할 code test는 없음.
실제 사용자 스토리 설계는 아직 작성·승인되지 않았으며 관련 UI 구현 전에 각 문서에서 별도로
검토해야 함.
T007 검증으로 네 `PrivacyInfo.xcprivacy`의 plist 문법과 root key type을 확인하고, 모든 manifest가
`NSPrivacyAccessedAPICategoryUserDefaults`의 `1C8F.1`, 빈 `NSPrivacyCollectedDataTypes`,
`NSPrivacyTracking = false`, 빈 `NSPrivacyTrackingDomains`를 선언하는지 확인함. `project.pbxproj`
문법과 각 manifest의 target별 Resources phase membership을 확인하고 `xcodebuild -list -json`으로
프로젝트 인식을 재검증함. Simulator service와 로컬 provisioning profile 경고가 있었지만 명령은
성공함. 실제 archive privacy report와 App Store Connect 검증은 배포 준비 전까지 미검증 상태임.
T008 검증으로 asset catalog와 string catalog JSON 문법, `AppIcon`의 기본·Dark·Tinted slot,
비어 있는 `AccentColor`, 한국어 `sourceLanguage` 및 빈 문자열 목록을 확인함. 두 resource의 앱 target
Resources phase membership과 Debug·Release의 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`,
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`를 확인하고 `xcodebuild -list -json`으로
프로젝트 인식을 재검증함. `actool`과 `xcstringstool`이 빈 scaffold를 오류 없이 처리함. Simulator
service와 로컬 provisioning profile 경고가 있었지만 관련 명령은 성공함. 실제 색상·아이콘·문구는
사용자 스토리별 하이파이 승인 뒤 추가하며, 현재 빈 app icon과 accent color는 출시용 asset으로
검증되지 않은 상태임.
T009 검증으로 `SharedIdentifiers.swift`를 Swift 6 strict concurrency 설정에서 type-check하고,
두 공유 파일명과 store·activity name 규칙을 확인함. 네 `Info.plist`의
`GetUpAppGroupIdentifier = $(GETUP_APP_GROUP_IDENTIFIER)` 선언과 plist 문법을 확인하고, 같은 source가
앱과 세 extension Sources phase에 각각 한 번 포함되는지 검증함. 실제 App Group container 접근과
typed `ManagedSettingsStore.Name`·`DeviceActivityName` 변환은 관련 adapter 구현 전까지 미검증
상태임. `xcodebuild -showBuildSettings`는 Simulator service와 로컬 provisioning profile 경고를
출력했지만 성공했으며 공통 App Group과 Swift 6 strict concurrency 설정을 확인함.
T010 검증으로 `RestrictionRuleModels.swift`를 iOS Simulator SDK와 Swift 6 strict concurrency,
app-extension-only 설정에서 warning을 error로 처리해 type-check함. 모든 모델의 Codable·Equatable
및 필요한 Hashable·Sendable conformance, 월요일부터 일요일까지의 안정적인 raw value,
500m·1,000m raw value와 `radiusMeters` CodingKey를 확인하고 같은 source가 앱과 세 extension에 한
번씩 포함되는지 검증함. 시간·좌표·revision·요일·앱 선택의 유효성 및 JSON round-trip 자동 테스트는
계획된 T025·T017에서 수행하기 전까지 미검증 상태임.
T011 검증으로 `RuntimeStateModels.swift`를 iOS Simulator SDK와 Swift 6 strict concurrency,
app-extension-only 설정에서 warning을 error로 처리해 type-check함. 위치 상태·관측 source·권한 상태의
stable raw value, 위치 snapshot schema version 및 필드, 제한 표시 상태의 associated value를 확인하고
같은 source가 앱과 세 extension에 한 번씩 포함되는지 검증함. 권한·시간·위치 조합의 상태 전이와 JSON
round-trip 자동 테스트는 계획된 T015·T017에서 수행하기 전까지 미검증 상태임.
T012 검증으로 기존 모델과 `PlatformContracts.swift`를 iOS Simulator SDK와 Swift 6 strict
concurrency, app-extension-only 설정에서 warning을 error로 처리해 type-check함. 일곱 platform
contract의 `Sendable` 경계, repository CRUD, 일정·위치 lifecycle, 권한 snapshot 조회 및 제한 적용
상태의 원자적 조회 signature를 확인하고 같은 source가 앱과 세 extension에 한 번씩 포함되는지
검증함. 실제 adapter의 protocol 준수와 오류·취소 동작은 T018·T046·T048·T049·T073 구현 전까지
미검증 상태임.
T013 검증으로 기존 core 모델·contract와 `RestrictionEvaluationModels.swift`를 iOS Simulator SDK,
Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해 type-check함.
평가 입력이 전역 상태 대신 규칙·시각·달력·시간대·위치·권한·현재 제한 상태를 명시적으로 받으며,
결정이 presentation·desired restriction·effect·reason을 모두 포함하는지 확인함. 전체 상태 행렬과
우선순위·idempotency 동작은 계획된 T015·T016 전까지 미검증 상태임.
T014 검증으로 기존 core source를 `GetUp` testable module로 compile한 뒤 `TestFixtures.swift`를
iOS Simulator SDK와 Swift 6 strict concurrency에서 warning을 error로 처리해 type-check함. 고정
clock의 `Clock` 준수, UTC Gregorian calendar, factory override와 test target Sources membership을
확인함. fixture는 테스트 보조 코드이므로 독립 assertion은 없으며 실제 상태 행렬 실행은 T015에서
시작함. 기본 `FamilyActivitySelection`은 opaque token을 위조하지 않은 빈 선택으로, 앱 선택 유효성은
T025 validation 테스트에서 별도 검증할 예정임.
T015에서 시간 2상태 × 위치 3상태 × 권한 2상태 × 현재 shield 2상태의 24개 조합과 시간 종료
우선순위, 위치 `unavailable` 보존, rule revision 불일치, apply/remove idempotency를 Swift Testing으로
작성함. 구현 전 임시 compile stub을 사용하면 테스트 source가 Swift 6 strict concurrency에서
type-check되었고, stub 없이 검사하면 `RestrictionStateMachine`을 찾을 수 없어 의도한 red 상태가
발생했음. 이후 T016 구현과 실행 검증을 통과해 T015를 함께 완료 처리함.
T016 검증으로 `RestrictionStateMachine.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK, Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해
type-check함. 실제 구현을 import한 T015 Swift Testing source가 compile 검사를 통과했으며, 동일 구현을
링크한 자동 실행 harness에서 24개 상태 조합, 시간 종료 우선순위, 위치 `unavailable`·revision 불일치
보존, apply/remove idempotency, 필수 권한 결합과 자정 초과 일정의 시작 요일 귀속 assertion을 모두
통과함. `BackgroundRefreshStatus`는 진단 정보로 유지하고 신규 shield 적용의 필수 권한 집합에서는
제외함. 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지 실행할 수 없어 미검증 상태임.
T017에서 규칙·위치 JSON의 별도 파일 round-trip과 `completeUntilFirstUserAuthentication` 보호,
파일 없음의 `nil` 처리, 두 파일의 손상 JSON·미지원 schema, rule revision 불일치, 두 파일의 atomic
write 실패 시 이전 snapshot 보존을 Swift Testing으로 작성함. 구현 전 임시 compile stub을 포함하면
테스트 source가 iOS 17 Simulator SDK와 Swift 6 strict concurrency에서 type-check되었고, 실제
source만 사용한 검사에서는 `SharedSnapshotRepository`, `SharedSnapshotRepositoryError`,
`SnapshotFileWriting`을 찾을 수 없어 의도한 red 상태가 발생했음. 이후 T018 구현과 실행 검증을
통과해 T017을 함께 완료 처리함.
T018 검증으로 `SharedSnapshotRepository.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK, Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해
type-check함. 실제 T017 Swift Testing suite를 macOS host에서 같은 Foundation 구현과 불투명
`FamilyActivitySelection` compile stub으로 실행해 1개 suite의 10개 테스트가 모두 통과함. JSON은
ISO-8601 날짜와 정렬된 key로 encoding하고, schema header 선검사, 현재 rule revision 교차 검사,
atomic write와 `completeUntilFirstUserAuthentication` 보호, 오류 분류 및 삭제의 멱등성을 구현함.
기존 상태 머신 회귀 테스트까지 합친 2개 suite의 20개 테스트도 모두 통과함. 전체 Xcode test 실행은
app entry point가 구현되는 T037 전까지 실행할 수 없어 미검증 상태임.
T019 검증으로 `DependencyContainer.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK 및 macOS host에서 Swift 6 strict concurrency warning을 error로 처리해 type-check함.
실행 harness에서 한 container의 규칙·위치 계약이 동일 `SharedSnapshotRepository` actor를 노출하는지,
앱과 extension을 모사한 별도 container 인스턴스가 같은 규칙·위치 파일을 읽는지 확인함. actor 밖의
`FileManager` 인스턴스를 저장소로 전송하지 않도록 파일 작업은 actor 내부에서 생성한 인스턴스만
사용하게 조정했으며 기존 2개 suite의 20개 회귀 테스트도 모두 통과함. 실제
`DependencyContainer.live()`의 App Group container URL 획득은 entitlement가 적용된 서명 target
실행 전까지 미검증 상태임.
T020 검증으로 `DiagnosticsLogger.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK와 macOS host에서 Swift 6 strict concurrency warning을 error로 처리해 type-check함.
저장소 오류 7종과 App Group 조립 오류 2종을 안정적인 code로 분류하고, file name·schema 값·revision
값과 알 수 없는 오류 설명을 event에서 폐기하도록 Swift Testing 3개 테스트로 검증함. 좌표와 불투명
앱 token을 포함한 임의 오류 문자열이 최종 `logMessage`에 포함되지 않음을 확인했으며, 기존 상태
머신·저장소 회귀를 합친 3개 suite의 23개 테스트가 모두 통과함. 실제 unified logging 수집 결과의
통합 개인정보 검사는 T079에서 수행하며, 전체 Xcode test 실행은 app entry point가 구현되는 T037
전까지 실행할 수 없어 미검증 상태임. T020 완료로 Phase 2 공통 기반을 완료 처리함.
iOS 26 최소 지원 변경으로 `Configuration/Base.xcconfig`의
`IPHONEOS_DEPLOYMENT_TARGET = 26.0`을 앱·세 extension·두 테스트 target이 Debug 구성에서 모두
상속하는지 `xcodebuild -showBuildSettings`로 확인함. `project.pbxproj` plist 문법을 재검증하고,
공통 production source를 `arm64-apple-ios26.0-simulator`, Swift 6 strict concurrency 및 warning-as-error
조건으로 type-check함. 첫 type-check는 오래된 입력 경로, 두 번째는 sandbox의 기본 module cache
쓰기 제한 때문에 실패했으며, 실제 source와 writable 임시 module cache를 지정한 최종 검사는
통과함. CoreSimulatorService 및 로컬 provisioning profile 경고는 build setting 출력에 영향을
주지 않았으며 실제 iOS 26 Simulator 실행·실기기 검증은 관련 app entry point와 UI 구현 이후 수행함.
T021 검증으로 Figma의 `US1 / 규칙 설정 흐름` section에 iPhone 393×852 기준 7개 frame을 작성하고,
직접 시간·자정 초과·15분 미만 오류·지도 핀·현재 위치 권한 부족·시스템 앱 선택·저장 실패 상태를
각각 확인함. 모든 화면이 Apple `iOS and iPadOS 26` 공식 library component와 `SF Pro`만 사용하는지,
실제 좌표·주소·app token을 포함하지 않는지, frame 직접 링크와 접근성 가설이 설계 문서에 기록됐는지
검증함. 이 task는 디자인·문서 작업이므로 code test는 실행하지 않았으며, 로우파이는 아직 사용자
승인 전이라 T022 검토와 T023 하이파이 작업이 남아 있음.
T022 진행 중 알람·집중 앱 7개 제품의 행동 유도 방식과 앱 이름 후보를 조사해
`design/research/alarm-focus-app-concept.md`에 정리함. Figma에 침대에서 문까지(A), 문턱(B), 출발
티켓(C) 세 방향의 onboarding·home 6개 frame을 추가함. 각 home은 오늘 또는 다음날의 요일·시간·
기준 위치·반경·제한 앱 요약, 규칙 수정 및 새 규칙 진입을 포함함. 구조 감사에서 6개 frame의
placeholder가 모두 제거됐고, 사용 font는 `SF Pro`뿐이며 실제 좌표·주소·app token과 frame overflow가
없음을 확인한 뒤 각 frame screenshot을 개별 검토함. 이 작업은 디자인·문서 변경이라 code test는
실행하지 않았으며, T022 완료와 하이파이 시작은 사용자 방향 선택·승인 전까지 보류함.
사용자가 직접 제작한 D안은 변경하지 않고 Figma에 별도의 `D안 보완 / 행동 명확화` 비교 영역을
추가함. onboarding, 규칙 없음, 오늘 규칙, 다음날 규칙 4개 frame에 오늘·다음날 맥락, 위치 이동과
앱 사용 가능 조건, 시간·위치 해제 조건, 제한 앱 요약, 규칙 수정 진입점을 반영함. 개별 frame과
전체 비교 screenshot에서 텍스트 잘림·겹침을 수정했고, 기존 D안 node `15:346` 보존 및 보완안의
모든 텍스트가 `SF Pro` 계열만 사용하는지 확인함. 디자인·문서 작업이므로 code test는 실행하지
않았으며 당시 T022는 사용자 승인 전이라 진행 중으로 유지함.
2026-08-23 추가 피드백에 따라 D안 home의 시간을 `06:00 AM` 형식으로 통일하고 `AM`/`PM` 크기를
시간 숫자보다 작게 조정했다. 규칙 화면은 시간 프리셋을 제거하고 직접 시작·종료 시각만 제공하며,
15분 미만 종료 시각을 비활성화한 DatePicker 상태를 추가했다. `프리셋 이름`은 `규칙 이름`으로,
위치 설정은 재사용 가능한 `집`·`회사`·`직접 입력` 장소와 여섯 단계 반경 slider로 변경했다.
home·규칙·장소·권한·키보드·DatePicker frame을 개별 screenshot으로 검수했고 이전 용어가 남지
않았음을 확인했다. Apple 시스템 keyboard component의 `SF Compact`를 제외한 제품 UI 텍스트는
`SF Pro` 계열을 유지한다. 이번 변경은 Figma와 명세·계획 문서 작업이므로 code test는 실행하지
않았고 `git diff --check`를 통과했다. 이 검수 시점에는 T022를 사용자 승인 전 진행 중으로 유지했다.
2026-08-23 사용자가 직접 수정해 `D 보완` frame에 정리한 안을 최종 로우파이로 승인했다.
`design/low-fidelity/US1-rule-configuration.md`에 승인자·승인일·미해결 항목 없음 상태를 기록하고
T022를 완료 처리했다. 승인 기록만 변경했으므로 code test는 실행하지 않았으며, 사용자의 별도
지시 전까지 T023 또는 다른 후속 작업을 시작하지 않는다.
T023 검증으로 승인된 `D 보완` 로우파이를 보존한 별도 Figma wrapper
`US1 / 하이파이 T023 · 검토용`에 iPhone 393×852 기준 9개 상태를 작성했다. 입력 전·유효 입력
Light, 유효 입력 Dark, 지도 핀·저장 장소, 현재 위치 권한 부족, 장소 이름 직접 입력, 15분 제한
DatePicker, 시스템 앱 선택 경계, 저장 실패·draft 유지 상태를 포함하고 Dynamic Type·VoiceOver·
44×44pt touch target·Reduce Motion 인계 규격을 추가했다. Apple `iOS and iPadOS 26` library의
290개 component instance와 431개 variable 연결 node를 사용했으며, 최종 자동 감사에서 313개
text의 허용되지 않은 font family, 0폭·0높이 text, 임시 placeholder 문구와 shimmer가 모두 0건임을
확인했다. 제품 UI는 `SF Pro` 계열을 사용하고 Apple 시스템 keyboard의 `SF Compact Rounded`만
예외로 확인했다. 권한 오류 본문은 `#B42518`로 조정해 흰 배경에서 6.52:1 대비를 확보했다.
`design/high-fidelity/US1-rule-configuration.md`에 색상·서체·간격·component 상태·문구·접근성·
플랫폼 제약과 구현 인계를 기록하고 `git diff --check`를 통과했다. 디자인·문서 작업이므로 code
test는 실행하지 않았으며, SwiftUI 구현은 T024 사용자 승인 전까지 시작하지 않는다.
2026-08-23 T024 검토를 위해 기존 T023 wrapper를 보존하고 별도 Figma wrapper
`US1 / 하이파이 후보 3안 · T024 검토`에 같은 규칙 데이터를 사용한 `A · Native Calm`,
`B · Dark Focus`, `C · Warm Behavioral` 대표 화면과 비교 카드를 작성했다. 최종 렌더에서 세
화면이 모두 393×852이고 화면 밖으로 벗어난 node가 없음을 확인했다. 자동 감사에서 83개 text의
허용되지 않은 font family와 0폭·0높이 text가 모두 0건이며 shimmer·gradient도 0건이었다.
디자인·문서 작업이므로 code test는 실행하지 않았고, T024는 사용자 방향 선택과 최종 구현 승인 전
상태이므로 완료 처리하지 않았다.
2026-08-23 사용자가 후보 B를 선택해 기존 T023과 후보 비교 보드를 보존하고 별도 Figma wrapper
`US1 / B Dark Focus 전면 적용 · T024 검토`를 작성했다. 규칙 편집, 지도 핀·권한·직접 입력,
DatePicker·시스템 앱 선택·저장 실패의 9개 393×852 화면과 접근성 인계 패널에 `#08090B` 배경,
`#15171B`·`#202329` surface, `#F4D600` accent, 20pt 주요 시간 위계를 적용했다. 최종 자동 감사에서
386개 text의 허용되지 않은 font family, 0폭·0높이 text, 화면 경계 밖 text와 placeholder가 모두
0건이었다. 시스템 keyboard의 `SF Compact`·`SF Compact Rounded`는 시스템 소유 예외로 유지했다.
디자인·문서 작업이므로 code test는 실행하지 않았고 `git diff --check`를 통과했다.
T024는 B 전면 적용본의 사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자 피드백으로 첫 B 적용본이 기존 form layout의 리스킨에 그쳐 선택한 B 후보의 UI
구조를 반영하지 못했음을 확인했다. 첨부 screenshot을 시각 source of truth로 지정하고 iOS 26
component를 제외한 `US1 / Dark Focus 재설계 · 첨부 기준` wrapper를 새로 작성했다. GetUp Focus
Primitives·Semantic·Layout collection 3개, variable 30개와 text style 7개를 만들고 9개 393×852
화면을 `editorial header → large focus card → circular selection → condition card → bottom CTA`
구조로 처음부터 다시 구성했다. 최종 자동 감사에서 233개 text의 font 오류, 0폭·0높이 text,
화면 경계 밖 text, placeholder, 이름 없는 node 및 의도하지 않은 hardcoded fill이 모두 0건이었다.
디자인·문서 작업이므로 code test는 실행하지 않았으며 T024는 재설계본의 사용자 최종 확인과 구현
승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자 피드백에 따라 `US1 / Dark Focus 논리 플로우 · T024 재검토` wrapper를 추가했다.
규칙 작성 화면의 `START`·`END` 행을 각각 명확한 편집 진입점으로 만들고 시작·종료 선택 화면과 모든
요약·오류 상태를 24시간제로 통일했다. 장소 설정은 화면 절반 이상의 큰 지도, 중심 핀, 실제 반경 원,
반경 slider를 함께 표시하며 D안의 `집`·`회사`·`직접 입력` 진입을 유지했다. `직접 입력`은 선택한
좌표·반경을 보존한 장소 이름 화면으로 이어진다. 앱 선택, 네 조건 최종 검토, draft를 보존하는 저장
실패까지 총 11개 393×852 화면과 사용자 흐름 규칙 패널을 작성했다. 자동 점검에서 251개 text의 실제
AM/PM 표기, 임시 placeholder, 부모 frame 밖 overflow가 모두 0건이었다. 디자인·문서 작업이므로 code
test는 실행하지 않았으며 T024는 사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자가 직접 다듬은 Figma 상태를 기준으로 기존 변경을 보존하고 시작·종료 시각 화면만
시·분·AM/PM 세 열 wheel로 교체했다. 분 열은 `58`·`59`·`00`·`01`·`02`처럼 1분 단위 이동을
명시하고 최소 15분 유효성 안내를 유지했다. 규칙·홈·요약 시간 표기는 `06:00 AM` 형식으로 통일했다.
승인된 D 보완 홈 정보 구조를 Dark Focus에 맞춰 `규칙 없음`, `오늘 규칙`, `다음 예정` 3개
393×852 화면으로 추가했으며 오늘 또는 다음날, 시간, 위치·반경, 제한 앱, 규칙 수정과 새 규칙 진입을
포함했다. 최종 감사에서 전체 13개 화면의 임시 placeholder와 SF Pro 외 제품 font가 0건임을
확인했다. 디자인·명세·결정 문서 작업이므로 code test는 실행하지 않았고 T024는 사용자 최종 확인과
구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 홈 규칙의 시간과 조건이 두 card로 분리돼 서로 다른 정보처럼 보인다는 피드백을 반영했다.
`HOME-02`와 `HOME-03`에서 시간, 위치·반경, 제한 앱과 규칙 수정 행동을 하나의 353×456
`Swipeable rule card` 배경과 외곽선 안에 통합했다. card 상단에 `RULE 1 OF 3` 또는
`RULE 2 OF 3`, 하단에 page indicator와 좌우 swipe 안내를 배치해 한 page가 한 규칙임을 명확히
했다. 두 화면의 외곽 container, 투명 내부 section, swipe 안내, text overflow와 SF Pro font를
감사해 오류가 없음을 확인했다. 디자인·명세 문서 작업이므로 code test는 실행하지 않았고 T024는
사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 여러 규칙이 저장되면 모두 적용한다는 사용자 결정을 반영했다. 홈의 두 규칙 화면을
`모든 규칙 1/3`, `모든 규칙 2/3` 상태로 정리하고 `RULE n OF 3`과 page indicator로 전체 규칙 탐색을 표시했다.
홈 pager에는 저장된 모든 유효 규칙을 표시하며 오늘 적용 규칙을 먼저 두고 나머지는 다음 적용 시점
순으로 정렬한다. 현재 보이는 card와 무관하게 각 규칙은 독립적으로 동작하고 동시 충족 시 제한 앱
합집합을 적용한다. `FR-034`·`FR-035`·`FR-043`을 수정하고 `FR-044`·`DEC-021` 및 관련 task를
추가·갱신했다. 디자인·명세 문서 작업이므로 code test는 실행하지 않았고 T024는 사용자 최종 확인과
구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자가 직접 다듬은 최종 Figma를 다시 감사했다. 13개 제품 화면에서 SF Pro 외 서체,
임시 문구와 text overflow가 모두 0건이었고, 시작·종료 시각의 시·분·AM/PM wheel과 1분 단위 분 전환,
큰 지도와 반경 원, 장소 이름 직접 입력 진입, 하나로 묶인 swipe card 및 모든 규칙 pager가 유지됨을
확인했다. 사용자가 이 상태를 최종 승인해 `T024`를 완료 처리했다. 이번 작업은 디자인·문서 검수이므로
code test는 실행하지 않았으며 다음 작업은 `T025`의 실패 테스트 작성이다.
