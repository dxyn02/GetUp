# 결정 사항

## DEC-001 — 사용자 지정 일정 최소 길이

**날짜**: 2026-08-20

**결정**: 사용자 지정 제한 일정의 길이는 최소 15분이어야 한다.

**근거**: 앱이 닫힌 상태의 동작에 필요한 시스템 일정 메커니즘은 더 짧은 구간을 거부한다.
앱 전용 timer로 더 짧은 구간을 지원하면 자동 동작 요구사항을 위반한다.

## DEC-002 — 플랫폼 event SLA와 재부팅 복구 경계

**날짜**: 2026-08-20

**결정**: 30초 상태 변경 목표는 신뢰 가능한 시간 또는 위치 조건 변경이 확인된 시점부터 시작한다.
재부팅 후 자동 복구는 기기의 첫 잠금 해제 이후 시작한다.

**근거**: 운영체제가 위치 경계 및 예약된 activity callback의 전달 시점을 제어하며, 첫 잠금 해제
전에는 보호된 위치 데이터를 사용할 수 없다.

**구현 메모 (2026-08-24)**: `RestrictionCoordinator`의 time·location event는 플랫폼이 알고 있는
신뢰 가능한 확인 시각을 `confirmedAt`으로 받을 수 있고, 값이 없으면 coordinator 진입 시각을
사용한다. 실제 Managed Settings adapter write가 성공한 경우에만 `RestrictionTransitionMeasurement`로
확인 시각, effect 완료 시각과 `applyShield | removeShield`를 반환한다. 동일 상태 반복 평가,
위치 `unavailable` 보존과 restoration에는 측정 event를 만들지 않는다. 일부 활성 규칙 종료로 남은
합집합을 다시 적용하는 경우에도 사용자 관점의 부분 해제이므로 측정 effect는 `removeShield`로
분류한다.

**구현 메모 (2026-08-25)**: T083에서 `ManagedSettingsRestrictionAdapter`의 성공 경계를 named
`ManagedSettingsStore` write 호출이 아니라 write 직후 같은 store의 `shield.applications`를 다시
읽어 기대 token 집합 또는 해제 `nil`과 일치하는 시점으로 강화했다. read-back이 일치하지 않으면
`storeVerificationFailed`를 반환하고 적용 상태 snapshot을 갱신하지 않으므로 coordinator도 완료
measurement를 만들지 않는다. 자동 계측은 이 경계의 100회 활성화와 100회 해제를 측정하지만
Simulator의 test double 결과이므로 실제 선택 앱 사용 가능 상태와 물리적 event 전달은 실기기
관찰 결과와 분리한다.

## DEC-003 — iOS target 및 target 구성

**날짜**: 2026-08-20

**상태**: 2026-08-21에 `DEC-014`로 대체됨

**결정**: iOS 17 이상, Swift 6.3 및 SwiftUI를 target으로 한다. 단일 Xcode project에서 하나의
app target과 Device Activity Monitor, Shield Configuration, Shield Action extension을 사용한다.

**근거**: iOS 17은 전체 deployment 범위에서 Observation을 제공한다. 각 extension은 앱이 닫힌
상태의 일정 처리와 제한 앱 shield 동작에 필요한 시스템 실행 지점이다.

## DEC-004 — 보호된 공유 snapshot 저장소

**날짜**: 2026-08-20

**상태**: 단일 규칙 payload 범위는 2026-08-21에 `DEC-015`·`DEC-016`으로, App Group identifier는
2026-08-25에 `DEC-035`로 대체됨. 보호된 App Group JSON, atomic replacement 및 파일 보호 원칙은
유지됨.

**결정**: 단일 규칙과 최신 위치 조건을 별도의 versioned Codable JSON 파일로 App Group container에
저장한다. 공통 App Group identifier는 `group.com.getup.GetUp`으로 정의하고 앱과 세 Screen Time
확장이 동일하게 상속한다. atomic replacement와 첫 잠금 해제까지의 파일 보호를 사용한다.

**근거**: MVP는 작은 aggregate 두 개만 저장하므로 database가 필요하지 않다. 분리된 single-writer
파일은 위치 데이터를 보호하고 extension의 읽기를 허용하면서 process 간 쓰기 충돌을 줄인다.

**구현 메모 (2026-08-21)**: `SharedSnapshotRepository` actor가 `RuleRepository`와
`LocationConditionRepository`를 함께 구현하며, 규칙과 위치 snapshot은 각각 고정된 별도 파일을
사용한다. write 경계는 `SnapshotFileWriting`으로 분리해 실제 구현에서는 보호 옵션을 포함한 atomic
write를 사용하고 테스트에서는 실패를 결정적으로 주입한다. read는 최소 `schemaVersion` header를
먼저 검사한 뒤 전체 payload를 decode하며, 위치 snapshot은 현재 저장된 규칙 revision과 일치할 때만
반환한다. 이 구조는 single-writer 책임과 이전 완전한 파일 보존을 유지하면서 오류 경로를 독립적으로
검증하기 위한 것이다.

다중 규칙 전환 전까지 이 구현은 기존 단일 규칙 schema를 유지한다. 후속 계획 갱신에서 규칙
collection과 규칙별 위치 snapshot으로 migration하고 기존 단일 규칙 파일을 데이터 손실 없이
읽어 들이는 경로를 정의해야 한다.

## DEC-005 — 순수 제한 state machine

**날짜**: 2026-08-20

**결정**: app, location 및 Device Activity event를 하나의 순수 제한 state machine으로 전달한다.
플랫폼 service는 명시적 contract 뒤의 adapter로 구성한다.

