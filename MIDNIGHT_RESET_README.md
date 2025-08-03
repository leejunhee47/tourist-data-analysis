# 자정 퀘스트 리셋 시스템

## 개요

자정 퀘스트 리셋 시스템은 사용자가 완료한 퀘스트들을 자정이 지나면 자동으로 다시 활성 상태로 초기화하는 기능입니다. 이를 통해 사용자는 매일 새로운 퀘스트를 수행할 수 있습니다.

## 리셋 대상

- **상태**: `REWARD_CLAIMED` (보상 받음)
- **날짜**: 어제 날짜의 퀘스트
- **타입**: 모든 퀘스트 타입 (테마 미션, 퀴즈, 방문 횟수, 공유 등)

## 구현된 기능

### 1. 자동 리셋 함수

#### `check_and_reset_quests_at_midnight(user_id: str)`
- 어제 완료된 퀘스트가 있는지 확인
- 필요시 자동으로 리셋 수행
- 리셋 결과 반환

#### `reset_quests_at_midnight(user_id: str)`
- 어제 완료된 퀘스트들을 강제로 리셋
- 모든 완료 데이터 초기화
- 만료일을 다음날로 설정

### 2. 통합 함수

#### `generate_daily_quests_with_midnight_reset(user_id: str)`
- 자정 리셋 확인 후 퀘스트 생성
- 기존 `generate_daily_quests` 함수를 대체

#### `get_quest_progress_with_midnight_check(user_id: str)`
- 자정 리셋 확인 후 진행 상황 조회
- 기존 `get_quest_progress` 함수를 대체

### 3. 강제 리셋 함수

#### `force_reset_all_user_quests(user_id: str)`
- 사용자의 모든 퀘스트를 강제로 ACTIVE 상태로 변경
- 테스트 및 관리 목적으로 사용

## 데이터 초기화 항목

리셋 시 다음 데이터들이 초기화됩니다:

- **상태**: `REWARD_CLAIMED` → `ACTIVE`
- **날짜**: 어제 날짜 → 오늘 날짜
- **만료일**: 다음날로 설정
- **완료된 장소**: `completed_places` → `[]`
- **방문 횟수**: `current_visit_count` → `0`
- **퀴즈 답변**: `is_answered` → `False`, `user_answer` → `None`, `is_correct` → `None`
- **공유 완료**: `is_completed` → `False`
- **리셋 시간**: `reset_at` 필드에 기록

## API 엔드포인트

### 기존 엔드포인트 (자정 리셋 통합)

#### `GET /quests/{user_id}`
- 자정 리셋 확인 후 퀘스트 조회
- `generate_daily_quests_with_midnight_reset` 사용

#### `GET /quests/{user_id}/progress`
- 자정 리셋 확인 후 진행 상황 조회
- `get_quest_progress_with_midnight_check` 사용

### 새로운 엔드포인트

#### `POST /quests/midnight-reset/{user_id}`
- 자정 리셋 확인 및 수행
- `check_and_reset_quests_at_midnight` 호출

#### `POST /quests/force-reset/{user_id}`
- 강제 리셋 (테스트용)
- `force_reset_all_user_quests` 호출

#### `POST /quests/manual-reset/{user_id}`
- 수동 리셋
- `reset_quests_at_midnight` 호출

## 사용 예시

### 1. 자동 리셋 (권장)
```python
# 퀘스트 조회 시 자동으로 리셋 확인
quests = generate_daily_quests_with_midnight_reset(user_id)
```

### 2. 수동 리셋
```python
# 특정 사용자의 퀘스트 수동 리셋
result = reset_quests_at_midnight(user_id)
```

### 3. 강제 리셋 (테스트용)
```python
# 모든 퀘스트를 강제로 리셋
result = force_reset_all_user_quests(user_id)
```

## 테스트 방법

### 테스트 파일 실행
```bash
python test_midnight_reset.py
```

### API 테스트
```bash
# 자정 리셋 확인
curl -X POST http://localhost:8000/quests/midnight-reset/test_user

# 강제 리셋
curl -X POST http://localhost:8000/quests/force-reset/test_user

# 수동 리셋
curl -X POST http://localhost:8000/quests/manual-reset/test_user
```

## 리셋 조건

### 자동 리셋 조건
1. 사용자가 어제 완료한 퀘스트가 존재
2. 퀘스트 상태가 `REWARD_CLAIMED`
3. 퀘스트 날짜가 어제 날짜

### 리셋 제외 조건
1. 오늘 생성된 퀘스트
2. 아직 완료되지 않은 퀘스트 (`ACTIVE`, `REWARD_READY`)
3. 이미 만료된 퀘스트 (`EXPIRED`, `FAILED`)

## 로깅

리셋 과정에서 다음 정보가 로그에 기록됩니다:

- 리셋된 퀘스트 수
- 리셋된 퀘스트 제목과 타입
- 오류 발생 시 상세 오류 메시지

## 주의사항

1. **데이터 손실**: 리셋 시 완료 데이터가 모두 초기화됩니다
2. **중복 실행**: 동일한 퀘스트에 대해 여러 번 리셋이 실행될 수 있습니다
3. **시간대**: 서버 시간을 기준으로 자정을 판단합니다
4. **성능**: 대량의 퀘스트가 있을 경우 리셋 시간이 오래 걸릴 수 있습니다

## 향후 개선 사항

1. **스케줄러**: 자동 스케줄러를 통한 정확한 자정 리셋
2. **배치 처리**: 대량 퀘스트 리셋 시 배치 처리 최적화
3. **백업**: 리셋 전 데이터 백업 기능
4. **알림**: 리셋 완료 시 사용자 알림 기능 