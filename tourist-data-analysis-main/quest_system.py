from datetime import datetime, timedelta
from typing import List, Dict, Any
from enum import Enum
import random
import uuid
from firebase_admin import firestore
from firebase_config import initialize_firebase, USERS_COLLECTION

# 퀘스트 관련 컬렉션 이름 상수
DAILY_QUESTS_COLLECTION = 'daily_quests'
QUIZ_COLLECTION = 'quizzes'

# 퀘스트 타입 정의
class QuestType(Enum):
    THEME_MISSION = "theme_mission"    # 테마 기반 미션 퀘스트
    FIRST_VISIT = "first_visit"        # 첫 방문 퀘스트
    HISTORY_QUIZ = "history_quiz"      # 역사 퀴즈 퀘스트

# 퀘스트 상태 정의
class QuestStatus(Enum):
    ACTIVE = "active"                  # 진행 중
    REWARD_READY = "reward_ready"      # 보상 받을 준비됨
    REWARD_CLAIMED = "reward_claimed"  # 보상 받음
    EXPIRED = "expired"                # 만료됨
    FAILED = "failed"                  # 실패

# 관광지 좌표 정보 (이름: (위도, 경도))
PLACE_COORDINATES = {
    '경복궁': (37.5796, 126.9770),
    '경희궁': (37.5704, 126.9682),
    '광화문': (37.5725, 126.9768),
    '남산서울타워': (37.5511, 126.9882),
    '북촌한옥마을': (37.5825, 126.9849),
    '청계천': (37.56961, 127.0059),
    '독립문': (37.5725, 126.9595),
    '서울도서관': (37.5664, 126.9780)
}

# 관광지별 역사 퀴즈 데이터
PLACE_QUIZZES = {
    '경복궁': [
        {
            "question": "경복궁은 언제 건립되었나요?",
            "options": ["1395년", "1392년", "1400년", "1388년"],
            "correct_answer": 0,
            "explanation": "경복궁은 조선왕조의 첫 번째 궁궐로 1395년 태조 이성계에 의해 건립되었습니다."
        },
        {
            "question": "경복궁의 정전(正殿) 이름은?",
            "options": ["근정전", "경회루", "교태전", "강녕전"],
            "correct_answer": 0,
            "explanation": "근정전은 경복궁의 정전으로 조선왕조의 가장 중요한 건물 중 하나입니다."
        }
    ],
    '남산서울타워': [
        {
            "question": "남산서울타워의 높이는?",
            "options": ["236m", "262m", "236.7m", "262.7m"],
            "correct_answer": 2,
            "explanation": "남산서울타워는 높이 236.7m로 서울의 상징적인 타워입니다."
        },
        {
            "question": "남산서울타워가 완공된 연도는?",
            "options": ["1969년", "1975년", "1980년", "1985년"],
            "correct_answer": 0,
            "explanation": "남산서울타워는 1969년에 완공되어 1970년부터 일반에 공개되었습니다."
        }
    ],
    '청계천': [
        {
            "question": "청계천 복원 사업이 완료된 연도는?",
            "options": ["2003년", "2005년", "2007년", "2009년"],
            "correct_answer": 1,
            "explanation": "청계천 복원 사업은 2003년에 시작되어 2005년에 완료되었습니다."
        },
        {
            "question": "청계천의 총 길이는?",
            "options": ["5.8km", "6.8km", "7.8km", "8.8km"],
            "correct_answer": 0,
            "explanation": "청계천은 총 길이 5.8km의 도심 하천입니다."
        }
    ],
    '광화문': [
        {
            "question": "광화문의 '광화'는 무슨 뜻인가요?",
            "options": ["빛나는 화려함", "넓은 교화", "밝은 변화", "광명한 교화"],
            "correct_answer": 3,
            "explanation": "광화문의 '광화'는 '광명한 교화'를 의미합니다."
        }
    ],
    '북촌한옥마을': [
        {
            "question": "북촌한옥마을의 '북촌'은 무슨 뜻인가요?",
            "options": ["북쪽 마을", "북쪽 언덕", "북쪽 골짜기", "북쪽 산"],
            "correct_answer": 0,
            "explanation": "북촌은 '북쪽 마을'을 의미하며, 경복궁 북쪽에 위치한 한옥마을입니다."
        }
    ],
    '경희궁': [
        {
            "question": "경희궁은 어떤 왕의 별궁이었나요?",
            "options": ["인조", "숙종", "영조", "정조"],
            "correct_answer": 0,
            "explanation": "경희궁은 조선 인조의 별궁으로 건립되었습니다."
        }
    ],
    '독립문': [
        {
            "question": "독립문이 건립된 연도는?",
            "options": ["1896년", "1897년", "1898년", "1899년"],
            "correct_answer": 1,
            "explanation": "독립문은 1897년에 건립되어 조선의 독립을 상징하는 문입니다."
        }
    ],
    '서울도서관': [
        {
            "question": "서울도서관이 개관한 연도는?",
            "options": ["2008년", "2009년", "2010년", "2011년"],
            "correct_answer": 1,
            "explanation": "서울도서관은 2009년에 개관한 서울시립 도서관입니다."
        }
    ]
}

