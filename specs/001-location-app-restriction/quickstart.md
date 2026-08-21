# Quickstart: 계획 검증 가이드

이 문서는 구현 완료 뒤 기능을 end-to-end로 검증하기 위한 실행 가이드다. 전체 데이터 규칙은
[data-model.md](data-model.md), 타깃 간 동작은 [contracts](contracts/)를 참조한다.

## Prerequisites

- Xcode 26.6 이상
- iOS 26 이상을 실행하는 테스트 iPhone
- 앱과 세 Screen Time 확장에 사용할 App ID
- 공통 App Group capability
- 앱과 각 Screen Time 확장의 Family Controls 개발 entitlement
- 배포 검증 시 Apple이 승인한 Family Controls 배포 entitlement
- 위치 이동 검증을 위한 500m/1km 실기기 경로 또는 Xcode 위치 시뮬레이션 파일

Simulator는 도메인·화면 흐름에 사용할 수 있지만 실제 앱 shield, 종료 상태 위치 전달,
재부팅 복구의 최종 근거로 사용하지 않는다.

## Build and Automated Tests

프로젝트 생성 후 먼저 scheme을 확인한다.

```sh
xcodebuild -list -project GetUp.xcodeproj
```

도메인·저장소·통합 테스트를 실행한다.

```sh
xcodebuild test \
  -project GetUp.xcodeproj \
  -scheme GetUp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

필수 자동 테스트 결과:

- 시간대 길이 14분은 거부되고 15분은 허용된다.
- 선택 요일, 비선택 요일, 자정 초과, 시작·종료 경계가 기대한 시간 상태를 만든다.
- 위치 오차 원의 내부·외부·경계 중첩 판정이 데이터 모델 공식과 일치한다.
- 위치 `unavailable`은 기존 shield 상태를 보존한다.
- 시간 종료와 신뢰 가능한 위치 이탈은 shield 제거 결정을 만든다.
- 동일 revision과 동일 상태의 반복 event는 효과를 만들지 않는다.
- 규칙 파일 round-trip, 손상 파일, 미지원 schema, atomic write 실패가 안전하게 처리된다.

## First-Run Device Setup

1. 개발 서명된 앱과 세 확장을 테스트 iPhone에 설치한다.
2. GetUp을 열고 개인용 앱 사용 제한 권한을 승인한다.
3. When In Use 위치 권한을 승인한 뒤 자동 기능 설정 과정에서 Always로 승격한다.
4. 정확한 위치 사용을 승인한다.
5. 시스템의 Background App Refresh가 사용 가능한지 확인한다.
6. 테스트용 앱 하나 이상을 제한 대상으로 선택한다.
7. 지도 핀 또는 현재 위치 바로가기로 기준 위치를 지정한다.
8. 500m 반경, 선택 요일과 15분 이상의 짧은 테스트 시간대를 저장한다.

Expected:

- 누락된 권한은 종류와 설정 방법이 표시된다.
- 장소·주소 검색 없이 지도 핀과 현재 위치 바로가기로 기준 위치를 선택할 수 있다.
- 유효하지 않은 15분 미만 규칙은 저장되지 않는다.
- 저장 성공 뒤 규칙이 다시 표시되고 시스템 일정 및 위치 조건이 등록된다.

## End-to-End Scenarios

### 1. 조건 결합과 shield

1. 선택 요일·시간대 안에서 기준 위치 내부의 신뢰 가능한 위치를 만든다.
2. 선택한 앱을 연다.
3. 선택하지 않은 앱도 연다.

Expected:

- 선택 앱에는 GetUp shield가 표시된다.
- shield 버튼은 제한 앱을 닫고 우회 권한을 제공하지 않는다.
- 비선택 앱은 GetUp 때문에 제한되지 않는다.

### 2. 위치 불확실성

내부 좌표, 외부 좌표, 오차 원이 500m 경계와 겹치는 좌표를 차례로 주입한다.

Expected:

- 확실한 내부만 새 제한을 활성화할 수 있다.
- 확실한 외부는 제한을 해제한다.
- 경계 중첩은 위치 확인 불가 상태를 표시하고 기존 제한 상태를 보존한다.

### 3. 시간 종료

활성 제한 상태에서 설정 종료 시각의 신뢰 가능한 시간 event를 발생시킨다.

Expected:

- 위치가 확인 불가여도 event 확인 뒤 30초 이내에 제한이 해제된다.

### 4. 앱 비실행과 재부팅

1. 유효한 규칙을 저장하고 GetUp을 foreground에서 제거한다.
2. 선택한 시간·위치 조건을 충족하고 선택 앱을 연다.
3. 기기를 재부팅하고 첫 잠금 해제를 완료한다.
4. GetUp을 직접 열지 않은 채 다음 신뢰 가능한 위치·시간 event를 만든다.

Expected:

- GetUp을 직접 열지 않아도 시스템 event 뒤 제한 상태가 규칙과 일치한다.
- 첫 잠금 해제 전 동작은 합격 기준에 포함하지 않는다.
- event 전달 지연과 event 확인 뒤 shield 반영 시간을 구분해 기록한다.

### 5. 권한 철회

Family Controls, Always location, Full Accuracy를 각각 철회한 뒤 앱을 다시 확인한다.

Expected:

- 새 제한을 적용하지 않는다.
- 필요한 권한과 복구 방법을 표시한다.
- Family Controls 재승인 뒤 제한 앱 재선택이 필요함을 안내한다.

### 6. 활성 중 편집 차단

활성 제한 중 기능 끄기, 규칙 수정, 규칙 삭제를 각각 시도한다.

Expected:

- 세 요청이 모두 거부된다.
- 시간 종료 또는 확인된 위치 이탈이라는 종료 조건을 안내한다.
- 시스템 설정의 권한 철회나 앱 삭제까지 막는다고 표시하지 않는다.

## Physical-Device Acceptance Record

다음 결과를 출시 전 STATUS 또는 별도 테스트 기록에 남긴다.

| Scenario | Required evidence |
|----------|-------------------|
| 500m entry/exit | 물리 경계 시각, OS event 시각, shield 반영 시각 |
| 1km entry/exit | 물리 경계 시각, OS event 시각, shield 반영 시각 |
| Background/terminated | 앱 비실행 상태의 event 및 제한 결과 |
| Reboot | 첫 잠금 해제 시각과 이후 자동 복구 결과 |
| Reduced Accuracy | 위치 확인 불가 안내와 상태 보존 |
| Permission revocation | 각 권한의 복구 안내와 새 제한 미적용 |
| Cross-midnight weekday | 시작 요일 귀속과 다음 날 종료 결과 |

관련 자동 테스트가 모두 통과하고 필수 실기기 시나리오가 기록되기 전에는 기능을 완료로 표시하지
않는다.
