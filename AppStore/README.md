# App Store Connect 제출 자료

## 스크린샷 규격

- 기기: iPhone 14 Plus Simulator, iOS 26.5
- 방향: 세로
- 제출본: `.jpg`, 1284×2778, 알파 채널 없음
- 원본: 같은 폴더의 `.png`, 1284×2778, Simulator 원본 캡처
- 상태 막대: 9:41, Wi-Fi 연결, 배터리 100%

Apple 규격상 6.5인치 iPhone 제출 화면은 1284×2778 또는 1242×2688 세로 이미지를 허용하며, 한 언어·기기 크기당 1~10장을 올릴 수 있다. PNG 원본은 알파 채널이 있으므로 App Store Connect에는 `.jpg` 제출본을 사용한다.

## 권장 업로드 순서 — 한국어

1. `screenshots/ko/02-active-rule.jpg` — 활성 규칙과 자동 해제 조건
2. `screenshots/ko/03-rule-editor.jpg` — 시간·요일·장소·앱을 한 화면에서 설정
3. `screenshots/ko/04-location-picker.jpg` — 지도와 저장 장소, 반경 선택
4. `screenshots/ko/06-time-picker.jpg` — 직관적인 시작 시각 설정
5. `screenshots/ko/01-home-rules.jpg` — 여러 집중 규칙 관리
6. `screenshots/ko/05-permission-overview.jpg` — 자동화를 위한 권한 안내

## 권장 업로드 순서 — 영어

1. `screenshots/en/01-active-rule.jpg` — Active rule and automatic release condition
2. `screenshots/en/02-rule-editor.jpg` — Configure time, days, place, and apps
3. `screenshots/en/03-location-picker.jpg` — Select a saved place and radius on the map
4. `screenshots/en/05-time-picker.jpg` — Choose a start time
5. `screenshots/en/04-permission-overview.jpg` — Permission guidance for automation

## Shield 캡처

실제 restricted-app Shield는 Family Controls에서 선택한 불투명 application token과 배포 entitlement가 적용된 실기기에서 iOS가 표시하는 system-owned 화면이다. iPhone 14 Plus Simulator의 UI test probe는 실제 Shield가 아니므로 App Store 제출 이미지로 포함하지 않았다. 실기기에서 Shield를 띄운 뒤 같은 언어별로 캡처하면 선택 항목의 마지막 이미지로 추가한다.

## 공식 참고

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
- https://developer.apple.com/app-store/product-page/
