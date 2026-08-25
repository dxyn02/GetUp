# 프로젝트 상태

## 현재 기능
001-location-app-restriction

## 현재 단계
Phase 7 마무리 및 교차 관심사 진행 중

## 진행 중
없음

## 마지막 완료 작업
T081 — 좌표·앱 token이 log·analytics에 기록되지 않도록 검증·보강함

## 다음 작업
T082 — Family Controls 배포 entitlement와 App Group 신청·승인 절차 문서화

## 차단 상태
없음. BLK-009은 사용자의 1안 선택으로 해결됨.

## 계획 갱신 필요
없음. 규칙 삭제 UI의 코드·Figma 불일치를 T060·T061로 보정한 뒤 US3 테스트를 시작하도록 계획을 갱신했다.

## 테스트 상태
T081에서 `DiagnosticsLogger`의 최종 출력 경계를 임의 문자열 대신 닫힌 `DiagnosticEvent`만 받는
`DiagnosticEventWriting`으로 분리했다. production writer는 기존과 동일하게 안전한 고정 code만
`OSLog`에 public 값으로 기록하며, 테스트 writer로 실제 출력 직전 메시지와 log level을 검증할 수
있다. `PrivacyLoggingTests` 3개를 추가해 좌표·경도·horizontal accuracy·장소명·opaque app token을
포함한 알 수 없는 오류 설명과 저장소 file name·schema·revision 세부값이 writer에 도달하지 않고,
모든 operation·result·error가 닫힌 code로만 기록되며 success·cancelled·failure가 각각
info·notice·error 수준을 유지하는지 확인했다. production source 전역 감사에서 `OSLog` 외 print,
별도 logger, analytics·telemetry 경로는 발견되지 않았다. iPhone 17 Pro iOS 26.5 Simulator에서 T081
전용 test 3개와 전체 `GetUpTests` 144개 test case가 동적 인자를 포함해 총 187회 모두 통과했으며
실패·skip은 없다.

T080에서 `AccessibilityUITests.swift`를 추가해 최대 Dynamic Type `AX5`에서 규칙 편집과 권한 복구의
핵심 내용·하단 행동이 손실 없이 노출되고 최소 `44×44pt` touch target을 유지하는지 검증했다. 활성
제한의 VoiceOver용 상태·제목·시간·위치·앱 수·수정 차단 정보가 시각적 읽기 순서와 명시적 문구로
제공되는지 확인하고, Reduce Motion에서도 shield 표시·닫기 행동이 동일하며 Increase Contrast와
Differentiate Without Color에서도 위치 확인 불가와 제한 유지 상태가 색상 외 문구로 남는지
검증했다. 최초 실행에서 UI test restriction probe의 `앱 닫기` 접근성 높이가 약 24pt로 확인되어
button label의 hit area를 44pt로 보강했다. iPhone 17 Pro iOS 26.5 Simulator에서 T080 전용 UI test
5개와 기존 US1~US4를 포함한 전체 `GetUpUITests` 22개가 실패·skip 없이 통과했다. 실제 물리 기기의
VoiceOver 음성 순회, Accessibility Inspector와 Increase Contrast 시각 확인은 최종 실기기 검증에서
확인한다.

T079에서 `AppLifecycleCoordinator`가 복구마다 최신 `AuthorizationSnapshot`을 읽고 일정·region·위치
snapshot·제한 합집합을 재평가한 뒤 통합 `RestrictionPresentationState`를 반환하도록 확장했다. 앱의
최초 활성화, foreground 복귀와 위치 재확인은 같은 복구 경로를 사용하며, app 전용 권한 provider로
Background App Refresh 실제 상태까지 반영해 `PermissionGuideModel`을 생성·갱신·종료한다. 필수 권한
부족을 위치 불가보다 우선하고, 제한 복구 실패 시에는 상태를 추정하지 않아 기존 안내를 보존한다.
대상 lifecycle·권한 안내·권한 adapter 16개 논리 테스트가 동적 인자 포함 21회 모두 통과했다. iPhone
17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 141개가 동적 인자 포함 총 184회, US4 UI test 6개가
모두 통과했으며 실패·skip은 없다. 실제 시스템 Settings 복귀, 권한 철회 callback과 Family Controls
재승인은 T085 실기기 인수에서 확인한다.

T078에서 `RestrictionCoordinator`가 현재 시각 기준 24시간 이상 지난 위치 근거를 평가 직전에
`unavailable`로 정규화하도록 구현했다. 유효 시간대 안에서는 동일 revision의 기존 활성 shield만
보존하고 비활성 규칙에는 새 shield를 적용하지 않으며, 시간대가 끝나면 위치가 `unavailable`이어도
기존 우선순위에 따라 shield를 해제한다. 위치 불가·자동 해제·다중 규칙 coordinator 대상 10개 논리
테스트가 동적 인자 포함 16회 모두 통과했다. 이어 iPhone 17 Pro iOS 26.5 Simulator에서 T073을
제외하지 않은 전체 `GetUpTests` 139개가 동적 인자 포함 총 182회 모두 통과했으며 실패·skip은 없다.
실제 Device Activity 종료 callback과 물리 기기 위치 오류는 T085 실기기 인수에서 확인한다.

T077에서 승인된 Figma 하이파이의 권한 개요, Family Controls 복구, Always·Full Accuracy,
Background App Refresh, 위치 `unavailable` 비활성·활성의 여섯 상태를 `PermissionGuideView`와 UI test
fixture에 연결했다. 권한 목록의 원형 표시는 `🛡️`, `📍`, `🎯`, `🔄` 이모지로 교체하고 모든 화면의
하단 action을 56pt 공통 구조와 `safeAreaInset`으로 고정했으며, 내용은 Dynamic Type에서 스크롤된다.
화면 전환 시 제목 VoiceOver focus, 접근성 identifier·label·hint, 승인 문구 localization resource도
추가했다. iPhone 17 Pro iOS 26.5 Simulator에서 `UserStory4PermissionGuidanceUITests` 6개가 모두
통과했고 실패·skip은 없다. 단위·통합 회귀는 T073의 계획된 오래된 fix red만 검증 중 target에서
제외한 뒤 즉시 복구해 `GetUpTests` 137개 test case, 동적 인자 포함 총 174회가 모두 통과했다. 실제
VoiceOver 탐색과 권한 철회·Settings 복귀는 T080·T085에서 실기기로 확인한다.

T076에서 `PermissionGuideModel`이 Family Controls, Always location, Full Accuracy와 Background App
Refresh를 승인된 `🛡️`, `📍`, `🎯`, `🔄` 순서로 합성하도록 구현했다. 필수 권한과 진단용 Background
App Refresh를 구분하고 Family Controls 복구 뒤에는 최신 승인 상태와 별개로 앱 재선택 완료 전까지
복구 상태를 유지한다. 권한 복구 우선순위, 위치 권한 결합 안내, Background App Refresh 지연·저전력
모드 안내, 위치 `unavailable`의 비활성 신규 제한 금지와 활성 제한 보존 문구, foreground 갱신 시
해결된 안내 종료를 전용 단위 테스트 7개(동적 실행 포함 8회)로 검증했다. T073의 계획된 오래된 fix
red가 회귀 실행을 막지 않도록 전체 검증 중에만 해당 파일의 Sources membership을 제외하고 즉시
복구했다. iPhone 17 Pro iOS 26.5 Simulator에서 나머지 `GetUpTests` 137개 test case가 동적 인자를
포함해 총 174회 모두 통과했으며 실패·skip은 없다. `PermissionGuideView`와 앱 진입·foreground
wiring은 T077·T079에서 연결하고, T074의 UI test 6개는 그때 green으로 전환한다. `project.pbxproj`
plist 문법과 `git diff --check`는 통과했다.

T075에서 `AuthorizationStatusReading` 경계와 `SystemAuthorizationStatusReader`를 추가해 Family Controls,
위치 승인, 정확도와 Background App Refresh 시스템 상태 읽기를 snapshot 합성과 분리했다.
`SystemAuthorizationProvider`는 매 조회마다 네 상태를 새로 합성하며, 앱 전용 `forApplication()`은
`UIApplication.backgroundRefreshStatus`의 available·denied·restricted를 도메인 상태로 정규화한다.
app extension 기본 경로는 extension 사용 금지 API를 호출하지 않으며, Permission Guide가 사용할
`UIApplication.openSettingsURLString` 기반 `settingsURL`도 앱 전용으로 제공한다. T072에 Background
App Refresh 세 상태 mapping과 설정 URL 테스트를 보강했다. T073의 계획된 오래된 fix red가 회귀
실행을 막지 않도록 검증 중에만 해당 파일의 Sources membership을 제외하고 즉시 복구했다. iPhone
17 Pro iOS 26.5 Simulator에서 앱과 Device Activity extension을 함께 빌드하고 `GetUpTests` 130개
test case가 동적 인자를 포함해 총 166회 모두 통과했으며 실패·skip은 없다. 실제 권한 철회와
Settings 이동·복귀는 T079 wiring 후 T085 실기기 인수에서 검증해야 한다. `project.pbxproj` plist
문법과 `git diff --check`는 통과했다.

T074에서 승인된 US4 하이파이의 권한 개요, Family Controls 재승인·앱 재선택, Always·Full Accuracy,
Background App Refresh 안내 4개와 위치 `unavailable` 재확인 후 비활성·활성 홈 상태로 복귀하는
2개 흐름을 `UserStory4PermissionGuidanceUITests.swift`에 작성했다. 시스템 Settings 자체는 iOS 소유
화면이므로 GetUp의 `설정 열기` 행동 노출까지만 검증하고 외부 앱 내부는 assertion하지 않는다.
T072의 계획된 compile red가 UI target 빌드를 막지 않도록 검증 중에만 해당 파일의 Sources
membership을 제외하고 즉시 복구했다. iPhone 17 Pro iOS 26.5 Simulator에서 신규 UI test 6개가
모두 실행됐으며 아직 `permissionGuide.screen`과 scenario fixture가 없어 6개 모두 실패하는 의도한
red를 확인했다. T076·T077·T079에서 모델·화면·foreground 및 위치 재확인 갱신을 연결해 green으로
전환해야 한다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다.

