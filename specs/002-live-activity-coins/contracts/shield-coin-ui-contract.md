# 계약: Shield 코인 사용 UI

## 목적

사용자가 제한 앱의 system Shield 안에서 대표 규칙과 비용·효과를 이해하고 한 번의 명시적 버튼
행동으로 해제를 확정하게 한다. Live Activity에는 이 행동을 제공하지 않는다.

## 표시 정책

Shield Configuration은 App Group의 활성 occurrence와 confirmed balance mirror만 읽는다.

| 상태 | 표시와 행동 |
|------|-------------|
| 무료분 사용 가능·sync current | 대표 규칙, 종료 시각, 다른 제한 여부, `무료 해제권 1회 사용` primary button |
| 무료분 없음·구매 코인 사용 가능·sync current | 같은 안내와 `코인 1개 사용` primary button |
| 잔액 없음 | 해제 버튼 없이 잔액 부족과 앱에서 구매할 수 있음을 안내 |
| sync stale/unavailable | 해제 버튼 없이 `iCloud 연결 후 사용 가능` 안내 |
| deletionConfirmed/resetRequired | 해제 버튼 없이 장부 복구 불가 가능성과 앱에서 새 장부 선택이 필요함을 안내 |
| snapshot 손상·대표 규칙 없음 | 기존 일반 제한 문구와 `앱 닫기`만 제공 |

- 비용, 대상 대표 규칙, 현재 구간 종료 시각, 다른 규칙으로 제한이 남는지를 primary button 전에
  title·subtitle에 모두 제시한다.
- `무료 해제권 1회 사용` 또는 `코인 1개 사용` 버튼 누름 자체가 명시적 확정이다.
- secondary button은 `앱 닫기`이며 제한 우회 권한을 주지 않는다.
- 위치 좌표·앱 이름 역해석·token·CloudKit 오류 상세를 표시하지 않는다.

## Action 처리

- primary action은 동일한 `RuleReleaseService`에 안정적인 command를 전달하고 결과가 확인될 때까지
  `.defer`로 Shield 응답을 보류한다.
- 성공 뒤 현재 대상에 남은 제한이 없으면 `.none`으로 system Shield 갱신을 허용한다.
- 다른 규칙 제한이 남거나 실패하면 Shield를 유지하고 configuration snapshot을 갱신한다.
- secondary action은 `.close`다.
- timeout은 실패 닫힘으로 처리하고 잔액을 확정 소모하지 않는다.

## 앱 내 표면

- 활성 제한 카드에서 대표 또는 사용자가 선택한 occurrence의 상세, 무료·구매 잔액, 사용할 수단,
  종료 시각, 겹친 규칙 영향을 보여준 뒤 별도 확인 dialog로 확정한다.
- 잔액 0이면 구매 화면으로 이동할 수 있다.
- pending reconciliation이 있으면 새 사용보다 처리 상태와 재시도를 먼저 표시한다.
- 장부 삭제가 확정되면 메인 앱에서만 삭제 불이익 고지와 새 장부 시작 선택을 제공한다. Shield는
  local mirror로 복구하거나 reset·구매를 시작하지 않는다.

## 접근성·지역화

- 한국어·영어가 같은 비용·대상·종료·남을 제한 의미를 전달해야 한다.
- VoiceOver는 상태 → 대상 → 비용 → 결과 경고 → 사용 → 닫기 순서로 이해할 수 있어야 한다.
- 시스템 Dynamic Type과 Light/Dark에서 주요 버튼·잔액·경고가 잘리지 않아야 한다.
- `Home`·`Work`는 기존 표시 지역화 경계를 재사용하고 영속 이름은 변경하지 않는다.

## 필수 테스트

- 무료분·구매분·잔액 없음·stale mirror별 configuration
- deletionConfirmed/resetRequired에서 해제·구매·reset 행동이 없고 앱 안내만 표시됨
- 단일 규칙과 같은 앱의 다중 규칙 경고
- primary 성공·실패·timeout·중복 tap, secondary close
- 해제 성공 후 Shield 제거 또는 다른 규칙 Shield 유지
- 한국어·영어, VoiceOver, Dynamic Type, Light/Dark
