# 프로젝트 상태

## 현재 기능
001-location-app-restriction, 002-live-activity-coins

## 현재 단계
001은 Phase 7 마무리 및 교차 관심사 진행 중, 002는 Phase 4 사용자 스토리 2 구현 진행 중

## 진행 중
`codex/shield-activitykit-probe`에서 002-live-activity-coins T039를 완료했다. iOS 26.6.1 실기기의
Shield Action extension은 메인 앱이 만든 Live Activity를 직접 열거하지 못해 `unsupported`로
확정했다. T055에는 직접 ActivityKit 조정을 연결하지 않고 iOS 26.5 이상 앱 진입 후 foreground,
iOS 26.0~26.4 다음 foreground 재조정을 사용한다.
001의 T083·T085 실기기 후속 확인은 여전히 남아 있음

## 마지막 완료 작업
T039 — Shield Action의 앱 생성 Live Activity 직접 조정이 실기기에서 미지원임을 확정함

## 다음 작업
T040 — 코인 reservation·해제 상태 머신의 정상·경계·실패 테스트를 먼저 작성한다.
001은 T083·T085 실기기 재검증과 T086 구현·하이파이 편차 대조가 남아 있음

## 차단 상태
BLK-014·BLK-013·BLK-012 해결됨. BLK-010은 `com.dxyn02.GetUp` namespace의 네 App ID 등록과
`group.com.dxyn02.GetUp` 할당, Family Controls Distribution `Assigned`와 갱신 profile을 사용한
실기기 설치·실행은 사용자 확인됐으며, extension별 서명 entitlement와 archive 증적이 추가로 필요함.

## 계획 갱신 필요
없음. Phase 0·Phase 1과 `002-live-activity-coins/tasks.md`를 DEC-077·DEC-078과 최신 명세에 맞게
재동기화했다. 001의 Apple
`intervalDidStart`·`intervalDidEnd` 전달은 물리적 시작·종료 정각이 아니라 해당 구간에서
기기를 사용할 때일 수 있다. callback 전달 이후 시작 적용은 T118, 마지막 활성 규칙 해제는 T114에서
동기화했으며, 기기가 사용되지 않는 동안의 정각 callback은 제품이 보장하지 않는다.

## 테스트 상태
2026-09-04 002 구현 T039를 완료했다. `ActivityKitFeasibilityProbe.swift`를 Shield Action target에
연결하고 `#if DEBUG`로 격리해 success·unsupported·failure·timeout과 조회·갱신·종료 단계를 App Group에
기록했다. iPhone 17 iOS 26.6.1(23G83)에서 메인 앱의 Live Activity 표시 후 제한 앱 Shield primary
action을 실행한 결과 extension의 `Activity<RestrictionLiveActivityAttributes>.activities`는 활동을
찾지 못했고 `unsupported`, `activityFound=false`, `updateVerified=false`, `endRequested=false`로
기록됐다. 따라서 T055 production에는 직접 ActivityKit adapter를 연결하지 않고 iOS 26.5 이상 앱 진입
후 foreground 재조정, iOS 26.0~26.4 다음 foreground 재조정을 사용한다. generic iOS Simulator
Debug·Release 빌드와 `ShieldActionResponsePolicyTests` 2개가 실패·skip 없이 통과했고, Debug binary의
probe 표식 6건·Release 앱·extension binary 0건, iOS 26.6.1 실기기 Debug 서명 빌드·설치·실행도
확인했다. 기존
XCTest binary strip 및 signed extension strip 경고는 변동 없이 남아 있다.

2026-09-04 002 구현 T038을 완료했다. `RestrictionOccurrenceEvaluator`, Live Activity content·time
policy, coordinator·system adapter와 관련 테스트 7개, Widget bundle·UI·preview, 공유 model 2개,
Widget String Catalog가 각각 앱·`GetUpTests`·`GetUpLiveActivity` target의 올바른 Sources·Resources
phase에 연결됐음을 최종 대조했다. iPhone 17 Pro iOS 26.5 Simulator의
`LiveActivityCoordinatorTests` 9개를 실패·skip 없이 통과시켰다. 코드 서명 없는 generic iOS
Simulator Debug·Release `GetUp` scheme 빌드가 모두 통과했고, 두 구성의 앱 내부
`GetUpLiveActivity.appex`에서 실행 파일·영문 문자열 리소스·`com.apple.widgetkit-extension` 식별자를
확인했다. target membership 누락이 없어 `project.pbxproj` 추가 변경은 필요하지 않았다. 기존 XCTest
binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다. 다음 T039는 지원 OS 실기기에서 수행하는
Shield Action ActivityKit feasibility gate다.

2026-09-04 002 구현 T037을 완료했다. Live Activity의 visible 거리·확인 불가·추가 제한 문구와
VoiceOver용 규칙명·남은 시간·남은 거리·다중 제한 설명을 한국어 source language와 영어 번역으로
앱 및 Widget String Catalog에 추가했다. `RestrictionRuleLabel`, `RestrictionCountdown`,
`RestrictionDistanceLabel`, `AdditionalRestrictionsLabel`은 각각 명시적인 접근성 label/value를
제공하고 장식 SF Symbol은 접근성 트리에서 숨긴다. Widget String Catalog를 extension resource에
연결했으며 빌드된 `GetUpLiveActivity.appex/en.lproj/Localizable.strings`에서 8개 번역과 `%lld`·`%@`
보간 형식을 확인했다. iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 352개(동적 인자 실행
포함 395회)를 실패·skip 없이 통과시켰고, 앱과 네 extension의 코드 서명 없는 generic iOS
Simulator Debug·Release 빌드, 두 catalog JSON parse, project plist와 `git diff --check`도 통과했다.
T038에는 US1 전체 source·resource membership과 coordinator·Widget Extension의 최종 회귀 검증이
남아 있다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T036을 완료했다. 빈 extension bootstrap을 실제 `WidgetBundle`로 교체하고,
`RestrictionLiveActivity`를 `ActivityConfiguration`에 연결했다. Lock Screen은 규칙명·종료 카운트다운·
known 또는 확인 불가 거리·추가 제한을 한 화면에 표시하며, Dynamic Island expanded는 같은 정보를
영역별로 나누고 compact·minimal은 공간에 맞춰 거리와 카운트다운을 우선한다. 동적 timer 구간은
`Date.now...max(Date.now, endsAt)`으로 구성해 종료 후 0에 머물고 Activity update를 초마다 만들지
않는다. T027의 deterministic known·unavailable·다중 규칙 fixture를 Lock Screen과 Dynamic Island
minimal·compact·expanded `#Preview`에 연결했다. iPhone 17 Pro iOS 26.5 Simulator의 전체
`GetUpTests` 352개(동적 인자 실행 포함 395회)를 실패·skip 없이 통과시켰고, 앱과 네 extension의
코드 서명 없는 generic iOS Simulator Debug·Release 빌드, project plist와 `git diff --check`도
통과했다. 첫 일반 빌드는 sandbox의 CoreSimulatorService 접근 제한으로 실패했으나 허용된 호스트
환경에서 같은 빌드를 재실행해 통과했다. `RestrictionLiveActivity.swift`의 source membership은
컴파일 검증에 필요한 범위로 연결했으며 T037 resource를 포함한 최종 membership 검증은 T038에 남아
있다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T035를 완료했다. `SharedSnapshotRepository`는 App Group의 위치 근거 중 현재
활성 규칙과 revision이 정확히 일치하는 항목만 foreground handoff로 반환한다.
`AppLifecycleCoordinator`는 위치 monitor가 `.restoration` 근거로 덮어쓰기 전에 이 handoff를 읽고,
관측 후 0초 이상 5분 이내의 `.regionEvent`는 그대로 Live Activity 조정에 전달하며 5분 초과·미래
근거는 foreground 위치 갱신으로 대체한다. extension 경로는 공유 저장소까지만 사용하고 ActivityKit은
호출하지 않는다. 저장소 API 부재 compile RED를 확인한 뒤 handoff 대상 테스트 27개와 extension
통합 테스트 2개, iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 352개(동적 인자 실행 포함
395회)를 실패·skip 없이 통과시켰다. 앱과 네 extension의 코드 서명 없는 generic iOS Simulator
빌드도 통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T034를 완료했다. `AppLifecycleCoordinator`는 일정·위치·월 allowance·제한 상태
복구가 끝난 뒤에만 Live Activity 조정 closure를 실행하며, 조정 준비 오류를 `.liveActivity`로
보고하되 기존 제한 복구 결과와 presentation state를 유지한다. `AppEnvironment.live()`는 앱 타깃의
`SystemLiveActivityAdapter`와 `LiveActivityCoordinator`를 조립하고, App Group의 활성 occurrence·
현재 규칙 revision·저장 장소·위치 근거로 대표 snapshot을 만든다. 규칙명이 없으면 정규화한 장소명을
사용하고, 현재 revision의 대표가 없으면 nil을 전달해 기존 활동을 종료하며, 5분 이내 `.inside`
근거만 기존 거리 policy를 통해 표시한다. 복구 순서·실패 격리·대표 snapshot 테스트 3개를 먼저
추가해 미구현 compile RED를 확인한 뒤 대상 테스트 10개와 iPhone 17 Pro iOS 26.5 Simulator의 전체
`GetUpTests` 349개(동적 인자 실행 포함 392회)를 실패·skip 없이 통과시켰다. 앱과 네 extension의
코드 서명 없는 generic iOS Simulator 빌드, project plist와 `git diff --check`도 통과했다. 첫 일반
빌드는 sandbox의 CoreSimulatorService 접근 제한으로 실패했으나 허용된 호스트 환경에서 같은 명령을
재실행해 통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T032를 완료했다. `SystemLiveActivityAdapter.live()`는
`ActivityAuthorizationInfo.areActivitiesEnabled`와
`Activity<RestrictionLiveActivityAttributes>.activities`를 도메인 권한·snapshot으로 변환하고,
`ActivityContent`의 stale 시각을 제한 종료 시각으로 지정해 로컬 request와 기존 활동 update를
수행한다. 종료는 최종 content state와 `.immediate` dismissal을 사용한다. 각 mutation은 실제
ActivityKit 활동을 attributes의 안정 `activityID`로 찾고 framework 상세 오류를
`requestFailed`·`updateFailed`·`endFailed`로 정규화한다. 주입 가능한 system-call 경계의 권한·활동
조회, payload 전달, 동작별 오류 변환 테스트 3개를 먼저 추가해 adapter 타입 부재 compile RED를
확인한 뒤 green으로 전환했다. iPhone 17 Pro iOS 26.5 Simulator에서 대상 테스트 3개와 전체
`GetUpTests` 346개(동적 인자 실행 포함 389회)가 실패·skip 없이 통과했고, 앱과 네 extension의 코드
서명 없는 generic iOS Simulator 빌드, project plist와 `git diff --check`도 통과했다. 첫 일반 빌드는
sandbox의 CoreSimulatorService 접근 제한으로 실패했으나 허용된 호스트 환경에서 같은 명령을
재실행해 통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T031을 완료했다. `DeviceActivityIntervalStartHandler`와 마지막 활성 규칙의
`DeviceActivityIntervalEndHandler`는 Shield read-back·공유 적용 상태 저장 직후 App Group의
`active-restrictions.json`을 같은 동기 callback 안에서 atomic write한다. foreground coordinator와
공통 `ActiveRestrictionSnapshotPolicy`를 사용해 occurrence ID·최초 `activatedAt`·snapshot revision
규칙을 동일하게 유지한다. 겹친 활성 규칙의 종료와 occurrence 저장 실패는 동기 성공으로 오인하지
않고 기존 `RestrictionCoordinator` 재평가 경로로 넘기며, Device Activity extension은 ActivityKit을
import하거나 직접 호출하지 않는다. 시작·종료 저장 테스트 2개를 먼저 추가해 새 주입 경계 미구현
compile RED를 확인한 뒤 대상 테스트 34개와 iPhone 17 Pro iOS 26.5 Simulator의 전체
`GetUpTests` 343개(동적 인자 실행 포함 386회)를 실패·skip 없이 통과시켰다. 앱과 네 extension의
코드 서명 없는 generic iOS Simulator 빌드와 `git diff --check`도 통과했다. 첫 일반 빌드는 sandbox의
CoreSimulatorService 접근 제한으로 실패했으나 허용된 호스트 환경에서 같은 명령을 재실행해
통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T030을 완료했다. `RestrictionCoordinator`는 제한 적용·제거 뒤 실제 adapter
read-back과 현재 규칙을 교차 확인하고, 기존 `ScheduleEvaluator`가 계산한 DST 대응 활성 구간으로
`RestrictionOccurrence`를 생성해 App Group repository에 저장한다. 규칙 입력 순서와 무관하게
`activatedAt`·`startAt`·`ruleID` 순으로 정렬하며, 동일 ID 재평가에서는 최초 `activatedAt`과 snapshot
revision을 보존하고 활성 집합 변경에서만 revision을 증가시킨다. 적용 구간·재평가·마지막 규칙 제거
테스트 3개를 먼저 추가해 persistence dependency 미구현 compile RED를 확인한 뒤 green으로 전환했다.
coordinator·일정 대상 테스트 19개와 iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 341개
(동적 인자 실행 포함 384회), 앱과 네 extension의 코드 서명 없는 generic iOS 빌드, project plist와
`git diff --check`가 실패·skip 없이 통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는
변동 없이 남아 있다.

2026-09-03 002 구현 T027을 완료했다. `RestrictionLiveActivityPreviewFixtures`는 고정 시각과 ID를
사용해 Lock Screen·Dynamic Island minimal·compact·expanded 네 표면에 known·unavailable·다중 규칙
세 상태를 조합한 12개 `Scenario`를 제공한다. 실제 `#Preview`와 표시 UI는 계획된 T036에서 이 fixture를
사용한다. 앱과 네 extension의 코드 서명 없는 generic iOS 빌드, iPhone 17 Pro iOS 26.5 Simulator의
전체 `GetUpTests` 338개(동적 인자 실행 포함 381회), project plist와 `git diff --check`가 실패·skip
없이 통과했다. 첫 sandbox 빌드는 CoreSimulatorService 접근 제한으로 실패했지만 같은 명령을 허용된
호스트 환경에서 재실행해 통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이
남아 있다.

2026-09-03 002 구현 T026을 완료했다. `LiveActivityLocationBridgeTests`는 메인 앱이 신뢰 가능한
`.inside` 위치를 받은 시점부터 `LiveActivityContentPolicy`와 foreground coordinator가 기존 activity의
거리를 `known(300m)`로 갱신한 시점까지 30초 이내임을 검증한다. extension-only 경로는 공용
`SharedSnapshotRepository`에 위치 근거를 저장하는 동안 ActivityKit 호출이 0건임을 확인하고, 다음
foreground에서 저장 근거를 읽어 조정 가능해진 시점부터 같은 거리 반영까지를 별도 기산점으로
측정한다. 실제 AppLifecycle 연결은 계획된 T035에서 이 계약에 맞게 구현한다. 대상 테스트 2개와
iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 338개(동적 인자 실행 포함 381회)가 실패·skip
없이 통과했고, 앱과 네 extension의 코드 서명 없는 generic iOS 빌드, project plist와
`git diff --check`도 통과했다. 기존 XCTest binary strip 및 불필요한 `try` 경고는 변동 없이 남아 있다.

2026-09-03 002 구현 T025를 완료했다. `LiveActivityStartMeasurementTests`는 Live Activity 지원·권한
허용·유효한 활성 제한·foreground 조건을 만족하는 100회만 적격 모집단으로 집계하고, 활성 제한 확인
직전의 `ContinuousClock.Instant`부터 fake activity가 실제 생성된 확인 시점까지를 측정한다. 100회
모두 30초 이내 생성되어 최소 95회 기준을 통과했다. 권한 거부·미지원은 적격 모집단에서 제외하고
activity 미생성·`activityAuthorizationDenied` 반환·기존 활성 제한 상태 유지를 별도로 검증했다.
이 자동 계측은 coordinator와 protocol fake 경계의 결정적 증적이며 실제 ActivityKit 시스템 표시
성공률은 T096의 지원 OS 실기기 검증에서 기록한다. 대상 테스트 2개와 iPhone 17 Pro iOS 26.5
Simulator의 전체 `GetUpTests` 336개(동적 인자 실행 포함 379회)가 실패·skip 없이 통과했고, 앱과
네 extension의 코드 서명 없는 generic iOS 빌드, project plist와 `git diff --check`도 통과했다.

2026-09-03 002 구현 T024·T033을 완료했다. `LiveActivityTimePolicyTests`에 주입 시각 기준 종료 전·
정확한 경계·종료 후 남은 시간과 0 clamp, 즉시 종료 final state를 먼저 추가하고 policy 미구현 compile
RED를 확인했다. `LiveActivityCoordinatorTests`는 background 무조회·foreground 생성, 동일 조정 멱등성,
대표 하나로 중복 정리, 대표 변경 갱신, 수동 제거 후 재생성, 대상 부재 시 즉시 전체 종료,
authorization 비활성·미지원과 request·update·end 실패 격리를 검증한다. `LiveActivityCoordinator`는
actor 경계에서 주입된 `Clock`의 한 시각으로 조정을 직렬화하고, 실패를 안정 오류 코드로 반환해 제한
상태에 예외가 전파되지 않게 한다. iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 334개
(동적 인자 실행 포함 377회)가 실패·skip 없이 통과했고, 앱과 네 extension의 코드 서명 없는 generic
iOS 빌드, project plist와 `git diff --check`도 통과했다.

2026-09-03 002 구현 T023·T029를 완료했다. `LiveActivityDistancePolicyTests`에 `.inside` 근거의
`max(0, radius - centerDistance)`, 항상 미터인 10m half-up 반올림, 5m·15m 경계, 0 clamp,
정확히 5분 유효·5분 초과 stale, outside·unavailable·미래·누락·revision 불일치 근거를 검증하는
8개 테스트(동적 실행 포함 11회)를 먼저 추가하고 policy 미구현 compile RED를 확인했다.
`LiveActivityContentPolicy`는 유효한 거리만 `known(meters)`와 관측 시각으로 전달하고 그 밖의 상태는
관측 시각까지 제거한 `unavailable` content state로 만든다. 전체 회귀 중 기존
`PendingAppRouteRepository`의 조회 후 삭제 경쟁이 반복 재현되어, route 파일을 고유 claim 파일로
원자 이동한 단일 소비자만 반환하도록 보정했다. 해당 동시 소비 테스트 50회 반복과 iPhone 17 Pro
iOS 26.5 Simulator의 전체 `GetUpTests` 320개(동적 인자 실행 포함 363회)가 실패·skip 없이 통과했고,
앱과 네 extension의 코드 서명 없는 Simulator 빌드, project plist와 `git diff --check`도 통과했다.

2026-09-03 002 구현 T022·T028을 완료했다. `RestrictionOccurrenceEvaluatorTests`에
`activatedAt`·`startAt`·`ruleID` tie-break, 종료 경계의 대표 교체, 현재 규칙 revision 불일치 제거,
snapshot 부재를 검증하는 6개 테스트를 먼저 추가하고 evaluator 미구현 compile RED를 확인했다.
`RestrictionOccurrenceEvaluator`는 `endAt` 배타 경계와 현재 revision을 만족하는 occurrence만 남겨
계약 순서로 정렬하고 대표·추가 제한 여부를 반환한다. 대상 suite와 iPhone 17 Pro iOS 26.5
Simulator의 전체 `GetUpTests` 312개(동적 인자 실행 포함 352회)가 실패·skip 없이 통과했고 앱과
네 extension의 코드 서명 없는 Simulator 빌드, project plist와 `git diff --check`도 통과했다.
첫 전체 회귀에서는 기존 `PendingAppRouteRepositoryTests.concurrentConsumersClaimRouteOnce()`가
파일 삭제 경쟁 중 `readFailed`로 1회 실패했으나 해당 테스트 10회 반복과 전체 suite 재실행은 모두
통과했다.

2026-09-02 002 구현 T021과 선행 RED 테스트 T007의 green 전환을 완료했다.
`MonthlyAllowancePolicy`는 `Asia/Seoul` 월 경계, 월 quota 2, 비이월, 장부 삭제를 확인한 reset 월의
quota 0과 서버 생성 시각의 월 일치를 강제한다. `MonthlyAllowanceService`는 확인된 current epoch에서만
새달 app foreground allowance를 멱등 생성하며, Shield에서는 별도 선행 생성을 하지 않고 repository의
allowance 생성·무료 1회 예약 단일 원자 명령만 호출한다. `AppLifecycleCoordinator`는 foreground 복구
때 월 생성 trigger를 실행하고 실패를 `.monthlyAllowance`로 보고하되 기존 제한 복구를 계속한다.
`DependencyContainer`에는 공통 service·repository와 동기화 context provider 연결 지점을 조립했다.
iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 306개(동적 인자 실행 포함 346회)가 실패·skip
없이 통과했다. project plist와 `git diff --check`도 통과했다.

2026-09-02 002 구현 T020을 완료했다. `LiveActivityCoinFixtures.swift`에 ActivityKit 활동 관리,
CloudKit database, StoreKit storefront, 코인 장부 repository의 순서 있는 성공·실패 script와 호출
기록을 제공한다. 별도의 mutable monotonic clock과 wall clock으로 5분 freshness·기기 시각 변경·
프로세스 재시작을 실제 대기 없이 분리하고, Shield의 4.9초 확인 성공·정확히 5초 성공 미확인·
5초 이후 late commit을 고정 fixture로 제공한다. fixture 자체 Swift Testing 3개가 실패·skip 없이
통과해 clock 독립성, deadline 경계와 네 framework/release 실패 주입·호출 기록을 검증했다. 전체
test target은 T021의 계획된 RED 월 정책·서비스 타입이 아직 없어 완료 상태로 실행하지 않으며,
T020 source는 임시 Swift Package에서 실제 test source 그대로 컴파일·실행한 뒤 manifest를 제거했다.
project plist와 `git diff --check`, 코드 서명을 끈 generic iOS Simulator의 앱·네 extension 제품 빌드도
통과했다.

2026-09-02 002 구현 T019를 완료했다. `CoinLedgerSyncSession`은 Codable이나 wall-clock 시각을 갖지
않는 현재 프로세스 전용 상태로 두고, 성공한 초기 fetch의 `ContinuousClock.Instant`부터 정확히
300초까지인 경우에만 `current`를 허용한다. iCloud 가용성, confirmed mirror, 장부·계정 epoch 일치,
완료된 projection과 pending reconciliation 부재를 함께 검사하며, 새 프로세스는 성공 fetch 전까지
wall-clock `syncedAt`만으로 `current`를 복원할 수 없다. 로컬 빈 설치에서는 원격 projection을 우선해
잔액을 복구하고, 확인된 장부 부재는 삭제 증거에 따라 `setupRequired` 또는 `deletionConfirmed`로
분류한다. 일시 장애는 `unavailable`로 유지하며 삭제로 간주하지 않는다. 계정 전환은 이전 mirror·
freshness·pending change를 즉시 폐기하고, 호출자가 이전 mirror를 넘겨도 새 계정 잔액으로 노출하지
않는다. 모델·gate·adapter Swift Testing 28개가 실패·skip 없이 통과했고 project
plist, `git diff --check`, 코드 서명을 끈 generic iOS Simulator의 앱·네 extension 제품 빌드가
통과했다. T007의 current gate 범위는 green이며, 전체 T007은 T021 월 정책·서비스 구현 뒤 완료한다.

2026-09-02 002 구현 T018과 선행 RED 테스트 T009의 green 전환을 완료했다.
`CloudKitCoinLedgerRepository`는 mutable account·allowance·command의 change tag를 보존하고
`ifServerRecordUnchanged` 단일 atomic modify에서 balance·결정적 audit event·command를 함께
저장한다. `serverRecordChanged`는 최신 서버 record를 다시 읽어 제한 횟수 안에서 같은 command·event
ID로 재평가하며, `resultUnknown`은 새 명령을 만들지 않고 기존 command 또는 purchase grant를 먼저
조회한다. 현재 월 allowance가 없는 첫 Shield 요청은 quota 2 allowance·free grant·무료 1회
reservation·reserved command를 한 번에 저장하고, 다기기 생성 충돌 뒤에는 서버 grant를 재사용해
무료분을 2회 넘게 예약하지 않는다. 구매 잔액 reservation·검증 거래 grant, command applied·commit·
compensation도 같은 CAS 경계로 구현했다. 기존 mapper·repository·월간 충돌 Swift Testing 12개가
실패·skip 없이 통과했고 Swift strict typecheck, project plist, `git diff --check`, 코드 서명을 끈
generic iOS Simulator의 앱·네 extension 제품 빌드가 통과했다. Simulator test runner 추가 접근은
계정 사용 한도로 허가되지 않아 같은 두 test source를 임시 Swift Package로 그대로 컴파일·실행한
뒤 manifest를 제거했다. 전체 test target은 T019·T021의 계획된 RED 타입 구현 뒤 실행한다.

