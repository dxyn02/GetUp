# 프로젝트 상태

## 현재 기능
001-location-app-restriction

## 현재 단계
Phase 3 사용자 스토리 1 — 로우파이 검토 준비

## 진행 중
T022 — US1 로우파이 사용자 검토 대기

## 마지막 완료 작업
T021 — US1 규칙 설정 흐름의 7개 로우파이 화면과 상태·접근성 가설을 작성함

## 다음 작업
T022 — US1 로우파이를 사용자와 검토하고 피드백·변경 사항·승인 여부를 기록함

## 차단 상태
없음

## 테스트 상태
명세 품질 체크리스트 16/16개 항목을 통과함. 계획 산출물의 구조 검증을 통과함.
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
시간 프리셋·자정 초과·15분 미만 오류·지도 핀·현재 위치 권한 부족·시스템 앱 선택·저장 실패 상태를
각각 확인함. 모든 화면이 Apple `iOS and iPadOS 26` 공식 library component와 `SF Pro`만 사용하는지,
실제 좌표·주소·app token을 포함하지 않는지, frame 직접 링크와 접근성 가설이 설계 문서에 기록됐는지
검증함. 이 task는 디자인·문서 작업이므로 code test는 실행하지 않았으며, 로우파이는 아직 사용자
승인 전이라 T022 검토와 T023 하이파이 작업이 남아 있음.
