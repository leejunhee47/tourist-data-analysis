import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path
import os
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

def initialize_firebase():
    """Firebase 초기화 함수"""
    try:
        # 이미 초기화되었는지 확인
        if not firebase_admin._apps:
            # 현재 스크립트의 디렉토리 기준으로 Firebase 서비스 계정 키 경로 설정
            current_dir = Path(__file__).parent
            service_account_path = current_dir / "tourapi-77ca1-firebase-adminsdk-fbsvc-3caf24d515.json"

            # Firebase 서비스 계정 키 경로
            cred = credentials.Certificate(str(service_account_path))

            # Firebase 서비스 계정 키 경로
            #cred = credentials.Certificate("tourapi-77ca1-firebase-adminsdk-fbsvc-3caf24d515.json")
            
            # Firebase 초기화
            firebase_admin.initialize_app(cred)
        
        # Firestore 데이터베이스 클라이언트 반환
        db = firestore.client()
        return db
    except Exception as e:
        print(f"Firebase 초기화 중 오류 발생: {e}")
        return None

# Firestore 컬렉션 이름 상수
USERS_COLLECTION = 'users'
GAME_SESSIONS_COLLECTION = 'game_sessions'
VISITS_COLLECTION = 'visits' 