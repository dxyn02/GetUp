# Contract: Shared Storage

## Purpose

메인 앱과 시스템 확장이 하나의 규칙 및 최근 위치 판정을 안전하게 공유하는 파일 계약이다.

## Container

- 앱과 관련 확장은 동일한 App Group identifier를 사용한다.
- 모든 파일 경로는 App Group container URL을 기준으로 계산한다.
- 실제 App Group identifier는 프로젝트 설정에서 한 곳에 정의하고 코드에 중복하지 않는다.

## Files

### restriction-rule.json

```json
{
  "schemaVersion": 1,
  "revision": 1,
  "isEnabled": true,
  "weekdays": ["monday", "tuesday"],
  "startTime": { "hour": 6, "minute": 0 },
  "endTime": { "hour": 9, "minute": 0 },
  "referenceLocation": { "latitude": 0.0, "longitude": 0.0 },
  "radiusMeters": 500,
  "activitySelection": "opaque-codable-payload",
  "createdAt": "ISO-8601 timestamp",
  "updatedAt": "ISO-8601 timestamp"
}
```

좌표와 `activitySelection` 예시는 형식만 나타내며 실제 값은 로그나 문서에 출력하지 않는다.

### location-condition.json

```json
{
  "schemaVersion": 1,
  "ruleRevision": 1,
  "state": "inside",
  "observedAt": "ISO-8601 timestamp",
  "distanceMeters": 120.0,
  "horizontalAccuracyMeters": 20.0,
  "source": "freshFix"
}
```

## Ownership and Atomicity

- 메인 앱만 규칙 파일을 쓴다.
- 메인 앱의 위치 adapter만 위치 판정 파일을 쓴다.
- 확장은 두 파일을 읽기 전용으로 사용한다.
- write는 같은 디렉터리의 임시 파일을 완전히 기록한 뒤 atomic replace한다.
- 파일 보호는 `completeUntilFirstUserAuthentication`을 사용한다.
- 저장 성공 후에만 일정·위치 등록을 새 revision으로 교체한다.

## Error Contract

| Error | Consumer behavior |
|-------|-------------------|
| 파일 없음 | 규칙은 `configurationRequired`, 위치는 `unavailable` |
| decode 실패 | 새 제한 적용 금지, 복구 안내 및 진단 기록 |
| 미지원 schema | 새 제한 적용 금지, migration 필요 상태 |
| rule revision 불일치 | 위치를 `unavailable`로 간주 |
| 첫 잠금 해제 전 파일 보호 | 상태 보존, 잠금 해제 후 재평가 |
| atomic write 실패 | 이전 완전한 snapshot 유지, 저장 실패 안내 |

## Privacy Contract

- 기준 좌표와 앱 선택 payload는 서버, analytics, 일반 로그에 기록하지 않는다.
- 앱 선택 토큰을 bundle identifier나 앱 이름으로 역변환하지 않는다.
- UserDefaults에는 전체 규칙이나 좌표를 저장하지 않는다.
- 규칙 삭제 시 공유 파일과 관련 시스템 일정·위치 조건을 함께 제거한다.
