# 계약: 현재 규칙 구간 1회 해제

## 입력

해제 요청은 다음 값을 포함한다.

- 안정적인 `commandID`
- 현재 활성 `occurrenceID`, `ruleID`, `ruleRevision`, `endsAt`
- 진입 표면 `shield | app`
- 현재 적용된 모든 occurrence와 대상 앱에 남을 다른 제한 정보

호출자가 funding source를 선택하지 않는다. 서비스가 최신 CloudKit 상태에서 무료 우선 정책으로
결정한다.

## 사전 조건

- occurrence가 현재 시각에 활성이고 아직 release exception이 없어야 한다.
- 규칙 revision과 현재 저장 규칙이 일치해야 한다.
- iCloud 계정과 최신 CloudKit 장부가 `current` 상태이며 요청 epoch가 현재 epoch와 일치해야 한다.
  `current`는 현재 프로세스 monotonic clock 기준 5분 이내 성공 fetch, 완료된 projection, 미해결
  reconciliation 없음까지 포함하며 해제 직전 최신 occurrence·account·allowance record를 다시
  fetch한다. 프로세스 재시작 후 persisted wall-clock 시각만으로 `current`를 복원하지 않는다.
- 현재 월 무료분 또는 사용 가능한 구매 코인이 1 이상이어야 한다.
- 같은 occurrence의 진행·완료 command가 없어야 한다.

조건이 하나라도 실패하면 잔액·App Group 예외·Shield를 변경하지 않는다.
`deletionConfirmed` 또는 `resetRequired`를 포함한 비가용 상태에서는 local mirror의 잔액이 양수여도
항상 실패한다.

Shield 요청은 primary action이 release service에 전달된 시점부터 주입 가능한 monotonic clock으로
5초 deadline을 적용한다. 5초 안에 CloudKit 성공을 확인하지 못하면 이후 로컬 예외와 제한 변경을
진행하지 않는다.

## 처리 순서

T047 서비스 경계: `RuleReleaseService`의 필수 `fetchCurrentContext` provider는 매 호출마다
위 사전 조건의 fresh fetch·monotonic current 증명을 수행하고 현재 저장 규칙의 revision도 반환한다.
서비스는 await 이후 시각으로 occurrence·요청을 검증한다. 앱·Shield의 실제 provider 주입은 후속
통합에서 수행하며 fixture의 `current` 값은 운영 freshness 증명이 아니다. 무료 예약이 확정적으로
잔액 부족을 반환한 경우에만 같은 command ID로 컨텍스트를 한 번 재조회·재검증한다. 결과 불명은
구매 fallback하지 않고 기존 명령 재조정으로 넘긴다. 월간 레코드가 없을 때 정책 계산용 provisional
allowance를 별도로 저장하지 않으며, 실제 생성·예약은 repository의 atomic modify에 맡긴다.
이 서비스 연결은 기본 거부인 `verifyReservationCompatibility`를 활성화하지 않는다.

BLK-015 승인 보강: 같은 epoch·occurrence의 명령은 공통 `ReleaseOccurrenceClaim`을 원자적으로
획득해야 한다. 요청별 command ID는 재시도에 유지하되 다른 command의 중복 예약은 claim으로 막는다.
보상 완료 시에만 소유권을 released로 바꾸고 새 사용자 시도를 허용한다. 결과 불명·committed에서는
추가 예약을 허용하지 않는다. 실제 repository 경계의 서로 다른 앱·Shield command 100회로 검증한다.

1. 최신 CoinAccount, 현재 서울 기준 MonthlyAllowance와 occurrence command를 fetch한다. 현재 월
   allowance가 없고 장부가 `current`이면 quota 2 생성을 같은 atomic command에 포함한다.
2. 생성·조회한 무료분이 있으면 무료 1회를, 없으면 구매 코인 1개를 atomic reservation한다.
3. App Group에 ReleaseException을 atomic write한다.
4. 모든 규칙을 다시 평가해 예외 occurrence를 제외한 token 합집합을 Managed Settings에 적용하고
   read-back으로 확인한다.
5. CloudKit command를 committed로 전환하고 reservation을 used로 확정한다.
6. confirmed balance mirror와 사용자 내역을 갱신한다.
7. Live Activity가 foreground 조정 가능한 상태면 대표 교체 또는 종료를 수행한다. ActivityKit 실패는
   기록하되 이미 확정한 해제와 장부 commit을 취소하지 않는다.

## 실패·재조정

