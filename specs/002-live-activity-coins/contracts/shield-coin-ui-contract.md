# 계약: Shield 코인 사용 UI

## 목적

사용자가 제한 앱의 system Shield 안에서 대표 규칙과 비용·효과를 이해하고 한 번의 명시적 버튼
행동으로 해제를 확정하게 한다. Live Activity에는 이 행동을 제공하지 않는다.

## 표시 정책

Shield Configuration은 App Group의 활성 occurrence와 confirmed balance mirror만 읽는다.

| 상태 | 표시와 행동 |
|------|-------------|
| sync current | 대표 규칙, 종료 시각, 다른 제한 여부, `해제권 1회 사용` primary button과 무료 우선·없으면 코인 1개 정책 |
| 잔액 없음으로 확인됨 | 같은 버튼을 유지하되 탭 시 제한을 유지하고 앱의 코인 구매 화면으로 진입 |
| sync stale/unavailable | 같은 버튼을 유지하되 탭 시 제한을 유지하고 앱의 iCloud 복구 화면으로 진입 |
| deletionConfirmed/resetRequired | 같은 버튼을 유지하되 탭 시 제한을 유지하고 앱의 장부 복구·새 장부 화면으로 진입 |
| snapshot 손상·대표 규칙 없음 | 기존 일반 제한 문구와 `앱 닫기`만 제공 |

- 비용, 대상 대표 규칙, 현재 구간 종료 시각, 다른 규칙으로 제한이 남는지를 primary button 전에
  title·subtitle에 모두 제시한다.
- subtitle은 무료분을 먼저 사용하고 없으면 구매 코인 1개를 사용한다는 비용 순서를 명시한다.
- `해제권 1회 사용` 버튼 누름 자체가 이 무료 우선 fallback에 대한 명시적 확정이다.
- secondary button은 기존 `앱 닫기`이며 제한 우회 권한을 주지 않는다.
- 위치 좌표·앱 이름 역해석·token·CloudKit 오류 상세를 표시하지 않는다.

## Action 처리

- primary action은 동일한 `RuleReleaseService`에 안정적인 command를 전달한다. 최신 현재 월
  allowance가 없으면 생성과 무료분 reservation을 한 atomic command에서 수행한다.
- 성공 뒤 현재 대상에 남은 제한이 없으면 `.none`으로 system Shield 갱신을 허용한다.
- 다른 규칙 제한이 남거나 실패하면 Shield를 유지하고 configuration snapshot을 갱신한다.
- 최신 장부가 `current`이고 잔액만 부족하면 `PendingAppRoute.coinStore`, iCloud·장부 불가이면 해당
  복구 route를 App Group에 기록한다. iOS 26.5 이상은 `.openParentalControlsApp`을 반환한다.
- iOS 26.0~26.4는 공식 앱 열기 응답이 없으므로 안내 상태를 기록한 뒤 `.close`를 반환한다. custom
  URL, `UIApplication`, 임의 `NSExtensionContext` 우회는 사용하지 않는다.
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

- 무료분·구매분·잔액 없음·stale mirror에서 동일한 해제권 버튼과 정확한 비용·실패 안내
- deletionConfirmed/resetRequired에서 해제·구매·reset 행동이 없고 앱 안내만 표시됨
- 단일 규칙과 같은 앱의 다중 규칙 경고
- primary 성공·실패·timeout·중복 tap, secondary close
- 해제 성공 후 Shield 제거 또는 다른 규칙 Shield 유지
- 새달 최초 Shield action의 무료분 생성·우선 차감, 잔액 부족·장부 불가 route 분기
- iOS 26.5 앱 직접 열기와 iOS 26.0~26.4 `.close` fallback
- 한국어·영어, VoiceOver, Dynamic Type, Light/Dark