# 관광지 테마 분류 (각 테마당 3개 관광지, 겹치지 않도록 설정)
PLACE_THEMES = {
    '궁궐_역사': {
        'name': '궁궐과 역사',
        'description': '조선왕조의 궁궐과 역사적 건축물을 탐방하세요',
        'places': ['경복궁', '경희궁', '광화문'],
        'color': '#8B4513'  # 갈색
    },
    '자연_공원': {
        'name': '자연과 공원',
        'description': '자연 속에서 휴식을 취할 수 있는 공원과 하천을 방문하세요',
        'places': ['청계천', '남산서울타워'],
        'color': '#228B22'  # 녹색
    },
    '전통_문화': {
        'name': '전통과 문화',
        'description': '한국의 전통 문화를 체험할 수 있는 장소를 탐방하세요',
        'places': ['북촌한옥마을', '서울도서관', '독립문'],
        'color': '#FFD700'  # 금색
    }
}

# 테마별 미션 설명 (각 테마당 3개 관광지, 겹치지 않도록 설정)
THEME_MISSIONS = {
    '궁궐_역사': {
        'title': '조선왕조의 발자취',
        'description': '조선왕조의 궁궐이나 역사적 건축물을 방문하여 과거로의 시간여행을 경험하세요',
        'hint': '경복궁, 경희궁, 광화문 중 하나를 방문하세요',
        'points': 20
    },
    '자연_공원': {
        'title': '도심 속 자연 탐방',
        'description': '도심 속에서 자연을 만날 수 있는 공원이나 하천을 방문하여 휴식을 취하세요',
        'hint': '청계천, 남산서울타워 중 하나를 방문하세요',
        'points': 20
    },
    '전통_문화': {
        'title': '전통 문화 체험',
        'description': '한국의 전통 문화와 현대 문화가 공존하는 장소를 방문하여 문화를 체험하세요',
        'hint': '북촌한옥마을, 서울도서관, 독립문 중 하나를 방문하세요',
        'points': 20
    }
}

def create_theme_mission_quest(user_id: str) -> Dict[str, Any]:
    """
    테마 기반 미션 퀘스트 생성 함수
    - user_id: 사용자 ID
    - 랜덤 테마를 선택하여 해당 테마의 관광지 중 하나를 방문하는 미션 생성
    """
    # 랜덤 테마 선택
    available_themes = list(PLACE_THEMES.keys())
    selected_theme = random.choice(available_themes)
    return create_theme_mission_quest_with_theme(user_id, selected_theme)

def create_theme_mission_quest_with_theme(user_id: str, theme: str) -> Dict[str, Any]:
    """
    지정된 테마로 미션 퀘스트 생성 함수
    - user_id: 사용자 ID
    - theme: 지정할 테마
    - 해당 테마의 관광지 중 하나를 방문하는 미션 생성
    """
    theme_info = PLACE_THEMES[theme]
    mission_info = THEME_MISSIONS[theme]
    
    quest_id = str(uuid.uuid4())  # 퀘스트 고유 ID 생성
    today = datetime.now().strftime('%Y-%m-%d')  # 오늘 날짜
    
    quest_data = {
        "quest_id": quest_id,
        "user_id": user_id,
        "type": QuestType.THEME_MISSION.value,
        "title": mission_info['title'],
        "description": mission_info['description'],
        "theme": theme,  # 지정된 테마
        "theme_name": theme_info['name'],  # 테마 이름
        "theme_color": theme_info['color'],  # 테마 색상
        "target_places": theme_info['places'],  # 해당 테마의 관광지들
        "required_visits": 1,  # 1곳 방문 필요
        "completed_places": [],
        "hint": mission_info['hint'],  # 힌트 제공
        "points": mission_info['points'],  # 테마별 점수
        "status": QuestStatus.ACTIVE.value,
        "created_at": firestore.SERVER_TIMESTAMP,
        "expires_at": datetime.now() + timedelta(days=1),  # 1일 후 만료
        "date": today
    }
    return quest_data

