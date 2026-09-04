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

**상태**: `intervalDidStart` 경로는 DEC-065로 대체됨. 앱 foreground 복구 경로는 유지함.

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

**상태**: DEC-064의 네 단계 반경 결정으로 대체됨

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

## DEC-037 — 권한 결정 상태별 순차 안내

**날짜**: 2026-08-25

**결정**: 권한 개요의 `다음`부터 Family Controls, 위치, Background App Refresh를 순서대로 확인한다.
Family Controls와 위치가 `notDetermined`이면 상세 화면 진입 시 시스템 권한 요청을 자동 표시하고 결과가
정해질 때까지 `다음`을 비활성화한다. 허용 상태는 활성화된 `다음`, 거부 또는 요구 수준 미충족 상태는
`설정 열기`를 제공하며 위치와 Background App Refresh에는 `나중에`도 제공한다. 이 결정은
`notDetermined`와 `denied`를 같은 Family Controls 직접 요청으로 처리하던 `DEC-036`의 권한 행동 부분을
대체한다. `UILaunchScreen` 결정은 그대로 유지한다.

Background App Refresh는 플랫폼이 미결정 상태를 제공하지 않으므로 `available`을 허용으로,
`denied`·`restricted`를 거부 복구 상태로 정규화하고 별도 상태를 추정하지 않는다.

**근거**: 사용자가 수정한 US4 하이파이는 최초 요청 중, 승인 완료, 복구 필요 상태에서 행동 가능 여부를
명확히 다르게 정의한다. 시스템 prompt가 표시되는 동안 다음 단계로 진행하지 않게 하고, 승인 후 같은
화면에서 진행을 이어 가면 현재 시스템 상태와 안내가 어긋나지 않는다.

**영향 범위**: `PermissionGuideModel`, `PermissionGuideView`, `GetUpRootView`, US4 모델·UI 테스트와
US4 로우·하이파이 구현 인계에 적용한다.

## DEC-038 — 직접 시간대와 저장 장소 입력 경계

**날짜**: 2026-08-25

**결정**: 반복 시간대는 시작 시각부터 다음 종료 시각까지 15분 이상 12시간 이하로 제한한다.
종료 시각이 시작 시각보다 이르면 자정을 넘는 구간으로 해석하며, 15분 미만과 12시간 초과 후보는
저장 validation에서만 거절하지 않고 time wheel의 선택 가능한 조합에서도 제거한다.

장소 선택 화면은 저장 여부와 관계없이 `집`, `회사`, `직접 입력`을 항상 표시한다. 저장되지 않은
`집` 또는 `회사`를 적용하면 현재 지도 핀 좌표로 새 저장 장소를 만들고, `직접 입력`은 같은 화면에
이름 필드를 연다. 장소 이름은 앞뒤 공백을 제거한 1자 이상 10자 이하이며 대소문자를 구분하지 않은
정규화 key가 collection 안에서 고유해야 한다.

**근거**: 사용자는 자정을 넘는 생활 패턴을 설정할 수 있어야 하지만 지나치게 긴 제한을 실수로
만들어서는 안 된다. 잘못된 시간 조합을 wheel에서 애초에 제공하지 않으면 저장 시점 오류보다 직접적이다.
항상 보이는 생활 장소 프리셋과 같은 화면의 직접 입력은 지도 좌표와 이름 저장의 관계를 명확히 하고,
이름 길이·중복 경계는 카드와 선택 목록의 식별 가능성을 보존한다.

**영향 범위**: `ScheduleEvaluator`, `RestrictionRuleValidator`, `TimeRangePicker`,
`SavedPlaceNamePolicy`, `LocationPickerModel`, `LocationPickerView`, `RuleConfigurationService`, US1 테스트와
저장·platform event 계약에 적용한다.

## DEC-039 — Background App Refresh의 비차단 진단 경계

**날짜**: 2026-08-25

**결정**: Background App Refresh는 Family Controls, Always location, Full Accuracy와 달리 필수 권한
gate가 아니다. 이 진단 상태만 `denied` 또는 `restricted`인 경우 앱 실행·foreground 복귀 때 권한
안내를 자동 표시하지 않는다. 사용자가 순차 안내에서 해당 화면을 확인할 때는 앱별 Settings action을
제공하지 않고 `설정 > 일반 > 백그라운드 앱 새로 고침` 시스템 전체 경로와 저전력 모드 영향을
설명한 뒤 `나중에`로 닫을 수 있게 한다.

**근거**: iOS 앱별 Settings에는 GetUp의 Background App Refresh 변경 항목이 표시되지 않을 수 있고,
앱 전용 URL로는 시스템 전체 토글을 직접 열 수 없다. 진단 상태가 foreground마다 필수 권한 화면을
재등장시키면 사용 가능한 핵심 기능을 방해하고 사용자가 해결할 수 없는 action을 반복 제공한다.

**영향 범위**: `PermissionGuideModel`, `PermissionGuideView`, foreground 권한 갱신, US4 모델·UI 테스트,
권한 platform contract와 US4 하이파이 구현 인계에 적용한다.

## DEC-040 — 온보딩 권한 확인과 일반 복구 라우팅 분리

**날짜**: 2026-08-25

**결정**: 권한 개요와 정상 승인 상태를 순차 확인하는 흐름은 온보딩에서만 사용한다. 일반 앱 실행과
foreground 복귀에서는 모든 필수 권한이 정상이면 권한 안내를 표시하지 않는다. Family Controls가
`denied`이면 Family Controls 복구 화면, 위치가 `whenInUse`·`denied`·`restricted`이거나 정확도가
`reduced`이면 위치 복구 화면으로 전체 개요 없이 직접 이동한다. 여러 권한이 동시에 복구 대상이면
Family Controls를 먼저 표시하고 해결 후 위치 화면으로 전환한다. 일반 복구의 `notDetermined` 상태는
별도 화면을 자동 표시하지 않으며 최초 시스템 요청은 온보딩 문맥에 한정한다.

종료되거나 사용자가 닫은 온보딩 모델은 다음 lifecycle 갱신부터 일반 복구 모델로 교체한다. 따라서
온보딩 완료 후 권한을 철회하면 해당 권한 화면이 다시 표시되지만, 승인된 권한 화면이나 전체 권한
개요는 재등장하지 않는다.

**근거**: 승인된 상태를 foreground마다 다시 확인시키면 정상 사용을 방해하고, 한 권한만 문제인
상황에서 전체 개요를 거치게 하면 복구 대상이 불명확하다. 온보딩과 복구 문맥을 모델에 명시하면
최초 교육 흐름을 유지하면서 이후에는 현재 문제에 필요한 행동만 제공할 수 있다.

**영향 범위**: `PermissionGuideModel`, `GetUpRootView`, US4 모델·UI 테스트, `FR-050`과 US4 하이파이
구현 인계에 적용하며 `DEC-037`의 일반 실행 권한 화면 라우팅을 대체한다.

## DEC-041 — 권한 온보딩의 설치 단위 1회 표시

**날짜**: 2026-08-25

**결정**: 권한 온보딩은 설치 후 최초 앱 실행에서 한 번만 표시한다. 첫 화면을 생성하는 즉시
`UserDefaults`에 versioned 표시 표식을 기록하고, 이후 프로세스 실행에서는 현재 권한 snapshot이
`notDetermined`로 일시 관찰되더라도 온보딩을 다시 추정하지 않고 일반 복구 모드로만 라우팅한다.
앱 데이터가 제거되거나 앱을 재설치하면 표식도 초기화되어 새 설치의 최초 실행으로 취급한다.
이 표식이 도입되기 전부터 사용하던 설치는 Family Controls 또는 위치 권한이 이미 결정되어 있으면
기존 사용자로 판단해 표식을 기록하고 온보딩 대신 일반 복구 모드로 바로 이전한다.

**근거**: 프로세스 메모리에만 온보딩 문맥을 보존하면 앱을 완전히 종료할 때 상태가 사라지고, 다음
실행의 초기 권한 snapshot에 따라 전체 권한 화면이 반복된다. 표시 시점의 영구 표식은 사용자가
온보딩 중 앱을 종료한 경우에도 “최초 실행 1회” 계약을 유지한다. 결정된 권한 상태를 사용하는
호환 이전은 새 표식이 없던 기존 설치에서 업데이트 직후 온보딩이 한 번 더 표시되는 문제를 막는다.

**영향 범위**: `PermissionOnboardingStateStore`, `PermissionGuideLaunchRouter`, `GetUpRootView`,
US4 단위·UI 테스트, `FR-050`과 권한 platform contract에 적용하며 `DEC-040`의 프로세스 내 모델 교체
규칙을 설치 단위 실행 경계로 보강한다.

## DEC-042 — 위치 복구와 Background App Refresh 종료 행동

**날짜**: 2026-08-25

**결정**: Always location 또는 Full Accuracy가 부족한 위치 권한 복구 화면에서는 우회 종료 행동인
`나중에`를 제거하고 `설정 열기`만 제공한다. Background App Refresh 제한 안내는 필수 권한 복구가
아닌 정보 확인 화면이므로 단일 주요 행동을 `확인`으로 표시하고 안내를 닫는다.

**근거**: 위치 권한은 자동 제한에 필수이므로 복구 화면에서 행동 선택지를 설정 복구로 집중한다.
Background App Refresh는 사용자가 앱별 설정에서 직접 복구할 수 없는 진단 상태이므로 `나중에`보다
안내를 읽었음을 명확히 표현하는 `확인`이 실제 행동과 일치한다.

**영향 범위**: `PermissionGuideAction`, `PermissionGuideModel`, `PermissionGuideView`, US4 모델·UI·
접근성 테스트, `FR-052`와 US4 하이파이 구현 인계에 적용하며 `DEC-037`, `DEC-039`의 `나중에` 행동을
대체한다.

## DEC-043 — 시스템 권한·설정 안내의 코드 기반 목업

**날짜**: 2026-08-25

**결정**: Family Controls와 위치 최초 요청에는 iOS alert 구조를 본뜬 비대화형 목업을, 위치와
Background App Refresh 복구에는 Settings row·toggle 구조를 본뜬 비대화형 목업을 표시한다. 실제로
사용자가 선택해야 할 버튼, 설정 값과 toggle만 GetUp accent로 강조한다. 위치 복구 본문의
`‘항상 허용’으로 변경해 주세요.`와 `‘정확한 위치’를 켜 주세요.` 문구도 같은 색으로 강조한다.
목업은 raster screenshot 대신 SwiftUI로 구성하고, 전체 목업을 하나의 설명용 접근성 요소로 제공한다.

**근거**: 시스템 화면 캡처는 언어·OS 버전·기기 크기에 따라 빠르게 달라지고 Dynamic Type에 대응하지
못한다. 코드 기반 목업은 실제 시스템 UI와 구분되는 GetUp 시각 체계를 유지하면서도 사용자가 눌러야
할 항목의 위치와 이름을 미리 학습할 수 있고, VoiceOver에는 간결한 절차 설명을 제공할 수 있다.

**영향 범위**: `PermissionGuideView`, US4 UI·접근성 테스트, `FR-053`, 권한 platform contract와 US4
하이파이 구현 인계에 적용한다.

## DEC-044 — 권한 요청 목업의 명시적 탭과 문맥별 결과 전환

**날짜**: 2026-08-25

**결정**: Family Controls, 위치 `앱을 사용하는 동안 허용`, 위치 `항상 허용으로 변경` 요청은 화면
진입 시 자동 실행하지 않는다. 승인된 Figma의 중앙 alert 목업 안에서 강조된 주요 버튼을 사용자가
직접 누르면 해당 시스템 권한 요청을 실행한다. 요청 결과가 요구 수준을 충족하면 온보딩에서는 다음
권한 화면으로 자동 이동하고, 일반 사용 중 복구 화면에서는 안내를 닫는다. 요청이 거부되거나 요구
수준을 충족하지 못하면 같은 권한 화면을 유지하되 다음 주요 행동을 `설정 열기`로 변경한다.

Core Location의 Always 요청을 거부해도 시스템 승인 상태가 기존 `.whenInUse`로 유지될 수 있으므로,
앱은 해당 명시적 요청 직후 Always를 얻지 못한 결과를 현재 안내 세션의 거부로 기록한다. 이후 주요
버튼은 동일 Always prompt를 반복하지 않고 Settings 복구를 제공한다. alert 외형은 SwiftUI로
구성하지만 위치 지도 preview는 승인된 Figma export asset을 사용한다.

**근거**: 시스템 prompt를 화면 진입과 동시에 띄우면 사용자가 사전 설명을 읽기 어렵고, 거부 뒤 같은
요청을 반복하는 행동도 예측하기 어렵다. 앱 소유 목업의 명시적 탭과 문맥별 결과 전환은 교육용
온보딩과 사용 중 복구의 목적을 분리하면서 시스템 권한 요청 시점을 사용자가 통제하게 한다.

