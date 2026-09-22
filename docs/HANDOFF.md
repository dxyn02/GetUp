# 작업 인계

## 현재 작업

- 기능: `002-live-activity-coins` Phase 9
- 마지막 완료 작업: T112
- 진행 중 작업: T113 실기기 Shield → 메인 앱 handoff 인수
- 다음 작업: T113 결과 기록 후 T114 Live Activity 로우파이 설계

## 2026-09-22 T113 준비 결과

동일한 서명 Debug 산출물을 iPhone 17(iOS 26.7)과 iPhone 15 Pro Max(iOS 27.0 beta)의 기존
`com.dxyn02.GetUp` 설치에 업데이트했다. 앱 데이터는 삭제하지 않았다. 산출물의 T089 대체 월 정책
세 값은 비어 있고, 앱과 Shield Action의 Family Controls·App Group·CloudKit entitlement를
확인했다. 설치 뒤 Shield-first 인수를 위해 GetUp 앱은 열지 않았다.

## 재개 조건과 인수 순서

iPhone Mirroring은 사용자가 직접 잠금 해제했고 iPhone 17 홈 화면 확인이 가능하다. 그러나
현재 시각에 활성 제한 규칙이 없으며, 양쪽 공통 설치 앱 `Sync`는 Beta 만료로 사용할 수 없다.
사용자와 안전한 테스트 대상 앱·적용 시간대를 정해 활성 규칙을 만든 뒤, 두 기기의 iCloud 계정
동일 여부와 활성 제한 occurrence를 확인한다. 각 기기에서
제한 앱 Shield의 `해제권 1회 사용`을 한 번만 눌러 메인 앱 처리 중 진입과 최종 상태를 기록한다.
성공은 해당 occurrence의 제한 해제·무료 우선 차감·코인 내역과 반대 기기 수렴까지 확인한다.
재시도·잔액 부족·기존 복구 화면, 앱 강제 종료 뒤 동일 command 복원과 실제 VoiceOver 발표·
초점 이동도 별도로 확인한다. 결과 표는
`specs/002-live-activity-coins/quickstart.md`의 T113 인수 기록에 있다.

## 차단 및 테스트 상태

실기기 설치·서명은 성공했지만 Shield 첫 탭과 결과 화면은 미검증이다. 현재 활성 제한 규칙이
없어 Shield가 나타나지 않으며, 테스트용 대상 앱·시간대 선택을 사용자에게 요청했다.
T112의 iPhone 17 Pro Max iOS 26.5 시뮬레이터 관련 자동 테스트는 664개 선언·동적 실행
784회가 실패·skip 없이 통과했다. T113 실기기 인수는 아직 완료 처리하지 않는다.
