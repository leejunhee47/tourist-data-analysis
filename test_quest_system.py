#!/usr/bin/env python3
"""
퀘스트 시스템 테스트 스크립트 (테마 퀘스트 클리어 버전)
- 광화문, 남산서울타워, 독립문 방문으로 3개 테마 퀘스트 클리어
- 방문 점수 30점 + 퀘스트 보상 60점 = 총 90점 테스트
"""

import requests
import json
from datetime import datetime
import time
import os

# API 서버 URL (로컬에서 실행 중인 경우)
BASE_URL = "http://localhost:8000"

def create_test_user():
    """테스트용 사용자를 생성합니다."""
    print("👤 테스트 사용자 생성 중...")
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    username = f"퀘스트클리어테스터_{timestamp}"
    
    user_data = {"username": username}
    response = requests.post(f"{BASE_URL}/create_user/", json=user_data)
    
    if response.status_code != 200:
        print(f"❌ 사용자 생성 실패: {response.text}")
        return None
    
    user_info = response.json()
    user_id = user_info["user_id"]
    print(f"✅ 테스트 사용자 생성: {user_info['username']} (ID: {user_id})")
    
    return user_id

def get_user_score(user_id):
    """사용자의 현재 점수를 조회합니다."""
    try:
        response = requests.get(f"{BASE_URL}/user_profile/{user_id}")
        if response.status_code == 200:
            profile_data = response.json()
            return profile_data['total_score']
        else:
            print(f"❌ 점수 조회 실패: {response.text}")
            return 0
    except Exception as e:
        print(f"❌ 점수 조회 중 오류: {e}")
        return 0

def visit_place(user_id, target_place):
    """특정 관광지를 방문하는 함수 (방문지별로 맞는 이미지를 사용)"""
    print(f"\n📍 {target_place} 방문 시도...")
    try:
        # 1. 게임 세션 시작
        session_data = {
            "user_id": user_id,
            "target_places": [target_place]
        }
        session_response = requests.post(f"{BASE_URL}/start_game/", json=session_data)
        if session_response.status_code != 200:
            print(f"   ❌ 게임 세션 시작 실패: {session_response.text}")
            return False
        session_info = session_response.json()
        session_id = session_info["session_id"]

        # 2. 관광지 좌표 설정 (실제 좌표 사용)
        place_coordinates = {
            "경복궁": (37.5796, 126.9770),
            "경희궁": (37.5704, 126.9682),
            "광화문": (37.5725, 126.9768),
            "남산서울타워": (37.5511, 126.9882),
            "북촌한옥마을": (37.5825, 126.9849),
            "청계천": (37.56961, 127.0059),
            "독립문": (37.5725, 126.9595),
            "서울도서관": (37.5664, 126.9780)
        }
        target_lat, target_lon = place_coordinates[target_place]

        # 3. 관광지별 테스트 이미지 매핑
        place_image_map = {
            "경복궁": r"E:\Download\tourist-data-analysis-frontend-api (6)\tourist-data-analysis-frontend-api\tourist-data-analysis-main\query_images\경복궁_7_공공3유형.jpg",
            "경희궁": r"E:\Download\tourist-data-analysis-frontend-api (6)\tourist-data-analysis-frontend-api\tourist-data-analysis-main\query_images\경희궁 흥화문_7_공공3유형.JPG",
            "광화문": r"E:\Download\tourist-data-analysis-frontend-api (6)\tourist-data-analysis-frontend-api\tourist-data-analysis-main\query_images\광화문.jpg"
        }
        test_image_path = place_image_map.get(target_place, None)
        if not test_image_path or not os.path.exists(test_image_path):
            print(f"   ❌ 테스트 이미지 파일이 없습니다: {test_image_path}")
            return False

        # 4. 방문 전 점수 확인
        before_score = get_user_score(user_id)
        print(f"   방문 전 점수: {before_score}점")

        # 5. /predict/ 엔드포인트 호출
        with open(test_image_path, 'rb') as image_file:
            files = {'image': image_file}
            data = {
                'session_id': session_id,
                'target_place': target_place,
                'latitude': target_lat,
                'longitude': target_lon
            }
            predict_response = requests.post(f"{BASE_URL}/predict/", files=files, data=data)
            if predict_response.status_code == 200:
                predict_result = predict_response.json()
                if predict_result['is_correct']:
                    print(f"   ✅ 방문 성공!")
                    print(f"   획득 점수: +{predict_result['score_earned']}점")
                    time.sleep(1)  # 점수 업데이트 대기
                    after_score = get_user_score(user_id)
                    print(f"   방문 후 점수: {after_score}점")
                    print(f"   점수 변화: +{after_score - before_score}점")
                    return True
                else:
                    print(f"   ❌ 방문 실패: {predict_result['message']}")
                    return False
            else:
                print(f"   ❌ 방문 처리 실패: {predict_response.text}")
                return False
        # 6. 게임 세션 종료
        end_response = requests.post(f"{BASE_URL}/end_game/{session_id}")
    except Exception as e:
        print(f"   ❌ 방문 처리 중 오류: {e}")
        return False


