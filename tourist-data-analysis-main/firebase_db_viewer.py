from firebase_config import initialize_firebase, USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION
from firebase_admin import firestore
import pandas as pd
from datetime import datetime

def view_firebase_database():
    """Firebase Firestore의 모든 컬렉션과 데이터를 조회합니다."""
    db = initialize_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return
    
    print("=" * 50)
    print("🔥 Firebase Firestore 데이터베이스 조회")
    print("=" * 50)
    
    # 1. 사용자 정보 조회
    print("\n👤 사용자 정보:")
    try:
        users_ref = db.collection(USERS_COLLECTION)
        users = users_ref.order_by('total_score', direction=firestore.Query.DESCENDING).get()
        
        if users:
            users_data = []
            for user in users:
                user_data = user.to_dict()
                users_data.append({
                    'user_id': user_data.get('user_id', ''),
                    'username': user_data.get('username', ''),
                    'total_score': user_data.get('total_score', 0),
                    'created_at': user_data.get('created_at', '')
                })
            
            users_df = pd.DataFrame(users_data)
            print(users_df.to_string(index=False))
        else:
            print("등록된 사용자가 없습니다.")
    except Exception as e:
        print(f"사용자 조회 중 오류: {e}")
    
    # 2. 게임 세션 정보 조회
    print("\n🎮 게임 세션 정보:")
    try:
        sessions_ref = db.collection(GAME_SESSIONS_COLLECTION)
        sessions = sessions_ref.order_by('created_at', direction=firestore.Query.DESCENDING).get()
        
        if sessions:
            sessions_data = []
            for session in sessions:
                session_data = session.to_dict()
                # 사용자 이름 가져오기
                user_id = session_data.get('user_id', '')
                username = "Unknown"
                if user_id:
                    try:
                        user_doc = db.collection(USERS_COLLECTION).document(user_id).get()
                        if user_doc.exists:
                            username = user_doc.to_dict().get('username', 'Unknown')
                    except:
                        pass
                
                sessions_data.append({
                    'session_id': session_data.get('session_id', ''),
                    'username': username,
                    'target_places': ', '.join(session_data.get('target_places', [])),
                    'current_score': session_data.get('current_score', 0),
                    'is_active': session_data.get('is_active', False),
                    'created_at': session_data.get('created_at', ''),
                    'ended_at': session_data.get('ended_at', '')
                })
            
            sessions_df = pd.DataFrame(sessions_data)
            print(sessions_df.to_string(index=False))
        else:
            print("게임 세션이 없습니다.")
    except Exception as e:
        print(f"게임 세션 조회 중 오류: {e}")
    
    # 3. 방문 기록 조회 (최근 20개)
    print("\n📍 방문 기록 (최근 20개):")
    try:
        visits_ref = db.collection(VISITS_COLLECTION)
        visits = visits_ref.order_by('visit_time', direction=firestore.Query.DESCENDING).limit(20).get()
        
        if visits:
            visits_data = []
            for visit in visits:
                visit_data = visit.to_dict()
                # 사용자 이름 가져오기
                user_id = visit_data.get('user_id', '')
                username = "Unknown"
                if user_id:
                    try:
                        user_doc = db.collection(USERS_COLLECTION).document(user_id).get()
                        if user_doc.exists:
                            username = user_doc.to_dict().get('username', 'Unknown')
                    except:
                        pass
                
                visits_data.append({
                    'visit_id': visit_data.get('visit_id', ''),
                    'username': username,
                    'target_place': visit_data.get('target_place', ''),
                    'predicted_place': visit_data.get('predicted_place', ''),
                    'is_correct': visit_data.get('is_correct', False),
                    'score_earned': visit_data.get('score_earned', 0),
                    'confidence': visit_data.get('confidence', 0),
                    'visit_time': visit_data.get('visit_time', '')
                })
            
            visits_df = pd.DataFrame(visits_data)
            print(visits_df.to_string(index=False))
        else:
            print("방문 기록이 없습니다.")
    except Exception as e:
        print(f"방문 기록 조회 중 오류: {e}")
    
    # 4. 통계 정보
    print("\n📊 통계 정보:")
    try:
        # 총 사용자 수
        users_count = len(db.collection(USERS_COLLECTION).get())
        print(f"총 사용자 수: {users_count}명")
        
        # 총 게임 세션 수
        sessions_count = len(db.collection(GAME_SESSIONS_COLLECTION).get())
        print(f"총 게임 세션 수: {sessions_count}개")
        
        # 총 방문 기록 수
        visits_all = db.collection(VISITS_COLLECTION).get()
        total_visits = len(visits_all)
        print(f"총 방문 기록 수: {total_visits}개")
        
        # 정답률 계산
        if total_visits > 0:
            correct_visits = sum(1 for visit in visits_all if visit.to_dict().get('is_correct', False))
            accuracy = (correct_visits / total_visits) * 100
            print(f"전체 정답률: {accuracy:.1f}% ({correct_visits}/{total_visits})")
        
        # 가장 많이 타깃된 관광지
        target_places = {}
        for visit in visits_all:
            target_place = visit.to_dict().get('target_place', '')
            if target_place:
                target_places[target_place] = target_places.get(target_place, 0) + 1
        
        if target_places:
            print("\n🎯 인기 타깃 관광지:")
            sorted_places = sorted(target_places.items(), key=lambda x: x[1], reverse=True)[:5]
            for place, count in sorted_places:
                print(f"  {place}: {count}회")
        
    except Exception as e:
        print(f"통계 조회 중 오류: {e}")