T073에서 위치 요청 오류, 24시간 전 fix, 음수 horizontal accuracy, 설정 반경과 오차 원의 경계
중첩을 실제 `LocationMonitor` → `LocationConditionSnapshot` → `RestrictionCoordinator` 경로에
주입하는 `LocationUnavailableTests.swift`를 작성했다. 각 원인에서 활성 제한은 그대로 유지하고
비활성 상태에는 새 제한을 적용하지 않는 계약을 각각 검증해 총 8개 동적 사례가 된다. T072의
계획된 compile red가 후속 suite 실행을 막지 않도록 검증 중에만 해당 파일의 Sources membership을
제외하고 즉시 복구했다. iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests`에서 기존 사례와
위치 오류·음수 accuracy·경계 중첩 사례 126개가 통과했고, 오래된 fix의 활성·비활성 2개는 24시간
전 근거를 `.inside`로 판정해 실패하는 의도한 red를 확인했다. 오래된 위치 최신성 판정과 상태 보존은
T078에서 green으로 전환해야 한다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다.

T072에서 `AuthorizationSnapshot`의 Family Controls, 위치 승인, 정확도, Background App Refresh
상태 조합 5개와 매 조회 시 최신 시스템 상태를 다시 합성하는 계약을
`AuthorizationAdapterTests.swift`에 작성하고 GetUpTests target에 추가했다. Background App Refresh는
진단 상태로 snapshot에 보존하되 기존 결정대로 신규 shield 적용의 필수 권한 gate에는 포함하지
않는다. iPhone 17 Pro iOS 26.5 Simulator의 대상 suite 실행은 아직 구현되지 않은
`AuthorizationStatusReading`과 `SystemAuthorizationProvider(statusReader:)` 때문에 compile 단계에서
실패해 의도한 red를 확인했으며, 이 계약은 T075에서 구현한다. 최초 sandbox 실행은
CoreSimulatorService 접근 제한으로 기기를 찾지 못했으나 Simulator 접근을 허용한 재실행에서는
환경 오류 없이 위 계약 누락으로 실패했다. `project.pbxproj` plist 문법과 `git diff --check`는
통과했으며 실패 테스트 task이므로 전체 suite는 실행하지 않았다.

T071에서 사용자가 직접 수정한 현재 US4 하이파이를 구현 기준으로 승인했다. 최종안은 화면 우측
상단 badge를 제거하고 권한 점검 목록의 `🛡️`, `📍`, `🎯`, `🔄` 표시와 기존 문구·action 구조를
유지한다. 최종 Figma wrapper를 다시 렌더링하고 여섯 화면, text node 48개, action frame 10개를
검사했으며 제품 font는 SF Pro Bold·Regular·Semibold만 사용했다. 빈 text, placeholder, shimmer와
393×852pt 화면 직접 자식 overflow는 모두 0건이고, action은 단일 화면 `y=768`, 두 행동 화면
`y=692`·`y=768`, `353×56pt`로 일치한다. 디자인 승인 문서 작업이므로 code test는 실행하지 않았다.
다음 작업은 T072~T074 실패 테스트이며 T077 UI 구현은 승인된 이 하이파이를 기준으로 진행한다.

T070에서 T069 승인 로우파이를 보존한 채 별도 Figma wrapper에 권한 점검, Family Controls 복구,
Always·Full Accuracy, Background App Refresh, 위치 `unavailable`의 비활성·활성 하이파이 6개 화면과
접근성·구현 인계 panel을 작성했다. GetUp Focus `Eyebrow`·`Title`·`Subtitle`·`Button` text style과
semantic color·radius token을 적용하고, 권한별 emoji badge와 상태 → 원인 → 제한 영향 → 복구 행동
위계를 추가했다. 전체 wrapper와 각 화면을 렌더링하고 text node 54개, icon badge 6개, action frame
10개를 감사한 결과 제품 font는 SF Pro Bold·Regular·Semibold만 사용했으며 빈 text, placeholder,
shimmer와 393×852pt 화면 직접 자식 overflow는 모두 0건이었다. action은 단일 화면 `y=768`, 두 행동
화면 `y=692`·`y=768`, `353×56pt`로 일치한다. 디자인·문서 task이므로 code test는 실행하지 않았고,
실제 Accessibility Inspector·VoiceOver·AX1~AX5·시스템 설정 복귀 focus는 구현 후 물리 기기에서
검증한다. 다음 작업은 T071 사용자 검토와 구현 승인이다.

T069에서 사용자가 직접 수정한 현재 Figma 상태를 최종 승인했다. 승인본은 권한 설명에 `🛡️`, `📍`,
`🎯`, `🔄` 표시를 사용하고 여섯 화면의 하단 action을 공통 baseline에 정렬한다. 최종 wrapper를
다시 렌더링하고 text node 48개와 버튼 frame 10개를 검사했으며, 빈 text, placeholder와 비정상
크기 text는 0건이었다. 기본 본문은 SF Pro를 유지하고 emoji가 포함된 일부 text run은 Figma에서
mixed font로 보고된다. 디자인 승인 문서 작업이므로 code test는 실행하지 않았으며 다음 작업은
T070 하이파이 제작이다.

T069 사용자 피드백에 따라 `US4-LF-01` 권한 설명 앞의 원형 bullet을 앱 사용 제한 `🛡️`, 위치 접근
`📍`, 정확한 위치 `🎯`, Background App Refresh `🔄` 표시로 교체했다. 여섯 화면의 primary 버튼은
모두 `x=20, y=692`, secondary 버튼은 `x=20, y=768`, 크기는 `353×56pt`로 고정해 내용 길이와
관계없이 같은 위치에 표시되도록 수정했다. 사용자가 Figma에서 직접 조정한 wrapper 배경과 화면
문구는 보존하고, 밝은 wrapper에서 상단 제목이 읽히도록 기존 `color/onAccent` token으로 대비만
보정했다. 반영본 자동 감사에서 text node 49개, 버튼 frame 10개를 확인했으며 SF Pro 외 서체, 빈
text, placeholder, shimmer와 화면 경계 밖 text overflow는 모두 0건이었다. 디자인·문서 변경이므로
code test는 실행하지 않았고, T069 완료 여부는 사용자 재검토와 승인 뒤 결정한다.

T068에서 기존 Figma 파일의 `GetUp Focus` local color·spacing·radius variable과 SF Pro typography를
재사용해 권한 점검, Family Controls 재승인·앱 재선택, Always·Full Accuracy 설정, Background App
Refresh 확인, 위치 `unavailable`의 비활성·활성 상태를 여섯 개 393×852pt frame으로 제작했다. 위치
확인 불가에서는 위치만을 근거로 제한 상태를 바꾸지 않고, 비활성은 새 shield 미적용, 활성은 기존
shield 보존, 시간 종료는 위치와 무관하게 해제하는 계약을 Figma panel과
`design/low-fidelity/US4-permission-location-errors.md`에 기록했다. Figma wrapper와 각 화면을
렌더링하고 text node 52개를 자동 감사한 결과 SF Pro 외 서체, 빈 text, placeholder, shimmer와 화면
경계 밖 text overflow는 모두 0건이었다. 실제 좌표·주소·앱 이름·bundle identifier·app token은
포함하지 않았다. 디자인·문서 task이므로 code test는 실행하지 않았으며 다음 작업은 T069 사용자
검토다.

T067에서 `AppModel.refreshRestrictionStatus()`가 최신 active `(ruleID, revision)` 집합을 읽은 뒤 홈의
`RestrictionStatusModel`과 현재 열린 `RuleEditorModel`의 `RestrictionModificationGuard`를 같은
snapshot 기준으로 함께 갱신하도록 연결했다. 자동 해제로 해당 revision이 active set에서 사라지면
열린 편집기의 guard가 즉시 제거되고, 편집을 닫았다가 같은 규칙에 다시 진입해 끄기·저장·삭제를
사용할 수 있다. 반대로 foreground 복구에서 규칙이 활성로 확인되면 같은 재계산 경계가 편집 guard를
다시 적용한다. `initialEditorDraft`도 최초 load가 완료된 active set에 맞춰 guard를 동기화한다.
iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 126개 test case가 동적 인자를 포함해 총
158회 모두 통과했고 실패·skip은 없다. T063 US3 UI suite의 활성 guard, 해제 후 끄기, 해제 후 삭제
3개도 모두 통과했다. `project.pbxproj` plist 검사와 `git diff --check`는 통과했다. Phase 5 US3의
시간 종료·신뢰 가능한 위치 이탈 자동 해제, 활성 중 내부 변경 거부, 해제 후 편집 재진입을 독립
검증했으며 다음 작업은 T068 US4 로우파이 제작이다.

T066에서 활성 `(ruleID, revision)`이 현재 규칙과 일치하면 `RuleEditorModel`에
`RestrictionModificationGuard`를 주입해 규칙 끄기와 저장을 거부하고, `AppModel`의 저장·삭제 경계도
같은 guard를 확인하도록 연결했다. 활성 홈의 `조건 종료 후 수정 가능` control은 승인된 네이티브
SwiftUI Alert를 열어 장소 이름·반경·종료 시각과 수정·끄기·삭제 가능 조건을 안내하고 편집 화면으로
진입하지 않는다. 비활성 편집 화면에는 `ruleEditor.enabled` toggle을 추가해 해제 후 규칙을 끄고
저장할 수 있다. `restriction_guard.*`와 `restriction_status.*` 문구는 `Localizable.xcstrings`에서
관리한다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 125개 test case가 동적 인자를
포함해 총 157회 모두 통과했고 실패·skip은 없다. T063 UI suite의 활성 guard, 시간 종료 후 끄기,
위치 이탈 후 삭제 3개도 모두 통과해 계획된 실패를 green으로 전환했다. 네이티브 Alert action에 직접
accessibility identifier를 지정하면 iOS 26 Simulator 접근성 트리에 동일 버튼이 중첩되는 현상이 있어
system-owned 제목과 label로 단일 focus target을 유지했다. 문자열 카탈로그 JSON 검사,
`project.pbxproj` plist 검사와 `git diff --check`는 통과했다. 기존에 열린 편집기의 guard를 자동 해제
뒤 최신 active set으로 갱신하는 동작은 T067에서 연결한다.

T065에서 `DeviceActivityMonitorExtension.intervalDidEnd`가 callback 진입 시각을 즉시 기록한 뒤 공통
live `RestrictionCoordinator`의 `handleTimeEvent(confirmedAt:)`를 호출하도록 연결했다. named store를
무조건 비우지 않고 저장된 모든 규칙을 현재 시각으로 재평가해 종료된 규칙은 위치 상태와 무관하게
해제하면서 다른 활성 규칙의 앱 token 합집합은 보존한다. `DependencyContainer`의 공통 coordinator
factory를 추가하고 `AppLifecycleCoordinator.live`도 같은 조립 경계를 사용하도록 정리했다. 보호
snapshot read나 live 조립이 실패하면 다른 활성 규칙을 잘못 제거하지 않고 기존 shield를 보존한다.
시간 종료 테스트의 위치 근거를 `unavailable`로 변경해 시간 우선 해제를 coordinator 수준에서
검증했다. iPhone 17 Pro iOS 26.5 Simulator에서 앱과 Device Activity extension을 함께 빌드하고 전체
`GetUpTests` 123개 test case가 동적 인자를 포함해 총 155회 모두 통과했으며 실패·skip은 없다.
실제 background·종료 상태의 `intervalDidEnd` 전달과 system shield 제거는 Simulator로 입증하지
않으며 T085 실기기 인수에서 확인해야 한다. T063 UI suite의 계획된 실패 2개는 T066·T067 구현 전까지
남아 있다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다. 다음 작업은 T066 활성 중
변경 guard와 종료 조건 안내 구현이다.

T064에서 `RestrictionCoordinator`의 time·location event에 선택적 `confirmedAt` 입력을 추가하고,
실제 제한 adapter write가 성공한 경우에만 `RestrictionTransitionMeasurement`를 반환하도록 구현했다.
측정 결과는 신뢰 가능한 event 확인 시각, effect 완료 시각, 경과 초와 `applyShield | removeShield`
분류를 제공한다. 시간 종료와 신뢰 가능한 위치 이탈은 활성 제한을 제거하며, 위치 `unavailable`과
동일 상태 반복 평가는 write·측정을 모두 생략한다. 다중 규칙에서 일부만 끝나 남은 앱 token 합집합을
다시 적용하는 경우도 사용자 관점의 부분 해제이므로 `removeShield` 측정으로 분류한다. 인자 없는 기존
coordinator 호출은 진입 시각을 자동 사용해 호환성을 유지하고 restoration은 신뢰 가능한 조건 변경
event가 아니므로 측정하지 않는다. T062 자동 해제 테스트 4개와 기존 coordinator 회귀 테스트가 모두
통과했으며, iPhone 17 Pro iOS 26.5 Simulator의 전체 `GetUpTests` 123개 test case가 동적 인자를
포함해 총 155회 모두 통과했고 실패·skip은 없다. T063 UI suite의 계획된 실패 2개는 T066·T067
구현 전까지 남아 있어 전체 UI suite는 실행하지 않았다. `project.pbxproj` plist 문법과
`git diff --check`는 통과했다. 다음 작업은 T065 Device Activity interval 종료 연결이다.

T063에서 `UserStory3AutoReleaseUITests.swift`에 활성 규칙의 공통 변경 guard Alert, 시간 종료 뒤
편집·끄기 허용, 신뢰 가능한 위치 이탈 뒤 정상 삭제 허용을 검증하는 UI test 3개를 추가했다. 활성
상태에서는 `restrictionStatus.editDisabled` control이 `제한 중에는 수정할 수 없어요` Alert를 열고
장소·반경·종료 시각과 수정·끄기·삭제 거부를 함께 안내한 뒤 편집 화면으로 진입하지 않아야 한다.
해제 상태에서는 `ruleEditor.enabled` toggle로 규칙을 끄고 저장할 수 있으며, 삭제는 기존 파괴적
확인 Alert를 거쳐 완료되어야 한다. T062의 계획된 red 단위 테스트를 검증 중에만 target에서 제외하고
iPhone 17 Pro iOS 26.5 Simulator에서 T063 suite를 실행한 결과 3개 중 해제 후 삭제 1개는 통과했고,
활성 guard control과 해제 후 enabled toggle이 아직 없어 2개가 예상 지점에서 실패했으며 skip은
없었다. T062 target membership은 즉시 복구했다. T066·T067에서 guard·끄기 UI와 상태 갱신을 연결한
뒤 green으로 전환해야 하며, T062가 compile red이므로 전체 suite는 실행하지 않았다.
`project.pbxproj` plist 문법과 `git diff --check`는 통과했다. 다음 작업은 T064 자동 해제 core
구현이다.

T062에서 `RestrictionReleaseTests.swift`에 시간 종료와 신뢰 가능한 위치 이탈이 활성 제한을
해제하는 경로, 위치 `unavailable`이 기존 제한을 보존하는 경로, 같은 종료 event 반복 평가가
해제·측정을 중복하지 않는 경로의 실패 테스트 4개를 추가했다. 시간·위치 event가 신뢰 가능한 조건
변경 확인 시각을 `confirmedAt`으로 전달하고 실제 remove effect가 발생한 결과에만
`transitionMeasurement`를 제공하는 계약을 명시했다. iPhone 17 Pro iOS 26.5 Simulator에서 새 suite를
실행해 현재 `RestrictionCoordinator`에 `confirmedAt` event API가 없어 compile 단계에서 실패하는
계획된 red 상태를 확인했다. 따라서 4개 테스트는 아직 실행되지 않았고 전체 suite도 실행하지
않았다. T064에서 event 시각·remove effect·측정 결과를 구현한 뒤 green으로 전환해야 한다.
`project.pbxproj` plist 문법과 `git diff --check`는 통과했다. 다음 작업은 T063 실패 UI test다.

T061에서 사용자가 T060의 정상 삭제 버튼·확인 Alert와 활성 삭제 guard 공통 진입점 동기화 결과를
구현 기준으로 승인했다. `design/high-fidelity/US1-rule-configuration.md`와
`design/high-fidelity/US3-auto-release.md`의 검토 기록·승인 상태·미해결 항목을 갱신하고 T061을
완료 처리했다. 디자인 승인 문서 작업이므로 code test는 실행하지 않았으며 다음 작업은 T062 자동
해제 core 실패 테스트 작성이다.

T060에서 T037의 실제 `RuleEditorView`를 기준으로 최종 US1 wrapper에 `HF-FLOW-12 / 규칙 삭제`,
`HF-FLOW-13 / 규칙 삭제 확인`과 상태·문구·접근성·구현 인계 panel을 추가했다. 비활성 규칙은
`GetUp Focus/color/error`의 353×52pt bordered 버튼에서 `규칙을 삭제할까요?` Alert로 이어지고,
저장 장소 보존 설명과 `취소`·공식 `Mode=Light, Type=Destructive` 삭제 행동을 제공한다. 활성 규칙은
같은 삭제 진입점에서 기존 `US3-HF-02` 종료 조건 guard Alert로 분기하도록 문서화했다. 두 화면과
규격 panel을 개별 렌더링했으며 text node 70개에서 SF Pro 외 서체, 빈 text, placeholder와 직접 자식
overflow가 모두 0건이었다. Figma·문서 task이므로 code test는 실행하지 않았다. 다음 작업은 T061
사용자 검토다.

규칙 삭제 UI가 T037에서 코드에 보완됐지만 최종 US1 Figma wrapper에는 반영되지 않은 정합성 누락을
확인했다. 정상 삭제 버튼·파괴적 확인 Alert는 활성 중 삭제 거부 UI의 진입 기준이므로 마무리 대조
단계까지 미루지 않고 T060 Figma 동기화와 T061 사용자 검토를 US3 테스트보다 앞에 추가했다. 기존
미완료 task는 실행 순서를 유지해 T062~T089로 재번호화했다. 이번 변경은 계획·상태 문서 작업이므로
code test는 실행하지 않았으며, 다음 작업은 T060이다.

T059에서 사용자가 완료 전용 UI를 제외한 US3 하이파이를 구현 기준으로 승인했다. Figma wrapper와
규격 panel을 `승인됨`으로 갱신하고 `design/high-fidelity/US3-auto-release.md`에 승인자·승인일·미해결
항목 없음 상태를 기록했다. 승인 문구 반영 뒤 wrapper를 다시 렌더링했으며, 전체 64개 text node에서
SF Pro 외 서체, 누락 font, 빈 text, placeholder, shimmer와 화면 경계 overflow가 모두 0건이었다.
Apple iOS 26 `Alert` component instance와 Accessibility annotation도 유지됨을 확인했다. 디자인·문서
승인 task이므로 code test는 실행하지 않았다. 다음은 T060·T061 디자인 정합성 보정과 승인,
T062·T063 테스트 작성이며, 이후 T066·T067 UI
구현은 이 승인본을 기준으로 진행한다.

T058에서 승인된 US3 로우파이와 기존 US2 활성 홈 하이파이를 기준으로 활성·guarded 홈과 iOS 26
공식 `Alert` component를 사용하는 편집 차단 상태를 제작했다. 시간 종료 또는 신뢰 가능한 위치 이탈
뒤에는 활성 규칙의 앱 token 합집합을 다시 계산하고, 별도 완료 화면·배너·toast·VoiceOver
announcement 없이 기존 예정·비활성 홈으로 복귀하는 승인 동작을 유지했다. VoiceOver 읽기 순서,
Alert dismiss 뒤 focus 복귀, AX1–AX5 자연 줄바꿈, Increase Contrast, Reduce Motion과 최소 44×44pt
touch target을 Figma 규격·Accessibility annotation과 `design/high-fidelity/US3-auto-release.md`에
기록했다. wrapper와 두 화면·규격 panel을 개별 렌더링했으며, 전체 64개 text node에서 SF Pro 외
서체, 누락 font, 빈 text, placeholder, shimmer와 화면 경계 overflow가 모두 0건이었다. 디자인·문서
task이므로 code test는 실행하지 않았다. 이후 T059 승인으로 구현 gate를 해제했으며 T060·T061
디자인 정합성 보정 뒤 T062·T063 테스트를 먼저 작성하고 T066·T067 UI 구현을 시작한다.

T057에서 사용자가 자동 해제 완료 전용 UI 제거 반영본을 승인했다. Figma 보드와
`design/low-fidelity/US3-auto-release.md`를 `승인됨`으로 갱신하고, 전용 화면·배너·toast 없이 조건
종료 뒤 기존 예정·비활성 홈으로 복귀하는 흐름을 T058 이후 구현 기준으로 확정했다. 승인 상태
텍스트를 반영한 Figma wrapper를 다시 렌더링해 레이아웃을 확인했다. 디자인·문서 승인 task이므로
code test는 실행하지 않았다.

T057 사용자 피드백에 따라 자동 해제 완료를 알리는 전용 화면은 불필요하다고 결정했다. Figma에서
`AUTO RELEASE COMPLETE` frame을 삭제하고, 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 제한 합집합을
재계산한 다음 활성 표시와 guard가 제거된 기존 예정·비활성 홈으로 복귀하도록 흐름과 설명을
갱신했다. 완료 전용 화면·배너·toast와 별도 VoiceOver announcement는 제공하지 않는다. 변경된
wrapper와 남은 393×852pt 화면 두 개를 다시 렌더링했고, 전체 64개 text node에서 누락 font, 빈 text,
임시 placeholder와 화면 경계 overflow가 모두 0건이었다. 디자인·문서 변경이므로 code test는
실행하지 않았다. 이후 사용자 승인으로 T057을 완료 처리했으며 T058 하이파이를 시작할 수 있다.

T056에서 기존 US2 활성 홈 카드와 iOS 26 공식 `Alert` component를 재사용해 `활성 홈 → 규칙 수정
시도 → 편집 차단과 종료 조건 안내 → 시간 종료 또는 신뢰 가능한 위치 이탈 뒤 기존 홈 복귀` 흐름의
로우파이를 Figma에 제작했다. 활성 규칙의 편집·끄기·삭제를 같은 guard로 거부하고, Alert에서
`집 1km 밖` 또는 `09:00 AM 이후`라는 실제 종료 조건을 안내한다. 두 해제 경로는 현재 활성 규칙의
앱 token 합집합을 다시 계산하고, 별도 완료 UI 없이 활성 표시와 guard를 제거한 기존 홈 상태로
합류한다. 393×852pt 화면 두 개와 상태 설명 panel을 렌더링했고, 전체 64개 text node에서 누락 font,
빈 text, 임시 placeholder와 화면 경계 overflow가 모두 0건이었다. 디자인·문서 task이므로 code
test는 실행하지 않았다. 이후 T057 승인본을 확정해 T058 하이파이를 시작할 수 있다.

T055에서 shared 적용 상태의 `(ruleID, revision)`과 현재 규칙 revision이 정확히 일치할 때만 활성으로
표시하는 `RestrictionStatusModel`을 추가했다. 앱 최초 load, 규칙 저장 직후 runtime 동기화, foreground
복귀 뒤 적용 상태를 다시 읽고, 활성 규칙은 승인된 `RESTRICTION ACTIVE` 카드에서 장소·반경, 종료
시각, 제한 앱 개수와 `조건 종료 후 수정 가능` 안내를 표시한다. 비활성 규칙은 기존 홈 카드와 편집
흐름을 유지한다. Dynamic Type 접근성 크기에서는 pager 높이를 확장하고 정보가 축약되지 않도록 했으며,
T045 전용 Simulator probe는 `--ui-test-scenario restriction-activation`에서만 제공한다. 모델 단위
테스트는 구현 전 계획된 compile 실패를 확인한 뒤 green으로 전환했고, T045 UI 테스트 3개에서
시간 활성·위치 내부의 대상 앱 shield, 비대상 앱 통과, 시간 또는 위치 조건 불충족 시 비활성을 모두
검증했다. iPhone 17 Pro iOS 26.5 Simulator에서 전체 `GetUpTests` 119개가 동적 인자를 포함해 총
151회 모두 통과했고 실패·skip은 없다. 기본 글자 크기 Simulator 캡처로 활성 카드의 색상, 정보 순서와
시간 표기 잘림이 없음을 확인했다. 실제 App Group 적용 상태, restricted app system shield와 물리 기기
VoiceOver·최대 Dynamic Type은 T085 인수에서 확인해야 한다. `project.pbxproj` plist 문법과
`git diff --check`도 통과했다.

T054에서 `RuleConfigurationService`가 저장 장소와 규칙 collection을 모두 성공적으로 기록한 뒤에만
새 rule revision을 runtime 동기화 경계로 전달하도록 확장했다. `AppModel`은 이 경계를 보존하고 live
`AppEnvironment`는 기존 `AppLifecycleCoordinator.restore()`에 연결한다. 따라서 저장 직후 GetUp 소유
일정·region을 초기화하고 저장된 모든 활성 규칙을 새 revision으로 재등록하며, `.restoration` fresh
위치 근거를 갱신한 다음 `RestrictionCoordinator`로 제한 앱 합집합을 즉시 재평가한다. 규칙 snapshot
write가 실패하면 runtime 동기화는 호출되지 않고, 개별 schedule·location 등록 실패는 DEC-028의
best-effort 복구를 따라 다른 규칙과 최종 제한 재평가를 막지 않는다. 저장 완료 후 새 revision 전달,
두 snapshot 이전 호출 금지, 규칙 write 실패 시 runtime 미변경과 `AppModel` 전달을 테스트했다.
iPhone 17 Pro iOS 26.5 Simulator에서 앱과 모든 extension을 함께 build하고 전체 `GetUpTests` 117개가
동적 인자를 포함해 총 149회 모두 통과했으며 실패·skip은 없다. 실제 Device Activity 일정·Core
Location region 등록과 저장 즉시 shield 전환은 entitlement·Always·Full Accuracy가 적용된 실기기
인수 T085에서 확인해야 한다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T053에서 `ShieldActionResponsePolicy`와 `ShieldActionExtension`을 구현했다. 화면에 제공하는 primary
`앱 닫기` action은 `.close`를 반환하며 application·category·web domain callback이 모두 같은 정책을
사용한다. 구성 화면에는 secondary action이 없지만 시스템이 예기치 않게 secondary action을
전달하더라도 `.close`를 반환해 `.defer`, `.none`, `openParentalControlsApp`로 제한을 우회하거나
GetUp을 여는 경로를 만들지 않는다. action 처리 과정은 Managed Settings store, App Group 상태와
사용자 데이터를 읽거나 변경하지 않는다. iPhone 17 Pro iOS 26.5 Simulator에서 앱과 Shield Action
extension을 함께 build하고 전체 `GetUpTests` 115개가 동적 인자를 포함해 총 147회 모두 통과했으며
실패·skip은 없다. 실제 restricted app 위에서 primary button을 눌렀을 때의 system-owned 종료 전환은
Simulator unit test로 입증하지 않으며 T085의 Family Controls entitlement 적용 실기기 인수에서
확인해야 한다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T052에서 사용자의 BLK-009 1안 결정을 반영해 `ShieldContentProvider`와
`ShieldConfigurationExtension`을 구현했다. App Group의 규칙·장소 snapshot과 활성
`(ruleID, revision)` 집합을 동기적으로 읽고, shield를 요청한 opaque application token에 실제로
대응하는 활성 규칙만 선택한다. 단일 규칙은 장소·반경·종료 시각을 포함한 승인 문구를 표시하고,
두 개 이상이면 개수와 모든 규칙의 위치 또는 시간이 끝나야 한다는 짧은 요약을 표시한다. token이
없거나 snapshot을 읽지 못하면 장소명·앱명 등 개인정보가 없는 fallback을 사용한다. 시스템 소유
shield layout에 어두운 배경, 정적 SF Symbol, 한국어 문자열 카탈로그와 `앱 닫기` primary button을
연결했으며 이름·bundle identifier·token을 기록하는 로그는 추가하지 않았다. iPhone 17 Pro iOS
26.5 Simulator에서 앱과 Shield Configuration extension을 함께 build하고 전체 `GetUpTests` 113개가
동적 인자를 포함해 총 145회 모두 통과했으며 실패·skip은 없다. 실제 Family Controls entitlement가
있는 실기기에서의 shield 표시, Dynamic Type·VoiceOver 읽기 순서와 시각적 최종 확인은 T085 인수
검증에 남긴다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T052 착수 시 승인된 shield 하이파이·계약과 `DEC-016`의 앱 token 합집합을 대조하고 iOS 26.5 SDK의
`ManagedSettings.Application.token` 제공 여부를 확인했다. 대상 앱과 활성 규칙의 대응은 가능하지만,
두 개 이상 규칙이 같은 앱에 적용될 때 승인된 단일 장소·반경·종료 시각 문구는 실제 결합 해제
조건을 정확히 표현하지 못해 BLK-009에 기록했으며, 사용자가 1안을 선택해 해결했다.

T051에서 `DeviceActivityMonitorExtension.intervalDidStart`와 앱 foreground `scenePhase`를 공통
`AppLifecycleCoordinator`에 연결했다. 복구는 공유 규칙 snapshot read 성공 후에만 GetUp 일정·region을
초기화하고 모든 활성 규칙의 일정·region을 재등록하며, fresh fix를 rule ID별 `.restoration` 위치
condition으로 갱신한 뒤 T050 제한 합집합을 재평가한다. Family Controls의 `.approved`와 iOS 26의
`.approvedWithDataAccess`, Always·Full Accuracy를 실제 시스템 상태에서 정규화하는 복구용 권한
provider를 앱과 extension target에 추가했다. 개별 schedule·location 실패는 다른 규칙과 최종 제한
재평가를 막지 않으며, 첫 잠금 해제 전 보호 파일 read 실패는 기존 시스템 상태를 변경하지 않고
다음 event 재시도로 남긴다. iPhone 17 Pro iOS 26.5 Simulator에서 앱과 extension을 함께 build하고
전체 `GetUpTests` 110개가 동적 인자를 포함해 총 142회 모두 통과했으며 실패·skip은 없다. 최초 red
검증 시 CoreSimulator service 연결이 일시적으로 끊겼으나 권한을 허용한 최종 두 실행은 정상
통과했다. 실제 앱 종료 상태 `intervalDidStart`, background region 등록과 재부팅 후 첫 잠금 해제
event 전달은 Simulator로 입증하지 않으며 T085 실기기 인수에서 확인해야 한다.
`project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T050에서 사용자의 BLK-008 1안 결정을 반영해 `location-conditions.json`을 rule ID별 schema 2
collection으로 변경하고, rule ID가 없는 schema 1 위치 snapshot은 빈 collection으로 안전하게
해석했다. 적용 상태는 활성 `(ruleID, revision)` 집합을 추적하며, 기존 Boolean·revision만 남은
UserDefaults 상태는 `requiresReset`으로 판정해 GetUp named store를 최초 평가에서 정리한다.
`RestrictionCoordinator`는 time·location·restoration event마다 저장된 모든 규칙을 독립 평가하고,
위치 `unavailable`은 동일 revision으로 이미 활성인 규칙만 보존한 뒤 최종 활성 규칙의 application
token 합집합을 한 번 적용한다. 동시 활성, 중복 token 제거, 일부 규칙 종료 후 남은 합집합 보존,
반복 평가 무효과와 schema migration 테스트를 추가했다. iPhone 17 Pro iOS 26.5 Simulator에서 전체
`GetUpTests` 107개가 동적 인자를 포함해 총 139회 모두 통과했고 실패·skip은 없다. T045 UI test는
상태 UI와 test seam을 구현하는 T055 전까지 계획된 red 상태이므로 이번 검증 범위에서 제외했다.
`project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T050 착수 시 `RestrictionStateMachine`, `PlatformContracts.swift`, 공유 저장 계약과 다중 규칙 요구사항을
대조했다. 기존 계약은 위치 상태와 적용 shield 상태를 단일 `ruleRevision`으로만 표현해 두 개 이상의
활성 규칙 합집합을 안전하게 계산·복구할 수 없음을 확인했다. 제품 동작과 공유 저장 schema에 영향을
주는 선택이므로 구현과 task 완료 처리를 중단하고 BLK-008에 선택지와 권장안을 기록했다. 이번
세션에는 제품 코드 변경과 테스트 실행이 없다.

T049에서 `ManagedSettingsRestrictionAdapter.swift`를 앱과 Device Activity Monitor extension target에
추가했다. 고정 이름 `getup.restriction`의 `ManagedSettingsStore`에 규칙의 opaque application token만
shield로 설정하고, App Group `UserDefaults`에 적용 여부와 rule revision을 함께 기록한다. 같은
revision이 이미 적용된 경우 store와 상태 저장소 write를 모두 생략하며, 제거 시에도 GetUp named
store만 비운다. `DependencyContainer.makeRestrictionAdapter()`로 앱과 extension의 live adapter를
조립했다. iOS 26.5의 `ApplicationToken` Codable dictionary 표현에 맞게 T044 fixture를 바로잡은 뒤
해당 계약 테스트 3개가 모두 통과했다. 이어 iPhone 17 Pro iOS 26.5 Simulator에서 전체
`GetUpTests` 99개가 동적 인자를 포함해 총 131회 모두 통과했고 실패·skip은 없다. 실제 Family
Controls 승인 아래 시스템 shield 표시와 다른 제공자의 실제 named store 공존은 Simulator fake
결과로 입증하지 않으며 T083·T085의 entitlement 적용 실기기 검증에서 확인해야 한다.
`project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T048에서 `LocationMonitor.swift`를 앱 target에 추가했다. Always·Full Accuracy, region monitoring
가용성, 기기 최대 반경을 등록 전에 검사하고, 저장 장소 좌표와 규칙별 안정적인 identifier로 원형
region을 교체한다. Core Location 단발성 fix의 관측 시각·거리·horizontal accuracy를 T047 공식으로
판정해 `LocationConditionSnapshot`으로 저장하며, 오류는 좌표를 추정하지 않고 `unavailable`로
기록한다. `DependencyContainer.makeLocationMonitor()`로 live Core Location adapter와 공유 저장소를
조립했다. 기존 T043에 Always·Full Accuracy gate와 규칙별 region 교체 검증을 보강하고, T049의
계획된 red 테스트를 검증 중에만 target에서 제외했다. iPhone 17 Pro iOS 26.5 Simulator에서 7개
테스트가 동적 인자를 포함해 총 27회 모두 통과했으며 target membership은 즉시 복구했다. 중간에
종료 상태 Simulator가 `Busy` preflight 오류를 두 번 반환했으나 명시적으로 부팅한 뒤 같은 suite가
통과했다. 실제 Always 권한 prompt, Full Accuracy 상태 변경과 background·종료 상태 region event
전달은 Simulator 결과로 입증하지 않으며 T085 실기기 인수에서 검증해야 한다. `project.pbxproj`
plist 문법과 `git diff --check`도 통과했다.

