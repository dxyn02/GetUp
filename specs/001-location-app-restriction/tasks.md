---
description: "시간·위치 기반 앱 사용 제한 기능의 구현 작업 목록"
---

# 작업: 시간·위치 기반 앱 사용 제한

**입력**: `/specs/001-location-app-restriction/`의 설계 문서

**선행 문서**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**테스트 원칙**: 프로젝트 헌법에 따라 핵심 비즈니스 로직 테스트는 필수다. 각 스토리의 테스트
task는 관련 구현보다 먼저 작성하고 실패를 확인한다.

**UI 원칙**: 모든 UI 구현은 해당 스토리의 로우파이 작성·검토와 하이파이 작성·검토가 완료된
후에만 시작한다.

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 선행 task 완료 후 다른 파일에서 병렬 진행 가능
- **[Story]**: spec의 사용자 스토리 추적 label
- 모든 task는 구현 또는 산출물의 정확한 파일 경로를 포함한다.

## Phase 1: 프로젝트 설정

**목적**: iOS 앱, 시스템 확장, 테스트 및 디자인 산출물의 기본 구조를 만든다.

- [x] T001 `GetUp.xcodeproj/project.pbxproj`에 iOS 17+ 앱, `GetUpDeviceActivityMonitor`, `GetUpShieldConfiguration`, `GetUpShieldAction`, `GetUpTests`, `GetUpUITests` target과 scheme을 생성한다
- [x] T002 [P] Swift 6.3, deployment target, bundle identifier 상속 규칙을 `Configuration/Base.xcconfig`, `Configuration/Debug.xcconfig`, `Configuration/Release.xcconfig`에 설정한다
- [x] T003 [P] Family Controls와 App Group capability를 `GetUp/GetUp.entitlements`, `GetUpDeviceActivityMonitor/GetUpDeviceActivityMonitor.entitlements`, `GetUpShieldConfiguration/GetUpShieldConfiguration.entitlements`, `GetUpShieldAction/GetUpShieldAction.entitlements`에 구성한다
- [x] T004 [P] 위치 권한 설명과 extension principal class를 `GetUp/Resources/Info.plist`, `GetUpDeviceActivityMonitor/Info.plist`, `GetUpShieldConfiguration/Info.plist`, `GetUpShieldAction/Info.plist`에 구성하고, region monitoring 외 지속적인 background location update 및 일반 background processing mode는 활성화하지 않는다
- [x] T005 [P] unit·integration·UI test bundle과 실행 순서를 `GetUp.xctestplan` 및 `GetUp.xcodeproj/xcshareddata/xcschemes/GetUp.xcscheme`에 구성한다
- [x] T006 [P] 로우파이·하이파이 링크, 화면 상태, 접근성, 검토 결과를 기록할 `design/README.md`, `design/low-fidelity/TEMPLATE.md`, `design/high-fidelity/TEMPLATE.md`를 생성한다
- [x] T007 [P] required-reason API와 수집 데이터 없음 정책을 `GetUp/Resources/PrivacyInfo.xcprivacy` 및 각 extension의 `PrivacyInfo.xcprivacy`에 초기 구성한다
- [x] T008 [P] 색상·아이콘·문자열 resource scaffold를 `GetUp/Resources/Assets.xcassets`와 `GetUp/Resources/Localizable.xcstrings`에 생성한다

**Checkpoint**: 앱·확장·테스트·디자인 작업을 시작할 수 있는 프로젝트 구조가 준비된다.

---

## Phase 2: 공통 기반

**목적**: 모든 사용자 스토리가 공유하는 모델, 계약, 상태 머신, 저장소를 구현한다.

**⚠️ 중요**: 이 phase가 완료되기 전에는 사용자 스토리 구현을 시작하지 않는다.

