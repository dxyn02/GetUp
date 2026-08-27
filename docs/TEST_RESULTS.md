# 테스트 결과

## 기록 원칙

- 자동 계측과 실기기 관찰을 같은 결과로 합치지 않는다.
- 앱의 30초 SLA는 신뢰 가능한 time·location event의 `confirmedAt`부터 GetUp named
  `ManagedSettingsStore` read-back 확인까지 측정한다.
- 물리적 시간·위치 경계부터 iOS event callback 전달까지의 지연은 SLA에 포함하지 않고 별도
  관찰값으로 기록한다.
- 자동 계측의 store access는 protocol test double이므로 실제 시스템 shield나 선택 앱의 사용 가능
  상태를 입증하지 않는다.
- 실기기 관찰은 실제 대상 앱에서 shield 표시 또는 해제를 확인한 시각까지 포함한다.

## T120 — 앱 비실행 시간 시작 실기기 진단

**상태**: 통과

2026-08-26 iPhone 17, iOS 26.6.1에서 `intervalDidStart`의 개인정보 없는 단계 record를 App Group에
추가하고 실패를 재현했다. 첫 record는 규칙 2개·위치 snapshot 2개·시작 위치 `inside`를 읽었지만,
앱에서 `approved`인 Family Controls가 extension에서 `notDetermined`로 반환돼
`startedRuleDecision=missingPermissions`, `desiredRuleCount=0`, `stage=completed`였다.

extension의 `notDetermined` Family Controls만 24시간 미만의 앱 snapshot으로 보완하고 현재 `denied`는
우선하도록 수정했다. 시작 전 단일 store와 적용 revision을 비우고 메인 앱을 종료한 뒤 실제 시간
경계를 통과한 결과 monitor extension이 앱 없이 실행됐고 다음 값을 기록했다.

- Family Controls `approved`, 위치 권한 `always`, 정확도 `full`
- 시작 위치 `inside`, 위치 근거 나이 약 13초
- `startedRuleDecision=conditionsSatisfied`, `desiredRuleCount=1`
- `currentAppliedRuleCount=0`, `stage=completed`
- 메인 앱 프로세스 없음, Device Activity Monitor·Shield Configuration·Shield Action extension 실행

관련 adapter 회귀는 extension `notDetermined` 보완과 현재 `denied` 우선을 모두 통과했다. 이 결과로
BLK-012를 해결 처리한다. 격리 DerivedData `/tmp/getup-interval-start-final-tests`의 전체
`GetUpTests` 209개가 통과했고 실패·skip·expected failure는 모두 0이다. Swift Testing 동적 인자를
포함한 device configuration 실행은 243회 통과했다.

## T119 — extension 권한 snapshot 보완

**상태**: 자동 검증·실기기 설치 통과, 실제 예약 경계 관찰 대기

실기기 프로세스 조사에서 `GetUpDeviceActivityMonitor`가 시스템에 의해 실행된 사실을 확인했다. 시작
handler가 extension에서 새 `CLLocationManager`의 권한을 즉시 읽을 때 `notDetermined`가 반환되면,
앱에서 이미 승인된 Always·Full Accuracy와 달라 새 제한이 거부될 수 있는 경로를 수정했다.

- 메인 앱이 최신 권한과 관찰 시각을 App Group에 기록한다.
- extension의 위치 권한이 `notDetermined`이고 기록이 24시간 미만일 때만 앱 위치 권한·정확도를 쓴다.
- 현재 Family Controls 철회와 명시적 위치 권한 상태는 캐시보다 우선한다.
- 24시간 이상 지난 값과 손상된 값은 사용하지 않는다.

2026-08-26 iPhone 17 Pro iOS 26.5 Simulator의 격리 DerivedData
`/tmp/getup-reassert-missing-shield-tests`에서 전체 `GetUpTests` 208개가 통과했고 실패·skip·expected
failure는 모두 0이다. Swift Testing 동적 인자를 포함한 device configuration 실행은 242회 통과했다.
같은 최종 코드로 iPhone 17 iOS 26.6.1 대상 서명 build와 연결 기기 설치가 성공했다. 설치 뒤 앱을
실행해 규칙 복원·최신 권한 기록을 유도하고 정상 종료했으며, 실제 다음 설정 시간의 system shield
표시는 BLK-012와 T083·T085에서 후속 관찰한다.