def create_first_visit_quest(user_id: str, db) -> Dict[str, Any]:
    """
    첫 방문 관광지 퀘스트 생성 함수
    - user_id: 사용자 ID
    - db: 파이어스토어 DB 객체
    - 사용자가 방문하지 않은 관광지 중 1곳 방문 미션 생성
    """
    visits_ref = db.collection('visits')
    user_visits = visits_ref.where('user_id', '==', user_id).get()  # 사용자의 방문 기록 조회
    visited_places = set()
    for visit in user_visits:
        visited_places.add(visit.to_dict().get('target_place', ''))  # 방문한 관광지 집합
    all_places = set(PLACE_COORDINATES.keys())
    unvisited_places = list(all_places - visited_places)  # 방문하지 않은 관광지
    if not unvisited_places:
        unvisited_places = list(all_places)  # 모두 방문했다면 전체 관광지로 대체
    quest_id = str(uuid.uuid4())
    today = datetime.now().strftime('%Y-%m-%d')
    quest_data = {
        "quest_id": quest_id,
        "user_id": user_id,
        "type": QuestType.FIRST_VISIT.value,
        "title": "첫 방문 도전",
        "description": "가본 적 없는 새로운 관광지를 방문하세요",
        "target_places": unvisited_places,
        "required_visits": 1,
        "completed_places": [],
        "points": 20,  # 모든 퀘스트는 20점으로 통일
        "status": QuestStatus.ACTIVE.value,
        "created_at": firestore.SERVER_TIMESTAMP,
        "expires_at": datetime.now() + timedelta(days=1),
        "date": today
    }
    return quest_data

def create_first_visit_quest_excluding_theme(user_id: str, db, theme_mission_quest: Dict[str, Any]) -> Dict[str, Any]:
    """
    테마 미션과 겹치지 않는 첫 방문 관광지 퀘스트 생성 함수
    - user_id: 사용자 ID
    - db: 파이어스토어 DB 객체
    - theme_mission_quest: 이미 생성된 테마 미션 퀘스트
    - 테마 미션에서 선택된 관광지를 제외하고 첫 방문 미션 생성
    """
    # 사용자의 방문 기록 조회
    visits_ref = db.collection('visits')
    user_visits = visits_ref.where('user_id', '==', user_id).get()
    visited_places = set()
    for visit in user_visits:
        visited_places.add(visit.to_dict().get('target_place', ''))
    
    # 테마 미션에서 선택된 관광지들
    theme_places = set(theme_mission_quest.get('target_places', []))
    
    # 전체 관광지에서 방문한 곳과 테마 미션 관광지를 제외
    all_places = set(PLACE_COORDINATES.keys())
    available_places = list(all_places - visited_places - theme_places)
    
    # 사용 가능한 관광지가 없으면 테마 미션 관광지를 제외한 전체 관광지로 대체
    if not available_places:
        available_places = list(all_places - theme_places)
    
    # 사용 가능한 관광지가 여전히 없으면 전체 관광지로 대체 (최후의 수단)
    if not available_places:
        available_places = list(all_places)
    
    quest_id = str(uuid.uuid4())
    today = datetime.now().strftime('%Y-%m-%d')
    
    quest_data = {
        "quest_id": quest_id,
        "user_id": user_id,
        "type": QuestType.FIRST_VISIT.value,
        "title": "첫 방문 도전",
        "description": "가본 적 없는 새로운 관광지를 방문하세요 (테마 미션과 겹치지 않음)",
        "target_places": available_places,
        "required_visits": 1,
        "completed_places": [],
        "points": 20,
        "status": QuestStatus.ACTIVE.value,
        "created_at": firestore.SERVER_TIMESTAMP,
        "expires_at": datetime.now() + timedelta(days=1),
        "date": today
    }
    
    print(f"🎯 첫 방문 퀘스트 생성: {len(available_places)}개 관광지 중 선택 가능")
    print(f"   테마 미션 제외 관광지: {list(theme_places)}")
    print(f"   첫 방문 대상 관광지: {available_places}")
    
    return quest_data

