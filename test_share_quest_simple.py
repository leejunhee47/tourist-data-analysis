#!/usr/bin/env python3
"""
기존 공유 기능을 이용한 공유 퀘스트 테스트
- 실제 리뷰를 생성한 후 공유 기능을 테스트
"""

import requests
import json
import time
from datetime import datetime

# 테스트 설정
BASE_URL = "http://localhost:8000"
TEST_USER_ID = f"test_user_share_quest_{int(time.time())}"  # 매번 새로운 사용자 ID 생성
TEST_PLACE_NAME = "경복궁"
TEST_REVIEW_TEXT = "아름다운 경복궁을 방문했습니다. 한국의 전통 건축물의 아름다움을 느낄 수 있었어요."

def print_step(step_num, title):
    """테스트 단계 출력"""
    print(f"\n{'='*50}")
    print(f"📋 단계 {step_num}: {title}")
    print(f"{'='*50}")

def print_success(message):
    """성공 메시지 출력"""
    print(f"✅ {message}")

def print_error(message):
    """오류 메시지 출력"""
    print(f"❌ {message}")

def print_info(message):
    """정보 메시지 출력"""
    print(f"ℹ️  {message}")

def print_warning(message):
    """경고 메시지 출력"""
    print(f"⚠️  {message}")

def create_test_user():
    """1. 테스트 사용자 생성"""
    print_step(1, "테스트 사용자 생성")
    
    try:
        url = f"{BASE_URL}/create_user/"
        data = {
            "username": f"테스트사용자_{TEST_USER_ID}",
            "profile_image_url": ""
        }
        
        print_info("사용자 생성 API 호출 중...")
        print(f"   사용자명: {data['username']}")
        
        response = requests.post(url, json=data)
        
        if response.status_code == 200:
            result = response.json()
            user_id = result.get('user_id')
            print_success("사용자 생성 성공!")
            print(f"   사용자 ID: {user_id}")
            return user_id
        else:
            print_error(f"사용자 생성 실패: {response.status_code}")
            print(f"   응답: {response.text}")
            return None
            
    except Exception as e:
        print_error(f"사용자 생성 중 오류: {e}")
        return None

def create_daily_quests(user_id):
    """2. 일일 퀘스트 생성"""
    print_step(2, "일일 퀘스트 생성")
    
    try:
        url = f"{BASE_URL}/quests/{user_id}"
        
        print_info("일일 퀘스트 생성 API 호출 중...")
        
        response = requests.get(url)
        
        if response.status_code == 200:
            result = response.json()
            quests = result.get('quests', [])
            print_success("일일 퀘스트 생성 성공!")
            print(f"   총 퀘스트 수: {len(quests)}개")
            
            # 공유 퀘스트 찾기
            share_quests = []
            for quest in quests:
                if quest.get('type') == 'share_image':
                    share_quests.append(quest)
                    print(f"   📱 공유 퀘스트: {quest.get('title')}")
                    print(f"      상태: {quest.get('status')}")
                    print(f"      보상: +{quest.get('points', 0)}점")
            
            if not share_quests:
                print_warning("공유 퀘스트가 생성되지 않았습니다.")
            
            return share_quests
        else:
            print_error(f"일일 퀘스트 생성 실패: {response.status_code}")
            print(f"   응답: {response.text}")
            return []
            
    except Exception as e:
        print_error(f"일일 퀘스트 생성 중 오류: {e}")
        return []

def create_test_review(user_id):
    """3. 테스트 리뷰 생성"""
    print_step(3, "테스트 리뷰 생성")
    
    try:
        url = f"{BASE_URL}/reviews/"
        
        # 폼 데이터로 리뷰 생성
        data = {
            'user_id': user_id,
            'place_name': TEST_PLACE_NAME,
            'review_text': TEST_REVIEW_TEXT
        }
        
        print_info("리뷰 생성 API 호출 중...")
        print(f"   장소: {TEST_PLACE_NAME}")
        print(f"   리뷰 내용: {TEST_REVIEW_TEXT[:30]}...")
        
        response = requests.post(url, data=data)
        
        if response.status_code == 200:
            result = response.json()
            review_id = result.get('review_id')
            print_success("리뷰 생성 성공!")
            print(f"   리뷰 ID: {review_id}")
            print(f"   획득 점수: +{result.get('score_earned', 0)}점")
            return review_id
        else:
            print_error(f"리뷰 생성 실패: {response.status_code}")
            print(f"   응답: {response.text}")
            return None
            
    except Exception as e:
        print_error(f"리뷰 생성 중 오류: {e}")
        return None