**근거**: 하나의 결정론적 decision table은 target 간 규칙 불일치를 방지하고 시간, 요일, 위치
불확실성, 권한 및 idempotency 동작을 독립적으로 테스트할 수 있게 한다.

## DEC-006 — 테스트 전략

**날짜**: 2026-08-20

**결정**: domain 및 repository logic에는 Swift Testing을 사용하고, UI 및 플랫폼 integration에는
XCTest를 사용한다. 위치, 종료된 앱, 권한 및 재부팅 동작에는 실기기 인수 검증을 필수로 한다.

**근거**: Simulator만을 사용한 검증으로는 실제 shield, geofence 전달 또는 재부팅 동작을 입증할
수 없다.

## DEC-007 — 기준 위치 선택 방식

**날짜**: 2026-08-20

**결정**: 사용자는 지도에서 핀을 이동해 기준 위치를 지정할 수 있으며 현재 위치 바로가기를
사용할 수 있다. MVP에서는 장소·주소 검색을 제공하지 않는다.

**근거**: 지도 핀은 현재 위치 외의 기준점도 지정할 수 있게 하면서, 검색 기능과 관련된 추가
화면·오류·네트워크 범위를 MVP에서 제외한다.

## DEC-008 — UI 설계 선행 절차

**날짜**: 2026-08-20

**결정**: 모든 UI 구현 task는 관련 로우파이 설계와 검토, 하이파이 설계와 검토가 완료된 후에만
시작한다.

**근거**: 정보 구조와 사용자 흐름을 코드 작성 전에 검증하고, 확정된 화면 상태·접근성·시각
규격을 구현 기준으로 사용해 UI 재작업을 줄인다.

## DEC-009 — Privacy manifest 기본 정책

**날짜**: 2026-08-21

**결정**: 앱과 세 extension의 `PrivacyInfo.xcprivacy`에 tracking 및 off-device 데이터 수집이
없음을 선언한다. App Group 구성원 사이에서 재생성 가능한 운영 표식만 공유하는 `UserDefaults`의
required-reason API 사유는 `1C8F.1`로 선언한다. 이후 데이터 수집이나 required-reason API 사용이
추가되면 해당 기능과 같은 변경 단위에서 각 실행 bundle의 manifest를 갱신한다.

**근거**: GetUp은 기준 좌표와 앱 선택 token을 기기 밖으로 전송하지 않으며, 공유
`UserDefaults` 접근은 동일 App Group의 앱과 extension 사이로 제한된다. Apple은 required-reason
API를 사용하는 각 실행 bundle에 정확한 사유가 포함된 privacy manifest를 요구한다.

## DEC-010 — FamilyActivitySelection의 동시성 경계

**날짜**: 2026-08-21

**결정**: `RestrictionRuleSnapshot`은 `FamilyActivitySelection`을 불투명 값으로 직접 보존하고
`@unchecked Sendable`을 선언한다. 앱 선택 token을 해석하거나 snapshot 외부에서 내부 collection을
공유하지 않으며, snapshot은 생성 후 변경하지 않는 값으로 사용한다.

**근거**: 현재 iOS SDK의 `FamilyActivitySelection`은 `Codable`·`Equatable` 값 타입이지만
`Sendable` conformance를 제공하지 않는다. 선택 결과의 공식 Codable 표현을 유지하면서 앱과
extension의 비동기 경계를 통과하려면 해당 immutable aggregate에만 명시적인 동시성 책임을
부여해야 한다. 향후 SDK가 `Sendable`을 제공하면 `@unchecked` 선언을 제거하고 compiler 검사를
사용한다.

## DEC-011 — 플랫폼 adapter의 비동기 계약 경계

**날짜**: 2026-08-21

**상태**: 적용 상태의 단일 rule revision 범위는 2026-08-24에 `DEC-027`로 대체됨. 비동기 protocol
경계와 하나의 일관된 snapshot으로 조회한다는 원칙은 유지한다.

**결정**: 시간, 공유 저장소, 권한, 일정, 위치 monitoring 및 제한 적용 기능을 `Sendable` protocol로
분리한다. process·actor 경계를 통과할 수 있는 작업은 명시적인 `async` API로 제공하고, 저장·등록·
시스템 제한 변경처럼 실패 가능한 작업은 `throws`로 노출한다. 제한 적용 상태는 적용 여부와 rule
revision을 하나의 `AppliedRestrictionState`로 조회한다.

**근거**: 앱과 extension이 동일한 core 판정 로직을 사용하면서 실제 Apple framework와 파일 I/O를
fake로 교체하려면 안정적인 의존성 경계가 필요하다. 적용 여부와 revision을 따로 읽으면 두 조회
사이에 시스템 상태가 바뀔 수 있으므로 하나의 snapshot으로 제공해야 idempotency 판정의 일관성을
유지할 수 있다.

## DEC-012 — 실행 target 공통 의존성 조립

**날짜**: 2026-08-21

**결정**: `DependencyContainer`를 앱과 세 extension target이 같은 source로 compile한다. live 조립은
각 target의 `Info.plist`에 있는 `GetUpAppGroupIdentifier`를 읽어 App Group container URL을 구하고,
process마다 하나의 `SharedSnapshotRepository` actor를 생성해 `RuleRepository`와
`LocationConditionRepository` 계약으로 함께 노출한다. 아직 구현되지 않은 플랫폼 adapter는 해당
구현 task에서 container에 추가한다.

**근거**: target별로 App Group 경로와 repository 조립을 복제하면 설정 차이와 파일 계약 불일치가
발생할 수 있다. 전역 singleton은 테스트용 container와 실패 writer 주입을 어렵게 하므로 사용하지
않는다. 공통 조립 source와 명시적 initializer를 사용하면 실행 target은 같은 영속성 경계를 유지하고
테스트는 실제 App Group entitlement 없이 임시 container를 사용할 수 있다.

