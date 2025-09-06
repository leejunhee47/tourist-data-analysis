from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import shutil
import os
import uuid
import traceback
from datetime import datetime
from clip_lora_inference import CLIPLoRAInference
from typing import List, Optional
from pydantic import BaseModel
from firebase_admin import firestore, storage
from firebase_config import initialize_firebase, USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION
from quest_system import (
    generate_daily_quests,
    check_quest_completion,
    submit_quiz_answer,
    claim_quest_reward,
    update_quest_status_only,
    get_quest_progress,
    create_history_quiz_quests,
    check_share_quest_completion
)
import random # [추가] 테스트 이미지 랜덤 선택을 위해 추가

app = FastAPI()

# Static 파일 마운트
app.mount("/map_images", StaticFiles(directory="map_images"), name="map_images")
app.mount("/test_images", StaticFiles(directory="test_images"), name="test_images") # [추가] 테스트 이미지 폴더 마운트

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
    raise Exception("Firebase 초기화에 실패했습니다.")

# Firebase Storage 초기화
try:
    bucket = storage.bucket(name='tourapi-77ca1.firebasestorage.app')
    print("✅ Firebase Storage 초기화 성공")
except Exception as e:
    print(f"❌ Firebase Storage 초기화 실패: {e}")
    bucket = None

# 임시 이미지 저장 폴더 생성
TEMP_DIR = "temp_images"
os.makedirs(TEMP_DIR, exist_ok=True)

# CLIP-LoRA 모델 초기화
inferencer = CLIPLoRAInference()

# ▼▼▼ [추가] 어드민 계정 정보 상수 ▼▼▼
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "admin"
ADMIN_USER_ID = "admin-user-001"
# ▲▲▲ [추가] 어드민 계정 정보 상수 ▲▲▲

# ▼▼▼ [추가] 리뷰 이미지 저장 함수 ▼▼▼
def save_review_image_to_storage(image_path: str, user_id: str, review_id: str) -> Optional[str]:
    """
    리뷰 이미지를 Firebase Storage에 저장하고 다운로드 URL을 반환합니다.
    """
    try:
        if bucket is None:
            print("❌ Firebase Storage bucket이 초기화되지 않았습니다")
            return None
        
        if not os.path.exists(image_path):
            print(f"❌ 이미지 파일이 존재하지 않습니다: {image_path}")
            return None
        
        file_extension = os.path.splitext(image_path)[1].lower() or '.jpg'
        storage_path = f"review_images/{user_id}/{review_id}{file_extension}"
        
        blob = bucket.blob(storage_path)
        blob.upload_from_filename(image_path)
        blob.make_public()
        download_url = blob.public_url
        
        print(f"📸 리뷰 이미지 저장 완료: {download_url}")
        return download_url
        
    except Exception as e:
        print(f"❌ 리뷰 이미지 저장 실패: {e}")
        return None
# ▲▲▲ [추가] 리뷰 이미지 저장 함수 ▲▲▲

# ▼▼▼ [추가] Firebase Storage 이미지 저장 함수 ▼▼▼
def save_image_to_storage(image_path: str, user_id: str, place_name: str, visit_id: str) -> Optional[str]:
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
# ▲▲▲ [추가] Firebase Storage 이미지 저장 함수 ▲▲▲

# ▼▼▼ [추가] 사용자 성공 이미지 조회 함수 ▼▼▼
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
# ▲▲▲ [추가] 사용자 성공 이미지 조회 함수 ▲▲▲

# ▼▼▼ [추가] 사용자 생성 헬퍼 함수 ▼▼▼
def create_user_in_db(user_id: str, username: str, profile_image_url: str = "", is_admin: bool = False, is_guest: bool = False) -> dict:
    """
    사용자를 데이터베이스에 생성하는 공통 함수
    """
    users_ref = db.collection(USERS_COLLECTION)
    user_ref = users_ref.document(user_id)
    
    user_data = {
        'user_id': user_id,
        'username': username,
        'total_score': 0,
        'profile_image_url': profile_image_url,
        'created_at': firestore.SERVER_TIMESTAMP
    }
    
    # 어드민 또는 게스트 플래그 추가
    if is_admin:
        user_data['is_admin'] = True
    if is_guest:
        user_data['is_guest'] = True
    
    user_ref.set(user_data)
    return user_data
# ▲▲▲ [추가] 사용자 생성 헬퍼 함수 ▲▲▲


