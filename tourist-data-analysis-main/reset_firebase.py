from firebase_config import initialize_firebase, USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION
from firebase_admin import firestore

def delete_collection(db, collection_name, batch_size=100):
    """컬렉션의 모든 문서를 삭제합니다."""
    print(f"🗑️ {collection_name} 컬렉션 삭제 중...")
    
    collection_ref = db.collection(collection_name)
    docs = collection_ref.limit(batch_size).stream()
    
    deleted = 0
    for doc in docs:
        doc.reference.delete()
        deleted += 1
    
    if deleted >= batch_size:
        # 더 많은 문서가 있을 수 있으므로 재귀 호출
        return delete_collection(db, collection_name, batch_size) + deleted
    else:
        print(f"✅ {collection_name} 컬렉션에서 {deleted}개 문서 삭제 완료")
        return deleted

def reset_firebase_database():
    """Firebase Firestore 데이터베이스를 완전히 리셋합니다."""
    print("🚀 Firebase Firestore 데이터베이스 리셋 시작")
    print("=" * 60)
    
    try:
        # Firebase 초기화
        db = initialize_firebase()
        if not db:
            print("❌ Firebase 초기화 실패")
            return False
        
        print("⚠️ 경고: 모든 데이터가 삭제됩니다!")
        confirm = input("계속하시겠습니까? (y/N): ")
        
        if confirm.lower() != 'y':
            print("❌ 리셋이 취소되었습니다.")
            return False
        
        print("\n🔥 데이터 삭제 시작...")
        
        # 각 컬렉션 삭제
        collections = [VISITS_COLLECTION, GAME_SESSIONS_COLLECTION, USERS_COLLECTION]
        total_deleted = 0
        
        for collection in collections:
            deleted_count = delete_collection(db, collection)
            total_deleted += deleted_count
        
        print(f"\n✨ 리셋 완료!")
        print(f"📊 총 {total_deleted}개의 문서가 삭제되었습니다.")
        print("💡 이제 API 서버를 재시작하면 깨끗한 데이터베이스로 시작됩니다.")
        
        return True
        
    except Exception as e:
        print(f"❌ 리셋 중 오류 발생: {e}")
        import traceback
        print("상세 오류:")
        print(traceback.format_exc())
        return False

def show_current_data():
    """현재 데이터베이스 상태를 보여줍니다."""
    print("📊 현재 Firebase 데이터베이스 상태:")
    print("-" * 40)
    
    try:
        db = initialize_firebase()
        if not db:
            print("❌ Firebase 초기화 실패")
            return
        
        collections = [USERS_COLLECTION, GAME_SESSIONS_COLLECTION, VISITS_COLLECTION]
        
        for collection_name in collections:
            collection_ref = db.collection(collection_name)
            docs = list(collection_ref.stream())
            print(f"{collection_name}: {len(docs)}개 문서")
            
            # 처음 3개 문서의 간단한 정보 표시
            for i, doc in enumerate(docs[:3]):
                data = doc.to_dict()
                if collection_name == USERS_COLLECTION:
                    print(f"  - {data.get('username', 'Unknown')} (점수: {data.get('total_score', 0)})")
                elif collection_name == GAME_SESSIONS_COLLECTION:
                    print(f"  - 세션 {doc.id[:8]}... (점수: {data.get('current_score', 0)})")
                elif collection_name == VISITS_COLLECTION:
                    print(f"  - {data.get('target_place', 'Unknown')} -> {data.get('predicted_place', 'Unknown')}")
            
            if len(docs) > 3:
                print(f"  ... 그 외 {len(docs) - 3}개 더")
        
    except Exception as e:
        print(f"❌ 데이터 조회 중 오류: {e}")

if __name__ == "__main__":
    print("🔥 Firebase Firestore 데이터베이스 관리")
    print("=" * 50)
    
    while True:
        print("\n선택하세요:")
        print("1. 현재 데이터 상태 보기")
        print("2. 데이터베이스 리셋")
        print("3. 종료")
        
        choice = input("\n선택 (1-3): ").strip()
        
        if choice == '1':
            show_current_data()
        elif choice == '2':
            reset_firebase_database()
        elif choice == '3':
            print("👋 종료합니다.")
            break
        else:
            print("❌ 잘못된 선택입니다.") 