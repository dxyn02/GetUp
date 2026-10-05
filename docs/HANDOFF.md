# 작업 인계

## 현재 작업

- 기능: `002-live-activity-coins` Phase 9
- 마지막 완료 작업: T119a
- 진행 중 작업: T119 Live Activity 시각·접근성 실기기 검증
- 다음 작업: T119 한국어 unavailable/stale 실기기 대조와 미확인 항목 정리
- 경로 결정: BLK-025 해결, DEC-130에 따라 기존 foreground 대표 교체·종료 유지
- 알려진 문제: 남은 시간 VoiceOver 결함은 DEC-128 사용자 결정으로 수정·수동 인수 보류

## 2026-10-05 T119a Monitor 조회 probe

조사 완료: iPhone 17 / iOS 26.7.1(23H30)의 14:30:01 callback에서 활성 규칙
2→1 재평가와 ActivityKit 조회 0개, `fileWritten` 단계를 확인했다. 사용자도
종료 전 활동 표시·앱 미진입·종료 뒤 첫 규칙 활동 잔류를 확인했다. Monitor 직접
조정 경로는 이 조합에서 채택하지 않는다. 사용자는 APNs 설명 뒤 기존 방식 유지를
결정했다(DEC-130). T119a 완료, T119는 한국어 unavailable/stale 미확인으로 진행 중이다.
두 번째 시험의 14:35 전체 종료 증적은 결정 시점에 아직 수집하지 않았다.

첫 시험의 종료 시각은 14:10·14:15였다. 공유 제한 재평가 진단의 14:10:02
활성 2→1, 14:15:02 활성 1→0을 확인했다. 사용자는 앱을 열지 않고 다른 앱을
사용했고 첫 규칙 Live Activity가 남았다고 확인했다. 조회 파일은 없으며 이 결과로
ActivityKit 조회 미지원이라고 판단하지 않는다. 새 빌드는 조회 전·후와 파일 쓰기
성공·실패 단계를 `getup.debug.monitor-live-activity-probe` 공유 UserDefaults에도
기록한다. Debug 빌드·서명 검증·iPhone 17 설치가 성공했고 두 번째 규칙 준비를
요청했다. `debug.dylib`의 진단 문자열 포함을 확인했으며 실행 stub만 검사하면 안 된다.
진단 보강 뒤 제한 재평가 테스트 30건 재실행 통과(실패·skip 0), Release 빌드 및
진단 문자열 제외 검사가 통과했다.


사용자 승인에 따라 DEBUG `intervalDidEnd`의 defer에서 ActivityKit 활동 개수를
동기 조회해 App Group의 `device-activity-live-activity-probe.json`에 최대 12건을
기록한다. 기존 Shield 재평가·snapshot 경로는 먼저 실행하며 활동을 변경하지 않는다.
첫 규칙 종료 전에 메인 앱 생성 Live Activity가 표시됐다는 사용자 확인과 함께
callback 뒤 이 파일을 읽어 조회 가능성을 판단한다. 성공하면 실제 갱신·종료 시험을
이어간다. 이 진단 코드는 Release에서 제외한다.
Debug 서명 빌드·iPhone 17 설치 성공, 관련 제한 재평가 테스트 30건 실패·skip 없이
통과, Release 빌드·진단 문자열 및 심볼 제외 확인. 사용자에게 두 규칙의 종료 시각을
요청했다. 첫 종료 후에는 GetUp을 열지 않고 다른 앱을 사용해야 foreground 결과와
Monitor callback 결과를 구분할 수 있다.
## 2026-10-05 T119 Home 완료·자동 종료 요구

사용자가 영어 Home 기본 규칙명 실기기 표시를 완료로 확인했다. 대표 규칙 교체와
모든 규칙 종료 뒤 Live Activity 제거는 앱을 열어야 반영된다. 현재 구현은
foreground만 ActivityKit을 조정하므로 이 관찰과 일치한다. 앱 진입 없는 자동 반영은
BLK-025로 경로 결정을 요청했다. Device Activity Monitor 실기기 probe는 아직 하지
않았으며 Shield Action의 기존 앱 활동 조회 실패를 Monitor의 불가 증적으로 단정하지 않는다.
한국어 거리 확인 불가 실기기 표시는 사용자가 확인하지 못했다. T119는 미완료다.

## 2026-10-05 T119 VoiceOver 보류

사용자가 VoiceOver 문제를 일단 건너뛰도록 지시했다. DEC-128에 기록하고 BLK-024의
결정 차단을 해제했다. 남은 시간 VoiceOver는 통과 처리하지 않으며 이번 T119 완료
게이트에서 제외한다. 시·분 단위 표현을 유지하고 마지막 1분의 `0분` 안내를 알려진
문제로 남긴다. 코드 변경은 없고 기존 자동 테스트 26건 통과 결과를 유지한다.
영어 Home 이름과 전체 종료 실기기 결과, 한국어 unavailable/stale 대조가 남았다.

