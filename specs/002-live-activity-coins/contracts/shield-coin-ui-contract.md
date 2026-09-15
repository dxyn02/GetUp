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

- primary action은 안정적인 command ID·occurrence를 포함한 `PendingAppRoute.releaseProcessing`을
  App Group에 원자적으로 기록한다. Shield extension은 FR-037 전체 동기화, allowance 생성, 예약,
  ReleaseException 적용이나 제한 read-back을 실행하지 않는다.
- iOS 26.5 이상은 route 저장 성공 뒤 `.openParentalControlsApp`을 즉시 반환한다. route 저장 실패는
  제한을 유지하는 fail-closed 결과로 끝내며 성공으로 표시하지 않는다.
- 메인 앱은 route 생성 후 5분 이내, 미소비, 연결 occurrence 활성 조건을 모두 만족할 때만 route를
  한 번 소비한다. 소비 뒤 처리 중 UI를 표시하고 `RuleReleaseService`로 FR-037 전체 동기화·월간
  allowance 생성·무료 우선 예약·예외 적용·제한 read-back·장부 commit을 수행한다. 성공한 소비와
  삭제는 atomic하며 만료·중복·종료 occurrence route는 이동 없이 삭제한다.
- 메인 앱은 확정 결과에 따라 완료, 같은 command ID 재시도, 코인 부족 후 구매 유도, iCloud·장부
  복구 화면 중 하나로 전환한다. `coinStore`는 앱의 권위 확인에서 잔액 부족이 확정된 경우에만 쓴다.
- iOS 26.0~26.4는 공식 앱 열기 응답이 없으므로 안내 상태를 기록한 뒤 `.close`를 반환한다. custom
  URL, `UIApplication`, 임의 `NSExtensionContext` 우회는 사용하지 않는다.
- secondary action은 `.close`다.
- 동일 route나 command가 재전달돼도 앱은 새 차감 없이 기존 결과를 재조정한다.

## 앱 내 표면

- Shield release route 진입은 처리 중 화면으로 시작한다. 중복 tap을 막고 VoiceOver live 상태로
  동기화·해제 진행 중임을 전달한다.
- 제한 read-back과 장부 commit이 모두 확인되면 해제 완료 화면에서 사용한 수단, 현재 구간 종료와
  다른 규칙으로 남는 제한을 표시한다.
- 서비스가 재시도 가능으로 분류한 네트워크·CloudKit·적용 오류 또는 다음 foreground 재조정에서
  완료되지 않은 중단 command는 제한 유지와 동일 command 재시도를 제공한다.
- 무료 해제권과 구매 코인이 모두 부족하면 제한 유지와 코인 구매 CTA를 제공한다.
- 동일 command의 서비스 호출이 실행 중인 동안 재시도 action을 노출하지 않는다. 서비스가 재시도
  가능한 오류를 반환하거나 다음 foreground 재조정에서 완료를 확인할 수 없는 중단 command로
  판정한 경우에만 같은 command ID 재시도를 활성화한다. 성공·잔액 부족·복구 필요는 해당 확정
  화면으로 직접 전환한다.
- 활성 제한 카드에서 대표 또는 사용자가 선택한 occurrence의 상세, 무료·구매 잔액, 사용할 수단,
  종료 시각, 겹친 규칙 영향을 보여준 뒤 별도 확인 dialog로 확정한다.
- 잔액 0이면 구매 화면으로 이동할 수 있다.
- pending reconciliation이 있으면 새 사용보다 처리 상태와 재시도를 먼저 표시한다.
- 장부 삭제가 확정되면 메인 앱에서만 삭제 불이익 고지와 새 장부 시작 선택을 제공한다. Shield는
  local mirror로 복구하거나 reset·구매를 시작하지 않는다.
- 위 앱 내 네 상태의 layout·motion·문구·초점 이동은 승인된 하이파이를 기준으로 구현한다. 하이파이
  승인 기록 전에는 제품 UI를 변경하지 않는다.

## 접근성·지역화

- 한국어·영어가 같은 비용·대상·종료·남을 제한 의미를 전달해야 한다.
- VoiceOver는 상태 → 대상 → 비용 → 결과 경고 → 사용 → 닫기 순서로 이해할 수 있어야 한다.
- 시스템 Dynamic Type과 Light/Dark에서 주요 버튼·잔액·경고가 잘리지 않아야 한다.
- `Home`·`Work`는 기존 표시 지역화 경계를 재사용하고 영속 이름은 변경하지 않는다.

## 필수 테스트

- 무료분·구매분·잔액 없음·stale mirror에서 동일한 해제권 버튼과 정확한 비용·실패 안내
- deletionConfirmed/resetRequired에서 해제·구매·reset 행동이 없고 앱 안내만 표시됨
- 단일 규칙과 같은 앱의 다중 규칙 경고
- release route 저장 성공·실패·중복 tap, secondary close와 iOS 26.5 즉시 앱 진입
- 앱 처리 중·완료·재시도·잔액 부족의 상태 전이, 앱 종료 뒤 command 재조정과 최종 미적용 차감 0
- 해제 성공 후 Shield 제거 또는 다른 규칙 Shield 유지
- 새달 최초 Shield action 뒤 메인 앱의 무료분 생성·우선 차감, 잔액 부족·장부 불가 결과 분기
- iOS 26.5 앱 직접 열기와 iOS 26.0~26.4 `.close` fallback
- PendingAppRoute의 5분 경계, 일회 소비, 중복 소비 거부, 종료 occurrence route 폐기
- 한국어·영어, VoiceOver, Dynamic Type, Light/Dark
- 승인된 해제 결과 하이파이와 스냅샷·실기기 결과의 시각 대조
