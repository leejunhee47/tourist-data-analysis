# 📸 성공 이미지 저장 및 조회 기능

## 개요

관광지 인증에 성공한 사용자의 이미지를 Firebase Storage에 저장하고, 사용자가 자신의 성공 이미지를 조회할 수 있는 기능입니다.

## 🚀 주요 기능

### 1. 자동 이미지 저장
- **정답 시에만 저장**: 모델 예측이 정답인 경우에만 이미지가 저장됩니다
- **Firebase Storage 활용**: 이미지는 Firebase Storage에 안전하게 저장됩니다
- **사용자별 폴더 구조**: `success_images/{user_id}/{visit_id}_{place_name}.jpg` 형태로 저장
- **상세한 디버깅 로그**: 이미지 저장 과정의 모든 단계를 로그로 출력

### 2. 이미지 조회 기능
- **개인 이미지 조회**: 사용자가 자신의 성공 이미지만 조회 가능
- **시간순 정렬**: 최신 이미지부터 조회
- **메타데이터 포함**: 장소명, 방문 시간, 점수 등 정보 제공
- **Firestore 인덱스 최적화**: 클라이언트 측 필터링으로 인덱스 문제 해결

### 3. 통계 기능
- **총 성공 횟수**: 사용자의 전체 성공 횟수
- **장소별 통계**: 각 관광지별 성공 횟수
- **총 획득 점수**: 성공 이미지로부터 획득한 총 점수

## 📋 API 엔드포인트

### 1. 성공 이미지 조회
```
GET /success_images/{user_id}
```

**응답 예시:**
```json
{
  "user_id": "user123",
  "success_images": [
    {
      "visit_id": "visit456",
      "place_name": "경복궁",
      "image_url": "https://storage.googleapis.com/...",
      "visit_time": "2024-01-15T10:30:00Z",
      "confidence": 0.95,
      "score_earned": 10
    }
  ],
  "total_count": 1,
  "message": "성공 이미지 1개를 조회했습니다."
}
```

### 2. 성공 이미지 통계 조회
```
GET /success_images/{user_id}/stats
```

**응답 예시:**
```json
{
  "user_id": "user123",
  "total_success_count": 5,
  "total_score_earned": 50,
  "place_stats": [
    {"place_name": "경복궁", "success_count": 2},
    {"place_name": "남산서울타워", "success_count": 3}
  ],
  "message": "성공 이미지 통계를 조회했습니다."
}
```

### 3. 사용자 프로필 조회 (이미지 URL 포함)
```
GET /user_profile/{user_id}
```

**응답 예시:**
```json
{
  "user_id": "user123",
  "username": "test_user",
  "total_score": 50,
  "visit_history": [
    {
      "target_place": "경복궁",
      "predicted_place": "경복궁",
      "is_correct": true,
      "score_earned": 10,
      "visit_time": "2024-01-15T10:30:00Z",
      "image_url": "https://storage.googleapis.com/..."
    }
  ]
}
```

## 🔧 기술적 구현

### 1. 이미지 저장 프로세스
```python
# 1. 정답 확인
is_correct = predicted_place == target_place

# 2. 정답인 경우에만 이미지 저장
if is_correct:
    print(f"🎉 정답입니다! 이미지 저장을 시작합니다...")
    user_id = session.to_dict()['user_id']
    visit_id = str(uuid.uuid4())
    
    image_url = save_image_to_storage(
        temp_image_path, 
        user_id, 
        target_place, 
        visit_id
    )
    
    if image_url:
        print(f"✅ 이미지 저장 성공: {image_url}")
    else:
        print("⚠️ 이미지 저장 실패했지만 게임은 계속 진행됩니다")

# 3. 방문 기록에 이미지 URL 추가
visit_data = {
    'visit_id': visit_id,
    'user_id': user_id,
    'target_place': target_place,
    'is_correct': is_correct,
    'image_url': image_url  # 정답인 경우에만 추가
}
```

### 2. Firebase Storage 구조
```
gs://tourapi-77ca1.firebasestorage.app/success_images/
├── user123/
│   ├── visit456_경복궁.jpg
│   └── visit789_남산서울타워.jpg
└── user456/
    └── visit101_청계천.jpg
```

### 3. 이미지 저장 함수
```python
def save_image_to_storage(image_path: str, user_id: str, place_name: str, visit_id: str) -> str:
    """
    이미지를 Firebase Storage에 저장하고 다운로드 URL을 반환합니다.
    """
    try:
        # Firebase Storage bucket 확인
        if bucket is None:
            print("❌ Firebase Storage bucket이 초기화되지 않았습니다")
            return None
        
        # 파일 존재 확인
        if not os.path.exists(image_path):
            print(f"❌ 이미지 파일이 존재하지 않습니다: {image_path}")
            return None
        
        # Storage 경로 생성
        storage_path = f"success_images/{user_id}/{visit_id}_{place_name}{file_extension}"
        
        # 파일을 Storage에 업로드
        blob = bucket.blob(storage_path)
        blob.upload_from_filename(image_path)
        
        # 공개 URL 설정 (읽기 권한)
        blob.make_public()
        
        # 다운로드 URL 반환
        download_url = blob.public_url
        
        print(f"📸 이미지 저장 완료: {storage_path}")
        print(f"   URL: {download_url}")
        
        return download_url
        
    except Exception as e:
        print(f"❌ 이미지 저장 실패: {e}")
        return None
```

