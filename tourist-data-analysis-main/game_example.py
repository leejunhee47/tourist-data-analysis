#!/usr/bin/env python3
"""
관광지 사진 랭킹 게임 예제

이 스크립트는 API를 사용하여 간단한 게임 플로우를 시연합니다.
실제 사용 시에는 모바일 앱이나 웹 인터페이스에서 사용하게 됩니다.
"""

import requests
import json
from PIL import Image
import io

BASE_URL = "http://localhost:8000"

def create_game_user(username):
    """새 사용자 생성"""
    print(f"👤 사용자 '{username}' 생성 중...")
    
    response = requests.post(f"{BASE_URL}/create_user/", json={"username": username})
    
    if response.status_code == 200:
        user_data = response.json()
        print(f"✅ 사용자 생성 완료: {user_data['user_id']}")
        return user_data['user_id']
    else:
        print(f"❌ 사용자 생성 실패: {response.text}")
        return None

def start_tour_game(user_id, target_places):
    """관광 게임 시작"""
    print(f"🎮 게임 시작! 타깃 관광지: {', '.join(target_places)}")
    
    game_data = {
        "user_id": user_id,
        "target_places": target_places
    }
    
    response = requests.post(f"{BASE_URL}/start_game/", json=game_data)
    
    if response.status_code == 200:
        session_data = response.json()
        print(f"✅ 게임 세션 생성: {session_data['session_id']}")
        return session_data['session_id']
    else:
        print(f"❌ 게임 시작 실패: {response.text}")
        return None

def take_photo_at_location(session_id, target_place, latitude, longitude, image_path=None):
    """관광지에서 사진 촬영 시뮬레이션"""
    print(f"📸 {target_place}에서 사진 촬영 중... (위도: {latitude}, 경도: {longitude})")
    
    # 실제 이미지가 없는 경우 더미 이미지 생성
    if image_path is None:
        print("⚠️ 테스트용 더미 이미지 생성")
        dummy_image = Image.new('RGB', (224, 224), color='lightblue')
        img_byte_arr = io.BytesIO()
        dummy_image.save(img_byte_arr, format='JPEG')
        image_file = img_byte_arr.getvalue()
        filename = f"dummy_{target_place}.jpg"
    else:
        with open(image_path, 'rb') as f:
            image_file = f.read()
        filename = image_path.split('/')[-1]
    
    # API 요청
    files = {'image': (filename, image_file, 'image/jpeg')}
    data = {
        'session_id': session_id,
        'target_place': target_place,
        'latitude': latitude,
        'longitude': longitude
    }
    
    response = requests.post(f"{BASE_URL}/predict/", files=files, data=data)
    
    if response.status_code == 200:
        result = response.json()
        
        # 결과 출력
        predicted = result['predictions'][0]['place_kor'] if result['predictions'] else 'Unknown'
        confidence = result['predictions'][0]['confidence'] if result['predictions'] else 0
        
        print(f"🔍 AI 예측: {predicted} (신뢰도: {confidence:.1f}%)")
        print(f"🎯 타깃: {target_place}")
        
        if result['is_correct']:
            print(f"🎉 정답! +{result['score_earned']}점 획득!")
        else:
            print(f"😅 틀렸습니다. 점수 변화 없음")
        
        print(f"💬 {result['message']}")
        return result
    else:
        print(f"❌ 사진 분석 실패: {response.text}")
        return None

def end_tour_game(session_id):
    """여행 게임 종료"""
    print("🏁 여행 종료 중...")
    
    response = requests.post(f"{BASE_URL}/end_game/{session_id}")
    
    if response.status_code == 200:
        result = response.json()
        print(f"✅ 게임 종료! 최종 점수: {result['final_score']}점")
        return result['final_score']
    else:
        print(f"❌ 게임 종료 실패: {response.text}")
        return 0

