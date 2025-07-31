from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import shutil
import os
import uuid
import traceback # 이 라인을 파일 상단에 추가해주세요.
from datetime import datetime
from clip_lora_inference import CLIPLoRAInference
from typing import List, Optional
from pydantic import BaseModel
from firebase_admin import firestore, storage
from firebase_config import initialize_firebase, USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION, REVIEWS_COLLECTION, DAILY_QUESTS_COLLECTION
from quest_system import (
    generate_daily_quests, 
    check_quest_completion, 
    submit_quiz_answer, 
    claim_quest_reward, 
    update_quest_status_only,
    get_quest_progress,
    create_history_quiz_quests  # 복수형 함수 import
)
from fastapi.staticfiles import StaticFiles
from place_config import PLACE_COORDINATES, calculate_distance_km

app = FastAPI()

app.mount("/map_images", StaticFiles(directory="map_images"), name="map_images")

MAX_DISTANCE_M = 100

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Firebase 초기화
db = initialize_firebase()
if not db:
    raise Exception("실패")

# Firebase Storage 초기화
try:
    # bucket 이름을 명시적으로 지정
    bucket = storage.bucket(name='tourapi-77ca1.firebasestorage.app')
    print("✅ Firebase Storage 초기화 성공")
except Exception as e:
    print(f"❌ Firebase Storage 초기화 실패: {e}")
    bucket = None

# 임시 이미지 저장 폴더 생성
TEMP_DIR = "temp_images"
os.makedirs(TEMP_DIR, exist_ok=True)

# CLIP-LoRA 모델 초기화 (지연 로딩)
print(" 서버 시작 중...")
inferencer = None  # 전역 변수로 선언

def initialize_model():
    """AI 모델을 초기화하는 함수"""
    global inferencer
    try:
        print("🤖 AI 모델 로딩 중...")
        inferencer = CLIPLoRAInference()
        print("✅ AI 모델 로딩 완료!")
        return True
    except Exception as e:
        print(f"❌ AI 모델 로딩 실패: {e}")
        return False

# Firebase Storage 이미지 저장 함수
def save_image_to_storage(image_path: str, user_id: str, place_name: str, visit_id: str) -> str:
    """
    이미지를 Firebase Storage에 저장하고 다운로드 URL을 반환합니다.
    
    Args:
        image_path: 로컬 이미지 파일 경로
        user_id: 사용자 ID
        place_name: 방문한 장소명
        visit_id: 방문 기록 ID
    
    Returns:
        str: Firebase Storage 다운로드 URL
    """
    try:
        print(f"📸 Firebase Storage 이미지 저장 시작...")
        print(f"   입력 파일: {image_path}")
        print(f"   사용자 ID: {user_id}")
        print(f"   장소명: {place_name}")
        print(f"   방문 ID: {visit_id}")
        
        # Firebase Storage bucket 확인
        if bucket is None:
            print("❌ Firebase Storage bucket이 초기화되지 않았습니다")
            return None
        
        # 파일 존재 확인
        if not os.path.exists(image_path):
            print(f"❌ 이미지 파일이 존재하지 않습니다: {image_path}")
            return None
        
        # 파일 확장자 확인
        file_extension = os.path.splitext(image_path)[1].lower()
        if file_extension not in ['.jpg', '.jpeg', '.png', '.gif']:
            file_extension = '.jpg'  # 기본값
        
        # Storage 경로 생성 (success_images 경로에 저장)
        storage_path = f"success_images/{user_id}/{visit_id}_{place_name}{file_extension}"
        print(f"   Storage 경로: {storage_path}")
        
        # 파일을 Storage에 업로드
        blob = bucket.blob(storage_path)
        print(f"   Blob 생성 완료: {blob.name}")
        
        blob.upload_from_filename(image_path)
        print(f"   파일 업로드 완료")
        
        # 공개 URL 설정 (읽기 권한)
        blob.make_public()
        
        # 다운로드 URL 반환
        download_url = blob.public_url
        
        print(f"📸 이미지 저장 완료: {storage_path}")
        print(f"   URL: {download_url}")
        
        return download_url
        
    except Exception as e:
        print(f"❌ 이미지 저장 실패: {e}")
        return None