T047에서 `LocationEvidenceEvaluator.swift`를 앱 target에 추가하고 중심 거리 `d`, 설정 반경 `R`,
horizontal accuracy `a`를 사용한 순수 판정을 구현했다. 음수 또는 유한하지 않은 입력은
`unavailable`, `d + a <= R`은 `inside`, `max(0, d - a) > R`은 `outside`, 나머지 경계 중첩은
`unavailable`로 분류한다. T048용 위치 snapshot 테스트와 T049의 계획된 red 테스트를 검증 중에만
제외하고 iPhone 17 Pro iOS 26.5 Simulator에서 여섯 반경별 내부·정확한 경계·외부·경계 중첩
4개 동적 테스트가 총 24회 모두 통과했으며, test source와 target membership은 즉시 복구했다.
T043의 최신 위치 snapshot 기록 테스트는 T048 구현 전까지 red 상태다. `project.pbxproj` plist
문법과 `git diff --check`도 통과했다.

T046에서 `DeviceActivityScheduleAdapter.swift`를 앱과 Device Activity Monitor extension target에
추가했다. 규칙 UUID와 요일을 포함하는 안정적인 activity name으로 선택 요일별 반복 일정을
등록하고, 동일 규칙의 이전 일정만 제거한 뒤 현재 규칙으로 복구하며, GetUp 소유 일정 전체 제거도
지원한다. 15분 미만 구간은 기존 일정 변경 전에 거부하고 자정 초과 구간의 종료 요일은 다음 날로
계산한다. 후속 T047·T048·T049의 계획된 red 테스트를 검증 중에만 target에서 제외하고 iPhone 17 Pro
iOS 26.5 Simulator에서 `DeviceActivityScheduleAdapterTests` 4개가 모두 통과했으며, target membership은
즉시 복구했다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다.

