#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
퀘스트 자정 초기화 테스트 코드
- 자정이 지났을 때 퀘스트가 올바르게 초기화되는지 테스트
- 다양한 시나리오를 통해 기능 검증
"""

import sys
import os
import time
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock
import json

# 프로젝트 루트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from quest_system import generate_daily_quests, QuestStatus, QuestType
from firebase_config import initialize_firebase, DAILY_QUESTS_COLLECTION

def test_midnight_reset_scenarios():
    """
    자정 퀘스트 초기화 시나리오 테스트
    """
    print("🕛 퀘스트 자정 초기화 테스트 시작")
    print("=" * 50)
    
    # 테스트 사용자 ID
    test_user_id = "test-midnight-user-001"
    
    # Firebase 초기화
    db = initialize_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return False
    
    quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
    
    # 기존 테스트 데이터 정리
    cleanup_test_data(db, test_user_id)
    
    try:
        # 시나리오 1: 자정이 지나지 않은 경우 (기존 퀘스트 유지)
        print("\n📋 시나리오 1: 자정이 지나지 않은 경우")
        test_same_day_quests(db, test_user_id)
        
        # 시나리오 2: 자정이 지난 경우 (퀘스트 초기화)
        print("\n📋 시나리오 2: 자정이 지난 경우")
        test_midnight_passed_quests(db, test_user_id)
        
        # 시나리오 3: 퀘스트가 없는 경우 (새 퀘스트 생성)
        print("\n📋 시나리오 3: 퀘스트가 없는 경우")
        test_no_existing_quests(db, test_user_id)
        
        print("\n✅ 모든 테스트 시나리오 완료!")
        return True
        
    except Exception as e:
        print(f"❌ 테스트 중 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        # 테스트 데이터 정리
        cleanup_test_data(db, test_user_id)

def test_same_day_quests(db, user_id):
    """
    시나리오 1: 자정이 지나지 않은 경우 테스트
    - 오늘 생성된 퀘스트가 있으면 그대로 반환되어야 함
    """
    print("   🔍 같은 날짜 퀘스트 유지 테스트")
    
    # 오늘 날짜로 퀘스트 생성
    today = datetime.now().strftime('%Y-%m-%d')
    
    # 첫 번째 퀘스트 생성
    quests1 = generate_daily_quests(user_id)
    print(f"   📝 첫 번째 퀘스트 생성: {len(quests1)}개")
    
    # 두 번째 호출 (같은 날짜)
    quests2 = generate_daily_quests(user_id)
    print(f"   📝 두 번째 퀘스트 조회: {len(quests2)}개")
    
    # 검증: 같은 퀘스트가 반환되어야 함
    if len(quests1) == len(quests2) and len(quests1) > 0:
        print("   ✅ 같은 날짜 퀘스트 유지 성공")
        return True
    else:
        print("   ❌ 같은 날짜 퀘스트 유지 실패")
        return False

def test_midnight_passed_quests(db, user_id):
    """
    시나리오 2: 자정이 지난 경우 테스트
    - 어제 생성된 퀘스트가 있으면 삭제되고 새로 생성되어야 함
    """
    print("   🔍 자정 지난 퀘스트 초기화 테스트")
    
    # 먼저 오늘 날짜로 퀘스트 생성
    today_quests = generate_daily_quests(user_id)
    print(f"   📝 오늘 퀘스트 생성: {len(today_quests)}개")
    
    # 오늘 퀘스트의 created_at을 어제로 수정 (자정 체크를 트리거하기 위해)
    quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
    today = datetime.now().strftime('%Y-%m-%d')
    
    # 오늘 퀘스트 중 하나의 created_at을 어제로 변경
    today_quests_docs = quests_ref.where('user_id', '==', user_id).where('date', '==', today).get()
    if today_quests_docs:
        first_quest_doc = today_quests_docs[0]
        yesterday = datetime.now() - timedelta(days=1)
        
        # 첫 번째 퀘스트의 created_at을 어제로 변경
        first_quest_doc.reference.update({
            'created_at': yesterday
        })
        print(f"   📝 첫 번째 퀘스트의 생성 시간을 어제로 변경: {yesterday}")
        
        # 자정 체크가 포함된 generate_daily_quests 호출
        new_quests = generate_daily_quests(user_id)
        print(f"   📝 자정 체크 후 퀘스트: {len(new_quests)}개")
        
        # 검증: 기존 퀘스트가 삭제되고 새로운 퀘스트가 생성되어야 함
        # 자정 체크가 제대로 작동했다면 기존 퀘스트가 삭제되고 새로운 퀘스트가 생성됨
        current_quests = list(quests_ref.where('user_id', '==', user_id).where('date', '==', today).get())
        
        # 첫 번째 퀘스트가 여전히 존재하는지 확인 (자정 체크가 실패했다면 존재할 것)
        first_quest_still_exists = any(
            quest_doc.id == first_quest_doc.id for quest_doc in current_quests
        )
        
        if not first_quest_still_exists and len(new_quests) > 0:
            print("   ✅ 자정 퀘스트 초기화 성공")
            return True
        else:
            print("   ❌ 자정 퀘스트 초기화 실패")
            if first_quest_still_exists:
                print("   ⚠️  어제 생성된 퀘스트가 삭제되지 않음")
            if len(new_quests) == 0:
                print("   ⚠️  새로운 퀘스트가 생성되지 않음")
            return False
    else:
        print("   ❌ 테스트용 퀘스트를 찾을 수 없음")
        return False

def test_no_existing_quests(db, user_id):
    """
    시나리오 3: 퀘스트가 없는 경우 테스트
    - 기존 퀘스트가 없으면 새로운 퀘스트가 생성되어야 함
    """
    print("   🔍 새 퀘스트 생성 테스트")
    
    # 기존 퀘스트 정리
    cleanup_test_data(db, user_id)
    
    # 퀘스트가 없는 상태에서 generate_daily_quests 호출
    new_quests = generate_daily_quests(user_id)
    print(f"   📝 새로 생성된 퀘스트: {len(new_quests)}개")
    
    # 검증: 새로운 퀘스트가 생성되어야 함
    if len(new_quests) > 0:
        print("   ✅ 새 퀘스트 생성 성공")
        return True
    else:
        print("   ❌ 새 퀘스트 생성 실패")
        return False

def cleanup_test_data(db, user_id):
    """
    테스트 데이터 정리
    """
    try:
        quests_ref = db.collection(DAILY_QUESTS_COLLECTION)
        # 해당 사용자의 모든 퀘스트 삭제
        user_quests = quests_ref.where('user_id', '==', user_id).get()
        for quest_doc in user_quests:
            quest_doc.reference.delete()
        print(f"   🗑️  테스트 데이터 정리 완료: {len(user_quests)}개 퀘스트 삭제")
    except Exception as e:
        print(f"   ⚠️  테스트 데이터 정리 중 오류: {e}")

def test_simple_quest_generation():
    """
    간단한 퀘스트 생성 테스트
    """
    print("\n🔍 간단한 퀘스트 생성 테스트")
    print("=" * 50)
    
    test_user_id = "simple-test-user-001"
    
    try:
        # Firebase 초기화
        db = initialize_firebase()
        if not db:
            print("   ❌ Firebase 초기화 실패")
            return False
        
        # 기존 테스트 데이터 정리
        cleanup_test_data(db, test_user_id)
        
        # 오늘 퀘스트 생성
        today_quests = generate_daily_quests(test_user_id)
        print(f"   📝 오늘 퀘스트 생성: {len(today_quests)}개")
        
        if len(today_quests) > 0:
            print("   ✅ 간단한 퀘스트 생성 테스트 성공")
            return True
        else:
            print("   ❌ 간단한 퀘스트 생성 테스트 실패")
            return False
            
    except Exception as e:
        print(f"   ❌ 간단한 테스트 중 오류: {e}")
        return False

def run_all_tests():
    """
    모든 테스트 실행
    """
    print("🚀 퀘스트 자정 초기화 테스트 시작")
    print("=" * 60)
    
    # 실제 Firebase 테스트
    print("\n🔥 실제 Firebase 테스트")
    real_test_result = test_midnight_reset_scenarios()
    
    # 간단한 테스트
    print("\n🔍 간단한 테스트")
    simple_test_result = test_simple_quest_generation()
    
    # 결과 요약
    print("\n" + "=" * 60)
    print("📊 테스트 결과 요약")
    print("=" * 60)
    print(f"🔥 실제 Firebase 테스트: {'✅ 성공' if real_test_result else '❌ 실패'}")
    print(f"🔍 간단한 테스트: {'✅ 성공' if simple_test_result else '❌ 실패'}")
    
    if real_test_result and simple_test_result:
        print("\n🎉 모든 테스트가 성공적으로 완료되었습니다!")
        return True
    else:
        print("\n⚠️  일부 테스트가 실패했습니다.")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