# 사용자 성공 이미지 조회 함수
def get_user_success_images(user_id: str) -> List[dict]:
    """
    특정 사용자의 모든 성공 이미지를 조회합니다.
    
    Args:
        user_id: 사용자 ID
    
    Returns:
        List[dict]: 성공 이미지 목록
    """
    try:
        # 방문 기록에서 정답을 맞힌 기록만 조회 (인덱스 사용)
        visits_ref = db.collection(VISITS_COLLECTION)
        visits = visits_ref.where('user_id', '==', user_id).where('is_correct', '==', True).order_by('visit_time', direction=firestore.Query.DESCENDING).get()
        
        success_images = []
        for visit in visits:
            visit_data = visit.to_dict()
            if visit_data.get('image_url'):  # 이미지 URL이 있는 경우만
                success_images.append({
                    'visit_id': visit_data.get('visit_id'),
                    'place_name': visit_data.get('target_place'),
                    'image_url': visit_data.get('image_url'),
                    'visit_time': visit_data.get('visit_time'),
                    'confidence': visit_data.get('confidence', 0),
                    'score_earned': visit_data.get('score_earned', 0)
                })
        
        return success_images
        
    except Exception as e:
        print(f"❌ 성공 이미지 조회 실패: {e}")
        return []

# 서버 시작 시에는 모델 로딩하지 않음 (첫 요청 시 로딩)
print("✅ 서버 시작 완료! (모델은 첫 요청 시 로딩됩니다)")

# Pydantic 모델들
# ▼▼▼ [수정] profile_image_url 필드 추가 ▼▼▼
class UserCreate(BaseModel):
    username: str
    profile_image_url: Optional[str] = None

class GameSessionCreate(BaseModel):
    user_id: str
    target_places: List[str]

class PredictionResponse(BaseModel):
    predictions: List[dict]
    score_earned: int
    is_correct: bool
    message: str

class RankingResponse(BaseModel):
    rankings: List[dict]

class UserProfileResponse(BaseModel):
    user_id: str
    username: str
    total_score: int
    visit_history: List[dict]

class Place(BaseModel):
    name: str
    latitude: float
    longitude: float

class PlacesResponse(BaseModel):
    places: List[Place]

class QuestRewardRequest(BaseModel):
    user_id: str
    quest_id: str

class QuizAnswerRequest(BaseModel):
    user_id: str
    quest_id: str
    answer_index: int

class QuizQuestCreateRequest(BaseModel):
    user_id: str

# ▼▼▼ [신규] 리뷰 관련 모델 추가 ▼▼▼
class ReviewRequest(BaseModel):
    user_id: str
    place_name: str
    review_text: str
    image_url: Optional[str] = None

class ReviewResponse(BaseModel):
    review_id: str
    user_id: str
    place_name: str
    review_text: str
    image_url: Optional[str] = None
    created_at: str
    score_earned: int
    message: str

# 사용자 생성
@app.post("/create_user/")
async def create_user(user_data: UserCreate):
    TEST_GUEST_USERNAME = "게스트유저"
    TEST_GUEST_USER_ID = "guest-test-user-001"

    try:
        users_ref = db.collection(USERS_COLLECTION)

        if user_data.username == TEST_GUEST_USERNAME:
            guest_user_ref = users_ref.document(TEST_GUEST_USER_ID)
            guest_user_doc = guest_user_ref.get()
            
            if not guest_user_doc.exists:
                 # ▼▼▼ [수정] 게스트 유저 생성 시 profile_image_url 필드 추가 ▼▼▼
                guest_user_ref.set({
                    'user_id': TEST_GUEST_USER_ID,
                    'username': TEST_GUEST_USERNAME,
                    'total_score': 0,
                    'profile_image_url': '', # 게스트는 프로필 이미지 없음
                    'created_at': firestore.SERVER_TIMESTAMP
                })
                print(f"테스트 게스트 사용자 생성: {TEST_GUEST_USER_ID}")

            return {
                "user_id": TEST_GUEST_USER_ID, 
                "username": TEST_GUEST_USERNAME, 
                "message": "게스트 사용자를 성공적으로 조회했습니다."
            }

        query = users_ref.where('username', '==', user_data.username).limit(1).get()
        
        user_list = list(query)
        if user_list:
            # ▼▼▼ [수정] 기존 사용자 프로필 이미지 업데이트 로직 추가 ▼▼▼
            existing_user_doc = user_list[0]
            existing_user_data = existing_user_doc.to_dict()
            
            # 프로필 이미지 URL이 전송되었으면 업데이트
            if user_data.profile_image_url:
                existing_user_doc.reference.update({
                    'profile_image_url': user_data.profile_image_url
                })
                print(f"기존 사용자 ({existing_user_data['user_id']}) 프로필 이미지 업데이트 완료")

            print(f"기존 사용자 발견: {existing_user_data['user_id']}")
            return {
                "user_id": existing_user_data['user_id'], 
                "username": existing_user_data['username'], 
                "message": "기존 사용자를 성공적으로 조회했습니다."
            }
        
        # ▼▼▼ [수정] 새 사용자 생성 시 프로필 이미지 저장 로직 추가 ▼▼▼
        user_id = str(uuid.uuid4())
        user_ref = users_ref.document(user_id)
        
        user_ref.set({
            'user_id': user_id,
            'username': user_data.username,
            'total_score': 0,
            'profile_image_url': user_data.profile_image_url or '', # URL이 없으면 빈 문자열 저장
            'created_at': firestore.SERVER_TIMESTAMP
        })
        
        return {"user_id": user_id, "username": user_data.username, "message": "사용자가 생성되었습니다."}
    except Exception as e:
        print(f"ERROR: 사용자 생성 중 오류 발생: {e}") 
        traceback.print_exc() 
        raise HTTPException(status_code=500, detail=str(e))


