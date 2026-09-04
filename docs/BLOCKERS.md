# 차단 사항

## BLK-015 — T047 occurrence 단위 중복 예약의 원자적 저장 계약

**상태**: 해결됨(RESOLVED) — 2026-09-04

`rule-release-contract.md`는 같은 occurrence의 진행·완료 command가 있으면 새 예약을 금지한다.
`data-model.md`는 command ID를 최초 시도에 만들고 재시도에 유지하며, `requestedFrom`은 감사용으로
정의한다. 그러나 `CloudKitCoinLedgerRepository.reserveMonthlyFree`·`reservePurchasedCoin`은 요청
command ID의 레코드만 조회하고 occurrence 단위 고유성은 검사하거나 atomic하게 저장하지 않는다.
따라서 서로 다른 command ID를 가진 앱·Shield 요청은 같은 occurrence에 잔액을 두 번 예약할 수 있다.
잔액 CAS는 초과 사용은 방지하지만 같은 occurrence의 중복 예약을 방지하지 않는다.

T040의 `AtomicOccurrenceReservationRepository` 대역은 `Set<String>`으로 occurrence를 별도 차단하므로
현재 100회 동시 요청 테스트만 통과시켜서는 실제 저장소의 보장을 입증할 수 없다. 기존 저장소는
같은 command의 `requestedFrom`까지 일치를 요구하며 `compensated` command를 재예약할 수 없다.
단순히 occurrence에서 command ID를 하나로 고정하면 표면 간 요청 및 보상 완료 후 새 시도 처리도
함께 결정해야 하므로 내부 helper 변경만으로 해결하지 않는다.

**권장안**: T047 범위를 확장해 epoch·occurrence별 예약 소유권 레코드를 도입한다. 무료·구매 예약과
소유권 획득을 같은 atomic modify에 넣고, 진행·완료 command가 있으면 새 예약을 거부한다.
보상 완료 때만 소유권을 원자적으로 해제해 새 사용자 시도를 허용하고, 결과 불명에서는 유지한다.
기존 command ID는 재시도 동안 유지하고 진입 표면은 최초 요청의 감사 정보로 보존한다.
저장 계약·record codec·schema 호환 전략·관련 테스트를 같은 변경에서 갱신하며, 실제 repository와
공유 상태를 갖는 database fake로 서로 다른 command ID의 앱·Shield 동시 요청을 검증한다.

**해결**: 사용자가 occurrence 소유권 저장 계약·CloudKit 스키마 보강과 실제 repository 경계 검증을
T047에 포함하도록 승인했다. T047a 모델·codec, T047b 원자 예약·보상, T047c 서비스 연결로 나누어
진행한다. 운영 스키마 배포와 기존 데이터 삭제는 승인 범위에 포함하지 않는다.

## BLK-014 — Live Activity background 시작·거리 갱신·결제 서버·월 경계

**상태**: 해결됨(RESOLVED) — 2026-09-01

`002-live-activity-coins` Phase 0 공식 문서 조사에서 현재 명세와 플랫폼 경계가 충돌하거나 제품
동작을 바꾸는 네 결정이 확인됐다.

1. 일반 로컬 `Activity.request`는 앱 foreground 시작이 원칙이므로, 앱 비실행 상태에서 자동
   제한이 시작될 때 Live Activity도 30초 이내 자동 시작하려면 ActivityKit push-to-start와 APNs
   서버가 필요하다. 서버가 없으면 앱이 제한을 foreground에서 확인한 시점에만 시작할 수 있다.
2. Live Activity는 위치를 직접 받을 수 없다. 기존 001처럼 region event와 단발 위치 확인만
   사용하면 이동 중 남은 거리의 연속 갱신을 보장할 수 없으며, 이를 보장하려면 제한 중 지속
   background location update와 추가 배터리·개인정보 범위를 허용해야 한다.
3. StoreKit 2와 CloudKit private database만으로는 같은 iCloud 계정의 편의 복구와 일반 중복 방지는
   가능하지만 App Store Server Notifications 기반 환불·철회와 강한 부정 사용 방지를 완전히
   보장하지 못한다. 권위 있는 결제 서버를 추가할지 MVP의 한계를 수용할지 결정해야 한다.
4. 기기 날짜 변경의 월간 무료 지급 악용을 막으려면 서버 시각과 비교할 고정 월 경계 시간대가
   필요하다. `Asia/Seoul`은 한국의 1일 00:00, `UTC`는 전 세계 단일 기준이지만 한국의 1일 09:00다.