**영향 범위**: `PermissionGuideModel`, `PermissionGuideView`, `GetUpRootView`,
`CurrentLocationProvider`, US4 모델·통합·UI 테스트, `FR-054`와 US4 하이파이 구현 인계에 적용한다.
권한 요청 화면에 한해 `DEC-043`의 비대화형 목업·raster 불필요 결정을 대체한다.

## DEC-045 — 온보딩 완료 표식과 마지막 시작하기 행동

**날짜**: 2026-08-25

**결정**: 권한 온보딩을 처음 표시할 때 완료로 기록하지 않는다. 마지막
`백그라운드 새로 고침을 확인해 주세요` 화면에서 사용자가 `시작하기`를 누른 뒤에만 versioned
`UserDefaults` 완료 표식을 저장한다. 완료 전 앱 프로세스가 종료되면 다음 실행에서 온보딩 개요부터
다시 시작하고, 완료 후에는 일반 복구 라우터가 승인 상태에서는 홈으로, 부족한 권한이 있으면 해당
복구 화면으로 직접 진입한다. 현재 권한이 이미 결정되어 있다는 사실만으로 완료를 추정하지 않는다.

**근거**: 권한 승인과 제품 온보딩 완료는 서로 다른 상태다. 사용자가 권한 요청 도중 앱을 이탈했거나
시스템 prompt에서 돌아오지 않은 경우에도 최초 화면 표식이나 현재 권한 snapshot으로 완료를 추정하면
남은 설명을 보지 못한 채 홈으로 진입한다. 사용자가 마지막 행동을 명시적으로 누르는 시점을 단일 완료
경계로 삼으면 중단 복구와 이후 일반 실행을 결정론적으로 구분할 수 있다.

**영향 범위**: `PermissionOnboardingStateStore`, `PermissionGuideLaunchRouter`,
`PermissionGuideAction`, `PermissionGuideView`, `GetUpRootView`, US4 단위·UI 테스트, `FR-050`,
`FR-055`, 권한 platform contract와 US4 하이파이 구현 인계에 적용한다. 최초 표시 즉시 완료하고
결정된 권한으로 기존 설치를 추정하던 `DEC-041`을 대체하며, 온보딩 Background App Refresh 행동을
`확인`으로 정의한 `DEC-042`는 일반 복구에만 유지한다.

## DEC-046 — 장소 선택 초기 상태와 앱 선택 권한 경계

**날짜**: 2026-08-25

**결정**: 새 규칙에서 저장 장소가 아직 선택되지 않은 장소 화면은 사용자 현재 위치를 최초 한 번
조회해 지도 중심과 핀으로 사용한다. 기존 규칙이나 저장 장소 재사용 흐름은 저장 좌표를 보존한다.
장소 이름 선택은 `집`, `회사`, 저장 장소, `직접 입력` 중 하나의 명시적 상태로 관리하고 선택 색상과
VoiceOver 선택 trait에 함께 반영한다. 이름이 비어 있을 때는 `장소 이름을 입력해 주세요.`를 화면에
한 번만 표시한다.

제한 앱 선택 행은 Family Controls 승인 상태를 먼저 확인한다. 승인 상태에서만 system-owned
`FamilyActivityPicker`를 열며, `notDetermined` 또는 `denied`이면 앱 선택 행을 비활성화하지 않고
Family Controls 권한 상세 화면으로 전환한다. 실제 시스템 권한 요청은 상세 화면의 명시적 목업 버튼을
누른 뒤에만 실행한다.

**근거**: 새 장소 지도의 고정 기본 좌표는 사용자가 실제 생활 장소를 고르기 위해 불필요하게 지도를
이동하게 한다. 장소 이름을 문자열로만 추론하거나 동일 검증을 두 위치에서 출력하면 선택 강조가
사라지고 같은 오류가 중복 표시될 수 있다. 앱 선택 행에서 직접 권한을 요청하거나 아무 반응 없이
실패하는 흐름은 `DEC-044`의 사전 설명과 명시적 요청 경계를 우회하므로 기존 권한 상세 화면을 단일
진입점으로 재사용한다.

**영향 범위**: `LocationPickerModel`, `LocationPickerView`, `RuleEditorView`, `GetUpRootView`, US1
단위·UI 테스트, `FR-056`~`FR-058`에 적용한다.

## DEC-047 — Family Activity 선택 대상의 통합 계산과 shield 적용

**날짜**: 2026-08-25

**결정**: `FamilyActivitySelection`의 개별 앱, 카테고리와 웹 도메인 token을 모두 유효한 제한
대상으로 계산한다. 화면에 표시하는 선택 수는 각 token 선택 항목 수의 합이며 카테고리 내부의 실제
앱 개수를 추정하지 않는다. 실제 제한은 개별 앱 token을 `shield.applications`, 카테고리 token을
`shield.applicationCategories = .specific(...)`, 웹 도메인 token을 `shield.webDomains`에 적용한다.
여러 활성 규칙은 각 종류별 합집합을 사용한다. 저장된 활성 revision 집합이 같아도 실제 GetUp store의
shield가 기대값과 다르면 idempotency 조기 종료를 하지 않고 다시 적용한다.

**근거**: Family Activity Picker의 카테고리 선택은 `applicationTokens`가 아니라
`categoryTokens`에 저장되므로 앱 token 수만 검사하면 사용자 선택을 0개로 오인한다. 유효성만
수정하고 runtime에서 앱 token만 적용하면 저장은 되지만 실제 제한이 동작하지 않으므로 편집·저장·
홈과 Managed Settings 적용 경계를 같은 선택 모델로 맞춰야 한다. 카테고리 내부 앱 수는 opaque
system token만으로 안전하게 계산할 수 없어 선택 항목 수만 표시한다. 기존 설치에서 이미 같은
revision이 활성 상태로 기록된 경우에도 누락된 category shield를 복구하려면 store 내용 비교가
필요하다.

**영향 범위**: `FamilyActivitySelection.restrictionTargetCount`, `RuleEditorModel`,
`RuleConfigurationService`, `AppModel`, `FamilyActivitySelectionAdapter`,
`ManagedSettingsRestrictionAdapter`, 관련 단위·통합 테스트, `FR-008`, `FR-062`와 플랫폼 이벤트
계약에 적용한다.

## DEC-048 — 시간 선택의 전용 화면과 단일 wheel 선택 행

**날짜**: 2026-08-25

**결정**: 시작·종료 시각 선택은 sheet가 아니라 승인된 Figma `80:2010`·`80:2033`과 같은 전용
navigation destination으로 제공한다. app-owned 시간 화면은 Liquid Glass navigation control을 쓰지
않고 44pt 노란 꺾쇠를 사용한다. 시스템 `Picker(.wheel)`의 입력·접근성 동작은 유지하되 iOS 26에서
열마다 표시되는 선택 배경 위에 불투명한 단일 accent 행과 현재 시·분·AM/PM 값을 표시한다. wheel
card는 410pt, 하단 완료 CTA는 64pt로 고정한다.

**근거**: 기존 large sheet, toolbar 완료와 열별 선택 pill은 승인된 전체 화면 계층·강조 방식과 크게
달랐다. wheel 자체를 다시 구현하면 관성·접근성·값 선택 회귀 위험이 커지므로 native interaction을
보존하면서 승인된 하나의 선택 행만 시각적으로 합성한다. 전용 화면과 명시적 뒤로가기는 시작·종료
편집 맥락을 유지하면서 Figma의 editorial hierarchy를 재현한다.

**영향 범위**: `RuleEditorView`, `TimeRangePicker`, US1 UI 회귀, `FR-063`,
`design/high-fidelity/US1-rule-configuration.md`에 적용한다.

## DEC-049 — 홈 요일 구간 축약과 한국어 localization fallback

**날짜**: 2026-08-25

**결정**: 활성·비활성 홈 카드는 `HomeWeekdayFormatter` 하나를 공유한다. 월요일부터 일요일까지
정렬한 선택 요일을 최대 연속 구간으로 나누고, 구간 길이가 2 이상이면 `시작-끝`, 단일 요일이면
요일 약어로 표시하며 각 구간은 ` · `로 구분한다. 따라서 월~금은 `MON-FRI`, 월~일은 `MON-SUN`,
토~일은 `SAT-SUN`, 수~금은 `WED-FRI`가 된다. 일요일과 월요일은 주간 표시 경계를 넘어 하나의
구간으로 합치지 않는다.

프로젝트 `developmentRegion`과 `Localizable.xcstrings`의 `sourceLanguage`는 모두 `ko`로 맞춘다.
활성 상태, 수정 차단과 guard Alert의 필수 문구는 `String(localized:defaultValue:)`를 통해 한국어
기본값도 함께 제공해 지원하지 않는 기기 언어에서도 resource key가 화면에 노출되지 않게 한다.

**근거**: 활성·비활성 카드의 별도 요일 formatter는 같은 규칙을 서로 다르게 표시하고 연속 요일을
불필요하게 길게 나열했다. 또한 한국어 string catalog와 영어 development region의 불일치 때문에
영어 기기 언어에서 `restriction_status.*`와 `restriction_guard.*` key가 그대로 fallback됐다.
단일 formatter와 일치하는 source language를 사용하면 표시 규칙과 현지화 fallback을 결정론적으로
유지할 수 있다.

**영향 범위**: `HomeWeekdayFormatter`, `RestrictionStatusView`, `HomeRuleCard`,
`RestrictionCopy`, Xcode project localization 설정, US1·US3·접근성 UI 회귀, `FR-064`·`FR-065`에
적용한다.

## DEC-050 — 시스템 BackButton과 opaque 카테고리 선택 요약

**날짜**: 2026-08-25

**결정**: `NavigationStack`으로 push되는 앱 소유 하위 화면은 custom chevron을 만들지 않고 iOS 기본
BackButton을 사용한다. 시간 선택 화면도 navigation bar를 숨기지 않으며 시스템 BackButton의 label,
hit area와 접근성 동작을 유지한다.

`FamilyActivitySelection`에 카테고리 token이 하나라도 포함되면 편집 화면은 `여러 앱 선택됨`, 홈은
`여러 앱`으로 표시한다. 카테고리가 없고 개별 제한 대상 수를 정확히 아는 경우에만 숫자를 표시한다.
유효성 검증과 Managed Settings 적용은 기존처럼 카테고리 token을 하나의 제한 대상으로 계산하며,
이번 결정은 카테고리 내부 앱 수를 나타내는 사용자 표시만 변경한다.

**근거**: 시스템 BackButton은 iOS navigation의 일관된 복귀 제스처, hit area와 VoiceOver 의미를
제공한다. Apple의 `FamilyActivitySelection`과 `ActivityCategoryToken`은 개인정보 보호를 위해
카테고리 내부 앱 목록이나 개수를 앱에 노출하지 않는 opaque token 경계이므로 숫자를 추정하면 실제
선택과 다른 정보를 표시할 수 있다.

**영향 범위**: `RuleEditorView`, `FamilyActivitySelection.restrictionSelectionSummary`,
`HomeRuleItem`, `HomeRuleCard`, `RestrictionStatusView`, US1 단위·UI 회귀, `FR-063`, `FR-066`,
`FR-067`과 US1 하이파이 구현 인계에 적용한다. 시간 화면의 custom 44pt 노란 꺾쇠를 정한
`DEC-048`의 해당 부분을 대체한다.

## DEC-051 — 고정 시간 설정 화면과 순차 완료 흐름

**날짜**: 2026-08-26

**결정**: 시작·종료 시각 설정 화면의 root는 `ScrollView`가 아닌 고정 `VStack`으로 구성해 화면
전체가 움직이지 않게 한다. 사용자는 각 native wheel만 위아래로 조작한다. 시작 화면의 `완료`는
규칙 편집 화면으로 복귀하지 않고 현재 navigation destination을 종료 시각 화면으로 전환하며, 종료
화면의 `완료`가 규칙 편집 화면으로 복귀한다.

시간 wheel 위에는 native 선택값을 다시 그리는 불투명 overlay나 별도 custom 선택 강조를 두지 않는다.
wheel 자체의 값과 iOS 기본 선택 표시를 그대로 사용한다. 각 picker에 추가했던 명시적 `.clipped()`도
제거해 인접 숫자의 glyph가 별도 view clipping에 잘리지 않게 한다. 이 시간 wheel의 세부 시각은 사용자
승인에 따라 Figma 하이파이보다 숫자 가독성을 우선한다.

**근거**: 화면 root scroll과 wheel scroll이 중첩되면 시간 조작 중 전체 화면이 움직일 수 있다.
또한 picker 위의 58pt 불투명 선택 행과 별도 선택값 text는 native wheel의 중앙 및 인접 숫자를
가렸다. 화면과 wheel의 scroll 책임을 분리하고 native 값을 직접 노출하면 조작 대상과 표시 결과가
일치한다. 시작·종료 설정을 순차로 연결하면 시작 완료 뒤 규칙 편집 화면에서 종료 행을 다시 누르는
불필요한 단계를 제거한다.