2026-09-02 002 구현 T017을 완료했다. `LedgerEpoch`, `CoinAccount`, `MonthlyAllowance`,
`PurchaseGrant`, `CoinLedgerEvent`, `ReleaseCommand`를 schema version 1의 명시적 필드 whitelist로
CloudKit record snapshot과 왕복 변환한다. singleton·월·거래·event·command별 결정적 record ID를
decode 시에도 검증하고, 알 수 없는 type·미지원 schema·필드 타입·record ID·정의되지 않은 필드를
거부한다. 따라서 위치 좌표·정확도와 Family Controls application/category/web domain token은
쓰기 record에 생성되지 않으며 원격 record에 섞여도 읽기 경계에서 차단된다. 여섯 entity 왕복,
mutable ID 안정성, type·schema·개인정보 필드 거부 독립 실행 검증과 Swift typecheck, project plist,
`git diff --check`가 통과했다. 코드 서명을 끈 generic iOS Simulator에서 앱과 네 extension 제품
빌드가 통과했다. 첫 sandbox 빌드는 CoreSimulatorService 접근 제한으로 실패했지만 권한을 허용한
동일 명령은 성공했다. T009의 mapper 범위는 green이나 같은 test source의 repository 범위는 T018
구현 전 compile할 수 있어 T009는 아직 미완료로 유지한다.

2026-09-02 002 구현 T016과 선행 RED 테스트 T008의 green 전환을 완료했다. 기존 001 규칙·장소·위치
파일과 분리된 활성 occurrence·confirmed 잔액 mirror·해제 예외 snapshot을 기존 보호된 atomic
writer로 저장하고, 새 파일 부재는 nil 또는 빈 예외로 안전하게 migration한다. `PendingAppRouteRepository`는
생성 시각 이상 5분 미만, 미소비, 선택적 occurrence 활성 조건을 actor 내부에서 함께 검사하며,
성공 route와 만료·미래·중복·종료 route 모두 파일 삭제가 성공한 뒤에만 결과를 반환하거나 폐기한다.
iPhone 17 Pro iOS 26.5 Simulator에서 관련 테스트 17개(동적 인자 실행 포함 23회)와 기존 001
`SharedSnapshotRepositoryTests` 14개가 실패·skip 없이 통과했다. 첫 회귀 실행은 직전 runner 때문에
Simulator preflight가 `Busy`로 중단됐지만 Simulator가 정리된 뒤 동일 명령 재실행은 통과했다.
Swift 구문, project plist와 제품·test build도 통과했다. 아직 구현되지 않은 T017·T019·T021 및
그에 대응하는 RED 테스트 소스는 관련 suite 실행에서 제외했으며, 전체 test target은 그 구현 뒤
검증한다.

2026-09-02 002 구현 T015를 완료했다. 활성 제한·코인 잔액·해제 예외·앱 진입 route의 App Group
snapshot 파일명과 `CoinLedgerZone`, 여섯 CloudKit record type, 고정·결정적 record ID를 공용
식별자로 정의했다. 상품 catalog의 Info.plist·상품 ID·수량 key도 T004 설정과 같은 문자열로
중앙화했다. 구매 지급 record와 구매 event, 해제 명령 record와 예약 event는 같은 custom zone에서
이름이 충돌하지 않도록 서로 다른 접두사를 사용한다. Swift typecheck, project plist,
`git diff --check`, 코드 서명을 끈 generic iOS Simulator의 앱·네 extension 제품 빌드가 통과했다.
전체 `GetUpTests`는 T017의 mapper·repository와 T019의 sync context 등 계획된 RED 구현이 남아 있어
아직 완료 상태로 실행하지 않으며 T007~T009도 미완료로 유지한다.

2026-09-02 002 구현 T014를 완료했다. ActivityKit 활동 목록·생성·갱신·종료, CloudKit fetch·
원자 modify, StoreKit 상품·구매·unfinished·transaction update·finish, 월간 allowance·무료 및 구매
reservation·구매 지급·명령 확정/보상, 활성 occurrence·잔액 mirror·해제 예외·pending route 저장소를
framework 독립 `Sendable` 계약으로 정의했다. CloudKit record 값과 change tag·save policy를
도메인 snapshot으로 제한하고, adapter 오류는 좌표·token·시스템 상세를 포함하지 않는 고정
`LiveActivityCoinErrorCode`로 변환하도록 했다. 이 계약을 앱과 세 Screen Time extension에 연결하고
공유 Live Activity 모델도 필요한 extension source에 포함했다. Swift strict concurrency typecheck,
project plist, `git diff --check`, iPhone 17 Pro iOS 26.5 Simulator의 앱·네 extension 제품 빌드가
통과했다. 전체 `GetUpTests` build는 계획된 RED 상태이며 첫 compile 오류는 T017의
`CoinLedgerRecordEntity`·`CoinLedgerRecordMapper`와 T019의 `CoinLedgerCurrentContext` 미구현이다.
후속 T015~T019·T021 구현 전에는 관련 RED 테스트를 완료 처리하지 않는다.

2026-09-02 002 구현 T013을 완료했다. `ReleaseCommand`에 `requested`·`reserved`·`applied`·
`committed`, 거절·보상, 5초 성공 미확인 뒤 `reconciliationRequired`에서 `committed` 또는
`compensated`로 수렴하는 선언적 상태 전이를 구현했다. reservation에서 확정한 무료분·구매 코인
funding source는 이후 바꿀 수 없고, 갱신 시각은 역행하지 않으며 안정 failure code는 최종 상태까지
보존한다. `ReleaseException`과 중복 command·occurrence를 막는 collection snapshot, `coinStore`·
`iCloudRecovery`·`ledgerReset`·`reconciliation` 목적의 `PendingAppRoute`도 생성·디코딩 경계에서
검증한다. 모델 typecheck·독립 실행 검증·Swift 구문·project plist·`git diff --check`가 통과했고,
코드 서명을 끈 generic iOS Simulator 제품 빌드도 앱과 네 extension을 포함해 통과했다. 전체
`GetUpTests` build에서 T013 symbol 오류가 사라진 것을 확인했으며, 잔여 compile 실패는
T014~T019·T021의 미구현 계약·adapter·정책 타입에 한정된다.

2026-09-02 002 구현 T012를 완료했다. `LedgerEpoch`, 구매 잔액·예약을 분리한 `CoinAccount`,
월 quota·사용·예약을 분리한 `MonthlyAllowance`, 검증된 거래와 조정 수량을 보존하는
`PurchaseGrant`, 감사 연결 필드를 가진 `CoinLedgerEvent`를 구현했다. `CoinBalanceSnapshot`은
`setupRequired`를 포함한 동기화 상태와 장부 epoch·확인 이력을 보존하며, `current`는 확인된
epoch가 있을 때만 생성·디코딩되도록 강제했다. 음수 잔액, 초과 예약·조정, 0 수량 event와
확인되지 않은 current snapshot 거부를 검증했다. 모델 typecheck·독립 실행 검증·Swift 구문·
project plist·`git diff --check`가 통과했고, 코드 서명을 끈 generic iOS Simulator 제품 빌드도
앱과 네 extension을 포함해 통과했다. 전체 `GetUpTests` build에서 T012 symbol 오류가 사라진 것을
확인했으며, 잔여 compile 실패는 T013~T019·T021의 미구현 타입에 한정된다.

2026-09-02 002 구현 T011을 완료했다. `RestrictionLiveActivityAttributes`의 정적 필드와
`ContentState`에 대표 occurrence·규칙명·종료 시각·추가 제한 여부를 최소 payload로 구성했다.
거리는 `known(meters)`·`unavailable`로만 표현하고, known의 0 이상 거리·필수 관측 시각과
unavailable의 nil 관측 시각을 생성·디코딩 모두에서 강제했다. 속성과 상태 JSON 합계가
4KB 미만이고 좌표·정확도·주소 key가 없음을 테스트했다. iOS에서만 `ActivityAttributes`를
채택해 앱·Widget Extension이 공유하고, 순수 Codable 부분은 macOS 독립 검증을 가능하게 했다.
iOS typecheck·독립 실행 검증·Swift 구문·project plist·`git diff --check`가 통과했고,
코드 서명을 끈 generic iOS Simulator 제품 빌드도 앱과 네 extension을 포함해 통과했다.
전체 `GetUpTests` build에서 T011 symbol·타입 오류가 사라진 것을 확인했으며, 잔여 compile
실패는 T012~T019·T021의 미구현 타입에 한정된다.

2026-09-02 002 구현 T010을 완료했다. `RestrictionOccurrence`는 rule ID·revision·시작·종료
시각의 정확한 bit pattern으로 재실행·재부팅에도 동일한 ID를 생성하고, 저장 ID가 필드와
다르거나 구간이 양수가 아니면 거부한다. `ActiveRestrictionSnapshot`은 schema version 1·0 이상 revision·
고유 occurrence ID를 강제하고 디코딩에서도 동일 불변 조건을 적용한다. 기존 테스트에
결정적 ID의 모든 식별 필드·`activatedAt` 비식별 규칙과 위조 ID 디코딩 거부를 추가했다.
모델 typecheck·독립 실행 검증·Swift 구문·project plist·`git diff --check`가 통과했고,
코드 서명을 끈 generic iOS Simulator 제품 빌드도 앱과 네 extension을 포함해 통과했다.
전체 `GetUpTests` build에서 T010 symbol 오류가 사라진 것을 확인했으며, 잔여 compile 실패는
T011~T019·T021의 미구현 타입에 한정된다.

2026-09-02 002 구현 T009의 CloudKit 장부 RED 테스트 12개를 두 파일에 작성했다. 모든
장부 entity의 record round-trip·schema 거부·위치와 Family Controls token 비포함·결정적 record
ID를 검증한다. Repository는 `ifServerRecordUnchanged` 단일 atomic modify, change-tag 충돌 후
동일 ID 재시도, timeout 결과 불명 후 동일 command 재조회와 reconciliation 전환을 검증한다.
첫 Shield 요청의 allowance·free grant·reservation·command 단일 atomic modify와 다기기 생성 충돌,
무료분 이중 예약 방지도 포함했다. 두 source의 Swift 구문, `project.pbxproj` plist·target membership,
`git diff --check`가 통과했고 코드 서명을 끈 generic iOS Simulator 제품 빌드도 앱과 네 extension을
포함해 통과했다. 실제 `GetUpTests` build는 계획대로 T012~T018의 record mapper·database
boundary·repository·월간 reservation 타입이 없어 RED가 확인됐다. 실패한 관련 테스트가 있으므로
T009는 체크하지 않고 T017·T018 구현과 green 전환 때 완료 처리한다.

2026-09-02 002 구현 T008의 RED 테스트를 두 파일에 작성했다. 활성 occurrence·confirmed balance
mirror·해제 예외의 독립 round-trip, 기존 001 규칙·위치 파일 비파괴 migration, 새 파일 부재의 안전한
빈 상태, 파일별 손상 JSON·지원하지 않는 schema와 atomic write 실패 시 이전 값 보존을 검증한다.
`PendingAppRoute`는 생성 직후 소비와 atomic 삭제, 정확히 5분·5분 초과·미래 시각 만료, 종료
occurrence·이미 소비된 route 폐기, occurrence 없는 복구 route, 같은 route ID 중복 저장·소비 거부,
손상 JSON과 write 실패를 포함한다. T007 테스트에서 후속 구현 시 드러날 fixture 접근 수준과 actor
저장 대역의 Sendable 타입도 함께 보정했다. 새 source의 Swift 구문 검사, `project.pbxproj` plist와
target membership, `git diff --check`가 통과했고 코드 서명을 끈 generic iOS Simulator 제품 빌드도
앱과 네 extension을 포함해 통과했다. 실제 `GetUpTests` build는 계획대로 T010~T013·T015~T016의
`ActiveRestrictionSnapshot`, `CoinBalanceSnapshot`, `PendingAppRouteRepository`, 새 파일 식별자 등
미구현 symbol에서 RED가 확인됐다. 실패한 관련 테스트가 있으므로 T008은 체크하지 않고 T016 구현과
green 전환 때 완료 처리한다.

2026-09-02 002 구현 T007의 RED 테스트 23개를 세 파일에 작성했다. occurrence 결정적 ID·Codable·
구간과 중복 불변 조건, Live Activity 거리 payload, 구매·예약 잔액과 해제 명령·예외, 비영속
`CoinLedgerSyncSession`의 monotonic 정확히 5분 경계·wall clock 무관성·프로세스 재시작·epoch·
projection·pending reconciliation gate를 검증한다. 서울 월 경계, quota 2, 비이월, 삭제 월 quota 0,
서버 생성 월 검증과 첫 앱 foreground 지연 생성의 성공·멱등·실패·비가용 장부 무변경도 포함했다.
세 source의 Swift 구문 검사, `project.pbxproj` plist와 target membership, `git diff --check`는 통과했다.
코드 서명을 끈 generic iOS Simulator 제품 빌드는 앱과 네 extension을 포함해 통과했다.
실제 `GetUpTests` build는 계획대로 T010~T013·T019·T021의 모델·정책·서비스가 없어
`RestrictionOccurrence`, `CoinLedgerCurrentGate`, `MonthlyAllowancePolicy`, `MonthlyAllowanceService` 등
미구현 symbol에서 RED가 확인됐다. 실패한 관련 테스트가 있으므로 T007은 체크하지 않고 후속 구현이
green으로 전환할 때 완료 처리한다.

2026-09-02 002 구현 T006과 Phase 1 체크포인트를 완료했다. `GetUp` 공용 scheme의 BuildAction에
`GetUpLiveActivity`를 명시하고 Run action에 `Configuration/GetUp.storekit`을 연결했으며,
`GetUp.xctestplan`에는 같은 StoreKit configuration과 기존 `GetUpTests`·`GetUpUITests`, 앱 변수 확장
target을 유지했다. project plist, scheme XML, test plan JSON과 `xcodebuild -showTestPlans` 검증이
통과했다. Apple 공식 StoreKit 샘플과 같은 `SKTestSession` 로드 결과를 확인했다.

첫 test 실행에서는 소스가 없는 Live Activity `.appex`에 실행 파일이 생성되지 않아 Simulator 설치가
실패했다. 실제 Widget UI를 앞당겨 구현하지 않는 `GetUpLiveActivityExtensionBootstrap` link anchor를
T036의 예정 파일에 추가한 뒤, 앱과 네 확장·단위/UI 테스트 bundle의 build-for-testing 및 Live
Activity Mach-O 산출물을 확인했다. 공용 test plan의 `GetUpTests` 233개가 동적 실행 포함 267회 모두
통과했고 실패·skip은 0개다. 코드 서명 비활성화에 따른 XCTest strip 경고, 기존 테스트의 불필요한
`try` 경고와 Xcode의 빈 device build number 경고는 남지만 빌드·테스트 결과에는 영향을 주지 않았다.

2026-09-02 002 구현 T005를 완료했다. `Configuration/GetUp.storekit`에
`com.dxyn02.GetUp.coin.1`·`.3`·`.5`를 판매 가능한 `Consumable`로 등록하고 한국어·영어 표시명과
설명, KOR storefront 로컬 테스트 가격 ₩1,100·₩2,900·₩4,400을 구성했다. JSON 구조, 상품 3개,
고정 허용 ID, 상품 종류, 가격, 양쪽 locale과 storefront를 `jq` assertion으로 검증했다.
`.storekit` 파일의 Xcode 로드와 scheme 연결은 T006에서 함께 검증한다.

2026-09-02 002 구현 T004를 완료했다. 앱 Info.plist의 catalog가
`com.dxyn02.GetUp.coin.1`→1, `.3`→3, `.5`→5로 구성되고
`SKIncludeConsumableInAppPurchaseHistory = true`임을 확인했다. Debug·Release에서 세 build setting이
같은 값으로 해석됐으며, 코드 서명 없는 generic iOS Simulator 빌드 뒤 실제 앱 번들 Info.plist의
변수 확장·수량과 앱 및 네 extension 산출물을 검증했다. 첫 sandbox 실행은 Simulator runtime 접근
제한으로 실패했으나 권한을 허용한 동일 빌드는 성공했다.

2026-09-02 002 구현 T003을 완료했다. 앱과 Shield Action entitlement의 plist 문법 및
`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services = CloudKit`
선언을 확인했다. 두 scheme의 Debug build settings에서 공통
`GETUP_ICLOUD_CONTAINER_IDENTIFIER = iCloud.com.dxyn02.GetUp`과 target별 entitlement 경로가
해석됐다. 실제 Apple Developer container 등록·두 App ID 할당·production schema와 서명 entitlement는
T097 배포 준비에서 별도 확인해야 한다.

2026-09-02 002 구현 T002를 완료했다. 앱·확장 Info.plist와 entitlement, `project.pbxproj`의 plist
문법 검사가 모두 통과했다. 앱의 `NSSupportsLiveActivities = true`, 확장의
`com.apple.widgetkit-extension`, 양쪽의 `group.com.dxyn02.GetUp`을 확인했다. 확장 Debug build
settings에서 `CODE_SIGN_ENTITLEMENTS`, `GETUP_APP_GROUP_IDENTIFIER`, `INFOPLIST_FILE`, bundle ID와
app-extension-only 설정이 기대값으로 해석됐다. 전체 Simulator build는 T006 체크포인트에서 실행한다.

2026-09-02 002 구현 T001을 완료했다. `plutil -lint GetUp.xcodeproj/project.pbxproj`가 통과했고,
`xcodebuild -list -project GetUp.xcodeproj`에서 `GetUpLiveActivity` target과 scheme을 확인했다.
시뮬레이터 서비스·로컬 provisioning profile 경고는 출력됐지만 명령은 성공했다. 확장의 Info.plist와
entitlements는 T002 범위이므로 전체 build와 테스트는 T002·T006 구성 후 실행한다.

2026-09-02 `002-live-activity-coins` 재분석의 잔여 권장 조치 3건을 반영했다. T039는 US1의 T011·
T032·T033 뒤 실행하고 T055의 직접 ActivityKit 연결만 차단하도록 의존성 그래프를 고쳤다.
`setupRequired` 최초 활성화는 initial epoch+당월 무료 2회의 `CoinLedgerSetupService`, 삭제 확인은
구매 0+당월 무료 0의 `CoinLedgerResetService`로 분리하고 T064·T065·T072·T075에 테스트·UI action을
명시했다. `current` 5분 freshness는 비영속 monotonic session 기준으로 통일하고 wall-clock
`syncedAt`은 표시·진단 전용, 프로세스 재시작 후 새 fetch 필수로 고정했다. 문서 변경이므로 코드
테스트는 실행하지 않았다. task 98개 연속 ID·형식, FR 41개·SC 12개, placeholder·충돌 표식 부재와
`git diff --check`를 검증해 모두 통과했다.

2026-09-02 `002-live-activity-coins` 교차 산출물 분석의 전체 권장 조치를 반영했다. FR-041의
`PendingAppRoute` 5분·일회 소비·종료 구간 폐기와 SC-003의 60초 정확도·0 clamp를 명시적 자동
테스트 task로 강화했다. 월간 정책·지연 생성·Shield 원자 예약을 Phase 2 공통 기반으로 앞당기고,
US2 구현 전 Shield Action ActivityKit 실기기 feasibility gate를 T039에 배치했다. `current`의 5분
freshness·epoch/projection·reconciliation 조건, 최초 setup·기존 장부 복구·삭제 reset 시나리오,
US2→US4 및 공유 파일 순차 의존성을 문서화했다. T092는 기존 계측 suite 집계로 한정했고 branch·상태
metadata를 현재 작업과 일치시켰다. 문서 변경이므로 코드 테스트는 실행하지 않았으며 산출물 형식과
`git diff --check`를 재검증해야 한다.

2026-09-02 `$speckit-tasks`로 `002-live-activity-coins` 작업을 최신 설계에 맞춰 98개로 재생성했다.
설정 6개, 공통 기반 15개, US1 17개, US2 20개, US3 19개, US4 12개, 마감 9개로 구성했다.
Live Activity 적격 모집단·위치 기산점, Shield 4.9초·5초·late commit, 동일 iCloud 로컬 빈 새 설치
복구, 새달 첫 앱·Shield 요청 지연 생성에 각각 선행 실패 테스트와 구체 구현 파일을 배정했다. 연속
ID·story label·`[P]`·파일 경로 형식과 `git diff --check`를 검증하고 있으며 문서 변경이므로 코드
테스트는 실행하지 않는다. 다음 단계는 `$speckit-analyze`다.

2026-09-02 `$speckit-plan`으로 `002-live-activity-coins`의 최신 명확화를 Phase 0·Phase 1 산출물에
재동기화했다. Live Activity 적격 100회 중 95회·30초 시작 기준과 위치 수신 주체별 30초 기산점,
동일 iCloud `current` 장부의 로컬 빈 새 설치 잔액·내역 복구, Shield의 5초 fail-closed·late commit
재조정, 새달 첫 앱·Shield 요청의 월간 무료분 지연 생성을 plan·research·data model·다섯 contract·
quickstart와 DEC-077에 반영했다. 헌법 사전·사후 게이트와 문서 일관성을 확인하고 있으며 문서
변경이므로 코드 테스트는 실행하지 않는다. 다음 단계는 `$speckit-tasks`다.

2026-09-01 이미 병합된 `codex/app-store-assets`의 PR #23을 확인하고 최신 `origin/main`에서
`codex/live-activity-coins-spec` 브랜치를 생성해 002 문서 변경만 분리했다. 문서 검증 후 커밋·PR
병합을 진행한다.

2026-09-01 `002-live-activity-coins` 분석 권장 수정 1·2·3·4·6과 사용자 확정 Shield 단일 버튼
흐름을 산출물에 반영했다. Live Activity payload를 4KB 미만으로 정정하고, foreground 시작 서술,
`.inside`·5분 유효기간·항상 미터·10m half-up 거리 정책, 코인 해제 뒤 Live Activity 조정의 비치명
경계를 명시했다. Shield는 기존 내용과 `해제권 1회 사용`·`앱 닫기`로 구성하며, tap 뒤 최신 장부에서
무료 우선·구매 fallback을 결정한다. `current` 잔액 부족은 coin store, 장부 불확실은 복구 route로
분리했다. Apple 공식 문서와 설치된 iOS 26.5 SDK interface에서
`ShieldActionResponse.openParentalControlsApp`이 iOS 26.5부터 가능함을 확인해 iOS 26.0~26.4에는
안내·`.close` 호환 경로를 설계했다. FR 41개·SC 12개·연속 task 91개와 task 형식,
`git diff --check`를 검증했다. 문서 변경이므로 코드 테스트는 실행하지 않았다.

2026-09-01 `$speckit-tasks`로 `002-live-activity-coins`의 구현 작업 91개를 생성했다. 공통 설정·
기반 21개, US1 14개, US2 18개, US3 17개, US4 12개, 마감 9개로 구성하고 각 스토리에 선행 실패
테스트, 독립 검증 기준, 의존성 그래프와 병렬 실행 예시를 포함했다. 모든 task의 체크박스·연속 ID·
스토리 label·구체 파일 경로 형식과 `git diff --check`를 검증했다. 문서 작업이므로 코드 테스트는
실행하지 않았다. 다음 권장 단계는 `$speckit-analyze`다.

2026-09-01 `$speckit-plan`을 재실행해 FR-037~FR-040과 DEC-075를 `research.md`, `plan.md`,
`data-model.md`, Live Activity·CloudKit 장부·StoreKit 구매·규칙 해제·Shield 코인 UI의 다섯
contract, `quickstart.md`에 반영했다. 최신 장부에서만 구매 시작, 1개·3개·5개 고정 상품,
Live Activity 수동 제거 후 foreground 재생성, 장부 삭제 확정 시 잠금과 명시적 새 장부의 구매 0·
당월 무료 0·다음 달 무료 2 정책을 설계와 검증 계약으로 고정했다. 헌법 게이트와 문서 일관성,
`git diff --check`를 확인했으며 계획 문서 작업이므로 코드 테스트는 실행하지 않았다. 다음 단계는
`$speckit-tasks`다.

2026-09-01 `$speckit-clarify`에서 네 질문을 확정했다. iCloud 장부가 최신이 아니면 구매를 시작하지
않고, 제거한 Live Activity는 활성 제한 중 다음 foreground에서 재생성하며, 초기 상품은 1개·3개·
5개 묶음으로 구성한다. CloudKit 개인 장부 삭제 시 사전 고지, 코인 기능 잠금, 사용자 확인 후
구매 코인 0개·현재 월 무료분 0회로 새 장부 시작과 다음 달 무료 지급 재개를 명세와 DEC-075에
반영했다. 명세 품질 체크리스트 14/14 항목은 그대로 통과했고 `git diff --check`를 검증했다. 문서
작업이므로 코드 테스트는 실행하지 않았다.

