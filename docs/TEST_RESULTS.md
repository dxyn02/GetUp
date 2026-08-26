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

**상태**: 미실행 — BLK-010

Apple Developer 계정의 Family Controls 배포 승인, App Group 할당과 갱신된 provisioning profile
증적이 없어 실제 `ManagedSettingsStore` 및 선택 앱 사용 가능 상태를 현재 환경에서 검증할 수 없다.
승인 증적이 준비되면 다음 표에 자동 계측과 섞지 않고 기록한다.

| 실행 ID | 기기·OS | 경로 | trigger 종류 | 물리 경계 시각 | event `confirmedAt` | store read-back 시각 | 대상 앱 반영 시각 | event 전달 지연 | SLA 지연 | 결과 | 증적 reference |
|---|---|---|---|---|---|---|---|---:|---:|---|---|
| 미실행 | 확인 필요 | 활성화 | 시간 시작 또는 위치 진입 | — | — | — | — | — | — | BLK-010 | `docs/ENTITLEMENTS.md` |
| 미실행 | 확인 필요 | 해제 | 시간 종료 또는 위치 이탈 | — | — | — | — | — | — | BLK-010 | `docs/ENTITLEMENTS.md` |

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
- Core Location region 진입·이탈 callback과 여섯 반경의 실외 정확도
- app background·terminated 상태와 재부팅 첫 잠금 해제 뒤 자동 복구
- 실제 시스템 설정에서 권한 철회 후 복구
- 실기기의 Dynamic Type·VoiceOver·Reduce Motion 및 Shield system-owned layout
- T083의 실제 `ManagedSettingsStore` 활성화·해제 각 100회 latency 관찰

위 항목은 자동 suite 통과로 완료 처리하지 않으며 T083·T085와 BLK-010의 실기기·서명 인수 범위를
유지한다.