- [x] T009 [P] App Group, 파일명, named Managed Settings store, activity name 규칙을 `GetUp/Core/Configuration/SharedIdentifiers.swift`에 정의한다
- [ ] T010 [P] `Weekday`, `TimeOfDay`, `RadiusOption`, `ReferenceLocation`, `RestrictionRuleSnapshot`을 `GetUp/Core/Models/RestrictionRuleModels.swift`에 구현한다
- [ ] T011 [P] `LocationConditionSnapshot`, `AuthorizationSnapshot`, `RestrictionPresentationState`를 `GetUp/Core/Models/RuntimeStateModels.swift`에 구현한다
- [ ] T012 [P] `Clock`, `RuleRepository`, `LocationConditionRepository`, `AuthorizationProviding`, `ScheduleManaging`, `LocationMonitoring`, `RestrictionApplying` 계약을 `GetUp/Core/Contracts/PlatformContracts.swift`에 정의한다
- [ ] T013 [P] `EvaluationInput`, `EvaluationDecision`, `RestrictionEffect`, `EvaluationReason`을 `GetUp/Core/Evaluation/RestrictionEvaluationModels.swift`에 정의한다
- [ ] T014 [P] 고정 clock, calendar, rule, 위치, 권한 fake를 `GetUpTests/Support/TestFixtures.swift`에 구현한다
- [ ] T015 제한 상태 전체 행렬, 시간 종료 우선순위, 위치 `unavailable` 보존, idempotency의 실패 테스트를 `GetUpTests/Core/RestrictionStateMachineTests.swift`에 작성한다
- [ ] T016 T015를 통과하도록 순수 `RestrictionStateMachine`을 `GetUp/Core/StateMachine/RestrictionStateMachine.swift`에 구현한다
- [ ] T017 보호된 JSON round-trip, 파일 없음, 손상 JSON, 미지원 schema, revision 불일치, atomic write 실패의 실패 테스트를 `GetUpTests/Persistence/SharedSnapshotRepositoryTests.swift`에 작성한다
- [ ] T018 T017을 통과하도록 단일 writer atomic 저장과 `completeUntilFirstUserAuthentication` 보호를 `GetUp/Infrastructure/Persistence/SharedSnapshotRepository.swift`에 구현한다
- [ ] T019 앱과 extension에서 동일한 core dependency를 조립하도록 `GetUp/App/DependencyContainer.swift`를 구현한다
- [ ] T020 좌표·앱 token을 기록하지 않는 진단 event와 오류 분류를 `GetUp/Infrastructure/Diagnostics/DiagnosticsLogger.swift`에 구현한다

**Checkpoint**: Foundation 완료 — 상태 판정과 공유 저장을 fake dependency로 독립 검증할 수 있다.

---

## Phase 3: 사용자 스토리 1 — 제한 조건 설정 (Priority: P1)

**목표**: 사용자가 요일, 15분 이상 시간대, 지도 핀 또는 현재 위치, 500m/1km 반경, 제한 앱을
단일 규칙으로 저장하고 다시 확인한다.

**독립 테스트**: 앱 제한을 실제 적용하지 않아도 프리셋·직접 시간·자정 초과·요일·지도 핀·현재
위치·반경·앱 선택을 포함한 유효 규칙을 저장하고 재실행 후 동일하게 불러올 수 있다.

### 로우파이 및 하이파이

- [ ] T021 [US1] 규칙 편집, 시간 프리셋, 요일, 반경, 앱 선택, 지도 핀, 현재 위치, 저장 오류 흐름의 로우파이를 제작하고 Figma 링크와 상태 설명을 `design/low-fidelity/US1-rule-configuration.md`에 기록한다
- [ ] T022 [US1] US1 로우파이를 사용자와 검토해 피드백·변경 사항·승인 여부를 `design/low-fidelity/US1-rule-configuration.md`에 반영한다
- [ ] T023 [US1] 승인된 로우파이를 기준으로 Dynamic Type, VoiceOver, 색상·간격·component 상태를 포함한 하이파이를 제작하고 Figma 링크와 규격을 `design/high-fidelity/US1-rule-configuration.md`에 기록한다
- [ ] T024 [US1] US1 하이파이를 사용자와 검토해 구현 승인 상태와 최종 변경 사항을 `design/high-fidelity/US1-rule-configuration.md`에 기록한다

