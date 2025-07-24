from fastapi.testclient import TestClient
from api import app
import os
import requests
import json
from PIL import Image
import io
import base64
import time

# 테스트 클라이언트 생성
client = TestClient(app)

# 관광지별 좌표
PLACE_COORDINATES = {
    '경복궁': (37.5796, 126.9770),
    '경희궁': (37.5704, 126.9682),
    '광화문': (37.5725, 126.9768),
    '남산서울타워': (37.5511, 126.9882),
    '북촌한옥마을': (37.5825, 126.9849),
    '청계천': (37.56961, 127.0059)
}

# API 서버 URL
BASE_URL = "http://localhost:8000"

def check_server_connection(max_retries=5, delay=2):
    """서버 연결 확인 (재시도 로직 포함)"""
    for attempt in range(max_retries):
        try:
            print(f"서버 연결 시도 {attempt + 1}/{max_retries}...")
            response = requests.get(f"{BASE_URL}/rankings/", timeout=10)
            if response.status_code == 200:
                print("✅ 서버 연결 성공!")
                return True
            else:
                print(f"⚠️ 서버 응답 코드: {response.status_code}")
        except requests.exceptions.ConnectionError:
            print(f"❌ 연결 실패 (시도 {attempt + 1}/{max_retries})")
        except requests.exceptions.Timeout:
            print(f"❌ 연결 타임아웃 (시도 {attempt + 1}/{max_retries})")
        except Exception as e:
            print(f"❌ 예상치 못한 오류: {e}")
        
        if attempt < max_retries - 1:
            print(f"⏰ {delay}초 후 재시도...")
            time.sleep(delay)
    
    return False

def get_place_from_filename(filename):
    """파일명에서 관광지명 추출"""
    filename = filename.lower()
    for place in PLACE_COORDINATES.keys():
        if place.lower() in filename:
            return place
    return None

def test_predict_endpoint():
    """모든 테스트 이미지로 예측 테스트"""
    query_folder = "query_images"
    
    if not os.path.exists(query_folder):
        print(f"❌ 쿼리 이미지 폴더를 찾을 수 없습니다: {query_folder}")
        return
    
    # 테스트 결과 통계
    total_tests = 0
    successful_tests = 0
    
    # 모든 이미지 파일 테스트
    for filename in os.listdir(query_folder):
        if not filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            continue
            
        place_name = get_place_from_filename(filename)
        if not place_name:
            print(f"\n⚠️ 건너뜀: {filename} - 관광지를 인식할 수 없습니다.")
            continue
        
        test_image = os.path.join(query_folder, filename)
        total_tests += 1
        
        # 해당 관광지의 좌표 가져오기
        latitude, longitude = PLACE_COORDINATES[place_name]
        
        print(f"\n📸 테스트 #{total_tests} 정보:")
        print(f"이미지: {filename}")
        print(f"관광지: {place_name}")
        print(f"좌표: ({latitude}, {longitude})")
        
        # API 호출
        try:
            with open(test_image, "rb") as f:
                response = client.post(
                    "/predict/",
                    files={"image": (filename, f, "image/jpeg")},
                    data={
                        "latitude": latitude,
                        "longitude": longitude
                    }
                )
            
            # 응답 확인
            print(f"상태 코드: {response.status_code}")
            
            if response.status_code != 200:
                print(f"❌ API 호출 실패: 상태 코드 {response.status_code}")
                continue
                
            if "predictions" not in response.json():
                print("❌ API 응답에 predictions가 없습니다.")
                continue
            
            # 예측 결과 출력
            predictions = response.json()["predictions"]
            print("\n📊 예측 결과:")
            for i, pred in enumerate(predictions, 1):
                print(f"{i}. {pred['place_kor']}")
                print(f"   - 신뢰도: {pred['confidence']:.2f}%")
                print(f"   - 거리: {pred['distance']:.2f}km")
            
            # 첫 번째 예측이 실제 장소와 일치하는지 확인
            if predictions and predictions[0]['place_kor'] == place_name:
                print(f"✅ 정확도 테스트 통과: 예측 결과가 실제 장소와 일치")
                successful_tests += 1
            else:
                print(f"❌ 정확도 테스트 실패: 예측된 장소가 실제 장소와 불일치")
                
        except Exception as e:
            print(f"❌ 테스트 중 오류 발생: {str(e)}")
    
    # 최종 테스트 결과 출력
    print("\n📋 테스트 결과 요약:")
    print(f"총 테스트 수: {total_tests}")
    print(f"성공한 테스트: {successful_tests}")
    print(f"정확도: {(successful_tests/total_tests*100):.1f}% ({successful_tests}/{total_tests})")

