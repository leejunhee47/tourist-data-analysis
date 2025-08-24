# 퀘스트 시스템 API 가이드

## 📋 개요
관광지 기반 게임의 일일 퀘스트 시스템 API입니다. 사용자가 관광지를 방문하고 퀴즈를 풀면서 보상을 받을 수 있는 기능을 제공합니다.

## 🎯 퀘스트 종류

| 퀘스트 타입 | 설명 | 보상 | 완료 조건 |
|------------|------|------|-----------|
| `theme_mission` | 테마별 관광지 방문 미션 | 20점 | 해당 테마의 관광지 1곳 방문 |
| `first_visit` | 가본 적 없는 새로운 관광지를 방문하세요 | 20점 | 처음 방문하는 관광지 |
| `history_quiz` | 관광지 관련 역사 퀴즈를 풀어보세요 | 20점 | 퀴즈 정답 제출 |
| `visit_count` | 오늘 아무 관광지 3곳 방문 | 30점 | 서로 다른 관광지 3곳 방문 |

## 🔄 퀘스트 상태 시스템 (3단계)

### **핵심 개념: 방문 ≠ 완료**
- **방문**: 관광지에 도착하여 사진 촬영 + GPS 확인
- **완료**: 퀘스트 탭에서 "보상 받기" 버튼 클릭

### **상태 변화 흐름**
```
퀘스트 생성
    ↓
ACTIVE 상태 (진행 중)
    ↓ (관광지 방문 시 자동)
REWARD_READY 상태 (보상 받을 준비됨)
    ↓ (퀘스트 탭에서 보상 받기 버튼 클릭)
REWARD_CLAIMED 상태 (완료)
    ↓
total_score에 점수 추가
```

### **상태별 상세 설명**

| 상태 | 설명 | 프론트엔드 표시 | 사용자 액션 |
|------|------|----------------|-------------|
| `active` | 진행 중 | "진행 중" 표시 | 관광지 방문 필요 |
| `reward_ready` | **보상 받을 준비됨** | **"보상 받기" 버튼** | **보상 받기 버튼 클릭** |
| `reward_claimed` | 보상 받음 | "완료" 표시 | 더 이상 액션 불필요 |
| `expired` | 만료됨 | "만료" 표시 | - |
| `failed` | 실패 | "실패" 표시 | - |

### **중요한 점**
- **방문 시 자동 상태 변경**: 관광지 방문이 성공하면 `active` → `reward_ready`로 자동 변경
- **수동 보상 지급**: 퀘스트 탭에서 사용자가 직접 "보상 받기" 버튼을 눌러야 점수 획득
- **점수 분리**: 방문 점수(10점)와 퀘스트 보상(20점/30점)은 별도로 지급

## 🚀 API 엔드포인트

### 1. 일일 퀘스트 조회
```http
GET /quests/{user_id}
```

**응답 예시:**
```json
{
  "user_id": "user123",
  "quests": [
    {
      "quest_id": "quest456",
      "title": "조선왕조의 발자취",
      "description": "조선왕조의 궁궐이나 역사적 건축물을 방문하여 과거로의 시간여행을 경험하세요",
      "type": "theme_mission",
      "theme_name": "궁궐과 역사",
      "target_places": ["경복궁", "경희궁", "광화문"],
      "status": "reward_ready",  // 방문 완료 후 상태
      "points": 20,
      "required_visits": 1,
      "completed_places": ["광화문"],  // 방문한 관광지
      "created_at": "2024-01-15T00:00:00",
      "expires_at": "2024-01-16T00:00:00"
    },
    {
      "quest_id": "visit_count_quest_id",
      "title": "관광지 탐방가",
      "type": "visit_count",
      "status": "active",
      "points": 30,
      "required_visits": 3,
      "completed_places": ["경복궁", "경희궁"],
      "current_visit_count": 2,
      "created_at": "2024-01-15T00:00:00",
      "expires_at": "2024-01-16T00:00:00"
    }
  ],
  "message": "일일 퀘스트를 성공적으로 조회했습니다."
}
```

### 2. 퀘스트 진행 상황 조회
```http
GET /quests/{user_id}/progress
```

**응답 예시:**
```json
{
  "user_id": "user123",
  "progress": {
    "total_quests": 3,
    "active_quests": 1,
    "reward_ready_quests": 1,  // 보상 받을 준비된 퀘스트
    "claimed_quests": 1,
    "available_reward": 20,    // 받을 수 있는 총 보상 점수
    "progress_percentage": 66.7
  },
  "message": "퀘스트 진행 상황을 성공적으로 조회했습니다."
}
```

### 3. 퀴즈 답변 제출
```http
POST /quests/quiz/answer
```

**요청:**
```json
{
  "user_id": "user123",
  "quest_id": "quest456",
  "answer_index": 0
}
```

**응답:**
```json
{
  "result": {
    "quest_id": "quest456",
    "is_correct": true,
    "points_earned": 20,
    "correct_answer": 0,
    "explanation": "정답 설명...",
    "message": "정답입니다!"
  },
  "message": "퀴즈 답변이 성공적으로 제출되었습니다."
}
```

### 4. 퀘스트 보상 받기 ⭐ (핵심 기능)
```http
POST /quests/reward
```

**요청:**
```json
{
  "user_id": "user123",
  "quest_id": "quest456"
}
```