## 2026-10-05 T119 Home 기본 규칙명 지역화

규칙 이름이 없으면 Live Activity 스냅샷이 지역화 전 장소명 `집`을 전달했다.
홈에서 사용하는 `AppLocalizedCopy.savedPlaceName`을 동일하게 적용했다. 저장된
장소나 사용자 지정 규칙명은 변경하지 않는다. 영어 리소스를 실제로 읽어 `Home`
전달을 확인하고 한국어 기본명·사용자 지정 이름 보존을 함께 검증했다.
관련 Simulator 테스트 26건은 실패·skip 없이 통과했다. 실제 영어 Live Activity
표시와 BLK-024 마지막 1분 VoiceOver, 전체 종료는 아직 확인이 필요하다.
서명 Debug 빌드와 서명 검증은 통과했다. 처음에는 기기를 찾지 못했으나
CoreDeviceService 재시작 후 연결이 복구돼 iPhone 17에 데이터 보존 설치·실행했다.
iPhone Mirroring은 Mac 로그인 잠금 상태여서 실제 영어 표시를 사용자에게 확인 요청했다.

## 2026-10-03 T119 마지막 1분 접근성 추가 확인

사용자는 초 단위 상대 시간을 읽을 때 1분 미만에서 종종 규칙 이름으로 초점이
이동한다고 확인했다. 앞선 시스템 타이머·상대 시간·정적 접근성 문구 실험도 각각
초점 이동 또는 값 정체가 있었다. 현재 소스는 끝까지 읽히고 갱신되는 시·분 단위
대체 표현으로 되돌렸다. 마지막 1분에는 `0분`만 읽어 정확한 초를 알 수 없어
BLK-024를 열었고 T119를 완료 처리하지 않는다. 관련 Simulator 테스트 3개
묶음과 iPhone 17 서명 Debug 빌드가 통과했고, 안정 분 단위 빌드를 데이터
보존 방식으로 다시 설치했다.

## 2026-10-03 T119 대표 교체·VoiceOver 진단

iPhone 17의 첫 규칙 시간 종료 뒤 홈·Shield에는 두 번째 규칙이 활성으로 보였지만
Live Activity는 첫 규칙을 유지했다. foreground 진단에서 원하는 규칙과 기존 Activity의
`activityID`가 다른 것을 확인했고, 이전 Activity 종료 후 새 대표 요청으로 두 번째 규칙
표시를 실기기에서 확인했다. DEC-127과 관련 자동 테스트를 반영했다.

잠금화면·Dynamic Island 잘림 없음, Light/Dark, Reduce Motion은 사용자 확인을 받았다.
known·unavailable·stale의 Xcode Canvas AX5 정보·접근성 거리 문구를 확인했고
대상 Simulator 테스트는 통과했다. 한국어 Canvas 대조, 전체 종료 실기기 관찰이 남았다.
VoiceOver의 초 단위 안내는 읽는 중 초점이 이동한다. 초를 제외한 시·분 안내는
끝까지 읽히고 갱신되지만 마지막 1분에 `0분`으로만 읽혀 미완료다. T119를 체크하지
않는다. iPhone 17에는 시·분 안내 빌드를 다시 설치했다.

## 2026-09-29 T119 expanded 배지 재보정

사용자 사진에서 영역 trailing 24pt 적용 후에도 배지 캡슐 오른쪽 끝이 잘렸다.
배지 뷰에 trailing 12pt를 직접 추가한 뒤 대상 Simulator 테스트 2건과 실기기
서명 빌드·데이터 보존 설치·실행이 성공했다. 사용자가 iPhone 17 expanded
화면에서 배지 잘림이 없다고 확인했다.

## 2026-09-29 T119 expanded 배지 안전 여백

사용자가 확대 화면의 오른쪽 아래 `More rules` 끝 잘림만 지적했다. bottom 영역의
leading 14pt는 유지하고 trailing만 24pt로 늘렸다. Xcode Canvas에서 배지 글자·캡슐
끝 표시와 대상 Simulator 테스트 2건 통과를 확인했다. 최신 수정본의 iPhone 17 확대
화면을 다시 확인해야 한다. 서명 빌드는 데이터 보존 설치·앱 실행까지 성공했다.

## 2026-09-29 T119 AX5 시안·플랫폼 한계 확인