### 테스트

- [ ] T025 [P] [US1] 14/15분 경계, 프리셋, 선택 요일, 같은 날·자정 초과·DST 시간 계산을 `GetUpTests/Core/ScheduleEvaluatorTests.swift`에, 요일·좌표·반경·앱 token 누락과 같은 시작·종료 및 14/15분 validation 실패를 `GetUpTests/Core/RestrictionRuleValidatorTests.swift`에 먼저 작성한다
- [ ] T026 [P] [US1] 지도 이동, 현재 위치 바로가기, When In Use 권한 없음, 확인·취소 상태와 현재 위치 조회 adapter의 실패 테스트를 `GetUpTests/Core/LocationPickerModelTests.swift`, `GetUpTests/Integration/CurrentLocationProviderTests.swift`에 작성한다
- [ ] T027 [P] [US1] 규칙 입력, validation, 앱 선택, 저장 및 재로딩 흐름의 실패 UI test를 `GetUpUITests/UserStory1RuleConfigurationUITests.swift`에 작성한다

### 구현

- [ ] T028 [P] [US1] T025를 통과하도록 요일·자정·DST 시간 판정을 `GetUp/Core/Evaluation/ScheduleEvaluator.swift`에 구현한다
- [ ] T029 [P] [US1] T025의 validation 테스트를 통과하도록 15분, 요일, 좌표, 반경, 앱 token validation을 `GetUp/Core/Evaluation/RestrictionRuleValidator.swift`에 구현한다
- [ ] T030 [P] [US1] T026을 통과하도록 지도 중심·핀 후보·현재 위치·When In Use 권한 없음 상태를 `GetUp/Features/LocationPicker/LocationPickerModel.swift`에 구현하고 현재 위치 바로가기용 단발성 위치·권한 adapter를 `GetUp/Infrastructure/Location/CurrentLocationProvider.swift`에 구현한다
- [ ] T031 [US1] 승인된 하이파이와 `location-picker-ui-contract.md`에 맞춰 MapKit 지도 핀과 현재 위치 바로가기를 `GetUp/Features/LocationPicker/LocationPickerView.swift`에 구현한다
- [ ] T032 [P] [US1] 개인용 Family Controls 승인과 `FamilyActivityPicker` 선택 결과를 `GetUp/Infrastructure/ScreenTime/FamilyActivitySelectionAdapter.swift`에 구현한다
- [ ] T033 [P] [US1] 시간 프리셋, 요일, 반경 선택 component를 `GetUp/Features/RuleEditor/Components/TimeRangePicker.swift`, `WeekdayPicker.swift`, `RadiusPicker.swift`에 구현한다
- [ ] T034 [US1] 편집 draft, validation, 단일 규칙 저장·불러오기를 `GetUp/Features/RuleEditor/RuleEditorModel.swift`에 구현한다
- [ ] T035 [US1] 승인된 하이파이에 맞춰 규칙 편집과 기준 위치·앱 선택 진입을 `GetUp/Features/RuleEditor/RuleEditorView.swift`에 구현한다
- [ ] T036 [US1] 규칙 aggregate 저장과 revision 증가를 `GetUp/Features/RuleEditor/RuleConfigurationService.swift`에 구현한다
- [ ] T037 [US1] 앱 시작 시 저장된 단일 규칙을 불러오고 편집 화면으로 연결하도록 `GetUp/App/GetUpApp.swift`와 `GetUp/App/AppModel.swift`를 구현한다

**Checkpoint**: US1을 독립 실행해 유효 규칙의 생성·저장·재로딩을 검증할 수 있다.

---

## Phase 4: 사용자 스토리 2 — 조건 충족 시 선택 앱 제한 (Priority: P1)

**목표**: 선택 요일·시간대와 신뢰 가능한 내부 위치가 모두 충족되면 선택 앱에 GetUp shield를
적용하고 비대상 앱은 제한하지 않는다.

**독립 테스트**: fake 시간·위치와 테스트 앱 선택으로 두 조건의 AND 조합, 앱 비실행 상태의
interval 시작, 대상·비대상 앱 shield를 검증한다.

