import firebase_admin
from firebase_admin import credentials, firestore
import os
import json
from dotenv import load_dotenv
from google.cloud import secretmanager

# 환경 변수 로드
load_dotenv()

def get_project_id():
    """Google Cloud 프로젝트 ID를 가져오는 함수"""
    # 1. 환경 변수에서 가져오기 (Cloud Run에서 자동 설정)
    project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
    if project_id:
        return project_id
    
    # 2. gcloud CLI에서 가져오기
    try:
        import subprocess
        result = subprocess.run(['gcloud', 'config', 'get-value', 'project'], 
                              capture_output=True, text=True, check=True)
        project_id = result.stdout.strip()
        if project_id and project_id != '(unset)':
            return project_id
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    
    # 3. 기본값 사용 (실제 프로젝트 ID로 변경 필요)
    return 'tourapi-77ca1'  # 실제 프로젝트 ID로 변경하세요

def get_firebase_credentials():
    """Secret Manager에서 Firebase 서비스 계정 키를 가져오는 함수"""
    # Secret Manager 클라이언트 생성
    client = secretmanager.SecretManagerServiceClient()
    
    # 프로젝트 ID 가져오기
    project_id = get_project_id()
    
    # 비밀 이름 구성
    secret_name = f"projects/{project_id}/secrets/tourapi-firebase-key/versions/latest"
    
    # 비밀 값 가져오기
    response = client.access_secret_version(request={"name": secret_name})
    secret_data = response.payload.data.decode("UTF-8")
    
    # JSON 문자열을 딕셔너리로 변환
    service_account_info = json.loads(secret_data)
    
    return credentials.Certificate(service_account_info)

def initialize_firebase():
    """Firebase 초기화 함수"""
    try:
        # 이미 초기화되었는지 확인
        if not firebase_admin._apps:
            # Secret Manager에서 Firebase 자격 증명 가져오기
            cred = get_firebase_credentials()
            
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