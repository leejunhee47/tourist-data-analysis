# 퀘스트 시스템 API 가이드

## 📋 개요
관광지 기반 게임의 일일 퀘스트 시스템 API입니다. 사용자가 관광지를 방문하고 퀴즈를 풀면서 보상을 받을 수 있는 기능을 제공합니다.

## 🎯 퀘스트 종류

| 퀘스트 타입 | 설명 | 보상 | 완료 조건 |
|------------|------|------|-----------|
| `theme_mission` | 테마별 관광지 방문 미션 | 20점 | 해당 테마의 관광지 1곳 방문 |
| `first_visit` | 가본 적 없는 새로운 관광지를 방문하세요 | 20점 | 처음 방문하는 관광지 |
| `history_quiz` | 관광지 관련 역사 퀴즈를 풀어보세요 | 20점 | 퀴즈 정답 제출 |

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
- **점수 분리**: 방문 점수(10점)와 퀘스트 보상(20점)은 별도로 지급

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

## 💡 프론트엔드 구현 가이드

### 1. 퀘스트 목록 화면 (핵심)

```dart
// 퀘스트 조회
Future<List<Quest>> getQuests(String userId) async {
  final response = await http.get(Uri.parse('$baseUrl/quests/$userId'));
  final data = jsonDecode(response.body);
  return (data['quests'] as List).map((q) => Quest.fromJson(q)).toList();
}

// 퀘스트 상태별 UI 표시
Widget buildQuestCard(Quest quest) {
  switch (quest.status) {
    case 'active':
      return ActiveQuestCard(quest);  // "진행 중" 표시
    case 'reward_ready':
      return RewardReadyCard(
        quest, 
        onClaimReward: () => claimReward(quest.id)  // "보상 받기" 버튼
      );
    case 'reward_claimed':
      return CompletedQuestCard(quest);  // "완료" 표시
    default:
      return DefaultQuestCard(quest);
  }
}

// 보상 받기 버튼 (핵심 기능)
class RewardReadyCard extends StatelessWidget {
  final Quest quest;
  final VoidCallback onClaimReward;
  
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange[100],
      child: Column(
        children: [
          Text(quest.title),
          Text('보상: +${quest.points}점'),
          ElevatedButton(
            onPressed: onClaimReward,
            child: Text('🎁 보상 받기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
```

### 2. 보상 받기 기능 (핵심)

```dart
// 보상 받기
Future<RewardResult> claimReward(String userId, String questId) async {
  final response = await http.post(
    Uri.parse('$baseUrl/quests/reward'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'user_id': userId,
      'quest_id': questId
    })
  );
  
  if (response.statusCode == 200) {
    final result = jsonDecode(response.body)['result'];
    
    // 성공 시 축하 애니메이션
    showRewardAnimation(result['reward_points']);
    
    return RewardResult.fromJson(result);
  } else {
    throw Exception('보상 지급 실패');
  }
}

// 축하 애니메이션
void showRewardAnimation(int points) {
  // 점수 획득 애니메이션 표시
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('🎉 축하합니다!'),
      content: Text('+$points점을 획득했습니다!'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('확인'),
        ),
      ],
    ),
  );
}
```

### 3. 퀴즈 화면

```dart
// 퀴즈 답변 제출
Future<QuizResult> submitQuizAnswer(String userId, String questId, int answerIndex) async {
  final response = await http.post(
    Uri.parse('$baseUrl/quests/quiz/answer'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'user_id': userId,
      'quest_id': questId,
      'answer_index': answerIndex
    })
  );
  return QuizResult.fromJson(jsonDecode(response.body)['result']);
}
```

### 4. 진행 상황 표시

```dart
// 진행 상황 조회
Future<QuestProgress> getQuestProgress(String userId) async {
  final response = await http.get(Uri.parse('$baseUrl/quests/$userId/progress'));
  return QuestProgress.fromJson(jsonDecode(response.body)['progress']);
}

// 프로그레스 바 표시
Widget buildProgressBar(QuestProgress progress) {
  return Column(
    children: [
      LinearProgressIndicator(
        value: progress.progressPercentage / 100,
        backgroundColor: Colors.grey[300],
        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
      ),
      Text('${progress.rewardReadyQuests}개 퀘스트 보상 대기 중'),
      Text('받을 수 있는 보상: +${progress.availableReward}점'),
    ],
  );
}
```