### 로우파이 및 하이파이

- [ ] T038 [US2] 제한 활성 상태 화면과 restricted-app shield의 제목·설명·닫기 흐름 로우파이를 제작하고 Figma 링크와 상태 설명을 `design/low-fidelity/US2-active-restriction.md`에 기록한다
- [ ] T039 [US2] US2 로우파이를 사용자와 검토해 피드백·변경 사항·승인 여부를 `design/low-fidelity/US2-active-restriction.md`에 반영한다
- [ ] T040 [US2] 승인된 로우파이와 `shield-ui-contract.md`를 기준으로 접근성·명암·Dynamic Type을 포함한 하이파이를 제작하고 Figma 링크와 규격을 `design/high-fidelity/US2-active-restriction.md`에 기록한다
- [ ] T041 [US2] US2 하이파이를 사용자와 검토해 구현 승인 상태와 최종 변경 사항을 `design/high-fidelity/US2-active-restriction.md`에 기록한다

### 테스트

- [ ] T042 [P] [US2] 선택 요일별 일정 등록, 15분 오류, 자정 초과, 기존 일정 교체의 실패 테스트를 `GetUpTests/Integration/DeviceActivityScheduleAdapterTests.swift`에 작성한다
- [ ] T043 [P] [US2] 500m/1km 내부·경계·외부·오차 중첩 및 위치 snapshot 기록의 실패 테스트를 `GetUpTests/Integration/LocationMonitoringAdapterTests.swift`에 작성한다
- [ ] T044 [P] [US2] 선택 앱만 shield 적용, 동일 revision 무효과, 다른 store 보존의 실패 테스트를 `GetUpTests/Integration/ManagedSettingsRestrictionAdapterTests.swift`에 작성한다
- [ ] T045 [P] [US2] 시간 활성 × 위치 내부에서만 제한되고 비대상 앱은 열리는 실패 UI test를 `GetUpUITests/UserStory2RestrictionActivationUITests.swift`에 작성한다

### 구현

- [ ] T046 [P] [US2] 선택 요일별 `DeviceActivitySchedule` 등록·교체·복구를 `GetUp/Infrastructure/Scheduling/DeviceActivityScheduleAdapter.swift`에 구현한다
- [ ] T047 [P] [US2] 거리·horizontal accuracy 판정 공식을 `GetUp/Infrastructure/Location/LocationEvidenceEvaluator.swift`에 구현한다
- [ ] T048 [US2] Always·Full Accuracy 아래 원형 region 등록과 최신 위치 snapshot 갱신을 `GetUp/Infrastructure/Location/LocationMonitor.swift`에 구현한다
- [ ] T049 [P] [US2] named `ManagedSettingsStore`의 선택 앱 shield 적용을 `GetUp/Infrastructure/ScreenTime/ManagedSettingsRestrictionAdapter.swift`에 구현한다
- [ ] T050 [US2] 시간·위치 event를 상태 머신과 restriction adapter에 연결하는 활성화 경로를 `GetUp/Infrastructure/ScreenTime/RestrictionCoordinator.swift`에 구현한다
- [ ] T051 [US2] 앱 비실행 상태의 `intervalDidStart`와 재부팅 뒤 첫 잠금 해제 이후 전달되는 시스템 event에서 공유 snapshot을 읽고 권한·일정·region·제한 상태를 복구하도록 `GetUpDeviceActivityMonitor/DeviceActivityMonitorExtension.swift`, `GetUp/App/AppLifecycleCoordinator.swift`를 구현한다
- [ ] T052 [US2] 승인된 하이파이에 맞는 shield 제목·설명·아이콘·닫기 버튼을 `GetUpShieldConfiguration/ShieldConfigurationExtension.swift`에 구현한다
- [ ] T053 [US2] 우회 없이 제한 앱을 닫는 primary action을 `GetUpShieldAction/ShieldActionExtension.swift`에 구현한다
- [ ] T054 [US2] 규칙 저장 성공 후 일정·region 등록과 초기 상태 평가를 연결하도록 `GetUp/Features/RuleEditor/RuleConfigurationService.swift`를 확장한다
- [ ] T055 [US2] 승인된 하이파이에 맞춰 현재 활성 상태와 종료 조건을 `GetUp/Features/RestrictionStatus/RestrictionStatusView.swift` 및 `RestrictionStatusModel.swift`에 구현한다