2026-09-01 `002-live-activity-coins`의 `plan.md`, `data-model.md`, Live Activity·CloudKit 장부·
StoreKit 구매·규칙 해제·Shield 코인 UI의 다섯 contract와 `quickstart.md`를 한국어로 작성했다.
헌법 사전·사후 게이트를 통과했고 모든 Phase 0 미확정 항목과 `[NEEDS CLARIFICATION]`이 제거됐다.
문서 링크·요구사항 경계와 `git diff --check`를 검증했으며 계획 작업이므로 코드 테스트는 실행하지
않았다. 다음 단계는 `$speckit-tasks`다.

2026-09-01 BLK-014의 마지막 결정으로 초기 앱 서버를 도입하지 않기로 확정했다. Live Activity는
foreground 활성 제한 확인 시 시작하고, 구매·환불은 검증된 StoreKit 거래와 CloudKit private
database 장부를 앱 실행 시 재조정한다. 서버 없는 복구·환불 한계와 구매 전 고지를 `spec.md`,
`research.md`, DEC-074에 반영했다. 문서 변경이므로 코드 테스트는 실행하지 않았다.

2026-09-01 BLK-014 중 거리 갱신은 기존 위치 이벤트와 앱 실행 시점의 신뢰 가능한 값만 사용하고
stale이면 확인 불가로 전환하는 저전력 방식을 선택했다. 월간 무료 해제권은 `Asia/Seoul` 매월 1일
00:00 경계로 확정해 `spec.md`, `research.md`, DEC-073에 반영했다. 서버 도입 여부는 비용·운영 범위
설명 후 사용자 결정을 기다린다. 문서 변경이므로 코드 테스트는 실행하지 않았다.

2026-09-01 `002-live-activity-coins` Phase 0에서 Apple 공식 문서를 기준으로 ActivityKit,
StoreKit 2, CloudKit private database와 CKSyncEngine을 조사해 `research.md`를 작성했다. 앱 비실행
Live Activity 자동 시작, 이동 중 거리 갱신, 권위 있는 결제·환불 서버, 월간 무료 지급 시간대가
제품 또는 외부 인프라 결정임을 BLK-014로 기록했다. 결정 전 Phase 1 산출물은 생성하지 않았으며,
문서 변경이므로 코드 테스트는 실행하지 않았다.

2026-09-01 `002-live-activity-coins`에 같은 iCloud 계정 기준 매월 무료 해제권 2회 충전,
미사용 무료분 비이월, 무료분 우선 사용, 구매 코인과 별도 표시·장부, 구매 코인 비만료 정책을
반영했다. 월 중간 신규 사용자 지급, 여러 기기·재실행·기기 날짜 변경의 계정·월별 중복 방지,
iCloud 상태 미확인 시 안전한 재시도 요구사항과 성공 기준도 추가했다. 명세 품질 체크리스트와
`[NEEDS CLARIFICATION]` 부재를 재검증했으며 문서 변경이므로 코드 테스트는 실행하지 않았다.

2026-09-01 `002-live-activity-coins` 명세의 3개 명확화를 반영했다. Live Activity는 대표 규칙
1개의 남은 거리·시간만 표시하고, 코인 사용은 Shield·앱 내로 한정했다. 확인된
구매 지급과 사용·보정 장부를 같은 iCloud 계정에 동기화해 잔액을 복구하는 정책을
명세했다. 명세의 모든 `[NEEDS CLARIFICATION]` 표시를 제거했고 품질 체크리스트의 모든
항목과 `git diff --check`를 검증했다. 이 세션은 명세 작성이므로 코드 테스트는 실행하지 않았다.

2026-09-01 T129에서 위치 권한 목업 이미지에 픽셀로 포함된 `정확한 위치: 켬`을 동일한 캡슐 형태의
현지화 SwiftUI 텍스트로 덮어 영어에서 `Precise Location: On`을 표시했다. Shield는 저장된
프리셋 값 `집`·`회사`를 변경하지 않고 상세 문구를 만들 때 extension bundle에서만 `Home`·`Work`로
지역화했다. `ShieldContentProviderTests`의 한국어 기존 회귀와 영어 Home·Work 회귀, US4 영어
위치 권한 UI 회귀가 iPhone 17 Pro iOS 26.5 Simulator에서 통과했다. 영어 시뮬레이터 스크린샷으로
목업 내 한글이 완전히 가려진 것을 확인했고, Shield Configuration extension 산출물의 `en.lproj` 안에
`Home`·`Work`·영어 Shield format이 포함된 것과 String Catalog JSON, `git diff --check`를 검증했다.

2026-08-27 T128에서 iPhone 14 Plus iOS 26.5 Simulator의 상태 막대를 9:41·배터리 100%로 고정하고
한국어 6장, 영어 5장의 1284×2778 원본 PNG와 알파 채널이 없는 JPEG 제출본을 생성했다. 한국어·영어
Promotional Text·Description·Keywords와 공통 Copyright 초안을 `AppStore/metadata`에 기록하고,
키워드는 UTF-8 100바이트 이내로 검증했다. 홈 조건 설명이 고정 548pt pager 안에서 한 줄로 압축되던
문제는 두 홈 카드의 설명에 세로 고정 크기를 부여해 두 줄을 유지하도록 수정했다. 영어 개수 문구는
`count == 1`에서 `1 app`, `1 app selected`, `You can use the selected app again` 전용 문자열을 사용하고
복수에서만 `apps`를 사용하도록 보정했다. 실제 system-owned Shield는 Simulator의 UI test probe와
다르므로 제출 이미지에 포함하지 않았고 Family Controls entitlement·token이 적용된 실기기 캡처로
남겼다. 전체 `GetUpTests` 231개가 동적 실행 포함 265회 실패·skip 없이 통과했다. US1 UI 회귀 전체
실행에서 기존 한국어 어순과 달라진 두 테스트만 실패해 `1개 앱`·`1개 앱 선택됨`을 보존하도록 수정한
뒤 해당 두 테스트와 `RestrictionStatusModelTests`를 재실행해 통과했다. 최종 Simulator build,
String Catalog JSON 구조, 11개 JPEG의 1284×2778·알파 없음과 `git diff --check`를 검증했다.

2026-08-27 T127에서 저장 장소를 선택한 뒤 지도 정착 또는 현재 위치 이동이 선택 ID·이름·chip 상태를
지우던 원인과, 선택을 유지해도 같은 이름을 재사용하면서 새 좌표를 버리던 두 번째 원인을 함께
수정했다. `LocationPickerCompletion.updated`가 기존 장소 ID와 새 좌표를 전달하고,
`RuleEditorModel`은 ID·이름·`createdAt`을 보존한 채 좌표와 `updatedAt`을 갱신한다. 저장소는 같은 ID를
upsert하며 `AppModel`이 모든 참조 규칙의 홈·runtime 복구에 새 좌표를 반영한다. 다른 활성 규칙이
공유하는 장소는 기존 활성 중 수정 차단을 우회하지 못하도록 저장을 거부한다. iPhone 14 Plus iOS
26.5 Simulator에서 전체 `GetUpTests` 230개가 동적 실행 포함 264회, US1 UI 회귀 17개가 실패·skip
없이 통과했다. Map을 실제로 swipe한 뒤 `집` chip 선택과 적용 가능 상태가 유지되는 회귀를 포함하며,
`git diff --check`도 통과했다.

2026-08-27 T126에서 한국어 source인 `Localizable.xcstrings`의 사용자 노출 항목 246개에 앱의 문체와
iOS 시스템 설정 명칭을 반영한 영어 번역을 추가하고 모든 영어 `stringUnit`을 `translated`로
전환했다. 첫 적용에서 영어 기기에도 한글이 남은 원인은 String Catalog가 `Text("…")` 정적 literal은
자동 변환하지만 모델 속성, 삼항식, 문자열 보간 등으로 먼저 생성된 `String`은 자동 lookup하지 않기
때문이었다. 공통 `AppLocalizedCopy`를 추가해 온보딩 모델·행동 문구·validation·접근성·앱 요약과
시간 안내를 명시적으로 지역화하고, 영속 프리셋 값 `집`·`회사`는 변경하지 않은 채 표시 시에만
`Home`·`Work`로 변환했다. 영어 Simulator에서 빈 홈, 규칙 편집, 위치 선택, 시작 시각, 온보딩 개요와
Screen Time 권한, 활성 홈을 직접 확인했으며 사용자 입력 규칙명만 원문 보존됨을 확인했다. 앱과 세
확장 Simulator build 및 전체 `GetUpTests` 발견 224개·동적 실행 포함 225회가 실패·skip 없이
통과했다. `UserStory1RuleConfigurationUITests` 16개와 `UserStory4PermissionGuidanceUITests` 19개,
총 35개 UI 회귀도 실패·skip 없이 통과했다. JSON 구조, 영어 번역 완료 상태, 한글 잔존과
한국어·영어 format placeholder 종류·개수도 검사했다.

2026-08-27 T125에서 직접 입력 장소가 위치 `적용` 뒤에는 `RuleEditorModel`에만 존재하고 규칙 저장
전에는 영속 장소 collection에 없다는 상태 차이를 삭제 경로에 반영했다. 기존 구현은 모든 chip을
`RuleConfigurationService.deleteSavedPlace`로 보내 `savedPlaceNotFound`를 일반 실패 Alert로
표시했다. `AppModel`이 앱의 영속 장소 목록에는 없고 열린 editor에만 있는 대상을 초안 전용으로
판별해 저장소 write 없이 editor·picker에서 제거하며, 초안 프리셋 보호는 유지한다. AppModel 대상
13개와 직접 입력→적용→즉시 삭제 UI 회귀 1개가 통과했다. 최종 전체 `GetUpTests`는 발견 224개·
동적 실행 포함 225회, `UserStory1RuleConfigurationUITests`는 16개가 실패·skip 없이 통과했다.
iPhone 17 Pro iOS 26.5 Simulator의 앱·extension build와 `git diff --check`도 통과했다.

2026-08-27 T124에서 `집`·`회사`를 제외한 직접 입력 저장 장소 chip에 별도 삭제 행동과 확인 Alert를
추가했다. 전용 `RuleConfigurationService.deleteSavedPlace`가 최신 활성·비활성 규칙 참조를 모두
검사해 사용 중이면 규칙 수와 함께 차단하고, 미사용이면 장소 collection revision을 증가시켜 마지막
장소의 빈 collection까지 저장한다. 저장 성공 뒤에만 `AppModel`·열린 편집 초안·위치 picker 목록을
갱신하며, 미저장 초안의 선택 장소를 삭제하면 선택·이름만 지우고 지도 핀은 보존한다. 같은 편집
세션에서 위치 화면을 적용하지 않고 나갔다 다시 들어올 때 동일 `LocationPickerModel`을 재사용하고,
선택 장소 좌표의 MapKit 정착 callback이 선택을 해제하지 않도록 보정했다. 삭제 service·앱·편집·
위치 모델 대상 테스트 56개가 통과했고, 최종 전체 `GetUpTests`는 발견 223개·동적 실행 포함 224회,
`UserStory1RuleConfigurationUITests`는 15개가 실패·skip 없이 통과했다. iPhone 17 Pro iOS 26.5
Simulator의 앱·extension build와 `git diff --check`도 통과했다.

2026-08-27 T123에서 `CoreLocationCurrentLocationSession.requestAlwaysAuthorization()`이
`.whenInUse`의 권한 변경 callback만 기다려 checked continuation을 끝내지 못하는 원인을 수정했다.
delegate callback은 즉시 반영하고, 시스템 prompt가 표시되면 앱이 다시 active가 될 때 권한을 읽으며,
prompt와 callback이 모두 없으면 1초 fallback으로 `.whenInUse`를 미승격 반환한다. 권한 안내는
로딩을 끝내고 `한 번만 허용` 또는 Always 미변경 상황을 설명하며
`설정 열기`로 전환한다. callback 정상 승인·무응답 미승격 어댑터 회귀와 모델 문구 회귀를 포함한
전체 `GetUpTests` 214개 test case가 동적 실행 포함 215회 실패·skip 없이 통과했고, US4 권한 안내
UI 테스트 19개와 iOS Simulator app·extension build도 통과했다.

2026-08-27 T122에서 `GetUp-2026-08-25-225630.ips`의 main-thread crash stack을 확인했다. 규칙 삭제
저장과 `AppModel.apply`는 마지막 규칙에서 빈 collection·`nil` selection으로 정상 전환했지만,
SwiftUI가 사라지는 `TabView`의 이전 `Binding`을 지연 갱신하면서 `HomeView.selectedRuleBinding`의
`homeRules[0]` fallback을 호출해 `Swift runtime failure: Index out of range`가 발생한 것이 원인이었다.
pager selection과 page tag를 `UUID?`로 변경해 빈 규칙 상태를 `nil`로 표현하고 index 접근을
제거했다. 마지막 규칙 삭제 시 `homeRules.isEmpty`, `selectedRuleID == nil`, 저장 장소 보존을 검증하는
`AppModelTests`와 세 규칙을 3→2→1→0으로 삭제한 뒤 앱 foreground·빈 홈을 확인하는 UI 회귀를
추가했다. XcodeBuildMCP 격리 환경에서 전체 `GetUpTests` 212회와
`UserStory1RuleConfigurationUITests` 13개가 실패·skip 없이 통과했다.

2026-08-27 T121에서 신규 규칙 생성 시 주입된 현재 현지 시·분과 15분 뒤 종료 시각, 자정 초과를
단위 테스트로 검증했다. 직접 입력 이름으로 chip이 바뀌고 이름 field를 닫은 뒤 chip 재탭으로 기존
이름을 유지해 다시 편집하는 UI 회귀를 추가했다. 홈 외부 `ScrollView`를 제거하고 규칙이 하나면
`TabView`·page indicator·`좌우로 밀어 보기`를 생성하지 않되, 세 규칙 pager의 양방향 swipe는
유지되는지 함께 검증했다. 격리 DerivedData `/tmp/getup-t121-tests`에서 전체 `GetUpTests` 211개가
실패·skip 없이 통과했고 Swift Testing 동적 인자를 포함한 device configuration 실행은 245회
통과했다. `UserStory1RuleConfigurationUITests` 12개도 실패·skip 없이 통과했다. Simulator 자동
부팅 중 두 차례 test runner `Busy` 오류가 있었으나 명시적 부팅 뒤 정상 실행됐으며, 반복된 LLDB
version-store warning은 테스트 판정에 영향을 주지 않았다.

2026-08-26 T120에서 앱 비실행 시간 경계의 각 단계를 App Group에 기록했다. 첫 실기기 재현은 규칙·
위치 로드는 정상이지만 extension Family Controls가 `notDetermined`여서 `missingPermissions`로 종료된
사실을 확인했다. 최근 앱 snapshot의 Family Controls가 `approved`이면 이 미결정 값만 보완하고 현재
`denied`는 우선하도록 수정했다. 수정 뒤 시작 전 Shield를 비우고 앱을 종료한 실기기 시간 경계에서
메인 앱 없이 monitor extension이 실행돼 `conditionsSatisfied`, 원하는 규칙 1개, `completed`를
기록했고 Shield Configuration·Action extension 실행과 자동 Shield 경로를 확인했다.
격리 DerivedData `/tmp/getup-interval-start-final-tests`의 전체 `GetUpTests` 209개가 실패·skip 없이
통과했고 Swift Testing 동적 인자를 포함한 device configuration 실행은 243회 통과했다.

2026-08-26 T119에서 실기기 `GetUpDeviceActivityMonitor` 프로세스 실행을 확인해 callback 내부 권한
평가로 원인을 좁혔다. 메인 앱이 최신 권한 snapshot을 App Group에 기록하고, extension이 위치 권한을
`notDetermined`로 읽을 때 24시간 미만의 앱 위치 권한·정확도만 보완하도록 수정했다. 현재 Family
Controls 철회와 명시적 위치 권한은 항상 우선한다. 격리 DerivedData의 전체 `GetUpTests` 208개가
실패·skip 없이 통과했고 동적 인자 포함 242회가 통과했다. iPhone 17 iOS 26.6.1용 서명 build·설치,
앱 1회 실행과 정상 종료까지 성공했으며 실제 다음 설정 시간 shield 표시는 재검증 대기다.

2026-08-26 T117 반경 변경과 T118 시간 시작 동기 적용을 같은 브랜치로 합친 상태에서 전체
`GetUpTests` 203회가 실패·skip 없이 통과했다. 반경 slider를 100m→250m→500m→1km로 조절하고 저장
요약을 확인하는 UI 회귀 1개도 통과했으며, 앱과 세 Screen Time 확장을 포함한 Simulator build가
성공했다. 두 변경은 현재 브랜치에서 함께 유지된다.

2026-08-26 T117에서 `RadiusOption`과 slider의 selectable value를 100m·250m·500m·1km로 교체하고,
validator가 이 네 값만 허용하며 위치 판정 parameterized test가 모든 새 반경을 실행하도록 갱신했다.
격리 DerivedData에서 전체 `GetUpTests` 193개 test case(동적 인자 포함 227회)가 실패·skip 없이
통과했고, UI 회귀에서 slider를 100m→250m→500m→1km로 조절한 뒤 저장 요약이 1km를 유지함을
확인했다. 반복된 LLDB version-store warning은 테스트 판정에 영향을 주지 않았다. 기존 2km·3km·
4km·5km 저장값은 사용자 결정에 따라 migration하거나 복원하지 않는다.

2026-08-26 T118에서 설정 시간이 지나도 Screen Time 제한이 시작되지 않는 실기기 회귀를 분석했다.
기존 시작 callback은 unstructured `Task`만 예약하고 반환했으며 그 Task가 먼저 전체 일정을 제거·
재등록하고 위치를 갱신한 뒤 제한을 적용해 extension 종료와 callback 재진입에 취약했다. callback
반환 전에 현재 schema 공유 snapshot·권한을 읽어 모든 규칙을 공통 순수 평가기로 계산하고, 단일
store에 제한 대상 합집합을 쓰고 read-back을 확인하도록 변경했다. 시작 callback에서는 일정·region
전체 복구를 호출하지 않는다. 만족 규칙 합집합 적용, 위치 외부·권한 거부 미적용, snapshot 실패 시
기존 상태 보존·store read-back 실패 시 상태 미저장을 포함한 adapter·coordinator 대상 테스트 24개가
실패·skip 없이 통과했다. 전체 `GetUpTests` 203회 실행도 실패·skip 없이 통과했고, 앱과 세 Screen
Time 확장을 포함한 Simulator build도 통과했다. 실제 callback·system shield 반영은 수정 빌드의
실기기 재검증이 남았다.

2026-08-26 T115에서 적용 revision set이 그대로여도 활성 규칙이 있으면 adapter의 idempotent store
read-back·reconcile을 실행하도록 변경했다. App Group 상태만 활성이고 실제 application shield가 빈
경우 동일 selection을 다시 쓰는 회귀를 추가했으며, 논리 상태가 같으면 transition measurement는
중복 생성하지 않는다.

같은 날 T116에서 실기기 위치 이탈 뒤 나서 앱에 진입해야 제한이 해제된다는 사용자 관찰을 재현 경로로
분석했다. 기존 `SystemLocationRegionMonitor`는 region을 등록하지만 `didEnterRegion`·`didExitRegion`
delegate가 전혀 없어 백그라운드에서 `RestrictionCoordinator`가 실행되지 않았다. 앱 launch 상주
`LocationRegionAppDelegate`와 `LocationRegionEventHandler`를 추가해 현재 GetUp 규칙의 region 전이를
`.regionEvent` snapshot으로 저장하고 즉시 제한 합집합을 재평가한다. 외부 namespace·stale event는
무시한다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 195개(동적 실행 포함 238회)가
실패·skip 없이 통과했고, 앱과 세 Screen Time 확장을 포함한 generic Simulator build도 통과했다.
실제 background·시스템 종료 상태의 callback 전달과 shield 해제는 수정 빌드 실기기 재검증이 남았다.

2026-08-26 T084에서 `GetUp.xctestplan`의 `GetUpTests`와 `GetUpUITests`를 iPhone 17 Pro iOS 26.5
Simulator에서 순차 실행했다. 단위·통합 193개와 UI 41개, 총 234개 test case가 모두 통과했고 실패·
skip·expected failure는 0개였다. Swift Testing 동적 인자를 포함한 device configuration 실행 수는
277회이며 전체 소요 시간은 약 284.6초였다. 가장 긴 UI test는 입력 검증·앱 선택 시나리오 13.82초로
통과했다. 17개 warning은 Apple 서명 XCTest 주입 binary를 strip하지 않는 Simulator build 경고이며
테스트 판정에 영향을 주지 않았다. 실제 Family Controls picker·system shield, 위치 region event,
background/terminated·재부팅·권한 철회와 실기기 Dynamic Type·VoiceOver는 T083·T085 범위로 남긴다.

2026-08-26 T114에서 T113의 규칙별 named store 전환 뒤 실기기에서 제한이 전혀 적용되지 않는 회귀를
확인했다. 실제 제한 적용 경로를 기존 단일 `getup.restriction` 합집합 store로 복원했다. 종료 callback은
현재 적용 상태에서 마지막 활성 규칙이 끝난 경우에만 단일 store와 상태를 동기적으로 비우며, 다른
규칙이 남거나 stale callback이면 store를 건드리지 않고 기존 coordinator가 전체 합집합을 다시
계산한다. 전체 `GetUpTests` 193개(동적 실행 포함 236회)가 실패·skip 없이 통과했고 앱·확장 generic
build도 통과했다.
사용자가 수정 빌드의 실기기에서 Screen Time 제한이 다시 정상 적용되고, 설정 시간이 지난 뒤 시간
종료 자동 해제도 정상 동작함을 확인했다. 이는 기능 경로의 실기기 확인이며 T083의 100회 지연 계측
완료를 의미하지는 않는다.

2026-08-26 T113에서 기존 단일 `getup.restriction` 합집합 store를 활성 규칙별
`getup.restriction.<rule UUID>` store로 분리했다. `intervalDidEnd`는 activity name에서 rule ID를
해석해 해당 store를 callback 안에서 동기적으로 비우고 App Group 적용 상태를 갱신한다. 다른 활성
규칙의 store는 유지하며, 기존 합집합 store는 남은 규칙별 store가 모두 확인된 경우에만 제거하고
그렇지 않으면 공통 coordinator 재평가로 넘긴다. adapter와 종료 handler의 단위·통합 회귀를 포함한
전체 `GetUpTests` 194개(동적 실행 포함 237회)가 실패·skip 없이 통과했다. 앱·확장 generic build도
통과했다. 실제 기기에서 종료 구간 밖 첫 사용 시 callback 전달과 대상 앱 shield 해제는 T083·T085
인수 범위로 남긴다.

2026-08-26 T112에서 홈 빈 상태 설명을 `밖으로 나가면 제한된 앱이 다시 열려요`로 변경했다. 위치
선택 화면의 56pt `적용` CTA는 채워진 shape를 `Button` label 내부로 이동해 좌측 6% 탭에서도 규칙
편집 화면으로 복귀하도록 보정했다. Shield extension의 기존 `GETUP` wordmark asset을 새
`NaseoShieldLogo` SVG로 교체하고 새 asset 이름으로 로드해 이전 이름과의 충돌을 피했다. 구현 전
홈 문구와 위치 좌측 탭 UI 회귀 2건이 실패했고 구현 후 모두 통과했다. iOS Simulator generic build와
US1 홈·규칙 구성 UI 테스트 11개가 모두 통과했다. extension `Assets.car`의 1x 88×88, 2x 176×176,
3x 264×264 `NaseoShieldLogo` rendition도 확인했다. string catalog JSON, `Info.plist`와 diff 검사도
통과했다.

2026-08-26 T111에서 홈 header를 `나서`, 빈 상태를 `READY TO STEP OUT`·`밖으로 나설 첫 규칙을
만들어보세요`·`집을 나서면 방해 앱이 다시 열려요`로 변경하고, 카드의 장소 행동은 `밖으로 나서면`으로
통일했다. Family Controls·위치·Background App Refresh 안내와 Settings 목업, 위치 권한 설명,
`CFBundleDisplayName`과 관련 VoiceOver 문구도 `나서`로 변경했다. Shield 상세 제목은
`%@에서 %@ 밖으로 나서세요`, fallback은 `밖으로 나설 시간이에요`로 보정하되 해제 조건 설명은
유지했다. Bundle ID·App Group·target/module·영속 key와 `Icon.icon`·`GetUpShieldLogo.svg`는 변경하지
않았다. 구현 전 Shield 문구 회귀 4건이 기존 카피로 실패했고 구현 후 `GetUpTests` 190개(동적 실행
포함 233회), US1 홈·규칙 구성 UI 테스트 10개, US4 권한 안내 UI 테스트 19개가 모두 통과했다.
앱과 확장 target을 포함한 iOS Simulator generic build, `Info.plist` lint, string catalog JSON 검사와
diff 검사도 통과했다.

