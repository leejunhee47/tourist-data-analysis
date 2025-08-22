import requests
import json
import time
from datetime import datetime

# API 서버 URL
BASE_URL = "http://localhost:8000"

def test_admin_login():
    """
    어드민 로그인 테스트
    """
    print("🔐 어드민 로그인 테스트 시작")
    print("=" * 50)
    
    # 테스트 케이스들
    test_cases = [
        {
            "name": "올바른 어드민 계정",
            "data": {"username": "admin", "password": "admin"},
            "expected_status": 200
        },
        {
            "name": "잘못된 비밀번호",
            "data": {"username": "admin", "password": "wrong_password"},
            "expected_status": 401
        },
        {
            "name": "잘못된 사용자명",
            "data": {"username": "wrong_admin", "password": "admin"},
            "expected_status": 401
        },
        {
            "name": "빈 사용자명",
            "data": {"username": "", "password": "admin"},
            "expected_status": 401
        },
        {
            "name": "빈 비밀번호",
            "data": {"username": "admin", "password": ""},
            "expected_status": 401
        }
    ]
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n 테스트 케이스 {i}: {test_case['name']}")
        print(f"   입력 데이터: {test_case['data']}")
        
        try:
            response = requests.post(
                f"{BASE_URL}/admin_login/",
                json=test_case['data'],
                headers={"Content-Type": "application/json"}
            )
            
            print(f"   상태 코드: {response.status_code}")
            
            if response.status_code == test_case['expected_status']:
                print("   ✅ 예상 결과와 일치")
                
                if response.status_code == 200:
                    result = response.json()
                    print(f"   응답 데이터: {json.dumps(result, indent=2, ensure_ascii=False)}")
                    
                    # 응답 데이터 검증
                    required_fields = ["user_id", "username", "is_admin", "message"]
                    for field in required_fields:
                        if field in result:
                            print(f"   ✅ {field} 필드 존재")
                        else:
                            print(f"   ❌ {field} 필드 누락")
                else:
                    print(f"   에러 메시지: {response.text}")
            else:
                print(f"   ❌ 예상 결과와 불일치 (예상: {test_case['expected_status']})")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ 요청 실패: {e}")
        except Exception as e:
            print(f"   ❌ 예상치 못한 오류: {e}")
    
    print("\n" + "=" * 50)

