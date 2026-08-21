# 프로젝트 상태

## 현재 기능
001-location-app-restriction

## 현재 단계
Phase 2 공통 기반 진행 중

## 진행 중
없음

## 마지막 완료 작업
T009 — `SharedIdentifiers.swift`에 공유 snapshot 파일명, named Managed Settings store 및 요일별
Device Activity name 규칙을 정의하고, App Group identifier를 네 bundle의 build setting 기반
`Info.plist` 값에서 읽도록 구성함

## 다음 작업
T010 — 제한 규칙의 `Weekday`, `TimeOfDay`, `RadiusOption`, `ReferenceLocation`,
`RestrictionRuleSnapshot` 모델을 구현함

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