## T117 — 네 단계 반경 선택

**상태**: 자동 테스트 통과

**실행 환경**: 2026-08-26, iPhone 17 Pro Simulator, iOS 26.5, arm64,
`CODE_SIGNING_ALLOWED=NO`, 격리 DerivedData `/tmp/getup-radius-four-options`

- `RadiusOption.allCases`와 validator가 100m·250m·500m·1km만 허용한다.
- 네 반경 각각의 내부·정확한 경계·외부·오차 중첩 위치 판정이 통과한다.
- slider UI를 100m→250m→500m→1km로 조절하고 1km 저장 요약으로 복귀하는 회귀가 통과한다.
- 전체 `GetUpTests` 193개 test case, 동적 인자 포함 227회가 실패·skip 없이 통과했다.
- 기존 2km·3km·4km·5km 저장값은 사용자 결정에 따라 migration·복원 범위에서 제외했다.

T118 시간 시작 동기 적용 변경과 같은 브랜치로 합친 뒤 전체 `GetUpTests` 203회가 다시 실패·skip 없이
통과했다. `testRequiredInputValidationAndApplicationSelection` UI 회귀 1개도 네 반경을 차례로 조절하고
1km 저장 요약을 확인해 통과했으며, 앱과 세 Screen Time 확장을 포함한 Simulator build가 성공했다.

## T083 — 제한 활성화·해제 지연

### 합격 기준

| 경로 | 최소 사례 수 | 판정값 | 합격 기준 |
|---|---:|---|---|
| 활성화 | 100 | p95 | 30초 이하 |
| 해제 | 100 | 전체 사례와 최대값 | 모든 사례 30초 이하 |

### 자동 계측

**상태**: 통과

**실행 환경**: 2026-08-25, iPhone 17 Pro Simulator, iOS 26.5, arm64,
`CODE_SIGNING_ALLOWED=NO`

**측정 경계**:

1. 테스트 clock의 신뢰 가능한 `confirmedAt`을 기록한다.
2. `RestrictionCoordinator`가 location event를 평가한다.
3. `ManagedSettingsRestrictionAdapter`가 GetUp named store에 application token 집합 또는 `nil`을 쓴다.
4. adapter가 같은 store를 read-back해 기대값과 일치함을 확인한다.
5. adapter가 적용 상태 snapshot을 저장하고 반환한 뒤 coordinator가 `effectCompletedAt`을 기록한다.

| 경로 | 사례 수 | 관찰값 | 기준 | 결과 |
|---|---:|---:|---:|---|
| 활성화 `applyShield` | 100 | p95 0.000149초 | p95 ≤ 30초 | 통과 |
| 해제 `removeShield` | 100 | 최대 0.000152초, 100/100 기준 이내 | 전체 ≤ 30초 | 통과 |

**실행 명령**:

```sh
xcodebuild test -project GetUp.xcodeproj -scheme GetUp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:GetUpTests/RestrictionLatencyTests \
  CODE_SIGNING_ALLOWED=NO
```

구조화된 console marker는 다음 형식을 사용한다.

```text
RESTRICTION_LATENCY_RESULT mode=automatic effect=<effect> samples=<count> <metric>_seconds=<seconds> limit_seconds=30 result=<PASS|FAIL>
```

대상 성능 테스트 1개와 adapter suite 7개, 총 8개가 통과했으며 실패·skip은 없다. 이어 실행한 전체
`GetUpTests`는 147개 test case, 동적 인자 포함 총 190회가 모두 통과했고 실패·skip은 없다.

### 실기기 관찰

**상태**: 일부 기능 경로 확인, 100회 계측 및 archive 증적 미완료 — BLK-010

갱신 profile로 설치한 실기기에서 단일 합집합 store 복원 뒤 Screen Time 제한 적용과 시간 종료 자동
해제는 사용자가 확인했다. 이후 설정 시간 시작 제한이 다시 적용되지 않는 실패가 관찰되어 T118에서
callback 동기 적용 경로를 수정했다. 위치 이탈은 기존 빌드에서 앱을 한 번 열고 나와야 해제되는
실패가 관찰되어 T116에서 누락된 Core Location region delegate 경로를 수정했다. 수정 빌드의 시작
적용, background·시스템 종료 위치 이탈 재검증과 100회 latency 측정은 아직 완료되지 않았다.

