# 알람·집중 앱 리서치와 GetUp 컨셉 방향

**작성일**: 2026-08-21  
**관련 작업**: `T022`  
**목적**: onboarding과 home 로우파이 후보를 만들기 위한 제품 메커니즘·브랜드 소재 조사

## 조사 요약

| 제품 | 사용자를 움직이는 방식 | GetUp에 참고할 점 | 그대로 따르지 않을 점 |
|---|---|---|---|
| [Alarmy](https://alar.my/en) | 수학·사진 촬영 같은 mission을 끝내야 알람을 끌 수 있음 | 의지만 요구하지 않고 구체적 행동으로 상태를 바꿈 | 별도 과제 수행보다 실제 집 밖 이동이 GetUp의 핵심임 |
| [Sleep Cycle](https://sleepcycle.com/the-app/smart-alarm) | 가벼운 수면 단계에 맞춰 부드럽게 깨움 | 취침·기상 맥락을 안심되는 tone으로 설명 | 수면 측정과 분석은 현재 범위가 아님 |
| [one sec](https://one-sec.app/) | 앱을 열기 전에 잠깐 멈추고 의도를 확인하게 함 | 차단 화면은 훈계보다 자동 행동을 끊는 짧은 마찰이어야 함 | 사용자가 매번 선택해 우회하는 흐름은 위치 기반 목표와 다름 |
| [Brick](https://getbrick.com/) | 떨어진 물리 장치에 가야 앱 차단을 해제할 수 있음 | 물리적 거리 자체를 commitment device로 사용 | 별도 hardware 없이 기준 위치 반경을 사용함 |
| [Opal](https://help.opalapp.com/article/how-to-use-schedules) | 요일·시간·앱을 규칙으로 만들고 예정된 focus를 자동 실행 | 홈에서 다음 규칙의 시간과 앱을 즉시 확인하게 함 | score·통계보다 오늘 해야 할 행동을 먼저 보여 줌 |
| [Jomo](https://help.jomo.so/en/article/how-to-start-with-jomo-mseknq/) | 여러 반복 rule과 block mode를 구성함 | 여러 독립 규칙의 생성·편집 구조를 참고 | 설정 종류를 늘려 onboarding을 복잡하게 만들지 않음 |
| [AppBlock](https://appblock.app/ios/) | 시간 또는 위치에 따라 앱을 자동 차단함 | GetUp과 가장 가까운 조건 모델이므로 권한·신뢰성 안내가 중요함 | 일반 생산성 profile보다 침대·문·외출 상황에 집중함 |

## 발견한 패턴

1. 강한 알람 앱은 설명보다 `사진 촬영`, `계산`, `걷기`처럼 끝낼 수 있는 행동을 요구한다.
2. 집중 앱은 차단 자체보다 차단이 시작될 시간과 대상 앱을 사용자가 예측할 수 있게 만든다.
3. 우회가 어려운 제품은 software 안에서 선택지를 늘리기보다 물리적 거리를 마찰로 사용한다.
4. GetUp의 차별점은 “앱을 덜 쓰기”가 아니라 `침대 → 문 → 반경 밖`의 공간 전환이다.
5. 홈은 dashboard보다 오늘 또는 다음 규칙의 행동 지시서에 가까워야 한다.

## 컨셉 원칙

- 주인공: screen time 수치가 아니라 사용자가 넘어야 할 `문턱`
- 핵심 은유: 침대는 현재 상태, 문은 전환, 바깥은 앱이 다시 열리는 결과
- 정보 우선순위: 오늘/내일 → 시간 → 나가야 할 거리 → 제한 앱 → 수정
- 문구 tone: 비난하거나 훈계하지 않고 짧고 단호하게 행동을 제안
- 시각 전달: 침대·문·걷기 symbol과 거리 변화만으로도 목적을 이해할 수 있어야 함
- 행동: 홈의 primary action은 `새 규칙`, 예정 카드의 secondary action은 `규칙 수정`

## 앱 이름 후보 평가

| 후보 | 장점 | 위험 | 현재 평가 |
|---|---|---|---|
| `Get Up` | 기상 문제를 즉시 이해하고 침대 소재와 잘 맞음 | 같은 이름의 challenge alarm과 `GetUp Alarm`이 App Store에 이미 있어 검색·차별화가 어려움 | 아침 중심 컨셉에 적합하지만 최종 이름으로는 주의 |
| `Go Out` | 부드럽고 취침·외출 모두 “다음 행동”으로 연결 가능 | 외출·소셜 서비스 이름과 겹치기 쉽고 차단 앱이라는 의미는 약함 | 친근한 tone 후보 |
| `GOUT` | 짧고 graphic wordmark로 쓰기 쉬움 | 영어권에서 질환 `gout`로 먼저 읽혀 의미·검색성이 크게 어긋남 | 사용하지 않는 것을 권장 |
| `GET OUT` | 문과 위치 반경을 가장 강하게 연결하고 shield에서도 즉시 읽힘 | 명령조가 강하고 기존 `Get Out` 서비스와 이름 충돌 가능성이 있음 | 컨셉 테스트용 working name 1순위 |

`Get Up`은 실제 challenge alarm 앱과 [GetUp Alarm](https://getupalarm.com/)이 이미 같은 문제를
다루고 있고, `Go Out`도 [동명 활동 서비스](https://getout.gr/)가 존재한다. 따라서 현재 후보 중
컨셉 전달력은 `GET OUT`이 가장 높지만, 최종 출시 전에는 App Store 검색과 상표 검토를 별도로
진행해야 한다.

## 로우파이 후보

전체 비교: [앱 컨셉 / Onboarding + Home 후보](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-340)

### A — 침대에서 문까지

- 이름 표현: `GET UP`
- 핵심: 침대에서 문까지의 이동을 한 화면의 journey로 표현
- onboarding: [A-ONB](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-343)
- home: [A-HOME](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-344)
- 강점: 제품 목적과 오늘의 행동을 가장 쉽게 이해함
- 주의: 알람 앱처럼 보일 수 있어 위치 반경과 제한 앱 설명을 유지해야 함

### B — 문턱

- 이름 표현: `GET OUT`
- 핵심: 사용자가 지금 문 안인지 밖인지와 남은 거리를 큰 상태로 표현
- onboarding: [B-ONB](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-347)
- home: [B-HOME](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-348)
- 강점: 문 symbol과 `1 km`가 강하게 남고 shield 경험으로 확장하기 좋음
- 주의: 위치를 정밀 실시간 tracking하는 것처럼 오해하지 않도록 문구를 다듬어야 함

### C — 출발 티켓

- 이름 표현: `GO OUT`
- 핵심: 오늘 또는 다음날 규칙을 다음 출발을 위한 ticket으로 표현
- onboarding: [C-ONB](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-351)
- home: [C-HOME](https://www.figma.com/design/cgw5wRUZRhUMWqEwrl0U04?node-id=16-352)
- 강점: 다음 규칙의 요일·시간·위치·앱을 가장 구조적으로 읽을 수 있음
- 주의: 시각 은유가 강해 실제 교통·예약 서비스로 오해될 수 있음

## 선택 제안

- 컨셉의 고유성과 shield 확장성을 우선하면 `B`
- 첫 사용 이해도와 균형을 우선하면 `A`
- 여러 예정 규칙을 빠르게 훑는 정보 구조를 우선하면 `C`
- 권장 조합: `B`의 문턱 hero + `C`의 다음 규칙 정보 구조

선택 후 `T022`에서 한 방향 또는 조합을 승인하고, onboarding 단계 수·home의 빈 상태·여러 규칙
목록 진입을 보완한 다음 하이파이로 이동한다.
