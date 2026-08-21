# 프로젝트 상태

## 현재 기능
001-location-app-restriction

## 현재 단계
Phase 1 프로젝트 설정 진행 중

## 진행 중
없음

## 마지막 완료 작업
T006 — `design/README.md`, `design/low-fidelity/TEMPLATE.md`,
`design/high-fidelity/TEMPLATE.md`에 로우파이 승인 후 하이파이, 하이파이 승인 후 구현으로 이어지는
검토 게이트와 화면 상태·접근성·검토 결과 기록 형식을 구성함

## 다음 작업
T007 — required-reason API와 수집 데이터 없음 정책을 앱과 extension의 `PrivacyInfo.xcprivacy`에
초기 구성함

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
