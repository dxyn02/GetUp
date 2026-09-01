# 계약: 제한 현황 Live Activity

## 목적

기존 제한 판정과 독립적으로 대표 활성 규칙의 남은 시간·거리만 안전하게 표시한다.

## 시작 경계

- 메인 앱이 foreground에서 활성 occurrence를 확인했을 때만 로컬 `Activity.request`를 호출한다.
- 앱 비실행 상태의 Device Activity callback은 Shield와 활성 occurrence snapshot을 갱신하지만 Live
  Activity를 시작하지 않는다.
- `ActivityAuthorizationInfo.areActivitiesEnabled == false`, request 실패 또는 시스템 한도 초과는
  제한 적용 실패로 전파하지 않는다.
- 활성 occurrence가 없으면 새 활동을 시작하지 않는다.

## 대표 규칙

- 활성 occurrence를 `activatedAt`, `startAt`, `ruleID` 순으로 정렬해 첫 항목을 대표로 사용한다.
- 동시에 여러 규칙이 있으면 `hasAdditionalRestrictions == true`를 표시한다.
- 대표 occurrence가 끝나고 다른 occurrence가 남으면 기존 Activity의 content state를 갱신한다.
- 앱이 다시 foreground가 되면 `Activity.activities`와 현재 snapshot을 비교해 중복 활동을 즉시
  종료하고 대표 활동 하나만 남긴다.
- 활성 occurrence가 있는데 `Activity.activities`가 비어 있으면 사용자가 같은 occurrence의 활동을
  직접 제거한 경우를 포함해 대표 활동을 다시 생성한다. 수동 제거를 기억하는 suppression marker는
  두지 않는다.

## 표시 데이터

| 상태 | 필수 표시 |
|------|-----------|
| 거리 known | 규칙 표시명, `max(0, radius - centerDistance)`를 가장 가까운 10m로 반올림한 미터 거리, 종료까지 카운트다운 |
| 거리 unavailable/stale | 규칙 표시명, `거리 확인 불가`, 종료까지 카운트다운 |
| 다른 규칙 존재 | 핵심 정보와 함께 다른 제한이 있음을 짧게 표시 |

- 카운트다운은 policy에서 `max(0, endsAt - now)`로 만든 `endsAt` 기반 동적 날짜 텍스트를 사용하고
  초 단위 Activity update를 만들지 않는다. 종료 전·경계·종료 후 표시 오차는 60초 이내여야 한다.
- 거리 payload에는 좌표, 위치 정확도, 장소 주소를 넣지 않는다.
- 지속 background location update를 시작하지 않는다. 기존 위치 이벤트 또는 앱 실행 시 얻은 신뢰
  가능한 근거에서만 갱신한다.
- content state와 attributes의 합계는 4KB 미만이어야 한다.
- Live Activity에는 버튼·토글·코인 잔액·구매 진입을 제공하지 않는다.

## 갱신과 stale

- 신뢰 가능한 위치 근거가 바뀌고 표시 거리의 반올림 결과 또는 availability가 달라질 때 갱신한다.
- 메인 앱이 신뢰 가능한 위치를 전달받아 ActivityKit을 조정할 수 있게 된 시점을 거리 갱신 30초의
  기산점으로 사용한다.
- extension만 위치를 전달받으면 근거를 App Group에 저장하고 ActivityKit을 직접 갱신한다고 가정하지
  않는다. 다음 앱 foreground에서 coordinator가 조정 가능해진 시점부터 30초 안에 반영한다.
- 기존 `LocationEvidenceEvaluator`가 `.inside`로 확정한 근거만 known으로 사용한다.
- 위치 확인 시점부터 5분을 초과한 거리는 이전 숫자를 유지하지 않고 `unavailable`로 갱신한다.
- 시간 종료는 위치 availability와 무관하게 활동 종료 대상이다.
- ActivityKit update 오류는 개인정보 없는 코드로 기록하고 다음 foreground 조정에서 재시도한다.

## 종료

- 활성 occurrence가 모두 끝났거나 해제 예외 적용으로 대표를 포함한 활성 집합이 비면 최종 content
  state와 `.immediate` dismissal로 종료한다.
- 사용자가 활동을 직접 제거해도 제한 상태에는 영향이 없다.
- 앱 삭제·Live Activities 비활성화는 다음 조정에서 정상 부재로 취급한다. 시스템 또는 사용자가
  활동만 제거했고 Live Activities가 허용된 경우에는 다음 foreground 조정에서 다시 생성한다.

## 필수 테스트

- Live Activity 지원 기기·권한 허용·유효한 활성 제한·foreground 조건의 100회 중 95회 이상이 활성
  제한 확인 뒤 30초 안에 표시됨
- 권한 거부·미지원 사례에서 Live Activity는 안전하게 실패하고 제한 판정·적용·해제는 정상 동작함
- 메인 앱 위치 수신 기산점부터 30초 안의 거리 반영과 extension-only 근거의 다음 foreground 기산점
  이후 30초 안의 반영
- 단일·다중 occurrence 대표 선택과 대표 교체
- known 거리 공식, 0 clamp, 5m half-up을 포함한 10m 반올림, 5분 stale 경계, unavailable
- 주입 시계의 종료 전·경계·종료 후 남은 시간 오차 60초 이내와 0 clamp
- foreground start, background 제한 시작 시 미시작, 다음 foreground에서 시작
- 사용자가 활동을 제거한 뒤 같은 occurrence가 활성인 상태로 foreground 진입 시 재생성
- request/update/end 실패가 Shield에 영향을 주지 않음
- 중복 Activity 조정과 즉시 종료
- Lock Screen 및 Dynamic Island compact/minimal/expanded의 한국어·영어 preview
- Dynamic Type, VoiceOver, Light/Dark와 4KB payload 상한