**Checkpoint**: US1+US2로 설정부터 조건 충족 시 실제 선택 앱 제한까지 첫 사용 가능한 MVP를 검증한다.

---

## Phase 5: 사용자 스토리 3 — 조건 종료 시 자동 해제 (Priority: P2)

**목표**: 신뢰 가능한 위치 이탈 또는 시간 종료가 확인되면 30초 이내에 제한을 해제하고, 활성
중 앱 내부 편집·끄기·삭제를 막는다.

**독립 테스트**: 활성 상태에서 위치 외부 event와 interval 종료를 각각 발생시켜 shield 해제를
검증하고, 해제 전 편집 요청은 거부되며 해제 후 허용되는지 확인한다.

### 로우파이 및 하이파이

- [ ] T056 [US3] 활성 중 편집 차단, 종료 조건 안내, 자동 해제 완료 상태의 로우파이를 제작하고 Figma 링크와 상태 설명을 `design/low-fidelity/US3-auto-release.md`에 기록한다
- [ ] T057 [US3] US3 로우파이를 사용자와 검토해 피드백·변경 사항·승인 여부를 `design/low-fidelity/US3-auto-release.md`에 반영한다
- [ ] T058 [US3] 승인된 로우파이를 기준으로 차단 안내와 해제 전환의 하이파이를 제작하고 Figma 링크와 접근성 규격을 `design/high-fidelity/US3-auto-release.md`에 기록한다
- [ ] T059 [US3] US3 하이파이를 사용자와 검토해 구현 승인 상태와 최종 변경 사항을 `design/high-fidelity/US3-auto-release.md`에 기록한다

### 테스트

- [ ] T060 [P] [US3] 시간 종료·신뢰 가능한 위치 이탈·위치 `unavailable`·반복 해제의 실패 테스트를 `GetUpTests/Core/RestrictionReleaseTests.swift`에 작성한다
- [ ] T061 [P] [US3] 활성 중 편집·끄기·삭제 거부와 해제 후 허용의 실패 UI test를 `GetUpUITests/UserStory3AutoReleaseUITests.swift`에 작성한다

### 구현

- [ ] T062 [US3] 위치 이탈과 시간 종료의 remove effect 및 30초 측정 event를 `GetUp/Infrastructure/ScreenTime/RestrictionCoordinator.swift`에 구현한다
- [ ] T063 [US3] `intervalDidEnd`에서 위치와 무관하게 GetUp shield를 제거하도록 `GetUpDeviceActivityMonitor/DeviceActivityMonitorExtension.swift`를 구현한다
- [ ] T064 [US3] 활성 제한 중 편집·끄기·삭제 guard와 종료 조건 안내를 `GetUp/Features/RuleEditor/RuleEditorModel.swift` 및 `GetUp/Features/RestrictionStatus/RestrictionStatusView.swift`에 구현한다
- [ ] T065 [US3] 해제 후 규칙 편집 재진입과 상태 갱신을 `GetUp/App/AppModel.swift`에 연결한다

**Checkpoint**: US3을 독립 검증해 두 자동 해제 경로와 활성 중 앱 내부 우회 차단을 확인한다.

---

## Phase 6: 사용자 스토리 4 — 권한 및 위치 문제 안내 (Priority: P2)

**목표**: 필수 권한 부족, Reduced Accuracy, Background App Refresh 제한, 위치 확인 불가의 원인과
복구 방법을 알리고 잘못된 위치 판단으로 제한 상태를 바꾸지 않는다.

**독립 테스트**: 각 권한 거부·철회와 위치 오류·오래된 위치·경계 중첩을 주입해 안내 상태, 새
제한 미적용, 기존 제한 보존, 시간 종료 해제를 각각 검증한다.