# Pydantic 모델들
class UserCreate(BaseModel):
    username: str
    profile_image_url: Optional[str] = None

class AdminLogin(BaseModel):
    username: str
    password: str

class GameSessionCreate(BaseModel):
    user_id: str
    target_places: List[str]

class PredictionResponse(BaseModel):
    predictions: List[dict]
    score_earned: int
    is_correct: bool
    message: str
    
# [추가] 테스트 예측 요청을 위한 Pydantic 모델
class TestPredictionRequest(BaseModel):
    session_id: str
    target_place: str
    latitude: float
    longitude: float
    image_filename: Optional[str] = None

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

class ReviewResponse(BaseModel):
    review_id: str
    user_id: str
    place_name: str
    review_text: str
    image_url: Optional[str] = None
    created_at: str
    score_earned: int
    message: str

class UserInfo(BaseModel):
    username: str
    profile_image_url: Optional[str] = None

class PlaceReviewResponse(BaseModel):
    review_id: str
    user_id: str
    user_info: UserInfo
    place_name: str
    review_text: str
    image_url: Optional[str] = None
    created_at: str
    score_earned: int

class ShareRecordRequest(BaseModel):
    user_id: str
    review_id: str
    platform: str = "kakao"


# --- 이하 API 엔드포인트 ---

@app.post("/admin_login/")
async def admin_login(admin_data: AdminLogin):
    """
    어드민 계정으로 로그인하는 API
    """
    try:
        # 어드민 계정 정보 확인
        if (admin_data.username == ADMIN_USERNAME and 
            admin_data.password == ADMIN_PASSWORD):
            
            users_ref = db.collection(USERS_COLLECTION)
            admin_user_ref = users_ref.document(ADMIN_USER_ID)
            admin_user_doc = admin_user_ref.get()
            
            # 어드민 계정이 없으면 생성
            if not admin_user_doc.exists:
                create_user_in_db(
                    user_id=ADMIN_USER_ID,
                    username=ADMIN_USERNAME,
                    is_admin=True
                )
                print(f"어드민 계정 생성: {ADMIN_USER_ID}")
            
            return {
                "user_id": ADMIN_USER_ID,
                "username": ADMIN_USERNAME,
                "is_admin": True,
                "message": "어드민 로그인 성공"
            }
        else:
            raise HTTPException(status_code=401, detail="잘못된 어드민 계정 정보")
            
    except Exception as e:
        print(f"ERROR: 어드민 로그인 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/guest_login/")
async def guest_login():
    """
    게스트 로그인 API - 매번 새로운 게스트 계정 생성
    """
    try:
        # 현재 시간을 기반으로 고유한 게스트 ID 생성
        current_time = datetime.now()
        guest_id = f"guest-{current_time.strftime('%Y%m%d%H%M%S')}"
        # 밀리초까지 포함하여 중복 방지 (밀리초를 2자리로 변환)
        guest_username = f"게스트-{current_time.strftime('%m%d%H%M%S')}{current_time.microsecond//10000:02d}"
        
        # 새로운 게스트 계정 생성
        create_user_in_db(
            user_id=guest_id,
            username=guest_username,
            is_guest=True
        )
        
        print(f"새 게스트 계정 생성: {guest_id} ({guest_username})")
        
        return {
            "user_id": guest_id,
            "username": guest_username,
            "is_guest": True,
            "message": "게스트 계정이 생성되었습니다."
        }
        
    except Exception as e:
        print(f"ERROR: 게스트 로그인 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/create_user/")