## DEC-013 — 개인정보 안전 진단 event

**날짜**: 2026-08-21

**결정**: 진단 로그는 닫힌 집합인 `DiagnosticOperation`과 `DiagnosticErrorCode`만 기록한다. 저장소
오류의 file name·schema 값·revision 값과 알 수 없는 `Error`의 설명은 분류 과정에서 폐기하며, 좌표,
거리, 정확도, `FamilyActivitySelection`, 앱 token 또는 임의 metadata 문자열을 진단 event API가
받지 않도록 한다. `DiagnosticsLogger`는 안전한 고정 code만 OSLog에 public 값으로 기록하고
`DependencyContainer`를 통해 주입한다.

**근거**: `Error.localizedDescription`이나 자유 형식 dictionary를 직접 기록하면 파일 경로, 좌표,
앱 선택 payload가 의도치 않게 로그에 포함될 수 있다. 모든 값을 private OSLog로 숨기는 방식도
민감 데이터 수집 자체를 막지 못하므로 선택하지 않는다. 필요한 운영 진단은 안정적인 operation과
오류 분류만으로 수행하고 상세 개인정보는 처음부터 event에 포함하지 않는다.

**구현 메모 (2026-08-25)**: T081에서 `DiagnosticsLogger`의 출력 경계를
`DiagnosticEventWriting`으로 분리하되 writer가 임의 문자열이나 metadata를 받지 않고 닫힌
`DiagnosticEvent`만 받도록 제한했다. production writer는 event의 고정 `logMessage`만 `OSLog`에
기록하고, 테스트 writer는 좌표·정확도·장소명·opaque app token을 포함한 오류 입력이 최종 메시지에
도달하지 않는지 검증한다. production source에는 이 경로 외 logger·analytics·telemetry가 없다.

## DEC-014 — 최소 지원 운영체제를 iOS 26으로 상향

**날짜**: 2026-08-21

**결정**: 앱과 `GetUpDeviceActivityMonitor`, `GetUpShieldConfiguration`, `GetUpShieldAction`, 테스트
target의 deployment target을 iOS 26 이상으로 통일한다. 이 결정은 `DEC-003`의 iOS 17 이상 지원
범위를 대체하며 Swift 6.3, SwiftUI 및 기존 target 구성은 유지한다.

**근거**: 초기 제품 검증 대상을 최신 운영체제로 한정해 iOS 26 SwiftUI API와 Apple의 공식
`iOS and iPadOS 26` design resource를 호환성 분기 없이 사용할 수 있게 한다. iOS 17 이상 지원은
설치 가능 기기 범위가 넓지만, 최신 UI와 API를 도입할 때 별도 fallback과 추가 테스트 행렬이
필요하므로 현재 MVP에서는 제외한다.

**영향 범위**: `Configuration/Base.xcconfig`, 기능 spec·plan·research·quickstart·tasks의 플랫폼
기준, 이후 로우파이·하이파이 설계와 실기기 검증 환경에 적용된다. 기존 iOS 17 기준 테스트 기록은
당시 실행 증거로 보존하며, 현재 완료 판단에는 iOS 26 기준 검증을 사용한다.

## DEC-015 — MVP부터 여러 독립 제한 규칙 지원

**날짜**: 2026-08-21

**결정**: MVP부터 여러 독립 제한 규칙을 저장하고 추가·확인·수정한다. 홈 화면은 오늘 예정된
규칙을 우선 표시하고, 오늘 일정이 없으면 다음날 예정된 규칙을 보여 주며 새 규칙 추가와 표시된
규칙 편집 진입점을 제공한다. 이 결정은 기존 단일 규칙 범위를 대체한다.

**근거**: 사용자는 취침과 외출처럼 서로 다른 시간·위치·제한 앱 조합을 함께 운용해야 하며,
오늘 또는 다음 예정 규칙을 확인하는 홈 경험은 여러 규칙이 보존될 때 제품 의도와 일치한다.

**영향 범위**: `RestrictionRuleSnapshot`의 식별자, 규칙 collection 저장과 migration, 일정·region
등록, 상태 평가, 홈 화면, 기존 단일 규칙 테스트와 `plan.md`·`data-model.md`·`tasks.md`를 후속
계획 갱신에서 변경해야 한다. 규칙 중첩 동작은 `DEC-016`의 합집합 규칙을 따른다.

## DEC-016 — 동시에 활성화된 규칙의 제한 앱 합집합 적용

**날짜**: 2026-08-21

**결정**: 시간과 위치 조건을 모두 충족한 모든 규칙의 제한 앱을 합집합으로 적용한다. 일부 규칙이
종료되면 남은 활성 규칙의 합집합을 다시 계산해 더 이상 어떤 활성 규칙도 요구하지 않는 앱만
해제한다.

**근거**: 여러 독립 규칙의 의도를 우선순위 없이 모두 보존하며, 규칙 하나가 끝났다는 이유로 다른
활성 규칙이 제한 중인 앱을 잘못 해제하지 않는다. 시간 중첩을 금지하거나 임의 우선순위를 두는
방식보다 사용자 예측 가능성이 높다.

**영향 범위**: 제한 상태 계산은 단일 Boolean·revision 대신 활성 rule ID 집합과 앱 token 합집합을
추적해야 한다. 규칙별 조건 평가, 부분 종료, 중복 앱 및 idempotency 테스트를 후속 계획에 추가한다.