### 로우파이 및 하이파이

- [ ] T066 [US4] 권한 종류별 안내, 시스템 설정 이동, 위치 확인 불가, 재선택 흐름의 로우파이를 제작하고 Figma 링크와 상태 설명을 `design/low-fidelity/US4-permission-location-errors.md`에 기록한다
- [ ] T067 [US4] US4 로우파이를 사용자와 검토해 피드백·변경 사항·승인 여부를 `design/low-fidelity/US4-permission-location-errors.md`에 반영한다
- [ ] T068 [US4] 승인된 로우파이를 기준으로 오류별 hierarchy, icon, 문구, 접근성을 포함한 하이파이를 제작하고 Figma 링크와 규격을 `design/high-fidelity/US4-permission-location-errors.md`에 기록한다
- [ ] T069 [US4] US4 하이파이를 사용자와 검토해 구현 승인 상태와 최종 변경 사항을 `design/high-fidelity/US4-permission-location-errors.md`에 기록한다

### 테스트

- [ ] T070 [P] [US4] Family Controls, Always, Full Accuracy, Background App Refresh 상태 합성의 실패 테스트를 `GetUpTests/Integration/AuthorizationAdapterTests.swift`에 작성한다
- [ ] T071 [P] [US4] 위치 오류·오래된 fix·음수 accuracy·경계 중첩에서 상태를 보존하는 실패 테스트를 `GetUpTests/Core/LocationUnavailableTests.swift`에 작성한다
- [ ] T072 [P] [US4] 권한별 안내와 위치 확인 불가 복구 흐름의 실패 UI test를 `GetUpUITests/UserStory4PermissionGuidanceUITests.swift`에 작성한다

### 구현

- [ ] T073 [P] [US4] Family Controls·위치·정확도·Background App Refresh 상태와 설정 URL을 `GetUp/Infrastructure/Permissions/AuthorizationAdapter.swift`에 구현한다
- [ ] T074 [US4] 권한별 원인·복구·앱 재선택 상태를 `GetUp/Features/PermissionGuide/PermissionGuideModel.swift`에 구현한다
- [ ] T075 [US4] 승인된 하이파이에 맞춰 권한 및 설정 안내를 `GetUp/Features/PermissionGuide/PermissionGuideView.swift`에 구현한다
- [ ] T076 [US4] 위치 확인 불가에서 기존 shield를 보존하고 시간 종료는 해제하도록 `GetUp/Infrastructure/ScreenTime/RestrictionCoordinator.swift`를 확장한다
- [ ] T077 [US4] foreground 진입과 권한 변경 시 권한·일정·region·snapshot을 재평가하고 권한 안내 상태를 갱신하도록 `GetUp/App/AppLifecycleCoordinator.swift`를 확장한다

**Checkpoint**: US4를 독립 검증해 사용자가 기능 미동작 원인을 이해하고 안전하게 복구할 수 있다.

---

## Phase 7: 마무리 및 교차 관심사

**목적**: 전체 스토리의 접근성, 개인정보 보호, 성능, 실기기 동작 및 문서를 검증한다.