**영향 범위**: `RuleEditorView.timePickerDestination`, `TimeRangePicker`, US1 UI 회귀,
`FR-063`, `FR-068`과 US1 하이파이 구현 인계에 적용한다. 410pt card와 불투명 단일 accent 선택 행을
정한 `DEC-048`의 해당 부분을 대체한다.

## DEC-052 — 제한 안내의 Figma SVG와 불투명 배경

**날짜**: 2026-08-26

**결정**: 제한 안내 화면의 정적 아이콘은 승인된 Figma shield `113:2025` 안의 `113:2028` GetUp
아이콘을 SVG로 직접 export해 Shield Configuration extension 전용 asset catalog에 보존한다.
`ShieldConfigurationExtension`은 이 이미지를 extension bundle에서 읽고 `.alwaysOriginal`로 표시한다.
기존 범용 `figure.stand` SF Symbol은 사용하지 않는다.

배경에는 material blur를 적용하지 않고 승인 색상 `#08090B`를 직접 지정한다. 제목·설명과 primary
`앱 닫기`의 동적 내용·동작은 기존 계약을 유지하며, content layout과 system button rendering은
`ManagedSettingsUI` 소유 경계를 존중한다.

**근거**: 첨부된 실제 화면의 범용 사람 아이콘과 회색 material 배경은 승인된 Dark Focus
하이파이의 제품 정체성과 명암을 반영하지 못했다. Figma 원본 SVG를 직접 bundle에 포함하면 만료되는
export URL이나 SF Symbol에 의존하지 않고 동일한 88×88 자산을 재현할 수 있다. blur를 제거해야
배경색이 주변 앱 화면의 영향 없이 결정적으로 유지된다.

**영향 범위**: `GetUpShieldConfiguration/ShieldConfigurationExtension.swift`, Shield Configuration
전용 `Assets.xcassets`, Xcode resource build phase, US2 하이파이 구현 인계, `FR-069`와 T104에
적용한다. 실기기의 system-owned layout·Dynamic Type·VoiceOver 최종 검증은 T085에 남긴다.

## DEC-053 — 로컬 홈 우선 표시와 비차단 runtime 복구

**날짜**: 2026-08-26

**결정**: 앱 시작 시 `AppModel.load()`로 보호된 로컬 규칙·저장 장소와 기존 적용 상태를 먼저 읽고,
성공하는 즉시 홈을 표시한다. `AppLifecycleCoordinator.restore()`가 수행하는 일정·region 초기화,
규칙별 재등록, 현재 위치 갱신, 권한 확인과 제한 합집합 재평가는 홈 표시 뒤 같은 view lifecycle의
후속 비동기 작업으로 실행한다. 복구 완료 뒤 제한 상태와 권한 안내를 최신 결과로 갱신한다.

시작 복구가 진행되는 동안 동일 view에서 foreground 복구가 요청되면 두 번째 복구는 시작하지 않는다.
복구 호출은 `AppEnvironment.RuntimeRecovery` closure로 주입해 앱 shell이 구체 actor 대신 비동기 복구
계약에만 의존하고, 지연된 복구를 UI 회귀에서 결정적으로 검증한다.

**근거**: 기존 시작 순서는 홈 데이터와 무관한 Core Location 단발성 fix를 규칙마다 기다린 뒤
로컬 파일을 다시 읽어, 위치 응답이 느리거나 규칙 수가 많을수록 `규칙을 불러오는 중` 전체 화면을
오래 유지했다. runtime 복구는 `FR-026`의 상태 일치를 위해 필요하지만 시스템 제한과 적용 상태는
앱 화면과 독립적으로 보존되므로 로컬 홈 표시를 막을 이유가 없다. 화면 표시와 복구 책임을 분리하면
안전한 재평가는 유지하면서 재실행 체감 시간을 로컬 snapshot read 시간으로 제한할 수 있다.

**영향 범위**: `GetUpRootView`, `AppEnvironment.RuntimeRecovery`, UI test 시작 fixture,
`FR-070`, T105와 foreground 복구 흐름에 적용한다. 실제 위치 fix 시간과 전체 복구 latency는 T083·
T085의 실기기 관찰 범위를 유지한다.

## DEC-054 — 제한 안내의 appearance별 대비와 시스템 layout 경계

**날짜**: 2026-08-26

**결정**: Shield Configuration은 다크 모드에서 승인된 `#08090B` 배경, `#FFFFFF` 제목과
`#A6A8AD` 설명을 유지한다. 라이트 모드에서는 `#F5F5F7` 배경, `#090A0C` 제목과 `#51535A` 설명을
사용한다. primary action은 appearance에 따라 색이 변하는 `.systemYellow` 대신 두 모드 모두 GetUp
`#F4D600`과 `#090A0C` label을 사용한다. fallback 설명은 `설정한 위치에서 벗어나거나 시간이 끝나면
자동으로 다시 사용할 수 있어요.`로 고정한다.

글꼴 크기와 icon·제목·설명·버튼 사이의 padding은 `ManagedSettingsUI`가 소유하므로 custom view로
대체하지 않는다. 앱이 제공할 수 있는 title·subtitle의 의미적 순서, adaptive text/background 색과
primary 색으로 시각 위계와 가독성을 보완한다.

**근거**: 실제 라이트 모드 화면에서 다크 모드용 흰 제목과 밝은 회색 설명이 밝은 배경 위에 그대로
표시되어 내용을 읽기 어려웠고 `.systemYellow` 버튼은 어두운 올리브색으로 변했다. appearance별
foreground/background를 함께 결정하고 브랜드 accent를 명시하면 시스템 layout을 침범하지 않으면서
두 모드의 대비를 안정적으로 유지할 수 있다.

**영향 범위**: `ShieldConfigurationExtension`, `ShieldContentProvider`, `Localizable.xcstrings`,
shield contract, US2 하이파이 구현 인계, `FR-069`, `FR-071`과 T106에 적용한다. 실제 restricted app의
system-owned layout, Dynamic Type·VoiceOver와 appearance 최종 확인은 T085 실기기 인수에서 수행한다.

## DEC-055 — Shield callback의 전체 제한 대상 token 매칭

**날짜**: 2026-08-26

**결정**: `ShieldContentProvider`는 `ApplicationToken`뿐 아니라 Shield callback에서 제공되는
`ActivityCategoryToken`과 `WebDomainToken`도 활성 규칙의 `FamilyActivitySelection`과 비교한다.
application-in-category와 web-domain-in-category callback은 전달받은 두 token을 모두 사용하되,
규칙 배열을 한 번만 filter해 같은 규칙을 중복 계산하지 않는다. 일치하는 단일 규칙의 저장 장소는
프리셋과 직접 입력을 구분하지 않고 ID로 찾아 상세 콘텐츠를 만든다.

**근거**: Managed Settings는 카테고리로 선택한 앱에 대해 application과 category를 함께 전달하지만,
기존 extension은 category를 버리고 application token만 비교했다. opaque category 선택에는 개별 앱
token이 저장되지 않으므로 활성 규칙이 0개로 오인되어 fallback이 표시됐다. 웹 도메인 callback도
같은 이유로 token을 버리고 있었다.

**영향 범위**: `ShieldContentProvider`, `ShieldConfigurationExtension`, shield contract,
`FR-072`, T107과 카테고리·웹 도메인 직접 입력 장소 회귀 테스트에 적용한다. snapshot 자체를 읽지
못하거나 일치 규칙·저장 장소가 실제로 없을 때의 fallback 계약은 유지한다.

## DEC-056 — 시간 완료 CTA 전체 hit area와 Shield 순수 검정 label

**날짜**: 2026-08-26

**결정**: 시간 설정 화면의 완료 CTA는 `Button` 바깥에 frame과 배경을 붙이지 않고 label 내부에
실제 `RoundedRectangle` fill과 text를 겹친 64pt `ZStack`을 둔다. label과 `Button` 양쪽에 전체 사각
content shape를 적용해 보이는 버튼 좌우 끝도 동일한 완료 행동을 실행한다.

Shield primary label은 기존 브랜드 near-black `#090A0C` 대신 순수 검정 `#000000`으로 지정한다.
GetUp `#F4D600` 배경은 유지하며 계산상 대비는 약 `14.47:1`이다. 시스템 소유 글꼴 굵기와 layout은
변경하지 않는다.

**근거**: plain button에서 label 바깥에 적용한 frame·background는 accessibility frame을 넓혔지만
실제 hit testing은 텍스트 부근에 남았다. 채워진 shape를 label의 실제 view로 만들었을 때 좌측 8%와
우측 92% 좌표 탭이 모두 전환을 실행했다. 첨부된 다크 Shield에서는 버튼 글자가 노란 배경 위에서
옅게 보여 앱이 제공 가능한 가장 어두운 불투명 색으로 대비를 강화할 필요가 있었다.

**영향 범위**: `RuleEditorView.timePickerDestination`, `ShieldPalette.primaryButtonText`, US1 UI 회귀,
US1·US2 하이파이 구현 인계, shield contract, `FR-071`, `FR-073`과 T108에 적용한다. 실제 Shield의
system compositing 결과는 T085 실기기 인수에서 다시 확인한다.

## DEC-057 — 종료 시간 wheel의 독립 상태와 명시적 유효성 차단

**날짜**: 2026-08-26

**결정**: 종료 시간의 시·분·AM/PM Picker는 각자 독립된 `@State`에 직접 바인딩하고, 사용자가 한
wheel을 움직일 때 선택된 세 구성요소를 조합해 `endTime`에 반영한다. 다른 wheel의 후보 배열을 현재
값으로 필터링하거나 가장 가까운 유효 시간을 다시 선택하지 않는다. 시작 후 15분 미만 또는 12시간
초과의 임시 조합은 그대로 표시하되 안내를 오류색으로 바꾸고 종료 화면의 `완료` CTA를 비활성화한다.

시작 화면에서 종료 화면으로 전환할 때는 `TimeRangePicker` identity를 boundary별로 분리해, 시작 시각
변경에 따라 계산된 최초 유효 종료 시각으로 종료 wheel의 로컬 상태를 새로 초기화한다.

**근거**: 종료 후보를 현재 period·hour·minute으로 교차 필터링하고 변경된 구성요소와 일치하는 가장
가까운 시간을 고르면 분을 움직였을 때 시가 바뀌고 AM/PM을 움직였을 때 시·분까지 바뀐다. 필터만
제거해도 세 Picker가 하나의 계산 binding을 공유하면 SwiftUI의 선택 동기화 중 다른 열이 재설정될 수
있다. 독립 상태와 완료 시점 검증을 분리하면 `10:00~10:15`처럼 경계에 가까운 시간도 예측 가능하게
조작하면서 15분~12시간 제품 규칙은 유지할 수 있다.

**영향 범위**: `TimeRangePicker`, `RuleEditorView.timePickerDestination`,
`ScheduleEvaluatorTests`, US1 시간 UI 회귀, `FR-063`과 T109에 적용한다. 종료 후보를 wheel에서 아예
제거하던 기존 US1 acceptance 15와 `DEC-051`의 유효성 표현을 이 결정으로 보완한다.

## DEC-058 — Icon Composer 원본 기반 앱 아이콘 브랜딩

**날짜**: 2026-08-26

**결정**: 사용자 제공 `Icon.icon`을 GetUp 앱 target의 primary app icon 원본으로 직접 연결한다.
`ASSETCATALOG_COMPILER_APPICON_NAME`은 파일명과 같은 `Icon`을 사용하고, `.icon` package를 app resource
build phase에 포함한다. Xcode가 원본의 노란 배경, 검정 GetUp glyph, appearance별 fill·opacity·glass
설정에서 default·dark·clear·tinted icon과 iPhone·iPad 크기를 생성하게 한다.

기존 `AppIcon.appiconset`의 PNG export는 사용자가 준비한 비교·fallback 산출물로 보존하지만 primary
icon으로 선택하지 않는다. 브랜딩 appearance 변경은 중복 export를 직접 교체하지 않고 `Icon.icon`
원본에서 수행한다.

**근거**: 프로젝트 최소 지원 버전은 iOS 26이며 제공된 브랜딩 원본이 Icon Composer의 layer와
appearance specialization을 이미 포함한다. 원본을 직접 컴파일하면 clear·tinted를 포함한 시스템
appearance와 크기를 Xcode가 일관되게 생성하고, asset catalog의 세 PNG slot을 수동 동기화할 때 생길
수 있는 appearance 누락을 피할 수 있다.

**영향 범위**: `Icon.icon`, `GetUp.xcodeproj/project.pbxproj`, `FR-074`, T110과 T085의 실기기
appearance 인수에 적용한다. 실제 Home Screen의 wallpaper·clear·tinted 조합 시각 확인은 T085에 남긴다.

## DEC-059 — 외부 제품명 `나서`와 내부 `GetUp` 식별자 분리

**날짜**: 2026-08-26

