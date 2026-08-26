# Contract: Platform Events

## Permission Adapter

### Required inputs

- Family Controls individual authorization
- Always location authorization
- Full Accuracy location authorization
- Background refresh availability 진단

### Behavior

- 권한 요청은 사용자가 기능을 설정하는 맥락에서 단계적으로 수행한다.
- 전체 권한 개요와 정상 승인 상태의 순차 확인은 온보딩 완료 전 앱 실행에서 수행한다.
- 마지막 Background App Refresh 화면의 `시작하기`를 누른 뒤에만 온보딩 완료 여부를 영구 저장한다.
  그 전에 앱 프로세스를 종료하거나 기기를 재시작하면 다음 실행에서 온보딩 개요부터 다시 시작한다.
- 일반 실행·foreground 복귀에서는 모든 필수 권한이 정상이면 권한 UI를 표시하지 않고, 거부되거나
  요구 수준에 못 미친 Family Controls 또는 위치 권한의 상세 복구 화면만 직접 표시한다.
- 권한 미승인 또는 철회 시 새 제한을 적용하지 않는다.
- 위치가 미결정이면 먼저 `앱을 사용하는 동안 허용`을 요청하고 이후 앱 설정에서 `항상 허용`과
  `정확한 위치`를 켜는 순서를 화면 상태로 제공한다.
- Background App Refresh는 필수 권한 gate가 아니며 이 상태만으로 foreground 권한 안내를 열지 않는다.
- Background App Refresh는 앱별 설정에서 변경할 수 없으므로 시스템 전체
  `설정 > 일반 > 백그라운드 앱 새로 고침` 경로만 안내하고 앱별 Settings action을 제공하지 않는다.
- 위치 권한 복구 화면은 `설정 열기`만 제공한다. 온보딩의 Background App Refresh 안내는 상태와
  관계없이 `시작하기`로 완료하고, 일반 복구의 제한 안내만 `확인`으로 닫는다.
- 앱 소유 안내 화면의 Settings 목업은 설명용 비대화형 요소다. 권한 요청 alert 목업의 지정된 주요
  버튼만 시스템 prompt를 실행하며 실제 권한 변경은 시스템 prompt 또는 Settings에서 수행한다.
- Family Controls 재승인 뒤에는 앱 선택을 다시 확인한다.

## Schedule Adapter

- 선택 요일마다 안정적인 activity name을 생성한다.
- 각 schedule은 15분 이상 12시간 이하이며 자정 초과 종료를 지원한다.
- 저장 성공 시 기존 등록을 새 rule revision의 일정으로 교체한다.
- interval start/end callback은 공유 규칙을 읽고 평가 계약을 호출한다.
- `intervalDidStart`가 도착하면 callback 반환 전에 현재 schema의 공유 규칙·위치 snapshot과 권한을
  동기 평가하고, 조건을 충족한 모든 규칙의 합집합을 단일 `getup.restriction` store에 쓰고
  read-back으로 확인한다. callback 안에서는 현재 실행 중인 일정을 제거하거나 재등록하지 않는다.
- `intervalDidStart`의 snapshot read 또는 store 검증이 실패하면 기존 일정·shield·적용 상태를
  보존하고 비동기 호환 재평가는 일정 초기화 없이 수행한다.
- `intervalDidEnd`는 종료 시각 정각이 아니라 schedule 구간 밖에서 기기가 처음 사용될 때 전달될 수
  있다. callback이 도착하면 activity name의 rule ID가 현재 적용 상태의 마지막 활성 규칙인 경우에만
  단일 `getup.restriction` store를 callback 안에서 동기적으로 비우고 적용 상태를 제거한다.
- callback에서 activity name을 해석할 수 없거나 다른 활성 규칙이 남아 있으면 callback 진입 시각을
  신뢰 가능한 time event 확인 시각으로 기록한 뒤 저장된 모든 규칙을 현재 시각 기준으로 다시 평가해
  단일 store의 제한 대상 합집합을 갱신한다. 종료된 규칙의 위치가 `unavailable`이어도 시간 종료를
  우선한다.
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
- `apply`는 현재 활성 `(ruleID, revision)` 집합이 선택한 개별 앱 token, 앱 category token과
  web domain token의 합집합에 shield를 설정한다. category token은
  `shield.applicationCategories = .specific(...)`로 적용한다.
- `remove`는 GetUp store의 shield만 지운다.
- 다른 Screen Time 제공자의 store는 수정하지 않는다.
- 동일한 활성 rule revision 집합이고 GetUp store의 앱·카테고리·웹 도메인 shield가 기대값과
  일치하면 시스템 write를 반복하지 않는다. revision이 같아도 store가 누락되거나 불일치하면
  기대 합집합을 다시 적용한다.

## Delivery and Recovery Boundary

- 30초 목표는 신뢰 가능한 시간 또는 위치 조건 변경이 확인된 뒤부터 측정한다.
- 물리 경계 통과부터 시스템 event 전달까지의 지연은 앱 SLA에 포함하지 않고 실기기에서 관찰한다.
- 재부팅 후 첫 잠금 해제 전에는 자동 위치 복구를 약속하지 않는다.
- 첫 잠금 해제 뒤 공유 파일, 권한, 일정, 위치 조건을 복구하고 사용자가 앱을 직접 열지 않아도
  다음 신뢰 가능한 event에서 상태를 일치시킨다.
- 앱 foreground 활성화는 공유 규칙을 먼저 읽은 뒤 GetUp 소유 일정·region을 재등록하고 위치를
  갱신한 다음 제한 합집합을 재평가하는 복구 coordinator를 호출한다.
- Device Activity extension의 `intervalDidStart`는 짧은 extension 생명주기 안에서 제한 반영이
  유실되지 않도록 callback-local 동기 평가·store 적용 경로를 사용한다. 이미 진행 중인 interval에서
  callback 재진입과 경합을 만들 수 있으므로 이 경로에서는 일정·region 전체 복구를 호출하지 않는다.
- 규칙과 저장 장소 snapshot 저장이 모두 성공하면 같은 복구 coordinator를 호출해 새 revision을
  포함한 모든 활성 규칙의 일정·region·위치 근거를 재등록하고 제한 합집합을 즉시 재평가한다.
- snapshot 저장이 완료되지 않으면 일정·region·shield를 변경하지 않는다.
- 첫 잠금 해제 전 파일 보호 등으로 규칙 snapshot을 읽을 수 없으면 일정·region·shield를 변경하지
  않고 다음 시스템 event에서 다시 시도한다.
- 개별 일정·region 등록 실패는 다른 유효 규칙과 최종 제한 상태 재평가를 막지 않으며 복구 결과에
  개인정보를 포함하지 않는 component·rule ID 수준 실패로 남긴다.