## DEC-027 — 다중 규칙 위치·제한 적용 상태 계약

**날짜**: 2026-08-24

**결정**: `location-conditions.json` schema 2는 rule ID별 `LocationConditionSnapshot` collection을
저장한다. 제한 적용 상태는 단일 Boolean·revision 대신 활성 `(ruleID, revision)` 집합을 App Group
`UserDefaults`에 저장한다. `RestrictionCoordinator`는 저장된 모든 유효 규칙을 같은 event 시점에
독립 평가하고, `active` 규칙과 기존 상태를 보존해야 하는 `unavailable` 규칙을 합성한 뒤 해당
규칙들의 application token 합집합을 named Managed Settings store에 한 번 적용한다.

rule ID가 없는 schema 1 위치 snapshot은 특정 규칙에 귀속시킬 수 없으므로 값 추정을 금지하고 빈
schema 2 collection으로 migration한다. 각 규칙은 새 위치 근거가 기록될 때까지 `unavailable`이다.
기존 UserDefaults가 적용 Boolean·revision만 보존한 경우에는 활성 규칙을 추정하지 않고 최초
coordinator 평가에서 GetUp named store를 한 번 초기화한다.
일부 규칙이 종료되거나 외부로 판정되면 남은 활성 규칙 집합으로 합집합을 다시 계산하며, 활성
rule revision 집합이 같으면 Managed Settings와 상태 저장소 write를 생략한다.

**근거**: `FR-038`·`FR-044`와 `DEC-016`의 합집합 및 부분 종료 동작을 앱과 extension의 재실행
경계에서도 결정적으로 복구하려면 규칙별 위치 근거와 활성 규칙 집합이 모두 필요하다. 기존 단일
revision을 collection revision으로 간주하거나 마지막 event 규칙에 귀속시키면 서로 다른 규칙이
같은 revision을 가질 수 있어 잘못된 제한 적용이 발생한다.

**영향 범위**: `RuntimeStateModels.swift`, `PlatformContracts.swift`,
`SharedSnapshotRepository.swift`, `LocationMonitor.swift`,
`ManagedSettingsRestrictionAdapter.swift`, `RestrictionCoordinator.swift`, 공유 저장·평가 계약과 관련
테스트 fixture를 함께 변경한다. T051의 extension 복구는 이 schema 2 collection을 읽어야 한다.

## DEC-028 — 앱·Device Activity extension의 공통 best-effort 복구 경로

**날짜**: 2026-08-24

**결정**: 앱 foreground 활성화와 Device Activity extension의 `intervalDidStart`는 동일한
`AppLifecycleCoordinator`를 사용한다. coordinator는 보호된 규칙 collection을 먼저 읽고, 읽기에
성공한 경우에만 GetUp 소유 일정과 region을 초기화한다. 이후 활성 규칙을 안정적인 ID 순서로
재등록하고 신뢰 가능한 위치 fix를 갱신한 뒤 `RestrictionCoordinator.restore()`로 현재 제한 합집합을
일치시킨다.

첫 잠금 해제 전 파일 보호 등으로 규칙을 읽지 못하면 기존 일정·region·shield를 그대로 보존하고
다음 event에서 다시 시도한다. 개별 일정 또는 region 등록 실패는 다른 규칙의 복구와 제한 상태
재평가를 막지 않으며 `AppLifecycleRecoveryResult`에 component와 rule ID만 기록한다. 실제 오류 설명,
좌표와 app token은 결과에 포함하지 않는다.

**근거**: 앱과 extension이 서로 다른 복구 순서나 저장 해석을 사용하면 재부팅·종료 상태에서 제한
결과가 달라질 수 있다. 반면 보호 파일을 읽기 전에 기존 시스템 등록을 제거하면 첫 잠금 해제 전
정상 설정까지 잃을 수 있다. 공통 순서와 best-effort 결과는 복구 가능한 규칙을 계속 처리하면서
개인정보 없는 진단 경계를 제공한다.

**영향 범위**: `AppLifecycleCoordinator.swift`, `DeviceActivityMonitorExtension.swift`, 앱
`scenePhase` wiring, `AuthorizationAdapter.swift`, `LocationMonitor.swift`의 extension target membership,
`platform-events-contract.md`와 복구 통합 테스트에 적용한다. 실제 background·종료·재부팅 event
전달은 Simulator로 입증하지 않고 T085 실기기 인수에서 검증한다.

**구현 메모 (2026-08-24)**: `intervalDidEnd`는 callback 진입 즉시 확인 시각을 기록하고 공통
`DependencyContainer.makeRestrictionCoordinator()`로 `handleTimeEvent(confirmedAt:)`를 호출한다.
GetUp named store를 무조건 비우거나 위치를 새로 추정하지 않고 저장된 모든 규칙을 현재 시간으로
재평가하므로, 종료 규칙은 위치 `unavailable`이어도 해제하면서 다른 활성 규칙의 합집합은 보존한다.
보호 파일 read 또는 live 조립 실패 시에는 다른 규칙을 잘못 해제하지 않고 기존 shield를 보존해
다음 시스템 event에서 재시도한다.

## DEC-017 — 직접 시간 입력과 DatePicker 유효 범위 제한

**날짜**: 2026-08-23

**결정**: 아침·밤 시간 프리셋을 제거하고 시작·종료 시각을 직접 설정한다. 시작 시각과 같거나
전체 구간이 15분 미만이 되는 종료 시각은 DatePicker에서 선택할 수 없게 한다.

**근거**: 사용자의 실제 생활 시간에 맞춘 설정을 우선하고 저장 시점의 사후 오류보다 입력
시점에 유효하지 않은 조합을 예방한다.