def test_share_record_api(user_id, review_id):
    """4. 공유 기록 API 테스트"""
    print_step(4, "공유 기록 API 테스트")
    
    try:
        # 공유 기록 API 호출 (실제 카카오톡 공유 후 호출되는 API)
        url = f"{BASE_URL}/shares/record"
        data = {
            "user_id": user_id,
            "review_id": review_id,
            "platform": "kakao"
        }
        
        print_info("API 요청 전송 중...")
        print(f"   URL: {url}")
        print(f"   데이터: {json.dumps(data, indent=2, ensure_ascii=False)}")
        
        response = requests.post(url, json=data)
        
        if response.status_code == 200:
            print_success("공유 기록 API 호출 성공!")
            print(f"   응답: {response.json()}")
            return True
        else:
            print_error(f"API 호출 실패: {response.status_code}")
            print(f"   응답: {response.text}")
            return False
            
    except Exception as e:
        print_error(f"API 호출 중 오류: {e}")
        return False

def test_quest_status_after_share(user_id):
    """5. 공유 후 퀘스트 상태 확인"""
    print_step(5, "공유 후 퀘스트 상태 확인")
    
    try:
        # 퀘스트 상태 조회 API 호출
        url = f"{BASE_URL}/quests/{user_id}"
        
        print_info("퀘스트 상태 조회 중...")
        
        response = requests.get(url)
        
        if response.status_code == 200:
            result = response.json()
            quests = result.get('quests', [])
            print_success("퀘스트 상태 조회 성공!")
            print(f"   총 퀘스트 수: {len(quests)}개")
            
            # 공유 퀘스트 찾기
            share_quests = []
            for quest in quests:
                if quest.get('type') == 'share_image':
                    share_quests.append(quest)
                    print(f"   📱 공유 퀘스트: {quest.get('title')}")
                    print(f"      상태: {quest.get('status')}")
                    print(f"      완료 여부: {quest.get('is_completed', False)}")
                    print(f"      보상: +{quest.get('points', 0)}점")
            
            if not share_quests:
                print("   공유 퀘스트를 찾을 수 없습니다.")
                print("   일일 퀘스트가 생성되지 않았거나 공유 퀘스트가 포함되지 않았을 수 있습니다.")
            
            return share_quests
        else:
            print_error(f"퀘스트 상태 조회 실패: {response.status_code}")
            print(f"   응답: {response.text}")
            return []
            
    except Exception as e:
        print_error(f"퀘스트 상태 조회 중 오류: {e}")
        return []

def test_claim_share_quest_reward(user_id, share_quests):
    """6. 공유 퀘스트 보상 수령"""
    print_step(6, "공유 퀘스트 보상 수령")
    
    if not share_quests:
        print_error("수령할 공유 퀘스트가 없습니다.")
        return False
    
    try:
        # 완료된 공유 퀘스트 찾기
        completed_quests = [q for q in share_quests if q.get('status') == 'reward_ready']
        
        if not completed_quests:
            print_info("수령할 보상이 있는 공유 퀘스트가 없습니다.")
            return False
        
        # 첫 번째 완료된 퀘스트의 보상 수령
        quest = completed_quests[0]
        quest_id = quest.get('quest_id')
        
        url = f"{BASE_URL}/quests/reward"
        data = {
            "user_id": user_id,
            "quest_id": quest_id
        }
        
        print_info("보상 수령 API 호출 중...")
        print(f"   퀘스트 ID: {quest_id}")
        print(f"   퀘스트 제목: {quest.get('title')}")
        
        response = requests.post(url, json=data)
        
        if response.status_code == 200:
            result = response.json()
            print_success("보상 수령 성공!")
            print(f"   획득 점수: +{result.get('result', {}).get('reward_points', 0)}점")
            print(f"   총 점수: {result.get('result', {}).get('completed_count', 0)}점")
            return True
        else:
            print_error(f"보상 수령 실패: {response.status_code}")
            print(f"   응답: {response.text}")
            return False
            
    except Exception as e:
        print_error(f"보상 수령 중 오류: {e}")
        return False