def test_missing_coordinates():
    """좌표 없는 경우 테스트"""
    query_folder = "query_images"
    test_image = None
    
    for filename in os.listdir(query_folder):
        if filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            test_image = os.path.join(query_folder, filename)
            break
    
    if test_image is None:
        print("❌ 테스트할 이미지를 찾을 수 없습니다.")
        return
    
    with open(test_image, "rb") as f:
        response = client.post(
            "/predict/",
            files={"image": (os.path.basename(test_image), f, "image/jpeg")}
        )
    
    print("\n✅ 좌표 누락 테스트:")
    print(f"상태 코드: {response.status_code}")
    
    assert response.status_code == 422  # FastAPI 유효성 검사 오류

def test_create_user():
    """사용자 생성 테스트 (중복 사용자명 자동 처리)"""
    print("=== 사용자 생성 테스트 ===")
    
    base_username = "테스트유저"
    username_number = 1
    max_attempts = 100  # 무한 루프 방지
    
    for attempt in range(max_attempts):
        username = f"{base_username}{username_number}"
        user_data = {
            "username": username
        }
        
        try:
            response = requests.post(f"{BASE_URL}/create_user/", json=user_data, timeout=10)
            
            if response.status_code == 200:
                result = response.json()
                print(f"✅ 사용자 생성 성공: {result}")
                return result["user_id"]
            elif response.status_code == 400 and "이미 존재합니다" in response.text:
                print(f"⚠️ 사용자명 '{username}' 이미 존재, 다음 번호로 시도...")
                username_number += 1
            else:
                print(f"❌ 사용자 생성 실패: {response.status_code}, {response.text}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"❌ 사용자 생성 요청 실패: {e}")
            return None
    
    print(f"❌ {max_attempts}번 시도 후에도 고유한 사용자명을 찾을 수 없습니다.")
    return None

def test_start_game(user_id):
    """게임 세션 시작 테스트"""
    print("\n=== 게임 세션 시작 테스트 ===")
    
    game_data = {
        "user_id": user_id,
        "target_places": ["경복궁", "남산서울타워", "북촌한옥마을"]
    }
    
    try:
        response = requests.post(f"{BASE_URL}/start_game/", json=game_data, timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 게임 시작 성공: {result}")
            return result["session_id"]
        else:
            print(f"❌ 게임 시작 실패: {response.status_code}, {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"❌ 게임 시작 요청 실패: {e}")
        return None

def test_predict_with_scoring(session_id, target_place="경복궁"):
    """점수 시스템이 포함된 예측 테스트"""
    print(f"\n=== 점수 시스템 예측 테스트 (타깃: {target_place}) ===")
    
    # query_images 폴더의 모든 이미지 가져오기
    query_folder = "query_images"
    
    if not os.path.exists(query_folder):
        print(f"❌ 쿼리 이미지 폴더를 찾을 수 없습니다: {query_folder}")
        return None
    
    total_tests = 0
    successful_tests = 0
    
    # 해당 관광지의 이미지만 필터링
    target_images = [f for f in os.listdir(query_folder) if target_place.lower() in f.lower() and f.lower().endswith(('.jpg', '.jpeg', '.png'))]
    
    if not target_images:
        print(f"⚠️ {target_place}에 대한 테스트 이미지를 찾을 수 없습니다.")
        return None
    
    print(f"📸 {len(target_images)}개의 테스트 이미지를 찾았습니다.")
    
    for image_name in target_images:
        total_tests += 1
        image_path = os.path.join(query_folder, image_name)
        print(f"\n테스트 {total_tests}/{len(target_images)}: {image_name}")
        
        try:
            # 이미지 파일 읽기
            with open(image_path, 'rb') as f:
                image_file = f.read()
            
            # 테스트용 GPS 좌표 설정
            latitude, longitude = PLACE_COORDINATES.get(target_place, (37.5796, 126.9770))
            
            # API 요청
            files = {
                'image': (image_name, image_file, 'image/jpeg')
            }
            
            data = {
                'session_id': session_id,
                'target_place': target_place,
                'latitude': latitude,
                'longitude': longitude
            }
            
            response = requests.post(f"{BASE_URL}/predict/", files=files, data=data, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                predicted_place = result['predictions'][0]['place_kor'] if result['predictions'] else 'None'
                is_correct = result['is_correct']
                score_earned = result['score_earned']
                
                status = "✅" if is_correct else "❌"
                print(f"{status} 예측 결과: {predicted_place}")
                print(f"   신뢰도: {result['predictions'][0]['confidence']:.2f}%")
                print(f"   획득 점수: {score_earned}점")
                
                if is_correct:
                    successful_tests += 1
                
            else:
                print(f"❌ 예측 실패: {response.status_code}, {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"❌ 예측 요청 실패: {e}")
        except Exception as e:
            print(f"❌ 테스트 중 오류 발생: {e}")
    
    # 최종 결과 출력
    success_rate = (successful_tests / total_tests * 100) if total_tests > 0 else 0
    print(f"\n📊 테스트 결과 요약 ({target_place}):")
    print(f"   총 테스트: {total_tests}개")
    print(f"   성공: {successful_tests}개")
    print(f"   정확도: {success_rate:.1f}%")
    
    return {
        "total_tests": total_tests,
        "successful_tests": successful_tests,
        "success_rate": success_rate
    }

def test_end_game(session_id):
    """게임 종료 테스트"""
    print(f"\n=== 게임 종료 테스트 ===")
    
    try:
        response = requests.post(f"{BASE_URL}/end_game/{session_id}", timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 게임 종료 성공: {result}")
            return result
        else:
            print(f"❌ 게임 종료 실패: {response.status_code}, {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"❌ 게임 종료 요청 실패: {e}")
        return None

def test_get_rankings():
    """랭킹 조회 테스트"""
    print("\n=== 랭킹 조회 테스트 ===")
    
    try:
        response = requests.get(f"{BASE_URL}/rankings/?limit=5", timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            print("✅ 랭킹 조회 성공:")
            for ranking in result["rankings"]:
                print(f"   {ranking['rank']}위: {ranking['username']} - {ranking['total_score']}점")
            return result
        else:
            print(f"❌ 랭킹 조회 실패: {response.status_code}, {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"❌ 랭킹 조회 요청 실패: {e}")
        return None

def test_get_user_profile(user_id):
    """사용자 프로필 조회 테스트"""
    print(f"\n=== 사용자 프로필 조회 테스트 ===")
    
    try:
        response = requests.get(f"{BASE_URL}/user_profile/{user_id}", timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 프로필 조회 성공:")
            print(f"   사용자명: {result['username']}")
            print(f"   총점: {result['total_score']}점")
            print(f"   방문 기록 수: {len(result['visit_history'])}개")
            
            if result['visit_history']:
                print("   최근 방문 기록:")
                for visit in result['visit_history'][:3]:  # 최근 3개만 표시
                    status = "✅" if visit['is_correct'] else "❌"
                    print(f"     {status} {visit['target_place']} -> {visit['predicted_place']} ({visit['score_earned']}점)")
            
            return result
        else:
            print(f"❌ 프로필 조회 실패: {response.status_code}, {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"❌ 프로필 조회 요청 실패: {e}")
        return None

def run_full_game_test():
    """전체 게임 플로우 테스트"""
    print("🎮 전체 게임 플로우 테스트 시작!")
    print("=" * 50)
    
    # 1. 사용자 생성
    user_id = test_create_user()
    if not user_id:
        print("❌ 사용자 생성 실패로 테스트를 중단합니다.")
        return
    
    # 2. 게임 시작
    session_id = test_start_game(user_id)
    if not session_id:
        print("❌ 게임 시작 실패로 테스트를 중단합니다.")
        return
    
    # 3. 모든 관광지에 대해 테스트
    total_results = {}
    for target_place in PLACE_COORDINATES.keys():
        result = test_predict_with_scoring(session_id, target_place)
        if result:
            total_results[target_place] = result
    
    # 전체 결과 요약
    if total_results:
        print("\n📊 전체 테스트 결과 요약:")
        print("=" * 30)
        total_tests = sum(r['total_tests'] for r in total_results.values())
        total_successes = sum(r['successful_tests'] for r in total_results.values())
        overall_success_rate = (total_successes / total_tests * 100) if total_tests > 0 else 0
        
        for place, result in total_results.items():
            print(f"{place}:")
            print(f"  - 테스트: {result['total_tests']}개")
            print(f"  - 성공: {result['successful_tests']}개")
            print(f"  - 정확도: {result['success_rate']:.1f}%")
        
        print("\n총 결과:")
        print(f"  - 전체 테스트: {total_tests}개")
        print(f"  - 전체 성공: {total_successes}개")
        print(f"  - 전체 정확도: {overall_success_rate:.1f}%")
    
    # 4. 게임 종료
    end_result = test_end_game(session_id)
    
    # 5. 랭킹 조회
    test_get_rankings()
    
    # 6. 사용자 프로필 조회
    test_get_user_profile(user_id)
    
    print("\n🎉 전체 테스트 완료!")

def test_multiple_users():
    """여러 사용자 랭킹 테스트"""
    print("\n🏆 여러 사용자 랭킹 테스트")
    print("=" * 50)
    
    users = []
    
    # 여러 사용자 생성 및 게임 진행
    for i in range(3):
        print(f"\n--- 사용자 {i+1} 테스트 ---")
        
        # 사용자 생성 (중복 처리)
        base_username = "테스트유저"
        username_number = i + 1
        user_created = False
        
        for attempt in range(50):  # 최대 50번 시도
            username = f"{base_username}{username_number}"
            user_data = {"username": username}
            
            try:
                response = requests.post(f"{BASE_URL}/create_user/", json=user_data, timeout=10)
                
                if response.status_code == 200:
                    user_created = True
                    break
                elif response.status_code == 400 and "이미 존재합니다" in response.text:
                    print(f"⚠️ '{username}' 이미 존재, 다음 번호로 시도...")
                    username_number += 1
                else:
                    print(f"❌ 사용자 생성 실패: {response.status_code}")
                    break
            except requests.exceptions.RequestException as e:
                print(f"❌ 사용자 생성 요청 실패: {e}")
                break
        
        if not user_created:
            print(f"❌ 사용자 {i+1} 생성 실패")
            continue
        
        if response.status_code == 200:
            user_info = response.json()
            user_id = user_info["user_id"]
            users.append(user_id)
            
            # 게임 시작
            game_data = {
                "user_id": user_id,
                "target_places": ["경복궁", "남산서울타워"]
            }
            
            try:
                session_response = requests.post(f"{BASE_URL}/start_game/", json=game_data, timeout=10)
                
                if session_response.status_code == 200:
                    session_id = session_response.json()["session_id"]
                    
                    # 랜덤하게 몇 개 정답 맞추기 (시뮬레이션)
                    correct_count = i + 1  # 사용자별로 다른 점수
                    
                    for j in range(correct_count):
                        # 더미 예측 (실제로는 이미지 업로드 필요)
                        print(f"  사용자 {i+1}의 {j+1}번째 예측...")
                    
                    # 게임 종료
                    try:
                        requests.post(f"{BASE_URL}/end_game/{session_id}", timeout=10)
                    except requests.exceptions.RequestException:
                        pass
            except requests.exceptions.RequestException as e:
                print(f"❌ 게임 시작 요청 실패: {e}")
    
    # 최종 랭킹 확인
    print("\n🏆 최종 랭킹:")
    test_get_rankings()

if __name__ == "__main__":
    print("🚀 관광지 사진 랭킹 시스템 API 테스트")
    print("=" * 60)
    
    # 서버 연결 확인
    if check_server_connection():
        print("서버 연결이 확인되었습니다. 테스트를 시작합니다.\n")
        
        # 전체 게임 플로우 테스트
        run_full_game_test()
        
    else:
        print("\n❌ 서버에 연결할 수 없습니다.")
        print("해결 방법:")
        print("1. 서버가 실행 중인지 확인: python api.py")
        print("2. 포트 8000이 다른 프로세스에서 사용 중인지 확인")
        print("3. 방화벽 설정 확인")
        print("4. 서버 로그에서 오류 메시지 확인")