## DEC-018 — 여섯 단계 반경 slider

**날짜**: 2026-08-23

**결정**: 반경은 `500m`, `1km`, `2km`, `3km`, `4km`, `5km`의 닫힌 집합이며 slider는 이 값에만
snap한다.

**근거**: 사용자가 생활 반경에 맞춰 더 넓은 범위를 고르면서도 임의 반경으로 인한 검증·표시
불일치를 방지한다. Core Location 등록 전 기기의 최대 허용 반경은 계속 확인한다.

## DEC-019 — 재사용 가능한 저장 장소와 규칙 이름 분리

**날짜**: 2026-08-23

**결정**: 장소 이름과 지도 핀 좌표를 저장 장소 aggregate로 보존해 여러 규칙에서 재사용한다.
선택적인 규칙 이름은 장소 이름과 별도의 값으로 저장한다. 장소 이름은 주소 검색이나 reverse
geocoding 결과가 아니라 사용자가 직접 지정한 표시 이름이다.

**근거**: 집·회사처럼 반복 사용하는 좌표를 규칙마다 다시 선택하는 비용을 줄이고 홈의
`집 1km`, `회사 500m` 표시를 안정적인 저장 값으로 제공한다.

## DEC-020 — 1분 단위 12시간 wheel time picker

**날짜**: 2026-08-23

**결정**: 시작·종료 시각은 시·분·AM/PM 세 열의 세로 wheel로 직접 선택한다. 분은 1분 단위로
선택할 수 있으며, 규칙 편집·홈·요약·오류의 사용자 시간 표기는 `06:00 AM` 형식으로 통일한다.
AM/PM은 시간 숫자보다 작은 시각적 계층으로 표시한다. 전체 구간의 최소 15분 규칙은 유지한다.

**근거**: 사용자가 첨부한 조작 방식은 시·분·오전·오후를 한 화면에서 직접 조정할 수 있고, 5분이나
15분 preset으로 제한하지 않아 실제 생활 시간에 맞춘 입력을 제공한다. 표기 형식을 통일하면 이전
24시간제와 AM/PM 혼용 문제도 제거할 수 있다.

## DEC-021 — 모든 저장 규칙 표시와 독립 적용

**날짜**: 2026-08-23

**결정**: 홈은 오늘 또는 다음 규칙 하나만 선택해 표시하지 않고 저장된 모든 유효 규칙을 card
pager에 제공한다. 오늘 적용되는 규칙을 먼저 배치하고 나머지는 각 규칙의 다음 적용 시점 순으로
정렬한다. 현재 화면에 보이는 card와 무관하게 모든 규칙은 자기 요일·시간·위치 조건에 따라 독립적으로
적용되며, 여러 규칙이 동시에 조건을 충족하면 `DEC-016`의 제한 앱 합집합을 사용한다. 이 결정은
`DEC-015`의 홈 대표 규칙 표시 범위를 대체하고 다중 규칙 저장 원칙은 유지한다.

**근거**: swipe 가능한 여러 card 중 현재 보이는 card만 적용되는 것으로 오해하지 않게 하고,
사용자가 만든 모든 규칙의 의도를 보존한다. 홈 card의 위치는 탐색 상태일 뿐 실행 우선순위가 아니다.

## DEC-022 — DST 전환일의 현지 시각 경계 보정

**날짜**: 2026-08-23

**결정**: DST 전환으로 규칙의 시작 또는 종료 현지 시각이 존재하지 않으면 해당 경계를 다음 유효
현지 시각으로 이동한다. 같은 현지 시각이 두 번 발생하면 시작 경계는 첫 번째 발생, 종료 경계는
두 번째 발생을 사용한다. 시작 경계는 포함하고 종료 경계는 포함하지 않는다.

**근거**: 선택한 요일의 규칙이 DST 전환만으로 하루 전체 누락되는 것을 막고, 반복되는 시각에서
사용자가 의도한 현지 시각 구간을 조기에 종료하지 않는다. `ScheduleEvaluator`는 주입된 `Calendar`와
`TimeZone`만 사용해 이 경계를 결정론적으로 계산한다.

## DEC-023 — 다중 규칙·저장 장소 collection 저장과 revision 정책

**날짜**: 2026-08-24

**결정**: 다중 규칙은 schema 2의 `restriction-rules.json`, 저장 장소는 schema 1의
`saved-places.json`에 각각 collection snapshot으로 저장한다. 규칙 저장 시 대상 규칙 revision과 규칙
collection revision을 각각 1 증가시키고, 저장 장소 collection revision도 1 증가시킨다. 편집 draft의
`sourceRevision`이 현재 대상 규칙 revision과 다르면 stale write로 거부한다. 두 파일을 함께 저장할
때는 저장 장소를 먼저 atomic write한 뒤 규칙을 기록해 새 규칙이 존재하지 않는 장소를 참조하는
상태를 만들지 않는다. 두 번째 write가 실패하면 사용되지 않는 장소가 남을 수 있으나 기존 규칙
snapshot은 온전하게 유지한다.

기존 schema 1의 `restriction-rule.json`만 존재하면 고정된 migration용 규칙 ID와 장소 ID를 부여하고,
기존 좌표를 이름 `기존 장소`인 저장 장소로 변환해 읽는다. 새 collection 파일이 저장되기 전까지
legacy 파일을 fallback으로 사용하며, 데이터 복구 가능성을 위해 legacy 파일을 즉시 삭제하지 않는다.