def view_firebase_rankings():
    """Firebase에서 랭킹만 간단히 조회합니다."""
    db = initialize_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return
    
    print("🏆 현재 랭킹:")
    try:
        users_ref = db.collection(USERS_COLLECTION)
        users = users_ref.order_by('total_score', direction=firestore.Query.DESCENDING).limit(10).get()
        
        if users:
            rankings_data = []
            for rank, user in enumerate(users, 1):
                user_data = user.to_dict()
                rankings_data.append({
                    'rank': rank,
                    'username': user_data.get('username', ''),
                    'total_score': user_data.get('total_score', 0),
                    'created_at': user_data.get('created_at', '')
                })
            
            rankings_df = pd.DataFrame(rankings_data)
            print(rankings_df.to_string(index=False))
        else:
            print("등록된 사용자가 없습니다.")
    except Exception as e:
        print(f"랭킹 조회 중 오류: {e}")

def view_firebase_user_history(username=None):
    """Firebase에서 특정 사용자의 기록을 조회합니다."""
    db = initialize_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return
    
    if not username:
        print("사용자명을 입력해주세요.")
        return
    
    print(f"👤 {username}님의 기록:")
    try:
        # 먼저 사용자 ID 찾기
        users_ref = db.collection(USERS_COLLECTION)
        user_query = users_ref.where(filter=firestore.FieldFilter("username", "==", username)).limit(1).get()
        
        user_docs = list(user_query)
        if not user_docs:
            print(f"{username}님을 찾을 수 없습니다.")
            return
        
        user_id = user_docs[0].to_dict().get('user_id')
        
        # 해당 사용자의 방문 기록 조회
        visits_ref = db.collection(VISITS_COLLECTION)
        visits = visits_ref.where(filter=firestore.FieldFilter("user_id", "==", user_id)).order_by('visit_time', direction=firestore.Query.DESCENDING).get()
        
        if visits:
            visits_data = []
            for visit in visits:
                visit_data = visit.to_dict()
                visits_data.append({
                    'target_place': visit_data.get('target_place', ''),
                    'predicted_place': visit_data.get('predicted_place', ''),
                    'is_correct': visit_data.get('is_correct', False),
                    'score_earned': visit_data.get('score_earned', 0),
                    'confidence': visit_data.get('confidence', 0),
                    'visit_time': visit_data.get('visit_time', '')
                })
            
            visits_df = pd.DataFrame(visits_data)
            print(visits_df.to_string(index=False))
        else:
            print(f"{username}님의 기록이 없습니다.")
    except Exception as e:
        print(f"사용자 기록 조회 중 오류: {e}")

def count_all_documents():
    """모든 컬렉션의 문서 수를 카운트합니다."""
    db = initialize_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return
    
    print("\n📊 Firebase 컬렉션별 문서 수:")
    print("-" * 30)
    
    collections = [USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION]
    total_docs = 0
    
    for collection_name in collections:
        try:
            docs = db.collection(collection_name).get()
            count = len(docs)
            total_docs += count
            print(f"{collection_name}: {count}개")
        except Exception as e:
            print(f"{collection_name}: 오류 - {e}")
    
    print(f"\n총 문서 수: {total_docs}개")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        if command == "rankings":
            view_firebase_rankings()
        elif command == "user" and len(sys.argv) > 2:
            view_firebase_user_history(sys.argv[2])
        elif command == "count":
            count_all_documents()
        else:
            print("사용법:")
            print("  python firebase_db_viewer.py           # 전체 Firebase 데이터베이스 조회")
            print("  python firebase_db_viewer.py rankings  # 랭킹만 조회")
            print("  python firebase_db_viewer.py user 사용자명  # 특정 사용자 기록 조회")
            print("  python firebase_db_viewer.py count      # 문서 수 카운트")
    else:
        view_firebase_database() 