**권장안**:

1. 결제 신뢰를 위한 앱 서버를 도입한다면 같은 서버에서 ActivityKit push-to-start도 제공해
   `SC-001`을 유지한다. 서버를 도입하지 않으면 foreground 시작으로 명세를 변경한다.
2. 지속 background location update는 추가하지 않고, 시스템 위치 이벤트 또는 앱 실행 때 얻은
   마지막 신뢰 거리를 표시하며 stale이면 확인 불가로 전환한다. 제한 해제 판정의 기존 저전력
   구조와 개인정보 최소화를 유지한다.
3. 유료 재화와 환불 요구를 유지하므로 거래 ID 기반 권위 장부와 App Store Server Notifications를
   처리하는 최소 앱 서버를 도입한다. CloudKit은 같은 iCloud 계정의 사용자 mirror와 복구에
   사용한다.
4. 현재 주요 사용자를 기준으로 `Asia/Seoul`을 사용한다. 전 세계 출시 정책이면 UTC 또는 사용자
   지역별 권위 시각 서비스를 별도 설계한다.

**부분 해결**: 지속 background location update는 추가하지 않고 기존 위치 이벤트 또는 앱 실행 때
얻은 마지막 신뢰 거리만 표시하며, stale이면 확인 불가로 전환한다. 월간 무료 해제권의 경계는
`Asia/Seoul` 매월 1일 00:00으로 확정했다.

**해결**: 초기 범위에서는 앱 서버를 도입하지 않는다. Live Activity는 앱이 foreground에서 활성
제한을 확인할 때 시작하며 앱 비실행 자동 시작을 약속하지 않는다. 결제는 StoreKit 검증 거래와
CloudKit private database 장부를 사용하고 앱 실행 시 거래 변경을 재조정한다. 완전한 소모성 구매
복원, private zone 삭제, 계정 불일치, 앱 비실행 중 실시간 환불 반영의 한계를 구매 전에 안내한다.
지속 background location update는 추가하지 않고 월 경계는 `Asia/Seoul`로 사용한다.

**영향**: `002-live-activity-coins`의 Phase 1 설계를 진행할 수 있다. 실제 유료 판매 규모 또는
부정 사용 위험이 커질 때 push-to-start와 App Store Server Notifications를 포함한 서버 도입을 별도
기능으로 검토한다.

## BLK-013 — Live Activity·유료 해제 코인의 핵심 범위

**상태**: 해결됨(RESOLVED) — 2026-09-01

`002-live-activity-coins` 명세를 계획하려면 다중 활성 규칙을 Live Activity에 표시하는
방식, Live Activity에서 코인 해제를 시작·확정할 범위, 재설치·기기 변경 후 미사용
유료 코인의 복구 범위를 결정해야 한다. 세 결정은 사용자 경험, 유료 잔액의 신뢰성,
개발·운영 범위를 크게 바꾸므로 임의로 확정하지 않는다.

**해결 조건**:

1. 다중 규칙 Live Activity를 규칙별로 표시할지, 단일 요약으로 표시할지 결정한다.
2. 코인 해제를 앱 내에서만 확정할지, Live Activity에서 연결 또는 즉시 사용할지 결정한다.
3. 미사용 유료 코인을 구매자 기준으로 복구할지, 기기 로컬 잔액으로 제한할지 결정한다.

**해결**: Live Activity는 가장 먼저 활성화된 대표 규칙 1개의 남은 거리·시간만 표시하고
코인 사용 행동을 제공하지 않는다. 코인은 Shield와 앱 내 화면에서만 사용한다. 유료
코인은 확인된 구매 지급과 사용·보정 내역을 iCloud에 동기화해 같은 iCloud 계정에서
미사용 잔액을 복구하되, iCloud 데이터만으로 새 구매를 인정하지 않는다.

**영향**: `002-live-activity-coins` 명세는 `$speckit-plan`으로 전환할 수 있다.

## BLK-012 — extension 위치 권한 오판정으로 시작 제한 누락

**상태**: 해결됨(RESOLVED) — 2026-08-26