async def create_user(user_data: UserCreate):
    """
    카카오 로그인용 사용자 생성 API
    """
    try:
        users_ref = db.collection(USERS_COLLECTION)
        
        # 기존 사용자 검색
        query = users_ref.where('username', '==', user_data.username).limit(1).get()
        
        user_list = list(query)
        if user_list:
            existing_user_doc = user_list[0]
            existing_user_data = existing_user_doc.to_dict()
            
            # 프로필 이미지 업데이트
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
        
        # 새 사용자 생성
        user_id = str(uuid.uuid4())
        create_user_in_db(
            user_id=user_id,
            username=user_data.username,
            profile_image_url=user_data.profile_image_url or ""
        )
        
        return {"user_id": user_id, "username": user_data.username, "message": "사용자가 생성되었습니다."}
        
    except Exception as e:
        print(f"ERROR: 사용자 생성 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


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
    if target_place not in inferencer.place_coords:
        raise HTTPException(status_code=400, detail="알 수 없는 타깃 관광지입니다.")
    target_lat, target_lon = inferencer.place_coords[target_place]

    distance_km = inferencer.calculate_distance(latitude, longitude, target_lat, target_lon)
    distance_m = distance_km * 1000

    if distance_m > MAX_DISTANCE_M:
        return PredictionResponse(
            predictions=[],
            score_earned=0,
            is_correct=False,
            message=f"인증 실패: 사용자의 위치가 관광지로부터 {int(distance_m)}m 떨어져 있습니다. (최대 허용 거리: {MAX_DISTANCE_M}m)"
        )

    try:
        filename = image.filename if image.filename else f"temp_{uuid.uuid4()}.jpg"
        temp_image_path = os.path.join(TEMP_DIR, filename)

        with open(temp_image_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)

        results = inferencer.predict_place(
            image_path=temp_image_path,
            user_lat=latitude,
            user_lon=longitude
        )

        if results is None:
            os.remove(temp_image_path)
            return PredictionResponse(predictions=[], score_earned=0, is_correct=False, message="예측에 실패했습니다.")

        best_prediction = results[0]
        predicted_place = best_prediction['place_kor']
        confidence = best_prediction['confidence']

        is_correct = predicted_place == target_place
        score_earned = 10 if is_correct else 0

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

        transaction = db.transaction()

        @firestore.transactional
        def update_in_transaction(transaction, session_id, user_id):
            session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
            session = session_ref.get(transaction=transaction)
            if not session.exists:
                raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")

            user_ref = db.collection(USERS_COLLECTION).document(user_id)
            user = user_ref.get(transaction=transaction)
            if not user.exists:
                raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")

            session_data = session.to_dict()
            new_session_score = session_data.get('current_score', 0) + score_earned

            user_data = user.to_dict()
            new_total_score = user_data.get('total_score', 0) + score_earned

            transaction.update(session_ref, {'current_score': new_session_score})
            transaction.update(user_ref, {'total_score': new_total_score})

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

        session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
        session = session_ref.get()
        if not session.exists:
            raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")
        user_id = session.to_dict()['user_id']

        new_session_score, new_total_score = update_in_transaction(transaction, session_id, user_id)

        if is_correct:
            user_ref = db.collection(USERS_COLLECTION).document(user_id)
            user_doc = user_ref.get()
            actual_total_score = user_doc.to_dict().get('total_score', 0)
            print(f"📍 관광지 방문! 사용자 {user_id}\n   방문 장소: {target_place}\n   획득 점수: +{score_earned}점\n   총 점수: {actual_total_score}점 (Firestore 확인)\n   ──────────────────────────────")

        completed_quests = []
        if is_correct:
            completed_quests = check_quest_completion(user_id, target_place)

        message = f"정답! +{score_earned}점" if is_correct else f"틀렸습니다. 예측: {predicted_place}, 타깃: {target_place}"
        if completed_quests:
            quest_names = [quest['title'] for quest in completed_quests]
            message += f"\n🎉 퀘스트 완료: {', '.join(quest_names)}"

        return PredictionResponse(predictions=results, score_earned=score_earned, is_correct=is_correct, message=message)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- [추가] 테스트 이미지를 사용한 예측 API (어드민 전용) ---
@app.post("/predict_with_test_image/", response_model=PredictionResponse)
async def predict_with_test_image(request: TestPredictionRequest):
    try:
        session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(request.session_id)
        session = session_ref.get()
        if not session.exists:
            raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")
        
        user_id = session.to_dict().get('user_id')
        if user_id != ADMIN_USER_ID:
            raise HTTPException(status_code=403, detail="이 기능은 어드민만 사용할 수 있습니다.")

        test_image_dir = os.path.join("test_images", request.target_place)
        if not os.path.isdir(test_image_dir):
            raise HTTPException(status_code=404, detail=f"'{request.target_place}'에 대한 테스트 이미지를 찾을 수 없습니다. (경로: {test_image_dir})")

        if request.image_filename:
            chosen_image = request.image_filename
            test_image_path = os.path.join(test_image_dir, chosen_image)
            if not os.path.isfile(test_image_path):
                raise HTTPException(status_code=404, detail=f"'{chosen_image}' 파일을 찾을 수 없습니다.")
        else:
            available_images = [f for f in os.listdir(test_image_dir) if os.path.isfile(os.path.join(test_image_dir, f))]
            if not available_images:
                raise HTTPException(status_code=404, detail=f"'{request.target_place}' 폴더에 테스트 이미지가 없습니다.")
            chosen_image = random.choice(available_images)
            test_image_path = os.path.join(test_image_dir, chosen_image)
        
        print(f"어드민 테스트: '{request.target_place}' 미션을 위해 '{test_image_path}' 이미지를 사용합니다.")

        # --- 여기서부터는 기존 predict_location 로직을 재사용 (단, 이미지 저장 제외) ---
        target_place = request.target_place
        latitude = request.latitude
        longitude = request.longitude
        session_id = request.session_id

        if target_place not in inferencer.place_coords:
            raise HTTPException(status_code=400, detail="알 수 없는 타깃 관광지입니다.")
        target_lat, target_lon = inferencer.place_coords[target_place]
        distance_km = inferencer.calculate_distance(latitude, longitude, target_lat, target_lon)
        distance_m = distance_km * 1000

        if distance_m > MAX_DISTANCE_M:
            return PredictionResponse(
                predictions=[], score_earned=0, is_correct=False,
                message=f"인증 실패: 사용자의 위치가 관광지로부터 {int(distance_m)}m 떨어져 있습니다. (최대 허용 거리: {MAX_DISTANCE_M}m)"
            )
        
        results = inferencer.predict_place(image_path=test_image_path, user_lat=latitude, user_lon=longitude)

        if results is None:
            return PredictionResponse(predictions=[], score_earned=0, is_correct=False, message="예측에 실패했습니다.")

        best_prediction = results[0]
        predicted_place = best_prediction['place_kor']
        confidence = best_prediction['confidence']

        is_correct = predicted_place == target_place
        score_earned = 10 if is_correct else 0
        
        # 테스트 예측이므로 이미지 URL은 항상 None
        image_url = None

        transaction = db.transaction()
        @firestore.transactional
        def update_in_transaction(transaction, session_id, user_id):
            session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
            session = session_ref.get(transaction=transaction)
            if not session.exists:
                raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")

            user_ref = db.collection(USERS_COLLECTION).document(user_id)
            user = user_ref.get(transaction=transaction)
            if not user.exists:
                raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")

            new_session_score = session.to_dict().get('current_score', 0) + score_earned
            new_total_score = user.to_dict().get('total_score', 0) + score_earned

            transaction.update(session_ref, {'current_score': new_session_score})
            transaction.update(user_ref, {'total_score': new_total_score})

            visit_id = str(uuid.uuid4())
            visit_ref = db.collection(VISITS_COLLECTION).document(visit_id)
            visit_data = {
                'visit_id': visit_id, 'session_id': session_id, 'user_id': user_id,
                'target_place': target_place, 'predicted_place': predicted_place,
                'is_correct': is_correct, 'score_earned': score_earned,
                'confidence': confidence, 'latitude': latitude, 'longitude': longitude,
                'visit_time': firestore.SERVER_TIMESTAMP,
                'is_test': True # 테스트 예측임을 명시
            }
            transaction.set(visit_ref, visit_data)

        update_in_transaction(transaction, session_id, user_id)
        
        completed_quests = []
        if is_correct:
            completed_quests = check_quest_completion(user_id, target_place)

        message = f"정답! +{score_earned}점" if is_correct else f"틀렸습니다. 예측: {predicted_place}, 타깃: {target_place}"
        if completed_quests:
            quest_names = [quest['title'] for quest in completed_quests]
            message += f"\n🎉 퀘스트 완료: {', '.join(quest_names)}"

        return PredictionResponse(predictions=results, score_earned=score_earned, is_correct=is_correct, message=message)

    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR: 테스트 이미지 예측 처리 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# --- [추가] 장소별 테스트 이미지 목록 반환 API ---
@app.get("/api/test_images/{place_name}")
async def get_test_images_for_place(place_name: str):
    """
    특정 장소에 대한 테스트 이미지 URL 목록을 반환합니다.
    """
    test_image_dir = os.path.join("test_images", place_name)
    if not os.path.isdir(test_image_dir):
        raise HTTPException(status_code=404, detail=f"'{place_name}'에 대한 테스트 이미지를 찾을 수 없습니다.")

    try:
        image_files = [f for f in os.listdir(test_image_dir) if os.path.isfile(os.path.join(test_image_dir, f))]
        image_urls = [f"/test_images/{place_name}/{f}" for f in image_files]
        return {"image_urls": image_urls}
    except Exception as e:
        print(f"ERROR: 테스트 이미지 목록 조회 중 오류 발생: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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
            transaction.update(session_ref, {'is_active': False, 'ended_at': firestore.SERVER_TIMESTAMP})
            return final_score

        final_score = end_game_transaction(transaction, session_id)
        return {"message": "게임이 종료되었습니다!", "final_score": final_score, "session_id": session_id}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/rankings/", response_model=RankingResponse)
async def get_rankings(limit: int = 10):
    try:
        users_ref = db.collection(USERS_COLLECTION)
        query = users_ref.order_by('total_score', direction=firestore.Query.DESCENDING).limit(limit)
        users = query.get()

        rankings = []
        for rank, user in enumerate(users, 1):
            user_data = user.to_dict()
            rankings.append({
                "rank": rank,
                "username": user_data['username'],
                "total_score": user_data['total_score'],
                "user_id": user_data['user_id'],
                "profile_image_url": user_data.get('profile_image_url', '')
            })
        return RankingResponse(rankings=rankings)
    except Exception as e:
        print(f"ERROR: 랭킹 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

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
    try:
        places_data = [Place(name=name, latitude=lat, longitude=lon) for name, (lat, lon) in inferencer.place_coords.items()]
        return PlacesResponse(places=places_data)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [추가] 장소별 로컬 이미지 URL을 제공하는 엔드포인트 ▼▼▼
from fastapi.responses import JSONResponse

@app.get("/places/local-images", response_class=JSONResponse)
async def get_places_local_images():
    """
    /map_images/ 폴더에 있는 장소 이미지 파일의 URL 맵을 반환합니다.
    파일 이름이 장소 이름과 일치해야 합니다 (예: 경복궁.jpg, 광화문.png).
    """
    try:
        local_images_map = {}
        supported_extensions = ['.jpg', '.jpeg', '.png']
        map_images_dir = "map_images"
        
        place_names = inferencer.place_coords.keys()

        if not os.path.isdir(map_images_dir):
             return JSONResponse(content={})

        for name in place_names:
            for ext in supported_extensions:
                image_filename = f"{name}{ext}"
                image_path = os.path.join(map_images_dir, image_filename)
                if os.path.exists(image_path):
                    # 로컬 파일이 존재하면, 해당 URL을 맵에 추가
                    local_images_map[name] = f"/{map_images_dir}/{image_filename}"
                    break # 첫 번째로 찾은 파일 사용
        
        return JSONResponse(content=local_images_map)
    except Exception as e:
        print(f"ERROR: 로컬 이미지 맵 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
# ▲▲▲ [추가] 장소별 로컬 이미지 URL을 제공하는 엔드포인트 ▲▲▲

# ==================== 퀘스트 시스템 엔드포인트 ====================

@app.get("/quests/{user_id}")
async def get_daily_quests(user_id: str):
    try:
        quests = generate_daily_quests(user_id)
        return {"user_id": user_id, "quests": quests, "message": "일일 퀘스트를 성공적으로 조회했습니다."}
    except Exception as e:
        print(f"ERROR: 퀘스트 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/quests/{user_id}/progress")
async def get_quest_progress_endpoint(user_id: str):
    try:
        progress = get_quest_progress(user_id)
        return {"user_id": user_id, "progress": progress, "message": "퀘스트 진행 상황을 성공적으로 조회했습니다."}
    except Exception as e:
        print(f"ERROR: 퀘스트 진행 상황 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/quests/quiz/answer")
async def submit_quiz_answer_endpoint(quiz_data: QuizAnswerRequest):
    try:
        result = submit_quiz_answer(user_id=quiz_data.user_id, quest_id=quiz_data.quest_id, answer_index=quiz_data.answer_index)
        user_ref = db.collection(USERS_COLLECTION).document(quiz_data.user_id)
        user_doc = user_ref.get()
        current_total_score = user_doc.to_dict().get('total_score', 0)
        is_correct = result.get('is_correct', False)
        print(f"🧩 퀴즈 답변 제출 완료! 사용자 {quiz_data.user_id}\n   퀴즈 결과: {'정답입니다!' if is_correct else '틀렸습니다!'}\n   현재 총점: {current_total_score}점 (Firestore 확인)")
        if is_correct:
            print("   보상 지급 시 +20점을 받을 수 있습니다.")
        print("   ──────────────────────────────")
        return {"result": result, "message": "퀴즈 답변이 성공적으로 제출되었습니다."}
    except Exception as e:
        print(f"ERROR: 퀴즈 답변 제출 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/quests/reward")
async def claim_quest_reward_endpoint(reward_data: QuestRewardRequest):
    try:
        result = claim_quest_reward(user_id=reward_data.user_id, quest_id=reward_data.quest_id)
        return {"result": result, "message": "퀘스트 보상을 성공적으로 받았습니다."}
    except Exception as e:
        print(f"ERROR: 퀘스트 보상 지급 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/quests/status/")
async def update_quest_status_only_endpoint(reward_data: QuestRewardRequest):
    try:
        result = update_quest_status_only(user_id=reward_data.user_id, quest_id=reward_data.quest_id)
        return {"result": result, "message": "퀘스트 상태가 성공적으로 변경되었습니다."}
    except Exception as e:
        print(f"ERROR: 퀘스트 상태 변경 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/quests/quiz")
async def create_quiz_quest_endpoint(request: QuizQuestCreateRequest):
    try:
        user_id = request.user_id
        quiz_quests = create_history_quiz_quests(user_id)
        db = initialize_firebase()
        if not db:
            raise Exception("Firebase 데이터베이스 연결에 실패했습니다.")
        quests_ref = db.collection("daily_quests")
        saved_quests = []
        for quest_data in quiz_quests:
            quests_ref.document(quest_data['quest_id']).set(quest_data)
            quest_doc = quests_ref.document(quest_data['quest_id']).get()
            if quest_doc.exists:
                saved_quests.append(quest_doc.to_dict())
        return {"quests": saved_quests, "message": "퀴즈 퀘스트 3개가 성공적으로 생성되었습니다."}
    except Exception as e:
        print(f"ERROR: 퀴즈 퀘스트 생성 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [수정] 리뷰 저장 API 엔드포인트 전체 수정 (Firebase Storage 연동) ▼▼▼
@app.post("/reviews/", response_model=ReviewResponse)
async def submit_review(
    user_id: str = Form(...),
    place_name: str = Form(...),
    review_text: str = Form(...),
    image: Optional[UploadFile] = File(None)
):
    """
    관광지 리뷰를 저장하고 보상 점수를 지급합니다.
    - 20자 이상의 리뷰 작성 시 +20점 추가
    - 이미지 파일 업로드 시 Firebase Storage에 저장
    """
    try:
        if len(review_text.strip()) < 20:
            raise HTTPException(status_code=400, detail="리뷰는 20자 이상 작성해주세요.")

        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")

        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")

        image_url = None
        review_id = f"review_{uuid.uuid4().hex[:8]}"

        if image:
            # 파일을 임시 경로에 저장
            filename = image.filename if image.filename else f"{review_id}.jpg"
            temp_image_path = os.path.join(TEMP_DIR, f"{review_id}_{filename}")
            
            try:
                with open(temp_image_path, "wb") as buffer:
                    shutil.copyfileobj(image.file, buffer)

                # Firebase Storage에 업로드하고 URL 받기
                image_url = save_review_image_to_storage(
                    image_path=temp_image_path, 
                    user_id=user_id, 
                    review_id=review_id
                )
            finally:
                 # 임시 파일 삭제
                if os.path.exists(temp_image_path):
                    os.remove(temp_image_path)

        now = datetime.now()

        review_doc = {
            "review_id": review_id,
            "user_id": user_id,
            "place_name": place_name,
            "review_text": review_text,
            "image_url": image_url, # Firebase URL 또는 None
            "created_at": now.isoformat(),
            "score_earned": 20
        }

        @firestore.transactional
        def save_review_transaction(transaction, review_doc_data, user_ref_to_update):
            reviews_ref = db.collection("reviews")
            transaction.set(reviews_ref.document(review_id), review_doc_data)
            transaction.update(user_ref_to_update, {
                'total_score': firestore.Increment(20),
                'last_review_at': now
            })

        transaction = db.transaction()
        save_review_transaction(transaction, review_doc, user_ref)

        print(f"리뷰 저장 완료: {review_id} (사용자: {user_id}, 장소: {place_name})")

        return ReviewResponse(
            review_id=review_id,
            user_id=user_id,
            place_name=place_name,
            review_text=review_text,
            image_url=image_url,
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


@app.get("/reviews/{user_id}")
async def get_user_reviews(user_id: str):
    """
    특정 사용자의 모든 리뷰를 조회합니다.
    - [수정] 각 리뷰에 작성자 정보(username, profile_image_url)를 포함합니다.
    - 생성일 기준 내림차순 정렬
    """
    try:
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")

        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")

        # [수정 시작] 사용자 정보를 미리 가져옵니다.
        user_data = user_doc.to_dict()
        user_info_data = {
            'username': user_data.get('username', '알 수 없는 사용자'),
            'profile_image_url': user_data.get('profile_image_url', '')
        }

        reviews_ref = db.collection("reviews")
        reviews_query = reviews_ref.where('user_id', '==', user_id).order_by('created_at', direction=firestore.Query.DESCENDING)

        reviews = []
        for doc in reviews_query.stream():
            review_data = doc.to_dict()
            # 각 리뷰 데이터에 user_info를 추가합니다.
            full_review_data = {**review_data, "user_info": user_info_data}
            reviews.append(full_review_data)
        # [수정 종료]

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

# ▼▼▼ [추가] 특정 장소의 모든 리뷰를 조회하는 API 엔드포인트 추가 ▼▼▼
@app.get("/reviews/place/{place_name}", response_model=List[PlaceReviewResponse])
async def get_reviews_for_place(place_name: str):
    """
    특정 장소에 대한 모든 리뷰를 조회합니다.
    - 각 리뷰에 작성자 정보(username, profile_image_url)를 포함합니다.
    - 생성일 기준 내림차순으로 정렬합니다.
    """
    try:
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")

        reviews_ref = db.collection("reviews")
        reviews_query = reviews_ref.where('place_name', '==', place_name).order_by('created_at', direction=firestore.Query.DESCENDING)

        place_reviews = []
        reviews_docs = reviews_query.stream()

        for doc in reviews_docs:
            review_data = doc.to_dict()

            # ▼▼▼ [수정] 데이터 유효성 검사 및 보강 코드 시작 ▼▼▼

            # 1. created_at 필드가 datetime 객체일 경우 문자열로 변환
            created_at_val = review_data.get("created_at")
            if isinstance(created_at_val, datetime):
                final_created_at = created_at_val.isoformat()
            elif isinstance(created_at_val, str):
                final_created_at = created_at_val
            else:
                final_created_at = "" # 값이 없거나 다른 타입이면 빈 문자열로 처리

            # 2. user_info를 위한 사용자 정보 조회
            user_id = review_data.get('user_id')
            user_info_data = {'username': '알 수 없는 사용자', 'profile_image_url': ''}
            if user_id:
                user_ref = db.collection(USERS_COLLECTION).document(user_id)
                user_doc = user_ref.get()
                if user_doc.exists:
                    user_data = user_doc.to_dict()
                    user_info_data['username'] = user_data.get('username', '알 수 없는 사용자')
                    user_info_data['profile_image_url'] = user_data.get('profile_image_url', '')

            # 3. Pydantic 모델에 맞게 데이터 구조화 (누락된 값에 대한 기본값 처리)
            full_review_data = {
                "review_id": review_data.get("review_id", f"missing_{doc.id}"), # review_id가 없으면 문서 ID로 대체
                "user_id": review_data.get("user_id", ""),
                "place_name": review_data.get("place_name", ""),
                "review_text": review_data.get("review_text", ""),
                "image_url": review_data.get("image_url"),
                "created_at": final_created_at, # 변환된 날짜 사용
                "score_earned": review_data.get("score_earned", 0),
                "user_info": user_info_data
            }
            place_reviews.append(full_review_data)
            # ▲▲▲ [수정] 데이터 유효성 검사 및 보강 코드 종료 ▲▲▲

        return place_reviews

    except Exception as e:
        print(f"ERROR: 장소별 리뷰 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"리뷰 조회 중 오류 발생: {e}")

@app.get("/reviews/user/{user_id}/place/{place_name}", response_model=List[PlaceReviewResponse])
async def get_user_reviews_for_place(user_id: str, place_name: str):
    """
    특정 사용자가 특정 장소에 대해 작성한 리뷰를 조회합니다.
    - 해당 사용자가 해당 장소에 대해 작성한 모든 리뷰를 반환
    - 작성자 정보(username, profile_image_url)를 포함
    - 생성일 기준 내림차순으로 정렬
    """
    try:
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")

        # 사용자 존재 여부 확인
        user_ref = db.collection(USERS_COLLECTION).document(user_id)
        user_doc = user_ref.get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")

        user_data = user_doc.to_dict()
        user_info_data = {
            'username': user_data.get('username', '알 수 없는 사용자'),
            'profile_image_url': user_data.get('profile_image_url', '')
        }

        # 특정 사용자의 특정 장소에 대한 리뷰 조회
        reviews_ref = db.collection("reviews")
        reviews_query = reviews_ref.where('user_id', '==', user_id).where('place_name', '==', place_name).order_by('created_at', direction=firestore.Query.DESCENDING)

        user_place_reviews = []
        reviews_docs = reviews_query.stream()

        for doc in reviews_docs:
            review_data = doc.to_dict()

            # created_at 필드 처리
            created_at_val = review_data.get("created_at")
            if isinstance(created_at_val, datetime):
                final_created_at = created_at_val.isoformat()
            elif isinstance(created_at_val, str):
                final_created_at = created_at_val
            else:
                final_created_at = ""

            # Pydantic 모델에 맞게 데이터 구조화
            full_review_data = {
                "review_id": review_data.get("review_id", f"missing_{doc.id}"),
                "user_id": review_data.get("user_id", ""),
                "place_name": review_data.get("place_name", ""),
                "review_text": review_data.get("review_text", ""),
                "image_url": review_data.get("image_url"),
                "created_at": final_created_at,
                "score_earned": review_data.get("score_earned", 0),
                "user_info": user_info_data
            }
            user_place_reviews.append(full_review_data)

        return user_place_reviews

    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR: 사용자별 장소 리뷰 조회 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"리뷰 조회 중 오류 발생: {e}")

# 🔥 [추가] 공유 기록 API 엔드포인트
@app.post("/shares/record")
async def record_share(request: ShareRecordRequest):
    """
    사용자의 공유 활동을 기록합니다.
    - review 문서의 share_count를 1 증가시킵니다.
    - 공유 퀘스트를 완료 상태로 업데이트합니다.
    """
    try:
        if not db:
            raise HTTPException(status_code=500, detail="데이터베이스 연결 실패")

        review_ref = db.collection("reviews").document(request.review_id)
        
        # Firestore 트랜잭션을 사용하여 안전하게 카운트 증가
        @firestore.transactional
        def update_share_count(transaction, ref):
            snapshot = ref.get(transaction=transaction)
            if not snapshot.exists:
                raise HTTPException(status_code=404, detail="공유하려는 리뷰를 찾을 수 없습니다.")
            
            transaction.update(ref, {
                'share_count': firestore.Increment(1)
            })
        
        transaction = db.transaction()
        update_share_count(transaction, review_ref)

        # 공유 퀘스트 완료 처리
        today = datetime.now().strftime('%Y-%m-%d')
        quests_ref = db.collection("daily_quests")
        
        # 오늘의 활성화된 공유 퀘스트 조회
        active_share_quests = quests_ref.where('user_id', '==', request.user_id).where('date', '==', today).where('type', '==', 'share_image').where('status', '==', 'active').get()
        
        completed_quests = []
        for quest_doc in active_share_quests:
            quest_data = quest_doc.to_dict()
            
            # 공유 퀘스트를 완료 상태로 업데이트
            quests_ref.document(quest_data['quest_id']).update({
                'is_completed': True,
                'status': 'reward_ready',
                'completed_at': firestore.SERVER_TIMESTAMP
            })
            
            quest_data['is_completed'] = True
            quest_data['status'] = 'reward_ready'
            quest_data['completed_at'] = datetime.now()
            completed_quests.append(quest_data)
            
            print(f"🔗 공유 퀘스트 완료! 사용자 {request.user_id}")
            print(f"   퀘스트: {quest_data['title']}")
            print(f"   보상: +{quest_data['points']}점")
            print(f"   ──────────────────────────────")

        print(f"🔗 공유 기록 완료: Review {request.review_id} by User {request.user_id}")
        print(f"   완료된 공유 퀘스트: {len(completed_quests)}개")
        return {"message": "공유가 성공적으로 기록되었습니다."}

    except HTTPException:
        raise # 이미 처리된 HTTP 예외는 다시 발생
    except Exception as e:
        print(f"ERROR: 공유 기록 중 오류 발생: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"공유 기록 중 서버 오류 발생: {e}")

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
# ▲▲▲ [신규] 사용자 성공 이미지 통계 조회 API 엔드포인트 추가 ▲▲▲

@app.get("/health")
async def health_check():
    """헬스체크 엔드포인트"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

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