- [ ] T078 [P] Dynamic Type, VoiceOver, Reduce Motion, 명암 및 색상 외 상태 표현을 `GetUpUITests/AccessibilityUITests.swift`에 검증한다
- [ ] T079 [P] 좌표와 앱 token이 log·analytics에 기록되지 않는지 `GetUpTests/Integration/PrivacyLoggingTests.swift`와 `GetUp/Infrastructure/Diagnostics/DiagnosticsLogger.swift`에서 검증·보강한다
- [ ] T080 [P] Family Controls 배포 entitlement와 App Group 설정·승인 절차를 `docs/ENTITLEMENTS.md`에 한국어로 문서화하고 app 및 각 extension bundle ID의 신청·승인 상태와 확인 증적을 기록한다
- [ ] T081 신뢰 가능한 event timestamp부터 실제 `ManagedSettingsStore` 반영 확인까지 활성화·해제 경로를 각각 100회 이상 계측해 활성화 p95 30초 이내와 모든 해제 사례 30초 이내를 판정하고, 자동 계측과 실기기 관찰을 구분한 결과 형식을 `GetUpTests/Performance/RestrictionLatencyTests.swift`, `docs/TEST_RESULTS.md`에 구현한다
- [ ] T082 `GetUp.xctestplan`의 전체 Swift Testing·XCTest suite를 실행하고 실패·skip·미검증 동작을 `docs/STATUS.md`와 `docs/TEST_RESULTS.md`에 한국어로 기록한다
- [ ] T083 `specs/001-location-app-restriction/quickstart.md`의 500m/1km, background/terminated, 재부팅 첫 잠금 해제, 권한 철회, 자정 초과 시나리오를 실기기에서 수행하고 결과를 `docs/TEST_RESULTS.md`에 기록한다
- [ ] T084 구현과 설계 차이를 `design/high-fidelity/US1-rule-configuration.md`, `US2-active-restriction.md`, `US3-auto-release.md`, `US4-permission-location-errors.md`에서 대조하고 승인되지 않은 편차를 수정한다
- [ ] T085 [P] 신규 사용자가 안내 없이 유효 규칙을 저장하는 과제의 참여자 기준·시작·종료·성공 정의와 3분 이내 완료율 측정 절차를 `docs/USABILITY_TEST_PLAN.md`에 작성하고 SC-001 결과를 `docs/USABILITY_TEST_RESULTS.md`에 기록한다
- [ ] T086 [P] 제한 활성 여부와 권한·위치 문제 해결 방법을 첫 시도에 설명하는 상태별 과제와 85% 이해 기준을 `docs/USABILITY_TEST_PLAN.md`에 작성하고 SC-007 결과를 `docs/USABILITY_TEST_RESULTS.md`에 기록한다
- [ ] T087 spec·plan·contract·결정 문서 추적성과 알려진 제약, entitlement 승인, 성능·사용성·실기기 검증 결과를 검토해 `docs/DECISIONS.md`, `docs/BLOCKERS.md`, `docs/STATUS.md`를 한국어로 최종 갱신한다

**Checkpoint**: 자동 테스트, 필수 실기기 검증, entitlement 승인 및 SC-001·SC-007 사용성 평가가
모두 기록된 경우에만 feature 완료로 표시한다.

---

## 의존성과 실행 순서

### Phase 의존성

- **Phase 1 프로젝트 설정**: 즉시 시작 가능
- **Phase 2 공통 기반**: Phase 1 완료 후 시작하며 모든 사용자 스토리를 차단
- **US1 Phase 3**: Phase 2 완료 후 시작
- **US2 Phase 4**: Phase 2 완료 후 core 구현은 시작할 수 있으나, 첫 사용 가능한 MVP 통합은 US1 규칙 저장이 필요
- **US3 Phase 5**: US2의 제한 활성화 경로 완료 후 시작
- **US4 Phase 6**: Phase 2 후 core·테스트는 병렬 시작 가능하며 최종 복구 통합은 US1·US2가 필요
- **Phase 7 마무리**: 포함하려는 모든 사용자 스토리 완료 후 시작

### UI 설계 gate

- 각 사용자 스토리의 로우파이 작성 → 사용자 검토·승인 → 하이파이 작성 → 사용자 검토·승인을
  순서대로 완료한다.
- 해당 하이파이 승인 task가 `[x]`가 되기 전에는 같은 스토리의 SwiftUI 또는 shield UI 구현
  task를 시작하지 않는다.
- core test와 비-UI adapter는 같은 스토리의 디자인 검토와 병렬 진행할 수 있다.

### 사용자 스토리 의존성

- **US1 (P1)**: 단일 규칙 설정·저장과 현재 위치 바로가기를 포함한 slice로 독립 검증 가능
- **US2 (P1)**: 제한 engine과 앱 비실행·첫 잠금 해제 이후 자동 복구를 검증할 수 있지만 실제 사용자 설정 통합은 US1에 의존
- **US3 (P2)**: US2의 활성 제한을 해제하므로 US2에 의존
- **US4 (P2)**: 안내 UI는 독립 검증 가능하며 전체 복구 wiring은 US1·US2에 의존

