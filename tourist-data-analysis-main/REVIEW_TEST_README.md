# 📝 리뷰 API 엔드포인트 테스트 가이드

리뷰 기능의 백엔드 API 엔드포인트를 테스트하기 위한 가이드입니다.

## 🚀 테스트 실행

### 1. 간단한 테스트 (추천)
```bash
cd tourist-data-analysis-main
python run_review_test.py
```

### 2. 전체 테스트
```bash
cd tourist-data-analysis-main
python test_review_api.py
```

## 📋 테스트 시나리오

### ✅ 성공 케이스
1. **리뷰 저장 성공** (POST /reviews/)
   - 20자 이상의 리뷰 텍스트
   - 유효한 사용자 ID
   - +20점 자동 지급

2. **리뷰 목록 조회** (GET /reviews/{user_id})
   - 특정 사용자의 모든 리뷰 조회
   - 생성일 기준 내림차순 정렬

3. **여러 리뷰 저장**
   - 여러 장소에 대한 리뷰 저장
   - 점수 누적 확인

### ❌ 실패 케이스
1. **짧은 리뷰 텍스트**
   - 20자 미만의 리뷰
   - 400 Bad Request 반환

2. **존재하지 않는 사용자**
   - 유효하지 않은 사용자 ID
   - 404 Not Found 반환

## 🔧 테스트 전 준비사항

### 1. 서버 실행
```bash
cd tourist-data-analysis-main
python api.py
```

### 2. 의존성 확인
```bash
pip install requests
```

### 3. Firestore 인덱스 설정 (중요!)
리뷰 목록 조회 시 인덱스 오류가 발생할 수 있습니다.

#### 인덱스 생성 방법:
```bash
# 인덱스 생성 가이드 실행
python create_firestore_indexes.py
```

#### 수동 인덱스 생성:
1. [Firebase Console](https://console.firebase.google.com/project/tourapi-77ca1/firestore/indexes) 접속
2. '복합 인덱스' 탭 클릭
3. '인덱스 만들기' 클릭
4. 컬렉션 ID: `reviews` 입력
5. 필드 추가:
   - `user_id` (오름차순)
   - `created_at` (내림차순)
6. '만들기' 클릭
7. 인덱스 생성 완료까지 대기 (몇 분 소요)

## 📊 테스트 결과 예시

### 성공적인 테스트 실행 결과:
```
🚀 리뷰 API 엔드포인트 테스트 시작
========================================
1️⃣ 테스트 사용자 생성 중...
✅ 사용자 생성 완료: test_user_1703123456 (ID: user_abc123)

2️⃣ 리뷰 저장 테스트 (POST /reviews/)
✅ 리뷰 저장 성공!
   리뷰 ID: review_xyz789
   장소: 경복궁
   획득 점수: +20점

3️⃣ 리뷰 목록 조회 테스트 (GET /reviews/{user_id})
✅ 리뷰 목록 조회 성공!
   총 리뷰 수: 1개
   첫 번째 리뷰: 경복궁
   리뷰 내용: 정말 아름다운 궁궐이었습니다. 조선왕조의 웅장함을...

4️⃣ 짧은 리뷰 테스트 (실패 케이스)
✅ 예상된 실패 케이스!
   에러 메시지: 리뷰는 20자 이상 작성해주세요.

🎉 모든 리뷰 엔드포인트 테스트가 성공했습니다!
```

## 🧪 리뷰 API 엔드포인트

### 1. 리뷰 저장
```http
POST /reviews/
Content-Type: application/json

{
  "user_id": "user_123",
  "place_name": "경복궁",
  "review_text": "정말 아름다운 궁궐이었습니다...",
  "image_url": null
}
```

**응답:**
```json
{
  "review_id": "review_abc123",
  "user_id": "user_123",
  "place_name": "경복궁",
  "review_text": "정말 아름다운 궁궐이었습니다...",
  "image_url": null,
  "created_at": "2024-01-15T10:30:00",
  "score_earned": 20,
  "message": "리뷰가 성공적으로 저장되었습니다! +20점 획득!"
}
```

### 2. 리뷰 목록 조회
```http
GET /reviews/{user_id}
```

**응답:**
```json
{
  "user_id": "user_123",
  "reviews": [
    {
      "review_id": "review_abc123",
      "place_name": "경복궁",
      "review_text": "정말 아름다운 궁궐이었습니다...",
      "image_url": null,
      "created_at": "2024-01-15T10:30:00",
      "score_earned": 20
    }
  ],
  "total_reviews": 1
}
```

## ⚠️ 주의사항

1. **서버 실행 필수**: 테스트 전에 API 서버가 실행 중이어야 합니다.
2. **Firebase 연결**: Firebase 프로젝트가 올바르게 설정되어 있어야 합니다.
3. **네트워크 연결**: 인터넷 연결이 필요합니다 (Firebase 접근용).
4. **Firestore 인덱스**: 리뷰 목록 조회를 위해 복합 인덱스가 필요합니다.

## 🔍 문제 해결

### 서버 연결 실패
```
❌ 사용자 생성 실패: Connection refused
```
**해결방법**: `python api.py`로 서버를 실행하세요.

### Firebase 오류
```
❌ 리뷰 저장 실패: 500
```
**해결방법**: Firebase 설정과 Secret Manager 설정을 확인하세요.

### 권한 오류
```
❌ 리뷰 저장 실패: 404
```
**해결방법**: 사용자 ID가 올바른지 확인하세요.

### 🔥 Firestore 인덱스 오류 (가장 중요!)
```
❌ 리뷰 목록 조회 실패: 500
에러: {"detail":"400 The query requires an index..."}
```
**해결방법**:
1. [Firebase Console](https://console.firebase.google.com/project/tourapi-77ca1/firestore/indexes) 접속
2. '복합 인덱스' 탭 클릭
3. '인덱스 만들기' 클릭
4. 컬렉션 ID: `reviews` 입력
5. 필드 추가:
   - `user_id` (오름차순)
   - `created_at` (내림차순)
6. '만들기' 클릭
7. 인덱스 상태가 '사용 가능'으로 변경될 때까지 대기 (몇 분 소요)

#### 인덱스 생성 확인:
```bash
python create_firestore_indexes.py
```

## 📈 성능 테스트

대량의 리뷰를 테스트하려면:
```bash
python test_review_api.py
```

이 스크립트는 다음을 테스트합니다:
- 5개의 서로 다른 장소에 대한 리뷰 저장
- 점수 누적 확인
- 리뷰 목록 정렬 확인
- 에러 처리 검증