Figma AX5 샘플 `395:2277`은 968×371pt이고 61/75/53/53pt 서체를 사용한다. Apple의
iPhone 17 Live Activity 잠금화면·expanded 높이는 최대 160pt라 네 줄을 시안 크기로
동시에 표시할 수 없다. 현재 24/22/18pt 상한과 시간 오른쪽 위 배치는 DEC-120의 앱
선택이며 시스템이 글자 크기를 자동 제한한 결과는 아니다. Xcode Canvas iPhone 17 Pro
AX5 다중 규칙 잠금화면에서 네 정보의 표시·잘림 없음 확인. 실기기 최종 인수는 남았다.

## 2026-09-29 T119 기기별 적응형 보정

사용자 지적에 따라 expanded 시간의 90pt 고정 폭을 제거하고 가변 폭·우선순위·오른쪽
4pt 내부 여유로 수정했다. iPhone 17 Pro Canvas에서 네 요소가 표시되고 대상 Simulator
테스트 2건이 통과했다. 서명 빌드의 iPhone 17 데이터 보존 설치는 성공했으나 기기 잠금으로
자동 실행은 거부됐다. 최종 빌드의 실기기 화면 확인이 남았다.

## 2026-09-29 T119 expanded 표시 회귀 수정

최신 iPhone 17 사진에서 `fixedSize` 적용 뒤 expanded의 시간·거리 행이 사라진 회귀가
확인됐다. 해당 설정을 제거하고 90pt trailing 영역으로 변경했으며, compact 타이머는
추가로 오른쪽 12pt 이동했다. Xcode Canvas에서 expanded 네 요소가 다시 보이고 대상
Simulator 테스트 2건이 통과했다. 새 빌드의 실기기 화면 확인이 남았다.

## 2026-09-29 T119 compact·expanded 시간 재보정

사용자는 iPhone 17에서 다중 제한 `More rules` 배지는 통과했다고 확인했다. 같은 사진에서
compact 타이머 오른쪽 공백과 expanded 상단 시간 끝 글자 잘림이 남아 DEC-123을 적용했다.
compactTrailing 텍스트를 오른쪽 정렬하고 추가 오른쪽 여백을 제거했으며, expanded 시간은
가로 고정 크기로 압축을 막았다. 대상 Simulator 테스트 2건 통과 후 서명 빌드를 iPhone 17에
데이터 보존 설치·실행했다. 두 영역 실기기 재확인과 T119 나머지 인수가 필요하다.

## 2026-09-29 T119 Figma 다중 제한 정합화

사용자의 추가 피드백으로 Figma node `395:2142`·`395:2214`의 다중 제한 상태를
재확인했다. 일반 잠금화면과 expanded에서는 거리 오른쪽에 elevated surface 캡슐 배지를
같은 행에 표시하고, 잠금화면 테두리·모서리·간격·거리 글자 크기도 맞췄다. AX5 잠금화면
별도 줄과 compact `+` 제거는 이전 실기기 피드백에 따른다. Xcode Canvas 기본 크기 두
표면에서 배지가 보이고 Simulator 대상 테스트 2건이 통과했다. 최종 서명 빌드를 iPhone 17에
데이터 보존 설치하고 앱을 실행했다. 겹친 활성 규칙의 잠금화면·expanded 배지는 사용자
실기기 확인을 기다린다. T119 나머지 인수도 이어서 확인한다.

## 2026-09-29 T119 추가 사진 피드백

compact의 카메라와 시간 사이가 멀고 expanded 상단 양쪽 글자가 잘린다는 실기기 사진에
따라 DEC-121을 기록했다. compact의 카메라 쪽 여백을 0으로, 시간 텍스트를 왼쪽 정렬하고
expanded 상단의 바깥 여백을 24pt로 늘렸다. Xcode Canvas와 Simulator 대상 테스트 2건은
통과했다. 처음에는 iPhone 17 연결 시간 초과와 iPhone Mirroring의 Mac 로그인 잠금이
발생했으나 사용자가 잠금 해제·연결했다. 최종 빌드를 데이터 보존 설치하고 앱을 실행한 뒤
compact `250 m`와 숫자 타이머가 카메라 양옆에 가까워진 것을 미러링에서 확인했다.
expanded의 길게 누르기와 양쪽 글자 잘림은 사용자 실기기 확인을 기다린다.
잠금화면·VoiceOver·대표 교체·전체 종료 인수도 계속 필요하다.

## 2026-09-29 T119 실기기 피드백 수정