T118 수정 빌드에서도 설정 시간이 지난 뒤 Screen Time 제한이 적용되지 않았다. 연결된 iPhone의 실행
프로세스를 확인한 결과 메인 앱뿐 아니라 `GetUpDeviceActivityMonitor` extension도 시스템에 의해
실행되어, callback 자체가 전혀 전달되지 않는 경우보다는 callback 내부 평가가 제한 적용을 거부하는
경로로 범위가 좁혀졌다.

callback 단계 진단을 추가해 앱 비실행 경계를 재현한 결과 규칙 2개와 위치 snapshot 2개는 정상
로드됐고 위치도 `always`·`full`·`inside`였다. 실제 실패 값은 extension의
`AuthorizationCenter.shared.authorizationStatus == notDetermined`였다. 메인 앱에서는 같은 시각
Family Controls가 `approved`였으므로 공통 상태 머신이 `missingPermissions`로 새 제한을 거부했다.
앱을 열면 메인 앱 권한 컨텍스트로 재평가돼 즉시 적용됐기 때문에 앱 상주가 필요한 것처럼 보였다.

**해결**: 메인 앱이 권한을 확인할 때 관찰 시각과 함께 최신 snapshot을 App Group `UserDefaults`에
기록한다. 시작 extension은 현재 위치 권한 또는 Family Controls가 `notDetermined`이고 snapshot이
24시간 미만일 때에만 앱의 해당 권한으로 보완한다. 현재 Family Controls `denied`, extension에서
명시적으로 확인된 위치 권한, 24시간 이상 지난 값과 decode 실패는 캐시로 덮지 않는다.

**검증**: 실기기 첫 진단은 `missingPermissions`, Family Controls `notDetermined`, 원하는 규칙 0개를
기록했다. 수정 뒤 앱을 종료하고 시작 전 Shield·적용 상태를 비운 상태에서 시간 경계를 통과하자 메인
앱 프로세스 없이 `GetUpDeviceActivityMonitor`가 실행됐고, Family Controls `approved`, 위치
`always`·`full`·`inside`, `conditionsSatisfied`, 원하는 규칙 1개, `completed`를 기록했다. 이어 Shield
Configuration·Action extension 실행과 대상 앱 Shield 표시 경로를 확인했다. 현재 `denied` 우선과
`notDetermined` 보완 회귀도 통과했다.

## BLK-011 — 설정 시간 시작 callback의 Screen Time 적용 유실

**상태**: 해결됨(RESOLVED) — 2026-08-26

설정 시간이 지난 뒤에도 선택 앱에 Screen Time 제한이 시작되지 않는 현상이 실기기에서 다시
관찰됐다. 기존 `DeviceActivityMonitorExtension.intervalDidStart`는 callback 안에서 제한을 적용하지
않고 unstructured `Task`만 예약한 뒤 반환했다. 비동기 작업은 먼저 `AppLifecycleCoordinator.restore()`로
현재 Device Activity 일정을 모두 제거·재등록하고 위치를 갱신한 뒤에야 제한 store를 썼다.

짧게 실행되는 extension이 `Task` 완료 전에 종료되면 store 쓰기가 유실될 수 있다. 또한 이미 진행
중인 interval에서 같은 일정을 제거·재등록하면 iOS가 시작 callback을 즉시 다시 전달할 수 있어
callback 재진입과 일정 경합이 발생한다. 이는 시작 callback 안에서 shield를 직접 설정하는 Apple의
사용 방식과도 맞지 않았다. 단, iOS는 기기가 사용 중일 때 Device Activity callback을 전달하므로
기기가 유휴 상태인 동안 정확한 벽시계 정각 적용 자체는 앱이 보장할 수 없다.

**해결**: `DeviceActivityIntervalStartHandler`가 callback 반환 전에 App Group의 현재 schema 규칙·위치
snapshot과 Family Controls·위치 권한을 동기적으로 읽고 공통 순수 평가기로 모든 규칙을 계산한다.
조건을 충족한 규칙의 앱·카테고리·웹 도메인 합집합을 단일 `getup.restriction` store에 즉시 쓰고
read-back을 확인한 뒤 적용 revision을 저장한다. 시작 callback에서는 일정·region 전체 복구를
호출하지 않으며, snapshot read 또는 store 검증 실패 시 기존 일정·shield·상태를 보존한 채 일정
초기화 없는 시간 재평가만 후속 시도한다.

