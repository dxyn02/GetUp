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

## 전체 suite

T084에서 `GetUp.xctestplan` 전체 Swift Testing·XCTest 실행 결과, 실패, skip과 미검증 동작을 이
섹션에 추가한다.