**결정**: 사용자가 읽는 제품명은 `나서`로 변경한다. 홈 header·빈 상태·활성 카드, 권한 안내와 시스템
설정 목업, `CFBundleDisplayName`, 위치 권한 설명, VoiceOver 문구와 Shield title은 “어서 집 밖을
나서”라는 브랜드 약속을 반영한다. Shield 상세 제목은 `%@에서 %@ 밖으로 나서세요`, fallback 제목은
`밖으로 나설 시간이에요`를 사용한다. 제한 해제 조건과 시간·반경 정보는 기존 정확성을 유지한다.

Bundle ID `com.dxyn02.GetUp` namespace, `group.com.dxyn02.GetUp`, Xcode project·target·scheme·module,
Swift 타입, `GetUpAppGroupIdentifier`, `getup.*` 저장·schedule·region 식별자는 변경하지 않는다. 이들은
이미 entitlement, 공유 저장소, 배포 profile과 영속 데이터에 연결된 기술 식별자이므로 외부 브랜드와
분리한다. 사용자 요청에 따라 `Icon.icon`과 `GetUpShieldLogo.svg`의 시각 교체는 별도 작업으로 남긴다.

**근거**: `GetUp`은 App Store에서 동명·유사 앱과 겹치고 “일어나기”에 더 가깝지만, 제품의 핵심
행동은 설정한 장소의 경계를 넘어 집 밖으로 나서는 것이다. 외부 카피를 `나서`로 통일하면 이 행동을
홈과 제한 화면에서 일관되게 전달하면서, entitlement 재발급과 기존 공유 데이터 단절 위험 없이
리브랜딩할 수 있다.

**영향 범위**: `GetUpApp`의 홈, `PermissionGuideView`·`PermissionGuideModel`, `LocationPickerView`,
`Info.plist`, `ShieldContentProvider`, `Localizable.xcstrings`, US1·US2·US4 UI와 문구 회귀, `FR-075`,
T111에 적용한다. 앱 아이콘과 Shield SVG의 새 브랜드 asset은 후속 별도 작업에서 결정한다.

## DEC-060 — 위치 CTA hit area와 새 Shield 심볼 연결

**날짜**: 2026-08-26

**결정**: 위치 선택 화면의 `적용` CTA는 56pt `RoundedRectangle`과 텍스트를 모두 `Button` label
내부에 두고 label 전체에 rectangular content shape를 적용한다. 홈 빈 상태 설명은 사용 결과가 더
직접 드러나도록 `밖으로 나가면 제한된 앱이 다시 열려요`를 사용한다.

Shield Configuration extension은 기존 `GETUP` wordmark asset을 제거하고 새 `나서` 심볼 SVG를
`NaseoShieldLogo`라는 새 asset 이름으로 불러온다. 새 이름은 확장 bundle의 이전 asset 이름과
충돌하지 않게 하며, vector 원본과 `.alwaysOriginal` rendering은 유지한다.

**근거**: frame·background가 plain `Button` 바깥에 있으면 보이는 버튼보다 hit-test 영역이 작아져
텍스트를 눌러야만 적용되는 현상이 발생했다. 또한 기존 extension asset catalog에는 새 심볼이 아니라
`GETUP` wordmark SVG가 남아 있어 코드가 정상적으로 asset을 읽어도 이전 로고가 표시됐다.

**영향 범위**: `GetUpApp.emptyState`, `LocationPickerView.applyButton`,
`ShieldConfigurationExtension`, extension 전용 asset catalog, `Localizable.xcstrings`, US1 UI 회귀,
`FR-076`과 T112에 적용한다.

## DEC-061 — 시간 종료 callback의 규칙별 동기 해제

**날짜**: 2026-08-26

**결정**: 활성 규칙마다 `getup.restriction.<rule UUID>` 이름의 독립 `ManagedSettingsStore`를 사용한다.
`DeviceActivityMonitor.intervalDidEnd`가 전달되면 activity name에서 rule ID를 복원하고, callback 안에서
해당 store를 동기적으로 비운 뒤 App Group의 적용 상태에서 그 규칙만 제거한다. 다른 활성 규칙의
store는 그대로 유지한다. 기존 버전의 단일 `getup.restriction` 합집합 store는 남은 모든 규칙의 독립
store가 확인될 때만 동기 제거하며, 안전하게 분리할 수 없으면 기존 coordinator 재평가로 넘긴다.

**근거**: Apple의 Device Activity 계약상 `intervalDidEnd`는 schedule 종료 정각이 아니라 종료 구간
밖에서 기기가 처음 사용될 때 호출될 수 있다. 따라서 기기가 유휴 상태인 동안 정각 해제를 보장할
수는 없지만, callback을 받은 뒤 `Task`만 예약하면 extension이 비동기 작업 완료 전에 종료되어 첫
제한 앱 접근에서도 이전 shield가 남을 수 있다. 시스템 store 변경은 callback 안에서 즉시 수행할 수
있으며, 규칙별 store를 사용하면 한 규칙 종료 시 겹친 다른 규칙의 제한을 보존할 수 있다.

**영향 범위**: `SharedIdentifiers`, `ManagedSettingsRestrictionAdapter`,
`DeviceActivityIntervalEndHandler`, `DeviceActivityMonitorExtension`, adapter·latency 테스트,
`platform-events-contract.md`, `FR-077`과 T113에 적용한다. 실제 callback 전달 시점과 system shield
반영은 T083·T085 실기기 관찰에서 별도로 기록한다.

## DEC-062 — 단일 제한 store 복원과 마지막 규칙 동기 해제

**날짜**: 2026-08-26

**상태**: DEC-061의 규칙별 store 결정을 대체함

**결정**: 실제 제한 적용은 기존에 실기기에서 검증된 단일 `getup.restriction` store에 모든 활성
규칙의 제한 대상 합집합을 쓰는 방식으로 복원한다. `intervalDidEnd` callback의 rule ID가 현재 적용
상태의 마지막 활성 규칙이면 단일 store와 적용 상태를 callback 안에서 동기 해제한다. 다른 활성
규칙이 남아 있거나 callback을 해석할 수 없으면 단일 store를 부분 변경하지 않고 coordinator가 전체
규칙을 재평가해 합집합을 다시 쓴다.

**근거**: DEC-061의 규칙별 named store 구현은 protocol test double과 Simulator build에서는
통과했지만 실제 기기에서 Screen Time 제한이 전혀 적용되지 않는 회귀를 만들었다. 단일 store는 이전
실기기 검수에서 앱·카테고리·웹 도메인 shield 적용이 확인된 경로다. 마지막 규칙 종료는 합집합 전체를
안전하게 비울 수 있으므로 동기 처리할 수 있고, 겹친 규칙 종료는 남은 규칙의 전체 selection 없이는
부분 해제가 안전하지 않으므로 기존 재평가가 필요하다.

**영향 범위**: `ManagedSettingsRestrictionAdapter`, `DeviceActivityIntervalEndHandler`, adapter 테스트,
`platform-events-contract.md`, `FR-077`과 T114에 적용한다. DEC-061의 규칙별 store 및 migration 설명은
더 이상 현재 구현 계약이 아니다.

## DEC-063 — 앱 launch 상주 delegate의 region event 직접 재평가

**날짜**: 2026-08-26

**결정**: SwiftUI 앱은 `UIApplicationDelegateAdaptor`로 main run loop에서 생성한
`CLLocationManager`와 delegate를 launch 시점부터 유지한다. `didEnterRegion`·`didExitRegion` callback의
identifier가 `getup.location.<rule UUID>`이고 현재 활성 규칙과 일치할 때, 시스템이 확인한 전이를
각각 `.inside`·`.outside`인 `.regionEvent` 위치 snapshot으로 App Group에 저장하고 즉시
`RestrictionCoordinator.handleLocationEvent`로 제한 합집합을 재평가한다. 외부 namespace, 삭제됐거나
비활성화된 규칙의 stale event는 무시한다.

region callback 뒤 별도의 `requestLocation()` 성공을 해제 조건으로 추가하지 않는다. iOS geofence
전이 자체를 신뢰 가능한 플랫폼 event로 사용하고, callback 전달 시각을 30초 측정의 `confirmedAt`으로
삼는다. foreground 복구의 fresh fix와 위치 오류 보존 정책은 그대로 유지한다.

**근거**: 기존 구현은 `CLCircularRegion`을 등록했지만 어느 `CLLocationManager`에도 region delegate를
연결하지 않았다. 따라서 백그라운드 이탈 시 저장 위치와 제한을 갱신할 실행 지점이 없었고, 사용자가
앱을 열었을 때만 `AppLifecycleCoordinator.restore()`의 fresh fix가 동작해 제한이 풀렸다. Core
Location은 등록한 manager와 무관하게 활성 manager delegate에 region event를 전달하며, 앱이 region
event로 재실행될 때도 launch에서 manager와 delegate를 다시 구성해야 한다. 전이 뒤 단발 위치 조회를
추가하면 짧은 background 실행 시간과 위치 조회 실패 때문에 이미 확인된 이탈을 놓칠 수 있다.

**영향 범위**: `GetUpApp`, `SharedIdentifiers`, `LocationRegionEventHandler`, 위치 monitoring adapter
테스트, `FR-030`·`FR-031`·`FR-077`, T116과 T083·T085 실기기 인수에 적용한다. 사용자가 앱을 강제
종료했거나 Background App Refresh를 끈 플랫폼 제한에서는 iOS가 앱을 깨우지 않을 수 있으며, 이는
권한 안내와 실기기 인수에서 구분해 기록한다.

## DEC-064 — 100m부터 1km까지 네 단계 반경

**날짜**: 2026-08-26

**결정**: 새 반경의 닫힌 집합은 `100m`, `250m`, `500m`, `1km`이며 slider는 이 네 값에만 snap한다.
`RadiusOption`에서 기존 `2km`, `3km`, `4km`, `5km` case를 제거하고 구형 저장값을 migration하거나
복원하지 않는다. 새 규칙의 기본 반경은 기존과 같은 `1km`를 유지한다.

**근거**: 사용자가 실제 생활권에 맞는 더 작은 반경을 선택하고 최대 범위를 1km로 제한하도록 직접
요청했으며, 기존 데이터 호환 없이 새 값 집합으로 덮어쓰는 정책을 승인했다. 모델·validator·UI가
동일한 `RadiusOption.allCases`를 사용하면 화면에 보이는 값과 저장 가능한 값의 불일치를 막을 수 있다.

**영향 범위**: `RadiusOption`, `RestrictionRuleValidator`, `RadiusPicker`, `LocationPickerView`, 위치
monitoring parameterized test, `FR-007`, 위치 관련 contract와 T117에 적용한다. DEC-018의 여섯 단계
결정과 구형 반경 저장값은 더 이상 현재 계약이 아니다.

## DEC-065 — 시작 callback 내 동기 제한 적용과 일정 재등록 금지

**날짜**: 2026-08-26

**결정**: `DeviceActivityMonitor.intervalDidStart`는 callback 반환 전에 App Group의 현재 schema 규칙·
위치 snapshot과 현재 Family Controls·위치 권한을 동기적으로 읽는다. 앱의 `RestrictionCoordinator`와
같은 순수 규칙 평가기를 사용해 모든 규칙을 평가하고, 조건을 충족하거나 안전하게 보존해야 하는 활성
규칙의 제한 대상 합집합을 단일 `getup.restriction` store에 쓰고 read-back으로 확인한다. 실제 store
확인 뒤에만 App Group 적용 revision 집합을 갱신한다.

시작 callback에서는 `AppLifecycleCoordinator.restore()`를 호출하지 않으며 Device Activity 일정과
region을 제거·재등록하지 않는다. snapshot read, schema 또는 store read-back이 실패하면 기존 일정·
shield·적용 상태를 보존한다. 비동기 호환 경로는 일정 초기화 없이 현재 시간 제한만 다시 평가한다.

**근거**: 기존 경로는 callback에서 unstructured `Task`만 예약하고 반환한 뒤, 그 Task 안에서 일정
전체 제거·재등록과 위치 갱신을 거쳐 제한을 적용했다. extension이 Task 완료 전에 종료되면 store
쓰기가 실행되지 않을 수 있고, 이미 활성인 interval을 재등록하면 시작 callback이 즉시 재전달되어
재진입과 경합을 만들 수 있다. Apple의 Device Activity 사용 예도 시작 callback 본문에서
`ManagedSettingsStore` shield를 직접 변경한다. callback 전달 자체는 기기 사용 시점에 의존하므로
벽시계 정각보다 늦을 수 있지만, 전달된 callback 안의 제한 반영은 동기적으로 완료할 수 있다.

**영향 범위**: `DeviceActivityMonitorExtension`, `DeviceActivityIntervalStartHandler`,
`RestrictionRuleSetEvaluator`, Managed Settings adapter·coordinator 테스트,
`platform-events-contract.md`, `FR-078`, T118과 BLK-011에 적용한다. DEC-028의 공통 전체 복구 결정은
앱 foreground에는 유지하지만 `intervalDidStart`에는 더 이상 적용하지 않는다. 실제 system callback과
shield 반영은 T083·T085 실기기 인수에서 확인한다.

