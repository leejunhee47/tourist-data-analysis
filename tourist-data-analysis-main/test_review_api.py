#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
리뷰 API 엔드포인트 테스트 스크립트
- 리뷰 저장 API (/reviews/) 테스트
- 리뷰 목록 조회 API (/reviews/{user_id}) 테스트
- 다양한 시나리오 테스트
"""

import requests
import json
import time
from datetime import datetime
import random

# 서버 URL 설정
BASE_URL = "http://localhost:8000"

def create_test_user():
    """테스트용 사용자를 생성합니다."""
    try:
        username = f"test_user_{int(time.time())}"
        user_data = {
            "username": username,
            "profile_image_url": None
        }
        
        response = requests.post(f"{BASE_URL}/create_user/", json=user_data)
        
        if response.status_code == 200:
            user_id = response.json()["user_id"]
            print(f"✅ 테스트 사용자 생성 완료: {username} (ID: {user_id})")
            return user_id
        else:
            print(f"❌ 사용자 생성 실패: {response.text}")
            return None
    except Exception as e:
        print(f"❌ 사용자 생성 중 오류: {e}")
        return None

def get_user_score(user_id):
    """사용자의 현재 점수를 조회합니다."""
    try:
        response = requests.get(f"{BASE_URL}/user_profile/{user_id}")
        if response.status_code == 200:
            return response.json()["total_score"]
        else:
            print(f"❌ 사용자 점수 조회 실패: {response.text}")
            return 0
    except Exception as e:
        print(f"❌ 점수 조회 중 오류: {e}")
        return 0

def test_submit_review_success():
    """리뷰 저장 성공 케이스 테스트"""
    print("\n=== 📝 리뷰 저장 성공 테스트 ===")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        return False
    
    # 2. 리뷰 저장 전 점수 확인
    before_score = get_user_score(user_id)
    print(f"리뷰 저장 전 점수: {before_score}점")
    
    # 3. 리뷰 데이터 준비
    review_data = {
        "user_id": user_id,
        "place_name": "경복궁",
        "review_text": "정말 아름다운 궁궐이었습니다. 조선왕조의 웅장함을 느낄 수 있었고, 특히 경회루에서 바라본 풍경이 인상적이었습니다. 역사의 깊이를 체험할 수 있는 좋은 장소입니다.",
        "image_url": None
    }
    
    # 4. 리뷰 저장 API 호출
    try:
        # Form 데이터로 전송하도록 수정
        response = requests.post(
            f"{BASE_URL}/reviews/",
            data={
                "user_id": user_id,
                "place_name": review_data["place_name"],
                "review_text": review_data["review_text"]
            }
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 리뷰 저장 성공!")
            print(f"   리뷰 ID: {result['review_id']}")
            print(f"   장소: {result['place_name']}")
            print(f"   리뷰 길이: {len(result['review_text'])}자")
            print(f"   획득 점수: +{result['score_earned']}점")
            print(f"   메시지: {result['message']}")
            
            # 5. 점수 변화 확인
            time.sleep(1)  # 점수 업데이트 대기
            after_score = get_user_score(user_id)
            print(f"리뷰 저장 후 점수: {after_score}점")
            print(f"점수 변화: +{after_score - before_score}점")
            
            return True
        else:
            print(f"❌ 리뷰 저장 실패: {response.status_code}")
            print(f"   에러: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 리뷰 저장 중 오류: {e}")
        return False

def test_submit_review_short_text():
    """짧은 리뷰 텍스트 테스트 (실패 케이스)"""
    print("\n=== ❌ 짧은 리뷰 텍스트 테스트 ===")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        return False
    
    # 2. 짧은 리뷰 데이터 준비 (20자 미만)
    review_data = {
        "user_id": user_id,
        "place_name": "경희궁",
        "review_text": "좋았습니다.",  # 6자 (20자 미만)
        "image_url": None
    }
    
    # 3. 리뷰 저장 API 호출
    try:
        # Form 데이터로 전송하도록 수정
        response = requests.post(
            f"{BASE_URL}/reviews/",
            data={
                "user_id": user_id,
                "place_name": review_data["place_name"],
                "review_text": review_data["review_text"]
            }
        )
        
        if response.status_code == 400:
            result = response.json()
            print(f"✅ 예상된 실패 케이스!")
            print(f"   상태 코드: {response.status_code}")
            print(f"   에러 메시지: {result['detail']}")
            return True
        else:
            print(f"❌ 예상과 다른 응답: {response.status_code}")
            print(f"   응답: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 테스트 중 오류: {e}")
        return False

def test_submit_review_long_text():
    """긴 리뷰 텍스트 테스트 (실패 케이스)"""
    print("\n=== ❌ 긴 리뷰 텍스트 테스트 ===")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        return False
    
    # 2. 긴 리뷰 데이터 준비 (100자 초과)
    long_review_text = "정말 아름다운 궁궐이었습니다. 조선왕조의 웅장함을 느낄 수 있었고, 특히 경회루에서 바라본 풍경이 인상적이었습니다. 역사의 깊이를 체험할 수 있는 좋은 장소입니다. 꼭 다시 방문하고 싶은 곳이에요!"  # 101자
    review_data = {
        "user_id": user_id,
        "place_name": "경복궁",
        "review_text": long_review_text,
        "image_url": None
    }
    
    # 3. 리뷰 저장 API 호출
    try:
        # Form 데이터로 전송하도록 수정
        response = requests.post(
            f"{BASE_URL}/reviews/",
            data={
                "user_id": user_id,
                "place_name": review_data["place_name"],
                "review_text": review_data["review_text"]
            }
        )
        
        if response.status_code == 400:
            result = response.json()
            print(f"✅ 예상된 실패 케이스!")
            print(f"   상태 코드: {response.status_code}")
            print(f"   에러 메시지: {result['detail']}")
            print(f"   리뷰 길이: {len(long_review_text)}자")
            return True
        else:
            print(f"❌ 예상과 다른 응답: {response.status_code}")
            print(f"   응답: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 테스트 중 오류: {e}")
        return False

def test_submit_review_invalid_user():
    """존재하지 않는 사용자로 리뷰 저장 테스트 (실패 케이스)"""
    print("\n=== ❌ 존재하지 않는 사용자 테스트 ===")
    
    # 1. 존재하지 않는 사용자 ID
    invalid_user_id = "invalid_user_12345"
    
    # 2. 리뷰 데이터 준비
    review_data = {
        "user_id": invalid_user_id,
        "place_name": "광화문",
        "review_text": "광화문은 서울의 상징적인 건축물입니다. 조선왕조의 정문으로서 역사적 의미가 깊고, 특히 밤에 조명이 켜진 모습이 아름답습니다. 많은 관광객들이 찾는 명소입니다.",
        "image_url": None
    }
    
    # 3. 리뷰 저장 API 호출
    try:
        # Form 데이터로 전송하도록 수정
        response = requests.post(
            f"{BASE_URL}/reviews/",
            data={
                "user_id": invalid_user_id,
                "place_name": review_data["place_name"],
                "review_text": review_data["review_text"]
            }
        )
        
        if response.status_code == 404:
            result = response.json()
            print(f"✅ 예상된 실패 케이스!")
            print(f"   상태 코드: {response.status_code}")
            print(f"   에러 메시지: {result['detail']}")
            return True
        else:
            print(f"❌ 예상과 다른 응답: {response.status_code}")
            print(f"   응답: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 테스트 중 오류: {e}")
        return False

def test_get_user_reviews():
    """사용자 리뷰 목록 조회 테스트"""
    print("\n=== 📋 사용자 리뷰 목록 조회 테스트 ===")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        return False
    
    # 2. 여러 리뷰 저장
    places = ["경복궁", "경희궁", "광화문", "남산서울타워", "북촌한옥마을"]
    review_texts = [
        "조선왕조의 웅장함을 느낄 수 있는 아름다운 궁궐입니다. 특히 경회루에서 바라본 풍경이 인상적이었습니다.",
        "조선왕조의 별궁으로서 조용하고 아름다운 분위기를 느낄 수 있었습니다. 궁궐의 정취를 즐기기 좋은 곳입니다.",
        "서울의 상징적인 건축물로 조선왕조의 정문 역할을 했습니다. 역사적 의미가 깊고 밤에 조명이 켜진 모습이 아름답습니다.",
        "서울의 전망을 한눈에 볼 수 있는 최고의 장소입니다. 특히 야경이 정말 아름다워서 추천합니다.",
        "전통 한옥의 아름다움을 느낄 수 있는 마을입니다. 조용하고 평화로운 분위기에서 한국의 전통 문화를 체험할 수 있습니다."
    ]
    
    print(f"   {len(places)}개의 리뷰를 저장합니다...")
    
    for i, (place, review_text) in enumerate(zip(places, review_texts), 1):
        review_data = {
            "user_id": user_id,
            "place_name": place,
            "review_text": review_text,
            "image_url": None
        }
        
        try:
            # Form 데이터로 전송하도록 수정
            response = requests.post(
                f"{BASE_URL}/reviews/",
                data={
                    "user_id": user_id,
                    "place_name": review_data["place_name"],
                    "review_text": review_data["review_text"]
                }
            )
            
            if response.status_code == 200:
                result = response.json()
                print(f"   {i}. {place} 리뷰 저장 완료 (+{result['score_earned']}점)")
            else:
                print(f"   {i}. {place} 리뷰 저장 실패: {response.text}")
                
        except Exception as e:
            print(f"   {i}. {place} 리뷰 저장 중 오류: {e}")
    
    # 3. 리뷰 목록 조회
    time.sleep(2)  # 모든 리뷰 저장 완료 대기
    
    try:
        response = requests.get(f"{BASE_URL}/reviews/{user_id}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"\n✅ 리뷰 목록 조회 성공!")
            print(f"   사용자 ID: {result['user_id']}")
            print(f"   총 리뷰 수: {result['total_reviews']}개")
            
            print(f"\n📝 저장된 리뷰 목록:")
            for i, review in enumerate(result['reviews'], 1):
                print(f"   {i}. {review['place_name']}")
                print(f"      리뷰: {review['review_text'][:50]}...")
                print(f"      점수: +{review['score_earned']}점")
                print(f"      작성일: {review['created_at']}")
                print()
            
            return True
        else:
            print(f"❌ 리뷰 목록 조회 실패: {response.status_code}")
            print(f"   에러: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 리뷰 목록 조회 중 오류: {e}")
        return False

def test_get_reviews_invalid_user():
    """존재하지 않는 사용자의 리뷰 조회 테스트 (실패 케이스)"""
    print("\n=== ❌ 존재하지 않는 사용자 리뷰 조회 테스트 ===")
    
    # 1. 존재하지 않는 사용자 ID
    invalid_user_id = "invalid_user_54321"
    
    try:
        response = requests.get(f"{BASE_URL}/reviews/{invalid_user_id}")
        
        if response.status_code == 404:
            result = response.json()
            print(f"✅ 예상된 실패 케이스!")
            print(f"   상태 코드: {response.status_code}")
            print(f"   에러 메시지: {result['detail']}")
            return True
        else:
            print(f"❌ 예상과 다른 응답: {response.status_code}")
            print(f"   응답: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 테스트 중 오류: {e}")
        return False

def test_review_with_image_url():
    """이미지 URL이 포함된 리뷰 저장 테스트"""
    print("\n=== 📸 이미지 URL 포함 리뷰 테스트 ===")
    
    # 1. 테스트 사용자 생성
    user_id = create_test_user()
    if not user_id:
        return False
    
    # 2. 이미지 URL이 포함된 리뷰 데이터
    review_data = {
        "user_id": user_id,
        "place_name": "청계천",
        "review_text": "도심 속에서 자연을 느낄 수 있는 아름다운 공간입니다. 산책로가 잘 정비되어 있고, 특히 봄철 벚꽃이 피는 시기가 정말 아름답습니다. 가족과 함께 산책하기 좋은 곳입니다.",
        "image_url": "https://example.com/cheonggyecheon_photo.jpg"
    }
    
    # 3. 리뷰 저장 API 호출
    try:
        # Form 데이터로 전송하도록 수정
        response = requests.post(
            f"{BASE_URL}/reviews/",
            data={
                "user_id": user_id,
                "place_name": review_data["place_name"],
                "review_text": review_data["review_text"]
            }
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 이미지 URL 포함 리뷰 저장 성공!")
            print(f"   리뷰 ID: {result['review_id']}")
            print(f"   장소: {result['place_name']}")
            print(f"   이미지 URL: {result['image_url']}")
            print(f"   획득 점수: +{result['score_earned']}점")
            return True
        else:
            print(f"❌ 리뷰 저장 실패: {response.status_code}")
            print(f"   에러: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 리뷰 저장 중 오류: {e}")
        return False

def run_all_tests():
    """모든 리뷰 API 테스트를 실행합니다."""
    print("🚀 리뷰 API 테스트 시작")
    print("=" * 50)
    
    test_results = []
    
    # 성공 케이스 테스트
    test_results.append(("리뷰 저장 성공", test_submit_review_success()))
    test_results.append(("이미지 URL 포함 리뷰", test_review_with_image_url()))
    test_results.append(("사용자 리뷰 목록 조회", test_get_user_reviews()))
    
    # 실패 케이스 테스트
    test_results.append(("짧은 리뷰 텍스트", test_submit_review_short_text()))
    test_results.append(("긴 리뷰 텍스트", test_submit_review_long_text()))
    test_results.append(("존재하지 않는 사용자 리뷰 저장", test_submit_review_invalid_user()))
    test_results.append(("존재하지 않는 사용자 리뷰 조회", test_get_reviews_invalid_user()))
    
    # 결과 요약
    print("\n" + "=" * 50)
    print("📊 테스트 결과 요약")
    print("=" * 50)
    
    passed = 0
    total = len(test_results)
    
    for test_name, result in test_results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status} - {test_name}")
        if result:
            passed += 1
    
    print(f"\n총 테스트: {total}개")
    print(f"성공: {passed}개")
    print(f"실패: {total - passed}개")
    print(f"성공률: {(passed/total)*100:.1f}%")
    
    if passed == total:
        print("\n🎉 모든 테스트가 성공했습니다!")
    else:
        print(f"\n⚠️ {total - passed}개의 테스트가 실패했습니다.")

if __name__ == "__main__":
    run_all_tests()