# 게임 세션 시작
@app.post("/start_game/")
async def start_game(session_data: GameSessionCreate):
    try:
        session_id = str(uuid.uuid4())
        sessions_ref = db.collection(GAME_SESSIONS_COLLECTION)
        
        sessions_ref.document(session_id).set({
            'session_id': session_id,
            'user_id': session_data.user_id,
            'target_places': session_data.target_places,
            'current_score': 0,
            'is_active': True,
            'created_at': firestore.SERVER_TIMESTAMP,
            'ended_at': None
        })
        
        return {
            "session_id": session_id,
            "target_places": session_data.target_places,
            "message": f"게임이 시작되었습니다! 타깃 관광지: {', '.join(session_data.target_places)}"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/predict/", response_model=PredictionResponse)
async def predict_location(
    session_id: str = Form(...),
    target_place: str = Form(...),
    image: UploadFile = File(...),
    latitude: float = Form(...),
    longitude: float = Form(...)
):
    # 모델이 로드되지 않았으면 로딩
    global inferencer
    if inferencer is None:
        print("🔄 첫 요청 시 모델 로딩 중...")
        if not initialize_model():
            raise HTTPException(status_code=500, detail="AI 모델 로딩에 실패했습니다.")
    
    # 1) 타깃 관광지 좌표 확인
    if target_place not in PLACE_COORDINATES:
        raise HTTPException(status_code=400, detail="알 수 없는 타깃 관광지입니다.")
    target_lat, target_lon = PLACE_COORDINATES[target_place]

    # 2) 거리 계산 (km 단위 반환)
    distance_km = calculate_distance_km(latitude, longitude, target_lat, target_lon)
    distance_m = distance_km * 1000  # m 단위로 변환
    
    # 3) 반경 100m 초과 시 즉시 인증 실패
    if distance_m > MAX_DISTANCE_M:
        return PredictionResponse(
            predictions=[],
            score_earned=0,
            is_correct=False,
            message=(
                f"인증 실패: 사용자의 위치가 관광지로부터 "
                f"{int(distance_m)}m 떨어져 있습니다. (최대 허용 거리: {MAX_DISTANCE_M}m)"
            )
        )
        
    # 4) 거리 체크 통과 시에만 이미지 저장 및 예측 로직 실행
    try:
        # 파일명이 None인 경우 처리
        filename = image.filename if image.filename else f"temp_{uuid.uuid4()}.jpg"
        temp_image_path = os.path.join(TEMP_DIR, filename)
        
        # 업로드된 이미지를 임시 파일로 저장
        with open(temp_image_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)
        
        # 예측 수행
        results = inferencer.predict_place(
            image_path=temp_image_path,
            user_lat=latitude,
            user_lon=longitude
        )
        
        if results is None:
            return PredictionResponse(
                predictions=[],
                score_earned=0,
                is_correct=False,
                message="예측에 실패했습니다."
            )
        
        # 최고 신뢰도 결과 확인
        best_prediction = results[0]
        predicted_place = best_prediction['place_kor']
        confidence = best_prediction['confidence']
        
        # 점수 계산
        is_correct = predicted_place == target_place
        score_earned = 10 if is_correct else 0  # 각 관광지 방문 시 10점
        
        # 정답을 맞힌 경우에만 이미지를 Firebase Storage에 저장
        image_url = None
        if is_correct:
            print(f"🎉 정답입니다! 이미지 저장을 시작합니다...")
            # 세션에서 사용자 ID 가져오기
            session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
            session = session_ref.get()
            if session.exists:
                user_id = session.to_dict()['user_id']
                # 방문 ID 생성 (트랜잭션에서 사용할 예정)
                visit_id = str(uuid.uuid4())
                print(f"   사용자 ID: {user_id}")
                print(f"   방문 ID: {visit_id}")
                print(f"   장소: {target_place}")
                print(f"   임시 파일: {temp_image_path}")
                
                # 이미지를 Firebase Storage에 저장
                image_url = save_image_to_storage(temp_image_path, user_id, target_place, visit_id)
                if image_url is None:
                    print("⚠️ 이미지 저장 실패했지만 게임은 계속 진행됩니다")
                else:
                    print(f"✅ 이미지 저장 성공: {image_url}")
        else:
            print(f"❌ 틀렸습니다. 이미지 저장하지 않습니다.")
        
        # 임시 파일 삭제
        os.remove(temp_image_path)
        
        # Firestore 트랜잭션 시작
        transaction = db.transaction()
        
        @firestore.transactional
        def update_in_transaction(transaction, session_id, user_id):
            # 모든 읽기 작업을 먼저 수행
            # 세션 읽기
            session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
            session = session_ref.get(transaction=transaction)
            
            if not session.exists:
                raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")
            
            # 사용자 읽기
            user_ref = db.collection(USERS_COLLECTION).document(user_id)
            user = user_ref.get(transaction=transaction)
            
            if not user.exists:
                raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")
            
            # 읽은 데이터로 새로운 값 계산
            session_data = session.to_dict()
            new_session_score = session_data.get('current_score', 0) + score_earned
            
            user_data = user.to_dict()
            current_total_score = user_data.get('total_score', 0)
            new_total_score = current_total_score + score_earned
            
            # 모든 쓰기 작업을 나중에 수행
            # 세션 업데이트
            transaction.update(session_ref, {
                'current_score': new_session_score
            })
            
            # 사용자 총점 업데이트
            transaction.update(user_ref, {
                'total_score': new_total_score
            })
            
            # 방문 기록 저장 (이미지 URL 포함)
            visit_id = str(uuid.uuid4())
            visit_ref = db.collection(VISITS_COLLECTION).document(visit_id)
            
            visit_data = {
                'visit_id': visit_id,
                'session_id': session_id,
                'user_id': user_id,
                'target_place': target_place,
                'predicted_place': predicted_place,
                'is_correct': is_correct,
                'score_earned': score_earned,
                'confidence': confidence,
                'latitude': latitude,
                'longitude': longitude,
                'visit_time': firestore.SERVER_TIMESTAMP
            }
            
            # 정답을 맞힌 경우에만 이미지 URL 추가
            if is_correct and image_url:
                visit_data['image_url'] = image_url
            
            transaction.set(visit_ref, visit_data)
            
            return new_session_score, new_total_score
        
        # 세션에서 사용자 ID 가져오기
        session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
        session = session_ref.get()
        
        if not session.exists:
            raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")
        
        user_id = session.to_dict()['user_id']
        
        # 트랜잭션 실행
        new_session_score, new_total_score = update_in_transaction(transaction, session_id, user_id)
        
        # 방문 점수 로그 출력
        if is_correct:
            # 실제 Firestore에서 최신 총점 확인
            user_ref = db.collection(USERS_COLLECTION).document(user_id)
            user_doc = user_ref.get()
            actual_total_score = user_doc.to_dict().get('total_score', 0)
            
            print(f"📍 관광지 방문! 사용자 {user_id}")
            print(f"   방문 장소: {target_place}")
            print(f"   획득 점수: +{score_earned}점")
            print(f"   총 점수: {actual_total_score}점 (Firestore 확인)")
            print(f"   ──────────────────────────────")
        
        # 퀘스트 완료 체크 (트랜잭션 외부에서 실행)
        completed_quests = []
        if is_correct:
            completed_quests = check_quest_completion(user_id, target_place)
        
        message = f"정답! +{score_earned}점" if is_correct else f"틀렸습니다. 예측: {predicted_place}, 타깃: {target_place}"
        
        # 퀘스트 완료 메시지 추가
        if completed_quests:
            quest_names = [quest['title'] for quest in completed_quests]
            message += f"\n🎉 퀘스트 완료: {', '.join(quest_names)}"
        
        return PredictionResponse(
            predictions=results,
            score_earned=score_earned,
            is_correct=is_correct,
            message=message
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 게임 종료
@app.post("/end_game/{session_id}")
async def end_game(session_id: str):
    try:
        transaction = db.transaction()
        
        @firestore.transactional
        def end_game_transaction(transaction, session_id):
            session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
            session = session_ref.get(transaction=transaction)
            
            if not session.exists:
                raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")
            
            session_data = session.to_dict()
            
            if not session_data['is_active']:
                raise HTTPException(status_code=400, detail="이미 종료된 게임 세션입니다.")
            
            final_score = session_data['current_score']
            
            # 세션 종료 처리
            transaction.update(session_ref, {
                'is_active': False,
                'ended_at': firestore.SERVER_TIMESTAMP
            })
            
            return final_score
        
        final_score = end_game_transaction(transaction, session_id)
        
        return {
            "message": "게임이 종료되었습니다!",
            "final_score": final_score,
            "session_id": session_id
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 랭킹 조회
@app.get("/rankings/", response_model=RankingResponse)
async def get_rankings(limit: int = 10):
    try:
        users_ref = db.collection(USERS_COLLECTION)
        query = users_ref.order_by('total_score', direction=firestore.Query.DESCENDING).limit(limit)
        users = query.get()
        
        rankings = []
        for rank, user in enumerate(users, 1):
            user_data = user.to_dict()
            # ▼▼▼ [수정] 응답에 profile_image_url 필드 추가 ▼▼▼
            rankings.append({
                "rank": rank,
                "username": user_data['username'],
                "total_score": user_data['total_score'],
                "user_id": user_data['user_id'],
                "profile_image_url": user_data.get('profile_image_url', '') # 필드가 없을 경우 대비
            })
        
        return RankingResponse(rankings=rankings)
        
    except Exception as e:
        print(f"ERROR: 랭킹 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# 사용자 프로필 조회
@app.get("/user_profile/{user_id}", response_model=UserProfileResponse)
async def get_user_profile(user_id: str):
    try:
        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user = user_ref.get()
        
        if not user.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")
        
        user_data = user.to_dict()
        
        visits_ref = db.collection(VISITS_COLLECTION)
        visits = visits_ref.where('user_id', '==', user_id).order_by('visit_time', direction=firestore.Query.DESCENDING).get()
        
        visit_history = []
        for visit in visits:
            visit_data = visit.to_dict()
            visit_info = {
                "target_place": visit_data['target_place'],
                "predicted_place": visit_data['predicted_place'],
                "is_correct": visit_data['is_correct'],
                "score_earned": visit_data['score_earned'],
                "visit_time": visit_data['visit_time']
            }
            
            # 정답을 맞힌 경우에만 이미지 URL 추가
            if visit_data['is_correct'] and visit_data.get('image_url'):
                visit_info['image_url'] = visit_data['image_url']
            
            visit_history.append(visit_info)
        
        return UserProfileResponse(
            user_id=user_id,
            username=user_data['username'],
            total_score=user_data['total_score'],
            visit_history=visit_history
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/places/", response_model=PlacesResponse)
async def get_places():
    """서버에 설정된 모든 관광지의 이름과 좌표를 반환합니다."""
    try:
        places_data = []
        for name, (lat, lon) in PLACE_COORDINATES.items():
            places_data.append(Place(name=name, latitude=lat, longitude=lon))
        
        print(f"📍 관광지 좌표 반환: {len(places_data)}개 장소")
        return PlacesResponse(places=places_data)
    except Exception as e:
        print(f"ERROR: 관광지 좌표 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ==================== 퀘스트 시스템 엔드포인트 ====================

# 일일 퀘스트 생성/조회
@app.get("/quests/{user_id}")
async def get_daily_quests(user_id: str):
    """
    사용자의 일일 퀘스트를 생성하거나 조회합니다.
    - 이미 오늘의 퀘스트가 있으면 조회
    - 없으면 새로 생성
    """
    try:
        quests = generate_daily_quests(user_id)
        return {
            "user_id": user_id,
            "quests": quests,
            "message": "일일 퀘스트를 성공적으로 조회했습니다."
        }
    except Exception as e:
        print(f"ERROR: 퀘스트 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# 퀘스트 진행 상황 조회
@app.get("/quests/{user_id}/progress")
async def get_quest_progress_endpoint(user_id: str):
    """
    사용자의 퀘스트 진행 상황을 조회합니다.
    """
    try:
        progress = get_quest_progress(user_id)
        return {
            "user_id": user_id,
            "progress": progress,
            "message": "퀘스트 진행 상황을 성공적으로 조회했습니다."
        }
    except Exception as e:
        print(f"ERROR: 퀘스트 진행 상황 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# 퀴즈 답변 제출
@app.post("/quests/quiz/answer")
async def submit_quiz_answer_endpoint(quiz_data: QuizAnswerRequest):
    """
    퀴즈 퀘스트의 답변을 제출합니다.
    """
    print('quiz_data 확인', quiz_data)
    try:
        result = submit_quiz_answer(
            user_id=quiz_data.user_id,
            quest_id=quiz_data.quest_id,
            answer_index=quiz_data.answer_index
        )
        print('result 확인', result)
        print('API 서버에서 퀴즈 답변 처리 완료')
        # 퀴즈 답변 제출 후 현재 총점 확인 및 출력 (정답 여부와 관계없이)
        user_ref = db.collection(USERS_COLLECTION).document(quiz_data.user_id)
        user_doc = user_ref.get()
        current_total_score = user_doc.to_dict().get('total_score', 0)
        
        # 정답 여부와 관계없이 항상 출력
        is_correct = result.get('is_correct', False)
        print(f"🧩 퀴즈 답변 제출 완료! 사용자 {quiz_data.user_id}")
        print(f"   퀴즈 결과: {'정답입니다!' if is_correct else '틀렸습니다!'}")
        print(f"   현재 총점: {current_total_score}점 (Firestore 확인)")
        if is_correct:
            print(f"   보상 지급 시 +20점을 받을 수 있습니다.")
        print(f"   ──────────────────────────────")
        print(f"API 서버에서 총점 출력 완료: {current_total_score}점")
        
        return {
            "result": result,
            "message": "퀴즈 답변이 성공적으로 제출되었습니다."
        }
    except Exception as e:
        print(f"ERROR: 퀴즈 답변 제출 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# 퀘스트 보상 받기
@app.post("/quests/reward")
async def claim_quest_reward_endpoint(reward_data: QuestRewardRequest):
    """
    완료된 퀘스트의 보상을 받습니다.
    """
    try:
        result = claim_quest_reward(
            user_id=reward_data.user_id,
            quest_id=reward_data.quest_id
        )
        return {
            "result": result,
            "message": "퀘스트 보상을 성공적으로 받았습니다."
        }
    except Exception as e:
        print(f"ERROR: 퀘스트 보상 지급 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# 퀘스트 상태만 변경 (점수 지급 없음)
@app.post("/quests/status/")
async def update_quest_status_only_endpoint(reward_data: QuestRewardRequest):
    """
    퀘스트 상태만 REWARD_CLAIMED로 변경합니다 (점수는 지급하지 않음).
    배치 점수 처리를 위해 사용됩니다.
    """
    try:
        result = update_quest_status_only(
            user_id=reward_data.user_id,
            quest_id=reward_data.quest_id
        )
        return {
            "result": result,
            "message": "퀘스트 상태가 성공적으로 변경되었습니다."
        }
    except Exception as e:
        print(f"ERROR: 퀘스트 상태 변경 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ==================== 퀴즈 퀘스트 생성 엔드포인트 ====================
@app.post("/quests/quiz")
async def create_quiz_quest_endpoint(request: QuizQuestCreateRequest):
    """
    랜덤 관광지 퀴즈 퀘스트 3개를 생성하여 반환합니다.
    - user_id를 받아 create_history_quiz_quests 함수로 퀘스트 3개 생성
    - Firestore에 각각 저장 후, 다시 읽어와 리스트로 반환
    """
    try:
        user_id = request.user_id
        # 퀴즈 퀘스트 3개 생성
        quiz_quests = create_history_quiz_quests(user_id)
        db = initialize_firebase()
        if not db:
            raise Exception("Firebase 데이터베이스 연결에 실패했습니다.")
        quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
        saved_quests = []
        for quest_data in quiz_quests:
            quests_ref.document(quest_data['quest_id']).set(quest_data)
            # 저장 후 다시 읽어서 리스트에 추가
            quest_doc = quests_ref.document(quest_data['quest_id']).get()
            if quest_doc.exists:
                saved_quests.append(quest_doc.to_dict())
        return {"quests": saved_quests, "message": "퀴즈 퀘스트 3개가 성공적으로 생성되었습니다."}
    except Exception as e:
        print(f"ERROR: 퀴즈 퀘스트 생성 중 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [신규] 리뷰 저장 API 엔드포인트 추가 ▼▼▼
@app.post("/reviews/", response_model=ReviewResponse)
async def submit_review(review_data: ReviewRequest):
    """
    관광지 리뷰를 저장하고 보상 점수를 지급합니다.
    - 20자 이상의 리뷰 작성 시 +20점 추가
    """
    try:
        # 리뷰 텍스트 길이 검증
        if len(review_data.review_text.strip()) < 20:
            raise HTTPException(
                status_code=400, 
                detail="리뷰는 20자 이상 작성해주세요."
            )
        
        # Firebase 연결 확인
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")
        
        # 사용자 존재 확인
        user_ref = db.collection(USERS_COLLECTION).document(review_data.user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")
        
        # 리뷰 ID 생성
        review_id = f"review_{uuid.uuid4().hex[:8]}"
        
        # 현재 시간
        now = datetime.now()
        
        # 리뷰 데이터 준비
        review_doc = {
            "review_id": review_id,
            "user_id": review_data.user_id,
            "place_name": review_data.place_name,
            "review_text": review_data.review_text,
            "image_url": review_data.image_url,
            "created_at": now.isoformat(),
            "score_earned": 20
        }
        
        # Firestore 트랜잭션으로 리뷰 저장 및 점수 업데이트
        @firestore.transactional
        def save_review_transaction(transaction, review_doc, user_ref):
            # 리뷰 저장
            reviews_ref = db.collection(REVIEWS_COLLECTION)
            transaction.set(reviews_ref.document(review_id), review_doc)
            
            # 사용자 점수 업데이트 (+20점)
            transaction.update(user_ref, {
                'total_score': firestore.Increment(20),
                'last_review_at': now
            })
            
            return review_doc
        
        # 트랜잭션 실행
        transaction = db.transaction()
        saved_review = save_review_transaction(transaction, review_doc, user_ref)
        
        print(f"리뷰 저장 완료: {review_id} (사용자: {review_data.user_id}, 장소: {review_data.place_name})")
        
        return ReviewResponse(
            review_id=review_id,
            user_id=review_data.user_id,
            place_name=review_data.place_name,
            review_text=review_data.review_text,
            image_url=review_data.image_url,
            created_at=now.isoformat(),
            score_earned=20,
            message="리뷰가 성공적으로 저장되었습니다! +20점 획득!"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR: 리뷰 저장 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [신규] 리뷰 목록 조회 API 엔드포인트 추가 ▼▼▼
@app.get("/reviews/{user_id}")
async def get_user_reviews(user_id: str):
    """
    특정 사용자의 모든 리뷰를 조회합니다.
    - 생성일 기준 내림차순 정렬
    """
    try:
        # Firebase 연결 확인
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")
        
        # 사용자 존재 확인
        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")
        
        # 리뷰 조회 (user_id로 필터링, created_at 내림차순 정렬)
        reviews_ref = db.collection(REVIEWS_COLLECTION)
        reviews_query = reviews_ref.where('user_id', '==', user_id).order_by('created_at', direction=firestore.Query.DESCENDING)
        
        reviews = []
        for doc in reviews_query.stream():
            review_data = doc.to_dict()
            reviews.append(review_data)
        
        return {
            "user_id": user_id,
            "reviews": reviews,
            "total_reviews": len(reviews)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR: 리뷰 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [신규] 사용자 성공 이미지 조회 API 엔드포인트 추가 ▼▼▼
@app.get("/success_images/{user_id}")
async def get_user_success_images_endpoint(user_id: str):
    """
    특정 사용자의 모든 성공 이미지를 조회합니다.
    - 정답을 맞힌 방문 기록의 이미지만 반환
    - 방문 시간 기준 내림차순 정렬
    """
    try:
        # Firebase 연결 확인
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")
        
        # 사용자 존재 확인
        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")
        
        # 성공 이미지 조회
        success_images = get_user_success_images(user_id)
        
        return {
            "user_id": user_id,
            "success_images": success_images,
            "total_count": len(success_images),
            "message": f"성공 이미지 {len(success_images)}개를 조회했습니다."
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR: 성공 이미지 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [신규] 사용자 성공 이미지 통계 조회 API 엔드포인트 추가 ▼▼▼
@app.get("/success_images/{user_id}/stats")
async def get_user_success_images_stats(user_id: str):
    """
    특정 사용자의 성공 이미지 통계를 조회합니다.
    - 총 성공 횟수, 장소별 성공 횟수 등
    """
    try:
        # Firebase 연결 확인
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")
        
        # 사용자 존재 확인
        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")
        
        # 성공 이미지 조회
        success_images = get_user_success_images(user_id)
        
        # 통계 계산
        total_success = len(success_images)
        place_stats = {}
        total_score = 0
        
        for image in success_images:
            place_name = image['place_name']
            if place_name not in place_stats:
                place_stats[place_name] = 0
            place_stats[place_name] += 1
            total_score += image.get('score_earned', 0)
        
        # 장소별 성공 횟수 정렬 (내림차순)
        sorted_places = sorted(place_stats.items(), key=lambda x: x[1], reverse=True)
        
        return {
            "user_id": user_id,
            "total_success_count": total_success,
            "total_score_earned": total_score,
            "place_stats": [{"place_name": place, "success_count": count} for place, count in sorted_places],
            "message": f"성공 이미지 통계를 조회했습니다."
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR: 성공 이미지 통계 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# 서버 종료 시 정리 작업
@app.on_event("shutdown")
async def shutdown_event():
    print("🔄 서버 종료 중...")
    
    # 임시 이미지 폴더 정리
    try:
        if os.path.exists(TEMP_DIR):
            for filename in os.listdir(TEMP_DIR):
                file_path = os.path.join(TEMP_DIR, filename)
                if os.path.isfile(file_path):
                    os.remove(file_path)
            print(f"✅ 임시 이미지 폴더 정리 완료: {TEMP_DIR}")
    except Exception as e:
        print(f"❌ 임시 이미지 폴더 정리 실패: {e}")
    
    print("✅ 서버 종료 완료!")

# 서버 시작
if __name__ == "__main__":
    import uvicorn
    import socket
    import subprocess
    import sys
    import time
    
    def kill_process_on_port(port):
        try:
            cmd = f'netstat -ano | findstr :{port}'
            result = subprocess.check_output(cmd, shell=True).decode()
            
            if result:
                pid = result.strip().split()[-1]
                subprocess.run(['taskkill', '/F', '/PID', pid], check=True)
                print(f"포트 {port}를 사용하던 프로세스(PID: {pid})를 종료했습니다.")
                time.sleep(1)
                return True
        except Exception as e:
            print(f"프로세스 종료 중 오류 발생: {e}")
        return False
    
    PORT = 8000
    try:
        print(f"서버를 포트 {PORT}에서 시작합니다...")
        uvicorn.run(app, host="0.0.0.0", port=PORT)
    except OSError as e:
        if "address already in use" in str(e).lower():
            print(f"포트 {PORT}가 이미 사용 중입니다. 해당 프로세스를 종료합니다...")
            if kill_process_on_port(PORT):
                print("프로세스가 종료되었습니다. 서버를 다시 시작합니다...")
                time.sleep(1)
                uvicorn.run(app, host="0.0.0.0", port=PORT)
            else:
                print("프로세스를 종료할 수 없습니다.")
                sys.exit(1)
        else:
            print(f"서버 시작 중 오류 발생: {e}")
            sys.exit(1)