## DEC-066 — 앱 권한 snapshot으로 extension의 미결정 위치 권한 보완

**날짜**: 2026-08-26

**결정**: 메인 앱의 `SystemAuthorizationProvider`는 권한을 읽을 때마다 관찰 시각을 포함한
`AuthorizationSnapshotRecord`를 App Group `UserDefaults`에 저장한다. Device Activity extension은
자체 `CLLocationManager`가 위치 권한을 `notDetermined`로 반환하고 기록이 24시간 미만일 때에만 앱이
관찰한 위치 권한·정확도를 사용한다. Family Controls도 extension에서 `notDetermined`이면 같은 기록의
앱 값을 사용한다. Family Controls가 `denied`이거나 extension의 위치 권한이 `denied`·`restricted`·
`whenInUse`·`always`로 명시되면 현재 값을 우선한다.

**근거**: 실기기에서 `GetUpDeviceActivityMonitor` 프로세스 실행은 확인됐지만 제한이 적용되지 않았다.
짧게 실행되는 extension에서 delegate 없이 새 `CLLocationManager`를 생성한 직후 읽는 초기 권한이
`notDetermined`이면 승인된 규칙도 필수 권한 부족으로 탈락할 수 있다. 실기기 진단에서 위치뿐 아니라
Family Controls도 앱 `approved`와 달리 extension에서 `notDetermined`로 확인됐다. 앱이 실제 권한
컨텍스트에서 확인한 최근 값으로 이 미결정 상태만 보완하면 앱 상주 의존성을 제거하면서, 사용자의
명시적 권한 철회를 오래된 캐시가 무시하는 위험을 막을 수 있다. 24시간은 기존 위치 snapshot 신뢰
한계와 맞춘다.

**영향 범위**: `SharedIdentifiers`, `AuthorizationSnapshotRecord`, `SystemAuthorizationProvider`,
`DeviceActivityAuthorizationSnapshotReader`, authorization·Managed Settings adapter 테스트,
`shared-storage-contract.md`, `platform-events-contract.md`, `FR-079`, T119와 BLK-012에 적용한다.

## DEC-067 — 신규 규칙 초기 시간과 단일 규칙 홈 상호작용 단순화

**날짜**: 2026-08-27

**결정**: 신규 규칙은 생성 시점의 현재 현지 시·분을 시작 시각으로, 15분 뒤를 종료 시각으로
초기화한다. 직접 입력 장소 chip은 입력한 이름을 표시하고 재탭하면 이름을 지우지 않은 채 입력
field와 focus를 다시 제공한다.

홈 화면 전체는 세로 scroll container를 사용하지 않는다. 저장 규칙이 하나면 card를 직접 표시하고
pager, page indicator와 `좌우로 밀어 보기` 문구를 만들지 않으며, 두 개 이상일 때만 좌우 pager를
사용한다.

**근거**: 신규 규칙이 고정된 `06:00`~`09:00`으로 시작하면 현재 상황에 맞춰 두 값을 모두 다시
조정해야 한다. 최소 유효 구간인 15분을 현재 시각에서 바로 제공하면 유효한 초안을 유지하면서 입력
부담을 줄인다. 직접 입력 이름을 chip에 반영하고 재편집 진입점으로 사용하면 선택 결과와 행동이
일치한다. 홈은 고정된 한 화면이며, 이동할 규칙이 없을 때 pager affordance를 노출하면 실제로 가능한
상호작용을 잘못 안내한다.

**영향 범위**: `RuleEditorModel`, `LocationPickerView`, `HomeView`, US1 단위·UI 테스트,
`FR-080`~`FR-083`과 T121에 적용한다.

**구현 메모 (2026-08-27)**: 규칙 삭제 저장과 `AppModel.apply`는 마지막 규칙에서 `homeRules = []`,
`selectedRuleID = nil`로 정상 전환했지만, 사라지는 SwiftUI `TabView`가 기존 `Binding`을 지연 평가하며
fallback `homeRules[0]`을 호출해 main thread에서 index crash가 발생했다. pager selection과 page
tag를 `UUID?`로 바꿔 빈 collection을 `nil` selection으로 표현한다. 마지막 규칙 삭제 뒤에도 저장
장소는 보존하며 빈 홈으로 전환한다. `FR-084`와 T122에 적용한다.

## DEC-068 — Always 위치 권한 요청의 bounded callback 대기

**날짜**: 2026-08-27

**결정**: `.whenInUse`에서 실행한 `requestAlwaysAuthorization()`은 권한 변경 delegate callback을
우선 기다린다. 권한 prompt로 앱이 inactive가 되면 다시 active가 될 때 현재 권한을 읽고, prompt가
표시되지 않은 채 1초 안에 callback도 없을 때에는 bounded fallback으로 현재 권한을 다시 읽는다.
결과가 `.always`이면 기존 성공 전환을 유지하고, `.whenInUse`이면 현재 안내 세션에서 미승격으로
기록해 무한 로딩 대신 `설정 열기`와 수동 Always 변경 안내를 제공한다. 이후 시스템 prompt 응답으로
앱이 다시 active가 되면 기존 foreground 복구가 최종 권한 상태를 다시 반영한다.

**근거**: Core Location은 최초 요청에서 `한 번만 허용`을 선택한 임시 `.authorizedWhenInUse` 상태의
후속 Always 요청을 무시하며, 사용자가 `앱을 사용하는 동안 허용`을 유지한 경우에도 권한 값이 바뀌지
않아 delegate callback을 보내지 않는다. 기존 checked continuation은 이 callback만 종료 조건으로
사용해 온보딩 버튼이 영구 로딩 상태가 됐다. callback 우선 처리와 bounded fallback을 함께 사용하면
정상 승격은 즉시 반영하면서 무응답 경로도 예측 가능한 Settings 복구로 끝낼 수 있다.

**영향 범위**: `CoreLocationCurrentLocationSession`, `PermissionGuideModel`, US4 어댑터·모델·UI
테스트, `FR-085`와 T123에 적용하며 `DEC-044`의 미승격 Settings 전환을 비동기 무응답에도 보장한다.

## DEC-069 — 저장 장소 독립 삭제와 위치 선택 세션 보존

**날짜**: 2026-08-27

**결정**: `집`·`회사` 프리셋을 제외하고 사용자가 직접 입력해 저장한 장소만 장소 선택 chip에서
삭제할 수 있다. destructive 확인 뒤 최신 영속 규칙 collection의 활성·비활성 규칙을 모두 검사하며,
참조 규칙이 하나라도 있으면 장소·규칙을 그대로 두고 참조 수를 안내한다. cascade 삭제와 dangling
reference는 만들지 않는다. 미사용 장소만 장소 collection revision을 증가시켜 저장하고 마지막
장소여도 빈 collection을 기록한다. 저장 실패 전에는 메모리 chip을 제거하지 않는다.

저장되지 않은 현재 초안이 삭제 장소를 선택 중이면 선택 ID와 이름은 지우되 지도 핀은 보존한다.
같은 규칙 편집 세션에서 위치 화면을 적용하지 않고 나갔다 다시 들어올 때에는 `RuleEditorView`가
동일한 `LocationPickerModel`을 재사용한다. 선택 장소 좌표와 같은 MapKit 정착 callback은 프로그램
이동으로 취급해 선택을 유지하고, 실제로 다른 좌표에 정착했을 때만 선택을 해제한다.

**근거**: 규칙 저장 service는 들어온 장소를 기존 collection과 병합하므로 화면 목록에서만 제거하면
다음 규칙 저장 때 장소가 되살아난다. 반대로 참조 중인 장소를 먼저 제거하면 `AppModel`의 규칙-장소
결합과 runtime 조건에 dangling reference가 생긴다. 전용 저장소 삭제 경계에서 최신 참조를 검사하고
성공 뒤에만 메모리를 갱신하면 데이터 무결성과 재시도 가능성을 함께 보장한다. 위치 선택은 Apply 전
임시 상태이므로 편집 세션이 유지되는 동안 별도 picker 모델이 소유하는 것이 사용자의 선택 기대와
일치한다.

**영향 범위**: `RuleConfigurationService`, `AppModel`, `RuleEditorModel`, `RuleEditorView`,
`LocationPickerModel`, `LocationPickerView`, US1 단위·UI 테스트, `FR-086`~`FR-089`와 T124에 적용한다.

**구현 메모 (2026-08-27)**: 직접 입력 장소는 위치 `적용` 직후 `RuleEditorModel.savedPlaces`에 먼저
추가되고 규칙을 저장할 때에만 영속 장소 collection에 기록된다. 따라서 삭제 대상이
`AppModel.savedPlaces`에는 없고 현재 editor에만 있으면 초안 전용 장소로 판정한다. 이 경우 저장소
service를 호출하지 않고 editor와 picker에서만 제거한다. 영속 장소만 기존 최신 규칙 참조 검사와
revision 증가 경로를 사용하며, 초안 전용 `집`·`회사`도 삭제 불가 원칙을 유지한다. T125에 적용한다.

## DEC-070 — 저장 장소 ID를 보존하는 좌표 재할당

**날짜**: 2026-08-27

**결정**: `집`·`회사` 프리셋과 직접 입력 저장 장소를 선택한 뒤 지도를 이동하거나 현재 위치
바로가기를 사용해도 `LocationPickerModel`은 선택 장소 ID·이름·chip 선택 상태를 유지한다. 좌표가
기존 값과 같으면 재사용 완료로 처리하고, 달라진 좌표를 적용하면 `RuleEditorModel`이 기존 장소 ID·
이름·`createdAt`을 보존한 채 좌표와 `updatedAt`만 갱신한다. 규칙 저장은 같은 ID의 장소 snapshot을
upsert하고 전체 runtime 복구를 실행한다.

같은 장소는 여러 규칙이 공유하는 aggregate이므로 장소 좌표 변경은 현재 편집 규칙만의 복사본을
만들지 않고 해당 ID를 참조하는 모든 규칙에 반영한다. `DEC-069`에서 실제로 다른 좌표에 정착하면
선택을 해제하도록 한 부분은 이 결정으로 대체하며, 장소 삭제 시 선택을 지우는 동작은 유지한다.
다른 규칙을 편집하더라도 변경 장소를 참조하는 규칙 중 현재 제한 중인 규칙이 있으면 저장을 거부해
활성 중 수정 차단을 우회하지 못하게 한다.

**근거**: 기존 구현은 지도 이동 시 선택 ID와 이름을 지워 다시 `집` chip을 누르면 저장된 옛 좌표로
카메라를 되돌렸다. 선택을 유지하기만 해도 완료 결과가 이름 중복을 발견해 기존 snapshot만 다시
선택하고 새 좌표를 버렸으므로, picker 완료 상태와 editor upsert 양쪽에 명시적인 좌표 갱신 경계가
필요하다. ID를 보존하면 규칙 참조 무결성과 장소 collection의 중복 이름 정책을 함께 유지할 수 있다.

**영향 범위**: `LocationPickerModel`, `RuleEditorModel`, `RuleConfigurationService`, `AppModel`,
US1 모델·저장소·UI 회귀, `FR-090`과 T127에 적용한다.

## DEC-071 — Live Activity 대표 규칙·코인 사용 표면·iCloud 잔액 복구

**날짜**: 2026-09-01

**결정**: 여러 규칙이 동시에 활성이면 Live Activity는 가장 먼저 활성화된 대표 규칙
1개의 해제까지 남은 직선 거리와 시간만 표시한다. 다른 규칙이 있음을 함께 알리고
대표 규칙 종료 후 다음 규칙으로 교체한다. Live Activity는 읽기 전용이며 코인 사용은
Shield와 앱 내 활성 제한 화면에서만 명시적 확인 후 허용한다.

코인은 소모성 인앱결제 재화로 판매하며, 확인된 구매 지급과 사용·보정 내역을 같은
iCloud 계정의 기기 간에 동기화해 미사용 잔액을 복구한다. iCloud 장부는 구매 사실 자체를
새로 증명하지 않으며 각 지급은 유효하게 확인된 구매 결과와 연결한다. App Store 구매
계정과 iCloud 계정이 다를 수 있으므로 잔액 복구는 동일 iCloud 계정 유지를 기준으로 하고
이 조건을 구매 전에 안내한다.

**근거**: 대표 규칙 하나만 표시하면 복수 Live Activity의 표시 잡음을 줄일 수 있고,
코인 사용을 더 많은 정보를 제공하는 Shield·앱 내로 한정하면 오사용과 겹친 규칙 오해를
줄일 수 있다. 소모성 상품은 일반 복원 흐름만으로 잔여 수량을 재구성할 수 없으므로,
확인된 지급과 사용 장부를 함께 동기화해야 중복 지급과 잔액 유실을 동시에 막을 수 있다.