def show_rankings():
    """현재 랭킹 표시"""
    print("\n🏆 현재 랭킹:")
    print("=" * 40)
    
    response = requests.get(f"{BASE_URL}/rankings/?limit=10")
    
    if response.status_code == 200:
        rankings = response.json()['rankings']
        
        if not rankings:
            print("아직 랭킹 데이터가 없습니다.")
            return
        
        for ranking in rankings:
            print(f"{ranking['rank']:2d}위. {ranking['username']:<15} {ranking['total_score']:3d}점")
    else:
        print(f"❌ 랭킹 조회 실패: {response.text}")

def show_user_profile(user_id, username):
    """사용자 프로필 표시"""
    print(f"\n👤 {username}님의 프로필:")
    print("=" * 40)
    
    response = requests.get(f"{BASE_URL}/user_profile/{user_id}")
    
    if response.status_code == 200:
        profile = response.json()
        
        print(f"총점: {profile['total_score']}점")
        print(f"방문 기록: {len(profile['visit_history'])}회")
        
        if profile['visit_history']:
            print("\n최근 방문 기록:")
            for visit in profile['visit_history'][:5]:  # 최근 5개만
                status = "✅" if visit['is_correct'] else "❌"
                print(f"  {status} {visit['target_place']} -> {visit['predicted_place']} ({visit['score_earned']}점)")
    else:
        print(f"❌ 프로필 조회 실패: {response.text}")

def run_game_simulation():
    """전체 게임 시뮬레이션 실행"""
    print("🎮 관광지 사진 랭킹 게임 시뮬레이션")
    print("=" * 50)
    
    # 1. 사용자 생성
    username = "테스트여행자"
    user_id = create_game_user(username)
    if not user_id:
        return
    
    # 2. 게임 시작
    target_places = ["경복궁", "남산서울타워", "북촌한옥마을"]
    session_id = start_tour_game(user_id, target_places)
    if not session_id:
        return
    
    print("\n" + "="*50)
    print("🗺️  서울 관광지 투어 시작!")
    print("="*50)
    
    # 3. 각 관광지 방문 시뮬레이션
    tour_locations = [
        {
            "place": "경복궁",
            "lat": 37.5796,
            "lon": 126.9770,
            "description": "조선 왕조의 첫 번째 궁궐"
        },
        {
            "place": "남산서울타워",
            "lat": 37.5511,
            "lon": 126.9882,
            "description": "서울의 상징적인 타워"
        },
        {
            "place": "북촌한옥마을",
            "lat": 37.5825,
            "lon": 126.9849,
            "description": "전통 한옥이 보존된 마을"
        }
    ]
    
    total_score = 0
    
    for i, location in enumerate(tour_locations, 1):
        print(f"\n📍 {i}번째 목적지: {location['place']}")
        print(f"   {location['description']}")
        print(f"   GPS: {location['lat']}, {location['lon']}")
        
        result = take_photo_at_location(
            session_id, 
            location['place'], 
            location['lat'], 
            location['lon']
        )
        
        if result:
            total_score += result['score_earned']
        
        print(f"   현재 누적 점수: {total_score}점")
        print("-" * 30)
    
    # 4. 게임 종료
    print(f"\n🏁 모든 관광지 방문 완료!")
    final_score = end_tour_game(session_id)
    
    # 5. 결과 확인
    show_user_profile(user_id, username)
    show_rankings()
    
    print(f"\n🎉 게임 완료! 최종 점수: {final_score}점")
    print("감사합니다! 다음에 또 놀러오세요! 👋")

if __name__ == "__main__":
    try:
        # 서버 연결 확인
        response = requests.get(f"{BASE_URL}/rankings/")
        if response.status_code == 200:
            print("✅ 서버 연결 성공!")
            run_game_simulation()
        else:
            print("❌ 서버에 연결할 수 없습니다.")
            print("서버를 먼저 실행하세요: python api.py")
    
    except requests.exceptions.ConnectionError:
        print("❌ 서버에 연결할 수 없습니다.")
        print("서버를 먼저 실행하세요: python api.py")
    except Exception as e:
        print(f"❌ 오류 발생: {e}") 