| 실행 ID | 기기·OS | 경로 | trigger 종류 | 물리 경계 시각 | event `confirmedAt` | store read-back 시각 | 대상 앱 반영 시각 | event 전달 지연 | SLA 지연 | 결과 | 증적 reference |
|---|---|---|---|---|---|---|---|---:|---:|---|---|
| 수동 관찰 | 사용자 실기기 | 활성화 | 시간 시작 | 미기록 | 미기록 | 미기록 | 미적용 | 미계측 | 미계측 | 실패, T118 수정 | 사용자 확인 |
| 수동 관찰 | 사용자 실기기 | 해제 | 시간 종료 | 미기록 | 미기록 | 미기록 | 정상 해제 확인 | 미계측 | 미계측 | 기능 경로 통과 | 사용자 확인 |
| 수동 관찰 | 사용자 실기기 | 해제 | 위치 이탈 | 미기록 | callback 미연결 | 앱 진입 뒤 갱신 | 앱 진입 뒤 해제 | 미계측 | 미계측 | 실패, T116 수정 | 사용자 확인 |

실기기 판정 시 활성화는 100개 이상 사례의 p95, 해제는 100개 이상 모든 사례와 최대값을 별도
요약한다. store read-back과 대상 앱 반영 시각이 다르면 SLA 지연은 더 늦은 대상 앱 반영 시각을
사용한다.

## T113 — 시간 종료 callback 동기 해제

**상태**: T114에서 규칙별 store 방식 대체 — 실기기 제한 미적용 회귀

### 자동 검증

`DeviceActivityIntervalEndHandler` 회귀는 종료된 규칙의 store만 동기 해제하고 다른 활성 규칙의
store와 적용 상태를 유지하는지 검증한다. 기존 단일 합집합 store가 함께 남은 경우에는 남은 규칙의
독립 store가 모두 존재할 때만 legacy store를 제거하고, 안전하게 분리할 수 없는 경우 아무 상태도
부분 변경하지 않은 채 coordinator 호환 경로로 넘기는 사례를 포함한다.

2026-08-26 iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 194개 test case, 동적 실행 포함
237회가 실패·skip 없이 통과했다. 앱·Device Activity Monitor·Shield 확장을 포함한 generic Simulator
build도 통과했다. 이 자동 검증은 실제 iOS callback 전달 시각이나 대상 앱의 system shield 해제를
입증하지 않으며, 해당 관찰은 T083·T085 실기기 인수에 남긴다.

## T114 — 단일 제한 store 복원

T113의 규칙별 named store 적용 후 실기기에서 Screen Time 제한이 전혀 적용되지 않는 회귀가 보고됐다.
실제 제한 적용을 기존 단일 `getup.restriction` 합집합 store로 복원하고, 종료 callback은 마지막 활성
규칙만 동기 해제하도록 축소했다. 다른 활성 규칙이 남거나 현재 적용 상태에 없는 stale callback인
테스트에서는 store와 적용 상태가 변경되지 않고 coordinator 호환 경로로 넘어가는 것을 검증한다.

2026-08-26 iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 193개 test case, 동적 실행 포함
236회가 실패·skip 없이 통과했다. 앱과 세 Screen Time 확장을 포함한 generic Simulator build도
통과했다. 같은 날 사용자가 수정 빌드의 실기기에서 Screen Time 제한이 정상 적용되고 설정 시간 종료
뒤 실제 shield가 자동 해제됨을 확인했다. 이 확인은 기능 경로 1회 이상의 수동 인수 결과이며,
T083의 활성화·해제 각 100회 latency 판정을 대체하지 않는다.

## T115·T116 — 제한 store 재조정과 background 위치 event 연결

T115는 현재 적용 revision이 활성인 경우에도 adapter가 실제 단일 store selection을 read-back하고,
application shield가 유실됐으면 같은 revision을 다시 적용하도록 보강했다. T116은 앱 launch 시점의
`CLLocationManagerDelegate`가 `didEnterRegion`·`didExitRegion`을 받아 GetUp rule ID를 복원하고,
시스템이 확인한 전이를 `.regionEvent` snapshot으로 저장한 뒤 제한 합집합을 즉시 재평가한다.

