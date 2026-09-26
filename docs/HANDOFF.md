# 작업 인계

## 현재 작업

- 기능: `002-live-activity-coins` Phase 9
- 마지막 완료 작업: T113
- 진행 중 작업: T114 Live Activity 로우파이 사용자 검토
- 다음 작업: T114 승인 기록 후 T115 Live Activity 하이파이 제작

## 2026-09-26 T114 로우파이 초안

사용자가 규칙 이름 앞 임시 사각형 아이콘의 의미가 불명확하다고 지적했다. 명확한 의미를 갖는
대체 아이콘이 아니므로 잠금화면 4곳과 Dynamic Island expanded 4곳에서 모두 제거하고 규칙 이름을
텍스트만으로 표시했다. 최종 screenshot에서 정렬과 잘림·겹침 없음을 확인했다.

사용자가 거리 아이콘의 가는 선과 복잡한 형태, 카드 안의 구현 주석 노출을 지적했다. Figma의
잠금화면·Dynamic Island 거리 표시 12곳을 채움형 `location.fill`로 교체하고, 네 잠금화면 카드에서
구현 계약용 주석을 제거했다. 반올림·stale·개인정보 계약은 실제 사용자 UI가 아니라 Figma 보드의
외부 상태 설명과 로우파이 문서에만 유지한다.

잠금화면 시간 표시의 오른쪽 여백이 크다는 사용자 피드백을 반영했다. 카드 내부 행이 406pt로
고정돼 좌측 16pt와 달리 우측에 약 48pt가 남던 원인이었으며, 네 상태의 primary·distance 행을
438pt로 맞춰 시간과 다중 규칙 badge의 trailing 여백을 16pt로 정렬했다. 최종 screenshot에서
좌우 균형과 잘림·겹침 없음을 확인했다.

사용자 피드백에 따라 거리와 시간에 같은 `m`을 쓰던 축약을 수정했다. Figma의 compact·minimal
카운트다운은 한국어 `42분`으로 바꾸고, 하이파이 및 지역화 인계에서는 영어 `42 min`, 거리 `m`를
서로 구분하도록 기록했다. 수정 screenshot에서 잘림과 겹침이 없음을 확인했다.

Figma node `384:2090`에 잠금화면 known·unavailable·stale·다중 규칙 4상태와 Dynamic Island
minimal·compact·expanded의 상태 행렬을 작성했다. stale은 이전 거리 숫자를 제거하고
`거리 확인 불가`로 수렴하며, minimal은 시간, compact는 거리 상태와 시간, expanded는 규칙·시간·
거리·추가 제한을 표시한다. VoiceOver는 대표 규칙→남은 시간→거리 상태→다른 제한 순서를 기본으로
하고 시각적 `?`·`+`는 전체 의미로 읽는다. 상세 계약과 네 검토 선택점은
`design/low-fidelity/US1-live-activity-refresh.md`에 기록했다. 사용자 승인 전에는 T114를 완료
처리하거나 T115 하이파이를 시작하지 않는다.

## 2026-09-22 T113 준비 결과

2026-09-25 T113 완료: 사용자가 iPhone 17의 최신 격리 recovery fixture에서 제목과 설명이
연속으로 발표되고 장식 아이콘·DEBUG·container·`heading` 안내는 들리지 않으며 다음 초점이
`닫기`로 이동함을 확인했다. 앞선 두 실기기의 Shield 첫 탭·처리 중·완료·재시도·잔액 부족·강제
종료 복원·제한/잔액/내역 수렴 증적과 합쳐 T113을 완료하고 BLK-022를 해결했다. 다음 작업은
T114 Live Activity 로우파이 설계이며 T089 월 경계 allowance 인수는 별도 미완료다.

2026-09-25 iPhone 17의 DEBUG recovery fixture로 기존 iCloud 복구 화면 연결을 확인했다. 실제
VoiceOver 검수에서 장식 아이콘·중복 제목·화면 컨테이너가 섞여 읽히고 제목 뒤에 설명이 즉시
이어지지 않는 결함이 발견됐다. 복구 화면 접근성 트리를 `제목(label) + 설명(value)` 단일 요약과
`닫기`만 남도록 정리하고 장식 아이콘·DEBUG 진단을 숨겼다. 첫 수정 빌드에서 설명 뒤 `heading`
안내가 남아 요약의 header trait도 제거했다. 한국어·영어 집중 UI 테스트 3건은 다시 실패·skip
없이 통과했고 최신 수정 서명 빌드를 iPhone 17에 설치했다. 다만 설치 직후 기기와 iPhone
Mirroring이 잠겨 앱 실행이 거부됐다. 사용자가 잠금을 해제한 뒤 fixture를 다시 실행해 실제 음성이
요약 전체를 먼저 읽고 다음 초점이 `닫기`인지 확인한다. 이 확인 전에는 T113을 닫지 않는다.