**근거**: 규칙별 revision은 서로 다른 규칙의 독립 편집을 보존하고 collection revision은 확장이 읽은
전체 구성과 위치 판정의 일관성을 확인하게 한다. stale write 차단은 오래 열린 편집 화면이 더 최신인
변경을 덮어쓰는 것을 막는다. 파일 간 transaction을 제공하지 않는 App Group 파일 저장에서 장소 우선
순서는 dangling reference보다 복구 가능한 미사용 장소를 선택하며, 결정론적인 legacy ID는 migration을
여러 번 읽어도 동일한 aggregate를 생성한다.

## DEC-024 — 앱 화면 상태와 홈 규칙 정렬 책임

**날짜**: 2026-08-24

**결정**: `@MainActor @Observable AppModel`이 규칙·저장 장소 collection 로딩, 홈 표시 모델 정렬,
선택 card, 규칙 생성·편집 진입 및 저장 후 홈 갱신을 소유한다. 홈은 참조 장소와 유효 일정, 하나
이상의 유효 앱 선택을 가진 모든 저장 규칙을 표시한다. 현재 날짜의 선택 요일에 속하거나 자정 초과
구간이 현재 활성인 규칙을 오늘 그룹에 두고 실제 당일 시작 시점 순으로 정렬한다. 나머지는 DST
보정된 다음 시작 시점 순으로 정렬하며, 같은 시점은 생성 시각과 규칙 ID로 결정론적으로 정렬한다.
pager에서 선택한 card는 탐색 상태일 뿐 규칙 적용 여부를 변경하지 않는다.

UI test 실행 시에만 `--ui-testing` launch argument로 App Group과 분리된 cache 저장소, 고정 시각,
불투명 앱 선택 개수 seam을 사용한다. 일반 실행은 `DependencyContainer.live()`의 App Group 저장소와
실제 `FamilyActivitySelection.applicationTokens`만 사용한다.

**근거**: 화면별로 저장소 로딩과 정렬을 반복하면 재실행·저장·편집 후 서로 다른 card 순서와
선택 상태가 생길 수 있다. main actor의 단일 화면 모델은 Observation 갱신과 repository actor 경계를
명확히 하며, 고정 시각의 순수 정렬 입력은 오늘·다음 규칙과 자정 초과 경계를 결정론적으로 테스트할
수 있게 한다. UI test seam은 시스템 Family Controls picker와 실제 App Group 상태에 의존하지 않고
opaque token 경계를 유지한다.

## DEC-025 — 규칙 삭제와 저장 장소 보존 경계

**날짜**: 2026-08-24

**결정**: 저장된 규칙은 편집 화면의 파괴적 동작과 확인 alert를 거쳐 삭제한다. 삭제 시 대상 규칙만
규칙 collection에서 제거하고 collection revision을 1 증가시키며, 다른 규칙과 재사용 가능한 저장
장소 collection은 변경하지 않는다. 편집을 시작한 규칙 revision이 달라졌다면 stale delete로
거부한다. `AppModel`은 삭제 전에 주입 가능한 비동기 guard를 호출하며, T066에서 실제 활성 제한
판정을 이 경계에 연결해 활성 규칙의 삭제를 거부하고 종료 조건을 안내한다.

**근거**: 저장 장소는 여러 규칙이 공유할 수 있는 독립 aggregate이므로 규칙 삭제와 함께 제거하면
다른 규칙의 참조를 깨뜨리거나 사용자가 다시 쓸 장소 데이터를 잃을 수 있다. revision 검증은 오래
열린 편집 화면이 최신 변경을 삭제하는 것을 막고, 삭제 guard를 단일 경로에 두면 제한 활성화 구현
이후에도 화면별 우회 없이 FR-023을 적용할 수 있다.

## DEC-026 — MVP shield의 단일 닫기 행동

**날짜**: 2026-08-24

**결정**: MVP의 restricted-app shield는 iOS 버전과 관계없이 secondary action을 제공하지 않는다.
저장 장소 이름·설정 반경·종료 시각을 제목과 설명으로 직접 안내하고, primary `앱 닫기` 행동만
제공한다. shield 내부 지도와 GetUp 앱 열기 행동은 구현하지 않는다.

향후 secondary action에 `오늘만 허용`을 제공하고 인앱결제 뒤 일시적으로 제한을 해제하는 아이디어는
현재 범위와 승인에 포함하지 않는다. 해당 기능은 해제 기간, 결제 실패·복원·환불, 활성 규칙 간
우선순위, 보호 기능의 유료 해제 적합성과 App Store 정책을 별도 spec에서 검토한 뒤 결정한다.

**근거**: 장소·반경·종료 시각 문구만으로 현재 해제 조건을 이해할 수 있으며, 모든 지원 버전에서
동일한 단일 행동 계약을 유지한다. 미래 수익화 아이디어를 현재 제한 우회 동작과 결합하지 않아
MVP의 자동 해제 규칙과 검증 범위를 안정적으로 유지한다.

## DEC-029 — 동일 앱의 다중 활성 규칙 shield 요약

**날짜**: 2026-08-24

**결정**: shield 대상 앱 token과 일치하는 활성 규칙이 하나이면 승인된 장소 이름·반경·종료 시각을
모두 표시한다. 두 개 이상이면 제목에 활성 규칙 수를 표시하고, 설명에는 각 규칙의 위치 또는 시간이
모두 끝나야 다시 사용할 수 있다는 결합 의미만 짧게 안내한다. 개별 조건 목록은 나열하지 않는다.
App Group snapshot, 적용 상태 또는 app token을 읽지 못하면 제한 활성 사실과 설정한 위치 또는 시간
종료 뒤 자동 해제된다는 일반 문구를 사용한다.

