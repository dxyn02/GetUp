# Implementation Plan: 시간·위치 기반 앱 사용 제한

**Branch**: `001-location-app-restriction` | **Date**: 2026-08-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-location-app-restriction/spec.md`

**Status**: Phase 1 design과 task 생성·교차 산출물 보완 완료; 재분석 준비됨.

## Summary

사용자가 직접 설정한 요일·시간대와 500m, 1km, 2km, 3km, 4km 또는 5km 위치 조건이 모두 충족될 때 선택 앱에
시스템 제한 화면을 적용하는 로컬 iOS 앱을 구현한다. 메인 앱은 설정·권한·위치 상태를 관리하고,
시스템 일정 확장은 앱이 열려 있지 않을 때 시간 이벤트를 처리하며, 제한 화면 확장은 선택 앱
접근을 차단한다. 여러 독립 규칙, 재사용 가능한 저장 장소와 최근의 신뢰 가능한 위치 판정은 앱과
확장이 공유하는 보호된 저장소에 보관한다.

Phase 0에서 발견한 최소 일정 길이와 플랫폼 이벤트 지연은 `DEC-001`, `DEC-002`로 해결했다.
Phase 1 산출물은 여러 규칙 aggregate, 저장 장소 collection, 순수 제한 상태 머신, 보호된 공유
저장 계약, 시스템 이벤트 및 shield UI 계약으로 갱신한다.

## Technical Context

**Language/Version**: Swift 6.3, Xcode 26.6

**Primary Dependencies**: SwiftUI, Observation, MapKit, FamilyControls, ManagedSettings,
ManagedSettingsUI, DeviceActivity, CoreLocation, Foundation; 외부 패키지 없음

**Storage**: App Group 공유 컨테이너의 버전이 있는 Codable JSON 스냅샷과 파일 보호;
재생성 가능한 소규모 운영 표식만 공유 UserDefaults 사용

**Testing**: Swift Testing 기반 도메인·저장소 테스트, XCTest 기반 UI·성능·시스템 통합 테스트,
실기기 위치·권한·재부팅 인수 테스트, SC-001·SC-007을 측정하는 사용자 사용성 평가

**Target Platform**: iPhone, iOS 26 이상; 실제 제한·위치·재부팅 검증에는 물리 기기 필요

**Project Type**: SwiftUI iOS 앱 + Device Activity Monitor, Shield Configuration,
Shield Action 확장

**Performance Goals**: 사용성 평가 참여자의 90% 이상이 설정을 3분 이내 완료하고 85% 이상이
상태·복구 방법을 첫 시도에 이해한다. 신뢰 가능한 플랫폼 이벤트 확인 뒤 제한 상태 조정은
30초 이내로 하며, 자동 계측에서 활성화 경로의 p95와 해제 경로 전체 통과율을 기록한다.
물리적 경계 통과부터 이벤트 전달까지는 별도로 관찰하고 기록한다.

**Constraints**: 완전 로컬 동작, 여러 독립 규칙, 직접 시간 입력, 500m/1km/2km/3km/4km/5km 반경, Always 및 Full Accuracy
위치 권한, 개인용 Family Controls 승인, App Group, Family Controls 배포 entitlement 필요;
Core Location region monitoring과 event 시점의 단발성 위치 확인을 사용하며 지속적인 background
location update나 일반 background processing을 사용하지 않는다. 재부팅 후 첫 잠금 해제 전에는
위치 모니터링이 불가능하다.

**Scale/Scope**: 기기 소유자 1명, 여러 규칙과 저장 장소, 규칙별 선택 요일 최대 7개와 원형 위치
조건 1개, 운영체제가 허용하는 선택 앱 토큰 집합, 외부 계정·서버·동기화 없음

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-Research Check | Evidence / Required Action |
|-----------|--------------------|----------------------------|
| I. Specification-Driven Implementation | PASS | `FR-031`, 수정된 `SC-002`, `SC-004`, `SC-008`이 최소 15분, event 확인 기준, 첫 잠금 해제 복구 경계를 명시한다. |
| II. Core Business Logic Testing | PASS | 시간·요일·자정·위치 오차·상태 전이를 순수 도메인 로직으로 분리하고 매개변수화 테스트를 계획한다. |
| III. Structural Change Documentation | PASS | `research.md`, `data-model.md`, `contracts/`, `quickstart.md`와 `docs/DECISIONS.md`에 구조 결정을 기록한다. Phase 1 산출물은 blocker 해결 후 생성한다. |
| IV. Pre-Completion Test Gate | PASS | 구현 task 완료 전 관련 Swift Testing/XCTest 및 실기기 인수 시나리오 실행을 필수로 둔다. |

**Pre-design gate result**: PASS after `BLK-001`, `BLK-002` resolution on 2026-08-20.

**Post-design re-check**: PASS.

- 각 spec 요구사항은 데이터 모델, 상태 평가 계약, 플랫폼 이벤트 계약 또는 shield UI 계약으로
  추적 가능하다.
- 핵심 시간·요일·규칙 validation·위치·권한·상태 전이는 Swift Testing의 결정론적
  매개변수화 테스트 대상이다.
- 앱과 세 확장, 공유 파일 및 이벤트 책임은 `research.md`, `data-model.md`, `contracts/`에
  문서화했다.
- `quickstart.md`는 자동 테스트와 실기기 인수 결과가 없으면 완료로 표시하지 못하도록 규정한다.

## Project Structure

### Documentation (this feature)

```text
specs/001-location-app-restriction/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
└── tasks.md             # $speckit-tasks에서 생성
```

### Source Code (repository root)

```text
GetUp.xcodeproj/
GetUp/
├── App/
├── Features/
│   ├── RuleEditor/
│   ├── LocationPicker/
│   ├── PermissionGuide/
│   └── RestrictionStatus/
├── Core/
│   ├── Models/
│   ├── Evaluation/
│   ├── StateMachine/
│   └── Contracts/
├── Infrastructure/
│   ├── Persistence/
│   ├── Location/
│   ├── ScreenTime/
│   └── Scheduling/
└── Resources/

GetUpDeviceActivityMonitor/
GetUpShieldConfiguration/
GetUpShieldAction/

GetUpTests/
├── Core/
├── Persistence/
└── Integration/

GetUpUITests/

design/
├── low-fidelity/
└── high-fidelity/

docs/
├── ENTITLEMENTS.md
├── USABILITY_TEST_PLAN.md
└── USABILITY_TEST_RESULTS.md
```

**Structure Decision**: 하나의 Xcode 프로젝트 안에서 메인 앱과 세 확장 타깃을 구성한다. 앱과
확장이 함께 사용하는 모델·판정·저장 계약은 `GetUp/Core`의 타깃 공유 소스로 유지한다. 별도
서버나 외부 아키텍처 패키지는 도입하지 않는다. Shield Action은 제한 화면 버튼의 닫기 동작을
명시적으로 처리하기 위해 포함한다. 모든 SwiftUI 화면은 `design/low-fidelity/`의 로우파이와
`design/high-fidelity/`의 하이파이가 검토된 후 구현한다.

## Complexity Tracking

현재 헌법 위반을 정당화하기 위한 추가 구조는 없다. 네 타깃은 iOS가 앱 비실행 상태 일정 처리와
시스템 제한 화면 사용자화를 각각 별도 확장 지점으로 제공하기 때문에 필요하다.