T045에서 `UserStory2RestrictionActivationUITests.swift`에 고정된 유효 규칙과 주입 시각·위치 상태를
사용하는 3개 실패 UI test를 작성했다. 시간 활성·위치 내부에서는 선택 앱 probe만 shield로 이동하고
비선택 앱 probe는 콘텐츠로 열려야 하며, 시간 비활성·위치 내부와 시간 활성·위치 외부에서는 선택
앱도 제한 없이 열려야 한다. 이 probe는 `--ui-testing`에서만 제공하는 Simulator 검증 경계이며 실제
Managed Settings shield의 출시 증거는 후속 실기기 인수 테스트로 남긴다. 선행 red 단위 테스트
T042~T044를 검증 중에만 target에서 제외하고 iPhone 17 Pro iOS 26.5 Simulator에서 새 UI test 3개가
compile·launch된 뒤 아직 없는 `restrictionStatus`·`restrictionProbe` 요소의 `XCTAssertTrue`에서 모두
실패하는 red 상태를 확인했다. 실패 3개, 통과·skip 0개이며 target membership은 즉시 복구했다.
`project.pbxproj` plist 문법과 `git diff --check`를 통과했고, T050의 활성화 경로와 T055의 상태 UI 및
UI test seam을 연결한 뒤 다시 실행해야 한다.

T044에서 `ManagedSettingsRestrictionAdapterTests.swift`에 규칙이 선택한 opaque application token만
GetUp named store에 shield로 기록하는 경로, 같은 rule revision이 이미 적용된 경우 Managed Settings와
적용 상태 저장소에 쓰지 않는 idempotency, 다른 제공자의 named store를 보존하는 경로를 검증하는
3개 실패 테스트를 작성했다. 테스트는 앱 이름이나 bundle identifier를 해석하지 않고 Codable
`ApplicationToken`만 사용하며 `GetUpTests` target에 포함했다. 선행 red 테스트인 T042·T043을 검증
중에만 target에서 제외해 iPhone 17 Pro iOS 26.5 Simulator 대상 빌드를 실행했고, T044 테스트 자체의
Swift 6 오류 없이 계획된 T049 타입인 `ManagedSettingsStoreAccess`,
`RestrictionApplicationStateStoring`, `ManagedSettingsRestrictionAdapter`가 아직 없어 compile
단계에서 실패하는 red 상태를 확인했다. 선행 테스트의 target membership은 즉시 복구했고,
`project.pbxproj` plist 문법과 `git diff --check`를 통과했다. T049 구현 뒤 이 suite를 다시 실행해야
한다.

T043에서 `LocationMonitoringAdapterTests.swift`에 500m·1km·2km·3km·4km·5km 각 반경의 확실한
내부, 정확도 0인 정확한 경계, 확실한 외부와 오차 원 경계 중첩 판정을 매개변수화하고, 최신 위치
evidence가 규칙 revision·관측 시각·거리·정확도·event source를 보존한
`LocationConditionSnapshot`으로 기록되는 실패 테스트를 작성했다. 총 5개 test case가 동적 인자를
포함해 25회 실행될 계약이며 테스트 파일을 `GetUpTests` target에 포함했다. iPhone 17 Pro iOS 26.5
Simulator 대상 빌드에서 계획된 T047·T048 타입인 `LocationEvidenceEvaluator`, `LocationEvidence`,
`LocationEvidenceProviding`, `LocationMonitor`가 아직 없어 compile 단계에서 실패하는 red 상태를
확인했다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했으며 T047·T048 구현 뒤 이
suite를 다시 실행해야 한다.

현재 작업은 최신 `origin/main`에서 분기한 `codex/us2-restriction-activation` 브랜치에서 진행한다.
US2의 관련 task를 같은 브랜치에 묶되 설계·운영 지침, T042, T043을 각각 논리적 커밋으로 분리한다.

