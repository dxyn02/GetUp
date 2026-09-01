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