**응답:**
```json
{
  "result": {
    "quest_id": "quest456",
    "reward_points": 20,
    "completed_count": 1,
    "message": "퀘스트 보상을 받았습니다! +20점 획득!"
  },
  "message": "퀘스트 보상을 성공적으로 받았습니다."
}
```

**중요**: 이 엔드포인트는 `reward_ready` 상태의 퀘스트만 처리합니다.

### 5. 관광지 방문 처리 (자동 상태 변경)
```http
POST /predict/
```

**요청:**
```
Content-Type: multipart/form-data

session_id: "session123"
target_place: "광화문"
image: [업로드된 이미지 파일]
latitude: 37.5725
longitude: 126.9768
```

**응답:**
```json
{
  "predictions": [...],
  "score_earned": 10,  // 방문 점수
  "is_correct": true,
  "message": "정답! +10점\n🎉 퀘스트 완료: 조선왕조의 발자취"
}
```

**중요**: 방문 성공 시 자동으로 관련 퀘스트의 상태가 `active` → `reward_ready`로 변경됩니다.

## 🆕 방문 횟수 퀘스트(visit_count) 가이드

### 생성 및 완료 흐름
1. 일일 퀘스트 생성 시 자동으로 1개 생성됨
2. 오늘 중 아무 관광지 3곳을 방문하면 완료
3. 각 방문 시 중복 없이 completed_places에 추가, current_visit_count 증가
4. 3곳 방문 시 상태가 `active` → `reward_ready`로 변경
5. /quests/reward 호출 시 상태가 `reward_claimed`로 변경되고 30점 지급
6. 중복 방문은 카운트되지 않음

### 예시
- 최초 상태:
```json
{
  "type": "visit_count",
  "status": "active",
  "completed_places": [],
  "current_visit_count": 0
}
```
- 1곳 방문 후:
```json
{
  "completed_places": ["경복궁"],
  "current_visit_count": 1
}
```
- 3곳 방문 후:
```json
{
  "completed_places": ["경복궁", "경희궁", "광화문"],
  "current_visit_count": 3,
  "status": "reward_ready"
}
```
- 보상 수령 후:
```json
{
  "status": "reward_claimed"
}
```

### 테스트 코드 흐름
1. 테스트 사용자를 생성한다.
2. /quests/{user_id}로 퀘스트를 조회해 visit_count 퀘스트가 생성됐는지 확인한다.
3. 경복궁, 경희궁, 광화문을 순서대로 방문한다.
4. 각 방문 후 completed_places, current_visit_count, status를 확인한다.
5. 3곳 방문 후 /quests/reward로 보상을 수령하고 상태와 점수 변화를 확인한다.
6. 중복 방문은 카운트되지 않음을 검증한다.

## 🧪 퀴즈 퀘스트(3개) 테스트 가이드

1. 전체 관광지 중 랜덤으로 3개를 뽑아 각각 퀴즈 퀘스트를 생성한다.
2. 각 퀴즈 퀘스트에 대해 서버에서 내려준 정답 인덱스를 제출하면 퀘스트 상태가 'active'에서 'reward_ready'로 변경된다.
3. reward_ready 상태의 퀴즈 퀘스트에 대해 /quests/reward 엔드포인트를 호출하면 상태가 'reward_claimed'로 변경되고, 사용자 total_score에 20점이 누적된다.
4. 테스트 코드에서는 정답 제출 전후로 퀘스트 status 변화를 확인하고, 보상 지급 후 최종 점수가 클리어한 퀘스트 개수 × 20점이 되는지 검증한다.
5. 오답을 제출하면 퀘스트 상태가 'failed'로 변경되고 점수는 지급되지 않는다.

---

## ⚠️ 주의사항

1. **일일 퀘스트**: 매일 자정에 새로운 퀘스트가 생성됩니다.
2. **상태 변화**: 퀘스트 상태는 `active` → `reward_ready` → `reward_claimed` 순서로 변화합니다.
3. **보상 중복 방지**: 같은 퀘스트에서 보상을 여러 번 받을 수 없습니다.
4. **방문 인증**: 실제 앱에서는 GPS 좌표 기반 거리 계산으로 방문을 인증합니다.
5. **테마 겹침 방지**: 각 테마의 관광지는 서로 겹치지 않도록 설계되었습니다.
6. **점수 분리**: 방문 점수와 퀘스트 보상은 별도로 지급됩니다.

---

## 🧪 테스트 시스템 진행 과정 (예시)

### test_visit_count_quest 실행 과정
1. 테스트 사용자 생성
2. visit_count 퀘스트 생성 확인
3. 경복궁, 경희궁, 광화문 방문
4. 각 방문 후 상태/점수 확인
5. 3곳 방문 후 reward_ready 상태 확인
6. /quests/reward로 보상 수령 및 reward_claimed 상태 확인
7. 최종 점수 및 상태 검증

### test_daily_quiz_quests 실행 과정
1. 테스트 사용자 생성
2. 퀴즈 퀘스트 3개 생성 확인
3. 각 퀴즈에 대해 정답 제출 및 상태 변화 확인
4. reward_ready 상태에서 보상 수령 및 점수 누적 확인
5. 오답 제출 시 failed 상태 및 점수 미지급 확인