2026-09-25 사용자가 iPhone 15 Pro Max의 수정 Coin History에서 성공 command가
`Monthly free used -1` 한 건으로만 보이는 것을 확인했다. 성공 차감과 반대 기기 잔액·내역 수렴은
통과다. 현재 두 테스트 iPhone이 CoreDevice에서 `unavailable`이라 DEBUG recovery fixture와 실제
VoiceOver 음성·초점 확인은 진행하지 못했다. 기기 연결 뒤 이 두 항목만 마치면 T113을 닫는다.

22:57 성공 해제의 Coin History에 같은 command의 예약과 확정 사용이 모두 `-1`로 보여 두 번
차감된 것처럼 보였지만, 실제 권위 잔액은 2/0에서 1/0으로 한 번만 감소했다. 확정 `spend` 또는
보상 `release`가 존재하는 command의 `reservation` 행을 접고, pending 예약에는 음수 수량을
표시하지 않도록 수정했다. 확정 사용은 `-1` 한 건만 남는다. 표시 정책 단위 테스트, US4 집중 UI
테스트, T089 설정을 명령행에서 비운 전체 `GetUpTests`가 통과했다. 수정 서명 빌드는 데이터를
보존해 두 iPhone에 설치했다. 다음 실기기 확인에서는 기존 22:57 내역에 `Monthly free used -1`
한 건만 보이는지 확인한다.

5분 설정 빌드 설치 뒤 iPhone 17의 22:57 Shield-first 실행이 성공했다. 사용자가 제공한 결과 화면은
`Release complete`, 무료 해제권 1회 사용, 남은 제한 없음이며, App Group 진단도
`releaseRouteSaved` → `finalRefreshCompleted`와 빈 활성 규칙 목록을 기록했다. iPhone 15 Pro Max의
Coins 화면은 처음 2/0을 표시했다가 몇 초 뒤 1/0으로 바뀌었고 22:59 장부 동기화 진단과 함께
원격 차감의 다기기 잔액 수렴을 확인했다. 다음 확인은 반대 기기의 release 내역이며, 그 뒤 복구
연결·실제 VoiceOver가 남는다.

사용자 확인에 따라 `Debug.xcconfig`의 `t089-five-minute-final`·5분 주기를 실제 포함한 새 서명
Debug 빌드를 만들었다. 앱과 Shield Action Info.plist에서 세 T089 값을 확인했고, 두 기기에 기존
데이터를 보존해 동일 산출물을 설치했다. 설치 뒤 GetUp은 열지 않았다. 기존 Games 제한은 종료됐기
때문에 새 활성 제한을 준비한 뒤 다음 5분 경계 전 앱을 닫고, 경계 뒤 Candy Crush Saga Shield를
첫 진입점으로 사용해야 한다.

iPhone 15 Pro Max에서도 사용자가 Candy Crush Saga Shield 첫 탭 뒤 `No releases available`을
확인했다. App Group 진단은 `releaseRouteSaved` → `syncEngineCaptureCompleted` →
`coinReservationPolicyError.insufficientBalance` 순서를 기록했다. 두 실기기의 부족 분기 수렴은
확인됐지만 iPhone 15 Pro Max의 상세 잔액·X 아이콘·제한 유지, 성공·복구·다기기 성공 수렴·실제
VoiceOver는 아직 미검증이다.

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
`Close` 뒤 terminal route가 정리되어 활성 `Home` 규칙 화면으로 돌아왔다. 동일 수정 산출물을
iPhone 15 Pro Max에도 데이터 보존 방식으로 설치했고 앱은 실행하지 않았다. BLK-021은 해결됐으며
새 해제나 구매는 실행하지 않았다.

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

실기기 설치·서명, 두 기기의 Shield 첫 탭 앱 진입·확정 잔액 부족 수렴, iPhone 17의 강제 종료
복원·재시도·제한 유지·terminal 정리, 5분 경계 무료 성공 차감과 iPhone 15 Pro Max의 2/0 → 1/0
잔액 수렴과 성공 내역의 확정 사용 `-1` 한 건 표시는 확인했다. DEBUG fixture의 복구 연결은
확인했고, 실제 VoiceOver에서 발견한 읽기 순서 결함과 남은 `heading` 안내를 수정했다. 사용자가
최신 빌드의 실제 음성·초점 순서까지 재확인해 BLK-022는 해결됐다.
T112의 iPhone 17 Pro Max iOS 26.5 시뮬레이터 관련 자동 테스트는 664개 선언·동적 실행
784회가 실패·skip 없이 통과했고, 이번 내역 표시 정책 단위 테스트·US4 집중 UI 테스트와 T089
설정을 명령행에서 비운 전체 `GetUpTests`도 통과했다. T113 실기기 인수는 완료했으며 다음 작업은
T114다.