def check_quest_completion(user_id, target_place):
    """특정 관광지 방문 후 퀘스트 완료 상태를 확인합니다."""
    try:
        response = requests.get(f"{BASE_URL}/quests/{user_id}")
        if response.status_code == 200:
            quests_data = response.json()
            quests = quests_data["quests"]
            
            # 해당 관광지가 포함된 테마 미션 찾기
            completed_quests = []
            for quest in quests:
                if (quest['type'] == 'theme_mission' and 
                    quest['status'] == 'reward_ready' and
                    target_place in quest.get('completed_places', [])):
                    completed_quests.append(quest)
            
            return completed_quests
        else:
            print(f"   ❌ 퀘스트 조회 실패: {response.text}")
            return []
    except Exception as e:
        print(f"   ❌ 퀘스트 확인 중 오류: {e}")
        return []


def test_theme_quest_clear():
    """테마 퀘스트 클리어 테스트 - 총 90점 달성"""
    print("=== 테마 퀘스트 클리어 테스트 시작 ===\n")
    print("🎯 목표: 광화문, 남산서울타워, 독립문 방문으로 3개 테마 퀘스트 클리어")
    print("📊 예상 점수: 방문 30점 + 퀘스트 보상 60점 = 총 90점\n")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        print("❌ 테스트 사용자 생성 실패")
        return
    
    # 2. 초기 점수 확인
    print(f"\n📊 초기 점수 확인...")
    initial_score = get_user_score(user_id)
    print(f"초기 총점: {initial_score}점")
    
    # 3. 테마 퀘스트 생성 확인
    print(f"\n🎯 테마 퀘스트 생성 확인...")
    response = requests.get(f"{BASE_URL}/quests/{user_id}")
    if response.status_code == 200:
        quests_data = response.json()
        quests = quests_data["quests"]
        theme_missions = [q for q in quests if q['type'] == 'theme_mission']
        print(f"생성된 테마 미션: {len(theme_missions)}개")
        for i, quest in enumerate(theme_missions, 1):
            print(f"  {i}. {quest.get('theme_name', '알 수 없음')}: {quest.get('target_places', [])}")
            print()
    
    # 4. 테스트할 관광지 목록
    test_places = ["광화문", "남산서울타워", "독립문"]
    
    # 5. 각 관광지 방문 및 퀘스트 완료 확인
    successful_visits = 0
    all_completed_quests = []
    
    for i, place in enumerate(test_places, 1):
        print(f"\n{'='*60}")
        print(f"방문 {i}/3: {place}")
        print(f"{'='*60}")
        
        # 방문 시도
        if visit_place(user_id, place):
            successful_visits += 1
            
            # 퀘스트 완료 확인
            print(f"\n🎯 {place} 방문 후 퀘스트 완료 확인...")
            completed_quests = check_quest_completion(user_id, place)
            
            if completed_quests:
                print(f"   ✅ {len(completed_quests)}개 테마 미션 완료!")
                for quest in completed_quests:
                    print(f"   - {quest.get('theme_name', '알 수 없음')}: +{quest['points']}점")
                all_completed_quests.extend(completed_quests)
            else:
                print(f"   📍 퀘스트 진행 중...")
        else:
            print(f"   ❌ {place} 방문 실패")
        
        # 방문 간 대기
        if i < len(test_places):
            print(f"\n⏳ 다음 방문까지 대기 중...")
            time.sleep(3)
    
    # 6. 중복 제거 (같은 퀘스트가 여러 번 포함될 수 있음)
    unique_quests = []
    seen_quest_ids = set()
    for quest in all_completed_quests:
        if quest['quest_id'] not in seen_quest_ids:
            unique_quests.append(quest)
            seen_quest_ids.add(quest['quest_id'])
    
    print(f"\n{'='*60}")
    print(f"🎁 퀘스트 보상 지급")
    print(f"{'='*60}")
    
    # 7. 퀘스트 보상 지급 (단계별 점수 추적)
    before_reward_score = get_user_score(user_id)
    print(f"보상 지급 전 점수: {before_reward_score}점")
    print(f"완료된 퀘스트: {len(unique_quests)}개")
    
    # 각 퀘스트별로 단계별 점수 추적
    step_scores = []
    current_score = before_reward_score
    
    for i, quest in enumerate(unique_quests, 1):
        quest_name = quest.get('theme_name', '알 수 없음')
        quest_id = quest['quest_id']
        quest_points = quest['points']
        
        print(f"\n   📋 퀘스트 {i}/{len(unique_quests)}: {quest_name}")
        print(f"      현재 점수: {current_score}점")
        print(f"     퀘스트 상태: {quest.get('status', '알 수 없음')}")
        
        # reward_ready 상태인 퀘스트만 보상 지급
        if quest.get('status') == 'reward_ready':
            print(f"     보상 점수 지급...")
            reward_data = {
                "user_id": user_id,
                "quest_id": quest_id
            }
            
            response = requests.post(f"{BASE_URL}/quests/reward", json=reward_data)
            
            if response.status_code == 200:
                result = response.json()
                
                # 에러 체크
                if 'error' in result['result']:
                    print(f"     ❌ 보상 지급 실패: {result['result']['error']}")
                    continue
                
                reward_points = result['result']['reward_points']
                
                # 보상 지급 후 점수 확인
                time.sleep(1)
                after_reward_score = get_user_score(user_id)
                actual_increase = after_reward_score - current_score
                
                print(f"     보상 지급 후 점수: {after_reward_score}점")
                print(f"     점수 증가: +{actual_increase}점 (예상: +{reward_points}점)")
                
                if actual_increase == reward_points:
                    print(f"     ✅ 점수 지급 정상!")
                else:
                    print(f"     ⚠️ 점수 불일치! 예상: +{reward_points}점, 실제: +{actual_increase}점")
                
                current_score = after_reward_score
                step_scores.append({
                    'quest_name': quest_name,
                    'status_change_success': True,
                    'reward_points': reward_points,
                    'final_score': after_reward_score,
                    'actual_increase': actual_increase
                })
            else:
                print(f"     ❌ 보상 지급 실패: {response.text}")
        else:
            print(f"     ⚠️ 퀘스트가 reward_ready 상태가 아닙니다. 건너뜀.")
            step_scores.append({
                'quest_name': quest_name,
                'status_change_success': False,
                'reward_points': 0,
                'final_score': current_score,
                'actual_increase': 0
            })
    
    # 최종 보상 지급 결과 요약
    final_reward_score = get_user_score(user_id)
    total_reward_increase = final_reward_score - before_reward_score
    
    print(f"\n📊 퀘스트 보상 지급 결과:")
    print(f"   보상 지급 전: {before_reward_score}점")
    print(f"   보상 지급 후: {final_reward_score}점")
    print(f"   총 보상 점수: +{total_reward_increase}점")
    
    # 각 퀘스트별 상세 결과
    print(f"\n📋 퀘스트별 상세 결과:")
    for i, step in enumerate(step_scores, 1):
        status_icon = "✅" if step['status_change_success'] else "⚠️"
        print(f"   {i}. {step['quest_name']}: +{step['actual_increase']}점 {status_icon}")
    
    claimed_count = len(step_scores)
    total_reward = total_reward_increase
    
    # 8. 최종 점수 확인
    print(f"\n{'='*60}")
    print(f"📊 최종 점수 확인")
    print(f"{'='*60}")
    
    final_score = get_user_score(user_id)
    total_increase = final_score - initial_score
    
    print(f"초기 점수: {initial_score}점")
    print(f"최종 점수: {final_score}점")
    print(f"총 점수 증가: +{total_increase}점")
    print(f"성공한 방문: {successful_visits}/3")
    print(f"완료된 퀘스트: {claimed_count}개")
    print(f"퀘스트 보상: +{total_reward}점")
    
    # 9. 예상 점수와 비교
    expected_visit_score = successful_visits * 10  # 방문당 10점
    expected_quest_score = claimed_count * 20     # 퀘스트당 20점
    expected_total = expected_visit_score + expected_quest_score
        
    print(f"\n📈 점수 분석:")
    print(f"   방문 점수: {successful_visits}방문 × 10점 = +{expected_visit_score}점")
    print(f"   퀘스트 보상: {claimed_count}개 × 20점 = +{expected_quest_score}점")
    print(f"   예상 총점: +{expected_total}점")
    print(f"   실제 총점: +{total_increase}점")
        
    if total_increase == expected_total:
        print("   ✅ 점수가 정확히 계산되었습니다!")
        if expected_total == 90:
            print("   🎉 목표 달성! 90점 획득!")
        else:
            print(f"   ⚠️ 목표 미달성 (목표: 90점, 실제: {expected_total}점)")
    else:
        print(f"   ❌ 점수 불일치! 예상: +{expected_total}점, 실제: +{total_increase}점")
    
    # 10. 최종 퀘스트 상태 확인
    print(f"\n🎯 최종 퀘스트 상태 확인...")
    try:
        response = requests.get(f"{BASE_URL}/quests/{user_id}")
        if response.status_code == 200:
            quests_data = response.json()
            quests = quests_data["quests"]
            
            theme_missions = [q for q in quests if q['type'] == 'theme_mission']
            print(f"테마 미션: {len(theme_missions)}개")
            
            for quest in theme_missions:
                status = quest['status']
                theme_name = quest.get('theme_name', '알 수 없음')
                completed_places = quest.get('completed_places', [])
                print(f"   {theme_name}: {status} (완료된 곳: {completed_places})")
        else:
            print(f"퀘스트 조회 실패: {response.text}")
    except Exception as e:
        print(f"퀘스트 확인 중 오류: {e}")
    
    print(f"\n=== 테스트 완료 ===")
    print(f"💡 테스트 사용자 ID: {user_id}")
    print(f"   방문한 곳: {test_places}")
    print(f"   성공한 방문: {successful_visits}/3")
    print(f"   완료된 퀘스트: {claimed_count}개")
    print(f"   점수 변화: {initial_score}점 → {final_score}점 (+{total_increase}점)")
    print(f"   목표 달성: {'✅' if total_increase == 90 else '❌'}")

