# Entitlement 및 App Group 배포 준비

## 문서 목적

이 문서는 GetUp의 Family Controls 배포 entitlement와 App Group을 Apple Developer 계정에 구성하고,
app 및 세 Screen Time extension의 신청·승인·provisioning 상태를 같은 기준으로 확인하기 위한
운영 기록이다.

- 기준일: `2026-08-25`
- 대상 환경: iOS 26 이상, TestFlight 및 App Store 배포
- Family Controls entitlement: `com.apple.developer.family-controls`
- App Group entitlement: `com.apple.security.application-groups`
- App Group identifier: `group.com.getup.GetUp`

## 상태 정의

| 상태 | 의미 |
|---|---|
| `확인됨` | 저장소, Apple Developer 계정 또는 서명 산출물의 확인 가능한 증적이 있다. |
| `확인 필요` | 필요한 구성이지만 현재 저장소와 로컬 서명 환경만으로 계정 상태를 확인할 수 없다. |
| `해당 없음` | 대상 target 또는 배포 방식에 필요하지 않다. |

`확인 필요`는 미신청 또는 거절을 의미하지 않는다. Account Holder가 Apple Developer 계정에서
상태와 증적을 확인하기 전까지 승인 완료로 간주하지 않는다는 뜻이다.

## 대상 식별자와 현재 상태

| 실행 target | Bundle ID | entitlement 파일 | 로컬 Family Controls | 로컬 App Group | Apple App ID·그룹 할당 | Family Controls 배포 요청·승인 | 배포 profile |
|---|---|---|---|---|---|---|---|
| `GetUp` | `com.getup.GetUp` | `GetUp/GetUp.entitlements` | `확인됨` | `확인됨` | `확인 필요` | `확인 필요` | `확인 필요` |
| `GetUpDeviceActivityMonitor` | `com.getup.GetUp.DeviceActivityMonitor` | `GetUpDeviceActivityMonitor/GetUpDeviceActivityMonitor.entitlements` | `확인됨` | `확인됨` | `확인 필요` | `확인 필요` | `확인 필요` |
| `GetUpShieldConfiguration` | `com.getup.GetUp.ShieldConfiguration` | `GetUpShieldConfiguration/GetUpShieldConfiguration.entitlements` | `확인됨` | `확인됨` | `확인 필요` | `확인 필요` | `확인 필요` |
| `GetUpShieldAction` | `com.getup.GetUp.ShieldAction` | `GetUpShieldAction/GetUpShieldAction.entitlements` | `확인됨` | `확인됨` | `확인 필요` | `확인 필요` | `확인 필요` |

### 저장소에서 확인한 증적

- 네 target의 resolved `PRODUCT_BUNDLE_IDENTIFIER`가 위 표와 일치한다.
- 네 entitlement 파일 모두 `com.apple.developer.family-controls = true`를 선언한다.
- 네 entitlement 파일 모두 `$(GETUP_APP_GROUP_IDENTIFIER)`를 App Group으로 선언한다.
- `Configuration/Base.xcconfig`의 resolved 값은
  `GETUP_APP_GROUP_IDENTIFIER = group.com.getup.GetUp`이다.
- 네 target 모두 자신의 entitlement 파일을 `CODE_SIGN_ENTITLEMENTS`로 지정한다.
- 저장소와 현재 build setting에는 `DEVELOPMENT_TEAM`, 배포 provisioning profile 지정 또는
  Apple Developer의 Capability Requests 상태 증적이 없다.
- 저장소에 `.mobileprovision`, `.provisionprofile`, `.cer` 파일을 보관하지 않는다.

마지막 두 항목은 보안상 정상적인 저장소 정책일 수 있으므로 미승인을 뜻하지 않는다. 다만 계정
화면이나 서명된 archive 증적이 없으므로 현재 상태는 `확인 필요`다.

## Family Controls 배포 entitlement 절차

Apple은 Family Controls를 사용하는 앱을 배포하기 전에 Apple Developer Account Holder가 배포
entitlement 사용 권한을 요청하도록 요구한다. Screen Time API app extension이 있으면 extension에도
같은 요청을 제출해야 한다. GetUp은 메인 앱과 extension 세 개가 있으므로 Bundle ID별로 총 네 건의
상태를 확인해야 한다.

1. Account Holder로 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/)에 로그인한다.
2. `Identifiers`에서 대상 Bundle ID를 선택한다.
3. `Capability Requests`에서 `Family Controls` 배포 권한을 요청한다.
4. GetUp의 개인용 authorization, Device Activity 일정 감시, Managed Settings shield, 사용자 선택
   token의 기기 내 처리와 앱 내부 우회 차단 범위를 요청서에 정확히 설명한다.
5. 위 과정을 메인 앱과 세 extension Bundle ID에 각각 반복한다.
6. 요청 상세에서 상태가 `Assigned`인지 확인한다.
7. 정보 버튼의 `Provisioning Support`에서 실제 필요한 Development, Ad Hoc, App Store 배포 방식이
   지원되는지 확인한다. TestFlight는 App Store 배포 profile 경로로 검증한다.

공식 근거:

- [Family Controls entitlement 요청](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [관리형 기능 액세스 권한 요청](https://developer.apple.com/kr/help/account/capabilities/capability-requests/)
- [Xcode에서 Family Controls 구성](https://developer.apple.com/documentation/xcode/configuring-family-controls)

## App Group 등록 및 App ID 할당 절차

1. Account Holder 또는 Admin으로 `Certificates, Identifiers & Profiles`에 로그인한다.
2. `Identifiers`에서 App Group `group.com.getup.GetUp`이 등록되어 있는지 확인하고, 없다면
   `App Groups` 유형으로 등록한다.
3. 네 명시적 App ID 각각의 `Capabilities`에서 `App Groups`를 활성화한다.
4. `Configure`에서 `group.com.getup.GetUp`을 선택하고 `Assign`한다.
5. Xcode의 네 target에서 같은 App Group이 선택되는지 확인한다.

공식 근거:

- [App Group 등록](https://developer.apple.com/kr/help/account/manage-identifiers/register-an-app-group/)
- [앱 기능 및 App Group 활성화](https://developer.apple.com/kr/help/account/identifiers/enable-app-capabilities/)
- [Xcode에서 App Group 구성](https://developer.apple.com/documentation/xcode/configuring-app-groups)

## Provisioning profile 갱신

App ID capability가 변경되면 기존 profile은 더 이상 현재 구성을 대표하지 않으므로 네 Bundle ID의
profile을 모두 갱신한다.

### 자동 서명

1. 네 target의 Signing & Capabilities에서 같은 Team과 automatic signing을 선택한다.
2. Family Controls와 App Groups가 각 target에 표시되는지 확인한다.
3. 승인된 managed capability를 반영해 Xcode가 새 profile을 생성하도록 실기기 build 또는 archive를
   수행한다.

### 수동 서명

1. 각 App ID에서 Family Controls와 App Group 할당을 완료한다.
2. Development, 필요 시 Ad Hoc, App Store Connect profile을 Bundle ID별로 재생성한다.
3. profile의 `Enabled Capabilities`에서 Family Controls와 App Groups를 확인한다.
4. 새 profile을 내려받아 각 target에 지정하고 다시 서명한다.

공식 근거:

- [관리형 기능으로 provisioning](https://developer.apple.com/kr/help/account/reference/provisioning-with-managed-capabilities/)
- [Provisioning profile 편집·재생성](https://developer.apple.com/kr/help/account/provisioning-profiles/edit-download-or-delete-profiles/)

## 승인 증적 기록표

민감한 인증서, profile 원본, Team ID와 개인 계정 정보는 저장소에 커밋하지 않는다. screenshot은
계정명·이메일·Team ID를 가린 뒤 안전한 내부 문서 위치에 보관하고 아래에는 위치나 식별 가능한
reference만 기록한다.

| 확인 항목 | 현재 상태 | 확인일 | 확인자 | 증적 reference |
|---|---|---|---|---|
| 메인 앱 Family Controls 요청 `Assigned` | `확인 필요` | - | - | - |
| Device Activity Monitor 요청 `Assigned` | `확인 필요` | - | - | - |
| Shield Configuration 요청 `Assigned` | `확인 필요` | - | - | - |
| Shield Action 요청 `Assigned` | `확인 필요` | - | - | - |
| 네 요청의 필요한 `Provisioning Support` | `확인 필요` | - | - | - |
| App Group 등록 | `확인 필요` | - | - | - |
| App Group의 네 App ID 할당 | `확인 필요` | - | - | - |
| 네 Development profile 갱신 | `확인 필요` | - | - | - |
| 네 App Store Connect profile 갱신 | `확인 필요` | - | - | - |
| 서명된 archive entitlement 검사 | `확인 필요` | - | - | - |

## 로컬 및 archive 검증 명령

저장소 구성은 다음 항목으로 확인한다.

```sh
plutil -p GetUp/GetUp.entitlements
plutil -p GetUpDeviceActivityMonitor/GetUpDeviceActivityMonitor.entitlements
plutil -p GetUpShieldConfiguration/GetUpShieldConfiguration.entitlements
plutil -p GetUpShieldAction/GetUpShieldAction.entitlements
xcodebuild -project GetUp.xcodeproj -target <target> -showBuildSettings
```

수동 profile은 원본을 저장소에 복사하지 않고 로컬에서 다음과 같이 확인한다.

```sh
security cms -D -i <profile-path>
```

서명된 archive에서는 app과 세 `.appex` 각각에 대해 다음 명령을 실행하고 두 entitlement의 실제 값을
확인한다.

```sh
codesign -d --entitlements :- <signed-bundle-path>
```

## 배포 완료 조건

- [ ] 네 명시적 App ID가 같은 Apple Developer Team에 등록되어 있다.
- [ ] 네 App ID의 Family Controls 배포 요청이 모두 `Assigned`다.
- [ ] 각 요청의 `Provisioning Support`가 필요한 배포 방식을 포함한다.
- [ ] `group.com.getup.GetUp`이 등록되고 네 App ID에 할당되어 있다.
- [ ] 네 target의 Development 및 App Store Connect profile이 최신 capability로 생성됐다.
- [ ] 서명된 archive의 app과 세 extension에 Family Controls와 같은 App Group entitlement가 있다.
- [ ] entitlement 적용 실기기에서 Family Controls 승인, 앱 선택, 일정 callback, shield와 App Group
  공유 상태를 확인했다.

이 조건이 모두 충족되기 전에는 entitlement 배포 준비 또는 기능 전체를 완료로 표시하지 않는다.