## 📊 데이터 모델

### Quest 모델
```dart
class Quest {
  final String questId;
  final String title;
  final String description;
  final String type;
  final String status;  // 'active', 'reward_ready', 'reward_claimed'
  final int points;
  final List<String> completedPlaces;  // 방문한 관광지 목록
  final int requiredVisits;
  final DateTime createdAt;
  final DateTime expiresAt;
  
  // 테마 미션 관련 필드
  final String? themeName;
  final String? themeColor;
  final List<String>? targetPlaces;  // 목표 관광지 목록
  final String? hint;
  
  // 퀴즈 관련 필드 (type이 'history_quiz'인 경우)
  final String? quizQuestion;
  final List<String>? quizOptions;
  final int? correctAnswer;
  final String? explanation;
  final bool? isAnswered;
  final int? userAnswer;
  final bool? isCorrect;
}
```

### QuestProgress 모델
```dart
class QuestProgress {
  final int totalQuests;
  final int activeQuests;        // 진행 중인 퀘스트
  final int rewardReadyQuests;   // 보상 받을 준비된 퀘스트 ⭐
  final int claimedQuests;       // 완료된 퀘스트
  final int availableReward;     // 받을 수 있는 총 보상 점수 ⭐
  final double progressPercentage;
}
```

## 🎮 사용자 경험 흐름

### 1. 관광지 방문 시나리오
```
1. 사용자가 관광지에 도착
2. 앱에서 사진 촬영 + GPS 확인
3. POST /predict/ 호출
4. 방문 성공 시:
   - 방문 점수 +10점 즉시 지급
   - 관련 퀘스트 상태가 active → reward_ready로 자동 변경
   - "퀘스트 완료!" 알림 표시
5. 퀘스트 탭에서 "보상 받기" 버튼 활성화
```

### 2. 퀘스트 탭에서 보상 받기
```
1. 사용자가 퀘스트 탭 접속
2. reward_ready 상태의 퀘스트에 "보상 받기" 버튼 표시
3. 사용자가 "보상 받기" 버튼 클릭
4. POST /quests/reward 호출
5. 퀘스트 상태가 reward_ready → reward_claimed로 변경
6. 퀘스트 보상 +20점 지급
7. 축하 애니메이션 표시
```

### 3. 점수 시스템
```
총 점수 = 방문 점수 + 퀘스트 보상 점수

예시:
- 광화문 방문: +10점 (방문 즉시)
- 궁궐과 역사 퀘스트 완료: +20점 (보상 받기 버튼 클릭 시)
- 총 획득: +30점
```

## ⚠️ 주의사항

1. **일일 퀘스트**: 매일 자정에 새로운 퀘스트가 생성됩니다.
2. **상태 변화**: 퀘스트 상태는 `active` → `reward_ready` → `reward_claimed` 순서로 변화합니다.
3. **보상 중복 방지**: 같은 퀘스트에서 보상을 여러 번 받을 수 없습니다.
4. **방문 인증**: 실제 앱에서는 GPS 좌표 기반 거리 계산으로 방문을 인증합니다.
5. **테마 겹침 방지**: 각 테마의 관광지는 서로 겹치지 않도록 설계되었습니다.
6. **점수 분리**: 방문 점수와 퀘스트 보상은 별도로 지급됩니다.

## 🔧 개발 환경 설정

### 서버 실행
```bash
cd tourist-data-analysis-main
python api.py
```

### 테스트 실행
```bash
python test_quest_system.py
```

### Flutter 앱에서 사용
```dart
// baseUrl 설정
const String baseUrl = 'http://localhost:8000';  // 개발 환경
// const String baseUrl = 'https://your-api-domain.com';  // 프로덕션 환경
```

## 📱 UI/UX 권장사항

1. **퀘스트 카드**: 상태별로 다른 색상과 아이콘 사용
   - `active`: 회색, "진행 중" 아이콘
   - `reward_ready`: 주황색, "🎁" 아이콘, "보상 받기" 버튼
   - `reward_claimed`: 초록색, "✅" 아이콘

2. **진행 상황**: 프로그레스 바와 퍼센트 표시
3. **보상 알림**: 퀘스트 완료 시 축하 애니메이션
4. **퀴즈 화면**: 4지선다 형태로 구현
5. **방문 기록**: 지도에서 방문한 관광지 표시