2026-08-26 T110에서 사용자 제공 `Icon.icon`을 GetUp 앱 target resource에 추가하고 Debug·Release의
`ASSETCATALOG_COMPILER_APPICON_NAME`을 `Icon`으로 변경했다. iOS Simulator generic build가 경고 없이
통과했으며 빌드된 `Info.plist`의 `CFBundleIconName`이 `Icon`이고 `Icon60x60@2x.png`와
`Icon76x76@2x~ipad.png`가 생성된 것을 확인했다. `Assets.car`에는 phone·pad의 default·dark·tinted
Icon Image와 light·dark·tinted IconImageStack이 포함됐다. 실제 Home Screen의 clear·tinted appearance와
wallpaper 조합은 T085 실기기 인수에서 확인한다.

2026-08-26 T109에서 종료 시간 후보를 현재 시·분·AM/PM으로 교차 필터링한 뒤 가장 가까운 유효 시간을
다시 선택해, 한 wheel 조작이 다른 wheel 값까지 바꾸던 문제를 수정했다. 세 native Picker를 각자
독립 `@State`에 바인딩하고 전체 12시간·60분·AM/PM 값을 제공하며, 선택된 구성요소 조합만
`endTime`에 반영한다. 시작→종료 화면 전환은 boundary별 identity로 새 종료 상태를 초기화한다.
15분 미만·12시간 초과 임시 조합은 자동 보정하지 않고 경고색 안내와 비활성 `완료` CTA로 적용만
차단한다. 구현 전 새 단위 회귀는 `TimePickerComponents.updating` 부재로 실패했고, UI 회귀는 기존
동작에서 AM→PM 변경 시 시가 `10`에서 `12`로 바뀌며 실패했다. 구현 후 시작 10:00에서 종료 10:15로
진입하고 분을 16으로 바꾼 뒤 AM→PM을 바꿔도 10:16이 유지되는 회귀를 통과했다. iPhone 17 Pro
iOS 26.5 Simulator에서 전체 `GetUpTests` 190개 test case(동적 파라미터 실행 포함 233회)와 US1 UI
테스트 10개가 실패·skip 없이 통과했다.

2026-08-26 T108에서 시간 설정 완료 CTA의 frame·background가 `Button` label 바깥에 있어 보이는
64pt 영역과 실제 hit area가 달랐던 문제를 수정했다. label 내부에 accent로 채운 `RoundedRectangle`과
text를 겹친 `ZStack`을 두고 label·button 전체 content shape를 지정했다. 시작 화면 버튼 좌측 8%와
종료 화면 버튼 우측 92% 좌표를 누르는 UI 회귀는 구현 전 화면 전환에 실패하고 구현 후 시작→종료→
규칙 편집 전환을 통과했다. 첨부된 다크 Shield의 흐린 `앱 닫기` 글자는 브랜드 near-black
`#090A0C`에서 순수 검정 `#000000`으로 강화해 `#F4D600` 배경과 약 `14.47:1` 계산 대비를 확보했다.
iOS Simulator generic 전체 build, iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 189개
test case(동적 파라미터 실행 포함 232회)와 US1 UI 테스트 9개가 실패·skip 없이 통과했다. 실제
Shield system compositing 결과는 T085 실기기 인수에서 다시 확인한다.

2026-08-26 T107에서 직접 입력 장소의 저장·규칙 ID 연결은 정상이며, 카테고리로 제한된 앱의
Shield callback이 제공하는 `ActivityCategoryToken`을 버리고 `ApplicationToken`만 규칙과 비교해
fallback으로 내려가던 원인을 수정했다. `ShieldContentProvider`는 앱·카테고리·웹 도메인 token을
각각 `FamilyActivitySelection`과 비교하고, application-in-category와 web-domain-in-category
callback은 제공된 두 token을 모두 전달한다. 직접 입력 `도서관`+카테고리 회귀는 구현 전 제목·설명
기대값에서 실패하고 구현 후 상세 문구로 통과했으며, 같은 누락 구조의 직접 입력 `스터디 카페`+웹
도메인 회귀도 추가했다. iOS Simulator generic 전체 build와 iPhone 17 Pro iOS 26.5 Simulator의
전체 `GetUpTests` 189개 test case(동적 파라미터 실행 포함 232회)가 실패·skip 없이 통과했다.
실제 Family Controls category/web domain callback과 system Shield 렌더링은 T085 실기기 인수에서
최종 확인한다.

2026-08-26 T106에서 실제 제한 안내 화면의 다크 고정 색을 appearance별 palette로 바꿨다. 다크는
승인된 `#08090B` 배경, 흰 제목과 `#A6A8AD` 설명을 유지하고, 라이트는 `#F5F5F7` 배경,
`#090A0C` 제목과 `#51535A` 설명을 사용한다. `.systemYellow`로 인해 라이트 모드 버튼이 어두운
올리브색으로 변하던 문제는 두 모드에 GetUp `#F4D600` 배경과 `#090A0C` label을 명시해 해결했다.
fallback 설명은 `설정한 위치에서 벗어나거나 시간이 끝나면 자동으로 다시 사용할 수 있어요.`로
수정했다. 회귀 테스트는 구현 전 새 기대 문구에서 실패하고 구현 후 통과했으며, iOS Simulator
generic 전체 build와 iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 187개 test case(동적
파라미터 실행 포함 230회)가 실패·skip 없이 통과했다. `Localizable.xcstrings` JSON과
`git diff --check`도 통과했다. `ManagedSettingsUI`가 소유하는 글꼴 크기·요소 간 padding과 실제
restricted app의 다크·라이트 렌더링, Dynamic Type·VoiceOver는 T085 실기기 인수에서 확인한다.

2026-08-26 T105에서 앱 시작의 `AppLifecycleCoordinator.restore()` 완료 뒤 `AppModel.load()`를
실행하던 직렬 순서를 반대로 바꿨다. 보호된 로컬 규칙·저장 장소와 기존 적용 상태를 읽는 즉시 홈을
표시하고, 일정·region 재등록, 규칙별 위치 fix, 권한 확인과 제한 합집합 재평가는 화면을 차단하지
않는 후속 비동기 작업으로 계속 실행한다. 복구 결과가 도착하면 홈 활성 상태와 권한 안내를 갱신하고,
시작 복구와 foreground 복구가 겹치면 `isRestoringRuntime` 경계에서 중복 실행을 생략한다. 구체
`AppLifecycleCoordinator` 대신 `AppEnvironment.RuntimeRecovery` closure를 앱 shell에 주입해 5초
지연 복구 fixture를 구성했다. 새 UI 회귀는 구현 전 홈 pager 2초 제한에서 실패했고 구현 후 같은
조건에서 홈이 먼저 표시되고 전체 로딩 문구가 사라짐을 통과했다. iOS Simulator generic build,
iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 187개 test case(동적 파라미터 실행 포함
230회)와 US1 UI 테스트 9개가 실패·skip 없이 통과했다. 반복된 LLDB version-store와 device build
number 경고는 결과에 영향을 주지 않았다. 실제 위치 fix와 전체 runtime 복구 latency 관찰은 T083·
T085 실기기 검증 범위를 유지한다.

2026-08-26 T104에서 승인된 Figma shield `113:2025`의 design context를 확인하고 정적 GetUp 아이콘
`113:2028`을 88×88 SVG로 직접 export했다. Shield Configuration extension 전용 asset catalog에
vector 보존 자산으로 추가하고 `figure.stand` SF Symbol을 원본 색상 SVG로 교체했다. 회색으로 보이던
`.systemMaterialDark` blur를 제거하고 배경을 정확한 `#08090B`로 수정했으며 제목·설명·시스템
`앱 닫기` 계약은 유지했다. iOS Simulator generic build가 통과했고 생성된
`GetUpShieldConfiguration.appex/Assets.car`에서 `GetUpShieldLogo`의 1x 88×88, 2x 176×176,
3x 264×264 rendition을 확인했다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 187개
test case(동적 파라미터 실행 포함 230회)가 실패·skip 없이 통과했다. 첫 sandbox build는
`CoreSimulatorService` 접근 제한으로 asset compile 전에 중단됐고 sandbox 밖에서 재실행해 통과했다.
실제 restricted app의 system-owned layout, Dynamic Type·VoiceOver와 닫기 동작은 T085 실기기
인수에서 계속 검증한다.

2026-08-26 T103에서 시작·종료 시각 설정 화면 root의 `ScrollView`를 고정 `VStack`으로 교체해
화면 전체가 움직이지 않고 세 native wheel만 조작되게 했다. 시작 화면의 `완료`는 현재 destination을
종료 시각 화면으로 전환하고, 종료 화면의 `완료`가 규칙 편집 화면으로 복귀한다. native wheel 위에
58pt 불투명 선택 행과 선택값을 다시 그리던 overlay, 후속 낮은 opacity custom 강조와 각 picker의
명시적 `.clipped()`를 모두 제거하고 iOS 기본 선택 표시와 실제 wheel 값을 사용한다. iPhone 17 Pro
iOS 26.5 Simulator의 최종 XCTAttachment 캡처에서 선택값 위·아래의 시·분·AM/PM 숫자가 custom
강조와 겹치지 않고 화면 제목·완료 CTA가 고정된 것을 확인했다. 같은 Simulator의 격리 DerivedData에서
전체 `GetUpTests` 187개 test case(동적 파라미터 실행 포함 230회), US1·접근성 UI 테스트 13개와
최종 시간 흐름·캡처 UI 회귀 1개가 실패·skip 없이 통과했다. 첫 UI 실행은 sandbox의
`CoreSimulatorService` 연결 종료로 test case 실행 전에 중단됐고 동일 산출물을 sandbox 밖에서
재실행해 통과했다. 반복된 LLDB version-store와 signed binary stripping 경고는 결과에 영향을 주지
않았다.

2026-08-25 T102에서 앱 소유 push 화면의 custom 뒤로가기를 조사해 시간 선택 화면의 노란 꺾쇠와
숨긴 navigation bar를 제거하고 iOS 기본 BackButton으로 교체했다. 규칙 편집·장소 선택은 기존
시스템 navigation을 유지하고, 권한 안내처럼 root로 표시되어 복귀 행동이 없는 화면은 대상에서
제외했다. `FamilyActivitySelection`에 opaque category token이 포함되면 내부 앱 수를 추정하지 않고
편집 화면은 `여러 앱 선택됨`, 활성·비활성 홈은 `여러 앱`으로 표시한다. 카테고리가 없고 정확한
개별 선택 수를 아는 경우에는 기존 `n개 앱 선택됨`·`n개 앱` 표기를 유지한다. iPhone 17 Pro iOS
26.5 Simulator에서 규칙 편집 화면의 시스템 BackButton을 시각 확인했고, 시간 선택 화면의 시스템
navigation과 카테고리 요약은 UI 식별자 회귀로 확인했다. 같은 Simulator의 격리 DerivedData에서
전체 `GetUpTests` 187개 test case(동적 파라미터 실행 포함 230회)와 US1·US3·접근성 UI 테스트
16개가 실패·skip 없이 통과했다. UI suite의 첫 sandbox 실행은 `CoreSimulatorService` 연결 종료로
test case 실행 전에 중단됐고, 동일 산출물을 sandbox 밖에서 다시 실행해 전부 통과했다. 반복된 LLDB
version-store와 signed extension stripping 경고는 결과에 영향을 주지 않았다.

2026-08-25 T101에서 활성·비활성 홈 카드의 중복 요일 formatter를 `HomeWeekdayFormatter`로 통합하고
월요일부터 일요일까지의 최대 연속 구간을 `MON-FRI`, `MON-SUN`, `SAT-SUN`, `WED-FRI`처럼
축약하도록 변경했다. 분리된 단일 요일과 구간은 ` · `로 구분한다. 사진에서 확인된
`restriction_status.*`·`restriction_guard.*` 노출은 `Localizable.xcstrings`의 한국어 source와
Xcode project의 영어 development region 불일치가 원인이었다. development region을 `ko`로 맞추고
활성 상태·수정 차단·guard 필수 문구에 한국어 `defaultValue`를 추가했다. 영어 기기 언어를 강제한
US3 UI 회귀와 iPhone 17 Pro iOS 26.5 Simulator 시각 대조에서 `현재 활성화됨`,
`규칙 적용 중 수정 불가`, `RULE 1 OF 1 · MON-FRI`가 표시됐다. 같은 Simulator의 격리
DerivedData에서 전체 `GetUpTests` 186개 test case(동적 파라미터 실행 포함 229회)와 US1·US3·접근성
UI 테스트 15개가 실패·skip 없이 통과했다. 반복된 LLDB version-store 경고는 결과에 영향을 주지
않았다.

2026-08-25 T100에서 승인된 Figma 시작 시각 `80:2010`과 종료 시각 `80:2033`을 기준으로 기존 large
sheet를 전용 navigation destination으로 교체했다. app-owned 화면의 시스템 Liquid Glass 뒤로가기를
제거하고 노란 꺾쇠, editorial header, 410pt wheel card, 시·분·AM/PM 세 열을 가로지르는 단일 accent
선택 행과 64pt 완료 CTA를 적용했다. native wheel interaction은 유지하며 시작·종료 화면을 iPhone 17
Pro iOS 26.5 Simulator에서 시각 대조했다. 같은 Simulator의 격리 DerivedData에서 전체
`GetUpTests` 185개 test case(동적 파라미터 실행 포함 228회), US1 UI 테스트 7개와 접근성 UI 테스트
5개가 실패·skip 없이 통과했다. 접근성 UI 테스트의 첫 실행은 sandbox의 CoreSimulatorService 연결
종료로 test case 실행 전 종료됐고, 동일 산출물을 sandbox 밖에서 다시 실행해 전부 통과했다. 반복된
LLDB version-store 경고는 테스트 결과에 영향을 주지 않았다.

2026-08-25 T099에서 `FamilyActivitySelection`의 개별 앱·카테고리·웹 도메인 token 수를 공통 제한
대상 수로 계산하도록 편집 모델, 저장 service, 홈 모델과 선택 adapter의 기본 동작을 통일했다.
카테고리는 `ManagedSettingsStore.shield.applicationCategories = .specific(...)`, 웹 도메인은
`shield.webDomains`로 적용하고 여러 활성 규칙의 각 token 집합을 합친다. 활성 rule revision이 같아도
실제 GetUp store에 카테고리 등 기대 shield가 누락되면 다시 적용하며, 해제 시 세 shield 종류를 함께
지운다. iPhone 17 Pro iOS 26.5 Simulator의 격리 DerivedData에서 전체 `GetUpTests` 185개 test case,
동적 파라미터 실행 포함 총 228회가 실패·skip 없이 통과했다. 기본 DerivedData의 첫 대상 실행은
기존 증분 산출물의 `PermissionGuideModel` 심볼 불일치로 링크에 실패했지만 새 격리 DerivedData의
전체 빌드·테스트는 통과했다.

2026-08-25 T098에서 활성 규칙 홈 상태를 `현재 활성화됨`, 수정 차단 버튼을
`규칙 적용 중 수정 불가`로 변경했다. 활성·비활성 카드 버튼의 label이 전체 배경과 동일한 hit area를
갖도록 구성해 텍스트 바깥을 눌러도 동작하며, 규칙 추가·수정 화면 완료 CTA는 별도 wrapper 안의
56pt plain button으로 다른 주요 CTA와 높이를 통일했다. 홈 pager는 카드 폭과 20pt 정렬을 유지하면서
`TabView` viewport만 화면 좌우 끝까지 확장해 swipe 중 좌우 여백 clip을 제거했다. iPhone 17 Pro
iOS 26.5 Simulator의 격리 DerivedData에서 전체 `GetUpTests` 178개와 US1·US3·접근성 UI 테스트
14개, 동적 파라미터 실행 포함 총 235회가 실패·skip 없이 통과했다. Xcode의 LLDB version-store
경고는 반복됐지만 결과에는 영향을 주지 않았다.

2026-08-25 T097에서 새 장소 화면은 저장 장소가 없을 때 사용자 현재 위치를 한 번 조회해 지도 중심과
핀으로 사용하고, 기존 저장 장소 편집은 저장 좌표를 보존하도록 변경했다. `집`·`회사`·저장 장소·
`직접 입력`은 모델의 단일 선택 상태로 색상과 접근성 선택 trait를 유지한다. 장소 이름이 없을 때
`장소 이름을 입력해 주세요.`를 한 번만 표시해 기존 장문과 중복 출력을 제거했다. 제한 앱 선택 행은
Family Controls 승인 상태에서만 `FamilyActivityPicker`를 열고, `notDetermined`·`denied`에서는 기존
권한 상세 화면으로 전환한다. iPhone 17 Pro iOS 26.5 Simulator의 격리 DerivedData에서 전체
`GetUpTests` 178개와 `UserStory1RuleConfigurationUITests` 6개, 동적 파라미터 실행 포함 총 227회가
실패·skip 없이 통과했다. Xcode의 LLDB version-store 경고는 반복됐지만 결과에는 영향을 주지 않았다.

2026-08-25 T096에서 `PermissionOnboardingStateStore`의 영구 상태를 최초 표시 표식이 아닌 완료 표식으로
교체하고, `PermissionGuideLaunchRouter`가 이 표식만으로 온보딩과 일반 복구를 구분하도록 변경했다.
마지막 `백그라운드 새로 고침을 확인해 주세요` 화면은 승인·제한 상태 모두 `시작하기`를 표시하며,
탭할 때 완료를 저장하고 홈으로 이동한다. 그 전에 앱을 종료하면 다음 실행에서 권한 개요부터 다시
시작하고, 완료 뒤 재실행하면 승인 상태에서 홈으로 바로 진입한다. 권한이 이미 결정되었다는 사실만으로
완료를 추정하지 않는다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 175개 test case
(동적 파라미터 실행 포함 218회), `UserStory4PermissionGuidanceUITests` 19개와 최대 Dynamic Type 권한
복구 접근성 UI test 1개가 실패·skip 없이 통과했다. Xcode의 LLDB version-store 경고는 반복됐지만
결과에는 영향을 주지 않았다.

