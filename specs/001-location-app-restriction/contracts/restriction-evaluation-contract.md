# Contract: Restriction Evaluation

## Purpose

메인 앱, 위치 처리, Device Activity 확장이 같은 비즈니스 규칙으로 제한 상태를 결정하도록 하는
순수 도메인 계약이다.

## Input

`evaluate`는 다음 값을 명시적으로 받는다.

- 규칙 snapshot 또는 없음
- 현재 `Date`, `Calendar`, `TimeZone`
- 위치 상태 `inside | outside | unavailable`
- Family Controls 및 위치 권한 상태
- 현재 shield 적용 여부와 마지막 적용 rule revision

전역 현재 시각, 현재 위치, 권한 singleton 또는 저장소를 함수 내부에서 직접 읽지 않는다.

## Output

```text
EvaluationDecision
├── presentationState
├── desiredRestriction: active | inactive | preserve
├── effect: applyShield | removeShield | none
└── reason
```

## Invariants

- 선택 요일의 유효 시간대와 신뢰 가능한 내부 위치가 모두 참일 때만 새 shield를 적용한다.
- 시간 종료는 위치 상태와 관계없이 shield를 제거한다.
- 신뢰 가능한 외부 위치는 shield를 제거한다.
- 위치 `unavailable`은 shield를 새로 적용하거나 위치만으로 제거하지 않는다.
- 필수 권한이 없으면 새 shield를 적용하지 않는다.
- 동일 목표 상태와 동일 rule revision은 `effect == none`이다.
- 자정 초과 시간대는 시작 요일에 귀속된다.
- 15분 미만 시간대는 evaluation 이전 validation에서 거부한다.

## Required Contract Tests

- 선택/비선택 요일 × 같은 날/자정 초과 × 시작/종료 경계
- 14분, 15분, 24시간 미만 경계
- 시간 상태 × 위치 3상태 × 권한 상태 × 현재 shield 상태 전체 행렬
- 500m/1000m 내부·경계·외부·오차 중첩
- 반복 평가의 idempotency
- DST의 존재하지 않는 시각과 반복 시각