**근거**: 한 규칙만 대표로 표시하면 실제 해제 조건을 잘못 안내하고, 모든 규칙을 나열하면 규칙
개수에 따라 ManagedSettingsUI의 system-owned layout과 Dynamic Type에서 핵심 문구가 잘릴 수 있다.
짧은 다중 규칙 요약은 정확한 결합 의미를 보존하면서 개인정보와 overflow 위험을 줄인다.

**영향 범위**: `shield-ui-contract.md`, US2 하이파이, `ShieldContentProvider`,
`ShieldConfigurationExtension`과 단일·다중·fallback 콘텐츠 테스트에 적용한다.

## DEC-030 — 규칙 저장 후 공통 runtime 복구 경로 재사용

**날짜**: 2026-08-24

**결정**: `RuleConfigurationService`는 저장 장소와 규칙 collection snapshot을 모두 기록한 뒤에만
새 `RestrictionRuleSnapshot`을 runtime 동기화 경계로 전달한다. 앱의 live 환경은 이 경계를
`AppLifecycleCoordinator.restore()`에 연결해 GetUp 소유 일정·region을 초기화하고 저장된 모든 활성
규칙을 새 revision으로 재등록하며, fresh 위치 근거를 갱신한 뒤 제한 합집합을 즉시 재평가한다.
snapshot 기록이 실패하면 runtime 동기화를 호출하지 않는다. 개별 일정·region 등록 실패는
`DEC-028`의 best-effort 결과를 따르며 다른 규칙과 최종 제한 재평가를 막지 않는다.

**근거**: 저장 직후 경로가 foreground·재부팅 복구와 다른 순서나 별도 adapter 조립을 사용하면 같은
snapshot으로도 시스템 등록과 제한 상태가 달라질 수 있다. 공통 coordinator를 재사용하면 여러 규칙,
권한, 위치 불가와 부분 등록 실패의 기존 검증을 그대로 유지하면서 `FR-022`의 즉시 재평가를
충족한다. 두 snapshot보다 먼저 runtime을 변경하지 않아 불완전한 저장 상태가 시스템 등록에
반영되는 것도 방지한다.

**영향 범위**: `RuleConfigurationService`, `AppModel`, live `AppEnvironment`,
`platform-events-contract.md`와 저장 후 동기화 테스트에 적용한다.

## DEC-031 — 자동 해제 뒤 별도 완료 UI 미제공

**날짜**: 2026-08-24

**결정**: 시간 종료 또는 신뢰 가능한 위치 이탈로 제한이 자동 해제되면 별도의 완료 화면, 배너,
toast 또는 완료 전용 VoiceOver announcement를 표시하지 않는다. 현재 활성 규칙 집합과 앱 token
합집합을 재계산한 뒤 활성 표시와 편집·끄기·삭제 guard가 제거된 기존 예정·비활성 홈 상태를 그대로
사용한다.

**근거**: 제한이 해제된 뒤 사용자가 수행해야 할 별도 후속 행동이 없으며, 전용 완료 상태는 홈의
기존 규칙 상태와 중복된다. 제한 대상 앱이 다시 열리고 GetUp 홈의 활성 표시가 사라지는 결과만으로
자동 해제를 확인할 수 있어 일시 상태와 추가 접근성 focus·announcement를 도입할 필요가 없다.

**영향 범위**: `design/low-fidelity/US3-auto-release.md`, T056·T057 설계 기준과 이후 T058·T066·T067
UI 구현에 적용한다. 자동 해제 effect, 30초 측정과 다중 규칙 합집합 재계산 동작은 변경하지 않는다.

## DEC-032 — 활성 revision 기반 단일 규칙 변경 guard

**날짜**: 2026-08-24

**결정**: 현재 적용 상태의 `(ruleID, revision)`이 저장된 규칙과 정확히 일치할 때 장소 이름·반경·종료
시각을 담은 `RestrictionModificationGuard`를 편집 모델에 주입한다. guard가 존재하면 규칙 끄기와
저장을 모델에서 거부하고, 앱 저장·삭제 경계에서도 다시 거부한다. 활성 홈의 변경 control과 이미
열린 편집기의 끄기·삭제 시도는 같은 종료 조건 문구를 사용하는 네이티브 SwiftUI Alert로 안내한다.
조건이 종료된 비활성 규칙은 기존 편집 화면의 `ruleEditor.enabled` toggle과 삭제 흐름을 그대로
사용한다. foreground 복구 또는 명시적인 상태 갱신에서 적용 상태를 다시 읽으면 홈 상태와 열린
편집기의 guard를 같은 snapshot으로 재계산해, 해제된 revision은 기존 편집기와 새 재진입 모두에서
즉시 변경 가능 상태로 전환한다.

**근거**: 화면 진입만 막으면 이미 열린 편집기나 직접 호출 경로에서 활성 규칙을 변경할 수 있으므로
화면·모델·저장 경계가 같은 활성 revision 판정을 공유해야 한다. 장소·반경·종료 시각을 값 객체로
보존하면 편집·끄기·삭제가 서로 다른 안내를 만들지 않고 승인된 종료 조건을 일관되게 표시할 수 있다.
SwiftUI Alert의 system-owned action에는 별도 accessibility identifier를 붙이지 않아 iOS 26의 중첩
접근성 요소를 피하고 제목과 button label을 단일 focus 대상으로 유지한다.

**영향 범위**: `RuleEditorModel`, `RestrictionStatusView`, `RuleEditorView`, `AppModel`,
`Localizable.xcstrings`, T063 UI test와 T066·T067 단위 테스트에 적용한다.

## DEC-033 — 위치 근거의 24시간 최신성 경계

**날짜**: 2026-08-24