def test_guest_login():
    """
    게스트 로그인 테스트
    """
    print("👤 게스트 로그인 테스트 시작")
    print("=" * 50)
    
    # 여러 번 테스트하여 매번 새로운 계정이 생성되는지 확인
    for i in range(3):
        print(f"\n📋 게스트 로그인 테스트 {i+1}")
        
        try:
            response = requests.post(
                f"{BASE_URL}/guest_login/",
                headers={"Content-Type": "application/json"}
            )
            
            print(f"   상태 코드: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                print(f"   응답 데이터: {json.dumps(result, indent=2, ensure_ascii=False)}")
                
                # 응답 데이터 검증
                required_fields = ["user_id", "username", "is_guest", "message"]
                for field in required_fields:
                    if field in result:
                        print(f"   ✅ {field} 필드 존재")
                    else:
                        print(f"   ❌ {field} 필드 누락")
                
                # 게스트 ID 형식 검증 (guest-YYYYMMDDHHMMSS)
                user_id = result.get("user_id", "")
                if user_id.startswith("guest-") and len(user_id) == 20:  # 20자로 수정
                    print("   ✅ 게스트 ID 형식 올바름")
                else:
                    print(f"   ❌ 게스트 ID 형식 오류: {user_id} (길이: {len(user_id)})")
                
                # 게스트 사용자명 형식 검증 (게스트-MMDDHHMMSSXX)
                username = result.get("username", "")
                if username.startswith("게스트-") and len(username) == 16:  # 16자로 수정
                    print("   ✅ 게스트 사용자명 형식 올바름")
                else:
                    print(f"   ❌ 게스트 사용자명 형식 오류: {username} (길이: {len(username)})")
                
                # 추가 검증: 시간 형식 확인
                try:
                    # user_id에서 시간 부분 추출 (guest-YYYYMMDDHHMMSS)
                    time_part = user_id[6:]  # "guest-" 제거
                    if len(time_part) == 14:  # YYYYMMDDHHMMSS = 14자
                        print("   ✅ 게스트 ID 시간 형식 올바름")
                    else:
                        print(f"   ❌ 게스트 ID 시간 형식 오류: {time_part}")
                except:
                    print("   ❌ 게스트 ID 시간 형식 파싱 실패")
                
            else:
                print(f"   ❌ 요청 실패: {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ 요청 실패: {e}")
        except Exception as e:
            print(f"   ❌ 예상치 못한 오류: {e}")
        
        # 테스트 간 간격
        if i < 2:
            time.sleep(1)
    
    print("\n" + "=" * 50)

def test_create_user():
    """
    일반 사용자 생성 테스트 (카카오 로그인용)
    """
    print("👤 일반 사용자 생성 테스트 시작")
    print("=" * 50)
    
    # 테스트 케이스들
    test_cases = [
        {
            "name": "새로운 사용자 생성",
            "data": {
                "username": f"테스트사용자_{int(time.time())}",
                "profile_image_url": "https://example.com/profile1.jpg"
            }
        },
        {
            "name": "기존 사용자 조회 (프로필 이미지 업데이트)",
            "data": {
                "username": "기존사용자",
                "profile_image_url": "https://example.com/profile2.jpg"
            }
        },
        {
            "name": "프로필 이미지 없는 사용자",
            "data": {
                "username": f"이미지없음사용자_{int(time.time())}",
                "profile_image_url": None
            }
        },
        {
            "name": "빈 사용자명",
            "data": {
                "username": "",
                "profile_image_url": "https://example.com/profile3.jpg"
            }
        }
    ]
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n�� 테스트 케이스 {i}: {test_case['name']}")
        print(f"   입력 데이터: {test_case['data']}")
        
        try:
            response = requests.post(
                f"{BASE_URL}/create_user/",
                json=test_case['data'],
                headers={"Content-Type": "application/json"}
            )
            
            print(f"   상태 코드: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                print(f"   응답 데이터: {json.dumps(result, indent=2, ensure_ascii=False)}")
                
                # 응답 데이터 검증
                required_fields = ["user_id", "username", "message"]
                for field in required_fields:
                    if field in result:
                        print(f"   ✅ {field} 필드 존재")
                    else:
                        print(f"   ❌ {field} 필드 누락")
                
                # user_id 형식 검증 (UUID)
                user_id = result.get("user_id", "")
                if len(user_id) == 36 and user_id.count("-") == 4:
                    print("   ✅ user_id 형식 올바름 (UUID)")
                else:
                    print(f"   ❌ user_id 형식 오류: {user_id}")
                
            else:
                print(f"   ❌ 요청 실패: {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ 요청 실패: {e}")
        except Exception as e:
            print(f"   ❌ 예상치 못한 오류: {e}")
    
    print("\n" + "=" * 50)

def test_login_integration():
    """
    로그인 통합 테스트 - 실제 시나리오 테스트
    """
    print("🔄 로그인 통합 테스트 시작")
    print("=" * 50)
    
    # 1. 어드민 로그인
    print("\n1️⃣ 어드민 로그인")
    admin_response = requests.post(
        f"{BASE_URL}/admin_login/",
        json={"username": "admin", "password": "admin"}
    )
    
    if admin_response.status_code == 200:
        admin_data = admin_response.json()
        print(f"   ✅ 어드민 로그인 성공: {admin_data['user_id']}")
        
        # 어드민 계정으로 다시 로그인 (기존 계정 조회)
        admin_response2 = requests.post(
            f"{BASE_URL}/admin_login/",
            json={"username": "admin", "password": "admin"}
        )
        
        if admin_response2.status_code == 200:
            admin_data2 = admin_response2.json()
            if admin_data2['user_id'] == admin_data['user_id']:
                print("   ✅ 어드민 계정 재사용 확인")
            else:
                print("   ❌ 어드민 계정 재사용 실패")
    else:
        print("   ❌ 어드민 로그인 실패")
    
    # 2. 게스트 로그인 (여러 번)
    print("\n2️⃣ 게스트 로그인 (새 계정 생성 확인)")
    guest_ids = []
    
    for i in range(3):
        guest_response = requests.post(f"{BASE_URL}/guest_login/")
        
        if guest_response.status_code == 200:
            guest_data = guest_response.json()
            guest_ids.append(guest_data['user_id'])
            print(f"   게스트 {i+1}: {guest_data['user_id']} ({guest_data['username']})")
        else:
            print(f"   ❌ 게스트 로그인 {i+1} 실패")
    
    # 게스트 ID 중복 확인
    if len(guest_ids) == len(set(guest_ids)):
        print("   ✅ 모든 게스트 계정이 고유함")
    else:
        print("   ❌ 게스트 계정 중복 발견")
    
    # 3. 일반 사용자 생성
    print("\n3️⃣ 일반 사용자 생성")
    test_username = f"통합테스트사용자_{int(time.time())}"
    
    user_response = requests.post(
        f"{BASE_URL}/create_user/",
        json={
            "username": test_username,
            "profile_image_url": "https://example.com/integration_test.jpg"
        }
    )
    
    if user_response.status_code == 200:
        user_data = user_response.json()
        print(f"   ✅ 사용자 생성 성공: {user_data['user_id']}")
        
        # 동일한 사용자명으로 다시 생성 (기존 사용자 조회)
        user_response2 = requests.post(
            f"{BASE_URL}/create_user/",
            json={
                "username": test_username,
                "profile_image_url": "https://example.com/updated_profile.jpg"
            }
        )
        
        if user_response2.status_code == 200:
            user_data2 = user_response2.json()
            if user_data2['user_id'] == user_data['user_id']:
                print("   ✅ 기존 사용자 조회 확인")
            else:
                print("   ❌ 기존 사용자 조회 실패")
    else:
        print("   ❌ 사용자 생성 실패")
    
    print("\n" + "=" * 50)

def main():
    """
    모든 테스트 실행
    """
    print("🚀 로그인 API 테스트 시작")
    print(f"📅 테스트 시작 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"🌐 서버 URL: {BASE_URL}")
    
    try:
        # 서버 연결 확인
        response = requests.get(f"{BASE_URL}/docs")
        if response.status_code == 200:
            print("✅ 서버 연결 성공")
        else:
            print("❌ 서버 연결 실패")
            return
    except requests.exceptions.RequestException as e:
        print(f"❌ 서버 연결 실패: {e}")
        return
    
    print("\n" + "=" * 60)
    
    # 각 테스트 실행
    test_admin_login()
    test_guest_login()
    test_create_user()
    test_login_integration()
    
    print("\n🎉 모든 테스트 완료!")
    print(f"📅 테스트 종료 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    main()