def create_history_quiz_quests(user_id: str) -> List[Dict[str, Any]]:
    """
    전체 관광지 중 랜덤으로 3개를 뽑아 각각 퀴즈 퀘스트를 생성하는 함수
    - user_id: 사용자 ID
    - 반환: 퀴즈 퀘스트 3개 리스트
    """
    all_places = list(PLACE_QUIZZES.keys())
    # 관광지 3개 랜덤 선택 (중복 없이)
    selected_places = random.sample(all_places, 3)
    quiz_quests = []
    today = datetime.now().strftime('%Y-%m-%d')
    for selected_place in selected_places:
        place_quizzes = PLACE_QUIZZES[selected_place]
        selected_quiz = random.choice(place_quizzes)
        quest_id = str(uuid.uuid4())
        quest_data = {
            "quest_id": quest_id,
            "user_id": user_id,
            "type": QuestType.HISTORY_QUIZ.value,
            "title": "역사 퀴즈",
            "description": f"{selected_place}에 대한 역사 퀴즈를 풀어보세요",
            "target_place": selected_place,
            "quiz_question": selected_quiz["question"],
            "quiz_options": selected_quiz["options"],
            "correct_answer": selected_quiz["correct_answer"],
            "explanation": selected_quiz["explanation"],
            "is_answered": False,
            "user_answer": None,
            "is_correct": None,
            "points": 20,  # 퀴즈 퀘스트는 20점
            "status": QuestStatus.ACTIVE.value,
            "created_at": firestore.SERVER_TIMESTAMP,
            "expires_at": datetime.now() + timedelta(days=1),
            "date": today
        }
        quiz_quests.append(quest_data)
    return quiz_quests

def generate_daily_quests(user_id: str) -> List[Dict[str, Any]]:
    """
    일일 테마 미션 퀘스트 3개 + 퀴즈 퀘스트 3개 생성 및 저장
    - user_id: 사용자 ID
    - 이미 생성된 퀘스트가 있으면 반환, 없으면 새로 생성
    - 3개의 서로 다른 테마 미션 + 3개의 서로 다른 퀴즈 퀘스트 생성
    """
    try:
        db = initialize_firebase()
        if not db:
            print("❌ Firebase 초기화 실패")
            raise Exception("Firebase 데이터베이스 연결에 실패했습니다.")
        
        print(f"✅ Firebase 연결 성공 - 사용자: {user_id}")
        
        today = datetime.now().strftime('%Y-%m-%d')
        quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
        
        # 이미 오늘의 퀘스트가 있으면 반환
        existing_quests = quests_ref.where('user_id', '==', user_id).where('date', '==', today).get()
        if existing_quests:
            quests = []
            for quest_doc in existing_quests:
                quest_data = quest_doc.to_dict()
                # SERVER_TIMESTAMP 값을 실제 datetime으로 변환
                quest_data = convert_timestamps(quest_data)
                quests.append(quest_data)
            print(f"📋 기존 퀘스트 {len(quests)}개 조회됨")
            return quests
        
        print("🆕 새로운 테마 미션 퀘스트 3개 + 퀴즈 퀘스트 3개 생성 중...")
        quests = []
        
        # 3개의 서로 다른 테마 미션 생성
        available_themes = list(PLACE_THEMES.keys())
        selected_themes = random.sample(available_themes, 3)  # 3개 테마 랜덤 선택
        for i, theme in enumerate(selected_themes, 1):
            theme_mission_quest = create_theme_mission_quest_with_theme(user_id, theme)
            quests.append(theme_mission_quest)
            print(f"   {i}. {PLACE_THEMES[theme]['name']} 테마 미션 생성 완료")
        
        # 3개의 퀴즈 퀘스트 생성
        quiz_quests = create_history_quiz_quests(user_id)
        for i, quiz_quest in enumerate(quiz_quests, 1):
            quests.append(quiz_quest)
            print(f"   {i}. {quiz_quest['target_place']} 퀴즈 퀘스트 생성 완료")
        
        # 퀘스트 DB에 저장
        for quest in quests:
            quests_ref.document(quest['quest_id']).set(quest)
        
        # 새로 생성된 퀘스트들도 SERVER_TIMESTAMP 변환
        converted_quests = []
        for quest in quests:
            converted_quest = convert_timestamps(quest)
            converted_quests.append(converted_quest)
        
        print(f"✅ 테마 미션 + 퀴즈 퀘스트 {len(converted_quests)}개 생성 및 저장 완료")
        return converted_quests
        
    except Exception as e:
        print(f"❌ 퀘스트 생성 중 오류: {e}")
        import traceback
        traceback.print_exc()
        raise Exception(f"퀘스트 생성에 실패했습니다: {str(e)}")
    
