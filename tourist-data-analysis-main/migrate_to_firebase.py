import sqlite3
from firebase_config import initialize_firebase, USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION
import json
from datetime import datetime
from firebase_admin import firestore

def migrate_users(cursor, db):
    """사용자 데이터 마이그레이션"""
    print("\n사용자 데이터 마이그레이션 시작...")
    cursor.execute("SELECT user_id, username, total_score FROM users")
    users = cursor.fetchall()
    
    users_ref = db.collection(USERS_COLLECTION)
    for user_id, username, total_score in users:
        users_ref.document(user_id).set({
            'user_id': user_id,
            'username': username,
            'total_score': total_score,
            'created_at': firestore.SERVER_TIMESTAMP
        })
    print(f"✅ {len(users)}명의 사용자 데이터 마이그레이션 완료")

def migrate_game_sessions(cursor, db):
    """게임 세션 데이터 마이그레이션"""
    print("\n게임 세션 데이터 마이그레이션 시작...")
    cursor.execute("""
        SELECT session_id, user_id, target_places, current_score, 
               is_active, created_at, ended_at 
        FROM game_sessions
    """)
    sessions = cursor.fetchall()
    
    sessions_ref = db.collection(GAME_SESSIONS_COLLECTION)
    for session in sessions:
        session_id, user_id, target_places, current_score, is_active, created_at, ended_at = session
        
        # JSON 문자열을 파이썬 리스트로 변환
        target_places_list = json.loads(target_places)
        
        sessions_ref.document(session_id).set({
            'session_id': session_id,
            'user_id': user_id,
            'target_places': target_places_list,
            'current_score': current_score,
            'is_active': bool(is_active),
            'created_at': firestore.SERVER_TIMESTAMP if not created_at else datetime.fromisoformat(created_at.replace('Z', '+00:00')),
            'ended_at': None if not ended_at else datetime.fromisoformat(ended_at.replace('Z', '+00:00'))
        })
    print(f"✅ {len(sessions)}개의 게임 세션 마이그레이션 완료")

def migrate_visits(cursor, db):
    """방문 기록 데이터 마이그레이션"""
    print("\n방문 기록 데이터 마이그레이션 시작...")
    cursor.execute("""
        SELECT visit_id, session_id, user_id, target_place, predicted_place,
               is_correct, score_earned, confidence, latitude, longitude, visit_time
        FROM visits
    """)
    visits = cursor.fetchall()
    
    visits_ref = db.collection(VISITS_COLLECTION)
    for visit in visits:
        (visit_id, session_id, user_id, target_place, predicted_place,
         is_correct, score_earned, confidence, latitude, longitude, visit_time) = visit
        
        visits_ref.document(visit_id).set({
            'visit_id': visit_id,
            'session_id': session_id,
            'user_id': user_id,
            'target_place': target_place,
            'predicted_place': predicted_place,
            'is_correct': bool(is_correct),
            'score_earned': score_earned,
            'confidence': confidence,
            'latitude': latitude,
            'longitude': longitude,
            'visit_time': firestore.SERVER_TIMESTAMP if not visit_time else datetime.fromisoformat(visit_time.replace('Z', '+00:00'))
        })
    print(f"✅ {len(visits)}개의 방문 기록 마이그레이션 완료")

def main():
    print("🔄 SQLite에서 Firebase로 데이터 마이그레이션을 시작합니다...")
    
    # Firebase 초기화
    db = initialize_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return
    
    try:
        # SQLite 연결
        conn = sqlite3.connect('tour_ranking.db')
        cursor = conn.cursor()
        
        # 데이터 마이그레이션 수행
        migrate_users(cursor, db)
        migrate_game_sessions(cursor, db)
        migrate_visits(cursor, db)
        
        conn.close()
        print("\n✨ 모든 데이터 마이그레이션이 완료되었습니다!")
        
    except Exception as e:
        print(f"\n❌ 마이그레이션 중 오류 발생: {e}")
        
if __name__ == "__main__":
    main() 