**검증**: 만족 규칙 합집합 동기 적용, 위치 외부·권한 거부 시 미적용, snapshot 실패 시 기존 상태
보존 회귀와 store read-back 실패 시 상태 미저장을 포함한 adapter·coordinator 대상 테스트 24개와
전체 `GetUpTests` 203회 실행이 실패·skip 없이 통과했다. 앱과 세 Screen Time 확장을 포함한
Simulator build도 통과했다. 실제 callback 전달과
system shield 반영은 수정 빌드로 T083·T085 실기기 인수에서 재확인한다.

## BLK-010 — Family Controls 배포 entitlement·App Group 계정 증적

**상태**: 열림(OPEN) — 2026-08-25

저장소에서는 app과 세 Screen Time extension의 Family Controls·App Group entitlement 선언 및 resolved
Bundle ID를 확인할 수 있다. 사용자는 Apple Developer에 `com.dxyn02.GetUp` namespace의 네 명시적
App ID를 등록하고 `group.com.dxyn02.GetUp`을 네 App ID에 할당했으며 Family Controls Distribution
`Assigned` 상태와 갱신된 profile을 사용한 실기기 설치·실행까지 확인했다. 그러나 extension을 포함한
네 Bundle ID의 서명 entitlement와 배포 archive 증적은 현재 작업 환경에서 확인할 수 없다.

이 상태는 미신청 또는 거절을 의미하지 않지만, 승인 완료로 추정할 수도 없다. Account Holder 또는
Admin이 `docs/ENTITLEMENTS.md`의 승인 증적 기록표를 갱신하고, 네 target이 포함된 서명 archive와
entitlement 적용 실기기 동작을 확인하기 전까지 TestFlight·App Store 배포 준비와 T085의 실제
Family Controls·App Group 인수 검증을 완료할 수 없다.

**해결 조건**:

1. 네 Bundle ID의 Family Controls Distribution `Assigned`와 profile 갱신은 사용자 확인 완료.
2. Account Holder 또는 Admin이 `group.com.dxyn02.GetUp` 등록과 네 App ID 할당의 지속 가능한 증적을
   기록한다.
3. 네 배포 profile을 갱신하고 서명 archive의 실제 entitlement를 검사한다.
4. 개인정보를 제거한 증적 reference와 확인자·확인일을 `docs/ENTITLEMENTS.md`에 기록한다.

**후속 작업 영향**: T082 문서화는 완료할 수 있다. T083의 자동 계측 구조와 문서 형식은 진행할 수
있으며 2026-08-25에 활성화 100회·해제 100회 자동 계측은 통과했다. 갱신 profile의 실기기 설치가
확인되어 실제 `ManagedSettingsStore` 관찰은 진행할 수 있다. 다만 서명 archive entitlement 증적,
T085의 배포 인수와 feature 완료 판정은 남은 조건에 의존한다.

## BLK-001 — 사용자 지정 일정 최소 길이

**상태**: 해결됨(RESOLVED) — 2026-08-20

Apple Device Activity는 15분보다 짧은 모니터링 구간을 거부하지만, 기능 spec에는 사용자 지정
시간대의 최소 길이가 정의되어 있지 않았다. 사용자 결정이 필요했다. 최소 길이를 15분으로
제한하거나, 더 짧은 구간의 자동 제한 요구사항을 변경해야 했다.

**해결**: 사용자 지정 일정의 최소 길이를 15분으로 제한한다.

## BLK-002 — 플랫폼 event 지연과 재부팅 경계

**상태**: 해결됨(RESOLVED) — 2026-08-20

region 및 Device Activity event 전달은 iOS가 제어하므로 앱은 물리적 위치 경계 또는 정확한
벽시계 시각을 기준으로 현재의 30초 결과를 보장할 수 없다. 재부팅 후 첫 기기 잠금 해제 전에는
위치 자동화를 사용할 수 없다. 신뢰 가능한 플랫폼 event 이후부터 30초 목표를 측정하고 재부팅
복구를 첫 잠금 해제부터 시작하도록 정의하거나, 제품 요구사항을 변경하는 사용자 결정이 필요했다.

**해결**: 신뢰 가능한 조건 변경이 확인된 뒤부터 30초 목표를 측정하고, 기기의 첫 잠금 해제 후
자동 재부팅 복구를 시작한다.

## BLK-003 — 기준 위치 선택 방식

**상태**: 해결됨(RESOLVED) — 2026-08-20