def test_daily_quiz_quests():
    """
    generate_daily_quests를 통해 생성된 3개의 퀴즈 퀘스트를 테스트하는 함수
    - /quests/{user_id} 엔드포인트로 퀘스트 전체 목록을 받아옴
    - type == 'history_quiz'인 퀘스트 3개를 대상으로 테스트
    - 각 퀴즈에 대해 오답/정답 제출 및 결과 출력
    """
    print("\n=== 일일 퀴즈 퀘스트 3개 테스트 시작 ===\n")
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        print("❌ 테스트 사용자 생성 실패")
        return
    # 2. /quests/{user_id}로 퀘스트 전체 목록 조회 (생성도 겸함)
    response = requests.get(f"{BASE_URL}/quests/{user_id}")
    if response.status_code != 200:
        print(f"❌ 퀘스트 목록 조회 실패: {response.text}")
        return
    quests = response.json()["quests"]
    # 3. 퀴즈 퀘스트만 추출
    quiz_quests = [q for q in quests if q["type"] == "history_quiz"]
    if len(quiz_quests) < 3:
        print(f"❌ 퀴즈 퀘스트가 3개가 아닙니다. (실제: {len(quiz_quests)})")
        return
    print(f"\n총 퀴즈 퀘스트 개수: {len(quiz_quests)}개\n")
    for idx, quiz in enumerate(quiz_quests, 1):
        print(f"--- 퀴즈 {idx} ---")
        print(f"  관광지: {quiz['target_place']}")
        print(f"  문제: {quiz['quiz_question']}")
        for i, opt in enumerate(quiz['quiz_options']):
            print(f"    {i}. {opt}")
        # 테스트 목적: 정답 인덱스를 1로 강제 설정
        
        print(f"  정답 인덱스(테스트용): {quiz['correct_answer']}")
        # 정답 제출 전 status 확인
        response_status = requests.get(f"{BASE_URL}/quests/{user_id}")
        if response_status.status_code == 200:
            quests_status = response_status.json()["quests"]
            my_quiz = next((q for q in quests_status if q["quest_id"] == quiz["quest_id"]), None)
            if my_quiz:
                print(f"  [정답 제출 전] 퀘스트 상태: {my_quiz['status']}")
        # 1. 1번(정답) 제출
        print(f"  ✅ 1번(정답) 제출...")
        answer_data = {
            "user_id": user_id,
            "quest_id": quiz['quest_id'],
            "answer_index": quiz['correct_answer']
        }
        response = requests.post(f"{BASE_URL}/quests/quiz/answer", json=answer_data)
        if response.status_code == 200:
            resp_json = response.json()
            print(f"    [응답 전체 구조]: {resp_json}")
            result = resp_json["result"]
            print(f"    결과: {result.get('message', '메시지 없음')}")
            print(f"    정답 여부: {result.get('is_correct', 'N/A')}")
            print(f"    해설: {result.get('explanation', '없음')}")
            print(f"    획득 점수: {result.get('points_earned', 'N/A')}")
        else:
            print(f"    ❌ 1번(정답) 제출 실패: {response.text}")
        # 정답 제출 후 status 확인
        response_status = requests.get(f"{BASE_URL}/quests/{user_id}")
        if response_status.status_code == 200:
            quests_status = response_status.json()["quests"]
            my_quiz = next((q for q in quests_status if q["quest_id"] == quiz["quest_id"]), None)
            if my_quiz:
                print(f"  [정답 제출 후] 퀘스트 상태: {my_quiz['status']}")
        print()
    # 4. 최종 점수 확인 전 보상 지급 처리
    # reward_ready 상태인 퀴즈 퀘스트를 모두 찾아 보상 지급
    response_status = requests.get(f"{BASE_URL}/quests/{user_id}")
    claimed_count = 0
    if response_status.status_code == 200:
        quests_status = response_status.json()["quests"]
        for quiz in [q for q in quests_status if q["type"] == "history_quiz" and q["status"] == "reward_ready"]:
            print(f"[보상 지급] 퀘스트 {quiz['quest_id']} ({quiz['quiz_question']}) reward_ready → reward_claimed")
            reward_data = {
                "user_id": user_id,
                "quest_id": quiz['quest_id']
            }
            reward_response = requests.post(f"{BASE_URL}/quests/reward", json=reward_data)
            if reward_response.status_code == 200:
                print("  → 보상 지급 완료!")
                claimed_count += 1
            else:
                print(f"  → 보상 지급 실패: {reward_response.text}")
    # 5. 최종 점수 확인
    final_score = get_user_score(user_id)
    print(f"\n🏁 최종 점수: {final_score}점 (보상 지급 퀘스트 수: {claimed_count}, 예상 점수: {claimed_count * 20}점)")
    print("\n=== 일일 퀴즈 퀘스트 테스트 종료 ===\n")