### 4. 보안 설정
- **공개 읽기 권한**: 이미지 URL을 통해 직접 접근 가능
- **사용자별 접근 제어**: API 레벨에서 사용자별 조회 제한
- **정답 시에만 저장**: 오답인 경우 이미지 저장하지 않음

## 🧪 테스트 방법

### 1. 테스트 스크립트 실행
```bash
cd tourist-data-analysis-main
python test_success_images.py
```

**참고**: 테스트 스크립트는 실제 경복궁 이미지(`query_images/경복궁_7_공공3유형.jpg`)를 사용합니다.

### 2. 간단한 조회 테스트
```bash
cd tourist-data-analysis-main
python test_success_images_simple.py
```

**참고**: 이 스크립트는 서버가 실행 중인 상태에서 성공 이미지 조회 기능만 테스트합니다.

### 3. 수동 테스트
```bash
# 1. 사용자 생성
curl -X POST "http://localhost:8000/create_user/" \
  -H "Content-Type: application/json" \
  -d '{"username": "test_user", "profile_image_url": null}'

# 2. 게임 세션 시작
curl -X POST "http://localhost:8000/start_game/" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "USER_ID", "target_places": ["경복궁"]}'

# 3. 이미지 업로드 및 예측
curl -X POST "http://localhost:8000/predict/" \
  -F "session_id=SESSION_ID" \
  -F "target_place=경복궁" \
  -F "image=@test_image.jpg" \
  -F "latitude=37.5796" \
  -F "longitude=126.9770"

# 4. 성공 이미지 조회
curl "http://localhost:8000/success_images/USER_ID"

# 5. 통계 조회
curl "http://localhost:8000/success_images/USER_ID/stats"
```

## 📊 데이터베이스 스키마

### VISITS_COLLECTION 업데이트
```json
{
  "visit_id": "visit456",
  "session_id": "session123",
  "user_id": "user123",
  "target_place": "경복궁",
  "predicted_place": "경복궁",
  "is_correct": true,
  "score_earned": 10,
  "confidence": 0.95,
  "latitude": 37.5796,
  "longitude": 126.9770,
  "visit_time": "2024-01-15T10:30:00Z",
  "image_url": "https://storage.googleapis.com/..."  // 새로 추가된 필드
}
```

## 🔄 기존 코드와의 호환성

### 1. 기존 API 유지
- 모든 기존 API 엔드포인트가 그대로 작동
- 기존 방문 기록은 `image_url` 필드가 없어도 정상 동작

### 2. 점진적 업그레이드
- 새로운 방문 기록부터 이미지 URL 포함
- 기존 데이터는 자동으로 처리됨

### 3. 에러 처리
- 이미지 저장 실패 시에도 방문 기록은 정상 저장
- Firebase Storage 연결 실패 시 적절한 에러 메시지 반환

## 🚨 주의사항

### 1. 저장소 용량
- Firebase Storage 사용량 모니터링 필요
- 오래된 이미지 정리 정책 고려

### 2. 보안
- 이미지 URL이 공개되므로 민감한 정보 포함 금지
- 사용자 동의 확인 필요

### 3. 성능
- 이미지 업로드 시 네트워크 지연 가능성
- 대용량 이미지 처리 시 메모리 사용량 주의

### 4. 디버깅
- 서버 로그에서 이미지 저장 과정 확인 가능
- 정답 여부, 파일 경로, Storage URL 등 상세 로그 출력
- 이미지 저장 실패 시에도 방문 기록은 정상 저장

## 📈 향후 개선 사항

### 1. 이미지 최적화
- 자동 리사이징 및 압축
- 다양한 해상도 지원

### 2. 추가 기능
- 이미지 공유 기능
- 이미지 댓글 및 좋아요
- 이미지 갤러리 뷰

### 3. 관리 기능
- 이미지 삭제 기능
- 사용자별 저장소 용량 제한
- 이미지 백업 및 복구

### 4. 현재 구현된 기능
- ✅ 정답 시 자동 이미지 저장
- ✅ Firebase Storage 연동
- ✅ 사용자별 성공 이미지 조회
- ✅ 성공 이미지 통계 기능
- ✅ 상세한 디버깅 로그
- ✅ 에러 처리 및 복구 메커니즘 