기능 spec은 사용자가 기준 위치를 설정할 수 있어야 한다고 정의하지만, 현재 위치만 사용할지,
지도에서 핀을 지정할지, 장소 검색까지 제공할지는 정의하지 않는다. 각 선택지는 사용자 경험,
권한 요청 시점, UI 범위 및 테스트 task를 변경하므로 사용자 결정이 필요하다.

**해결**: 지도에서 핀을 이동해 기준 위치를 지정하고 현재 위치 바로가기를 제공한다. MVP에서는
장소·주소 검색을 제공하지 않는다.

## BLK-004 — 홈 화면의 새 규칙과 MVP 규칙 개수

**상태**: 해결됨(RESOLVED) — 2026-08-21

현재 기능 spec은 MVP에서 단일 제한 규칙만 지원하고, 저장된 규칙이 있으면 새 규칙 추가 대신
기존 규칙을 수정하도록 정의한다. 새 홈 요구사항은 오늘 또는 다음날의 규칙을 보여 주고 새로운
규칙 설정으로 이동하는 버튼을 포함하므로, 여러 규칙을 동시에 저장하는 기능인지 기존 단일 규칙을
교체하는 진입점인지 결정해야 한다. 이 선택은 영속성 모델, 규칙 정렬·충돌 처리, 홈 화면 상태,
테스트와 기존 `T017`·`T018` 구현의 변경 범위에 영향을 준다.

**해결**: MVP부터 여러 독립 제한 규칙을 추가·확인·수정한다.

## BLK-005 — 여러 규칙의 활성 시간 중첩

**상태**: 해결됨(RESOLVED) — 2026-08-21

여러 규칙이 같은 시간에 활성화되고 각각의 위치 조건까지 충족될 수 있다. 이때 제한 앱 집합을
합칠지, 우선순위가 높은 하나의 규칙만 적용할지, 시간 중첩 저장 자체를 막을지에 따라 제한 상태
계산과 shield 해제 조건이 달라지므로 사용자 결정이 필요하다.

**해결**: 조건을 충족한 모든 규칙의 제한 앱을 합집합으로 적용한다. 일부 규칙이 끝나면 남아 있는
활성 규칙이 요구하지 않는 앱만 해제한다.

## BLK-006 — DST 전환일의 존재하지 않거나 반복되는 현지 시각

**상태**: 해결됨(RESOLVED) — 2026-08-23

T025는 DST의 존재하지 않는 시각과 반복 시각에 대한 기대 결과를 테스트하도록 요구하지만, 현재
명세는 전환일의 구체적인 보정 규칙을 정의하지 않는다. 예를 들어 봄 전환일의 `02:30` 시작은 그날
규칙을 건너뛸 수도 있고 다음 유효 시각인 `03:00`으로 보정할 수도 있다. 가을 전환일의 `01:30`은
첫 번째 발생과 두 번째 발생 중 어느 경계를 사용할지에 따라 실제 제한 시간이 달라진다.

**선택지**:

1. 현지 시각 의도를 보존한다. 존재하지 않는 경계는 다음 유효 시각으로 이동하고, 반복되는 시작
   시각은 첫 번째 발생, 반복되는 종료 시각은 두 번째 발생을 사용한다.
2. 경계가 존재하지 않거나 반복되어 모호한 전환일에는 해당 규칙을 실행하지 않는다.

**권장안**: 1안. 사용자가 선택한 요일의 규칙이 예고 없이 하루 전체 누락되는 것을 막고, 반복되는
현지 시각 구간을 조기에 해제하지 않는다. 결정 후 T025의 DST 기대값, `spec.md`, `data-model.md`,
`restriction-evaluation-contract.md` 및 `DECISIONS.md`에 같은 규칙을 기록해야 한다.

**해결**: 1안을 선택한다. DST 전환으로 존재하지 않는 시작·종료 경계는 각각 다음 유효 현지
시각으로 이동한다. 반복되는 시작 경계는 첫 번째 발생, 반복되는 종료 경계는 두 번째 발생을
사용한다.

## BLK-007 — Restricted App Shield의 지도 확인 진입과 iOS 지원 범위

**상태**: 해결됨(RESOLVED) — 2026-08-24

