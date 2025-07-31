#!/usr/bin/env python3
"""
성공 이미지 저장 및 조회 기능 테스트 스크립트
"""

import requests
import json
from PIL import Image
import io
import os

# 서버 URL
BASE_URL = "http://localhost:8000"

def load_test_image():
    """실제 경복궁 이미지 로드"""
    # 실제 경복궁 이미지 파일 경로
    image_path = r"C:\Users\fwdw9\Documents\tourist-data-analysis\review api and collection - 복사본\tourist-data-analysis-main\query_images\경복궁_7_공공3유형.jpg"
    
    try:
        # 이미지 파일 열기
        with open(image_path, 'rb') as img_file:
            img_byte_arr = io.BytesIO(img_file.read())
            img_byte_arr.seek(0)
        
        print(f"📸 실제 경복궁 이미지 로드 성공: {image_path}")
        return img_byte_arr
        
    except FileNotFoundError:
        print(f"❌ 이미지 파일을 찾을 수 없습니다: {image_path}")
        # 파일이 없을 경우 기본 테스트 이미지 생성
        img = Image.new('RGB', (100, 100), color='red')
        img_byte_arr = io.BytesIO()
        img.save(img_byte_arr, format='JPEG')
        img_byte_arr.seek(0)
        print("🔄 기본 테스트 이미지로 대체합니다.")
        return img_byte_arr
        
    except Exception as e:
        print(f"❌ 이미지 로드 중 오류 발생: {e}")
        # 오류 발생 시 기본 테스트 이미지 생성
        img = Image.new('RGB', (100, 100), color='red')
        img_byte_arr = io.BytesIO()
        img.save(img_byte_arr, format='JPEG')
        img_byte_arr.seek(0)
        print("🔄 기본 테스트 이미지로 대체합니다.")
        return img_byte_arr

def test_success_image_flow():
    """성공 이미지 저장 및 조회 전체 플로우 테스트"""
    print("🧪 성공 이미지 저장 및 조회 테스트 시작")
    print("📸 Firebase Storage 경로: /success_images/")
    print("⚠️  서버가 실행 중인지 확인하세요: python -m uvicorn api:app --host 0.0.0.0 --port 8000")
    print("=" * 50)
    
    # 1. 사용자 생성
    print("\n1️⃣ 사용자 생성 테스트")
    user_data = {
        "username": "test_user_success_images",
        "profile_image_url": None
    }
    
    response = requests.post(f"{BASE_URL}/create_user/", json=user_data)
    if response.status_code == 200:
        user_info = response.json()
        user_id = user_info['user_id']
        print(f"✅ 사용자 생성 성공: {user_id}")
    else:
        print(f"❌ 사용자 생성 실패: {response.text}")
        return
    
    # 2. 게임 세션 시작
    print("\n2️⃣ 게임 세션 시작 테스트")
    session_data = {
        "user_id": user_id,
        "target_places": ["경복궁", "남산서울타워"]
    }
    
    response = requests.post(f"{BASE_URL}/start_game/", json=session_data)
    if response.status_code == 200:
        session_info = response.json()
        session_id = session_info['session_id']
        print(f"✅ 게임 세션 시작 성공: {session_id}")
    else:
        print(f"❌ 게임 세션 시작 실패: {response.text}")
        return
    
    # 3. 이미지 업로드 및 예측 (정답 시나리오)
    print("\n3️⃣ 이미지 업로드 및 예측 테스트 (정답)")
    print("📸 실제 경복궁 이미지 사용")
    
    # 실제 경복궁 이미지 로드
    test_image = load_test_image()
    
    # 예측 요청 (경복궁 좌표 사용)
    files = {'image': ('test_image.jpg', test_image, 'image/jpeg')}
    data = {
        'session_id': session_id,
        'target_place': '경복궁',
        'latitude': 37.5796,  # 경복궁 좌표
        'longitude': 126.9770
    }
    
    response = requests.post(f"{BASE_URL}/predict/", files=files, data=data)
    if response.status_code == 200:
        prediction_result = response.json()
        print(f"✅ 예측 성공: {prediction_result['message']}")
        print(f"   정답 여부: {prediction_result['is_correct']}")
        print(f"   획득 점수: {prediction_result['score_earned']}")
        
        # 정답 여부에 따른 추가 정보 출력
        if prediction_result['is_correct']:
            print("   🎉 정답입니다! 이미지가 저장됩니다.")
        else:
            print("   ❌ 틀렸습니다. 이미지가 저장되지 않습니다.")
            print(f"   예측된 장소: {prediction_result.get('predictions', [{}])[0].get('place_kor', 'N/A')}")
    else:
        print(f"❌ 예측 실패: {response.text}")
        return
    
    # 4. 성공 이미지 조회
    print("\n4️⃣ 성공 이미지 조회 테스트")
    
    response = requests.get(f"{BASE_URL}/success_images/{user_id}")
    if response.status_code == 200:
        success_images = response.json()
        print(f"✅ 성공 이미지 조회 성공")
        print(f"   총 이미지 수: {success_images['total_count']}")
        print(f"   메시지: {success_images['message']}")
        
        if success_images['success_images']:
            for i, image in enumerate(success_images['success_images']):
                print(f"   이미지 {i+1}:")
                print(f"     장소: {image['place_name']}")
                print(f"     URL: {image['image_url']}")
                print(f"     점수: {image['score_earned']}")
        else:
            print("   📝 아직 성공 이미지가 없습니다.")
    else:
        print(f"❌ 성공 이미지 조회 실패: {response.text}")
    
    # 5. 성공 이미지 통계 조회
    print("\n5️⃣ 성공 이미지 통계 조회 테스트")
    
    response = requests.get(f"{BASE_URL}/success_images/{user_id}/stats")
    if response.status_code == 200:
        stats = response.json()
        print(f"✅ 성공 이미지 통계 조회 성공")
        print(f"   총 성공 횟수: {stats['total_success_count']}")
        print(f"   총 획득 점수: {stats['total_score_earned']}")
        print(f"   장소별 통계: {stats['place_stats']}")
    else:
        print(f"❌ 성공 이미지 통계 조회 실패: {response.text}")
    
    # 6. 사용자 프로필 조회 (이미지 URL 포함)
    print("\n6️⃣ 사용자 프로필 조회 테스트 (이미지 URL 포함)")
    
    response = requests.get(f"{BASE_URL}/user_profile/{user_id}")
    if response.status_code == 200:
        profile = response.json()
        print(f"✅ 사용자 프로필 조회 성공")
        print(f"   사용자명: {profile['username']}")
        print(f"   총 점수: {profile['total_score']}")
        print(f"   방문 기록 수: {len(profile['visit_history'])}")
        
        # 이미지가 있는 방문 기록 확인
        image_visits = [v for v in profile['visit_history'] if v.get('image_url')]
        print(f"   이미지가 있는 방문 기록: {len(image_visits)}개")
        
        for visit in image_visits:
            print(f"     - {visit['target_place']}: {visit['image_url']}")
    else:
        print(f"❌ 사용자 프로필 조회 실패: {response.text}")
    
    print("\n" + "=" * 50)
    print("🎉 성공 이미지 저장 및 조회 테스트 완료!")

if __name__ == "__main__":
    try:
        test_success_image_flow()
    except Exception as e:
        print(f"❌ 테스트 중 오류 발생: {e}")
        import traceback
        traceback.print_exc() 