def test_visit_count_quest():
    """
    방문 횟수 퀘스트(3곳 방문 시 클리어) 테스트 함수
    QUEST_README.md의 방문 횟수 퀘스트 가이드 6단계 순서대로 동작을 검증한다.
    경복궁, 경희궁, 광화문을 방문했다고 가정하여 테스트한다.
    """
    print("\n=== 방문 횟수 퀘스트 테스트 시작 ===\n")
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        print("❌ 테스트 사용자 생성 실패")
        return

    # 1. 일일 퀘스트 생성 시 방문 횟수 퀘스트 1개가 자동으로 생성된다.
    response = requests.get(f"{BASE_URL}/quests/{user_id}")
    if response.status_code != 200:
        print(f"❌ 퀘스트 목록 조회 실패: {response.text}")
        return
    quests = response.json()["quests"]
    visit_count_quest = next((q for q in quests if q["type"] == "visit_count"), None)
    if not visit_count_quest:
        print("❌ 방문 횟수 퀘스트가 생성되지 않았습니다.")
        return
    print(f"[1단계] 방문 횟수 퀘스트 생성 확인: {visit_count_quest['quest_id']}")

    # 2. 경복궁, 경희궁, 광화문을 순서대로 방문
    fixed_places = ["경복궁", "경희궁", "광화문"]
    visited_places = []
    visit_success = 0
    for place in fixed_places:
        if visit_place(user_id, place):
            visited_places.append(place)
            visit_success += 1
            print(f"[2단계] {place} 방문 성공 ({visit_success}/3)")
        else:
            print(f"❌ {place} 방문 실패")

    # 3. 각 방문마다 check_quest_completion 함수가 호출되어 방문 횟수가 업데이트된다.
    response = requests.get(f"{BASE_URL}/quests/{user_id}")
    if response.status_code == 200:
        quests_status = response.json()["quests"]
        my_quest = next((q for q in quests_status if q["quest_id"] == visit_count_quest["quest_id"]), None)
        if my_quest:
            print(f"[3단계] 방문 목록: {my_quest['completed_places']}, 현재 방문 수: {my_quest['current_visit_count']}")

    # 4. 3곳 방문 완료 시 퀘스트 상태가 'active'에서 'reward_ready'로 변경된다.
    response = requests.get(f"{BASE_URL}/quests/{user_id}")
    if response.status_code == 200:
        quests_status = response.json()["quests"]
        my_quest = next((q for q in quests_status if q["quest_id"] == visit_count_quest["quest_id"]), None)
        if my_quest and my_quest["status"] == "reward_ready":
            print(f"[4단계] 퀘스트 상태: {my_quest['status']} (3곳 방문 완료)")
        else:
            print(f"❌ 퀘스트가 reward_ready 상태가 아닙니다. 현재 상태: {my_quest['status'] if my_quest else 'N/A'}")
    else:
        print("❌ 퀘스트 상태 조회 실패")

    # 5. reward_ready 상태에서 /quests/reward 엔드포인트를 호출하면 상태가 'reward_claimed'로 변경되고, 사용자 total_score에 30점이 누적된다.
    if my_quest and my_quest["status"] == "reward_ready":
        reward_data = {
            "user_id": user_id,
            "quest_id": my_quest["quest_id"]
        }
        reward_response = requests.post(f"{BASE_URL}/quests/reward", json=reward_data)
        if reward_response.status_code == 200:
            print("[5단계] 보상 지급 완료!")
        else:
            print(f"❌ 보상 지급 실패: {reward_response.text}")
        # 상태 재확인
        response = requests.get(f"{BASE_URL}/quests/{user_id}")
        if response.status_code == 200:
            quests_status = response.json()["quests"]
            my_quest = next((q for q in quests_status if q["quest_id"] == visit_count_quest["quest_id"]), None)
            if my_quest:
                print(f"[5단계] 보상 지급 후 상태: {my_quest['status']}")
    else:
        print("❌ reward_ready 상태가 아니어서 보상 지급을 건너뜀")

    # 6. 중복 방문은 카운트되지 않으며, 오늘 방문한 관광지 목록이 completed_places에 저장된다.
    response = requests.get(f"{BASE_URL}/quests/{user_id}")
    if response.status_code == 200:
        quests_status = response.json()["quests"]
        my_quest = next((q for q in quests_status if q["quest_id"] == visit_count_quest["quest_id"]), None)
        if my_quest:
            print(f"[6단계] 최종 방문 목록(completed_places): {my_quest['completed_places']}")
            print(f"[6단계] 방문 수(중복 제외): {len(my_quest['completed_places'])}")
    # 최종 점수 확인
    final_score = get_user_score(user_id)
    print(f"\n🏁 최종 점수: {final_score}점 (예상: 30점)")
    print(f"방문한 관광지(고정): {visited_places}")
    print("\n=== 방문 횟수 퀘스트 테스트 종료 ===\n")

if __name__ == "__main__":
    try:
        test_visit_count_quest()
        # test_daily_quiz_quests()
        # test_theme_quest_clear()
    except requests.exceptions.ConnectionError:
        print("❌ API 서버에 연결할 수 없습니다.")
        print("   서버가 실행 중인지 확인해주세요.")
        print("   서버 실행 명령: python api.py")
    except Exception as e:
        print(f"❌ 테스트 중 오류 발생: {e}") 