def test_flutter_share_integration():
    """7. Flutter 앱에서 공유 기능 테스트 가이드"""
    print_step(7, "Flutter 앱 공유 기능 테스트 가이드")
    
    print_info("Flutter 앱에서 공유 퀘스트를 테스트하려면:")
    print()
    print("1. Flutter 앱 실행:")
    print("   cd flutter_test1")
    print("   flutter run")
    print()
    print("2. 앱에서 다음 순서로 테스트:")
    print("   - 로그인 후 지도 페이지로 이동")
    print("   - 관광지를 방문하고 리뷰 작성")
    print("   - '나의 리뷰' 버튼 클릭")
    print("   - 리뷰 상세 보기에서 '카카오톡 공유하기' 버튼 클릭")
    print("   - 카카오톡에서 공유 완료 후 앱으로 복귀")
    print("   - 퀘스트 창에서 '이미지 공유하기' 퀘스트 완료 확인")
    print("   - 보상 수령 버튼 클릭")
    print()
    print("3. 예상 결과:")
    print("   - 공유 후 퀘스트 상태가 'reward_ready'로 변경")
    print("   - +20점 보상 수령 가능")
    print("   - 총 점수에 20점 추가")

def run_simple_test():
    """간단한 테스트 실행"""
    print("🚀 카카오톡 공유 후 앱 복귀 시 퀘스트 완료 기능 테스트")
    print(f"📅 테스트 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"👤 테스트 사용자: {TEST_USER_ID}")
    print(f"🏛️  테스트 장소: {TEST_PLACE_NAME}")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        print_error("테스트 중단: 사용자 생성 실패")
        return
    
    # 잠시 대기
    print("\n⏳ 1초 대기 중...")
    time.sleep(1)
    
    # 2. 일일 퀘스트 생성 및 확인
    share_quests = create_daily_quests(user_id)
    if not share_quests:
        print_warning("일일 퀘스트 생성 실패 또는 공유 퀘스트가 없습니다. 테스트를 진행할 수 없습니다.")
        return
    
    # 잠시 대기
    print("\n⏳ 1초 대기 중...")
    time.sleep(1)
    
    # 3. 테스트 리뷰 생성
    review_id = create_test_review(user_id)
    if not review_id:
        print_error("테스트 중단: 리뷰 생성 실패")
        return
    
    # 잠시 대기
    print("\n⏳ 1초 대기 중...")
    time.sleep(1)
    
    # 4. 공유 기록 API 테스트
    if not test_share_record_api(user_id, review_id):
        print_error("테스트 중단: 공유 기록 API 실패")
        return
    
    # 잠시 대기
    print("\n⏳ 2초 대기 중...")
    time.sleep(2)
    
    # 5. 퀘스트 상태 확인
    share_quests = test_quest_status_after_share(user_id)
    
    # 6. 보상 수령 테스트
    if share_quests:
        test_claim_share_quest_reward(user_id, share_quests)
    
    # 7. Flutter 앱 테스트 가이드
    test_flutter_share_integration()
    
    print("\n🎉 테스트 완료!")
    print("✅ 카카오톡 공유 후 앱 복귀 시 퀘스트 완료 기능 테스트가 완료되었습니다.")
    print(f"📊 최종 결과:")
    print(f"   - 사용자 ID: {user_id}")
    print(f"   - 리뷰 ID: {review_id}")
    print(f"   - 공유 퀘스트 수: {len(share_quests)}개")

if __name__ == "__main__":
    run_simple_test() 