### 스토리 내부 순서

1. 로우파이와 검토
2. 하이파이와 검토
3. 테스트 작성 및 실패 확인
4. 모델·service·adapter 구현
5. 승인된 UI 구현
6. 독립 테스트 실행

## 병렬 실행 기회

- Phase 1의 `[P]` 설정 task는 T001 뒤 서로 다른 파일에서 병렬 수행 가능하다.
- Phase 2의 모델·contract·fixture task는 병렬 수행 가능하다.
- US1에서 일정, 위치 선택, UI acceptance test는 병렬 작성 가능하다.
- US2에서 일정, 위치, Managed Settings adapter test와 구현은 서로 다른 파일에서 병렬화 가능하다.
- US4의 권한 adapter test와 위치 불가 core test는 병렬 수행 가능하다.
- Phase 2 후 US1 디자인과 US2·US4의 비-UI core test 준비를 병렬 수행할 수 있다.

### 병렬 예시: US1

```text
Task T025: GetUpTests/Core/ScheduleEvaluatorTests.swift, GetUpTests/Core/RestrictionRuleValidatorTests.swift
Task T026: GetUpTests/Core/LocationPickerModelTests.swift, GetUpTests/Integration/CurrentLocationProviderTests.swift
Task T027: GetUpUITests/UserStory1RuleConfigurationUITests.swift
```

### 병렬 예시: US2

```text
Task T042: GetUpTests/Integration/DeviceActivityScheduleAdapterTests.swift
Task T043: GetUpTests/Integration/LocationMonitoringAdapterTests.swift
Task T044: GetUpTests/Integration/ManagedSettingsRestrictionAdapterTests.swift
Task T045: GetUpUITests/UserStory2RestrictionActivationUITests.swift
```

### 병렬 예시: US4

```text
Task T070: GetUpTests/Integration/AuthorizationAdapterTests.swift
Task T071: GetUpTests/Core/LocationUnavailableTests.swift
Task T072: GetUpUITests/UserStory4PermissionGuidanceUITests.swift
```

## 구현 전략

### 첫 사용 가능한 MVP

1. Phase 1 프로젝트 설정 완료
2. Phase 2 공통 기반 완료
3. US1 로우파이·하이파이 승인 후 설정·저장 구현 및 독립 검증
4. US2 로우파이·하이파이 승인 후 조건 결합·shield 구현 및 독립 검증
5. **중단 후 검증**: US1+US2로 설정부터 실제 제한, 앱 비실행 상태와 재부팅 뒤 첫 잠금 해제
   이후 자동 복구까지 end-to-end 검증

US1만으로도 설정 slice는 검증할 수 있지만 제품의 핵심 가치인 앱 사용 제한을 제공하지 않으므로,
첫 사용 가능한 MVP 범위는 US1+US2다.

### 점진적 전달

1. Setup + Foundation → 테스트 가능한 core
2. US1 → 규칙 설정·저장
3. US2 → 첫 사용 가능한 MVP
4. US3 → 자동 해제와 활성 중 우회 차단
5. US4 → 권한·위치 오류 안내와 복구
6. Polish → 접근성·개인정보·성능·실기기 승인

## 참고

- `[P]`는 파일 충돌과 미완료 dependency가 없는 task에만 표시한다.
- `[USn]`은 spec의 사용자 스토리와 직접 추적된다.
- 테스트 task는 관련 구현 전에 실패를 확인한다.
- task 또는 작은 논리적 task group 완료마다 `tasks.md` 체크박스와 `docs/STATUS.md`를 갱신한다.
- blocker가 발생하면 `docs/BLOCKERS.md`와 `docs/STATUS.md`를 한국어로 갱신하고 사용자 결정을 기다린다.
- 중요한 architecture 변경은 `docs/DECISIONS.md`에 한국어로 기록한다.