사용자가 전달한 Dynamic Island 스크린샷의 여백·잘림과 잠금화면 타이머 위치를 수정하고
compact 거리 오른쪽 `+`를 제거했다. 다중 규칙 정보는 VoiceOver에서 유지한다. Xcode Canvas
iPhone 17 Pro AX5의 잠금화면 known·다중 규칙, 2시간 compact 다중 규칙에서 정보가 모두
보이고 시간이 오른쪽 위에 있으며 `+`가 없음을 확인했다. 타이머 텍스트를 오른쪽 정렬해
잠금화면과 expanded의 오른쪽 여백도 맞췄다. 실기기 compact의 긴 영어
`minutes`는 사용자 승인으로 숫자 타이머로 교체하고 trailing 최대 너비를 66pt로 제한했다.
영어 다중 규칙 VoiceOver 문구도 Canvas에서 확인했다. iPhone 17에 서명 Debug 빌드를 데이터
보존 설치해 compact `500 m`·`59:39`의 잘림 없는 표시와 폭 축소를 확인했다. Simulator
presentation 테스트 2건은 최종 수정 뒤 통과했다. 최종 빌드의 실기기 잠금화면·VoiceOver와
대표 교체·전체 종료는 확인해야 한다. 변경 기준은 DEC-120과 Live Activity 하이파이 문서의
T119 추가 기록에 있다.

## 2026-09-28 BLK-023 결정 반영

사용자가 compact 영어 `minutes`, minimal 숫자 타이머를 승인했다. DEC-119에 근거를 기록했고
BLK-023을 해결했다. Xcode Canvas에서 minimal `44:47`이 잘림 없이 표시된다. T119의 실제
잠금화면·VoiceOver·Reduce Motion·대표 교체·종료 검증은 계속 필요하다.

## 2026-09-28 T119 진행 및 차단

PR #35를 병합한 `codex/live-activity-t119`에서 Xcode Canvas Debug `-Onone`, 만료된 preview
fixture를 고쳤다. iPhone 17에 데이터 보존 설치 후 expanded의 대표 규칙·시간·거리와 compact
거리 표시를 확인했다. 기존 사용자 정의 분 포맷은 시간이 빈칸이었고 시스템 분 포맷은
`144 minutes`를 정상 표시했다. 영어 `min` 승인 시안과의 차이 및 minimal의 `44...` 잘림을
BLK-023에 기록하고 사용자 결정을 요청했다. `LiveActivityPresentationTests` 2건은 통과했다.
실기기 잠금화면, VoiceOver, Reduce Motion, 대표 교체·종료는 미검증이다. BLK-017은 별도다.

## 2026-09-26 T116 구현 승인

사용자가 AX5 확대 수정본을 포함한 Figma node `395:2090`의 전체 하이파이를 “이대로 확정”하며
명시적으로 구현 승인했다. 승인 결과를 하이파이 문서와 DEC-118에 기록하고 T116을 완료 처리했다.
T117~T119 게이트가 해제됐으며, 다음 작업은 승인 상태를 고정하는 preview·snapshot fixture를 먼저
작성하는 T117이다.

## 2026-09-26 T115 하이파이

사용자 피드백에 따라 AX5 잠금화면의 초기 27/32/23pt 크기가 최대 Dynamic Type을 충분히 나타내지
못한다고 판단했다. 규칙명 61pt, 카운트다운 75pt, 거리·추가 제한 53pt로 확대하고 카드 높이를
371pt로 자동 확장했다. 최종 2080×2001 전체 렌더에서 잘림·겹침 없음을 확인했다.

Figma node `395:2090`에 T114 승인 구조를 유지한 Live Activity 하이파이를 작성했다. 앱의 실제
색상 token·SF Pro·16/12/8pt 간격·`location.fill`, Light appearance에서도 동일한 dark surface,
AX5 잠금화면, VoiceOver 읽기 순서, system-driven motion·Reduce Motion, ActivityKit 영역별 정보
예산과 4KB 제약을 보강했다. 첫 렌더의 AX5 세로 clipping은 부모 행을 hug sizing으로 바꿔 해결했고
최종 전체 렌더에서 잘림·겹침과 font 누락이 없음을 확인했다. 구현 인계는
`design/high-fidelity/US1-live-activity-refresh.md`에 기록했다. 다음 작업은 T116 명시적 구현 승인이고,
승인 전에는 T117~T119나 제품 Live Activity UI를 변경하지 않는다.

## 2026-09-26 T114 로우파이 초안

사용자가 피드백 반영본과 네 선택점을 포함한 전체 정보 구조를 명시적으로 승인했다. T114의 문서
상태와 체크리스트를 승인 완료로 바꾸고 task를 완료 처리했다. 다음 작업은 T115 하이파이 제작이며,
T116의 별도 구현 승인 전에는 제품 Live Activity UI를 변경하지 않는다. 사용자는 하이파이가
로우파이와 차이가 없다면 생략하도록 요청했지만, 로우파이 제외 범위에 최종 색상·서체·간격·motion,
Light/Dark, 최대 Dynamic Type, VoiceOver 및 ActivityKit 영역 제약이 남아 있다. 따라서 T115는
승인된 구조를 다시 만드는 대신 이 차이만 확정하는 보강 작업으로 진행한다.

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