## 🚀 확장 가능한 기능

- 연속 퀘스트 완료 보너스
- 특별 이벤트 퀘스트
- 퀘스트 난이도별 보상 차등화
- 퀘스트 힌트 시스템
- 사용자별 퀘스트 통계

## 🧪 테스트 시스템 진행 과정

### test_quest_system.py test_theme_quest_clear 실행 과정

#### 1. 테스트 환경 준비
- **테스트 사용자 생성**: 타임스탬프 기반 고유 사용자명으로 새 사용자 생성
- **초기 점수 확인**: 테스트 시작 전 사용자의 총점 확인

#### 2. 테마 미션 퀘스트 생성/검증
- **API 호출**: `GET /quests/{user_id}`로 일일 퀘스트 생성
- **퀘스트 검증**: 정확히 3개의 테마 미션이 생성되었는지 확인
- **테마 분류**:
  - 궁궐과 역사: 경복궁, 경희궁, 광화문
  - 자연과 공원: 청계천, 남산서울타워  
  - 전통과 문화: 북촌한옥마을, 서울도서관, 독립문

#### 3. 관광지 방문 시뮬레이션
- **방문할 관광지**: 광화문, 남산서울타워, 독립문
- **방문 처리**: `POST /predict/` 엔드포인트 호출
  - 실제 이미지 파일 업로드
  - 정확한 GPS 좌표 전송
  - 거리 검증 (100m 이내)
- **자동 상태 변경**: 방문 성공 시 관련 퀘스트가 `active` → `reward_ready`로 자동 변경
- **방문 점수 지급**: 각 방문마다 +10점 즉시 지급

#### 4. 퀘스트 보상 지급 (핵심 테스트)
- **보상 대기 퀘스트 확인**: `reward_ready` 상태의 퀘스트 조회
- **보상 지급**: `POST /quests/reward` 엔드포인트 호출
- **상태 변경**: 퀘스트 상태가 `reward_ready` → `reward_claimed`로 변경
- **점수 지급**: 퀘스트 보상 +20점 지급
- **점수 검증**: 각 단계별 점수 변화 확인

#### 5. 최종 검증
- **점수 분석**: 예상 총점(90점)과 실제 총점 비교
  - 방문 점수: 3곳 × 10점 = 30점
  - 퀘스트 보상: 3개 × 20점 = 60점
  - 총 예상 점수: 90점
- **진행 상황 확인**: 퀘스트 진행률 및 상태별 개수 확인
- **결과 출력**: 성공/실패 여부 및 상세 분석 결과

#### 6. 핵심 테스트 포인트
- **3단계 시스템 검증**: `active` → `reward_ready` → `reward_claimed`
- **자동 상태 변경**: 방문 시 자동으로 `reward_ready` 상태로 변경
- **수동 보상 지급**: 퀘스트 탭에서 보상 받기 버튼으로 점수 획득
- **점수 분리**: 방문 점수와 퀘스트 보상이 별도로 지급되는지 확인
- **에러 처리**: 잘못된 요청에 대한 적절한 에러 응답 확인

#### 7. 예상 결과
```
✅ 총점이 정확히 계산되었습니다!
📊 점수 분석:
   방문 점수: 3곳 × 10점 = 30점
   퀘스트 보상: 3개 × 20점 = 60점
   예상 총점: 90점
   실제 총점: 90점
   �� 목표 달성! 90점 획득!
``` 

## test_daily_quiz_quests 퀴즈 퀘스트 가이드

1. 전체 관광지 중 랜덤으로 3개를 뽑아 각각 퀴즈 퀘스트를 생성한다.
2. 각 퀴즈 퀘스트에 대해 서버에서 내려준 정답 인덱스를 제출하면 퀘스트 상태가 'active'에서 'reward_ready'로 변경된다.
3. reward_ready 상태의 퀴즈 퀘스트에 대해 `/quests/reward` 엔드포인트를 호출하면 상태가 'reward_claimed'로 변경되고, 사용자 total_score에 20점이 누적된다.
4. 테스트 코드에서는 정답 제출 전후로 퀘스트 status 변화를 확인하고, 보상 지급 후 최종 점수가 클리어한 퀘스트 개수 × 20점이 되는지 검증한다.
5. 오답을 제출하면 퀘스트 상태가 'failed'로 변경되고 점수는 지급되지 않는다.

