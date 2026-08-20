# Phase 0 Research: 시간·위치 기반 앱 사용 제한

**Date**: 2026-08-20

**Status**: Research complete; product constraints resolved on 2026-08-20.

## Research Scope

Apple 공식 문서, 현재 설치된 iOS SDK 인터페이스, 프로젝트 헌법을 기준으로 Screen Time 제한,
시간 일정, 위치 모니터링, 앱·확장 간 저장, 테스트 전략을 조사했다.

## R1. 플랫폼 기준과 타깃 구조

**Decision**: iOS 17 이상, Swift 6.3, SwiftUI 앱과 Device Activity Monitor, Shield
Configuration, Shield Action 확장을 사용한다.

**Rationale**: 개인 사용자의 Family Controls 승인은 iOS 16부터 가능하고, iOS 17부터 Observation을
전 구간에서 사용할 수 있다. 신규 앱이므로 `@MainActor @Observable` 화면 모델과 Swift 6 동시성
검사를 사용하되, 핵심 판정은 UI에 독립적인 Sendable 값과 순수 함수로 유지한다.

**Alternatives considered**:

- iOS 16 + ObservableObject: 더 넓은 지원 범위가 필요할 때 가능하지만 신규 코드의 관찰 모델이
  복잡해진다.
- iOS 18 이상: 필요한 기능 없이 지원 범위만 줄인다.
- 외부 아키텍처 패키지: MVP에 불필요한 의존성과 구조를 추가한다.

**Sources**: [Apple Observation migration](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro), [Adopting Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6), [WWDC22 Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)

## R2. Family Controls 권한과 배포 entitlement

**Decision**: 개인 사용자 승인을 요청하고, 메인 앱과 모든 Screen Time 확장 App ID에 Family
Controls capability 및 배포 entitlement 승인을 준비한다.

**Rationale**: Family Controls 승인 없이는 앱 선택 및 제한을 사용할 수 없고, App Store/TestFlight
배포 전에 Apple의 entitlement 승인이 필요하다. 개인 사용자는 시스템 설정에서 승인을 철회하거나
앱을 삭제할 수 있으므로 GetUp 내부의 변경만 막고 완전한 우회 방지를 약속하지 않는다.

**Alternatives considered**:

- 부모·자녀 승인을 사용한 삭제 방지: 자기 통제 앱의 사용자 모델과 맞지 않는다.
- 시스템 권한 자동 획득: 지원되지 않는다.