2026-08-26 iPhone 17 Pro iOS 26.5 Simulator에서 위치 adapter 대상 7개 test case(동적 실행 포함
27회), 전체 `GetUpTests` 195개 test case(동적 실행 포함 238회)가 실패·skip 없이 통과했다. 앱과 세
Screen Time 확장을 포함한 generic Simulator build도 통과했다. Simulator 검증은 Core Location의
실제 background wake와 system shield 반영을 입증하지 않으므로, 수정 빌드의 suspended·background·
시스템 종료 상태 위치 이탈은 T083·T085 실기기 표에 후속 기록한다.

## T118 — 시간 시작 callback 동기 제한 적용

실기기에서 설정 시간이 지나도 Screen Time 제한이 시작되지 않는 회귀를 분석했다. 기존
`intervalDidStart`는 unstructured `Task`만 예약하고 반환했으며, Task 내부에서 현재 Device Activity
일정을 모두 제거·재등록하고 위치를 갱신한 뒤 제한을 적용했다. extension이 먼저 종료되면 store
쓰기가 유실될 수 있고, 진행 중인 interval 재등록은 callback 재진입과 경합을 만들 수 있었다.

`DeviceActivityIntervalStartHandler`가 callback 안에서 현재 schema 공유 snapshot과 권한을 읽어
모든 규칙을 동기 평가하고, 단일 store의 제한 합집합을 쓰고 read-back을 확인하도록 수정했다. 만족한
두 규칙의 합집합 적용, 위치 외부·권한 거부 시 미적용, snapshot read 실패 시 기존 shield·revision
보존과 store read-back 실패 시 상태 미저장 회귀를 추가했다. 2026-08-26 iPhone 17 Pro iOS 26.5
Simulator에서 adapter·coordinator 대상 24개 test case가 실패·skip 없이 통과했다. 실제 Device
Activity callback 전달과 system shield 반영은
Simulator가 입증하지 못하므로 T083·T085 실기기 표에 후속 기록한다. 이어 실행한 전체 `GetUpTests`
203회가 실패·skip 없이 통과했고, 앱과 세 Screen Time 확장을 포함한 Simulator build도 통과했다.

## 전체 suite

### T084 — `GetUp.xctestplan` 전체 실행

**상태**: 통과

**실행 환경**: 2026-08-26, iPhone 17 Pro Simulator, iOS 26.5, arm64, Xcode 26.6.2,
`CODE_SIGNING_ALLOWED=NO`, `GetUp.xctestplan` 기본 실행 configuration

| 테스트 bundle | test case | 결과 |
|---|---:|---|
| `GetUpTests` | 193 | 통과 |
| `GetUpUITests` | 41 | 통과 |
| 합계 | 234 | 통과 |

- 실패: 0
- skip: 0
- expected failure: 0
- Swift Testing 동적 인자를 포함한 device configuration 실행: 277회 통과
- 전체 소요 시간: 약 284.6초
- 최장 test: `testRequiredInputValidationAndApplicationSelection()` 13.82초, 통과
- 결과 bundle:
  `/Users/andy/Library/Developer/XcodeBuildMCP/workspaces/GetUp-6908c4ee558c/result-bundles/test_sim_2026-08-26T08-04-48-093Z_pid78162_1323f01c.xcresult`

17개 build warning은 Simulator의 Apple 서명 XCTest·Testing 지원 binary를 strip하지 않는다는
메시지로, 실패나 skip과 연결되지 않았다.

### Simulator에서 미검증된 동작

- 실제 Family Controls system picker의 사용자 선택과 배포 entitlement 적용
- 실제 대상 앱·카테고리·웹 도메인의 system shield 표시 및 해제
- Core Location region 진입·이탈 callback과 네 반경의 실외 정확도
- app background·terminated 상태와 재부팅 첫 잠금 해제 뒤 자동 복구
- 실제 시스템 설정에서 권한 철회 후 복구
- 실기기의 Dynamic Type·VoiceOver·Reduce Motion 및 Shield system-owned layout
- T083의 실제 `ManagedSettingsStore` 활성화·해제 각 100회 latency 관찰

위 항목은 자동 suite 통과로 완료 처리하지 않으며 T083·T085와 BLK-010의 실기기·서명 인수 범위를
유지한다.