2026-08-25 T095에서 사용자가 승인한 Figma
`US4 / 권한 요청 클릭 유도 · 하이파이 제안 · 승인 대기`(`204:2014`)를 구현 기준으로 확정했다.
Family Controls, 위치 `앱을 사용하는 동안 허용`, 위치 `항상 허용으로 변경` 화면을 중앙 system alert
형태로 재구성하고 설명 본문은 skeleton line, 위치 preview는 Figma export asset으로 표현했다. 강조된
목업 버튼을 누른 뒤에만 실제 Family Controls 또는 Core Location 요청을 실행한다. 허용 결과는
온보딩에서 다음 권한 화면으로 자동 이동하고 일반 복구에서는 안내를 닫으며, 거부 결과는 같은 화면의
다음 주요 행동을 `설정 열기`로 바꾼다. Always 요청 뒤 권한 상태가 `whenInUse`로 유지되는 iOS 결과도
거부로 기억해 Settings 복구로 전환한다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests`
174개 test case(동적 파라미터 실행 포함 217회), `UserStory4PermissionGuidanceUITests` 18개와 최대
Dynamic Type 권한 복구 접근성 UI test 1개가 실패·skip 없이 통과했다. Family Controls·위치 사용 중·
Always 요청 화면을 직접 캡처해 승인된 중앙 배치·강조 CTA·설명 skeleton·지도 preview를 확인했다.
Xcode의 LLDB version-store 경고는 반복됐지만 결과에는 영향을 주지 않았다.

2026-08-25 T094에서 `PermissionGuideView`에 재사용 가능한 system mockup card, option, setting row와
toggle을 추가했다. Family Controls는 `Face ID로 허용`, 위치 최초 요청은 `앱을 사용하는 동안 허용`,
위치 설정은 `항상`·`정확한 위치`, Background App Refresh는 `켬`·`GetUp` toggle을 accent로 강조한다.
위치 복구 본문의 Always·정확한 위치 행동 문구도 accent로 강조하고 각 목업을 간결한 VoiceOver 설명과
고유 identifier로 제공했다. iPhone 17 Pro iOS 26.5 Simulator에서 경고 없는 app build와 US4 UI test
13개, 최대 Dynamic Type 권한 복구 접근성 UI test 1개가 실패·skip 없이 통과했으며 세 목업 화면을
직접 캡처해 레이아웃과 하단 action 노출을 확인했다.

2026-08-25 T093에서 위치 권한 요구 수준 미달 화면의 secondary action을 제거해 `설정 열기`만
표시하고, Background App Refresh 제한 화면에는 별도 `.confirm` action과
`permissionGuide.confirm` identifier를 도입해 버튼 문구를 `확인`으로 변경했다. 모델·US4 UI·최대
Dynamic Type 접근성 회귀를 함께 갱신했다. iPhone 17 Pro iOS 26.5 Simulator에서 전체
`GetUpTests` 166회와 `UserStory4PermissionGuidanceUITests` 13개, 대상 접근성 UI test 1개가 모두
실패·skip 없이 통과했다.

2026-08-25 T092에서 `PermissionOnboardingStateStore`와 `PermissionGuideLaunchRouter`를 추가해 권한
온보딩의 최초 표시를 versioned `UserDefaults` 표식으로 영구 보존했다. 첫 화면 생성 즉시 표식을
기록하므로 온보딩 도중 앱 프로세스가 종료되어도 다음 실행은 일반 복구 모드로 진입한다. 전용 단위
테스트와 동일 UI test 저장소를 사용하는 최초 실행 → 앱 종료 → 재실행 회귀가 통과했다. 기존 설치는
이미 결정된 Family Controls 또는 위치 상태를 감지해 업데이트 직후에도 온보딩을 다시 표시하지 않는다.
iPhone 17 Pro iOS 26.5 Simulator를 브라우저에 미러링해 같은 절차를 직접 수행했으며, 재실행 화면이
권한 개요 없이 홈으로 진입하는 것을 확인했다. 전체 `GetUpTests`는 동적 사례를 포함해 166회,
`UserStory4PermissionGuidanceUITests`는 재실행 회귀를 포함해 13개가 실패·skip 없이 통과했다.
이 표시 즉시 완료 정책은 T096과 `DEC-045`에서 마지막 `시작하기` 완료 정책으로 대체되었다.

2026-08-25 T091에서 `PermissionGuidePresentationMode`를 도입해 온보딩은 권한 개요와 승인 상태를
순차 확인하고, 일반 실행·foreground 복구는 승인 상태에서 아무 화면도 표시하지 않도록 분리했다.
Family Controls `denied`는 Family Controls 화면으로, Always location 미충족 또는 Full Accuracy
`reduced`는 위치 화면으로 전체 개요 없이 직접 이동한다. 일반 복구의 `notDetermined`는 자동 표시하지
않고 최초 요청은 온보딩에 한정한다. 여러 권한이 문제면 Family Controls 해결 후 위치 화면으로
전환하며, 종료된 온보딩 객체는 다음 lifecycle 갱신에서 일반 복구 모델로 교체한다. iPhone 17 Pro
iOS 26.5 Simulator에서 `PermissionGuideModelTests`와 전체 `GetUpTests`, 승인 시 홈 진입·거부 시 상세
화면 직접 진입을 포함한 `UserStory4PermissionGuidanceUITests`와 `AccessibilityUITests`가 모두
통과했고 실패·skip은 없다.

2026-08-25 T090에서 위치 권한 안내에 최초 `앱을 사용하는 동안 허용` 뒤 `항상 허용`·`정확한 위치`
설정을 명시하고, Background App Refresh는 앱별 Settings action을 제거해 시스템 전체 설정 경로만
안내하도록 변경했다. 이 진단 상태만 제한된 foreground 복귀에서는 권한 화면을 자동 표시하지 않는다.
시간 wheel과 저장 validation은 자정 초과를 포함한 15분 이상 12시간 이하 후보만 허용한다. 장소
화면은 `집`·`회사`·`직접 입력`을 항상 표시하고, 직접 입력을 같은 화면의 10자 필드로 제공하며
정규화된 중복 이름을 UI·모델·저장 service에서 거절한다. 홈과 활성 상태는 Figma의 GETUP header,
통합 456pt card, 큰 시간 위계, 조건 행, page indicator와 종료 후 수정 CTA 구조로 맞췄다.
iPhone 17 Pro iOS 26.5 Simulator에서 generic app build, 전체 `GetUpTests`, US1 UI test 5개(직접 입력
단일 재실행 포함), US2·US3·US4 UI test와 접근성 UI test가 모두 통과했고 실패·skip은 없다.
`git diff --check`와 `project.pbxproj` plist 검사도 통과했다. Xcode의 debugger version store 경고는
반복됐지만 test 결과에는 영향을 주지 않았다. 실제 Always 전환, 시스템 전체 Background App Refresh
경로와 Figma 시각 일치는 실기기에서 최종 확인해야 한다.

2026-08-25 사용자가 수정한 US4 하이파이에 맞춰 권한 개요부터 Family Controls → 위치 → Background
App Refresh를 순차 진행하도록 변경했다. Family Controls와 위치 `notDetermined`에서는 시스템 요청을
자동 표시하고 `다음`을 비활성화하며, 허용 후에는 활성 `다음`, 거부 후에는 설정 복구 행동을 표시한다.
Background App Refresh는 플랫폼에 미결정 상태가 없어 `available`과 `denied`·`restricted`로 정규화한다.
기존 앱 재선택 중간 상태는 새 승인 흐름과 중복되어 제거했다. iPhone 17 Pro iOS 26.5 Simulator에서
전체 `GetUpTests`, 권한 상태·위치 오류를 포함한 `UserStory4PermissionGuidanceUITests` 11개가 모두
통과했다. 최대 Dynamic Type 접근성 회귀에서 투명 `나중에` 버튼의 접근성 frame이 39pt로 축소되는
문제를 발견해 button 자체에 56pt frame과 content shape를 적용했고, 실패했던 접근성 테스트 재실행도
통과했다. Xcode의 debugger version store 경고는 반복됐지만 test 결과에는 영향을 주지 않았다.

2026-08-25 첫 실기기 실행에서 앱이 화면 중앙의 구형 호환 canvas로 표시되고 Family Controls
복구 버튼이 앱별 Settings로 이동하는 결함을 확인했다. 메인 앱 `Info.plist`에 `UILaunchScreen`을
선언해 native 전체 화면 실행을 복구하고, Family Controls action을
`AuthorizationCenter.requestAuthorization(for: .individual)` 직접 호출로 변경했다. 위치와
Background App Refresh의 Settings action은 유지했다. 관련 모델·UI 회귀를 갱신했으며 iPhone 17 Pro
iOS 26.5 Simulator에서 전체 `GetUpTests`와 `UserStory4PermissionGuidanceUITests`가 모두 통과했다.
`Info.plist` 문법과 `git diff --check`도 통과했다. 실제 승인 alert·생체 인증 sheet와 letterboxing
제거는 수정본을 실기기에 재설치해 확인해야 한다.

Apple Developer에서 기존 `com.getup.GetUp`을 사용할 수 없어 사용자가 등록 가능한
`com.dxyn02.GetUp` namespace로 네 App ID를 등록하고 `group.com.dxyn02.GetUp`을 모두 할당했다.
Xcode가 만든 네 target Bundle ID·entitlement 변경을 보존하고 `Configuration/Base.xcconfig`, 진단
fallback과 배포 문서를 같은 identifier로 맞췄다. 계정 등록·그룹 할당은 사용자 확인으로 기록했지만,
extension별 Family Controls `Assigned`와 `Provisioning Support`, 새 profile 및 archive의 실제 서명
entitlement는 아직 확인하지 못해 BLK-010을 유지한다. `xcodebuild -showBuildSettings`에서 네 target의
새 Bundle ID와 `group.com.dxyn02.GetUp` 상속을 확인했고, iPhone 17 Pro iOS 26.5 Simulator에서 전체
`GetUpTests` 147개 test case가 동적 인자를 포함해 총 190회 모두 통과했으며 실패·skip은 없다.

T083의 자동 계측 부분에서 `ManagedSettingsRestrictionAdapter`가 named store write 후 같은 store를
read-back해 기대 application token 집합 또는 해제 `nil`이 확인된 뒤에만 성공하도록 보강했다.
read-back 불일치 시 `storeVerificationFailed`를 반환하고 적용 상태 snapshot과 coordinator 완료
measurement를 남기지 않는 회귀 테스트 2개를 추가했다. `RestrictionLatencyTests`는 신뢰 가능한
`confirmedAt`부터 이 확인 경계까지 활성화 100회와 해제 100회를 반복했다. iPhone 17 Pro iOS 26.5
Simulator에서 활성화 p95는 0.000149초, 해제 최대값은 0.000152초로 각각 30초 기준을 통과했고,
adapter 회귀를 포함한 대상 테스트 8개가 실패·skip 없이 통과했다. 자동 테스트는 protocol test
double을 사용하므로 실제 시스템 store와 선택 앱 사용 가능 상태를 입증하지 않는다. 해당 실기기
관찰은 BLK-010이 열려 있어 미실행이며 T083은 완료 처리하지 않았다. 결과와 실기기 기록 형식은
`docs/TEST_RESULTS.md`에 분리해 기록했다. 같은 Simulator에서 전체 `GetUpTests` 147개 test case가
동적 인자를 포함해 총 190회 모두 통과했으며 실패·skip은 없다. `project.pbxproj` plist 문법과
`git diff --check`도 통과했다.

T082에서 Apple 2026 공식 Family Controls·Xcode·Developer Account 문서를 기준으로
`docs/ENTITLEMENTS.md`를 작성했다. app과 세 Screen Time extension의 resolved Bundle ID, 각 entitlement
파일, `com.apple.developer.family-controls = true`와 당시 공통 `group.com.getup.GetUp` 선언은 로컬에서
확인했다. 계정의 App ID 등록, Bundle ID별 배포 요청 `Assigned` 상태, provisioning support, App Group
할당, Development·App Store Connect profile과 서명 archive 증적은 저장소에 없어 `확인 필요`로
기록하고 BLK-010을 열었다. 문서에는 Account Holder의 네 건 요청, Account Holder·Admin의 App Group
등록·할당, 자동·수동 signing별 profile 갱신, 개인정보를 제거한 증적 기록표와 archive 검증 명령을
포함했다. 문서 task이므로 code test는 실행하지 않았으며 네 entitlement의 plist, target별 resolved
build setting, `project.pbxproj` 문법과 `git diff --check`를 검증한다.

T081에서 `DiagnosticsLogger`의 최종 출력 경계를 임의 문자열 대신 닫힌 `DiagnosticEvent`만 받는
`DiagnosticEventWriting`으로 분리했다. production writer는 기존과 동일하게 안전한 고정 code만
`OSLog`에 public 값으로 기록하며, 테스트 writer로 실제 출력 직전 메시지와 log level을 검증할 수
있다. `PrivacyLoggingTests` 3개를 추가해 좌표·경도·horizontal accuracy·장소명·opaque app token을
포함한 알 수 없는 오류 설명과 저장소 file name·schema·revision 세부값이 writer에 도달하지 않고,
모든 operation·result·error가 닫힌 code로만 기록되며 success·cancelled·failure가 각각
info·notice·error 수준을 유지하는지 확인했다. production source 전역 감사에서 `OSLog` 외 print,
별도 logger, analytics·telemetry 경로는 발견되지 않았다. iPhone 17 Pro iOS 26.5 Simulator에서 T081
전용 test 3개와 전체 `GetUpTests` 144개 test case가 동적 인자를 포함해 총 187회 모두 통과했으며
실패·skip은 없다.

T080에서 `AccessibilityUITests.swift`를 추가해 최대 Dynamic Type `AX5`에서 규칙 편집과 권한 복구의
핵심 내용·하단 행동이 손실 없이 노출되고 최소 `44×44pt` touch target을 유지하는지 검증했다. 활성
제한의 VoiceOver용 상태·제목·시간·위치·앱 수·수정 차단 정보가 시각적 읽기 순서와 명시적 문구로
제공되는지 확인하고, Reduce Motion에서도 shield 표시·닫기 행동이 동일하며 Increase Contrast와
Differentiate Without Color에서도 위치 확인 불가와 제한 유지 상태가 색상 외 문구로 남는지
검증했다. 최초 실행에서 UI test restriction probe의 `앱 닫기` 접근성 높이가 약 24pt로 확인되어
button label의 hit area를 44pt로 보강했다. iPhone 17 Pro iOS 26.5 Simulator에서 T080 전용 UI test
5개와 기존 US1~US4를 포함한 전체 `GetUpUITests` 22개가 실패·skip 없이 통과했다. 실제 물리 기기의
VoiceOver 음성 순회, Accessibility Inspector와 Increase Contrast 시각 확인은 최종 실기기 검증에서
확인한다.

T079에서 `AppLifecycleCoordinator`가 복구마다 최신 `AuthorizationSnapshot`을 읽고 일정·region·위치
snapshot·제한 합집합을 재평가한 뒤 통합 `RestrictionPresentationState`를 반환하도록 확장했다. 앱의
최초 활성화, foreground 복귀와 위치 재확인은 같은 복구 경로를 사용하며, app 전용 권한 provider로
Background App Refresh 실제 상태까지 반영해 `PermissionGuideModel`을 생성·갱신·종료한다. 필수 권한
부족을 위치 불가보다 우선하고, 제한 복구 실패 시에는 상태를 추정하지 않아 기존 안내를 보존한다.
대상 lifecycle·권한 안내·권한 adapter 16개 논리 테스트가 동적 인자 포함 21회 모두 통과했다. iPhone
17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 141개가 동적 인자 포함 총 184회, US4 UI test 6개가
모두 통과했으며 실패·skip은 없다. 실제 시스템 Settings 복귀, 권한 철회 callback과 Family Controls
재승인은 T085 실기기 인수에서 확인한다.

T078에서 `RestrictionCoordinator`가 현재 시각 기준 24시간 이상 지난 위치 근거를 평가 직전에
`unavailable`로 정규화하도록 구현했다. 유효 시간대 안에서는 동일 revision의 기존 활성 shield만
보존하고 비활성 규칙에는 새 shield를 적용하지 않으며, 시간대가 끝나면 위치가 `unavailable`이어도
기존 우선순위에 따라 shield를 해제한다. 위치 불가·자동 해제·다중 규칙 coordinator 대상 10개 논리
테스트가 동적 인자 포함 16회 모두 통과했다. 이어 iPhone 17 Pro iOS 26.5 Simulator에서 T073을
제외하지 않은 전체 `GetUpTests` 139개가 동적 인자 포함 총 182회 모두 통과했으며 실패·skip은 없다.
실제 Device Activity 종료 callback과 물리 기기 위치 오류는 T085 실기기 인수에서 확인한다.

T077에서 승인된 Figma 하이파이의 권한 개요, Family Controls 복구, Always·Full Accuracy,
Background App Refresh, 위치 `unavailable` 비활성·활성의 여섯 상태를 `PermissionGuideView`와 UI test
fixture에 연결했다. 권한 목록의 원형 표시는 `🛡️`, `📍`, `🎯`, `🔄` 이모지로 교체하고 모든 화면의
하단 action을 56pt 공통 구조와 `safeAreaInset`으로 고정했으며, 내용은 Dynamic Type에서 스크롤된다.
화면 전환 시 제목 VoiceOver focus, 접근성 identifier·label·hint, 승인 문구 localization resource도
추가했다. iPhone 17 Pro iOS 26.5 Simulator에서 `UserStory4PermissionGuidanceUITests` 6개가 모두
통과했고 실패·skip은 없다. 단위·통합 회귀는 T073의 계획된 오래된 fix red만 검증 중 target에서
제외한 뒤 즉시 복구해 `GetUpTests` 137개 test case, 동적 인자 포함 총 174회가 모두 통과했다. 실제
VoiceOver 탐색과 권한 철회·Settings 복귀는 T080·T085에서 실기기로 확인한다.

T076에서 `PermissionGuideModel`이 Family Controls, Always location, Full Accuracy와 Background App
Refresh를 승인된 `🛡️`, `📍`, `🎯`, `🔄` 순서로 합성하도록 구현했다. 필수 권한과 진단용 Background
App Refresh를 구분하고 Family Controls 복구 뒤에는 최신 승인 상태와 별개로 앱 재선택 완료 전까지
복구 상태를 유지한다. 권한 복구 우선순위, 위치 권한 결합 안내, Background App Refresh 지연·저전력
모드 안내, 위치 `unavailable`의 비활성 신규 제한 금지와 활성 제한 보존 문구, foreground 갱신 시
해결된 안내 종료를 전용 단위 테스트 7개(동적 실행 포함 8회)로 검증했다. T073의 계획된 오래된 fix
red가 회귀 실행을 막지 않도록 전체 검증 중에만 해당 파일의 Sources membership을 제외하고 즉시
복구했다. iPhone 17 Pro iOS 26.5 Simulator에서 나머지 `GetUpTests` 137개 test case가 동적 인자를
포함해 총 174회 모두 통과했으며 실패·skip은 없다. `PermissionGuideView`와 앱 진입·foreground
wiring은 T077·T079에서 연결하고, T074의 UI test 6개는 그때 green으로 전환한다. `project.pbxproj`
plist 문법과 `git diff --check`는 통과했다.

T075에서 `AuthorizationStatusReading` 경계와 `SystemAuthorizationStatusReader`를 추가해 Family Controls,
위치 승인, 정확도와 Background App Refresh 시스템 상태 읽기를 snapshot 합성과 분리했다.
`SystemAuthorizationProvider`는 매 조회마다 네 상태를 새로 합성하며, 앱 전용 `forApplication()`은
`UIApplication.backgroundRefreshStatus`의 available·denied·restricted를 도메인 상태로 정규화한다.
app extension 기본 경로는 extension 사용 금지 API를 호출하지 않으며, Permission Guide가 사용할
`UIApplication.openSettingsURLString` 기반 `settingsURL`도 앱 전용으로 제공한다. T072에 Background
App Refresh 세 상태 mapping과 설정 URL 테스트를 보강했다. T073의 계획된 오래된 fix red가 회귀
실행을 막지 않도록 검증 중에만 해당 파일의 Sources membership을 제외하고 즉시 복구했다. iPhone
17 Pro iOS 26.5 Simulator에서 앱과 Device Activity extension을 함께 빌드하고 `GetUpTests` 130개
test case가 동적 인자를 포함해 총 166회 모두 통과했으며 실패·skip은 없다. 실제 권한 철회와
Settings 이동·복귀는 T079 wiring 후 T085 실기기 인수에서 검증해야 한다. `project.pbxproj` plist
문법과 `git diff --check`는 통과했다.

T074에서 승인된 US4 하이파이의 권한 개요, Family Controls 재승인·앱 재선택, Always·Full Accuracy,
Background App Refresh 안내 4개와 위치 `unavailable` 재확인 후 비활성·활성 홈 상태로 복귀하는
2개 흐름을 `UserStory4PermissionGuidanceUITests.swift`에 작성했다. 시스템 Settings 자체는 iOS 소유
화면이므로 GetUp의 `설정 열기` 행동 노출까지만 검증하고 외부 앱 내부는 assertion하지 않는다.
T072의 계획된 compile red가 UI target 빌드를 막지 않도록 검증 중에만 해당 파일의 Sources
membership을 제외하고 즉시 복구했다. iPhone 17 Pro iOS 26.5 Simulator에서 신규 UI test 6개가
모두 실행됐으며 아직 `permissionGuide.screen`과 scenario fixture가 없어 6개 모두 실패하는 의도한
red를 확인했다. T076·T077·T079에서 모델·화면·foreground 및 위치 재확인 갱신을 연결해 green으로
전환해야 한다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다.

T073에서 위치 요청 오류, 24시간 전 fix, 음수 horizontal accuracy, 설정 반경과 오차 원의 경계
중첩을 실제 `LocationMonitor` → `LocationConditionSnapshot` → `RestrictionCoordinator` 경로에
주입하는 `LocationUnavailableTests.swift`를 작성했다. 각 원인에서 활성 제한은 그대로 유지하고
비활성 상태에는 새 제한을 적용하지 않는 계약을 각각 검증해 총 8개 동적 사례가 된다. T072의
계획된 compile red가 후속 suite 실행을 막지 않도록 검증 중에만 해당 파일의 Sources membership을
제외하고 즉시 복구했다. iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests`에서 기존 사례와
위치 오류·음수 accuracy·경계 중첩 사례 126개가 통과했고, 오래된 fix의 활성·비활성 2개는 24시간
전 근거를 `.inside`로 판정해 실패하는 의도한 red를 확인했다. 오래된 위치 최신성 판정과 상태 보존은
T078에서 green으로 전환해야 한다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다.

T072에서 `AuthorizationSnapshot`의 Family Controls, 위치 승인, 정확도, Background App Refresh
상태 조합 5개와 매 조회 시 최신 시스템 상태를 다시 합성하는 계약을
`AuthorizationAdapterTests.swift`에 작성하고 GetUpTests target에 추가했다. Background App Refresh는
진단 상태로 snapshot에 보존하되 기존 결정대로 신규 shield 적용의 필수 권한 gate에는 포함하지
않는다. iPhone 17 Pro iOS 26.5 Simulator의 대상 suite 실행은 아직 구현되지 않은
`AuthorizationStatusReading`과 `SystemAuthorizationProvider(statusReader:)` 때문에 compile 단계에서
실패해 의도한 red를 확인했으며, 이 계약은 T075에서 구현한다. 최초 sandbox 실행은
CoreSimulatorService 접근 제한으로 기기를 찾지 못했으나 Simulator 접근을 허용한 재실행에서는
환경 오류 없이 위 계약 누락으로 실패했다. `project.pbxproj` plist 문법과 `git diff --check`는
통과했으며 실패 테스트 task이므로 전체 suite는 실행하지 않았다.

T071에서 사용자가 직접 수정한 현재 US4 하이파이를 구현 기준으로 승인했다. 최종안은 화면 우측
상단 badge를 제거하고 권한 점검 목록의 `🛡️`, `📍`, `🎯`, `🔄` 표시와 기존 문구·action 구조를
유지한다. 최종 Figma wrapper를 다시 렌더링하고 여섯 화면, text node 48개, action frame 10개를
검사했으며 제품 font는 SF Pro Bold·Regular·Semibold만 사용했다. 빈 text, placeholder, shimmer와
393×852pt 화면 직접 자식 overflow는 모두 0건이고, action은 단일 화면 `y=768`, 두 행동 화면
`y=692`·`y=768`, `353×56pt`로 일치한다. 디자인 승인 문서 작업이므로 code test는 실행하지 않았다.
다음 작업은 T072~T074 실패 테스트이며 T077 UI 구현은 승인된 이 하이파이를 기준으로 진행한다.

T070에서 T069 승인 로우파이를 보존한 채 별도 Figma wrapper에 권한 점검, Family Controls 복구,
Always·Full Accuracy, Background App Refresh, 위치 `unavailable`의 비활성·활성 하이파이 6개 화면과
접근성·구현 인계 panel을 작성했다. GetUp Focus `Eyebrow`·`Title`·`Subtitle`·`Button` text style과
semantic color·radius token을 적용하고, 권한별 emoji badge와 상태 → 원인 → 제한 영향 → 복구 행동
위계를 추가했다. 전체 wrapper와 각 화면을 렌더링하고 text node 54개, icon badge 6개, action frame
10개를 감사한 결과 제품 font는 SF Pro Bold·Regular·Semibold만 사용했으며 빈 text, placeholder,
shimmer와 393×852pt 화면 직접 자식 overflow는 모두 0건이었다. action은 단일 화면 `y=768`, 두 행동
화면 `y=692`·`y=768`, `353×56pt`로 일치한다. 디자인·문서 task이므로 code test는 실행하지 않았고,
실제 Accessibility Inspector·VoiceOver·AX1~AX5·시스템 설정 복귀 focus는 구현 후 물리 기기에서
검증한다. 다음 작업은 T071 사용자 검토와 구현 승인이다.

T069에서 사용자가 직접 수정한 현재 Figma 상태를 최종 승인했다. 승인본은 권한 설명에 `🛡️`, `📍`,
`🎯`, `🔄` 표시를 사용하고 여섯 화면의 하단 action을 공통 baseline에 정렬한다. 최종 wrapper를
다시 렌더링하고 text node 48개와 버튼 frame 10개를 검사했으며, 빈 text, placeholder와 비정상
크기 text는 0건이었다. 기본 본문은 SF Pro를 유지하고 emoji가 포함된 일부 text run은 Figma에서
mixed font로 보고된다. 디자인 승인 문서 작업이므로 code test는 실행하지 않았으며 다음 작업은
T070 하이파이 제작이다.

T069 사용자 피드백에 따라 `US4-LF-01` 권한 설명 앞의 원형 bullet을 앱 사용 제한 `🛡️`, 위치 접근
`📍`, 정확한 위치 `🎯`, Background App Refresh `🔄` 표시로 교체했다. 여섯 화면의 primary 버튼은
모두 `x=20, y=692`, secondary 버튼은 `x=20, y=768`, 크기는 `353×56pt`로 고정해 내용 길이와
관계없이 같은 위치에 표시되도록 수정했다. 사용자가 Figma에서 직접 조정한 wrapper 배경과 화면
문구는 보존하고, 밝은 wrapper에서 상단 제목이 읽히도록 기존 `color/onAccent` token으로 대비만
보정했다. 반영본 자동 감사에서 text node 49개, 버튼 frame 10개를 확인했으며 SF Pro 외 서체, 빈
text, placeholder, shimmer와 화면 경계 밖 text overflow는 모두 0건이었다. 디자인·문서 변경이므로
code test는 실행하지 않았고, T069 완료 여부는 사용자 재검토와 승인 뒤 결정한다.

T068에서 기존 Figma 파일의 `GetUp Focus` local color·spacing·radius variable과 SF Pro typography를
재사용해 권한 점검, Family Controls 재승인·앱 재선택, Always·Full Accuracy 설정, Background App
Refresh 확인, 위치 `unavailable`의 비활성·활성 상태를 여섯 개 393×852pt frame으로 제작했다. 위치
확인 불가에서는 위치만을 근거로 제한 상태를 바꾸지 않고, 비활성은 새 shield 미적용, 활성은 기존
shield 보존, 시간 종료는 위치와 무관하게 해제하는 계약을 Figma panel과
`design/low-fidelity/US4-permission-location-errors.md`에 기록했다. Figma wrapper와 각 화면을
렌더링하고 text node 52개를 자동 감사한 결과 SF Pro 외 서체, 빈 text, placeholder, shimmer와 화면
경계 밖 text overflow는 모두 0건이었다. 실제 좌표·주소·앱 이름·bundle identifier·app token은
포함하지 않았다. 디자인·문서 task이므로 code test는 실행하지 않았으며 다음 작업은 T069 사용자
검토다.

T067에서 `AppModel.refreshRestrictionStatus()`가 최신 active `(ruleID, revision)` 집합을 읽은 뒤 홈의
`RestrictionStatusModel`과 현재 열린 `RuleEditorModel`의 `RestrictionModificationGuard`를 같은
snapshot 기준으로 함께 갱신하도록 연결했다. 자동 해제로 해당 revision이 active set에서 사라지면
열린 편집기의 guard가 즉시 제거되고, 편집을 닫았다가 같은 규칙에 다시 진입해 끄기·저장·삭제를
사용할 수 있다. 반대로 foreground 복구에서 규칙이 활성로 확인되면 같은 재계산 경계가 편집 guard를
다시 적용한다. `initialEditorDraft`도 최초 load가 완료된 active set에 맞춰 guard를 동기화한다.
iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 126개 test case가 동적 인자를 포함해 총
158회 모두 통과했고 실패·skip은 없다. T063 US3 UI suite의 활성 guard, 해제 후 끄기, 해제 후 삭제
3개도 모두 통과했다. `project.pbxproj` plist 검사와 `git diff --check`는 통과했다. Phase 5 US3의
시간 종료·신뢰 가능한 위치 이탈 자동 해제, 활성 중 내부 변경 거부, 해제 후 편집 재진입을 독립
검증했으며 다음 작업은 T068 US4 로우파이 제작이다.

T066에서 활성 `(ruleID, revision)`이 현재 규칙과 일치하면 `RuleEditorModel`에
`RestrictionModificationGuard`를 주입해 규칙 끄기와 저장을 거부하고, `AppModel`의 저장·삭제 경계도
같은 guard를 확인하도록 연결했다. 활성 홈의 `조건 종료 후 수정 가능` control은 승인된 네이티브
SwiftUI Alert를 열어 장소 이름·반경·종료 시각과 수정·끄기·삭제 가능 조건을 안내하고 편집 화면으로
진입하지 않는다. 비활성 편집 화면에는 `ruleEditor.enabled` toggle을 추가해 해제 후 규칙을 끄고
저장할 수 있다. `restriction_guard.*`와 `restriction_status.*` 문구는 `Localizable.xcstrings`에서
관리한다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 125개 test case가 동적 인자를
포함해 총 157회 모두 통과했고 실패·skip은 없다. T063 UI suite의 활성 guard, 시간 종료 후 끄기,
위치 이탈 후 삭제 3개도 모두 통과해 계획된 실패를 green으로 전환했다. 네이티브 Alert action에 직접
accessibility identifier를 지정하면 iOS 26 Simulator 접근성 트리에 동일 버튼이 중첩되는 현상이 있어
system-owned 제목과 label로 단일 focus target을 유지했다. 문자열 카탈로그 JSON 검사,
`project.pbxproj` plist 검사와 `git diff --check`는 통과했다. 기존에 열린 편집기의 guard를 자동 해제
뒤 최신 active set으로 갱신하는 동작은 T067에서 연결한다.