**Sources**: [Family Controls](https://developer.apple.com/documentation/FamilyControls), [Requesting the entitlement](https://developer.apple.com/documentation/FamilyControls/requesting-the-family-controls-entitlement), [Individual authorization](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization%28for%3A%29)

## R3. 앱 선택과 제한 저장소

**Decision**: FamilyActivityPicker가 반환한 `FamilyActivitySelection`을 불투명 토큰 그대로
저장하고, 고정된 이름의 ManagedSettingsStore 하나로 선택 앱의 shield를 적용·해제한다.

**Rationale**: 선택 결과는 Codable이며 앱 정체를 노출하지 않는 토큰이다. iOS 16의 이름 있는
ManagedSettingsStore는 앱과 확장이 같은 이름으로 접근할 수 있다. 권한 철회 뒤 토큰이 무효화되면
새 제한을 적용하지 않고 재승인과 앱 재선택을 안내한다.

**Alternatives considered**:

- bundle identifier 직접 보관: 개인정보 보호 모델과 맞지 않고 공개 계약이 아니다.
- 앱 또는 토큰별 복수 store: 단일 규칙 MVP에 불필요하다.
- 서버 저장: 오프라인·로컬 범위를 벗어난다.

**Sources**: [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker), [FamilyActivitySelection](https://developer.apple.com/documentation/familycontrols/familyactivityselection), [ManagedSettingsStore](https://developer.apple.com/documentation/managedsettings/managedsettingsstore)

## R4. 시간 일정과 앱 비실행 상태

**Decision**: 선택 요일별 반복 DeviceActivitySchedule을 등록하고 DeviceActivityMonitor 확장의
구간 시작·종료 콜백을 권위 있는 시간 이벤트로 사용한다.

**Rationale**: 앱 프로세스 타이머, 로컬 알림, 일반 백그라운드 작업은 앱이 열려 있지 않을 때
정확한 제한 적용을 담당할 수 없다. Device Activity는 시스템이 확장을 호출하도록 설계됐지만,
콜백은 정확한 벽시계 시각보다 사용자가 해당 구간에 기기를 사용할 때 전달될 수 있다.

**Alternatives considered**:

- 앱 타이머: 앱 정지·종료 시 동작하지 않는다.
- 로컬 알림: 실행 트리거가 아니라 사용자 알림이다.
- 짧은 일정만 앱 타이머로 처리: FR-026과 충돌한다.

**Sources**: [DeviceActivitySchedule](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule), [DeviceActivityCenter](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter), [WWDC21 Screen Time API](https://developer.apple.com/videos/play/wwdc2021/10123/)

## R5. 위치 모니터링과 권한

**Decision**: Always 및 Full Accuracy 위치 권한 아래 원형 지오펜스 하나를 등록하고, 지오펜스
이벤트를 재평가 트리거로 사용한다. 런타임에서 모니터링 가용성과 최대 반경을 검사한다.

**Rationale**: 원형 조건 모니터링은 앱이 열려 있지 않을 때 경계 변화로 앱을 깨울 수 있는
저전력 수단이다. MVP는 시스템 한도 20개보다 훨씬 적은 한 개만 사용한다. Reduced Accuracy에서는
정확한 경계 판정과 region monitoring을 신뢰할 수 없다.

**Alternatives considered**:

- 지속 표준 위치 업데이트: 배터리 비용이 크고 종료 상태 자동성을 보장하지 않는다.
- significant-change 단독 사용: 500m/1km 경계의 주 판정 수단으로 너무 거칠다.
- When In Use 권한: 종료 상태 자동 실행 요구를 만족시키지 못한다.

**Sources**: [Monitoring geographic regions](https://developer.apple.com/documentation/CoreLocation/monitoring-the-user-s-proximity-to-geographic-regions), [Location authorization](https://developer.apple.com/documentation/CoreLocation/requesting-authorization-to-use-location-services), [Accuracy authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization)

## R6. 위치 오차와 상태 보존

**Decision**: 중심 거리 `d`, 설정 반경 `R`, horizontal accuracy `a`에 대해 `a < 0`이면 무효,
`d + a <= R`이면 확실한 내부, `max(0, d - a) > R`이면 확실한 외부, 나머지는 경계 중첩으로
판정한다. 경계 중첩·오래된 위치·오류는 위치 확인 불가이며 제한 상태를 위치 때문에 변경하지 않는다.

**Rationale**: horizontal accuracy는 위치 좌표의 오차 원 반경이다. 좌표점만 비교하면 500m
경계에서 잘못된 활성화나 해제가 발생할 수 있다. 시간대 종료는 위치 상태와 무관하게 제한을
해제한다.

**Alternatives considered**:

- `d <= R`만 비교: 명세의 오차 경계 요구를 충족하지 않는다.
- 불확실한 위치를 항상 내부 또는 외부로 간주: 잘못된 위치 기반 상태 변경을 만든다.

**Sources**: [CLLocation horizontalAccuracy](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy), [CLLocation distance](https://developer.apple.com/documentation/corelocation/cllocation/distance(from:)), [Location unknown](https://developer.apple.com/documentation/corelocation/clerror-swift.struct/locationunknown)

## R7. 시간과 위치 상태의 결합

**Decision**: 시간 콜백과 위치 이벤트가 동일한 순수 RestrictionStateMachine을 호출한다. 두
조건이 모두 참이고 권한이 유효할 때만 named store에 shield를 적용한다. 위치가 불확실하면 위치
때문에 현재 상태를 변경하지 않고, 시간 종료는 항상 shield를 제거한다.

**Rationale**: Device Activity는 위치 조건을 표현하지 않는다. App Group의 공유 스냅샷을 통해
시간 확장이 최근의 신뢰 가능한 위치 판정을 읽고, 위치 처리 측도 같은 제한 저장소를 조정하면
동일한 규칙을 앱과 확장에서 재사용할 수 있다. 동일 목표 상태에는 효과를 재실행하지 않는다.

**Alternatives considered**:

- 확장에서 새 위치를 직접 요청: 확장 실행 책임과 제약을 키운다.
- 각 타깃에 판정 로직 복제: 상태 불일치와 회귀 위험이 크다.

**Sources**: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [Named store sharing](https://developer.apple.com/videos/play/wwdc2022/110336/)

## R8. 공유 저장과 데이터 보호

**Decision**: 단일 규칙을 `schemaVersion`과 `revision`이 있는 Codable JSON 파일로 App Group
컨테이너에 원자적으로 저장한다. 기준 위치가 포함되므로 `.completeUntilFirstUserAuthentication`
파일 보호를 적용한다. 앱만 규칙을 쓰고 확장은 읽기 전용으로 사용한다.

**Rationale**: 단일 aggregate에는 SwiftData의 관계·검색·migration 계층이 과하다. 보호된 공유
파일은 앱과 확장이 함께 읽으면서 위치 정보를 기기 안에 보관할 수 있다. 공유 UserDefaults는
last-applied revision처럼 재생성 가능한 작은 운영 표식에만 사용한다.

**Alternatives considered**:

- SwiftData: 다중 규칙과 검색이 필요해질 때 재평가한다.
- 전체 규칙을 UserDefaults에 저장: 위치 정보 보호와 파일 수준 데이터 보호가 불명확하다.
- Keychain: 구조화된 규칙 스냅샷에 맞지 않는다.

**Sources**: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [Encrypting app files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files), [FileProtectionType](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication)

## R9. 제한 화면 계약

**Decision**: Shield Configuration 확장에서 제한 제목·설명·아이콘·닫기 버튼을 제공하고, Shield
Action의 기본 응답은 제한 앱 닫기로 고정한다. 제한 화면에서 GetUp 앱을 자동으로 열거나 임의의
전체 화면을 표시한다고 가정하지 않는다.

**Rationale**: Managed Settings UI가 제공하는 것은 시스템 shield의 사용자화이며, Shield Action
응답은 `.close`, `.defer`, `.none`으로 제한된다.

**Alternatives considered**:

- 별도 전면 화면 강제 표시: 공식 shield 계약이 아니다.
- 기본 shield만 사용: 제한 이유와 GetUp 상태 안내가 부족하다.

**Sources**: [Managed Settings UI](https://developer.apple.com/documentation/ManagedSettingsUI), [ShieldActionDelegate](https://developer.apple.com/documentation/managedsettings/shieldactiondelegate)

## R10. 테스트 전략

**Decision**: Swift Testing으로 시간·요일·자정·DST·거리·오차·권한·현재 상태 조합을 매개변수화
테스트하고, XCTest는 UI·성능·플랫폼 통합에 사용한다. 실제 기기에서 500m/1km 진입·이탈,
background·종료·재부팅, 첫 잠금 해제, 권한 철회, Reduced Accuracy, Background App Refresh
비활성 시나리오를 검증한다.

**Rationale**: 실제 시간과 GPS를 단위 테스트에 사용하면 비결정적이다. Simulator는 시스템
제한과 위치 전달 지연 및 재부팅을 완전히 재현하지 못하므로 실기기 인수가 필수다.

**Alternatives considered**:

- 전부 XCTest: 도메인 입력 행렬의 표현이 장황하다.
- UI 테스트만 사용: 경계 조합 누락과 비결정성이 크다.
- Simulator 전용 승인: 플랫폼 동작의 출시 근거로 부족하다.

**Sources**: [Swift Testing](https://developer.apple.com/documentation/testing), [XCTest](https://developer.apple.com/documentation/xctest), [Simulating location](https://developer.apple.com/documentation/xcode/simulating-location-in-tests)

## Resolved Blockers

### BLK-001: 사용자 지정 시간의 최소 길이

Device Activity는 15분보다 짧은 모니터링 구간을 거부한다. 현재 spec은 시작·종료 시각의 최소
간격을 정의하지 않는다. 자동 동작 요구를 유지하려면 사용자 지정 시간대를 최소 15분으로
제한하는 제품 결정이 필요하다.

**Resolution**: 사용자 지정 시간대는 최소 15분으로 제한한다. `FR-031`에 반영했다.

**Source**: [MonitoringError.intervalTooShort](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)

### BLK-002: 30초 SLA와 재부팅 기대

Core Location 경계 이벤트는 완충 거리, 체류 시간, 환경 및 시스템 재실행 throttle의 영향을
받는다. Apple Staff는 종료 앱 재실행이 약 3~5분 조절될 수 있다고 설명한다. Device Activity
콜백도 정확한 벽시계 시각보다 구간 중 기기 사용 시 전달될 수 있다. 재부팅 후 위치 모니터링은
첫 잠금 해제 전에는 불가능하다. 따라서 현재 `SC-002`, `SC-004`, `SC-008`을 앱이 통제할 수 없는
물리 경계 시각 또는 재부팅 직후부터 측정하는 절대 보장으로 구현할 수 없다.

권장 조정은 플랫폼이 신뢰 가능한 시간·위치 이벤트를 전달한 뒤 30초 이내 상태를 반영하고,
재부팅 후 첫 잠금 해제 이후 자동 복구하는 것으로 성공 기준을 정의하는 것이다.

**Resolution**: 권장 조정을 승인해 `SC-002`, `SC-004`, `SC-008`과 `FR-026`에 반영했다.

**Sources**: [Apple Staff region monitoring guidance](https://developer.apple.com/forums/thread/818908), [Region monitoring behavior](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html), [Device Activity](https://developer.apple.com/documentation/deviceactivity)