| 실패 지점 | 결과 |
|-----------|------|
| reservation 전 | 무변경 실패 |
| reservation 성공, 예외 저장 실패 | reservation 보상; 보상 결과 불명이면 reconciliationRequired |
| 예외 저장 성공, Shield write 실패 | 예외를 제거하고 reservation 보상; 둘 중 결과 불명이면 reconciliationRequired |
| Shield 성공, commit 결과 불명 | 예외를 유지하고 command를 조회해 committed 또는 보상 여부를 재조정 |
| Shield 요청 후 5초까지 성공 미확인 | 제한과 기존 예외를 변경하지 않고 reconciliation route를 기록한다. 같은 command ID를 조회해 늦은 reservation은 보상하고 해제되지 않은 차감을 남기지 않는다. |
| 앱/extension 종료 | 같은 command ID와 App Group 예외·CloudKit 상태를 다음 실행에서 재조정 |

`reconciliationRequired` reservation은 consumed로 표시하지 않고 `처리 확인 중`으로 표시한다. 새
해제보다 기존 명령 재조정을 우선한다.

## 다중 규칙

- Shield와 앱은 가장 먼저 활성화된 대표 occurrence를 기본 대상으로 제시한다.
- 확정 전 다른 규칙 수와 해당 앱 제한이 남는지 안내한다.
- 대표 occurrence만 예외 처리하고 다른 occurrence는 유지한다.
- 다른 규칙이 같은 대상을 제한하면 Shield가 남는 것은 성공 결과이며 중복 차감하지 않는다.

## 만료·정리

- exception은 occurrence `endsAt`에 만료된다.
- 만료된 exception은 다음 평가에서 제외하고 App Group에서 정리한다.
- 다음 반복 occurrence ID는 다르므로 이전 해제가 적용되지 않는다.
- 규칙 삭제·revision 변경은 활성 중 금지되며 만료 뒤 오래된 exception을 제거한다.

T048 저장 경계는 기존 schema 1 파일을 유지한다. `loadApplicableReleaseExceptions`에는 전체 저장
규칙의 revision 사전과 현재 활성 occurrence ID를 전달한다. `effectiveAt <= now < expiresAt`이고
활성 ID가 일치하는 예외만 반환하며, 아직 유효한 예외는 일시적인 비활성만으로 삭제하지 않는다.
만료·삭제 규칙·revision 불일치의 정리는 읽기부터 atomic 교체까지 파일 조정 안에서 수행한다.
손상·지원하지 않는 schema·정리 쓰기 실패는 오류를 전달하고 기존 bytes를 보존한다.
`saveReleaseExceptions`는 전체 collection 교체이며 외부의 분리된 load→save에 대한 병합·CAS를
제공하지 않는다. 후속 coordinator는 오래된 collection으로 다른 명령의 예외를 덮어쓰면 안 된다.

BLK-016 승인 보강: `insertReleaseException`은 최신 목록 조회·고유성 확인·추가를 한 파일 조정 안에서
수행한다. 같은 command·occurrence·내용의 재시도는 무변경 성공이며, 같은 command 또는 occurrence에
다른 내용이 있으면 충돌로 거부한다. `removeReleaseException(commandID:occurrenceID:)`는 두 식별자가
모두 일치하는 항목만 제거하고 부재·다른 소유자는 무변경으로 둔다. 반환 목록은 각 수정 직후의
snapshot이며 이후 제한 적용 시점까지 최신이라는 보장은 아니다. 보상은 과거 목록 전체를 복원하지
않고 해당 명령만 제거한 뒤 최신 규칙·예외로 재평가한다. 중단된 명령의 지연 재시도는 coordinator가
원격 command 상태를 확인해 처리하며 저장소 자체가 완료 명령 tombstone을 보관하지는 않는다.
멱등 payload 비교는 기존 ISO8601 파일 표현의 날짜 정밀도를 기준으로 한다. 메모리의 소수 초가
파일 왕복 후 달라졌다는 이유만으로 같은 요청을 충돌 처리하지 않으며 날짜 형식·schema는 바꾸지 않는다.

## 필수 테스트

- 무료 우선, 구매 fallback, 양쪽 잔액 부족
- 같은 occurrence 100회 동시 요청과 Shield·앱 교차 요청
- 사용 직전 occurrence 자동 종료
- 다른 규칙이 같은 앱을 제한하는 부분 해제
- 각 실패 지점의 보상·재조정과 앱/extension 종료
- 재실행·재부팅 후 exception 유지와 다음 occurrence 정상 제한
- 제한·Live Activity·장부 내역의 최종 일치
- 장부 비가용·삭제 확정·epoch 불일치에서 무변경 실패
- Shield의 새달 첫 요청에서 allowance 생성과 무료 1회 reservation이 하나의 명령으로 처리됨
- 주입한 monotonic clock의 4.9초 성공, 5초 성공 미확인과 초과·late commit에서 fail-closed 및 최종
  미적용 차감 0
- 앱 내 해제 뒤 Live Activity 대표 교체·종료와 ActivityKit 실패의 비치명적 격리