T065에서 `DeviceActivityMonitorExtension.intervalDidEnd`가 callback 진입 시각을 즉시 기록한 뒤 공통
live `RestrictionCoordinator`의 `handleTimeEvent(confirmedAt:)`를 호출하도록 연결했다. named store를
무조건 비우지 않고 저장된 모든 규칙을 현재 시각으로 재평가해 종료된 규칙은 위치 상태와 무관하게
해제하면서 다른 활성 규칙의 앱 token 합집합은 보존한다. `DependencyContainer`의 공통 coordinator
factory를 추가하고 `AppLifecycleCoordinator.live`도 같은 조립 경계를 사용하도록 정리했다. 보호
snapshot read나 live 조립이 실패하면 다른 활성 규칙을 잘못 제거하지 않고 기존 shield를 보존한다.
시간 종료 테스트의 위치 근거를 `unavailable`로 변경해 시간 우선 해제를 coordinator 수준에서
검증했다. iPhone 17 Pro iOS 26.5 Simulator에서 앱과 Device Activity extension을 함께 빌드하고 전체
`GetUpTests` 123개 test case가 동적 인자를 포함해 총 155회 모두 통과했으며 실패·skip은 없다.
실제 background·종료 상태의 `intervalDidEnd` 전달과 system shield 제거는 Simulator로 입증하지
않으며 T085 실기기 인수에서 확인해야 한다. T063 UI suite의 계획된 실패 2개는 T066·T067 구현 전까지
남아 있다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다. 다음 작업은 T066 활성 중
변경 guard와 종료 조건 안내 구현이다.

T064에서 `RestrictionCoordinator`의 time·location event에 선택적 `confirmedAt` 입력을 추가하고,
실제 제한 adapter write가 성공한 경우에만 `RestrictionTransitionMeasurement`를 반환하도록 구현했다.
측정 결과는 신뢰 가능한 event 확인 시각, effect 완료 시각, 경과 초와 `applyShield | removeShield`
분류를 제공한다. 시간 종료와 신뢰 가능한 위치 이탈은 활성 제한을 제거하며, 위치 `unavailable`과
동일 상태 반복 평가는 write·측정을 모두 생략한다. 다중 규칙에서 일부만 끝나 남은 앱 token 합집합을
다시 적용하는 경우도 사용자 관점의 부분 해제이므로 `removeShield` 측정으로 분류한다. 인자 없는 기존
coordinator 호출은 진입 시각을 자동 사용해 호환성을 유지하고 restoration은 신뢰 가능한 조건 변경
event가 아니므로 측정하지 않는다. T062 자동 해제 테스트 4개와 기존 coordinator 회귀 테스트가 모두
통과했으며, iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 123개 test case가 동적 인자를
포함해 총 155회 모두 통과했고 실패·skip은 없다. T063 UI suite의 계획된 실패 2개는 T066·T067
구현 전까지 남아 있어 전체 UI suite는 실행하지 않았다. `project.pbxproj` plist 문법과
`git diff --check`는 통과했다. 다음 작업은 T065 Device Activity interval 종료 연결이다.

T063에서 `UserStory3AutoReleaseUITests.swift`에 활성 규칙의 공통 변경 guard Alert, 시간 종료 뒤
편집·끄기 허용, 신뢰 가능한 위치 이탈 뒤 정상 삭제 허용을 검증하는 UI test 3개를 추가했다. 활성
상태에서는 `restrictionStatus.editDisabled` control이 `제한 중에는 수정할 수 없어요` Alert를 열고
장소·반경·종료 시각과 수정·끄기·삭제 거부를 함께 안내한 뒤 편집 화면으로 진입하지 않아야 한다.
해제 상태에서는 `ruleEditor.enabled` toggle로 규칙을 끄고 저장할 수 있으며, 삭제는 기존 파괴적
확인 Alert를 거쳐 완료되어야 한다. T062의 계획된 red 단위 테스트를 검증 중에만 target에서 제외하고
iPhone 17 Pro iOS 26.5 Simulator에서 T063 suite를 실행한 결과 3개 중 해제 후 삭제 1개는 통과했고,
활성 guard control과 해제 후 enabled toggle이 아직 없어 2개가 예상 지점에서 실패했으며 skip은
없었다. T062 target membership은 즉시 복구했다. T066·T067에서 guard·끄기 UI와 상태 갱신을 연결한
뒤 green으로 전환해야 하며, T062가 compile red이므로 전체 suite는 실행하지 않았다.
`project.pbxproj` plist 문법과 `git diff --check`는 통과했다. 다음 작업은 T064 자동 해제 core
구현이다.

T062에서 `RestrictionReleaseTests.swift`에 시간 종료와 신뢰 가능한 위치 이탈이 활성 제한을
해제하는 경로, 위치 `unavailable`이 기존 제한을 보존하는 경로, 같은 종료 event 반복 평가가
해제·측정을 중복하지 않는 경로의 실패 테스트 4개를 추가했다. 시간·위치 event가 신뢰 가능한 조건
변경 확인 시각을 `confirmedAt`으로 전달하고 실제 remove effect가 발생한 결과에만
`transitionMeasurement`를 제공하는 계약을 명시했다. iPhone 17 Pro iOS 26.5 Simulator에서 새 suite를
실행해 현재 `RestrictionCoordinator`에 `confirmedAt` event API가 없어 compile 단계에서 실패하는
계획된 red 상태를 확인했다. 따라서 4개 테스트는 아직 실행되지 않았고 전체 suite도 실행하지
않았다. T064에서 event 시각·remove effect·측정 결과를 구현한 뒤 green으로 전환해야 한다.
`project.pbxproj` plist 문법과 `git diff --check`는 통과했다. 다음 작업은 T063 실패 UI test다.

T061에서 사용자가 T060의 정상 삭제 버튼·확인 Alert와 활성 삭제 guard 공통 진입점 동기화 결과를
구현 기준으로 승인했다. `design/high-fidelity/US1-rule-configuration.md`와
`design/high-fidelity/US3-auto-release.md`의 검토 기록·승인 상태·미해결 항목을 갱신하고 T061을
완료 처리했다. 디자인 승인 문서 작업이므로 code test는 실행하지 않았으며 다음 작업은 T062 자동
해제 core 실패 테스트 작성이다.

T060에서 T037의 실제 `RuleEditorView`를 기준으로 최종 US1 wrapper에 `HF-FLOW-12 / 규칙 삭제`,
`HF-FLOW-13 / 규칙 삭제 확인`과 상태·문구·접근성·구현 인계 panel을 추가했다. 비활성 규칙은
`GetUp Focus/color/error`의 353×52pt bordered 버튼에서 `규칙을 삭제할까요?` Alert로 이어지고,
저장 장소 보존 설명과 `취소`·공식 `Mode=Light, Type=Destructive` 삭제 행동을 제공한다. 활성 규칙은
같은 삭제 진입점에서 기존 `US3-HF-02` 종료 조건 guard Alert로 분기하도록 문서화했다. 두 화면과
규격 panel을 개별 렌더링했으며 text node 70개에서 SF Pro 외 서체, 빈 text, placeholder와 직접 자식
overflow가 모두 0건이었다. Figma·문서 task이므로 code test는 실행하지 않았다. 다음 작업은 T061
사용자 검토다.

규칙 삭제 UI가 T037에서 코드에 보완됐지만 최종 US1 Figma wrapper에는 반영되지 않은 정합성 누락을
확인했다. 정상 삭제 버튼·파괴적 확인 Alert는 활성 중 삭제 거부 UI의 진입 기준이므로 마무리 대조
단계까지 미루지 않고 T060 Figma 동기화와 T061 사용자 검토를 US3 테스트보다 앞에 추가했다. 기존
미완료 task는 실행 순서를 유지해 T062~T089로 재번호화했다. 이번 변경은 계획·상태 문서 작업이므로
code test는 실행하지 않았으며, 다음 작업은 T060이다.

T059에서 사용자가 완료 전용 UI를 제외한 US3 하이파이를 구현 기준으로 승인했다. Figma wrapper와
규격 panel을 `승인됨`으로 갱신하고 `design/high-fidelity/US3-auto-release.md`에 승인자·승인일·미해결
항목 없음 상태를 기록했다. 승인 문구 반영 뒤 wrapper를 다시 렌더링했으며, 전체 64개 text node에서
SF Pro 외 서체, 누락 font, 빈 text, placeholder, shimmer와 화면 경계 overflow가 모두 0건이었다.
Apple iOS 26 `Alert` component instance와 Accessibility annotation도 유지됨을 확인했다. 디자인·문서
승인 task이므로 code test는 실행하지 않았다. 다음은 T060·T061 디자인 정합성 보정과 승인,
T062·T063 테스트 작성이며, 이후 T066·T067 UI
구현은 이 승인본을 기준으로 진행한다.

T058에서 승인된 US3 로우파이와 기존 US2 활성 홈 하이파이를 기준으로 활성·guarded 홈과 iOS 26
공식 `Alert` component를 사용하는 편집 차단 상태를 제작했다. 시간 종료 또는 신뢰 가능한 위치 이탈
뒤에는 활성 규칙의 앱 token 합집합을 다시 계산하고, 별도 완료 화면·배너·toast·VoiceOver
announcement 없이 기존 예정·비활성 홈으로 복귀하는 승인 동작을 유지했다. VoiceOver 읽기 순서,
Alert dismiss 뒤 focus 복귀, AX1–AX5 자연 줄바꿈, Increase Contrast, Reduce Motion과 최소 44×44pt
touch target을 Figma 규격·Accessibility annotation과 `design/high-fidelity/US3-auto-release.md`에
기록했다. wrapper와 두 화면·규격 panel을 개별 렌더링했으며, 전체 64개 text node에서 SF Pro 외
서체, 누락 font, 빈 text, placeholder, shimmer와 화면 경계 overflow가 모두 0건이었다. 디자인·문서
task이므로 code test는 실행하지 않았다. 이후 T059 승인으로 구현 gate를 해제했으며 T060·T061
디자인 정합성 보정 뒤 T062·T063 테스트를 먼저 작성하고 T066·T067 UI 구현을 시작한다.

T057에서 사용자가 자동 해제 완료 전용 UI 제거 반영본을 승인했다. Figma 보드와
`design/low-fidelity/US3-auto-release.md`를 `승인됨`으로 갱신하고, 전용 화면·배너·toast 없이 조건
종료 뒤 기존 예정·비활성 홈으로 복귀하는 흐름을 T058 이후 구현 기준으로 확정했다. 승인 상태
텍스트를 반영한 Figma wrapper를 다시 렌더링해 레이아웃을 확인했다. 디자인·문서 승인 task이므로
code test는 실행하지 않았다.

T057 사용자 피드백에 따라 자동 해제 완료를 알리는 전용 화면은 불필요하다고 결정했다. Figma에서
`AUTO RELEASE COMPLETE` frame을 삭제하고, 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 제한 합집합을
재계산한 다음 활성 표시와 guard가 제거된 기존 예정·비활성 홈으로 복귀하도록 흐름과 설명을
갱신했다. 완료 전용 화면·배너·toast와 별도 VoiceOver announcement는 제공하지 않는다. 변경된
wrapper와 남은 393×852pt 화면 두 개를 다시 렌더링했고, 전체 64개 text node에서 누락 font, 빈 text,
임시 placeholder와 화면 경계 overflow가 모두 0건이었다. 디자인·문서 변경이므로 code test는
실행하지 않았다. 이후 사용자 승인으로 T057을 완료 처리했으며 T058 하이파이를 시작할 수 있다.

T056에서 기존 US2 활성 홈 카드와 iOS 26 공식 `Alert` component를 재사용해 `활성 홈 → 규칙 수정
시도 → 편집 차단과 종료 조건 안내 → 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 기존 홈 복귀` 흐름의
로우파이를 Figma에 제작했다. 활성 규칙의 편집·끄기·삭제를 같은 guard로 거부하고, Alert에서
`집 1km 밖` 또는 `09:00 AM 이후`라는 실제 종료 조건을 안내한다. 두 해제 경로는 현재 활성 규칙의
앱 token 합집합을 다시 계산하고, 별도 완료 UI 없이 활성 표시와 guard를 제거한 기존 홈 상태로
합류한다. 393×852pt 화면 두 개와 상태 설명 panel을 렌더링했고, 전체 64개 text node에서 누락 font,
빈 text, 임시 placeholder와 화면 경계 overflow가 모두 0건이었다. 디자인·문서 task이므로 code
test는 실행하지 않았다. 이후 T057 승인본을 확정해 T058 하이파이를 시작할 수 있다.

T055에서 shared 적용 상태의 `(ruleID, revision)`과 현재 규칙 revision이 정확히 일치할 때만 활성으로
표시하는 `RestrictionStatusModel`을 추가했다. 앱 최초 load, 규칙 저장 직후 runtime 동기화, foreground
복귀 뒤 적용 상태를 다시 읽고, 활성 규칙은 승인된 `RESTRICTION ACTIVE` 카드에서 장소·반경, 종료
시각, 제한 앱 개수와 `조건 종료 후 수정 가능` 안내를 표시한다. 비활성 규칙은 기존 홈 카드와 편집
흐름을 유지한다. Dynamic Type 접근성 크기에서는 pager 높이를 확장하고 정보가 축약되지 않도록 했으며,
T045 전용 Simulator probe는 `--ui-test-scenario restriction-activation`에서만 제공한다. 모델 단위
테스트는 구현 전 계획된 compile 실패를 확인한 뒤 green으로 전환했고, T045 UI 테스트 3개에서
시간 활성·위치 내부의 대상 앱 shield, 비대상 앱 통과, 시간 또는 위치 조건 불충족 시 비활성을 모두
검증했다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 119개가 동적 인자를 포함해 총
151회 모두 통과했고 실패·skip은 없다. 기본 글자 크기 Simulator 캡처로 활성 카드의 색상, 정보 순서와
시간 표기 잘림이 없음을 확인했다. 실제 App Group 적용 상태, restricted app system shield와 물리 기기
VoiceOver·최대 Dynamic Type은 T085 인수에서 확인해야 한다. `project.pbxproj` plist 문법과
`git diff --check`도 통과했다.

T054에서 `RuleConfigurationService`가 저장 장소와 규칙 collection을 모두 성공적으로 기록한 뒤에만
새 rule revision을 runtime 동기화 경계로 전달하도록 확장했다. `AppModel`은 이 경계를 보존하고 live
`AppEnvironment`는 기존 `AppLifecycleCoordinator.restore()`에 연결한다. 따라서 저장 직후 GetUp 소유
일정·region을 초기화하고 저장된 모든 활성 규칙을 새 revision으로 재등록하며, `.restoration` fresh
위치 근거를 갱신한 다음 `RestrictionCoordinator`로 제한 앱 합집합을 즉시 재평가한다. 규칙 snapshot
write가 실패하면 runtime 동기화는 호출되지 않고, 개별 schedule·location 등록 실패는 DEC-028의
best-effort 복구를 따라 다른 규칙과 최종 제한 재평가를 막지 않는다. 저장 완료 후 새 revision 전달,
두 snapshot 이전 호출 금지, 규칙 write 실패 시 runtime 미변경과 `AppModel` 전달을 테스트했다.
iPhone 17 Pro iOS 26.5 Simulator에서 앱과 모든 extension을 함께 build하고 전체 `GetUpTests` 117개가
동적 인자를 포함해 총 149회 모두 통과했으며 실패·skip은 없다. 실제 Device Activity 일정·Core
Location region 등록과 저장 즉시 shield 전환은 entitlement·Always·Full Accuracy가 적용된 실기기
인수 T085에서 확인해야 한다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T053에서 `ShieldActionResponsePolicy`와 `ShieldActionExtension`을 구현했다. 화면에 제공하는 primary
`앱 닫기` action은 `.close`를 반환하며 application·category·web domain callback이 모두 같은 정책을
사용한다. 구성 화면에는 secondary action이 없지만 시스템이 예기치 않게 secondary action을
전달하더라도 `.close`를 반환해 `.defer`, `.none`, `openParentalControlsApp`로 제한을 우회하거나
GetUp을 여는 경로를 만들지 않는다. action 처리 과정은 Managed Settings store, App Group 상태와
사용자 데이터를 읽거나 변경하지 않는다. iPhone 17 Pro iOS 26.5 Simulator에서 앱과 Shield Action
extension을 함께 build하고 전체 `GetUpTests` 115개가 동적 인자를 포함해 총 147회 모두 통과했으며
실패·skip은 없다. 실제 restricted app 위에서 primary button을 눌렀을 때의 system-owned 종료 전환은
Simulator unit test로 입증하지 않으며 T085의 Family Controls entitlement 적용 실기기 인수에서
확인해야 한다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T052에서 사용자의 BLK-009 1안 결정을 반영해 `ShieldContentProvider`와
`ShieldConfigurationExtension`을 구현했다. App Group의 규칙·장소 snapshot과 활성
`(ruleID, revision)` 집합을 동기적으로 읽고, shield를 요청한 opaque application token에 실제로
대응하는 활성 규칙만 선택한다. 단일 규칙은 장소·반경·종료 시각을 포함한 승인 문구를 표시하고,
두 개 이상이면 개수와 모든 규칙의 위치 또는 시간이 끝나야 한다는 짧은 요약을 표시한다. token이
없거나 snapshot을 읽지 못하면 장소명·앱명 등 개인정보가 없는 fallback을 사용한다. 시스템 소유
shield layout에 어두운 배경, 정적 SF Symbol, 한국어 문자열 카탈로그와 `앱 닫기` primary button을
연결했으며 이름·bundle identifier·token을 기록하는 로그는 추가하지 않았다. iPhone 17 Pro iOS
26.5 Simulator에서 앱과 Shield Configuration extension을 함께 build하고 전체 `GetUpTests` 113개가
동적 인자를 포함해 총 145회 모두 통과했으며 실패·skip은 없다. 실제 Family Controls entitlement가
있는 실기기에서의 shield 표시, Dynamic Type·VoiceOver 읽기 순서와 시각적 최종 확인은 T085 인수
검증에 남긴다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T052 착수 시 승인된 shield 하이파이·계약과 `DEC-016`의 앱 token 합집합을 대조하고 iOS 26.5 SDK의
`ManagedSettings.Application.token` 제공 여부를 확인했다. 대상 앱과 활성 규칙의 대응은 가능하지만,
두 개 이상 규칙이 같은 앱에 적용될 때 승인된 단일 장소·반경·종료 시각 문구는 실제 결합 해제
조건을 정확히 표현하지 못해 BLK-009에 기록했으며, 사용자가 1안을 선택해 해결했다.

T051에서 `DeviceActivityMonitorExtension.intervalDidStart`와 앱 foreground `scenePhase`를 공통
`AppLifecycleCoordinator`에 연결했다. 복구는 공유 규칙 snapshot read 성공 후에만 GetUp 일정·region을
초기화하고 모든 활성 규칙의 일정·region을 재등록하며, fresh fix를 rule ID별 `.restoration` 위치
condition으로 갱신한 뒤 T050 제한 합집합을 재평가한다. Family Controls의 `.approved`와 iOS 26의
`.approvedWithDataAccess`, Always·Full Accuracy를 실제 시스템 상태에서 정규화하는 복구용 권한
provider를 앱과 extension target에 추가했다. 개별 schedule·location 실패는 다른 규칙과 최종 제한
재평가를 막지 않으며, 첫 잠금 해제 전 보호 파일 read 실패는 기존 시스템 상태를 변경하지 않고
다음 event 재시도로 남긴다. iPhone 17 Pro iOS 26.5 Simulator에서 앱과 extension을 함께 build하고
전체 `GetUpTests` 110개가 동적 인자를 포함해 총 142회 모두 통과했으며 실패·skip은 없다. 최초 red
검증 시 CoreSimulator service 연결이 일시적으로 끊겼으나 권한을 허용한 최종 두 실행은 정상
통과했다. 실제 앱 종료 상태 `intervalDidStart`, background region 등록과 재부팅 후 첫 잠금 해제
event 전달은 Simulator로 입증하지 않으며 T085 실기기 인수에서 확인해야 한다.
`project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T050에서 사용자의 BLK-008 1안 결정을 반영해 `location-conditions.json`을 rule ID별 schema 2
collection으로 변경하고, rule ID가 없는 schema 1 위치 snapshot은 빈 collection으로 안전하게
해석했다. 적용 상태는 활성 `(ruleID, revision)` 집합을 추적하며, 기존 Boolean·revision만 남은
UserDefaults 상태는 `requiresReset`으로 판정해 GetUp named store를 최초 평가에서 정리한다.
`RestrictionCoordinator`는 time·location·restoration event마다 저장된 모든 규칙을 독립 평가하고,
위치 `unavailable`은 동일 revision으로 이미 활성인 규칙만 보존한 뒤 최종 활성 규칙의 application
token 합집합을 한 번 적용한다. 동시 활성, 중복 token 제거, 일부 규칙 종료 후 남은 합집합 보존,
반복 평가 무효과와 schema migration 테스트를 추가했다. iPhone 17 Pro iOS 26.5 Simulator에서 전체
`GetUpTests` 107개가 동적 인자를 포함해 총 139회 모두 통과했고 실패·skip은 없다. T045 UI test는
상태 UI와 test seam을 구현하는 T055 전까지 계획된 red 상태이므로 이번 검증 범위에서 제외했다.
`project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T050 착수 시 `RestrictionStateMachine`, `PlatformContracts.swift`, 공유 저장 계약과 다중 규칙 요구사항을
대조했다. 기존 계약은 위치 상태와 적용 shield 상태를 단일 `ruleRevision`으로만 표현해 두 개 이상의
활성 규칙 합집합을 안전하게 계산·복구할 수 없음을 확인했다. 제품 동작과 공유 저장 schema에 영향을
주는 선택이므로 구현과 task 완료 처리를 중단하고 BLK-008에 선택지와 권장안을 기록했다. 이번
세션에는 제품 코드 변경과 테스트 실행이 없다.