사용자는 `US2-LF-02`에서 어떤 위치로부터 얼마나 벗어나야 하는지 문구 또는 지도 화면으로 확인하고
싶다고 요청했다. 저장 장소 이름·설정 반경·종료 시각은 현재 `ShieldConfiguration`의 title과
subtitle로 안내할 수 있어 로우파이에 반영했다. 그러나 시스템 shield에는 임의의 Map UI를 삽입할 수
없다. 지도 화면을 열려면 secondary action과 앱 진입 동작이 필요하지만,
`ShieldActionResponse.openParentalControlsApp`은 iOS 26.5부터 제공된다. 이는 현재 최소 지원 버전
iOS 26.0과 secondary action·GetUp 자동 실행을 제공하지 않는 `shield-ui-contract.md`에 영향을 준다.

**선택지**:

1. MVP에서는 shield에 `집 중심에서 1km 밖 또는 09:00 AM`처럼 장소·반경·종료 시각을 직접
   표시하고 지도 버튼은 제공하지 않는다. iOS 26.0 이상에서 계약 변경 없이 일관되게 동작한다.
2. `지도에서 보기` secondary action을 추가하고 iOS 26.5 이상에서 GetUp의 지도 화면을 연다.
   iOS 26.0~26.4에서는 버튼을 숨기거나 별도 fallback을 정의해야 하며 contract·task·테스트를
   변경해야 한다. 최소 지원 버전을 iOS 26.5로 올리는 방안도 별도 제품 결정이 필요하다.

**권장안**: 1안. 사용자가 필요한 장소와 이탈 거리를 제한 앱을 떠나지 않고 즉시 확인할 수 있고,
현재 MVP의 최소 지원 버전과 단일 닫기 행동 계약을 유지한다. 지도 진입은 최소 OS와 shield 계약을
함께 재검토하는 후속 범위로 둔다.

**해결**: 1안을 선택한다. MVP의 모든 지원 버전에서 secondary action을 제공하지 않고,
저장 장소 이름·설정 반경·종료 시각을 shield 제목과 설명으로 안내하며 primary `앱 닫기` 행동만
제공한다. 향후 `오늘만 허용`과 인앱결제를 통한 일시 해제 아이디어는 현재 기능에 포함하지 않고
별도 spec과 플랫폼·결제 정책 검토를 거쳐 결정한다.

## BLK-008 — 여러 규칙 활성화 상태의 런타임 저장 계약

**상태**: 해결됨(RESOLVED) — 2026-08-24

`FR-038`·`FR-044`와 `DEC-016`은 시간·위치 조건을 충족한 모든 규칙의 앱 token 합집합을 적용하고,
일부 규칙이 끝나면 남은 활성 규칙만으로 합집합을 다시 계산하도록 요구한다. 그러나 T050 착수
시점의 런타임 계약은 다음과 같이 단일 규칙만 표현한다.

- `LocationConditionSnapshot`과 `location-conditions.json`은 rule ID 없이 하나의 `ruleRevision`만
  저장한다.
- `AppliedRestrictionState`는 하나의 `ruleRevision`과 Boolean만 저장한다.
- `RestrictionApplying.applyRestriction(for:)`는 하나의 `RestrictionRuleSnapshot`만 받는다.
- `RestrictionStateMachine.evaluate(_:)`는 하나의 규칙과 하나의 위치 snapshot만 평가한다.

이 상태로 T050을 연결하면 두 규칙이 동시에 활성화될 때 마지막으로 평가된 규칙이 앞선 규칙의
shield를 덮어쓰거나 제거할 수 있어 명세를 위반한다. 반대로 T050에서 다중 규칙 계약을 도입하면
공유 JSON schema, App Group 적용 상태, adapter API와 기존 테스트 fixture를 함께 변경해야 하므로
중대한 저장 계약 변경에 해당한다.

**선택지**:

1. T050 범위에서 다중 규칙 런타임 계약을 도입한다. 위치 상태를 rule ID별 collection으로 저장하고,
   적용 상태는 활성 rule ID·revision 집합과 최종 앱 token 합집합을 식별할 수 있게 변경한다.
   coordinator는 모든 유효 규칙을 독립 평가한 뒤 합집합을 한 번 적용한다. 기존 단일 위치 snapshot은
   명시적인 migration 또는 안전한 `unavailable` 처리 규칙을 함께 정의한다.
2. T050을 단일 규칙 활성화 경로로만 구현하고 다중 규칙 합집합과 저장 migration은 후속 task로
   분리한다. 이 경우 현재 `FR-038`·`FR-044`를 만족하지 못하는 기간과 완료 task를 명시하고 새로운
   task를 `tasks.md`에 추가해야 한다.

