#!/usr/bin/env python3
"""
실제 관광지 이미지를 사용한 API 테스트

실제 관광지 사진으로 점수 시스템이 제대로 작동하는지 테스트합니다.
"""

import requests
import os

BASE_URL = "http://localhost:8000"

def test_with_real_images():
    """실제 관광지 이미지로 테스트"""
    print("🎮 실제 관광지 이미지 테스트 시작!")
    print("=" * 50)
    
    # 1. 사용자 생성
    user_data = {"username": "실제이미지테스터"}
    response = requests.post(f"{BASE_URL}/create_user/", json=user_data)
    
    if response.status_code != 200:
        print(f"❌ 사용자 생성 실패: {response.text}")
        return
    
    user_id = response.json()["user_id"]
    print(f"✅ 사용자 생성: {user_id}")
    
    # 2. 게임 시작
    game_data = {
        "user_id": user_id,
        "target_places": ["경복궁", "남산서울타워", "북촌한옥마을", "광화문", "경희궁", "청계천"]
    }
    
    response = requests.post(f"{BASE_URL}/start_game/", json=game_data)
    if response.status_code != 200:
        print(f"❌ 게임 시작 실패: {response.text}")
        return
    
    session_id = response.json()["session_id"]
    print(f"✅ 게임 시작: {session_id}")
    
    # 3. 실제 이미지 테스트
    test_cases = [
        {
            "image_file": "경복궁_7_공공3유형.jpg",
            "target_place": "경복궁",
            "latitude": 37.5796,
            "longitude": 126.9770,
            "description": "경복궁 실제 사진"
        },
        {
            "image_file": "남산서울타워_1004093.jpg", 
            "target_place": "남산서울타워",
            "latitude": 37.5511,
            "longitude": 126.9882,
            "description": "남산서울타워 실제 사진"
        },
        {
            "image_file": "북촌한옥마을_6_공공3유형.jpg",
            "target_place": "북촌한옥마을", 
            "latitude": 37.5825,
            "longitude": 126.9849,
            "description": "북촌한옥마을 실제 사진"
        },
        {
            "image_file": "광화문.jpg",
            "target_place": "광화문",
            "latitude": 37.5725,
            "longitude": 126.9768,
            "description": "광화문 실제 사진"
        },
        {
            "image_file": "경희궁 흥화문_7_공공3유형.JPG",
            "target_place": "경희궁",
            "latitude": 37.5704,
            "longitude": 126.9682,
            "description": "경희궁 실제 사진"
        },
        {
            "image_file": "청계천_3_공공3유형.JPG",
            "target_place": "청계천",
            "latitude": 37.5697,
            "longitude": 126.9975,
            "description": "청계천 실제 사진"
        }
    ]
    
    total_score = 0
    correct_predictions = 0
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n📸 테스트 {i}: {test_case['description']}")
        print(f"   이미지: {test_case['image_file']}")
        print(f"   타깃: {test_case['target_place']}")
        print(f"   위치: {test_case['latitude']}, {test_case['longitude']}")
        
        image_path = os.path.join("query_images", test_case['image_file'])
        
        if not os.path.exists(image_path):
            print(f"   ❌ 이미지 파일을 찾을 수 없습니다: {image_path}")
            continue
        
        try:
            # 이미지 파일 읽기
            with open(image_path, 'rb') as f:
                image_file = f.read()
            
            # API 요청
            files = {'image': (test_case['image_file'], image_file, 'image/jpeg')}
            data = {
                'session_id': session_id,
                'target_place': test_case['target_place'],
                'latitude': test_case['latitude'],
                'longitude': test_case['longitude']
            }
            
            response = requests.post(f"{BASE_URL}/predict/", files=files, data=data)
            
            if response.status_code == 200:
                result = response.json()
                
                if result['predictions']:
                    predicted = result['predictions'][0]['place_kor']
                    confidence = result['predictions'][0]['confidence']
                    
                    print(f"   🔍 AI 예측: {predicted} (신뢰도: {confidence:.1f}%)")
                    
                    if result['is_correct']:
                        print(f"   🎉 정답! +{result['score_earned']}점")
                        correct_predictions += 1
                    else:
                        print(f"   😅 틀렸습니다. 점수 변화 없음")
                    
                    total_score += result['score_earned']
                    
                    # 상위 3개 예측 결과 표시
                    print("   📊 상위 예측 결과:")
                    for j, pred in enumerate(result['predictions'][:3], 1):
                        print(f"      {j}. {pred['place_kor']}: {pred['confidence']:.1f}%")
                else:
                    print("   ❌ 예측 실패")
            else:
                print(f"   ❌ API 요청 실패: {response.status_code}")
                
        except Exception as e:
            print(f"   ❌ 오류 발생: {e}")
        
        print("-" * 40)
    
    # 4. 게임 종료
    print(f"\n🏁 테스트 완료!")
    response = requests.post(f"{BASE_URL}/end_game/{session_id}")
    
    if response.status_code == 200:
        final_score = response.json()['final_score']
        print(f"✅ 게임 종료! 최종 점수: {final_score}점")
    
    # 5. 결과 요약
    print(f"\n📊 테스트 결과 요약:")
    print(f"   총 테스트: {len(test_cases)}개")
    print(f"   정답: {correct_predictions}개")
    print(f"   정답률: {correct_predictions/len(test_cases)*100:.1f}%")
    print(f"   총 점수: {total_score}점")
    
    # 6. 랭킹 확인
    print(f"\n🏆 현재 랭킹:")
    response = requests.get(f"{BASE_URL}/rankings/?limit=5")
    if response.status_code == 200:
        rankings = response.json()['rankings']
        for ranking in rankings:
            print(f"   {ranking['rank']}위: {ranking['username']} - {ranking['total_score']}점")

if __name__ == "__main__":
    try:
        # 서버 연결 확인
        response = requests.get(f"{BASE_URL}/rankings/")
        if response.status_code == 200:
            print("✅ 서버 연결 성공!")
            test_with_real_images()
        else:
            print("❌ 서버에 연결할 수 없습니다.")
            print("서버를 먼저 실행하세요: python api.py")
    
    except requests.exceptions.ConnectionError:
        print("❌ 서버에 연결할 수 없습니다.")
        print("서버를 먼저 실행하세요: python api.py")
    except Exception as e:
        print(f"❌ 오류 발생: {e}") 