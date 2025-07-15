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
from firebase_admin import firestore
from firebase_config import initialize_firebase, USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION
from fastapi.staticfiles import StaticFiles

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

# 임시 이미지 저장 폴더 생성
TEMP_DIR = "temp_images"
os.makedirs(TEMP_DIR, exist_ok=True)

# CLIP-LoRA 모델 초기화
inferencer = CLIPLoRAInference()

# Pydantic 모델들
class UserCreate(BaseModel):
    username: str

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
                guest_user_ref.set({
                    'user_id': TEST_GUEST_USER_ID,
                    'username': TEST_GUEST_USERNAME,
                    'total_score': 0,
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
            existing_user_data = user_list[0].to_dict()
            print(f"기존 사용자 발견: {existing_user_data['user_id']}")
            return {
                "user_id": existing_user_data['user_id'], 
                "username": existing_user_data['username'], 
                "message": "기존 사용자를 성공적으로 조회했습니다."
            }
        
        user_id = str(uuid.uuid4())
        user_ref = users_ref.document(user_id)
        
        user_ref.set({
            'user_id': user_id,
            'username': user_data.username,
            'total_score': 0,
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
    
    # 1) 타깃 관광지 좌표 확인
    if target_place not in inferencer.place_coords:
        raise HTTPException(status_code=400, detail="알 수 없는 타깃 관광지입니다.")
    target_lat, target_lon = inferencer.place_coords[target_place]

    # 2) 거리 계산 (CLIPLoRAInference.calculate_distance는 km 단위 반환)
    distance_km = inferencer.calculate_distance(latitude, longitude, target_lat, target_lon)
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
        
        # 임시 파일 삭제
        os.remove(temp_image_path)
        
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
        score_earned = 10 if is_correct else 0
        
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
            
            # 방문 기록 저장
            visit_id = str(uuid.uuid4())
            visit_ref = db.collection(VISITS_COLLECTION).document(visit_id)
            
            transaction.set(visit_ref, {
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
            })
            
            return new_session_score
        
        # 세션에서 사용자 ID 가져오기
        session_ref = db.collection(GAME_SESSIONS_COLLECTION).document(session_id)
        session = session_ref.get()
        
        if not session.exists:
            raise HTTPException(status_code=404, detail="게임 세션을 찾을 수 없습니다.")
        
        user_id = session.to_dict()['user_id']
        
        # 트랜잭션 실행
        update_in_transaction(transaction, session_id, user_id)
        
        message = f"정답! +{score_earned}점" if is_correct else f"틀렸습니다. 예측: {predicted_place}, 타깃: {target_place}"
        
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
        
        # ▼▼▼ [핵심 수정 사항] 트랜잭션 함수에서 점수 합산 로직 제거 ▼▼▼
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
            
            # 사용자 총점 업데이트 로직 제거 (이미 predict에서 실시간 처리됨)
            
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
            rankings.append({
                "rank": rank,
                "username": user_data['username'],
                "total_score": user_data['total_score'],
                "user_id": user_data['user_id']
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
            visit_history.append({
                "target_place": visit_data['target_place'],
                "predicted_place": visit_data['predicted_place'],
                "is_correct": visit_data['is_correct'],
                "score_earned": visit_data['score_earned'],
                "visit_time": visit_data['visit_time']
            })
        
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
        for name, (lat, lon) in inferencer.place_coords.items():
            places_data.append(Place(name=name, latitude=lat, longitude=lon))
        
        return PlacesResponse(places=places_data)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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