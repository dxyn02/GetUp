# 작업 인계

## 현재 작업

- 기능: `002-live-activity-coins` Phase 9
- 마지막 완료 작업: T112
- 진행 중 작업: T113 실기기 Shield → 메인 앱 handoff 인수
- 다음 작업: T113 성공·복구·다기기·VoiceOver 잔여 인수, 완료 뒤 T114 Live Activity 로우파이 설계

## 2026-09-22 T113 준비 결과

사용자가 현재부터 약 22:30까지 Games 카테고리를 제한하고 Candy Crush Saga를 테스트
대상으로 지정했다. iPhone 17의 실제 Shield 첫 `Use 1 Release` 탭은 메인 앱 처리 중 화면을
열었다. 처리 중이 약 1분 이상 지속돼 강제 종료했고, 다시 열린 앱은 재시도·화면상 미차감·
제한 유지를 표시했다. `Try Again`도 약 1분 이상 처리 중에 머물러 강제 종료했다. 아직 완료·
권위 잔액·내역 수렴은 확인하지 못했다(BLK-021). `devicectl`의 CoreDeviceService 연결
무효화로 기기 로그 수집도 실패했다. 재개 시 새 해제 요청·구매 전에 같은 command 상태와
CloudKit refresh 단계별 지연을 확인한다.

재연결 뒤 App Group 진단에서 동기화 완료와 무료 0회·구매 0코인의
`CoinReservationPolicyError.insufficientBalance`를 확인했다. 이 오류가 결과 불명으로 분류되어
processing을 유지하던 결함을 수정하고 회귀 테스트를 통과시켰다. 수정 빌드의 기존 동일 command
`Try Again`은 X 아이콘의 `No releases available` 화면과 0/0 잔액으로 수렴했고 제한은 유지됐다.
BLK-021은 해결됐으며 새 해제나 구매는 실행하지 않았다.

동일한 서명 Debug 산출물을 iPhone 17(iOS 26.7)과 iPhone 15 Pro Max(iOS 27.0 beta)의 기존
`com.dxyn02.GetUp` 설치에 업데이트했다. 앱 데이터는 삭제하지 않았다. 산출물의 T089 대체 월 정책
세 값은 비어 있고, 앱과 Shield Action의 Family Controls·App Group·CloudKit entitlement를
확인했다. 설치 뒤 Shield-first 인수를 위해 GetUp 앱은 열지 않았다.

## 재개 조건과 인수 순서

iPhone Mirroring은 사용자가 직접 잠금 해제했고 iPhone 17에서 Candy Crush Saga Shield를
확인했다. 테스트 제한은 약 22:30까지만 적용된다. 두 기기의 iCloud 계정 동일 여부를 검증한 뒤
미검증 기기에서
제한 앱 Shield의 `해제권 1회 사용`을 한 번만 눌러 메인 앱 처리 중 진입과 최종 상태를 기록한다.
성공은 해당 occurrence의 제한 해제·무료 우선 차감·코인 내역과 반대 기기 수렴까지 확인한다.
재시도·잔액 부족·기존 복구 화면, 앱 강제 종료 뒤 동일 command 복원과 실제 VoiceOver 발표·
초점 이동도 별도로 확인한다. 결과 표는
`specs/002-live-activity-coins/quickstart.md`의 T113 인수 기록에 있다.

## 차단 및 테스트 상태

실기기 설치·서명, iPhone 17의 Shield 첫 탭 앱 진입·강제 종료 복원·재시도·확정 잔액 부족
수렴은 확인했다. 완료 결과·성공 차감·iPhone 15 Pro Max 첫 탭·복구·다기기 수렴·실제
VoiceOver는 미검증이다.
T112의 iPhone 17 Pro Max iOS 26.5 시뮬레이터 관련 자동 테스트는 664개 선언·동적 실행
784회가 실패·skip 없이 통과했고, 이번 `AppReleaseHandoffTests` 집중 실행도 통과했다. T113
실기기 인수는 아직 완료 처리하지 않는다.
