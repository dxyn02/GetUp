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

## DEC-003 — iOS target 및 target 구성

**날짜**: 2026-08-20

**상태**: 2026-08-21에 `DEC-014`로 대체됨

**결정**: iOS 17 이상, Swift 6.3 및 SwiftUI를 target으로 한다. 단일 Xcode project에서 하나의
app target과 Device Activity Monitor, Shield Configuration, Shield Action extension을 사용한다.

**근거**: iOS 17은 전체 deployment 범위에서 Observation을 제공한다. 각 extension은 앱이 닫힌
상태의 일정 처리와 제한 앱 shield 동작에 필요한 시스템 실행 지점이다.

## DEC-004 — 보호된 공유 snapshot 저장소

**날짜**: 2026-08-20

**상태**: 단일 규칙 payload 범위는 2026-08-21에 `DEC-015`·`DEC-016`으로 대체됨. 보호된 App Group
JSON, atomic replacement 및 파일 보호 원칙은 유지됨.

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