T049에서 `ManagedSettingsRestrictionAdapter.swift`를 앱과 Device Activity Monitor extension target에
추가했다. 고정 이름 `getup.restriction`의 `ManagedSettingsStore`에 규칙의 opaque application token만
shield로 설정하고, App Group `UserDefaults`에 적용 여부와 rule revision을 함께 기록한다. 같은
revision이 이미 적용된 경우 store와 상태 저장소 write를 모두 생략하며, 제거 시에도 GetUp named
store만 비운다. `DependencyContainer.makeRestrictionAdapter()`로 앱과 extension의 live adapter를
조립했다. iOS 26.5의 `ApplicationToken` Codable dictionary 표현에 맞게 T044 fixture를 바로잡은 뒤
해당 계약 테스트 3개가 모두 통과했다. 이어 iPhone 17 Pro iOS 26.5 Simulator에서 전체
`GetUpTests` 99개가 동적 인자를 포함해 총 131회 모두 통과했고 실패·skip은 없다. 실제 Family
Controls 승인 아래 시스템 shield 표시와 다른 제공자의 실제 named store 공존은 Simulator fake
결과로 입증하지 않으며 T083·T085의 entitlement 적용 실기기 검증에서 확인해야 한다.
`project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T048에서 `LocationMonitor.swift`를 앱 target에 추가했다. Always·Full Accuracy, region monitoring
가용성, 기기 최대 반경을 등록 전에 검사하고, 저장 장소 좌표와 규칙별 안정적인 identifier로 원형
region을 교체한다. Core Location 단발성 fix의 관측 시각·거리·horizontal accuracy를 T047 공식으로
판정해 `LocationConditionSnapshot`으로 저장하며, 오류는 좌표를 추정하지 않고 `unavailable`로
기록한다. `DependencyContainer.makeLocationMonitor()`로 live Core Location adapter와 공유 저장소를
조립했다. 기존 T043에 Always·Full Accuracy gate와 규칙별 region 교체 검증을 보강하고, T049의
계획된 red 테스트를 검증 중에만 target에서 제외했다. iPhone 17 Pro iOS 26.5 Simulator에서 7개
테스트가 동적 인자를 포함해 총 27회 모두 통과했으며 target membership은 즉시 복구했다. 중간에
종료 상태 Simulator가 `Busy` preflight 오류를 두 번 반환했으나 명시적으로 부팅한 뒤 같은 suite가
통과했다. 실제 Always 권한 prompt, Full Accuracy 상태 변경과 background·종료 상태 region event
전달은 Simulator 결과로 입증하지 않으며 T085 실기기 인수에서 검증해야 한다. `project.pbxproj`
plist 문법과 `git diff --check`도 통과했다.

T047에서 `LocationEvidenceEvaluator.swift`를 앱 target에 추가하고 중심 거리 `d`, 설정 반경 `R`,
horizontal accuracy `a`를 사용한 순수 판정을 구현했다. 음수 또는 유한하지 않은 입력은
`unavailable`, `d + a <= R`은 `inside`, `max(0, d - a) > R`은 `outside`, 나머지 경계 중첩은
`unavailable`로 분류한다. T048용 위치 snapshot 테스트와 T049의 계획된 red 테스트를 검증 중에만
제외하고 iPhone 17 Pro iOS 26.5 Simulator에서 여섯 반경별 내부·정확한 경계·외부·경계 중첩
4개 동적 테스트가 총 24회 모두 통과했으며, test source와 target membership은 즉시 복구했다.
T043의 최신 위치 snapshot 기록 테스트는 T048 구현 전까지 red 상태다. `project.pbxproj` plist
문법과 `git diff --check`도 통과했다.

T046에서 `DeviceActivityScheduleAdapter.swift`를 앱과 Device Activity Monitor extension target에
추가했다. 규칙 UUID와 요일을 포함하는 안정적인 activity name으로 선택 요일별 반복 일정을
등록하고, 동일 규칙의 이전 일정만 제거한 뒤 현재 규칙으로 복구하며, GetUp 소유 일정 전체 제거도
지원한다. 15분 미만 구간은 기존 일정 변경 전에 거부하고 자정 초과 구간의 종료 요일은 다음 날로
계산한다. 후속 T047·T048·T049의 계획된 red 테스트를 검증 중에만 target에서 제외하고 iPhone 17 Pro
iOS 26.5 Simulator에서 `DeviceActivityScheduleAdapterTests` 4개가 모두 통과했으며, target membership은
즉시 복구했다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T045에서 `UserStory2RestrictionActivationUITests.swift`에 고정된 유효 규칙과 주입 시각·위치 상태를
사용하는 3개 실패 UI test를 작성했다. 시간 활성·위치 내부에서는 선택 앱 probe만 shield로 이동하고
비선택 앱 probe는 콘텐츠로 열려야 하며, 시간 비활성·위치 내부와 시간 활성·위치 외부에서는 선택
앱도 제한 없이 열려야 한다. 이 probe는 `--ui-testing`에서만 제공하는 Simulator 검증 경계이며 실제
Managed Settings shield의 출시 증거는 후속 실기기 인수 테스트로 남긴다. 선행 red 단위 테스트
T042~T044를 검증 중에만 target에서 제외하고 iPhone 17 Pro iOS 26.5 Simulator에서 새 UI test 3개가
compile·launch된 뒤 아직 없는 `restrictionStatus`·`restrictionProbe` 요소의 `XCTAssertTrue`에서 모두
실패하는 red 상태를 확인했다. 실패 3개, 통과·skip 0개이며 target membership은 즉시 복구했다.
`project.pbxproj` plist 문법과 `git diff --check`를 통과했고, T050의 활성화 경로와 T055의 상태 UI 및
UI test seam을 연결한 뒤 다시 실행해야 한다.

T044에서 `ManagedSettingsRestrictionAdapterTests.swift`에 규칙이 선택한 opaque application token만
GetUp named store에 shield로 기록하는 경로, 같은 rule revision이 이미 적용된 경우 Managed Settings와
적용 상태 저장소에 쓰지 않는 idempotency, 다른 제공자의 named store를 보존하는 경로를 검증하는
3개 실패 테스트를 작성했다. 테스트는 앱 이름이나 bundle identifier를 해석하지 않고 Codable
`ApplicationToken`만 사용하며 `GetUpTests` target에 포함했다. 선행 red 테스트인 T042·T043을 검증
중에만 target에서 제외해 iPhone 17 Pro iOS 26.5 Simulator 대상 빌드를 실행했고, T044 테스트 자체의
Swift 6 오류 없이 계획된 T049 타입인 `ManagedSettingsStoreAccess`,
`RestrictionApplicationStateStoring`, `ManagedSettingsRestrictionAdapter`가 아직 없어 compile
단계에서 실패하는 red 상태를 확인했다. 선행 테스트의 target membership은 즉시 복구했고,
`project.pbxproj` plist 문법과 `git diff --check`를 통과했다. T049 구현 뒤 이 suite를 다시 실행해야
한다.

T043에서 `LocationMonitoringAdapterTests.swift`에 500m·1km·2km·3km·4km·5km 각 반경의 확실한
내부, 정확도 0인 정확한 경계, 확실한 외부와 오차 원 경계 중첩 판정을 매개변수화하고, 최신 위치
evidence가 규칙 revision·관측 시각·거리·정확도·event source를 보존한
`LocationConditionSnapshot`으로 기록되는 실패 테스트를 작성했다. 총 5개 test case가 동적 인자를
포함해 25회 실행될 계약이며 테스트 파일을 `GetUpTests` target에 포함했다. iPhone 17 Pro iOS 26.5
Simulator 대상 빌드에서 계획된 T047·T048 타입인 `LocationEvidenceEvaluator`, `LocationEvidence`,
`LocationEvidenceProviding`, `LocationMonitor`가 아직 없어 compile 단계에서 실패하는 red 상태를
확인했다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했으며 T047·T048 구현 뒤 이
suite를 다시 실행해야 한다.

현재 작업은 최신 `origin/main`에서 분기한 `codex/us2-restriction-activation` 브랜치에서 진행한다.
US2의 관련 task를 같은 브랜치에 묶되 설계·운영 지침, T042, T043을 각각 논리적 커밋으로 분리한다.

T042에서 `DeviceActivityScheduleAdapterTests.swift`에 선택한 월·수·금의 반복 일정과 시작·종료
`DateComponents`, 14분 일정의 사전 거부와 기존 등록 보존, 일요일 자정 초과 일정의 월요일 종료,
동일 규칙의 이전 요일 일정만 교체하고 다른 규칙 일정은 보존하는 4개 실패 테스트를 작성했다.
테스트 파일을 `GetUpTests` target에 포함하고 `project.pbxproj` plist 문법과 `git diff --check`를
통과했다. iPhone 17 Pro iOS 26.5 Simulator에서 대상 suite 빌드를 실행해 테스트 자체의 Swift 6
동시성 오류는 없고, 계획된 T046 대상인 `DeviceActivityScheduling`,
`DeviceActivityScheduleAdapter`, `DeviceActivityScheduleAdapterError`가 아직 없어 compile 단계에서
실패하는 red 상태를 확인했다. 따라서 전체 테스트 통과 상태는 아니며 T046 구현 뒤 이 suite를
다시 실행해야 한다.

명세 품질 체크리스트 16/16개 항목을 통과함. 계획 산출물의 구조 검증을 통과함.
T025 착수 전 `xcodebuild -list -project GetUp.xcodeproj`로 6개 target과 공유 scheme을 확인했으나,
로컬 CoreSimulator service 연결 실패 경고가 발생했다. 이후 사용자가 BLK-006의 1안을 선택해 DST의
존재하지 않는 경계는 다음 유효 시각, 반복 시작은 첫 번째 발생, 반복 종료는 두 번째 발생으로
확정했다. `ScheduleEvaluatorTests.swift`에 14/15분, 선택·비선택 요일, 같은 날·자정 초과, DST 시작·
종료 보정과 반복 시각 경계를 작성하고, `RestrictionRuleValidatorTests.swift`에 요일·저장 장소·여섯
반경·앱 token·같은 시작/종료·14/15분 validation을 작성했다. 두 파일은 임시 계약 stub을 사용한
Swift 6 strict concurrency type-check를 통과했으며, 실제 production module에 대해서는 계획대로
`ScheduleEvaluator`, `RestrictionRuleValidator`, `RestrictionRuleValidationInput` 미구현 오류로
red 상태를 확인했다. `xcodebuild build-for-testing`은 앱 target에 실행 entry point가 아직 없어
linker 단계에서 실패했고 CoreSimulator service 경고도 계속 발생했다. `project.pbxproj` 문법과
`git diff --check`는 통과했으며, validation red 테스트는 T029 구현과 함께 해소됐다.
T026에서 `LocationPickerModelTests.swift`에 지도 이동, 현재 위치 바로가기, When In Use 권한 부족과
위치 조회 실패 시 pin 보존, 저장 장소 draft 생성·재사용, 확인·취소 상태를 작성했다.
`CurrentLocationProviderTests.swift`에는 When In Use 성공, denied·restricted·notDetermined 권한 흐름,
권한 요청 거절, 단발성 위치 실패 정규화를 작성했다. 두 파일과 test fake는 임시 계약 stub을 사용한
Swift 6 strict concurrency type-check를 통과했다. 실제 production module에서는 계획대로
`LocationPickerModel`, `SavedPlaceSnapshot`, `CurrentLocationProvider`, `CurrentLocationSession` 등
T030 대상 타입의 미구현 오류로 red 상태를 확인했다. 새 테스트의 `GetUpTests` target membership,
`project.pbxproj` 문법과 `git diff --check`를 확인했으며, red 상태는 T030 구현과 함께 해소됐다.
T027에서 `UserStory1RuleConfigurationUITests.swift`에 필수 입력 validation과 요일·저장 장소·앱
선택, 유효 규칙 저장 후 process 재실행 재로딩, 세 저장 규칙의 양방향 card swipe, 선택 card 편집 시
값 보존, 규칙 삭제 확인과 재실행 후 삭제 보존을 작성했다. 승인된 하이파이의 accessibility
identifier를 사용하고, 시스템 소유
`FamilyActivityPicker` 결과는 `--ui-test-family-picker-result` launch argument로 test seam에서만
주입하도록 계약했다. UI test source는 Swift 6 strict concurrency standalone type-check와
`xcodebuild build-for-testing`의 arm64·x86_64 compile을 통과했다. 전체 test build는 app entry point가
아직 없어 GetUp linker 단계에서 실패했고 CoreSimulator service도 사용할 수 없었으므로 UI assertion은
실행되지 않았다. 이는 T035~T037 UI·app 구현 전의 예상 red 상태다. `project.pbxproj` 문법과
`git diff --check`는 통과했다.
T028에서 `ScheduleEvaluator.swift`에 15분 최소 간격의 종료 시각 선택 여부, 선택 요일, 시작 포함·
종료 미포함, 자정 초과 구간의 시작 요일 귀속을 구현했다. 현지 시각 경계는 `Calendar.nextDate`의
`.nextTime` 정책을 사용해 존재하지 않는 시각을 다음 유효 시각으로 이동하고, 반복 시작은 첫 번째,
반복 종료는 두 번째 발생을 사용한다. `RestrictionStateMachine`의 기존 단순 시·분 판정을
`ScheduleEvaluator` 호출로 교체해 앱과 extension의 실제 평가 경로도 같은 DST 규칙을 사용하게 했다.
임시 로컬 Swift package에서 T025의 `ScheduleEvaluatorTests` 7개와 기존 상태 머신 회귀 테스트 10개,
총 17개가 모두 통과했다. 변경한 core source는 iOS 26 Simulator SDK, Swift 6 strict concurrency 및
warning-as-error 조건에서 type-check를 통과했고, `ScheduleEvaluator.swift`가 앱과 세 extension의
Sources phase에 각각 한 번 포함되는지 확인했다. `project.pbxproj` plist 문법과 `git diff --check`도
통과했다. 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지 미검증 상태다.
T029에서 `RestrictionRuleValidator.swift`에 빈 요일, 유효하지 않은 시·분, 같은 시작·종료,
15분 미만 구간, 저장 장소 누락·삭제, 좌표 누락·범위 초과·비유한 값, 지원하지 않는 반경 및 앱
token 누락 판정을 구현했다. 반경의 단일 source of truth로 `RadiusOption.allCases`를 사용하고
`RadiusOption`을 500m·1km·2km·3km·4km·5km 여섯 값으로 확장했다. 기존 T025 테스트에 좌표와
시·분 모델 범위 경계를 보강했으며, 임시 로컬 Swift package에서 validator 11개, 일정 평가 7개,
상태 머신 회귀 10개로 총 28개 테스트가 모두 통과했다. 변경한 core source는 iOS 26 Simulator SDK,
Swift 6 strict concurrency 및 warning-as-error 조건에서 type-check를 통과했고,
`RestrictionRuleValidator.swift`가 앱과 세 extension의 Sources phase에 각각 한 번 포함되는지
확인했다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다. 전체 Xcode test 실행은 app
entry point가 구현되는 T037 전까지 미검증 상태다.
T030에서 `SavedPlaceSnapshot`·`SavedPlaceDraft`, 지도 중심·핀 후보·저장 장소 재사용·확정·취소·안내
상태를 가진 `@MainActor @Observable LocationPickerModel`을 구현했다. 현재 위치 바로가기는
`CurrentLocationProvider`와 `CurrentLocationSession` 계약으로 분리하고, 승인 상태에서는 단 한 번의
위치를 요청하며 `.notDetermined`에서만 When In Use 권한을 요청한다. denied·restricted와 Core
Location 실패를 닫힌 오류로 정규화하고, 실제 `CLLocationManager` delegate callback은
`CoreLocationCurrentLocationSession`의 main actor 경계에서 continuation으로 변환했다. 임시 로컬
Swift package에서 위치 선택 모델 9개, 현재 위치 provider 6개와 기존 core 회귀 28개로 총 43개
테스트가 모두 통과했다. 변경 source는 iOS 26 Simulator SDK, Swift 6 strict concurrency 및
warning-as-error 조건에서 type-check를 통과했고, 두 새 source가 앱 target Sources phase에 각각 한
번 포함되는지 확인했다. 실제 시스템 권한 prompt와 `CLLocationManager` callback은 Simulator·실기기
통합 검증 전까지 미검증 상태이며, 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지
미검증 상태다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다.
T031에서 승인된 Figma `HF-FLOW-05`와 `location-picker-ui-contract.md`를 기준으로
`LocationPickerView.swift`를 구현했다. 실제 MapKit 지도에 중심 고정 `mappin.circle.fill`, 선택
반경의 실제 meter 값을 사용하는 `MapCircle`, 저장 장소 chip, 직접 입력 진입, 적용 CTA와 현재 위치
바로가기를 구성했다. 프로그램 방식의 카메라 이동과 사용자 지도 이동을 분리해 저장 장소 선택이
MapKit의 camera 종료 callback으로 해제되지 않도록 했고, 지도 이동·현재 위치 선택 시 기존 장소
이름을 비워 새 좌표가 이전 장소 이름으로 저장되지 않게 보강했다. 권한 부족·위치 확인 실패 안내는
지도 핀 직접 선택을 유지하며, 모든 주요 control에 VoiceOver label·value·hint와 UI test identifier를
부여했다. 반경 값은 `Binding<RadiusOption>`으로 받아 지도 원에 즉시 반영하며 실제 여섯 단계 slider는
계획된 T033의 `RadiusPicker.swift`에서 연결한다. 관련 core 회귀 43개 테스트가 모두 통과했고,
`LocationPickerView.swift`를 포함한 변경 source는 iOS 26 Simulator SDK, Swift 6 strict concurrency,
warning-as-error 조건에서 type-check를 통과했다. 앱 entry point가 T037까지 미구현이므로 실제 화면
render, 지도 gesture, 시스템 권한 prompt 및 UI test 실행은 아직 미검증 상태다. `project.pbxproj`
plist 문법과 `git diff --check`는 통과했다.
T032에서 `FamilyControlsAuthorizationSession`과 `FamilyActivitySelectionAdapter`를 구현했다.
`AuthorizationCenter.requestAuthorization(for: .individual)`만 요청하고 이미 승인된 경우에는 시스템
요청을 반복하지 않는다. denied 상태에서 사용자가 명시적으로 재시도할 수 있으며 시스템 반환 상태를
그대로 안내 계층에 전달한다. iOS 26.4에서 추가된 `approvedWithDataAccess`는 도메인의 `approved`로
정규화했다. `FamilyActivityPicker` 결과는 앱 이름·bundle identifier로 해석하지 않고 불투명
`FamilyActivitySelection` 그대로 교체·초기화하며, validation과 요약에 필요한 application token
개수만 제공한다. 승인 재사용·최초 요청·거부 후 재시도·선택 결과 보존·초기화 5개 테스트를 추가했고,
기존 회귀를 포함한 6개 suite의 48개 테스트가 모두 통과했다. 실제 iOS 26.5 SDK에서 production
module을 Swift 6 strict concurrency 및 warning-as-error 조건으로 compile했으며, adapter와 테스트의
target membership, `project.pbxproj` plist 문법과 `git diff --check`를 확인했다. 실제 Family Controls
승인 sheet와 `FamilyActivityPicker` 표시는 T035 연결 및 entitlement가 적용된 실기기 검증 전까지
미검증 상태다.
T033에서 승인된 Figma `HF-FLOW-01`·`HF-FLOW-02`·`HF-FLOW-03`·`HF-FLOW-05`를 기준으로
`TimeRangePicker`, `WeekdayPicker`, `RadiusPicker`를 구현했다. 시간 picker는 시·분·AM/PM을 독립된
wheel로 제공하고 분을 1분 단위로 선택하며, 종료 시각 변경은 `ScheduleEvaluator`를 사용해 시작
시각으로부터 15분 미만인 후보를 반영하지 않는다. 요일 chip은 44pt 최소 hit target과 선택 trait,
요일별 UI test identifier를 제공한다. 반경 slider는 `RadiusOption.allCases`의 500m·1km·2km·3km·
4km·5km 여섯 값에만 스냅되고 VoiceOver 조절값과 `locationPicker.radius` identifier를 제공하며,
기존 `LocationPickerView`에 연결해 반경 변경이 지도 원과 카메라에 즉시 반영되도록 했다. 승인된
accent `#F4D600`을 `AccentColor` asset에 등록했고, 12시간제의 자정·정오 변환과 0 채움 표시 테스트를
추가했다. 세 component와 관련 core source는 iOS 17 Simulator SDK, Swift 6 strict concurrency 및
warning-as-error 조건의 독립 type-check를 통과했다. 전체 `build-for-testing`은 앱·component·test
source compile과 asset compile을 통과한 뒤 아직 앱 entry point가 없어 기존 예상 상태인 `_main`
linker 오류로 종료됐다. 따라서 새 assertion의 실제 실행, 화면 render, wheel gesture 및 VoiceOver
동작은 T037의 앱 entry point 구현 후 검증해야 한다. T032에서 누락된
`FamilyActivitySelectionAdapterTests.swift`의 Xcode `Integration` group 경로도 바로잡았고,
`project.pbxproj` 문법, asset JSON 및 `git diff --check`를 확인했다.
T034에서 `RuleEditorDraft`와 `@MainActor @Observable RuleEditorModel`을 구현했다. 새 규칙은 주입 가능한
고유 ID와 `sourceRevision == nil`을 사용하고, 기존 규칙 편집은 ID·revision·생성 시각과 모든 입력을
보존해 다른 저장 규칙을 대체하지 않는다. 선택적인 규칙 이름은 앞뒤 공백을 제거한 뒤 빈 값이면
`nil`로 준비하며, 요일·시간·저장 장소·여섯 단계 반경·opaque `FamilyActivitySelection`을 하나의
draft로 유지한다. 저장 가능 여부는 별도 규칙을 복제하지 않고 `RestrictionRuleValidator` 결과로
계산한다. `LocationPickerCompletion`의 새 장소는 ID와 생성·수정 시각을 부여해 collection에 추가하고,
기존 장소는 ID 기준으로 갱신·재사용하며 취소 시 현재 draft를 보존한다. 새 규칙 필수 validation,
유효 draft, 기존 편집 값 보존, 새 장소 생성, 기존 장소 재사용, 취소, 삭제된 장소 참조, 규칙별 독립
ID를 검증하는 Swift Testing 8개를 추가했다. production 및 test source는 iOS 26 Simulator SDK,
Swift 6 strict concurrency와 warning-as-error compile을 통과했고, 동일 production source의 임시 host
harness 12개 assertion이 모두 통과했다. 전체 `build-for-testing`은 새 source compile 후 T037 전의
기존 예상 상태인 앱 entry point `_main` linker 오류로 종료되어 Xcode test suite 실행은 아직
미검증 상태다. `project.pbxproj` 문법과 `git diff --check`를 확인했다.
T035에서 승인된 Figma `HF-FLOW-01`·`HF-FLOW-10`·`HF-FLOW-11`을 기준으로
`RuleEditorView.swift`를 구현했다. Dark Focus의 편집 header, 시간 disclosure, 요일 chip, 장소·앱
조건 card와 하단 저장 CTA를 구성하고 필수 요일·장소·앱 validation을 화면에 연결했다. 시작·종료
시간은 기존 wheel sheet로, 장소는 `LocationPickerView` push와 재사용 가능한 장소 이름 입력 alert로
연결했다. 앱 선택은 개인용 Family Controls 승인 뒤 시스템 `FamilyActivityPicker`를 표시하고 opaque
selection을 model에 반영하며, UI test에서만 결과를 주입할 수 있는 seam을 제공한다. 저장은 T036의
service를 주입받는 async closure로 분리하고 중복 tap 방지, draft를 보존하는 저장 실패 card와 재시도
식별자를 구현했다. 주요 control과 validation에는 T027 UI test 계약의 accessibility identifier,
label, value, hint를 적용했다. `RuleEditorView.swift`와 관련 앱·테스트 source는 iOS 26 Simulator SDK의
arm64·x86_64에서 Swift 6 compile을 통과했다. 전체 `build-for-testing`은 source와 test compile 뒤
T037 전의 기존 예상 상태인 앱 entry point `_main` linker 오류로 종료되어 실제 화면 render, 시스템
Family Controls 승인·picker 및 UI test 실행은 아직 미검증 상태다. `project.pbxproj` 문법과
`git diff --check`를 확인했다.
T036에서 `RuleConfigurationService`와 collection repository 계약을 구현했다. 새 규칙과 대상 규칙의
revision, 전체 규칙 collection revision 및 저장 장소 collection revision을 저장마다 각각 증가시키고,
편집 시작 revision이 현재 값과 다른 stale write는 파일을 쓰기 전에 거부한다. 다른 규칙은 그대로
보존하며 새·수정 장소를 ID로 병합하고, 장소를 규칙보다 먼저 atomic write해 존재하지 않는 장소 참조를
방지한다. schema 1의 기존 `restriction-rule.json`은 좌표와 시각을 보존한 결정론적 규칙·장소
aggregate로 읽으며, 새 plural collection 파일이 생기면 이를 우선한다. 임시 Swift package에서
`RuleConfigurationServiceTests` 4개와 `SharedSnapshotRepositoryTests` 12개, 총 16개 테스트가 모두
통과했다. `xcodebuild build-for-testing`은 앱과 새 test source의 arm64·x86_64 compile을 통과한 뒤
T037 전의 기존 예상 상태인 앱 entry point `_main` linker 오류로 종료됐다. `project.pbxproj` 문법과
`git diff --check`를 확인했다.
T037에서 `GetUpApp` 실행 진입점과 `@MainActor @Observable AppModel`을 구현해 규칙·저장 장소
collection을 로딩하고, 오늘 선택 요일 또는 현재 활성인 자정 초과 규칙을 먼저 배치한 뒤 나머지를
DST 보정된 다음 시작 시점 순으로 정렬한다. 승인된 Dark Focus의 규칙 없음 화면과 시간·요일·장소·
반경·앱 개수·수정 행동을 하나로 묶은 swipeable card, page indicator, 새 규칙 CTA를 구현했다.
선택 card 편집은 ID·revision과 기존 값을 보존하고 저장 성공 뒤 collection을 다시 반영해 홈으로
복귀한다. UI test 전용 격리 저장소와 불투명 앱 선택 seam은 launch argument가 있을 때만 활성화한다.
사용자 피드백으로 누락을 확인한 규칙 삭제를 같은 편집 화면에 보완했다. 삭제 확인 후 대상 규칙만
제거하고 규칙 collection revision을 증가시키며, 다른 규칙과 재사용 가능한 저장 장소는 보존한다.
stale editor 삭제는 기록 전에 거부하고 `AppModel`의 비동기 삭제 guard가 거부하면 화면을 닫거나
저장소를 변경하지 않는다. 실제 활성 제한 판정은 계획된 T066에서 이 guard에 연결한다.
`build-for-testing`에서 앱 entry point를 포함한 앱·단위 테스트·UI 테스트 target의 arm64·x86_64
compile과 link가 모두 통과했다. 삭제 보완 후 iPhone 17 Pro iOS 26.5 Simulator에서 단위·저장소
85개 test case(동적 인자 포함 97회 실행)와 T027 UI test 5개가 실패·skip 없이 통과했다. Simulator가
실제 파일 보호 속성을 노출하지 않는 환경 차이는 writer option을 직접 검증하고 물리
기기에서 실제 속성을 확인하도록 기존 테스트를 보정했다. 실제 App Group, Family Controls picker,
지도 권한과 실기기 Dynamic Type·VoiceOver는 계획된 통합·마무리 task 전까지 미검증 상태다.
T038에서 기존 US1 Figma 파일의 `GetUp Focus` 변수·text style과 iOS 26 text button component를
재사용해 별도 wrapper `US2 / 제한 활성 + Restricted App Shield · T038 로우파이`를 작성했다.
`US2-LF-01`은 제한 앱 개수, 시간·위치 조건 충족 이유와 시간 종료·신뢰 가능한 위치 이탈이라는
자동 해제 조건을 표시한다. `US2-LF-02`는 정적 GetUp 아이콘, 제한 활성 제목, 자동 해제 설명과 단일
`앱 닫기` 행동만 제공하며 앱 이름·bundle identifier를 직접 표시하거나 우회·규칙 변경·GetUp 자동
실행을 약속하지 않는다. 조건 충족부터 제한 앱 종료까지의 4단계 흐름과 VoiceOver 순서, 색상 외 상태
표현 가설을 Figma와 `design/low-fidelity/US2-active-restriction.md`에 기록했다. 최종 자동 감사에서
35개 text node의 SF Pro 외 서체, 0폭·0높이 text, 임시 placeholder, shimmer, 화면 overflow와 실제
앱 식별 정보가 모두 0건이며 primary action instance가 `앱 닫기` 하나뿐임을 확인했다. 디자인·문서
작업이므로 code test는 실행하지 않았고, T039 사용자 검토 전까지 T040 하이파이를 시작하지 않는다.
T039 사용자 피드백에 따라 별도 `US2-LF-01` 화면을 기존 홈 카드의 제한 활성 상태로 교체하고,
`US2-LF-02` 제목과 설명에 저장 장소 `집`, 설정 반경 `1km`, 종료 시각 `09:00 AM`을 직접 표시했다.
Figma 재렌더링과 node 감사에서 LF-01 21개와 LF-02 5개 text node의 누락 font, 빈 text, placeholder,
육안상 overflow가 0건이고 shield 행동 instance가 `앱 닫기` 하나뿐임을 확인했다. iOS 26.5 SDK의
`ShieldConfiguration`과 `ShieldActionResponse`를 확인한 결과 shield 내부 임의 Map UI는 지원되지
않고 GetUp 앱 열기는 iOS 26.5 이상의 `openParentalControlsApp`과 secondary action·contract 변경이
필요하다. 이를 `BLK-007`로 기록했으며 결정 전까지 T039를 완료 처리하지 않는다. 디자인·문서
변경이므로 code test는 실행하지 않았다.
사용자가 BLK-007의 1안을 선택해 MVP shield는 모든 지원 버전에서 secondary action 없이 장소·반경·
종료 시각 문구와 primary `앱 닫기`만 제공하기로 확정했다. Figma의 계약·승인 주석,
`design/low-fidelity/US2-active-restriction.md`, `docs/BLOCKERS.md`와 `DEC-026`에 결정을 반영하고
T039를 완료했다. 향후 `오늘만 허용`과 인앱결제를 통한 일시 해제는 현재 범위에서 제외하고 별도
spec과 플랫폼·결제 정책 검토 대상으로 기록했다. 디자인·문서 변경이므로 code test는 실행하지
않았다.
T040에서 승인된 기존 홈 활성 상태, 기본 restricted-app shield와 Dynamic Type `AX5` 비교 상태를
하나의 Figma 하이파이 wrapper로 구성했다. `GetUp Focus` semantic color·spacing token, SF Pro와
iOS 26 Liquid Glass primary button instance를 재사용하고 장소·반경·종료 시각, 단일 `앱 닫기`,
VoiceOver 순서, Increase Contrast·Reduce Motion, 명암 계산과 T052·T053·T055 구현 인계를
`design/high-fidelity/US2-active-restriction.md`에 기록했다. 전체와 개별 frame 렌더링 및 50개 text
node 감사에서 누락 font, 빈 text, placeholder, shimmer, 화면 경계 overflow가 모두 0건이었고 행동
instance는 `Primary Action · 앱 닫기` 두 개뿐이었다. 디자인·문서 작업이므로 code test는 실행하지
않았으며 T041 사용자 승인 전에는 shield UI 구현을 시작하지 않는다.
T041에서 사용자가 기본·Dynamic Type AX5 restricted-app shield, 장소·반경·종료 시각 안내,
secondary action 없는 단일 `앱 닫기`, 접근성·명암·구현 인계를 최종 승인했다. Figma wrapper의 승인
주석과 `design/high-fidelity/US2-active-restriction.md`의 검토 기록·승인 상태를 갱신하고 T041을
완료했다. 디자인 승인 기록 작업이므로 code test는 실행하지 않았으며 T042부터 US2 선행 실패
테스트를 진행한다.
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
현재는 `DEC-035`에 따라 `GETUP_APP_GROUP_IDENTIFIER = group.com.dxyn02.GetUp` 상속을 확인함. 실제 개발·배포 서명 및
entitlement 승인은 T082와 실기기 검증 전까지 미검증 상태임.
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
T010 검증으로 `RestrictionRuleModels.swift`를 iOS Simulator SDK와 Swift 6 strict concurrency,
app-extension-only 설정에서 warning을 error로 처리해 type-check함. 모든 모델의 Codable·Equatable
및 필요한 Hashable·Sendable conformance, 월요일부터 일요일까지의 안정적인 raw value,
500m·1,000m raw value와 `radiusMeters` CodingKey를 확인하고 같은 source가 앱과 세 extension에 한
번씩 포함되는지 검증함. 시간·좌표·revision·요일·앱 선택의 유효성 및 JSON round-trip 자동 테스트는
계획된 T025·T017에서 수행하기 전까지 미검증 상태임.
T011 검증으로 `RuntimeStateModels.swift`를 iOS Simulator SDK와 Swift 6 strict concurrency,
app-extension-only 설정에서 warning을 error로 처리해 type-check함. 위치 상태·관측 source·권한 상태의
stable raw value, 위치 snapshot schema version 및 필드, 제한 표시 상태의 associated value를 확인하고
같은 source가 앱과 세 extension에 한 번씩 포함되는지 검증함. 권한·시간·위치 조합의 상태 전이와 JSON
round-trip 자동 테스트는 계획된 T015·T017에서 수행하기 전까지 미검증 상태임.
T012 검증으로 기존 모델과 `PlatformContracts.swift`를 iOS Simulator SDK와 Swift 6 strict
concurrency, app-extension-only 설정에서 warning을 error로 처리해 type-check함. 일곱 platform
contract의 `Sendable` 경계, repository CRUD, 일정·위치 lifecycle, 권한 snapshot 조회 및 제한 적용
상태의 원자적 조회 signature를 확인하고 같은 source가 앱과 세 extension에 한 번씩 포함되는지
검증함. 실제 adapter의 protocol 준수와 오류·취소 동작은 T018·T046·T048·T049·T075 구현 전까지
미검증 상태임.
T013 검증으로 기존 core 모델·contract와 `RestrictionEvaluationModels.swift`를 iOS Simulator SDK,
Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해 type-check함.
평가 입력이 전역 상태 대신 규칙·시각·달력·시간대·위치·권한·현재 제한 상태를 명시적으로 받으며,
결정이 presentation·desired restriction·effect·reason을 모두 포함하는지 확인함. 전체 상태 행렬과
우선순위·idempotency 동작은 계획된 T015·T016 전까지 미검증 상태임.
T014 검증으로 기존 core source를 `GetUp` testable module로 compile한 뒤 `TestFixtures.swift`를
iOS Simulator SDK와 Swift 6 strict concurrency에서 warning을 error로 처리해 type-check함. 고정
clock의 `Clock` 준수, UTC Gregorian calendar, factory override와 test target Sources membership을
확인함. fixture는 테스트 보조 코드이므로 독립 assertion은 없으며 실제 상태 행렬 실행은 T015에서
시작함. 기본 `FamilyActivitySelection`은 opaque token을 위조하지 않은 빈 선택으로, 앱 선택 유효성은
T025 validation 테스트에서 별도 검증할 예정임.
T015에서 시간 2상태 × 위치 3상태 × 권한 2상태 × 현재 shield 2상태의 24개 조합과 시간 종료
우선순위, 위치 `unavailable` 보존, rule revision 불일치, apply/remove idempotency를 Swift Testing으로
작성함. 구현 전 임시 compile stub을 사용하면 테스트 source가 Swift 6 strict concurrency에서
type-check되었고, stub 없이 검사하면 `RestrictionStateMachine`을 찾을 수 없어 의도한 red 상태가
발생했음. 이후 T016 구현과 실행 검증을 통과해 T015를 함께 완료 처리함.
T016 검증으로 `RestrictionStateMachine.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK, Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해
type-check함. 실제 구현을 import한 T015 Swift Testing source가 compile 검사를 통과했으며, 동일 구현을
링크한 자동 실행 harness에서 24개 상태 조합, 시간 종료 우선순위, 위치 `unavailable`·revision 불일치
보존, apply/remove idempotency, 필수 권한 결합과 자정 초과 일정의 시작 요일 귀속 assertion을 모두
통과함. `BackgroundRefreshStatus`는 진단 정보로 유지하고 신규 shield 적용의 필수 권한 집합에서는
제외함. 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지 실행할 수 없어 미검증 상태임.
T017에서 규칙·위치 JSON의 별도 파일 round-trip과 `completeUntilFirstUserAuthentication` 보호,
파일 없음의 `nil` 처리, 두 파일의 손상 JSON·미지원 schema, rule revision 불일치, 두 파일의 atomic
write 실패 시 이전 snapshot 보존을 Swift Testing으로 작성함. 구현 전 임시 compile stub을 포함하면
테스트 source가 iOS 17 Simulator SDK와 Swift 6 strict concurrency에서 type-check되었고, 실제
source만 사용한 검사에서는 `SharedSnapshotRepository`, `SharedSnapshotRepositoryError`,
`SnapshotFileWriting`을 찾을 수 없어 의도한 red 상태가 발생했음. 이후 T018 구현과 실행 검증을
통과해 T017을 함께 완료 처리함.
T018 검증으로 `SharedSnapshotRepository.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK, Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해
type-check함. 실제 T017 Swift Testing suite를 macOS host에서 같은 Foundation 구현과 불투명
`FamilyActivitySelection` compile stub으로 실행해 1개 suite의 10개 테스트가 모두 통과함. JSON은
ISO-8601 날짜와 정렬된 key로 encoding하고, schema header 선검사, 현재 rule revision 교차 검사,
atomic write와 `completeUntilFirstUserAuthentication` 보호, 오류 분류 및 삭제의 멱등성을 구현함.
기존 상태 머신 회귀 테스트까지 합친 2개 suite의 20개 테스트도 모두 통과함. 전체 Xcode test 실행은
app entry point가 구현되는 T037 전까지 실행할 수 없어 미검증 상태임.
T019 검증으로 `DependencyContainer.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK 및 macOS host에서 Swift 6 strict concurrency warning을 error로 처리해 type-check함.
실행 harness에서 한 container의 규칙·위치 계약이 동일 `SharedSnapshotRepository` actor를 노출하는지,
앱과 extension을 모사한 별도 container 인스턴스가 같은 규칙·위치 파일을 읽는지 확인함. actor 밖의
`FileManager` 인스턴스를 저장소로 전송하지 않도록 파일 작업은 actor 내부에서 생성한 인스턴스만
사용하게 조정했으며 기존 2개 suite의 20개 회귀 테스트도 모두 통과함. 실제
`DependencyContainer.live()`의 App Group container URL 획득은 entitlement가 적용된 서명 target
실행 전까지 미검증 상태임.
T020 검증으로 `DiagnosticsLogger.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK와 macOS host에서 Swift 6 strict concurrency warning을 error로 처리해 type-check함.
저장소 오류 7종과 App Group 조립 오류 2종을 안정적인 code로 분류하고, file name·schema 값·revision
값과 알 수 없는 오류 설명을 event에서 폐기하도록 Swift Testing 3개 테스트로 검증함. 좌표와 불투명
앱 token을 포함한 임의 오류 문자열이 최종 `logMessage`에 포함되지 않음을 확인했으며, 기존 상태
머신·저장소 회귀를 합친 3개 suite의 23개 테스트가 모두 통과함. 실제 unified logging 수집 결과의
통합 개인정보 검사는 T081에서 수행하며, 전체 Xcode test 실행은 app entry point가 구현되는 T037
전까지 실행할 수 없어 미검증 상태임. T020 완료로 Phase 2 공통 기반을 완료 처리함.
iOS 26 최소 지원 변경으로 `Configuration/Base.xcconfig`의
`IPHONEOS_DEPLOYMENT_TARGET = 26.0`을 앱·세 extension·두 테스트 target이 Debug 구성에서 모두
상속하는지 `xcodebuild -showBuildSettings`로 확인함. `project.pbxproj` plist 문법을 재검증하고,
공통 production source를 `arm64-apple-ios26.0-simulator`, Swift 6 strict concurrency 및 warning-as-error
조건으로 type-check함. 첫 type-check는 오래된 입력 경로, 두 번째는 sandbox의 기본 module cache
쓰기 제한 때문에 실패했으며, 실제 source와 writable 임시 module cache를 지정한 최종 검사는
통과함. CoreSimulatorService 및 로컬 provisioning profile 경고는 build setting 출력에 영향을
주지 않았으며 실제 iOS 26 Simulator 실행·실기기 검증은 관련 app entry point와 UI 구현 이후 수행함.
T021 검증으로 Figma의 `US1 / 규칙 설정 흐름` section에 iPhone 393×852 기준 7개 frame을 작성하고,
직접 시간·자정 초과·15분 미만 오류·지도 핀·현재 위치 권한 부족·시스템 앱 선택·저장 실패 상태를
각각 확인함. 모든 화면이 Apple `iOS and iPadOS 26` 공식 library component와 `SF Pro`만 사용하는지,
실제 좌표·주소·app token을 포함하지 않는지, frame 직접 링크와 접근성 가설이 설계 문서에 기록됐는지
검증함. 이 task는 디자인·문서 작업이므로 code test는 실행하지 않았으며, 로우파이는 아직 사용자
승인 전이라 T022 검토와 T023 하이파이 작업이 남아 있음.
T022 진행 중 알람·집중 앱 7개 제품의 행동 유도 방식과 앱 이름 후보를 조사해
`design/research/alarm-focus-app-concept.md`에 정리함. Figma에 침대에서 문까지(A), 문턱(B), 출발
티켓(C) 세 방향의 onboarding·home 6개 frame을 추가함. 각 home은 오늘 또는 다음날의 요일·시간·
기준 위치·반경·제한 앱 요약, 규칙 수정 및 새 규칙 진입을 포함함. 구조 감사에서 6개 frame의
placeholder가 모두 제거됐고, 사용 font는 `SF Pro`뿐이며 실제 좌표·주소·app token과 frame overflow가
없음을 확인한 뒤 각 frame screenshot을 개별 검토함. 이 작업은 디자인·문서 변경이라 code test는
실행하지 않았으며, T022 완료와 하이파이 시작은 사용자 방향 선택·승인 전까지 보류함.
사용자가 직접 제작한 D안은 변경하지 않고 Figma에 별도의 `D안 보완 / 행동 명확화` 비교 영역을
추가함. onboarding, 규칙 없음, 오늘 규칙, 다음날 규칙 4개 frame에 오늘·다음날 맥락, 위치 이동과
앱 사용 가능 조건, 시간·위치 해제 조건, 제한 앱 요약, 규칙 수정 진입점을 반영함. 개별 frame과
전체 비교 screenshot에서 텍스트 잘림·겹침을 수정했고, 기존 D안 node `15:346` 보존 및 보완안의
모든 텍스트가 `SF Pro` 계열만 사용하는지 확인함. 디자인·문서 작업이므로 code test는 실행하지
않았으며 당시 T022는 사용자 승인 전이라 진행 중으로 유지함.
2026-08-23 추가 피드백에 따라 D안 home의 시간을 `06:00 AM` 형식으로 통일하고 `AM`/`PM` 크기를
시간 숫자보다 작게 조정했다. 규칙 화면은 시간 프리셋을 제거하고 직접 시작·종료 시각만 제공하며,
15분 미만 종료 시각을 비활성화한 DatePicker 상태를 추가했다. `프리셋 이름`은 `규칙 이름`으로,
위치 설정은 재사용 가능한 `집`·`회사`·`직접 입력` 장소와 여섯 단계 반경 slider로 변경했다.
home·규칙·장소·권한·키보드·DatePicker frame을 개별 screenshot으로 검수했고 이전 용어가 남지
않았음을 확인했다. Apple 시스템 keyboard component의 `SF Compact`를 제외한 제품 UI 텍스트는
`SF Pro` 계열을 유지한다. 이번 변경은 Figma와 명세·계획 문서 작업이므로 code test는 실행하지
않았고 `git diff --check`를 통과했다. 이 검수 시점에는 T022를 사용자 승인 전 진행 중으로 유지했다.
2026-08-23 사용자가 직접 수정해 `D 보완` frame에 정리한 안을 최종 로우파이로 승인했다.
`design/low-fidelity/US1-rule-configuration.md`에 승인자·승인일·미해결 항목 없음 상태를 기록하고
T022를 완료 처리했다. 승인 기록만 변경했으므로 code test는 실행하지 않았으며, 사용자의 별도
지시 전까지 T023 또는 다른 후속 작업을 시작하지 않는다.
T023 검증으로 승인된 `D 보완` 로우파이를 보존한 별도 Figma wrapper
`US1 / 하이파이 T023 · 검토용`에 iPhone 393×852 기준 9개 상태를 작성했다. 입력 전·유효 입력
Light, 유효 입력 Dark, 지도 핀·저장 장소, 현재 위치 권한 부족, 장소 이름 직접 입력, 15분 제한
DatePicker, 시스템 앱 선택 경계, 저장 실패·draft 유지 상태를 포함하고 Dynamic Type·VoiceOver·
44×44pt touch target·Reduce Motion 인계 규격을 추가했다. Apple `iOS and iPadOS 26` library의
290개 component instance와 431개 variable 연결 node를 사용했으며, 최종 자동 감사에서 313개
text의 허용되지 않은 font family, 0폭·0높이 text, 임시 placeholder 문구와 shimmer가 모두 0건임을
확인했다. 제품 UI는 `SF Pro` 계열을 사용하고 Apple 시스템 keyboard의 `SF Compact Rounded`만
예외로 확인했다. 권한 오류 본문은 `#B42518`로 조정해 흰 배경에서 6.52:1 대비를 확보했다.
`design/high-fidelity/US1-rule-configuration.md`에 색상·서체·간격·component 상태·문구·접근성·
플랫폼 제약과 구현 인계를 기록하고 `git diff --check`를 통과했다. 디자인·문서 작업이므로 code
test는 실행하지 않았으며, SwiftUI 구현은 T024 사용자 승인 전까지 시작하지 않는다.
2026-08-23 T024 검토를 위해 기존 T023 wrapper를 보존하고 별도 Figma wrapper
`US1 / 하이파이 후보 3안 · T024 검토`에 같은 규칙 데이터를 사용한 `A · Native Calm`,
`B · Dark Focus`, `C · Warm Behavioral` 대표 화면과 비교 카드를 작성했다. 최종 렌더에서 세
화면이 모두 393×852이고 화면 밖으로 벗어난 node가 없음을 확인했다. 자동 감사에서 83개 text의
허용되지 않은 font family와 0폭·0높이 text가 모두 0건이며 shimmer·gradient도 0건이었다.
디자인·문서 작업이므로 code test는 실행하지 않았고, T024는 사용자 방향 선택과 최종 구현 승인 전
상태이므로 완료 처리하지 않았다.
2026-08-23 사용자가 후보 B를 선택해 기존 T023과 후보 비교 보드를 보존하고 별도 Figma wrapper
`US1 / B Dark Focus 전면 적용 · T024 검토`를 작성했다. 규칙 편집, 지도 핀·권한·직접 입력,
DatePicker·시스템 앱 선택·저장 실패의 9개 393×852 화면과 접근성 인계 패널에 `#08090B` 배경,
`#15171B`·`#202329` surface, `#F4D600` accent, 20pt 주요 시간 위계를 적용했다. 최종 자동 감사에서
386개 text의 허용되지 않은 font family, 0폭·0높이 text, 화면 경계 밖 text와 placeholder가 모두
0건이었다. 시스템 keyboard의 `SF Compact`·`SF Compact Rounded`는 시스템 소유 예외로 유지했다.
디자인·문서 작업이므로 code test는 실행하지 않았고 `git diff --check`를 통과했다.
T024는 B 전면 적용본의 사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자 피드백으로 첫 B 적용본이 기존 form layout의 리스킨에 그쳐 선택한 B 후보의 UI
구조를 반영하지 못했음을 확인했다. 첨부 screenshot을 시각 source of truth로 지정하고 iOS 26
component를 제외한 `US1 / Dark Focus 재설계 · 첨부 기준` wrapper를 새로 작성했다. GetUp Focus
Primitives·Semantic·Layout collection 3개, variable 30개와 text style 7개를 만들고 9개 393×852
화면을 `editorial header → large focus card → circular selection → condition card → bottom CTA`
구조로 처음부터 다시 구성했다. 최종 자동 감사에서 233개 text의 font 오류, 0폭·0높이 text,
화면 경계 밖 text, placeholder, 이름 없는 node 및 의도하지 않은 hardcoded fill이 모두 0건이었다.
디자인·문서 작업이므로 code test는 실행하지 않았으며 T024는 재설계본의 사용자 최종 확인과 구현
승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자 피드백에 따라 `US1 / Dark Focus 논리 플로우 · T024 재검토` wrapper를 추가했다.
규칙 작성 화면의 `START`·`END` 행을 각각 명확한 편집 진입점으로 만들고 시작·종료 선택 화면과 모든
요약·오류 상태를 24시간제로 통일했다. 장소 설정은 화면 절반 이상의 큰 지도, 중심 핀, 실제 반경 원,
반경 slider를 함께 표시하며 D안의 `집`·`회사`·`직접 입력` 진입을 유지했다. `직접 입력`은 선택한
좌표·반경을 보존한 장소 이름 화면으로 이어진다. 앱 선택, 네 조건 최종 검토, draft를 보존하는 저장
실패까지 총 11개 393×852 화면과 사용자 흐름 규칙 패널을 작성했다. 자동 점검에서 251개 text의 실제
AM/PM 표기, 임시 placeholder, 부모 frame 밖 overflow가 모두 0건이었다. 디자인·문서 작업이므로 code
test는 실행하지 않았으며 T024는 사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자가 직접 다듬은 Figma 상태를 기준으로 기존 변경을 보존하고 시작·종료 시각 화면만
시·분·AM/PM 세 열 wheel로 교체했다. 분 열은 `58`·`59`·`00`·`01`·`02`처럼 1분 단위 이동을
명시하고 최소 15분 유효성 안내를 유지했다. 규칙·홈·요약 시간 표기는 `06:00 AM` 형식으로 통일했다.
승인된 D 보완 홈 정보 구조를 Dark Focus에 맞춰 `규칙 없음`, `오늘 규칙`, `다음 예정` 3개
393×852 화면으로 추가했으며 오늘 또는 다음날, 시간, 위치·반경, 제한 앱, 규칙 수정과 새 규칙 진입을
포함했다. 최종 감사에서 전체 13개 화면의 임시 placeholder와 SF Pro 외 제품 font가 0건임을
확인했다. 디자인·명세·결정 문서 작업이므로 code test는 실행하지 않았고 T024는 사용자 최종 확인과
구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 홈 규칙의 시간과 조건이 두 card로 분리돼 서로 다른 정보처럼 보인다는 피드백을 반영했다.
`HOME-02`와 `HOME-03`에서 시간, 위치·반경, 제한 앱과 규칙 수정 행동을 하나의 353×456
`Swipeable rule card` 배경과 외곽선 안에 통합했다. card 상단에 `RULE 1 OF 3` 또는
`RULE 2 OF 3`, 하단에 page indicator와 좌우 swipe 안내를 배치해 한 page가 한 규칙임을 명확히
했다. 두 화면의 외곽 container, 투명 내부 section, swipe 안내, text overflow와 SF Pro font를
감사해 오류가 없음을 확인했다. 디자인·명세 문서 작업이므로 code test는 실행하지 않았고 T024는
사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 여러 규칙이 저장되면 모두 적용한다는 사용자 결정을 반영했다. 홈의 두 규칙 화면을
`모든 규칙 1/3`, `모든 규칙 2/3` 상태로 정리하고 `RULE n OF 3`과 page indicator로 전체 규칙 탐색을 표시했다.
홈 pager에는 저장된 모든 유효 규칙을 표시하며 오늘 적용 규칙을 먼저 두고 나머지는 다음 적용 시점
순으로 정렬한다. 현재 보이는 card와 무관하게 각 규칙은 독립적으로 동작하고 동시 충족 시 제한 앱
합집합을 적용한다. `FR-034`·`FR-035`·`FR-043`을 수정하고 `FR-044`·`DEC-021` 및 관련 task를
추가·갱신했다. 디자인·명세 문서 작업이므로 code test는 실행하지 않았고 T024는 사용자 최종 확인과
구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자가 직접 다듬은 최종 Figma를 다시 감사했다. 13개 제품 화면에서 SF Pro 외 서체,
임시 문구와 text overflow가 모두 0건이었고, 시작·종료 시각의 시·분·AM/PM wheel과 1분 단위 분 전환,
큰 지도와 반경 원, 장소 이름 직접 입력 진입, 하나로 묶인 swipe card 및 모든 규칙 pager가 유지됨을
확인했다. 사용자가 이 상태를 최종 승인해 `T024`를 완료 처리했다. 이번 작업은 디자인·문서 검수이므로
code test는 실행하지 않았으며 다음 작업은 `T025`의 실패 테스트 작성이다.