**권장안**: 1안. 이미 확정된 다중 규칙 제품 동작을 실제 런타임 경계에서 보존하고, T051의 extension
복구 경로가 잘못된 단일 규칙 저장 계약에 의존하기 전에 바로잡을 수 있다. 결정되면
`data-model.md`, `shared-storage-contract.md`, `restriction-evaluation-contract.md`,
`PlatformContracts.swift` 및 관련 테스트를 같은 내용으로 갱신해야 한다.

**해결**: 사용자가 1안을 선택했다. T050에서 위치 상태를 rule ID별 collection으로 저장하고,
적용 상태는 활성 rule ID·revision 집합을 추적한다. coordinator는 모든 유효 규칙을 독립 평가해
활성 규칙의 앱 token 합집합을 한 번 적용한다. rule ID가 없는 기존 schema 1 위치 snapshot은 어느
규칙의 근거인지 안전하게 판별할 수 없으므로 migration 시 빈 collection으로 변환하고, 새 위치
근거가 기록될 때까지 각 규칙을 `unavailable`로 평가한다.

## BLK-009 — 동일 앱에 여러 활성 규칙이 적용될 때 shield 해제 조건 표시

**상태**: 해결됨(RESOLVED) — 2026-08-24

T052의 승인된 하이파이는 하나의 저장 장소·반경·종료 시각을 사용해 `집 1km 밖으로 이동하세요`와
같은 shield 문구를 표시한다. 그러나 `FR-038`·`FR-044`와 `DEC-016`에 따라 같은 앱 token이 두 개
이상의 활성 규칙에 포함될 수 있다. 이 경우 앱 제한이 실제로 해제되려면 해당 앱을 선택한 각 활성
규칙의 `(장소 밖 또는 시간 종료)` 조건이 모두 끝나야 한다.

iOS 26.5의 `ManagedSettings.Application.token`으로 현재 shield 대상 앱과 활성 규칙의 token을
비교할 수는 있다. 하지만 여러 규칙 중 하나의 장소·반경·시각만 표시하면 그 조건만 끝났을 때 앱을
다시 쓸 수 있는 것처럼 잘못 안내한다. 모든 조건을 나열하면 규칙 개수에 따라 system-owned shield
설명이 길어져 Dynamic Type과 화면 높이에서 잘릴 수 있으며, 승인된 단일 조건 하이파이와도 달라진다.

**선택지**:

1. 단일 규칙일 때는 승인된 장소·반경·종료 시각 문구를 사용하고, 두 개 이상일 때는
   `이 앱에 여러 제한 규칙이 활성화되어 있어요. 각 규칙의 위치 또는 시간이 끝나면 다시 사용할 수
   있어요.`처럼 규칙 수와 정확한 결합 의미를 짧게 안내한다. 개별 조건은 나열하지 않는다.
2. 두 개 이상일 때도 해당 앱에 적용된 모든 규칙의 `장소·반경 또는 종료 시각`을 subtitle에
   나열한다. 정보는 완전하지만 규칙 수 제한과 overflow·Dynamic Type 처리 규칙을 새로 정하고
   하이파이를 다시 승인해야 한다.
3. 안정적인 정렬의 첫 규칙 또는 가장 늦은 종료 시각 규칙 하나만 표시한다. 위치 조건 조합 때문에
   실제 해제 시점을 대표하지 못해 잘못된 안내가 될 수 있다.

**권장안**: 1안. 실제 해제 조건을 거짓 없이 전달하면서 ManagedSettingsUI가 소유하는 제한된
layout과 Dynamic Type에서 핵심 문구가 잘릴 위험을 줄인다. 결정되면 `shield-ui-contract.md`와
US2 하이파이의 다중 규칙 상태를 갱신하고, 단일·다중·snapshot 불가 fallback 콘텐츠를 테스트한 뒤
T052를 구현해야 한다.

**해결**: 사용자가 1안을 선택했다. shield 대상 앱에 적용된 활성 규칙이 하나이면 승인된
장소·반경·종료 시각 상세 문구를 사용하고, 두 개 이상이면 규칙 수와 각 규칙의 위치 또는 시간이
모두 끝나야 한다는 짧은 요약을 사용한다. snapshot 또는 app token을 읽지 못하면 제한이 활성화된
사실과 자동 종료 조건만 안내하는 개인정보 없는 fallback을 표시한다.