**영향 범위**: `specs/002-live-activity-coins/spec.md`의 Live Activity 표시, 코인 해제,
구매·잔액·복구 요구사항과 후속 계획·테스트에 적용한다.

## DEC-072 — 월간 무료 해제권 2회와 구매 코인 분리

**날짜**: 2026-09-01

**결정**: 같은 iCloud 계정에 매월 무료 해제권을 2회 제공한다. 월 중간에 처음 사용한
사용자도 해당 월의 2회를 받는다. 남은 무료분은 다음 달로 이월하거나 누적하지 않고 새 달에
사용 가능 수량을 2회로 갱신한다. 규칙 해제 시 무료 해제권을 구매 코인보다 먼저 사용한다.

무료 해제권과 구매 코인은 별도 잔액·변동으로 관리하고 화면에서도 구분한다. 월간 지급은
iCloud 계정과 연월의 조합마다 한 번만 확정해 여러 기기, 재실행, 기기 날짜 변경으로 2회를
초과하지 않게 한다. iCloud 상태를 신뢰할 수 없으면 지급을 보류하고 상태 확인 후 재시도한다.
구매 코인은 월간 무료분 갱신과 무관하게 보존하며 만료시키지 않는다.

**근거**: 월 2회의 무료 예외는 실수·긴급 상황의 안전장치를 제공한다. 비이월 방식은 장기간
미사용으로 해제 수단이 과도하게 누적돼 제한 기능의 목적이 약해지는 것을 막는다. 무료분과
구매분을 분리하면 월간 갱신이 유료 잔액에 영향을 주지 않으며, 구매 재화의 비만료 원칙과
환불·복구 장부를 명확하게 유지할 수 있다.

**영향 범위**: `specs/002-live-activity-coins/spec.md`의 무료 지급, 잔액 표시, 사용 순서,
iCloud 동기화, 월 경계 및 구매 코인 보존 요구사항과 후속 계획·테스트에 적용한다.

## DEC-073 — 저전력 거리 갱신과 서울 기준 월 경계

**날짜**: 2026-09-01

**결정**: Live Activity의 남은 거리를 위해 지속적인 background location update를 새로 사용하지
않는다. 기존 시스템 위치 이벤트 또는 앱 실행 시 얻은 신뢰 가능한 거리만 표시하고, 마지막 위치가
신뢰 기준을 벗어나면 이전 거리를 유지하지 않고 확인 불가로 전환한다. 이동 중 거리의 연속 갱신은
제품 보장 범위에 포함하지 않는다.

월간 무료 해제권은 `Asia/Seoul` 시간대의 매월 1일 00:00을 경계로 갱신한다. 계정·월별 결정적
지급 ID와 CloudKit 서버 시각을 함께 사용해 기기 날짜·시간대 변경으로 미래나 과거 월의 지급을
반복 확정하지 않는다.

**근거**: 기존 region monitoring과 단발 위치 확인 구조를 유지하면 지속 위치 추적으로 인한 배터리와
개인정보 범위 확대를 피할 수 있다. 오래된 거리의 확인 불가 전환은 정확하지 않은 값을 현재값으로
오인하는 문제를 막는다. 현재 주요 사용자의 기대에 맞춰 서울의 달력상 1일 자정을 월 경계로 사용한다.

**영향 범위**: `specs/002-live-activity-coins/spec.md`의 거리 표시·성공 기준, 월간 무료 지급,
CloudKit 동시성 계약과 후속 계획·테스트에 적용한다.

## DEC-074 — 서버 없는 초기 Live Activity·결제 범위

**날짜**: 2026-09-01

**결정**: 초기 범위에서는 별도 앱 서버, ActivityKit push-to-start, App Store Server Notifications를
도입하지 않는다. Live Activity는 앱이 foreground에서 제한 시작 또는 현재 활성 제한을 확인할 때
로컬로 시작한다. 앱 비실행 상태에서 자동 제한이 시작되면 Shield는 적용하지만 Live Activity 자동
시작은 보장하지 않는다.

구매 코인은 기기에서 검증된 StoreKit 2 거래만 CloudKit private database의 지급 장부에 반영하고,
앱 실행 때 transaction update와 미완료 거래를 재조정한다. 환불·철회도 앱이 검증된 상태를 확인한
시점에 조정한다. 같은 iCloud 계정의 CloudKit 장부는 기기 간 잔액 복구에 사용하지만 구매의 권위
있는 서버 증명으로 간주하지 않는다. private zone 삭제, iCloud·App Store 계정 불일치, 앱 장기
미실행 중 환불 반영 지연과 소모성 구매 완전 복원의 한계를 구매 전에 안내한다.

**근거**: 초기 제품 검증 단계에서 서버 비용과 키·알림·장애 대응 운영을 추가하지 않는다. 로컬
ActivityKit과 StoreKit·CloudKit만으로 핵심 사용 흐름을 검증할 수 있으며, 서버가 필요한 자동 시작과
강한 결제 신뢰성은 실제 유료 판매 규모와 위험이 확인된 뒤 별도 범위로 도입할 수 있다.

**영향 범위**: `specs/002-live-activity-coins/spec.md`의 `FR-001`, `FR-022`, `FR-036`, `SC-001`,
Phase 1 ActivityKit·StoreKit·CloudKit 계약과 구매 전 고지 UI에 적용한다.

## DEC-075 — 구매 가용성·Live Activity 재생성·상품 묶음·장부 삭제 복구

**날짜**: 2026-09-01

**결정**: iCloud 계정과 최신 CloudKit 장부를 확인할 수 없으면 StoreKit 구매를 시작하지 않고
구매 버튼을 비활성화한다. 사용자가 진행 중인 Live Activity를 직접 지워도 활성 제한이 남아 있는
동안 앱을 다시 foreground로 열면 현재 대표 규칙의 Live Activity를 재생성한다. 초기 consumable
상품은 코인 1개·3개·5개 묶음으로 구성하고 가격은 App Store Connect의 현지 가격을 사용한다.

코인 기능 최초 활성화와 각 구매 확정 전에 CloudKit 개인 장부 삭제의 복구 불가 가능성을 고지한다.
장부 삭제가 확인되면 코인 구매·사용을 잠그고 로컬 mirror로 자동 복원하거나 조용히 초기화하지
않는다. 사용자가 새 장부 시작을 명시적으로 확정한 경우에만 구매 코인 0개·현재 월 무료 해제권
0회로 시작하며, 다음 `Asia/Seoul` 월 경계부터 무료 해제권 2회 지급을 재개한다.

**근거**: iCloud commit이 불가능한 상태에서 결제를 시작하면 결제와 지급이 분리될 수 있다. 활성
제한 중 foreground 재진입 시 Live Activity를 다시 보여 주는 것은 사용자가 선택한 지속 안내 정책과
일치한다. 작은 상품 묶음은 예외적 해제라는 목적을 유지한다. 삭제된 장부를 오래된 기기 mirror로
복원하면 이미 사용한 유료·무료 재화가 되살아날 수 있으므로, 명시적 0 초기화와 사전 고지가 가장
예측 가능하다.

**영향 범위**: `specs/002-live-activity-coins/spec.md`의 구매 흐름, Live Activity 복구, IAP catalog,
CloudKit 삭제 경계와 후속 계획·계약·테스트에 적용한다.

## DEC-076 — Live Activity 거리 표시와 Shield 단일 해제 경로

**날짜**: 2026-09-01

**결정**: Live Activity 남은 거리는 기존 `LocationEvidenceEvaluator`가 `.inside`로 판정한 5분 이내
근거에서만 `max(0, radius - centerDistance)`로 계산한다. 단위 전환 없이 항상 미터로 표시하며 가장
가까운 10m로 half-up 반올림해 정확히 5m인 경계는 위쪽 값으로 올린다. 그 밖의 위치 상태에는 이전
숫자를 유지하지 않고 확인 불가를 표시한다.

Shield는 기존 제한 안내 요소와 `앱 닫기`를 유지하고 `해제권 1회 사용` primary button 하나를
추가한다. 사용자가 누르면 최신 CloudKit 장부와 현재 occurrence를 확인해 당월 무료 해제권을 먼저
예약하고, 없으면 구매 코인 1개를 예약한다. 당월 allowance가 없고 장부가 `current`이면 quota 2
생성과 첫 무료 예약을 같은 원자적 command로 처리한다. 해제 성공 뒤 대표 Live Activity를 즉시
갱신하거나 끝내되 ActivityKit 실패는 성공한 제한 해제와 장부 commit을 되돌리지 않는다.

`current` 장부에서 잔액만 부족하면 `PendingAppRoute.coinStore`를 기록하고 앱의 구매 화면으로
유도한다. iCloud·장부가 unavailable·stale·삭제 확정·재조정 중이면 구매를 유도하지 않고 복구
route를 기록한다. iOS 26.5 이상은 공식 `ShieldActionResponse.openParentalControlsApp`을 사용하고,
iOS 26.0~26.4는 앱 실행 안내와 `.close`를 사용한 뒤 사용자가 앱을 열면 pending route를 소비한다.
Shield에는 상품·가격·결제 제안을 직접 표시하지 않는다.

**근거**: 단일 버튼은 무료 우선 정책을 사용자에게 예측 가능하게 만들면서 stale mirror로 funding
source를 미리 단정하지 않는다. 장부 불확실 상태와 실제 잔액 부족을 분리하면 지급을 확정할 수 없는
결제로 유도하는 문제를 막는다. 설치된 iOS 26.5 SDK에서 앱 직접 열기 응답의 도입 버전을 확인했으므로
최소 지원 버전 전체에는 명시적 호환 경로가 필요하다.

**영향 범위**: `specs/002-live-activity-coins`의 `spec.md`, `plan.md`, `research.md`,
`data-model.md`, Live Activity·규칙 해제·Shield UI contract, `quickstart.md`, `tasks.md`의 거리 정책,
해제 state machine, 앱 route와 OS 버전별 실기기 검증에 적용한다.

## DEC-077 — Live Activity 계측·iCloud 잔액 복구·Shield 5초·월간 지연 생성

**날짜**: 2026-09-02

**결정**: Live Activity 시작 성공률은 지원 기기, 권한 허용, 유효한 활성 제한, 앱 foreground를 모두
만족하는 100회만 모집단으로 삼고 활성 제한 확인부터 30초 안에 95회 이상 표시되는지 측정한다.
권한 거부·미지원은 제한 기능 독립성을 확인하는 별도 안전 실패 테스트로 다룬다. 거리 갱신은 메인
앱이 신뢰 위치를 받고 ActivityKit 조정이 가능해진 시점부터 30초를 측정하며, extension-only 위치는
저장 후 다음 foreground의 조정 가능 시점부터 측정한다.

로컬 코인 데이터가 없는 재설치·새 기기는 동일 iCloud의 기존 CloudKit 장부를 먼저 fetch한다.
현재 epoch와 검증된 StoreKit transaction에 연결된 지급·사용·보정 projection이 `current`이면
미사용 잔액과 내역을 복구한다. 이는 StoreKit `구매 복원`이나 새 지급이 아니며 `iCloud 잔액 동기화`
또는 `iCloud 잔액 복구`로 안내한다. 장부 부재·삭제·불확실 상태에서는 자동 복구하지 않는다.

Shield 해제 요청은 primary action이 service에 전달된 때부터 최대 5초 안에 CloudKit 성공을 확인한
경우에만 제한을 해제한다. 5초 안에 성공을 확인하지 못하면 Shield를 유지하고, 같은 command ID의
늦은 결과를 다음 앱 foreground에서 재조정해 제한이 해제되지 않은 차감을 보상한다. 5초는 Apple의
공식 보장값이 아닌 제품 내부 상한이므로 네트워크·저전력·iCloud 오류를 포함한 실기기 검증을
완료 조건으로 둔다.

월간 무료 해제권은 `Asia/Seoul` 자정을 정책 경계로 사용하되 정확한 자정 background 실행을
요구하지 않는다. 새달 첫 앱 foreground 또는 Shield 해제 요청에서 지연 생성하며, Shield가 첫
요청이면 quota 2 생성과 무료 1회 reservation을 하나의 원자적 장부 명령으로 처리한다.

**근거**: Apple은 소모성 구매의 내부 상태를 앱이 영속화하고 iCloud로 기기 간 동기화할 수 있다고
안내하지만, 완료된 소모성 구매의 잔량은 일반 구매 복원만으로 재구성할 수 없다. 또한 background
task는 지정 시각 실행이 보장되지 않고 Shield extension의 정확한 실행 시간도 공개 보장되지 않는다.
따라서 사용자 상호작용을 신뢰 가능한 지급 트리거로 사용하고, 짧은 timeout·fail-closed·멱등
재조정으로 제한과 유료 재화의 일관성을 보존한다.

**영향 범위**: `specs/002-live-activity-coins`의 `plan.md`, `research.md`, `data-model.md`, 다섯
contract와 `quickstart.md`, `tasks.md`에 적용한다.

## DEC-078 — 장부 current 증명·최초 활성화 구분·분석 보완 게이트

