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

def is_cloud_environment():
    """클라우드 환경인지 확인하는 함수"""
    # 1. Cloud Run 환경 변수 확인
    if os.getenv('K_SERVICE') or os.getenv('PORT'):
        return True
    
    # 2. Google Cloud 환경 변수 확인
    if os.getenv('GOOGLE_CLOUD_PROJECT') and os.getenv('GOOGLE_APPLICATION_CREDENTIALS') is None:
        return True
    
    # 3. App Engine 환경 확인
    if os.getenv('GAE_ENV'):
        return True
    
    # 4. Compute Engine 환경 확인
    if os.path.exists('/etc/google_cloud'):
        return True
    
    return False

def get_firebase_credentials():
    """Firebase 서비스 계정 키를 가져오는 함수"""
    # 환경 감지
    is_cloud = is_cloud_environment()
    print(f"🌍 환경 감지: {'클라우드' if is_cloud else '로컬'}")
    
    if is_cloud:
        # 클라우드 환경: Secret Manager 사용
        print("☁️ 클라우드 환경 - Secret Manager에서 Firebase 키 로드")
        try:
            client = secretmanager.SecretManagerServiceClient()
            project_id = get_project_id()
            secret_name = f"projects/{project_id}/secrets/tourapi-firebase-key/versions/latest"
            response = client.access_secret_version(request={"name": secret_name})
            secret_data = response.payload.data.decode("UTF-8")
            service_account_info = json.loads(secret_data)
            return credentials.Certificate(service_account_info)
        except Exception as e:
            print(f"❌ Secret Manager 접근 실패: {e}")
            raise Exception("클라우드 환경에서 Firebase 자격 증명을 가져올 수 없습니다.")
    else:
        # 로컬 환경: 파일 또는 환경 변수 사용
        print("💻 로컬 환경 - 파일에서 Firebase 키 로드")
        
        # 1. 환경 변수로 지정된 서비스 계정 키 파일 사용
        service_account_path = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
        if service_account_path and os.path.exists(service_account_path):
            print(f"✅ 환경 변수 지정 파일 사용: {service_account_path}")
            return credentials.Certificate(service_account_path)
        
        # 2. 프로젝트 내 Firebase 키 파일 직접 사용
        current_dir = os.path.dirname(os.path.abspath(__file__))
        firebase_key_path = os.path.join(current_dir, "tourapi-77ca1-firebase-adminsdk-fbsvc-3caf24d515.json")
        
        if os.path.exists(firebase_key_path):
            print(f"✅ 프로젝트 내 Firebase 키 파일 사용: {firebase_key_path}")
            return credentials.Certificate(firebase_key_path)
        
        # 3. 환경 변수에서 직접 JSON 문자열 사용
        firebase_key_json = os.getenv('FIREBASE_SERVICE_ACCOUNT_KEY')
        if firebase_key_json:
            try:
                service_account_info = json.loads(firebase_key_json)
                print("✅ 환경 변수에서 Firebase 키 로드")
                return credentials.Certificate(service_account_info)
            except json.JSONDecodeError as e:
                print(f"❌ Firebase 키 JSON 파싱 오류: {e}")
        
        # 4. 모든 방법 실패
        raise Exception("로컬 환경에서 Firebase 자격 증명을 찾을 수 없습니다. 다음 중 하나를 확인해주세요:\n" +
                       "1. GOOGLE_APPLICATION_CREDENTIALS 환경 변수 설정\n" +
                       "2. 프로젝트 내 Firebase 키 파일 존재 확인\n" +
                       "3. FIREBASE_SERVICE_ACCOUNT_KEY 환경 변수 설정")

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