T042에서 `DeviceActivityScheduleAdapterTests.swift`에 선택한 월·수·금의 반복 일정과 시작·종료
`DateComponents`, 14분 일정의 사전 거부와 기존 등록 보존, 일요일 자정 초과 일정의 월요일 종료,
동일 규칙의 이전 요일 일정만 교체하고 다른 규칙 일정은 보존하는 4개 실패 테스트를 작성했다.
테스트 파일을 `GetUpTests` target에 포함하고 `project.pbxproj` plist 문법과 `git diff --check`를
통과했다. iPhone 17 Pro iOS 26.5 Simulator에서 대상 suite 빌드를 실행해 테스트 자체의 Swift 6
동시성 오류는 없고, 계획된 T046 대상인 `DeviceActivityScheduling`,
`DeviceActivityScheduleAdapter`, `DeviceActivityScheduleAdapterError`가 아직 없어 compile 단계에서
실패하는 red 상태를 확인했다. 따라서 전체 테스트 통과 상태는 아니며 T046 구현 뒤 이 suite를
다시 실행해야 한다.

명세 품질 체크리스트 16/16개 항목을 통과함. 계획 산출물의 구조 검증을 통과함.
T025 착수 전 `xcodebuild -list -project GetUp.xcodeproj`로 6개 target과 공유 scheme을 확인했으나,
로컬 CoreSimulator service 연결 실패 경고가 발생했다. 이후 사용자가 BLK-006의 1안을 선택해 DST의
존재하지 않는 경계는 다음 유효 시각, 반복 시작은 첫 번째 발생, 반복 종료는 두 번째 발생으로
확정했다. `ScheduleEvaluatorTests.swift`에 14/15분, 선택·비선택 요일, 같은 날·자정 초과, DST 시작·
종료 보정과 반복 시각 경계를 작성하고, `RestrictionRuleValidatorTests.swift`에 요일·저장 장소·여섯
반경·앱 token·같은 시작/종료·14/15분 validation을 작성했다. 두 파일은 임시 계약 stub을 사용한
Swift 6 strict concurrency type-check를 통과했으며, 실제 production module에 대해서는 계획대로
`ScheduleEvaluator`, `RestrictionRuleValidator`, `RestrictionRuleValidationInput` 미구현 오류로
red 상태를 확인했다. `xcodebuild build-for-testing`은 앱 target에 실행 entry point가 아직 없어
linker 단계에서 실패했고 CoreSimulator service 경고도 계속 발생했다. `project.pbxproj` 문법과
`git diff --check`는 통과했으며, validation red 테스트는 T029 구현과 함께 해소됐다.
T026에서 `LocationPickerModelTests.swift`에 지도 이동, 현재 위치 바로가기, When In Use 권한 부족과
위치 조회 실패 시 pin 보존, 저장 장소 draft 생성·재사용, 확인·취소 상태를 작성했다.
`CurrentLocationProviderTests.swift`에는 When In Use 성공, denied·restricted·notDetermined 권한 흐름,
권한 요청 거절, 단발성 위치 실패 정규화를 작성했다. 두 파일과 test fake는 임시 계약 stub을 사용한
Swift 6 strict concurrency type-check를 통과했다. 실제 production module에서는 계획대로
`LocationPickerModel`, `SavedPlaceSnapshot`, `CurrentLocationProvider`, `CurrentLocationSession` 등
T030 대상 타입의 미구현 오류로 red 상태를 확인했다. 새 테스트의 `GetUpTests` target membership,
`project.pbxproj` 문법과 `git diff --check`를 확인했으며, red 상태는 T030 구현과 함께 해소됐다.
T027에서 `UserStory1RuleConfigurationUITests.swift`에 필수 입력 validation과 요일·저장 장소·앱
선택, 유효 규칙 저장 후 process 재실행 재로딩, 세 저장 규칙의 양방향 card swipe, 선택 card 편집 시
값 보존, 규칙 삭제 확인과 재실행 후 삭제 보존을 작성했다. 승인된 하이파이의 accessibility
identifier를 사용하고, 시스템 소유
`FamilyActivityPicker` 결과는 `--ui-test-family-picker-result` launch argument로 test seam에서만
주입하도록 계약했다. UI test source는 Swift 6 strict concurrency standalone type-check와
`xcodebuild build-for-testing`의 arm64·x86_64 compile을 통과했다. 전체 test build는 app entry point가
아직 없어 GetUp linker 단계에서 실패했고 CoreSimulator service도 사용할 수 없었으므로 UI assertion은
실행되지 않았다. 이는 T035~T037 UI·app 구현 전의 예상 red 상태다. `project.pbxproj` 문법과
`git diff --check`는 통과했다.
T028에서 `ScheduleEvaluator.swift`에 15분 최소 간격의 종료 시각 선택 여부, 선택 요일, 시작 포함·
종료 미포함, 자정 초과 구간의 시작 요일 귀속을 구현했다. 현지 시각 경계는 `Calendar.nextDate`의
`.nextTime` 정책을 사용해 존재하지 않는 시각을 다음 유효 시각으로 이동하고, 반복 시작은 첫 번째,
반복 종료는 두 번째 발생을 사용한다. `RestrictionStateMachine`의 기존 단순 시·분 판정을
`ScheduleEvaluator` 호출로 교체해 앱과 extension의 실제 평가 경로도 같은 DST 규칙을 사용하게 했다.
임시 로컬 Swift package에서 T025의 `ScheduleEvaluatorTests` 7개와 기존 상태 머신 회귀 테스트 10개,
총 17개가 모두 통과했다. 변경한 core source는 iOS 26 Simulator SDK, Swift 6 strict concurrency 및
warning-as-error 조건에서 type-check를 통과했고, `ScheduleEvaluator.swift`가 앱과 세 extension의
Sources phase에 각각 한 번 포함되는지 확인했다. `project.pbxproj` plist 문법과 `git diff --check`도
통과했다. 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지 미검증 상태다.
T029에서 `RestrictionRuleValidator.swift`에 빈 요일, 유효하지 않은 시·분, 같은 시작·종료,
15분 미만 구간, 저장 장소 누락·삭제, 좌표 누락·범위 초과·비유한 값, 지원하지 않는 반경 및 앱
token 누락 판정을 구현했다. 반경의 단일 source of truth로 `RadiusOption.allCases`를 사용하고
`RadiusOption`을 500m·1km·2km·3km·4km·5km 여섯 값으로 확장했다. 기존 T025 테스트에 좌표와
시·분 모델 범위 경계를 보강했으며, 임시 로컬 Swift package에서 validator 11개, 일정 평가 7개,
상태 머신 회귀 10개로 총 28개 테스트가 모두 통과했다. 변경한 core source는 iOS 26 Simulator SDK,
Swift 6 strict concurrency 및 warning-as-error 조건에서 type-check를 통과했고,
`RestrictionRuleValidator.swift`가 앱과 세 extension의 Sources phase에 각각 한 번 포함되는지
확인했다. `project.pbxproj` plist 문법과 `git diff --check`도 통과했다. 전체 Xcode test 실행은 app
entry point가 구현되는 T037 전까지 미검증 상태다.
T030에서 `SavedPlaceSnapshot`·`SavedPlaceDraft`, 지도 중심·핀 후보·저장 장소 재사용·확정·취소·안내
상태를 가진 `@MainActor @Observable LocationPickerModel`을 구현했다. 현재 위치 바로가기는
`CurrentLocationProvider`와 `CurrentLocationSession` 계약으로 분리하고, 승인 상태에서는 단 한 번의
위치를 요청하며 `.notDetermined`에서만 When In Use 권한을 요청한다. denied·restricted와 Core
Location 실패를 닫힌 오류로 정규화하고, 실제 `CLLocationManager` delegate callback은
`CoreLocationCurrentLocationSession`의 main actor 경계에서 continuation으로 변환했다. 임시 로컬
Swift package에서 위치 선택 모델 9개, 현재 위치 provider 6개와 기존 core 회귀 28개로 총 43개
테스트가 모두 통과했다. 변경 source는 iOS 26 Simulator SDK, Swift 6 strict concurrency 및
warning-as-error 조건에서 type-check를 통과했고, 두 새 source가 앱 target Sources phase에 각각 한
번 포함되는지 확인했다. 실제 시스템 권한 prompt와 `CLLocationManager` callback은 Simulator·실기기
통합 검증 전까지 미검증 상태이며, 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지
미검증 상태다. `project.pbxproj` plist 문법과 `git diff --check`는 통과했다.
T031에서 승인된 Figma `HF-FLOW-05`와 `location-picker-ui-contract.md`를 기준으로
`LocationPickerView.swift`를 구현했다. 실제 MapKit 지도에 중심 고정 `mappin.circle.fill`, 선택
반경의 실제 meter 값을 사용하는 `MapCircle`, 저장 장소 chip, 직접 입력 진입, 적용 CTA와 현재 위치
바로가기를 구성했다. 프로그램 방식의 카메라 이동과 사용자 지도 이동을 분리해 저장 장소 선택이
MapKit의 camera 종료 callback으로 해제되지 않도록 했고, 지도 이동·현재 위치 선택 시 기존 장소
이름을 비워 새 좌표가 이전 장소 이름으로 저장되지 않게 보강했다. 권한 부족·위치 확인 실패 안내는
지도 핀 직접 선택을 유지하며, 모든 주요 control에 VoiceOver label·value·hint와 UI test identifier를
부여했다. 반경 값은 `Binding<RadiusOption>`으로 받아 지도 원에 즉시 반영하며 실제 여섯 단계 slider는
계획된 T033의 `RadiusPicker.swift`에서 연결한다. 관련 core 회귀 43개 테스트가 모두 통과했고,
`LocationPickerView.swift`를 포함한 변경 source는 iOS 26 Simulator SDK, Swift 6 strict concurrency,
warning-as-error 조건에서 type-check를 통과했다. 앱 entry point가 T037까지 미구현이므로 실제 화면
render, 지도 gesture, 시스템 권한 prompt 및 UI test 실행은 아직 미검증 상태다. `project.pbxproj`
plist 문법과 `git diff --check`는 통과했다.
T032에서 `FamilyControlsAuthorizationSession`과 `FamilyActivitySelectionAdapter`를 구현했다.
`AuthorizationCenter.requestAuthorization(for: .individual)`만 요청하고 이미 승인된 경우에는 시스템
요청을 반복하지 않는다. denied 상태에서 사용자가 명시적으로 재시도할 수 있으며 시스템 반환 상태를
그대로 안내 계층에 전달한다. iOS 26.4에서 추가된 `approvedWithDataAccess`는 도메인의 `approved`로
정규화했다. `FamilyActivityPicker` 결과는 앱 이름·bundle identifier로 해석하지 않고 불투명
`FamilyActivitySelection` 그대로 교체·초기화하며, validation과 요약에 필요한 application token
개수만 제공한다. 승인 재사용·최초 요청·거부 후 재시도·선택 결과 보존·초기화 5개 테스트를 추가했고,
기존 회귀를 포함한 6개 suite의 48개 테스트가 모두 통과했다. 실제 iOS 26.5 SDK에서 production
module을 Swift 6 strict concurrency 및 warning-as-error 조건으로 compile했으며, adapter와 테스트의
target membership, `project.pbxproj` plist 문법과 `git diff --check`를 확인했다. 실제 Family Controls
승인 sheet와 `FamilyActivityPicker` 표시는 T035 연결 및 entitlement가 적용된 실기기 검증 전까지
미검증 상태다.
T033에서 승인된 Figma `HF-FLOW-01`·`HF-FLOW-02`·`HF-FLOW-03`·`HF-FLOW-05`를 기준으로
`TimeRangePicker`, `WeekdayPicker`, `RadiusPicker`를 구현했다. 시간 picker는 시·분·AM/PM을 독립된
wheel로 제공하고 분을 1분 단위로 선택하며, 종료 시각 변경은 `ScheduleEvaluator`를 사용해 시작
시각으로부터 15분 미만인 후보를 반영하지 않는다. 요일 chip은 44pt 최소 hit target과 선택 trait,
요일별 UI test identifier를 제공한다. 반경 slider는 `RadiusOption.allCases`의 500m·1km·2km·3km·
4km·5km 여섯 값에만 스냅되고 VoiceOver 조절값과 `locationPicker.radius` identifier를 제공하며,
기존 `LocationPickerView`에 연결해 반경 변경이 지도 원과 카메라에 즉시 반영되도록 했다. 승인된
accent `#F4D600`을 `AccentColor` asset에 등록했고, 12시간제의 자정·정오 변환과 0 채움 표시 테스트를
추가했다. 세 component와 관련 core source는 iOS 17 Simulator SDK, Swift 6 strict concurrency 및
warning-as-error 조건의 독립 type-check를 통과했다. 전체 `build-for-testing`은 앱·component·test
source compile과 asset compile을 통과한 뒤 아직 앱 entry point가 없어 기존 예상 상태인 `_main`
linker 오류로 종료됐다. 따라서 새 assertion의 실제 실행, 화면 render, wheel gesture 및 VoiceOver
동작은 T037의 앱 entry point 구현 후 검증해야 한다. T032에서 누락된
`FamilyActivitySelectionAdapterTests.swift`의 Xcode `Integration` group 경로도 바로잡았고,
`project.pbxproj` 문법, asset JSON 및 `git diff --check`를 확인했다.
T034에서 `RuleEditorDraft`와 `@MainActor @Observable RuleEditorModel`을 구현했다. 새 규칙은 주입 가능한
고유 ID와 `sourceRevision == nil`을 사용하고, 기존 규칙 편집은 ID·revision·생성 시각과 모든 입력을
보존해 다른 저장 규칙을 대체하지 않는다. 선택적인 규칙 이름은 앞뒤 공백을 제거한 뒤 빈 값이면
`nil`로 준비하며, 요일·시간·저장 장소·여섯 단계 반경·opaque `FamilyActivitySelection`을 하나의
draft로 유지한다. 저장 가능 여부는 별도 규칙을 복제하지 않고 `RestrictionRuleValidator` 결과로
계산한다. `LocationPickerCompletion`의 새 장소는 ID와 생성·수정 시각을 부여해 collection에 추가하고,
기존 장소는 ID 기준으로 갱신·재사용하며 취소 시 현재 draft를 보존한다. 새 규칙 필수 validation,
유효 draft, 기존 편집 값 보존, 새 장소 생성, 기존 장소 재사용, 취소, 삭제된 장소 참조, 규칙별 독립
ID를 검증하는 Swift Testing 8개를 추가했다. production 및 test source는 iOS 26 Simulator SDK,
Swift 6 strict concurrency와 warning-as-error compile을 통과했고, 동일 production source의 임시 host
harness 12개 assertion이 모두 통과했다. 전체 `build-for-testing`은 새 source compile 후 T037 전의
기존 예상 상태인 앱 entry point `_main` linker 오류로 종료되어 Xcode test suite 실행은 아직
미검증 상태다. `project.pbxproj` 문법과 `git diff --check`를 확인했다.
T035에서 승인된 Figma `HF-FLOW-01`·`HF-FLOW-10`·`HF-FLOW-11`을 기준으로
`RuleEditorView.swift`를 구현했다. Dark Focus의 편집 header, 시간 disclosure, 요일 chip, 장소·앱
조건 card와 하단 저장 CTA를 구성하고 필수 요일·장소·앱 validation을 화면에 연결했다. 시작·종료
시간은 기존 wheel sheet로, 장소는 `LocationPickerView` push와 재사용 가능한 장소 이름 입력 alert로
연결했다. 앱 선택은 개인용 Family Controls 승인 뒤 시스템 `FamilyActivityPicker`를 표시하고 opaque
selection을 model에 반영하며, UI test에서만 결과를 주입할 수 있는 seam을 제공한다. 저장은 T036의
service를 주입받는 async closure로 분리하고 중복 tap 방지, draft를 보존하는 저장 실패 card와 재시도
식별자를 구현했다. 주요 control과 validation에는 T027 UI test 계약의 accessibility identifier,
label, value, hint를 적용했다. `RuleEditorView.swift`와 관련 앱·테스트 source는 iOS 26 Simulator SDK의
arm64·x86_64에서 Swift 6 compile을 통과했다. 전체 `build-for-testing`은 source와 test compile 뒤
T037 전의 기존 예상 상태인 앱 entry point `_main` linker 오류로 종료되어 실제 화면 render, 시스템
Family Controls 승인·picker 및 UI test 실행은 아직 미검증 상태다. `project.pbxproj` 문법과
`git diff --check`를 확인했다.
T036에서 `RuleConfigurationService`와 collection repository 계약을 구현했다. 새 규칙과 대상 규칙의
revision, 전체 규칙 collection revision 및 저장 장소 collection revision을 저장마다 각각 증가시키고,
편집 시작 revision이 현재 값과 다른 stale write는 파일을 쓰기 전에 거부한다. 다른 규칙은 그대로
보존하며 새·수정 장소를 ID로 병합하고, 장소를 규칙보다 먼저 atomic write해 존재하지 않는 장소 참조를
방지한다. schema 1의 기존 `restriction-rule.json`은 좌표와 시각을 보존한 결정론적 규칙·장소
aggregate로 읽으며, 새 plural collection 파일이 생기면 이를 우선한다. 임시 Swift package에서
`RuleConfigurationServiceTests` 4개와 `SharedSnapshotRepositoryTests` 12개, 총 16개 테스트가 모두
통과했다. `xcodebuild build-for-testing`은 앱과 새 test source의 arm64·x86_64 compile을 통과한 뒤
T037 전의 기존 예상 상태인 앱 entry point `_main` linker 오류로 종료됐다. `project.pbxproj` 문법과
`git diff --check`를 확인했다.
T037에서 `GetUpApp` 실행 진입점과 `@MainActor @Observable AppModel`을 구현해 규칙·저장 장소
collection을 로딩하고, 오늘 선택 요일 또는 현재 활성인 자정 초과 규칙을 먼저 배치한 뒤 나머지를
DST 보정된 다음 시작 시점 순으로 정렬한다. 승인된 Dark Focus의 규칙 없음 화면과 시간·요일·장소·
반경·앱 개수·수정 행동을 하나로 묶은 swipeable card, page indicator, 새 규칙 CTA를 구현했다.
선택 card 편집은 ID·revision과 기존 값을 보존하고 저장 성공 뒤 collection을 다시 반영해 홈으로
복귀한다. UI test 전용 격리 저장소와 불투명 앱 선택 seam은 launch argument가 있을 때만 활성화한다.
사용자 피드백으로 누락을 확인한 규칙 삭제를 같은 편집 화면에 보완했다. 삭제 확인 후 대상 규칙만
제거하고 규칙 collection revision을 증가시키며, 다른 규칙과 재사용 가능한 저장 장소는 보존한다.
stale editor 삭제는 기록 전에 거부하고 `AppModel`의 비동기 삭제 guard가 거부하면 화면을 닫거나
저장소를 변경하지 않는다. 실제 활성 제한 판정은 계획된 T066에서 이 guard에 연결한다.
`build-for-testing`에서 앱 entry point를 포함한 앱·단위 테스트·UI 테스트 target의 arm64·x86_64
compile과 link가 모두 통과했다. 삭제 보완 후 iPhone 17 Pro iOS 26.5 Simulator에서 단위·저장소
85개 test case(동적 인자 포함 97회 실행)와 T027 UI test 5개가 실패·skip 없이 통과했다. Simulator가
실제 파일 보호 속성을 노출하지 않는 환경 차이는 writer option을 직접 검증하고 물리
기기에서 실제 속성을 확인하도록 기존 테스트를 보정했다. 실제 App Group, Family Controls picker,
지도 권한과 실기기 Dynamic Type·VoiceOver는 계획된 통합·마무리 task 전까지 미검증 상태다.
T038에서 기존 US1 Figma 파일의 `GetUp Focus` 변수·text style과 iOS 26 text button component를
재사용해 별도 wrapper `US2 / 제한 활성 + Restricted App Shield · T038 로우파이`를 작성했다.
`US2-LF-01`은 제한 앱 개수, 시간·위치 조건 충족 이유와 시간 종료·신뢰 가능한 위치 이탈이라는
자동 해제 조건을 표시한다. `US2-LF-02`는 정적 GetUp 아이콘, 제한 활성 제목, 자동 해제 설명과 단일
`앱 닫기` 행동만 제공하며 앱 이름·bundle identifier를 직접 표시하거나 우회·규칙 변경·GetUp 자동
실행을 약속하지 않는다. 조건 충족부터 제한 앱 종료까지의 4단계 흐름과 VoiceOver 순서, 색상 외 상태
표현 가설을 Figma와 `design/low-fidelity/US2-active-restriction.md`에 기록했다. 최종 자동 감사에서
35개 text node의 SF Pro 외 서체, 0폭·0높이 text, 임시 placeholder, shimmer, 화면 overflow와 실제
앱 식별 정보가 모두 0건이며 primary action instance가 `앱 닫기` 하나뿐임을 확인했다. 디자인·문서
작업이므로 code test는 실행하지 않았고, T039 사용자 검토 전까지 T040 하이파이를 시작하지 않는다.
T039 사용자 피드백에 따라 별도 `US2-LF-01` 화면을 기존 홈 카드의 제한 활성 상태로 교체하고,
`US2-LF-02` 제목과 설명에 저장 장소 `집`, 설정 반경 `1km`, 종료 시각 `09:00 AM`을 직접 표시했다.
Figma 재렌더링과 node 감사에서 LF-01 21개와 LF-02 5개 text node의 누락 font, 빈 text, placeholder,
육안상 overflow가 0건이고 shield 행동 instance가 `앱 닫기` 하나뿐임을 확인했다. iOS 26.5 SDK의
`ShieldConfiguration`과 `ShieldActionResponse`를 확인한 결과 shield 내부 임의 Map UI는 지원되지
않고 GetUp 앱 열기는 iOS 26.5 이상의 `openParentalControlsApp`과 secondary action·contract 변경이
필요하다. 이를 `BLK-007`로 기록했으며 결정 전까지 T039를 완료 처리하지 않는다. 디자인·문서
변경이므로 code test는 실행하지 않았다.
사용자가 BLK-007의 1안을 선택해 MVP shield는 모든 지원 버전에서 secondary action 없이 장소·반경·
종료 시각 문구와 primary `앱 닫기`만 제공하기로 확정했다. Figma의 계약·승인 주석,
`design/low-fidelity/US2-active-restriction.md`, `docs/BLOCKERS.md`와 `DEC-026`에 결정을 반영하고
T039를 완료했다. 향후 `오늘만 허용`과 인앱결제를 통한 일시 해제는 현재 범위에서 제외하고 별도
spec과 플랫폼·결제 정책 검토 대상으로 기록했다. 디자인·문서 변경이므로 code test는 실행하지
않았다.
T040에서 승인된 기존 홈 활성 상태, 기본 restricted-app shield와 Dynamic Type `AX5` 비교 상태를
하나의 Figma 하이파이 wrapper로 구성했다. `GetUp Focus` semantic color·spacing token, SF Pro와
iOS 26 Liquid Glass primary button instance를 재사용하고 장소·반경·종료 시각, 단일 `앱 닫기`,
VoiceOver 순서, Increase Contrast·Reduce Motion, 명암 계산과 T052·T053·T055 구현 인계를
`design/high-fidelity/US2-active-restriction.md`에 기록했다. 전체와 개별 frame 렌더링 및 50개 text
node 감사에서 누락 font, 빈 text, placeholder, shimmer, 화면 경계 overflow가 모두 0건이었고 행동
instance는 `Primary Action · 앱 닫기` 두 개뿐이었다. 디자인·문서 작업이므로 code test는 실행하지
않았으며 T041 사용자 승인 전에는 shield UI 구현을 시작하지 않는다.
T041에서 사용자가 기본·Dynamic Type AX5 restricted-app shield, 장소·반경·종료 시각 안내,
secondary action 없는 단일 `앱 닫기`, 접근성·명암·구현 인계를 최종 승인했다. Figma wrapper의 승인
주석과 `design/high-fidelity/US2-active-restriction.md`의 검토 기록·승인 상태를 갱신하고 T041을
완료했다. 디자인 승인 기록 작업이므로 code test는 실행하지 않았으며 T042부터 US2 선행 실패
테스트를 진행한다.
`tasks.md`의 87개 task가 연속 ID, 체크박스 및 파일 경로 형식 검증을 통과함.
T001 검증으로 `project.pbxproj` plist 문법, 공유 scheme XML 및 `xcodebuild -list -json`을 실행해
Debug/Release 구성, 6개 target과 6개 scheme 인식을 확인함. Simulator service와 기본 DerivedData
접근 경고가 있었으나 프로젝트 목록 검증 명령은 성공함. 아직 앱 source가 없어 build/test는
후속 task 완료 뒤 실행함. T002 검증으로 Xcode 26.6의 Swift 6.3.3 toolchain을 확인하고,
`project.pbxproj` plist 문법과 `xcodebuild -list -json`을 재검증했으며, 6개 target의 Debug build
settings에서 `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`,
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` 및 기대한 bundle identifier 상속 결과를 확인함. 로컬
Simulator service와 일부 provisioning profile 경고가 있었으나 build settings 검증은 성공함.
T003 검증으로 네 entitlements와 `project.pbxproj`의 plist 문법을 확인하고, Family Controls 값이
모두 `true`이며 App Group 항목이 공통 `GETUP_APP_GROUP_IDENTIFIER` build setting을 참조하는지
검증함. Debug·Release의 앱과 세 확장 build settings에서 각 `CODE_SIGN_ENTITLEMENTS` 경로와
`GETUP_APP_GROUP_IDENTIFIER = group.com.getup.GetUp` 상속을 확인함. 실제 개발·배포 서명 및
entitlement 승인은 T082와 실기기 검증 전까지 미검증 상태임.
T004 검증으로 앱과 세 extension `Info.plist`, `project.pbxproj`의 plist 문법을 확인하고 위치 권한
문구, `NSExtensionPointIdentifier`, `NSExtensionPrincipalClass` 값을 Xcode 26.6 템플릿과 대조함.
Debug·Release의 네 target에서 수동 `INFOPLIST_FILE` 경로와 version 상속을 확인했으며,
`UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers` 및 관련 build setting이 없음을 검증함.
principal class의 실제 로딩은 각 extension source 구현 후 build 및 실기기 테스트 전까지 미검증
상태임.
T005 검증으로 `GetUp.xctestplan` JSON과 공유 scheme XML 문법을 확인하고,
`GetUpTests` → `GetUpUITests` 순서 및 두 target의 `parallelizable = false`를 확인함.
`xcodebuild -showTestPlans`에서 공유 scheme이 `GetUp` test plan을 인식하는 것을 검증함. 아직 앱과
테스트 source가 없으므로 실제 test 실행 결과는 없으며, 최초 실행은 관련 source task 완료 뒤
수행해야 함.
T006 검증으로 세 UI 설계 문서가 존재하며 Figma node 링크, 화면 상태, 접근성, 검토 기록과 승인
게이트 항목을 포함하는지 확인함. 이 task는 문서 scaffold 작업이므로 실행할 code test는 없음.
실제 사용자 스토리 설계는 아직 작성·승인되지 않았으며 관련 UI 구현 전에 각 문서에서 별도로
검토해야 함.
T007 검증으로 네 `PrivacyInfo.xcprivacy`의 plist 문법과 root key type을 확인하고, 모든 manifest가
`NSPrivacyAccessedAPICategoryUserDefaults`의 `1C8F.1`, 빈 `NSPrivacyCollectedDataTypes`,
`NSPrivacyTracking = false`, 빈 `NSPrivacyTrackingDomains`를 선언하는지 확인함. `project.pbxproj`
문법과 각 manifest의 target별 Resources phase membership을 확인하고 `xcodebuild -list -json`으로
프로젝트 인식을 재검증함. Simulator service와 로컬 provisioning profile 경고가 있었지만 명령은
성공함. 실제 archive privacy report와 App Store Connect 검증은 배포 준비 전까지 미검증 상태임.
T008 검증으로 asset catalog와 string catalog JSON 문법, `AppIcon`의 기본·Dark·Tinted slot,
비어 있는 `AccentColor`, 한국어 `sourceLanguage` 및 빈 문자열 목록을 확인함. 두 resource의 앱 target
Resources phase membership과 Debug·Release의 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`,
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`를 확인하고 `xcodebuild -list -json`으로
프로젝트 인식을 재검증함. `actool`과 `xcstringstool`이 빈 scaffold를 오류 없이 처리함. Simulator
service와 로컬 provisioning profile 경고가 있었지만 관련 명령은 성공함. 실제 색상·아이콘·문구는
사용자 스토리별 하이파이 승인 뒤 추가하며, 현재 빈 app icon과 accent color는 출시용 asset으로
검증되지 않은 상태임.
T009 검증으로 `SharedIdentifiers.swift`를 Swift 6 strict concurrency 설정에서 type-check하고,
두 공유 파일명과 store·activity name 규칙을 확인함. 네 `Info.plist`의
`GetUpAppGroupIdentifier = $(GETUP_APP_GROUP_IDENTIFIER)` 선언과 plist 문법을 확인하고, 같은 source가
앱과 세 extension Sources phase에 각각 한 번 포함되는지 검증함. 실제 App Group container 접근과
typed `ManagedSettingsStore.Name`·`DeviceActivityName` 변환은 관련 adapter 구현 전까지 미검증
상태임. `xcodebuild -showBuildSettings`는 Simulator service와 로컬 provisioning profile 경고를
출력했지만 성공했으며 공통 App Group과 Swift 6 strict concurrency 설정을 확인함.
T010 검증으로 `RestrictionRuleModels.swift`를 iOS Simulator SDK와 Swift 6 strict concurrency,
app-extension-only 설정에서 warning을 error로 처리해 type-check함. 모든 모델의 Codable·Equatable
및 필요한 Hashable·Sendable conformance, 월요일부터 일요일까지의 안정적인 raw value,
500m·1,000m raw value와 `radiusMeters` CodingKey를 확인하고 같은 source가 앱과 세 extension에 한
번씩 포함되는지 검증함. 시간·좌표·revision·요일·앱 선택의 유효성 및 JSON round-trip 자동 테스트는
계획된 T025·T017에서 수행하기 전까지 미검증 상태임.
T011 검증으로 `RuntimeStateModels.swift`를 iOS Simulator SDK와 Swift 6 strict concurrency,
app-extension-only 설정에서 warning을 error로 처리해 type-check함. 위치 상태·관측 source·권한 상태의
stable raw value, 위치 snapshot schema version 및 필드, 제한 표시 상태의 associated value를 확인하고
같은 source가 앱과 세 extension에 한 번씩 포함되는지 검증함. 권한·시간·위치 조합의 상태 전이와 JSON
round-trip 자동 테스트는 계획된 T015·T017에서 수행하기 전까지 미검증 상태임.
T012 검증으로 기존 모델과 `PlatformContracts.swift`를 iOS Simulator SDK와 Swift 6 strict
concurrency, app-extension-only 설정에서 warning을 error로 처리해 type-check함. 일곱 platform
contract의 `Sendable` 경계, repository CRUD, 일정·위치 lifecycle, 권한 snapshot 조회 및 제한 적용
상태의 원자적 조회 signature를 확인하고 같은 source가 앱과 세 extension에 한 번씩 포함되는지
검증함. 실제 adapter의 protocol 준수와 오류·취소 동작은 T018·T046·T048·T049·T075 구현 전까지
미검증 상태임.
T013 검증으로 기존 core 모델·contract와 `RestrictionEvaluationModels.swift`를 iOS Simulator SDK,
Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해 type-check함.
평가 입력이 전역 상태 대신 규칙·시각·달력·시간대·위치·권한·현재 제한 상태를 명시적으로 받으며,
결정이 presentation·desired restriction·effect·reason을 모두 포함하는지 확인함. 전체 상태 행렬과
우선순위·idempotency 동작은 계획된 T015·T016 전까지 미검증 상태임.
T014 검증으로 기존 core source를 `GetUp` testable module로 compile한 뒤 `TestFixtures.swift`를
iOS Simulator SDK와 Swift 6 strict concurrency에서 warning을 error로 처리해 type-check함. 고정
clock의 `Clock` 준수, UTC Gregorian calendar, factory override와 test target Sources membership을
확인함. fixture는 테스트 보조 코드이므로 독립 assertion은 없으며 실제 상태 행렬 실행은 T015에서
시작함. 기본 `FamilyActivitySelection`은 opaque token을 위조하지 않은 빈 선택으로, 앱 선택 유효성은
T025 validation 테스트에서 별도 검증할 예정임.
T015에서 시간 2상태 × 위치 3상태 × 권한 2상태 × 현재 shield 2상태의 24개 조합과 시간 종료
우선순위, 위치 `unavailable` 보존, rule revision 불일치, apply/remove idempotency를 Swift Testing으로
작성함. 구현 전 임시 compile stub을 사용하면 테스트 source가 Swift 6 strict concurrency에서
type-check되었고, stub 없이 검사하면 `RestrictionStateMachine`을 찾을 수 없어 의도한 red 상태가
발생했음. 이후 T016 구현과 실행 검증을 통과해 T015를 함께 완료 처리함.
T016 검증으로 `RestrictionStateMachine.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK, Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해
type-check함. 실제 구현을 import한 T015 Swift Testing source가 compile 검사를 통과했으며, 동일 구현을
링크한 자동 실행 harness에서 24개 상태 조합, 시간 종료 우선순위, 위치 `unavailable`·revision 불일치
보존, apply/remove idempotency, 필수 권한 결합과 자정 초과 일정의 시작 요일 귀속 assertion을 모두
통과함. `BackgroundRefreshStatus`는 진단 정보로 유지하고 신규 shield 적용의 필수 권한 집합에서는
제외함. 전체 Xcode test 실행은 app entry point가 구현되는 T037 전까지 실행할 수 없어 미검증 상태임.
T017에서 규칙·위치 JSON의 별도 파일 round-trip과 `completeUntilFirstUserAuthentication` 보호,
파일 없음의 `nil` 처리, 두 파일의 손상 JSON·미지원 schema, rule revision 불일치, 두 파일의 atomic
write 실패 시 이전 snapshot 보존을 Swift Testing으로 작성함. 구현 전 임시 compile stub을 포함하면
테스트 source가 iOS 17 Simulator SDK와 Swift 6 strict concurrency에서 type-check되었고, 실제
source만 사용한 검사에서는 `SharedSnapshotRepository`, `SharedSnapshotRepositoryError`,
`SnapshotFileWriting`을 찾을 수 없어 의도한 red 상태가 발생했음. 이후 T018 구현과 실행 검증을
통과해 T017을 함께 완료 처리함.
T018 검증으로 `SharedSnapshotRepository.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK, Swift 6 strict concurrency 및 app-extension-only 설정에서 warning을 error로 처리해
type-check함. 실제 T017 Swift Testing suite를 macOS host에서 같은 Foundation 구현과 불투명
`FamilyActivitySelection` compile stub으로 실행해 1개 suite의 10개 테스트가 모두 통과함. JSON은
ISO-8601 날짜와 정렬된 key로 encoding하고, schema header 선검사, 현재 rule revision 교차 검사,
atomic write와 `completeUntilFirstUserAuthentication` 보호, 오류 분류 및 삭제의 멱등성을 구현함.
기존 상태 머신 회귀 테스트까지 합친 2개 suite의 20개 테스트도 모두 통과함. 전체 Xcode test 실행은
app entry point가 구현되는 T037 전까지 실행할 수 없어 미검증 상태임.
T019 검증으로 `DependencyContainer.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK 및 macOS host에서 Swift 6 strict concurrency warning을 error로 처리해 type-check함.
실행 harness에서 한 container의 규칙·위치 계약이 동일 `SharedSnapshotRepository` actor를 노출하는지,
앱과 extension을 모사한 별도 container 인스턴스가 같은 규칙·위치 파일을 읽는지 확인함. actor 밖의
`FileManager` 인스턴스를 저장소로 전송하지 않도록 파일 작업은 actor 내부에서 생성한 인스턴스만
사용하게 조정했으며 기존 2개 suite의 20개 회귀 테스트도 모두 통과함. 실제
`DependencyContainer.live()`의 App Group container URL 획득은 entitlement가 적용된 서명 target
실행 전까지 미검증 상태임.
T020 검증으로 `DiagnosticsLogger.swift`를 앱과 세 extension Sources phase에 포함하고 iOS 17
Simulator SDK와 macOS host에서 Swift 6 strict concurrency warning을 error로 처리해 type-check함.
저장소 오류 7종과 App Group 조립 오류 2종을 안정적인 code로 분류하고, file name·schema 값·revision
값과 알 수 없는 오류 설명을 event에서 폐기하도록 Swift Testing 3개 테스트로 검증함. 좌표와 불투명
앱 token을 포함한 임의 오류 문자열이 최종 `logMessage`에 포함되지 않음을 확인했으며, 기존 상태
머신·저장소 회귀를 합친 3개 suite의 23개 테스트가 모두 통과함. 실제 unified logging 수집 결과의
통합 개인정보 검사는 T081에서 수행하며, 전체 Xcode test 실행은 app entry point가 구현되는 T037
전까지 실행할 수 없어 미검증 상태임. T020 완료로 Phase 2 공통 기반을 완료 처리함.
iOS 26 최소 지원 변경으로 `Configuration/Base.xcconfig`의
`IPHONEOS_DEPLOYMENT_TARGET = 26.0`을 앱·세 extension·두 테스트 target이 Debug 구성에서 모두
상속하는지 `xcodebuild -showBuildSettings`로 확인함. `project.pbxproj` plist 문법을 재검증하고,
공통 production source를 `arm64-apple-ios26.0-simulator`, Swift 6 strict concurrency 및 warning-as-error
조건으로 type-check함. 첫 type-check는 오래된 입력 경로, 두 번째는 sandbox의 기본 module cache
쓰기 제한 때문에 실패했으며, 실제 source와 writable 임시 module cache를 지정한 최종 검사는
통과함. CoreSimulatorService 및 로컬 provisioning profile 경고는 build setting 출력에 영향을
주지 않았으며 실제 iOS 26 Simulator 실행·실기기 검증은 관련 app entry point와 UI 구현 이후 수행함.
T021 검증으로 Figma의 `US1 / 규칙 설정 흐름` section에 iPhone 393×852 기준 7개 frame을 작성하고,
직접 시간·자정 초과·15분 미만 오류·지도 핀·현재 위치 권한 부족·시스템 앱 선택·저장 실패 상태를
각각 확인함. 모든 화면이 Apple `iOS and iPadOS 26` 공식 library component와 `SF Pro`만 사용하는지,
실제 좌표·주소·app token을 포함하지 않는지, frame 직접 링크와 접근성 가설이 설계 문서에 기록됐는지
검증함. 이 task는 디자인·문서 작업이므로 code test는 실행하지 않았으며, 로우파이는 아직 사용자
승인 전이라 T022 검토와 T023 하이파이 작업이 남아 있음.
T022 진행 중 알람·집중 앱 7개 제품의 행동 유도 방식과 앱 이름 후보를 조사해
`design/research/alarm-focus-app-concept.md`에 정리함. Figma에 침대에서 문까지(A), 문턱(B), 출발
티켓(C) 세 방향의 onboarding·home 6개 frame을 추가함. 각 home은 오늘 또는 다음날의 요일·시간·
기준 위치·반경·제한 앱 요약, 규칙 수정 및 새 규칙 진입을 포함함. 구조 감사에서 6개 frame의
placeholder가 모두 제거됐고, 사용 font는 `SF Pro`뿐이며 실제 좌표·주소·app token과 frame overflow가
없음을 확인한 뒤 각 frame screenshot을 개별 검토함. 이 작업은 디자인·문서 변경이라 code test는
실행하지 않았으며, T022 완료와 하이파이 시작은 사용자 방향 선택·승인 전까지 보류함.
사용자가 직접 제작한 D안은 변경하지 않고 Figma에 별도의 `D안 보완 / 행동 명확화` 비교 영역을
추가함. onboarding, 규칙 없음, 오늘 규칙, 다음날 규칙 4개 frame에 오늘·다음날 맥락, 위치 이동과
앱 사용 가능 조건, 시간·위치 해제 조건, 제한 앱 요약, 규칙 수정 진입점을 반영함. 개별 frame과
전체 비교 screenshot에서 텍스트 잘림·겹침을 수정했고, 기존 D안 node `15:346` 보존 및 보완안의
모든 텍스트가 `SF Pro` 계열만 사용하는지 확인함. 디자인·문서 작업이므로 code test는 실행하지
않았으며 당시 T022는 사용자 승인 전이라 진행 중으로 유지함.
2026-08-23 추가 피드백에 따라 D안 home의 시간을 `06:00 AM` 형식으로 통일하고 `AM`/`PM` 크기를
시간 숫자보다 작게 조정했다. 규칙 화면은 시간 프리셋을 제거하고 직접 시작·종료 시각만 제공하며,
15분 미만 종료 시각을 비활성화한 DatePicker 상태를 추가했다. `프리셋 이름`은 `규칙 이름`으로,
위치 설정은 재사용 가능한 `집`·`회사`·`직접 입력` 장소와 여섯 단계 반경 slider로 변경했다.
home·규칙·장소·권한·키보드·DatePicker frame을 개별 screenshot으로 검수했고 이전 용어가 남지
않았음을 확인했다. Apple 시스템 keyboard component의 `SF Compact`를 제외한 제품 UI 텍스트는
`SF Pro` 계열을 유지한다. 이번 변경은 Figma와 명세·계획 문서 작업이므로 code test는 실행하지
않았고 `git diff --check`를 통과했다. 이 검수 시점에는 T022를 사용자 승인 전 진행 중으로 유지했다.
2026-08-23 사용자가 직접 수정해 `D 보완` frame에 정리한 안을 최종 로우파이로 승인했다.
`design/low-fidelity/US1-rule-configuration.md`에 승인자·승인일·미해결 항목 없음 상태를 기록하고
T022를 완료 처리했다. 승인 기록만 변경했으므로 code test는 실행하지 않았으며, 사용자의 별도
지시 전까지 T023 또는 다른 후속 작업을 시작하지 않는다.
T023 검증으로 승인된 `D 보완` 로우파이를 보존한 별도 Figma wrapper
`US1 / 하이파이 T023 · 검토용`에 iPhone 393×852 기준 9개 상태를 작성했다. 입력 전·유효 입력
Light, 유효 입력 Dark, 지도 핀·저장 장소, 현재 위치 권한 부족, 장소 이름 직접 입력, 15분 제한
DatePicker, 시스템 앱 선택 경계, 저장 실패·draft 유지 상태를 포함하고 Dynamic Type·VoiceOver·
44×44pt touch target·Reduce Motion 인계 규격을 추가했다. Apple `iOS and iPadOS 26` library의
290개 component instance와 431개 variable 연결 node를 사용했으며, 최종 자동 감사에서 313개
text의 허용되지 않은 font family, 0폭·0높이 text, 임시 placeholder 문구와 shimmer가 모두 0건임을
확인했다. 제품 UI는 `SF Pro` 계열을 사용하고 Apple 시스템 keyboard의 `SF Compact Rounded`만
예외로 확인했다. 권한 오류 본문은 `#B42518`로 조정해 흰 배경에서 6.52:1 대비를 확보했다.
`design/high-fidelity/US1-rule-configuration.md`에 색상·서체·간격·component 상태·문구·접근성·
플랫폼 제약과 구현 인계를 기록하고 `git diff --check`를 통과했다. 디자인·문서 작업이므로 code
test는 실행하지 않았으며, SwiftUI 구현은 T024 사용자 승인 전까지 시작하지 않는다.
2026-08-23 T024 검토를 위해 기존 T023 wrapper를 보존하고 별도 Figma wrapper
`US1 / 하이파이 후보 3안 · T024 검토`에 같은 규칙 데이터를 사용한 `A · Native Calm`,
`B · Dark Focus`, `C · Warm Behavioral` 대표 화면과 비교 카드를 작성했다. 최종 렌더에서 세
화면이 모두 393×852이고 화면 밖으로 벗어난 node가 없음을 확인했다. 자동 감사에서 83개 text의
허용되지 않은 font family와 0폭·0높이 text가 모두 0건이며 shimmer·gradient도 0건이었다.
디자인·문서 작업이므로 code test는 실행하지 않았고, T024는 사용자 방향 선택과 최종 구현 승인 전
상태이므로 완료 처리하지 않았다.
2026-08-23 사용자가 후보 B를 선택해 기존 T023과 후보 비교 보드를 보존하고 별도 Figma wrapper
`US1 / B Dark Focus 전면 적용 · T024 검토`를 작성했다. 규칙 편집, 지도 핀·권한·직접 입력,
DatePicker·시스템 앱 선택·저장 실패의 9개 393×852 화면과 접근성 인계 패널에 `#08090B` 배경,
`#15171B`·`#202329` surface, `#F4D600` accent, 20pt 주요 시간 위계를 적용했다. 최종 자동 감사에서
386개 text의 허용되지 않은 font family, 0폭·0높이 text, 화면 경계 밖 text와 placeholder가 모두
0건이었다. 시스템 keyboard의 `SF Compact`·`SF Compact Rounded`는 시스템 소유 예외로 유지했다.
디자인·문서 작업이므로 code test는 실행하지 않았고 `git diff --check`를 통과했다.
T024는 B 전면 적용본의 사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자 피드백으로 첫 B 적용본이 기존 form layout의 리스킨에 그쳐 선택한 B 후보의 UI
구조를 반영하지 못했음을 확인했다. 첨부 screenshot을 시각 source of truth로 지정하고 iOS 26
component를 제외한 `US1 / Dark Focus 재설계 · 첨부 기준` wrapper를 새로 작성했다. GetUp Focus
Primitives·Semantic·Layout collection 3개, variable 30개와 text style 7개를 만들고 9개 393×852
화면을 `editorial header → large focus card → circular selection → condition card → bottom CTA`
구조로 처음부터 다시 구성했다. 최종 자동 감사에서 233개 text의 font 오류, 0폭·0높이 text,
화면 경계 밖 text, placeholder, 이름 없는 node 및 의도하지 않은 hardcoded fill이 모두 0건이었다.
디자인·문서 작업이므로 code test는 실행하지 않았으며 T024는 재설계본의 사용자 최종 확인과 구현
승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자 피드백에 따라 `US1 / Dark Focus 논리 플로우 · T024 재검토` wrapper를 추가했다.
규칙 작성 화면의 `START`·`END` 행을 각각 명확한 편집 진입점으로 만들고 시작·종료 선택 화면과 모든
요약·오류 상태를 24시간제로 통일했다. 장소 설정은 화면 절반 이상의 큰 지도, 중심 핀, 실제 반경 원,
반경 slider를 함께 표시하며 D안의 `집`·`회사`·`직접 입력` 진입을 유지했다. `직접 입력`은 선택한
좌표·반경을 보존한 장소 이름 화면으로 이어진다. 앱 선택, 네 조건 최종 검토, draft를 보존하는 저장
실패까지 총 11개 393×852 화면과 사용자 흐름 규칙 패널을 작성했다. 자동 점검에서 251개 text의 실제
AM/PM 표기, 임시 placeholder, 부모 frame 밖 overflow가 모두 0건이었다. 디자인·문서 작업이므로 code
test는 실행하지 않았으며 T024는 사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자가 직접 다듬은 Figma 상태를 기준으로 기존 변경을 보존하고 시작·종료 시각 화면만
시·분·AM/PM 세 열 wheel로 교체했다. 분 열은 `58`·`59`·`00`·`01`·`02`처럼 1분 단위 이동을
명시하고 최소 15분 유효성 안내를 유지했다. 규칙·홈·요약 시간 표기는 `06:00 AM` 형식으로 통일했다.
승인된 D 보완 홈 정보 구조를 Dark Focus에 맞춰 `규칙 없음`, `오늘 규칙`, `다음 예정` 3개
393×852 화면으로 추가했으며 오늘 또는 다음날, 시간, 위치·반경, 제한 앱, 규칙 수정과 새 규칙 진입을
포함했다. 최종 감사에서 전체 13개 화면의 임시 placeholder와 SF Pro 외 제품 font가 0건임을
확인했다. 디자인·명세·결정 문서 작업이므로 code test는 실행하지 않았고 T024는 사용자 최종 확인과
구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 홈 규칙의 시간과 조건이 두 card로 분리돼 서로 다른 정보처럼 보인다는 피드백을 반영했다.
`HOME-02`와 `HOME-03`에서 시간, 위치·반경, 제한 앱과 규칙 수정 행동을 하나의 353×456
`Swipeable rule card` 배경과 외곽선 안에 통합했다. card 상단에 `RULE 1 OF 3` 또는
`RULE 2 OF 3`, 하단에 page indicator와 좌우 swipe 안내를 배치해 한 page가 한 규칙임을 명확히
했다. 두 화면의 외곽 container, 투명 내부 section, swipe 안내, text overflow와 SF Pro font를
감사해 오류가 없음을 확인했다. 디자인·명세 문서 작업이므로 code test는 실행하지 않았고 T024는
사용자 최종 확인과 구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 여러 규칙이 저장되면 모두 적용한다는 사용자 결정을 반영했다. 홈의 두 규칙 화면을
`모든 규칙 1/3`, `모든 규칙 2/3` 상태로 정리하고 `RULE n OF 3`과 page indicator로 전체 규칙 탐색을 표시했다.
홈 pager에는 저장된 모든 유효 규칙을 표시하며 오늘 적용 규칙을 먼저 두고 나머지는 다음 적용 시점
순으로 정렬한다. 현재 보이는 card와 무관하게 각 규칙은 독립적으로 동작하고 동시 충족 시 제한 앱
합집합을 적용한다. `FR-034`·`FR-035`·`FR-043`을 수정하고 `FR-044`·`DEC-021` 및 관련 task를
추가·갱신했다. 디자인·명세 문서 작업이므로 code test는 실행하지 않았고 T024는 사용자 최종 확인과
구현 승인 전이므로 완료 처리하지 않았다.
2026-08-23 사용자가 직접 다듬은 최종 Figma를 다시 감사했다. 13개 제품 화면에서 SF Pro 외 서체,
임시 문구와 text overflow가 모두 0건이었고, 시작·종료 시각의 시·분·AM/PM wheel과 1분 단위 분 전환,
큰 지도와 반경 원, 장소 이름 직접 입력 진입, 하나로 묶인 swipe card 및 모든 규칙 pager가 유지됨을
확인했다. 사용자가 이 상태를 최종 승인해 `T024`를 완료 처리했다. 이번 작업은 디자인·문서 검수이므로
code test는 실행하지 않았으며 다음 작업은 `T025`의 실패 테스트 작성이다.