def convert_timestamps(quest_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    퀘스트 데이터의 SERVER_TIMESTAMP 값을 실제 datetime으로 변환
    """
    from firebase_admin import firestore
    
    # SERVER_TIMESTAMP를 실제 datetime으로 변환
    # 직접 비교로 SERVER_TIMESTAMP 감지
    timestamp_fields = ['created_at', 'completed_at', 'reward_claimed_at', 'expires_at']
    
    for field in timestamp_fields:
        if field in quest_data and quest_data[field] == firestore.SERVER_TIMESTAMP:
            if field == 'expires_at':
                quest_data[field] = datetime.now() + timedelta(days=1)
            else:
                quest_data[field] = datetime.now()
    
    return quest_data
    

def check_quest_completion(user_id: str, visited_place: str) -> List[Dict[str, Any]]:
    """
    관광지 방문 시 퀘스트 완료 여부 확인 및 업데이트
    - user_id: 사용자 ID
    - visited_place: 방문한 관광지 이름
    - 완료된 퀘스트 리스트 반환
    """
    db = initialize_firebase()
    if not db:
        return []
    today = datetime.now().strftime('%Y-%m-%d')
    quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
    # 오늘의 활성화된 퀘스트 조회
    active_quests = quests_ref.where('user_id', '==', user_id).where('date', '==', today).where('status', '==', QuestStatus.ACTIVE.value).get()
    completed_quests = []
    for quest_doc in active_quests:
        quest_data = quest_doc.to_dict()
        if quest_data['status'] != QuestStatus.ACTIVE.value:
            continue
        # 테마 기반 미션 퀘스트 완료 체크
        if quest_data['type'] == QuestType.THEME_MISSION.value:
            # 방문한 관광지가 해당 테마의 관광지인지 확인
            if visited_place in quest_data['target_places']:
                # 이미 완료된 관광지인지 확인
                if visited_place not in quest_data['completed_places']:
                    quest_data['completed_places'].append(visited_place)
                    
                    # 1곳 방문했는지 확인 (테마 미션은 1곳만 방문하면 완료)
                    if len(quest_data['completed_places']) >= quest_data['required_visits']:
                        quest_data['status'] = QuestStatus.REWARD_READY.value  # 보상 받을 준비 상태로 변경
                        completed_quests.append(quest_data)
                    
                    # DB 업데이트 (방문 기록 추가)
                    quests_ref.document(quest_data['quest_id']).update({
                        'completed_places': quest_data['completed_places'],
                        'status': quest_data['status'],
                        'completed_at': firestore.SERVER_TIMESTAMP if quest_data['status'] == QuestStatus.REWARD_READY.value else None
                    })
    return completed_quests

def submit_quiz_answer(user_id: str, quest_id: str, answer_index: int) -> Dict[str, Any]:
    """
    퀴즈 퀘스트 정답 제출 및 결과 처리
    - user_id: 사용자 ID
    - quest_id: 퀘스트 ID
    - answer_index: 사용자가 선택한 답변 인덱스
    - 정답 여부, 획득 점수 등 결과 반환
    """
    db = initialize_firebase()
    if not db:
        return {"error": "Database connection failed"}
    quest_ref = db.collection(DAILY_QUESTS_COLLECTION).document(quest_id)
    quest_doc = quest_ref.get()
    if not quest_doc.exists:
        return {"error": "Quest not found"}
    quest_data = quest_doc.to_dict()
    if quest_data['type'] != QuestType.HISTORY_QUIZ.value:
        return {"error": "Not a quiz quest"}
    if quest_data.get('is_answered', False):
        return {"error": "Quiz already answered"}
    is_correct = (answer_index == quest_data['correct_answer'])  # 정답 여부 판별
    points_earned = quest_data['points'] if is_correct else 0    # 정답 시 점수 획득
    # 퀘스트 상태 및 결과 DB 업데이트
    quest_ref.update({
        'is_answered': True,
        'user_answer': answer_index,
        'is_correct': is_correct,
        'status': QuestStatus.REWARD_READY.value if is_correct else QuestStatus.FAILED.value,  # 정답 시 보상 받을 준비 상태로 변경
        'completed_at': firestore.SERVER_TIMESTAMP
    })
    
    # 정답일 경우 즉시 점수 지급하지 않고 보상 지급 시에만 지급
    if is_correct:
        # 실제 Firestore에서 최신 총점 확인
        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        actual_total_score = user_doc.to_dict().get('total_score', 0)
        
        print(f"🧩 퀴즈 정답! 사용자 {user_id}")
        print(f"   퀴즈: {quest_data['quiz_question']}")
        print(f"   정답: {quest_data['quiz_options'][quest_data['correct_answer']]}")
        print(f"   보상 지급 시 +20점을 받을 수 있습니다.")
        print(f"   현재 총점: {actual_total_score}점 (Firestore 확인)")
        print(f"   ──────────────────────────────")
    return {
        "quest_id": quest_id,
        "is_correct": is_correct,
        "points_earned": points_earned,
        "correct_answer": quest_data['correct_answer'],
        "explanation": quest_data['explanation'],
        "message": "정답입니다!" if is_correct else "틀렸습니다. 다시 도전해보세요!"
    }

def calculate_quest_reward(completed_count: int) -> int:
    """
    퀘스트 완료 개수에 따른 보상 점수 계산
    - completed_count: 완료한 퀘스트 개수
    - 1개: +10점, 2개: +20점, 3개: +30점
    """
    if completed_count == 1:
        return 10
    elif completed_count == 2:
        return 20
    elif completed_count >= 3:
        return 30
    return 0

def claim_quest_reward(user_id: str, quest_id: str) -> Dict[str, Any]:
    """
    퀘스트 보상 받기 함수
    - user_id: 사용자 ID
    - quest_id: 퀘스트 ID
    - 보상 지급 및 상태 업데이트
    """
    db = initialize_firebase()
    if not db:
        return {"error": "Database connection failed"}

    quest_ref = db.collection(DAILY_QUESTS_COLLECTION).document(quest_id)
    quest_doc = quest_ref.get()

    if not quest_doc.exists:
        return {"error": "Quest not found"}

    quest_data = quest_doc.to_dict()

    # 퀘스트 소유자 확인
    if quest_data['user_id'] != user_id:
        return {"error": "Unauthorized access"}

    # 보상 받을 준비가 된 상태인지 확인
    if quest_data['status'] != QuestStatus.REWARD_READY.value:
        return {"error": "Quest is not ready for reward"}

    # 현재 퀘스트를 REWARD_CLAIMED로 변경
    quest_ref.update({
        'status': QuestStatus.REWARD_CLAIMED.value,
        'reward_claimed_at': firestore.SERVER_TIMESTAMP,
        'reward_points': quest_data['points']  # 개별 퀘스트 점수
    })

    # 모든 퀘스트에 대해 점수 지급 (퀴즈도 포함)
    user_ref = db.collection('users').document(user_id)
    
    # 트랜잭션을 사용하여 안전하게 점수 업데이트
    @firestore.transactional
    def update_user_score(transaction, user_ref, points_to_add):
        user_doc = user_ref.get(transaction=transaction)
        if not user_doc.exists:
            raise Exception("사용자를 찾을 수 없습니다.")
        
        current_score = user_doc.to_dict().get('total_score', 0)
        new_score = current_score + points_to_add
        
        transaction.update(user_ref, {
            'total_score': new_score,
            'last_quest_reward_at': firestore.SERVER_TIMESTAMP
        })
        
        return new_score
    
    # 트랜잭션 실행
    transaction = db.transaction()
    new_total_score = update_user_score(transaction, user_ref, quest_data['points'])
    
    # 실제 Firestore에서 최신 총점 확인
    user_doc = user_ref.get()
    actual_total_score = user_doc.to_dict().get('total_score', 0)
    
    print(f"🎉 퀘스트 완료! 사용자 {user_id}")
    print(f"   퀘스트: {quest_data['title']}")
    print(f"   획득 점수: +{quest_data['points']}점")
    print(f"   총 점수: {actual_total_score}점 (Firestore 확인)")
    print(f"   ──────────────────────────────")

    return {
        "quest_id": quest_id,
        "reward_points": quest_data['points'],
        "completed_count": 1,
        "message": f"퀘스트 보상을 받았습니다! +{quest_data['points']}점 획득!"
    }

def update_quest_status_only(user_id: str, quest_id: str) -> Dict[str, Any]:
    """
    퀘스트 상태만 REWARD_CLAIMED로 변경 (점수는 추가하지 않음)
    - user_id: 사용자 ID
    - quest_id: 퀘스트 ID
    - 상태만 변경하고 점수 지급은 하지 않음
    """
    db = initialize_firebase()
    if not db:
        return {"error": "Database connection failed"}

    quest_ref = db.collection(DAILY_QUESTS_COLLECTION).document(quest_id)
    quest_doc = quest_ref.get()

    if not quest_doc.exists:
        return {"error": "Quest not found"}

    quest_data = quest_doc.to_dict()

    # 퀘스트 소유자 확인
    if quest_data['user_id'] != user_id:
        return {"error": "Unauthorized access"}

    # 보상 받을 준비가 된 상태인지 확인
    if quest_data['status'] != QuestStatus.REWARD_READY.value:
        return {"error": "Quest is not ready for reward"}

    # 퀘스트 상태만 REWARD_CLAIMED로 변경 (점수 지급 없음)
    quest_ref.update({
        'status': QuestStatus.REWARD_CLAIMED.value,
        'reward_claimed_at': firestore.SERVER_TIMESTAMP
    })

    print(f"📋 퀘스트 상태 변경 완료! 사용자 {user_id}")
    print(f"   퀘스트: {quest_data['title']}")
    print(f"   상태: REWARD_READY → REWARD_CLAIMED")
    print(f"   점수 지급: 없음 (별도 처리)")
    print(f"   ──────────────────────────────")

    return {
        "quest_id": quest_id,
        "status": QuestStatus.REWARD_CLAIMED.value,
        "message": "퀘스트 상태가 성공적으로 변경되었습니다."
    }



def get_quest_progress(user_id: str) -> Dict[str, Any]:
    """
    사용자의 퀘스트 진행 상황 조회
    - user_id: 사용자 ID
    - 퀘스트 진행 상황 및 보상 정보 반환
    """
    db = initialize_firebase()
    if not db:
        return {"error": "Database connection failed"}

    today = datetime.now().strftime('%Y-%m-%d')
    quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
    user_quests = quests_ref.where('user_id', '==', user_id).where('date', '==', today).get()

    total_quests = 0
    active_quests = 0
    reward_ready_quests = 0
    claimed_quests = 0

    for quest_doc in user_quests:
        quest_data = quest_doc.to_dict()
        total_quests += 1

        if quest_data['status'] == QuestStatus.ACTIVE.value:
            active_quests += 1
        elif quest_data['status'] == QuestStatus.REWARD_READY.value:
            reward_ready_quests += 1
        elif quest_data['status'] == QuestStatus.REWARD_CLAIMED.value:
            claimed_quests += 1

    # 보상 받을 수 있는 점수 계산
    available_reward = calculate_quest_reward(reward_ready_quests)

    return {
        "total_quests": total_quests,
        "active_quests": active_quests,
        "reward_ready_quests": reward_ready_quests,
        "claimed_quests": claimed_quests,
        "available_reward": available_reward,
        "progress_percentage": (reward_ready_quests + claimed_quests) / total_quests * 100 if total_quests > 0 else 0
    } 