**결정**: `RestrictionCoordinator`는 현재 시각 기준 24시간 이상 지난 `LocationConditionSnapshot`을
평가 직전에 `unavailable`로 정규화한다. 원래 `observedAt`과 source는 보존하되 거리와 정확도 값은
판정 근거에서 제거한다. 유효 시간대 안에서는 같은 `(ruleID, revision)`의 기존 shield만 보존하고
새 shield를 적용하지 않는다. 시간대가 종료된 규칙은 위치 최신성과 관계없이 먼저 비활성으로
판정해 shield를 해제한다.

**근거**: 오래된 위치를 내부 또는 외부의 권위 있는 근거로 재사용하면 잘못된 신규 제한이나 위치
기반 해제가 발생할 수 있다. T073이 명시한 24시간 전 fix를 닫힌 최신성 경계로 사용하고, 위치 불가
상태 보존보다 시간 종료를 우선하는 `FR-015`, `FR-019`, `FR-020`의 순서를 유지한다.

**영향 범위**: `RestrictionCoordinator`, `LocationUnavailableTests`, `RestrictionReleaseTests`와
`restriction-evaluation-contract.md`의 위치 불가·시간 종료 우선순위에 적용한다.

## DEC-034 — foreground 복구 결과와 권한 안내 갱신 경계

**날짜**: 2026-08-24

**결정**: 앱 최초 활성화, foreground 복귀와 사용자의 위치 재확인은 모두
`AppLifecycleCoordinator.restore()`를 호출한다. main app은 `SystemAuthorizationProvider.forApplication()`을
주입해 Family Controls, 위치 승인·정확도와 Background App Refresh의 최신 상태를 읽고 같은 provider를
제한 재평가에도 사용한다. 복구 결과는 권한 snapshot과 통합 화면 상태를 함께 반환하며 화면 상태는
필수 권한 부족, 위치 확인 불가, 제한 활성, 구성 필요 또는 비활성 순서로 합성한다.

`GetUpRootView`는 이 결과로 기존 `PermissionGuideModel`을 갱신하거나 새 안내를 표시한다. 권한과 위치
문제가 모두 해결되면 안내를 닫고, 제한 재평가 자체가 실패하면 활성 여부를 추정하지 않고 기존
안내 상태를 보존한다. app extension은 Background App Refresh app API를 사용하지 않는 기본
`SystemAuthorizationProvider`를 계속 사용한다.

**근거**: Settings 이동 뒤 foreground, 최초 실행과 수동 위치 재확인이 서로 다른 권한·일정·위치
복구 순서를 사용하면 동일한 시스템 상태에서 안내와 shield가 어긋날 수 있다. 공통 결과를 화면까지
전달하면 최신 권한을 기준으로 안내를 열고 닫으면서도 복구 실패 시 잘못된 활성·비활성 추정을 막는다.

**영향 범위**: `AppLifecycleCoordinator`, `GetUpRootView`, `SystemAuthorizationProvider`,
`RestrictionCoordinator` 조립과 `AppLifecycleCoordinatorTests`, US4 UI test에 적용한다.

## DEC-035 — 배포 식별자 namespace 확정

**날짜**: 2026-08-25

**결정**: Apple Developer에서 기존 `com.getup.GetUp`이 사용 불가능함을 확인해 GetUp의 배포
namespace를 `com.dxyn02.GetUp`으로 확정한다. 메인 앱과 세 Screen Time extension의 Bundle ID는
각각 `com.dxyn02.GetUp`, `.DeviceActivityMonitor`, `.ShieldConfiguration`, `.ShieldAction` suffix를
사용하며 공통 App Group은 `group.com.dxyn02.GetUp`을 사용한다.

**근거**: 네 실행 target과 공유 container는 Apple Developer에 등록 가능한 하나의 고유 namespace를
사용해야 한다. 사용자가 네 명시적 App ID 등록과 공통 App Group의 네 App ID 할당을 완료했으며,
같은 prefix를 사용하면 Xcode build setting, entitlement와 계정 구성을 일관되게 검증할 수 있다.

**영향 범위**: `Configuration/Base.xcconfig`, 네 entitlement, `DiagnosticsLogger` fallback subsystem,
Apple Developer App ID·App Group·provisioning profile 및 배포 준비 문서에 적용한다. 기존 개발 중
`group.com.getup.GetUp` container의 로컬 데이터는 새 App Group으로 자동 이전되지 않으며, 배포 전
개발 데이터이므로 새 namespace에서 다시 생성한다.

## DEC-036 — Family Controls 승인과 전체 화면 실행 경계

**날짜**: 2026-08-25

**결정**: Family Controls 미승인 화면의 주요 행동은 `UIApplication.openSettingsURLString`을 열지
않고 `AuthorizationCenter.requestAuthorization(for: .individual)`을 호출한다. 위치 접근과
Background App Refresh만 앱별 Settings 이동을 유지한다. 메인 앱 `Info.plist`에는 빈
`UILaunchScreen` dictionary를 선언해 현대 iPhone의 native 화면 크기로 실행한다.

**근거**: 실기기에서 앱별 Settings에 Family Controls 승인 항목이 없고, Apple 공식 API가 최초
개인용 승인 시 시스템 alert와 생체 인증 sheet를 표시하는 것을 확인했다. 또한 launch screen 선언이
없으면 최신 iPhone에서 앱이 구형 호환 canvas로 실행되어 위아래 letterboxing이 발생한다.

**영향 범위**: `GetUpApp`, `PermissionGuideModel`, `PermissionGuideView`, `Info.plist`, US4 모델·UI
테스트와 US4 로우·하이파이 구현 인계에 적용한다.