**날짜**: 2026-09-02

**결정**: 코인 장부의 `current`는 iCloud 계정 사용 가능, 현재 프로세스 private database 초기 fetch
완료, 주입 가능한 monotonic clock 기준 마지막 성공 fetch 이후 5분 이내, 로컬 mirror·`LedgerEpoch`·
`CoinAccount` epoch 일치, fetch된 구매 지급·사용·보정 projection 완료, 결과 불명 release command와
pending reconciliation 없음이 모두 성립할 때만 부여한다. 구매와 해제 직전 최신 서버 record를 다시
확인하고 monotonic 경과 시간이 5분을 넘으면 `stale`로 전환한다. persisted wall-clock `syncedAt`은
표시·진단 전용이며 프로세스 재시작 뒤 새 fetch 전에는 `current`를 복원하지 않는다.

로컬 데이터가 없는 설치는 세 상태로 나눈다. 기존 동일 iCloud 장부가 `current`이면 잔액·내역만
복구한다. 초기 fetch 뒤 원격 장부와 삭제 증거가 모두 없으면 `setupRequired`로 두고 최초 활성화
고지 확인 뒤 initial epoch와 현재 월 무료 2회를 한 번 생성한다. `userDeletedZone` 또는 기존 장부
보유 증거 뒤 zone 부재로 삭제가 확인되면 `deletionConfirmed`로 잠그고 사용자 reset 뒤 구매 0·삭제
월 무료 0으로 시작한다. `setupRequired`는 고지와 명시적 activation action 뒤 initial epoch+당월
무료 2회를 만드는 `CoinLedgerSetupService`, 삭제 확인은 구매 0+당월 무료 0을 만드는
`CoinLedgerResetService`의 서로 다른 허용 상태와 entry point를 사용한다. 일시적 불확실성은 자동
생성·복구하지 않는다. 별도 서버가 없어 새 설치에서
원격 장부와 삭제 증거를 모두 잃은 사례는 최초 사용자와 완전히 구분할 수 없으며 이를 최초 활성화와
구매 전에 고지한다.

월 계산·quota 2·비이월, 지연 생성과 Shield의 allowance 생성+무료 1회 reservation 원자성은 US2보다
앞선 공통 기반에서 구현한다. Shield Action의 직접 ActivityKit 갱신·종료는 US1의 공유 attributes·
system adapter·coordinator(T011·T032·T033) 뒤 지원 OS 실기기 probe를 완료하고 성공이 재현된 경로만
T055에 연결한다. US2 해제 core와 fallback은 이 probe와 병렬 진행할 수 있다. `PendingAppRoute`는 생성 후 5분 이내,
활성 occurrence, 미소비 조건을 모두 만족할 때 atomic하게 한 번 소비하며 stale·중복·종료 route는
폐기한다. Live Activity 남은 시간은 주입 시계에서 오차 60초 이내와 종료 후 0 clamp를 자동
검증한다. 마감 계측은 전용 테스트 결과를 집계하며 같은 계측 로직을 중복 구현하지 않는다.

**근거**: `current`의 객관적 증명 조건이 없으면 stale mirror로 유료 재화를 구매·사용할 수 있고,
최초 활성화와 삭제 reset을 같은 부재 상태로 처리하면 신규 사용자 무료 2회와 삭제 월 무료 0 정책이
충돌한다. 월간 원자 예약은 Shield 무료 우선 해제의 선행 의존성이다. ActivityKit extension 접근은
Simulator 가정만으로 제품 경로를 결정할 수 없고, route·남은 시간 경계는 헌법상 핵심 실패·경계
자동 테스트가 필요하다.

**영향 범위**: `specs/002-live-activity-coins`의 전체 설계 산출물과 T007~T021, T024, T039~T040,
T055, T057, T064, T073, T076, T078~T085, T092, T096, T098에 적용한다.

## DEC-079 — CloudKit container 식별자와 접근 타깃

**날짜**: 2026-09-02

**결정**: 코인 장부의 CloudKit container는 기존 배포 namespace에 맞춘
`iCloud.com.dxyn02.GetUp`을 사용한다. `GETUP_ICLOUD_CONTAINER_IDENTIFIER` 공통 build setting으로
정의하고 메인 앱과 `GetUpShieldAction`이 같은 container의 private database에 접근한다. 두 타깃의
entitlement에는 `com.apple.developer.icloud-container-identifiers`와
`com.apple.developer.icloud-services = CloudKit`을 선언한다.

**근거**: 메인 앱과 Shield Action은 같은 계정 범위 장부에서 구매·무료 잔액 및 해제 reservation을
원자적으로 확인해야 한다. container 식별자를 공통 build setting으로 관리하면 target별 문자열
불일치와 다른 private database 접근을 막을 수 있다.

**영향 범위**: `Configuration/Base.xcconfig`, `GetUp/GetUp.entitlements`,
`GetUpShieldAction/GetUpShieldAction.entitlements`와 후속 CloudKit adapter에 적용한다. 실제 배포 전
Apple Developer에서 container 등록, 두 App ID 할당, production schema와 서명 entitlement를
T097에서 확인한다.

## DEC-080 — 초기 코인 상품 식별자와 번들 허용 catalog

**날짜**: 2026-09-02

**결정**: 초기 consumable 상품 ID는 각각 `com.dxyn02.GetUp.coin.1`,
`com.dxyn02.GetUp.coin.3`, `com.dxyn02.GetUp.coin.5`를 사용한다. 세 식별자는
`GETUP_COIN_PRODUCT_1_IDENTIFIER`, `GETUP_COIN_PRODUCT_3_IDENTIFIER`,
`GETUP_COIN_PRODUCT_5_IDENTIFIER` build setting으로 관리한다. 앱 Info.plist의
`GetUpCoinProductCatalog`는 각 식별자를 지급 수량 1·3·5와 명시적으로 매핑하며 이 목록 밖의 상품은
지급 대상으로 인정하지 않는다. 완료된 소모성 거래의 후속 검증을 위해
`SKIncludeConsumableInAppPurchaseHistory`를 활성화한다. 로컬 StoreKit fixture에서는 세 상품을
판매 가능한 `Consumable`로 두고 한국어 `코인 1개`·`코인 3개`·`코인 5개`, 영어 `1 Coin`·
`3 Coins`·`5 Coins`와 KOR 테스트 가격 ₩1,100·₩2,900·₩4,400을 사용한다. 이 가격은 로컬 테스트
시나리오용이며 App Store Connect의 실제 판매 가격을 확정하지 않는다.

**근거**: StoreKit에서 전달된 product ID만으로 지급 수량을 추측하지 않고 배포 설정의 고정 허용
목록과 대조해야 잘못된 상품·수량 지급을 막을 수 있다. 동일 ID를 StoreKit Configuration과 App Store
Connect에서 사용하면 로컬·sandbox·production 검증의 계약이 일치한다.

**영향 범위**: `Configuration/Base.xcconfig`, `GetUp/Resources/Info.plist`, 후속
`CoinProductCatalog`, StoreKit Configuration 및 App Store Connect 상품 등록에 적용한다.

## DEC-081 — 공용 scheme·test plan의 Live Activity·StoreKit 연결

**날짜**: 2026-09-02

**결정**: 공용 `GetUp` scheme의 BuildAction에 `GetUpLiveActivity`를 명시하고 Run action의
`StoreKitConfigurationFileReference`는 `Configuration/GetUp.storekit`을 가리킨다. 공용
`GetUp.xctestplan`은 `storeKitConfiguration = GetUp.storekit`을 사용하고 실제 test target은
`GetUpTests`·`GetUpUITests`, 변수 확장 target은 메인 앱으로 유지한다. 비테스트 Widget Extension을
test target으로 추가하지 않는다.

Phase 1의 빈 Live Activity target이 실행 파일 없는 `.appex`를 만들어 앱 설치를 막지 않도록
`GetUpLiveActivity/GetUpLiveActivityBundle.swift`에 제품 UI를 노출하지 않는 link anchor를 둔다.
T036에서 같은 파일을 실제 `WidgetBundle`과 Live Activity UI로 교체한다.

**근거**: 앱의 target dependency만으로 compile은 성공해도 소스가 전혀 없는 extension에는 bundle
executable이 생성되지 않아 Simulator와 실기기 설치가 실패한다. 공용 build graph에 extension을
명시하고 최소 실행 산출물을 확인해야 이후 단위·UI 테스트를 설치할 수 있다. StoreKit 구성은 Run
scheme과 test plan에 각각 지정해야 앱 수동 실행과 자동 테스트가 동일한 로컬 상품 catalog를 사용한다.

**영향 범위**: `GetUp.xcodeproj/project.pbxproj`, 공용 `GetUp.xcscheme`, `GetUp.xctestplan`,
`GetUpLiveActivity/GetUpLiveActivityBundle.swift`와 T036의 실제 Widget 구현에 적용한다.

## DEC-082 — CloudKit 장부 record의 명시적 필드 whitelist

**날짜**: 2026-09-02

**결정**: 여섯 코인 장부 record type은 schema version별 명시적 필드 whitelist로만 encode·decode한다.
decode 시 알 수 없는 필드가 하나라도 있으면 record를 무시하지 않고 `invalidRecord` 경계로 거부한다.
singleton·월·거래·event·command record name도 payload에서 다시 계산한 결정적 ID와 일치해야 하며,
현재 구현은 schema version 1만 허용한다. 새 필드를 추가할 때는 schema version을 올리고 별도 migration
codec을 제공한다.

**근거**: 위치 좌표·정확도와 Family Controls token·앱/도메인 식별 정보는 CloudKit 저장 금지
데이터다. 쓰기 필드만 제한하면 다른 기기나 향후 adapter 오류로 섞인 민감 필드를 기존 client가
조용히 수용할 수 있으므로 읽기 경계도 닫아야 한다. 미지 필드 추가를 schema 변경으로 취급하면
구버전 client가 부분 payload를 잘못 해석하는 것도 막을 수 있다.

**영향 범위**: `CoinLedgerRecordMapper`, 후속 CloudKit database adapter·repository와 record schema
migration에 적용한다.

## DEC-083 — 코인 장부 변경의 단일 CAS 조정 경계

**날짜**: 2026-09-02

**결정**: 코인 잔액 또는 월간 무료분을 바꾸는 모든 repository 명령은 mutable record의 최신
change tag와 `ifServerRecordUnchanged`를 사용하고, 대응하는 결정적 audit event와 `ReleaseCommand`를
하나의 atomic modify에 포함한다. 충돌은 서버 상태를 다시 읽어 같은 command·event ID로 재평가하고,
결과 불명은 새 쓰기 전에 해당 command 또는 purchase grant의 존재를 조회한다. 재조회에도 결과를
확정할 record가 없으면 차감을 성공으로 추정하지 않고 `reconciliationRequired`로 닫는다.

현재 월 allowance가 없는 Shield 무료 예약은 quota 2 allowance, `free:{monthID}` 지급 event,
`reserve:{commandID}` 예약 event와 release command를 같은 modify에 포함한다. 동시 생성에서 진 기기는
서버 allowance와 free grant를 다시 읽고 지급 event를 중복 생성하지 않는다.

**근거**: mutable balance만 저장하거나 retry마다 새 event ID를 만들면 다기기 충돌에서 초과 사용과
중복 감사 기록이 생긴다. timeout을 실패로 단정해 즉시 재시도하면 이미 성공한 차감을 다시 적용할
수 있으므로, 동일 ID의 서버 결과를 먼저 확인하는 fail-closed 경계가 필요하다.

**영향 범위**: `CloudKitCoinLedgerRepository`, `CoinLedgerCloudDatabase` adapter와 후속
`RuleReleaseService`, StoreKit 지급·재조정 흐름에 적용한다.

## DEC-084 — 코인 장부 current의 비영속 monotonic 세션과 계정 격리

**날짜**: 2026-09-02

**결정**: 코인 장부의 `current` 권한은 현재 프로세스에서 성공한 초기 fetch 시각을
`ContinuousClock.Instant`로만 보관하는 `CoinLedgerSyncSession`으로 판정한다. 성공 fetch 이후 정확히
300초까지 허용하고 300초를 넘거나 프로세스가 재시작되면 새 fetch 전까지 허용하지 않는다.
wall-clock `CoinBalanceSnapshot.syncedAt`은 표시·진단에만 사용한다. iCloud 계정 가용성, confirmed
mirror, `LedgerEpoch`와 계정 epoch 일치, 완료된 projection, pending reconciliation 부재도 모두
동시에 만족해야 한다.

계정 session ID가 바뀌면 이전 mirror·freshness·pending local change를 즉시 폐기한다. 새 계정의
초기 fetch 호출에 이전 계정 local mirror가 전달되더라도 참고 잔액으로 사용하지 않는다. 성공한
원격 fetch에서 장부가 있으면 로컬 빈 설치보다 원격 projection을 우선하고, 장부가 없으면 삭제 증거가
없는 경우 `setupRequired`, 삭제가 확인된 경우에만 `deletionConfirmed`로 분류한다. network·계정
불확실성은 `unavailable`이며 삭제 증거로 승격하지 않는다.

