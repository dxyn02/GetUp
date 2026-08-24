# Contract: Restricted App Shield

## Trigger

GetUp의 named Managed Settings store가 선택 앱에 shield를 적용한 상태에서 사용자가 해당 앱을
열려고 할 때 시스템이 이 화면을 표시한다.

## Content

| Element | Required behavior |
|---------|-------------------|
| Icon | GetUp 제한 상태를 식별할 수 있는 정적 아이콘 |
| Title | 현재 앱 사용 제한이 활성화되었음을 명확히 알림 |
| Subtitle | 시간과 위치 조건 때문에 제한 중이며 조건 종료 시 자동 해제됨을 안내 |
| Primary button | 제한 앱을 닫음 |
| Secondary button | 제공하지 않음 |

대상 앱에 적용된 활성 규칙이 하나이면 저장 장소·반경·종료 시각을 모두 표시한다. 두 개 이상이면
규칙 수와 각 규칙의 위치 또는 시간이 모두 끝나야 한다는 짧은 요약을 표시하며 개별 조건은
나열하지 않는다. snapshot 또는 app token을 읽지 못하면 제한 활성 사실과 자동 종료 조건만 담은
일반 문구를 사용한다.

## Interaction Rules

- 제한 해제 또는 규칙 변경 버튼을 shield에 제공하지 않는다.
- GetUp 앱을 자동 실행한다고 약속하지 않는다.
- primary action은 제한 앱 닫기로만 응답한다.
- 개인 사용자가 시스템 설정에서 권한을 해제하거나 GetUp을 삭제할 수 있다는 플랫폼 한계를
  앱 내부 권한 안내에서 설명하되 shield에 장황하게 노출하지 않는다.
- VoiceOver가 제목, 설명, 버튼을 의미 있는 순서로 읽을 수 있어야 한다.
- 시스템 글자 크기와 명암 설정에서도 핵심 안내가 잘리거나 색상만으로 전달되지 않아야 한다.
- 다중 규칙 요약과 fallback에는 장소·좌표·앱 식별 정보 또는 token을 포함하지 않는다.

## Acceptance Cases

- 제한 대상 앱에는 shield가 표시되고 비대상 앱에는 표시되지 않는다.
- 버튼을 누르면 제한 앱이 닫히며 사용 권한이 부여되지 않는다.
- 앱 이름이나 bundle identifier를 GetUp이 직접 해석하거나 표시하지 않는다.
- 제한 해제 뒤 같은 앱을 열면 GetUp shield가 더 이상 표시되지 않는다.
