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

**결정**: iOS 17 이상, Swift 6.3 및 SwiftUI를 target으로 한다. 단일 Xcode project에서 하나의
app target과 Device Activity Monitor, Shield Configuration, Shield Action extension을 사용한다.

**근거**: iOS 17은 전체 deployment 범위에서 Observation을 제공한다. 각 extension은 앱이 닫힌
상태의 일정 처리와 제한 앱 shield 동작에 필요한 시스템 실행 지점이다.

## DEC-004 — 보호된 공유 snapshot 저장소

**날짜**: 2026-08-20

**결정**: 단일 규칙과 최신 위치 조건을 별도의 versioned Codable JSON 파일로 App Group container에
저장한다. 공통 App Group identifier는 `group.com.getup.GetUp`으로 정의하고 앱과 세 Screen Time
확장이 동일하게 상속한다. atomic replacement와 첫 잠금 해제까지의 파일 보호를 사용한다.

**근거**: MVP는 작은 aggregate 두 개만 저장하므로 database가 필요하지 않다. 분리된 single-writer
파일은 위치 데이터를 보호하고 extension의 읽기를 허용하면서 process 간 쓰기 충돌을 줄인다.

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
