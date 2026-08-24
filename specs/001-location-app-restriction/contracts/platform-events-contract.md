# Contract: Platform Events

## Permission Adapter

### Required inputs

- Family Controls individual authorization
- Always location authorization
- Full Accuracy location authorization
- Background refresh availability 진단

### Behavior

- 권한 요청은 사용자가 기능을 설정하는 맥락에서 단계적으로 수행한다.
- 권한 미승인 또는 철회 시 새 제한을 적용하지 않는다.
- 권한 종류와 시스템 설정에서 복구하는 방법을 화면 상태로 제공한다.
- Family Controls 재승인 뒤에는 앱 선택을 다시 확인한다.

## Schedule Adapter

- 선택 요일마다 안정적인 activity name을 생성한다.
- 각 schedule은 15분 이상이며 자정 초과 종료를 지원한다.
- 저장 성공 시 기존 등록을 새 rule revision의 일정으로 교체한다.
- interval start/end callback은 공유 규칙을 읽고 평가 계약을 호출한다.
- `intervalDidEnd`는 callback 진입 시각을 신뢰 가능한 time event 확인 시각으로 기록하고 저장된 모든
  규칙을 현재 시각 기준으로 다시 평가한다. 종료된 규칙의 위치가 `unavailable`이어도 시간 종료를
  우선하며, 다른 활성 규칙이 있으면 해당 규칙의 앱 token 합집합은 유지한다.
- 앱 타이머나 알림을 권위 있는 자동 제한 트리거로 사용하지 않는다.
- callback 전달 시점이 정확한 벽시계 시각과 다를 수 있음을 상태·테스트에서 고려한다.

## Location Adapter

- 규칙당 원형 위치 조건 하나를 500m, 1000m, 2000m, 3000m, 4000m 또는 5000m로 등록한다.
- 모니터링 가용성과 기기의 최대 허용 반경을 등록 전에 확인한다.
- region event는 새 위치 판정을 요청하는 트리거이며, 경계 event만으로 내부·외부를 확정하지 않는다.
- 위치 fix의 거리와 horizontal accuracy로 `inside | outside | unavailable`을 계산한다.
- 오류, Reduced Accuracy, 오래된 fix, 음수 accuracy, 경계 중첩은 `unavailable`이다.
- 앱 foreground, 위치 event, 권한 변경, 재부팅 뒤 첫 잠금 해제에서 재평가한다.

## Restriction Adapter

- 고정된 이름의 Managed Settings store 하나를 사용한다.
- `apply`는 현재 활성 `(ruleID, revision)` 집합이 선택한 앱 token 합집합에 shield를 설정한다.
- `remove`는 GetUp store의 shield만 지운다.
- 다른 Screen Time 제공자의 store는 수정하지 않는다.
- 동일한 활성 rule revision 집합은 시스템 write를 반복하지 않는다.

## Delivery and Recovery Boundary

- 30초 목표는 신뢰 가능한 시간 또는 위치 조건 변경이 확인된 뒤부터 측정한다.
- 물리 경계 통과부터 시스템 event 전달까지의 지연은 앱 SLA에 포함하지 않고 실기기에서 관찰한다.
- 재부팅 후 첫 잠금 해제 전에는 자동 위치 복구를 약속하지 않는다.
- 첫 잠금 해제 뒤 공유 파일, 권한, 일정, 위치 조건을 복구하고 사용자가 앱을 직접 열지 않아도
  다음 신뢰 가능한 event에서 상태를 일치시킨다.
- Device Activity extension의 `intervalDidStart`와 앱 foreground 활성화는 같은 복구 coordinator를
  호출한다. 복구는 공유 규칙을 먼저 읽은 뒤 GetUp 소유 일정·region을 초기화하고 활성 규칙별로
  재등록·위치 갱신한 다음 제한 합집합을 재평가한다.
- 규칙과 저장 장소 snapshot 저장이 모두 성공하면 같은 복구 coordinator를 호출해 새 revision을
  포함한 모든 활성 규칙의 일정·region·위치 근거를 재등록하고 제한 합집합을 즉시 재평가한다.
- snapshot 저장이 완료되지 않으면 일정·region·shield를 변경하지 않는다.
- 첫 잠금 해제 전 파일 보호 등으로 규칙 snapshot을 읽을 수 없으면 일정·region·shield를 변경하지
  않고 다음 시스템 event에서 다시 시도한다.
- 개별 일정·region 등록 실패는 다른 유효 규칙과 최종 제한 상태 재평가를 막지 않으며 복구 결과에
  개인정보를 포함하지 않는 component·rule ID 수준 실패로 남긴다.
