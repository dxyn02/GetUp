# Contract: Shared Storage

## Purpose

메인 앱과 시스템 확장이 여러 규칙, 저장 장소 및 최근 위치 판정을 안전하게 공유하는 파일 계약이다.

## Container

- 앱과 관련 확장은 동일한 App Group identifier를 사용한다.
- 모든 파일 경로는 App Group container URL을 기준으로 계산한다.
- 실제 App Group identifier는 프로젝트 설정에서 한 곳에 정의하고 코드에 중복하지 않는다.

## Files

### restriction-rules.json

```json
{
  "schemaVersion": 2,
  "revision": 2,
  "rules": [{
    "schemaVersion": 2,
    "id": "stable-rule-id",
    "revision": 1,
    "name": "출근 준비",
    "isEnabled": true,
    "weekdays": ["monday", "tuesday"],
    "startTime": { "hour": 6, "minute": 0 },
    "endTime": { "hour": 9, "minute": 0 },
    "savedPlaceID": "stable-place-id",
    "radiusMeters": 1000,
    "activitySelection": "opaque-codable-payload",
    "createdAt": "ISO-8601 timestamp",
    "updatedAt": "ISO-8601 timestamp"
  }]
}
```

좌표와 `activitySelection` 예시는 형식만 나타내며 실제 값은 로그나 문서에 출력하지 않는다.

### saved-places.json

```json
{
  "schemaVersion": 1,
  "revision": 1,
  "places": [{
    "id": "stable-place-id",
    "name": "집",
    "latitude": 0.0,
    "longitude": 0.0,
    "createdAt": "ISO-8601 timestamp",
    "updatedAt": "ISO-8601 timestamp"
  }]
}
```

### location-conditions.json

```json
{
  "schemaVersion": 2,
  "conditions": [{
    "schemaVersion": 2,
    "ruleID": "stable-rule-id",
    "ruleRevision": 1,
    "state": "inside",
    "observedAt": "ISO-8601 timestamp",
    "distanceMeters": 120.0,
    "horizontalAccuracyMeters": 20.0,
    "source": "freshFix"
  }]
}
```

schema 2에는 rule ID별 최신 condition을 하나씩 저장한다. rule ID가 없는 schema 1 단일 snapshot은
특정 규칙에 귀속하지 않고 빈 schema 2 collection으로 migration한다.

### getup.authorization.last-known-snapshot

App Group `UserDefaults`에는 메인 앱이 마지막으로 확인한 Family Controls·위치 권한·위치 정확도·
Background App Refresh 상태와 `observedAt`을 JSON data로 저장한다. 전체 규칙, 위치 좌표 또는 앱 선택
token은 포함하지 않는다. Device Activity extension은 자체 위치 권한이 `notDetermined`일 때에만
24시간 미만의 앱 위치 권한·정확도를 보완값으로 사용한다. 현재 Family Controls 상태와 extension이
명시적으로 확인한 위치 권한은 항상 이 값보다 우선한다.

## Ownership and Atomicity

- 메인 앱만 규칙 파일을 쓴다.
- 메인 앱만 저장 장소 파일을 쓴다.
- 메인 앱의 위치 adapter만 위치 판정 파일을 쓴다.
- 확장은 규칙·장소·위치 판정 파일을 읽기 전용으로 사용한다.
- 메인 앱만 최신 권한 snapshot을 쓰고 Device Activity extension은 이를 읽기 전용으로 사용한다.
- write는 같은 디렉터리의 임시 파일을 완전히 기록한 뒤 atomic replace한다.
- 파일 보호는 `completeUntilFirstUserAuthentication`을 사용한다.
- 규칙 저장마다 대상 규칙 revision과 규칙 collection revision을 각각 1 증가시킨다.
- 저장 장소 collection을 먼저 기록한 뒤 규칙 collection을 기록해 규칙이 없는 장소를 참조하지 않게 한다.
- 편집을 시작한 규칙 revision과 현재 저장된 revision이 다르면 저장하지 않고 최신 값 재로딩을 요구한다.
- 저장 성공 후에만 일정·위치 등록을 새 revision으로 교체한다.

## Error Contract

| Error | Consumer behavior |
|-------|-------------------|
| 파일 없음 | 규칙은 `configurationRequired`, 위치는 `unavailable` |
| decode 실패 | 새 제한 적용 금지, 복구 안내 및 진단 기록 |
| 미지원 schema | 새 제한 적용 금지, migration 필요 상태 |
| rule ID 없음 또는 revision 불일치 | 해당 규칙의 위치를 `unavailable`로 간주 |
| 첫 잠금 해제 전 파일 보호 | 상태 보존, 잠금 해제 후 재평가 |
| atomic write 실패 | 이전 완전한 snapshot 유지, 저장 실패 안내 |

## Privacy Contract

- 기준 좌표와 앱 선택 payload는 서버, analytics, 일반 로그에 기록하지 않는다.
- 앱 선택 토큰을 bundle identifier나 앱 이름으로 역변환하지 않는다.
- UserDefaults에는 전체 규칙이나 좌표를 저장하지 않는다.
- 규칙 삭제 시 해당 규칙의 공유 데이터와 관련 시스템 일정·위치 조건을 함께 제거한다.