**근거**: 영속 wall-clock 시각은 기기 시간 변경과 프로세스 재시작 뒤에도 오래된 잔액에 권한을
부여할 수 있다. 계정 전환 중 이전 mirror를 재사용하면 다른 iCloud 계정의 유료 잔액이 노출되거나
사용될 수 있다. 원격 부재와 통신 실패를 분리해야 삭제된 장부를 자동 복원하거나 최초 사용자에게
잘못된 reset을 요구하는 일을 막을 수 있다.

**영향 범위**: `CoinLedgerSyncAdapter`, `CoinLedgerCurrentGate`, 후속 구매·해제 승인 gate와 T071의
CloudKit zone 삭제 증거 분류에 적용한다.

## DEC-085 — 월간 무료분 생성 경계와 foreground 복구 격리

**날짜**: 2026-09-02

**결정**: 기존 current 장부의 새달 무료분은 앱 foreground에서 월 레코드가 없을 때만 지연 생성한다.
이 동작은 제한 일정·위치·Shield 복구와 같은 `AppLifecycleCoordinator.restore()`에서 실행하지만,
iCloud 쓰기 실패는 `.monthlyAllowance`로 보고하고 기존 제한 복구를 중단하지 않는다. `setupRequired`의
최초 장부 생성과 삭제 후 reset 장부 생성은 T072의 명시적 사용자 확인 service가 담당한다.

Shield의 무료 해제는 allowance를 별도로 먼저 생성하지 않고 `CoinLedgerRepository.reserveMonthlyFree`에
위임해 allowance·free grant·reservation·command를 하나의 원자 명령으로 저장한다. 공통
`MonthlyAllowanceService`는 app과 Shield가 같은 current epoch gate를 사용하도록 하고,
`DependencyContainer`는 repository와 foreground 동기화 context provider를 주입받아 조립한다.

**근거**: 월 레코드 생성 실패가 기존 Screen Time 제한 복구까지 막으면 코인 부가기능 장애가 핵심
제한 기능을 훼손한다. 반대로 Shield가 생성과 예약을 두 번의 쓰기로 나누면 지급만 확인되고 예약은
실패하는 부분 상태가 생긴다. 최초·reset 장부는 고지와 사용자 확인이 필요한 별도 제품 흐름이므로
일반 foreground 지연 생성에서 자동 처리하지 않는다.

**영향 범위**: `MonthlyAllowancePolicy`, `MonthlyAllowanceService`, `AppLifecycleCoordinator`,
`DependencyContainer`와 T072 초기 설정 service에 적용한다.

## DEC-088 — claim 예약의 epoch CAS와 기본 거부 호환성 경계

**날짜**: 2026-09-04

**결정**: T047b의 무료·구매 예약은 공통 내부 경로에서 최신 epoch·allowance·account·command·event·
claim을 조회한다. claim 획득, 잔액 reservation, command·event와 읽은 epoch의 change tag를 같은
atomic modify에 포함한다. 구매 fallback은 소진된 allowance도 CAS해 다른 요청의 보상으로 무료분이
복구되면 충돌 재시도에서 무료분을 우선한다. epoch 교체는 기존 요청의 CAS 또는 재조회에서 거부한다.

`verifyReservationCompatibility(epochID)`는 현재 장부 freshness와 별개인 호환성 주입 경계다.
기본값은 false로 새 예약을 거부하며 이번 구현에는 운영 환경에서 true를 반환하는 provider를 넣지
않는다. 격리된 database fake에서만 명시적으로 허용한다. 이 closure 자체가 구버전 writer를
탐지하거나 원격 migration을 완료한 것은 아니다. 실제 활성화 전 구버전 writer 부재·기존 command
전환을 검증한 provider가 필요하며, T047c도 임의로 true를 주입해서는 안 된다.

같은 command의 표면 간 재시도는 최초 `requestedFrom`을 보존한다. command가 존재하더라도 claim·
reservation event가 없거나 소유자가 불일치하면 새 예약이나 성공 응답 대신 재조정으로 보낸다.
결과 불명 예약은 동일 record 집합을 재조회해 확인된 잔액만 반환하고, 재조회 실패도
`reconciliationRequired`로 남긴다. applied·commit·보상 쓰기도 epoch·현재 소유권을 CAS하며,
보상 완료 command의 재호출은 새 owner를 수정하지 않는다.

**근거**: claim만 저장하면 장부 reset과 경쟁할 수 있고, 구매 잔액만 CAS하면 충돌 중 복구된 무료분을
건너뛸 수 있다. 호환성을 record 부재에서 추정하거나 기존 테스트의 허용 값을 운영 조립에 사용하면
구버전 writer의 중복 예약 위험이 재발한다.

**영향 범위**: `CloudKitCoinLedgerRepository`, 실제 repository를 사용하는 공유 CAS database fake,
후속 T047c 서비스 및 운영 장부 활성화·migration 검증. 원격 쓰기·schema 배포·데이터 삭제는 없다.

## DEC-087 — occurrence 소유권과 해제 명령 멱등성 분리

**날짜**: 2026-09-04

**상태**: 승인됨 — BLK-015에 대한 사용자 승인

**결정**: 같은 epoch·occurrence의 해제 요청은 `ReleaseOccurrenceClaim` 하나를 공유한다.
새 record type의 schema version은 1이며 기존 여섯 record type의 필드와 version은 변경하지 않는다.
record ID는 `release-claim:{소문자 epoch UUID}:{occurrenceID UTF-8 SHA-256 소문자 hex}`다.
해시를 사용해 record name 길이를 고정하고, payload의 원래 occurrence·epoch를 읽기 때 다시 검사한다.
이는 식별자 구성이지 민감 정보를 익명화하는 보안 경계가 아니다.

claim은 `held | released`와 소유 command ID를 갖는다. 무료·구매 reservation과 `held` 획득은 같은
CAS atomic modify로 처리하고, committed·결과 불명에서는 held를 유지한다. 잔액 보상·command의
compensated 확정과 released 전환도 같은 modify로 처리한다. released record는 삭제하지 않고 기존
change tag를 사용해 새 소유자를 기록하므로 이전 소유자의 지연 응답이 새 소유권을 지울 수 없다.
시간 경과만으로 소유권을 해제하지 않는다. command ID는 시도별로 만들고 재시도에는 유지하며,
requestedFrom은 최초 감사 정보를 보존한다.

**대안**: occurrence에서 command ID 하나만 파생하는 방식은 보상 완료 후 새 시도와 감사 이력을
혼합한다. 프로세스 내 Set·actor만 사용하는 방식은 앱·extension·다기기 공통 배타성을 제공하지 않는다.

**호환·출시 조건**: T047a는 모델·codec 기반만 추가하며 원격 쓰기나 운영 schema 배포를 하지 않는다.
새 record type을 모르는 구버전 codec은 이를 거부하지만, 구버전 writer가 claim을 무시하는 경우까지
차단한다고 간주하지 않는다. claim 없는 기존 진행·완료 command가 있는 장부와 구버전 writer 공존은
검증된 전환 절차 전에는 새 예약을 허용하지 않는 fail-closed 연결이 T047b에 필요하다.
기존 잔액·command 삭제나 자동 reset으로 migration하지 않는다. 원격 데이터·배포 상태 확인과
혼합 버전 안전성 검증은 실제 코인 해제 활성화 전 필수이며, 기존 schema 1 읽기 자체는 유지한다.

**영향 범위**: 공유 해제 모델·record ID·mapper, CloudKit 예약·보상 repository, T047 서비스와
database fake 통합 테스트. T047a→T047b→T047c 순으로 구현하고 전체 연결 전 T047은 미완료로 둔다.

## DEC-090 — 명령별 예외 수정·보상 계약 보강 승인

**날짜**: 2026-09-04

**상태**: 승인됨 — BLK-016 사용자 승인

**결정**: 전체 목록 교체 대신 명령별 원자 추가·조건부 제거를 해제 흐름에 사용한다. 같은 내용의
추가는 멱등이며 command 또는 occurrence가 기존 다른 내용과 충돌하면 덮지 않는다. 제거는
command ID와 occurrence ID가 모두 일치할 때만 수행한다. 두 연산은 최신 파일 조회부터 atomic
교체까지 기존 파일 조정 경계를 공유하고 다른 항목을 보존한다. 기존 schema 1과 파일명은 유지한다.
충돌은 명시적 `conflict` 오류이며 기존 안정 write failure 코드에 대응한다.

**근거·대안**: 전체 과거 목록 복원은 다른 성공 명령을 지울 수 있다. actor 또는 파일 교체만의
직렬화는 분리된 load→save를 안전한 병합으로 만들지 못한다. 명령별 수정은 필요한 항목만 변경한다.

**영향 범위**: T049a에서 저장 protocol·두 facade·파일 store·관련 테스트를 보강하고 T049b에서
coordinator와 보상을 연결한다. 수정 결과 snapshot만으로 제한 적용까지 직렬화됐다고 간주하지
않으며 T049b는 최신 상태 재평가와 적용 경합을 검증해야 한다. 저장소는 제거된 명령의 이력을
보관하지 않으므로 지연 재시도의 원격 상태 판정은 coordinator·reconciler가 담당한다.
원격 데이터 삭제·schema 배포·운영 활성화는 수행하지 않는다.

## DEC-089 — 해제 예외 정리의 공유 파일 조정 경계

**날짜**: 2026-09-04

**결정**: T048의 `AppGroupReleaseExceptionRepository`와 기존 `SharedSnapshotRepository`는
`ReleaseExceptionFileStore`를 공유한다. schema 1·기존 파일명·ISO8601·보호된 atomic write는 유지한다.
`NSFileCoordinator`로 모든 예외 파일 접근을 조정하며 정리의 읽기·필터·저장을 하나의 동기 접근
블록으로 수행한다. coordinator 블록 안에서는 await하지 않는다. 전용 facade는 읽기·쓰기 실패를
기존 안정 오류 코드로 전달하고, 공통 snapshot facade의 schema 오류 경계는 유지한다.

**근거**: atomic 파일 교체만으로는 서로 다른 repository instance의 정리가 중간에 저장된 최신
예외를 덮는 읽기·쓰기 경합을 막지 못한다. actor만 추가하는 대안도 다른 instance·프로세스를
직렬화하지 못한다. 두 facade가 같은 조정 경계를 사용해 기존 쓰기 경로의 우회를 방지한다.

**정리 기준**: 전체 저장 규칙 revision 사전을 받아 만료·삭제 규칙·revision 불일치만 영속 정리한다.
일시적 위치 이탈 등으로 inactive가 된 예외와 미래 effectiveAt 예외는 적용하지 않되 만료 전에는
보존한다. 정리가 필요 없으면 파일을 다시 쓰지 않는다. decode·정리 쓰기 실패는 빈 상태로 숨기거나
파일을 삭제하지 않는다.

**범위와 한계**: 새 스키마·migration은 없다. 전체 collection 저장 API는 병합·CAS가 아니므로
별도 load→save를 원자적 수정으로 간주하지 않는다. 후속 coordinator의 명령별 수정·보상 연결과
실제 앱/extension 중단·재부팅·잠금 인수는 별도 검증한다. T048은 같은 프로세스의 독립 instance
50회 경합을 확인했으며 실기기 교차 프로세스 검증 완료를 주장하지 않는다.

## DEC-086 — Shield Action의 Live Activity 조정은 foreground fallback 사용

**날짜**: 2026-09-04

**상태**: 승인됨

**결정**: Shield Action extension의 production 해제 흐름에는 메인 앱이 만든 Live Activity를 직접
조회·갱신·종료하는 adapter를 연결하지 않는다. 코인 해제가 성공하면 iOS 26.5 이상은
`openParentalControlsApp`으로 앱을 열어 foreground coordinator가 대표 활동을 재조정하고,
iOS 26.0~26.4는 다음 앱 foreground에서 재조정한다. DEBUG feasibility probe와 결과 exporter는 출시
binary에서 제외한다.

**근거**: iPhone 17 iOS 26.6.1(23G83) 실기기에서 메인 앱의 Live Activity가 표시된 상태로 Shield
primary action을 실행했지만 `Activity<RestrictionLiveActivityAttributes>.activities`가 빈 배열을
반환했다. probe 결과는 `unsupported`, `activityFound=false`, `updateVerified=false`,
`endRequested=false`로 기록됐다. framework API의 컴파일 가능성만으로 서로 다른 process의 활동
열거 가능성을 보장할 수 없으므로, 재현되지 않은 직접 조정 경로를 유료 재화 해제 흐름에 넣지 않는다.

**영향 범위**: `ActivityKitFeasibilityProbe`, `ShieldActionExtension`, T055의 Live Activity 조정 분기,
T096 실기기 회귀와 `quickstart.md`의 Shield 선행 게이트에 적용한다.
