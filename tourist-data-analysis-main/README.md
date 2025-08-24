# test_api.py 실행 가이드

test_api.py는 관광지 사진 인식 API의 테스트 코드입니다.

## 필수 파일

1. `api.py`: FastAPI 서버
2. `test_api.py`: 테스트 코드
3. `firebase_config.py`: Firebase 설정
4. `requirements.txt`: 필요한 패키지 목록
5. `tourapi-77ca1-firebase-adminsdk-fbsvc-3caf24d515.json`: Firebase 인증키
6. `query_images/`: 테스트용 이미지 폴더
   - 경복궁*7*공공3유형.jpg
   - 경희궁 흥화문*7*공공3유형.JPG
   - 광화문.jpg
   - 남산서울타워\_1004093.jpg
   - 북촌한옥마을*6*공공3유형.jpg
   - 청계천*3*공공3유형.JPG

## 실행 방법

### 1단계: 패키지 설치

먼저 필요한 Python 패키지들을 설치합니다:

```bash
pip install -r requirements.txt
```

또는 개별적으로 설치:

```bash
pip install fastapi uvicorn requests Pillow firebase-admin torch torchvision transformers
```

### 2단계: Firebase 인증키 설정

`tourapi-77ca1-firebase-adminsdk-fbsvc-3caf24d515.json` 파일을 프로젝트 루트 디렉토리에 위치시킵니다.

### 3단계: API 서버 실행

첫 번째 터미널에서 API 서버를 실행합니다:

```bash
python api.py
```

서버가 정상적으로 실행되면 다음과 같은 메시지가 출력됩니다:

```
INFO:     Started server process [PID]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

### 4단계: 테스트 실행

새로운 터미널을 열고 테스트를 실행합니다:

```bash
python test_api.py
```

테스트가 시작되면 다음과 같은 과정이 진행됩니다:

1. 서버 연결 확인
2. 사용자 생성
3. 게임 세션 시작
4. 각 관광지별 이미지 예측 테스트
5. 게임 종료
6. 랭킹 조회
7. 사용자 프로필 조회

## 주의사항

1. **서버 실행**: API 서버가 실행 중이어야 테스트가 가능합니다.
2. **Firebase 인증**: Firebase 인증키가 없으면 테스트가 실패합니다.
3. **테스트 이미지**: 테스트 이미지는 반드시 `query_images/` 폴더에 있어야 합니다.
4. **포트 충돌**: 포트 8000이 사용 중이면 서버 실행이 실패할 수 있습니다.
5. **인터넷 연결**: Firebase 연결을 위해 인터넷 연결이 필요합니다.

## 테스트 항목

test_api.py는 다음 기능들을 테스트합니다:

1. 이미지 인식 테스트

   - 모든 테스트 이미지에 대한 예측 정확도 검증
   - GPS 좌표 기반 위치 검증
   - 신뢰도 점수 확인

2. 사용자 관리 테스트

   - 사용자 생성
   - 중복 사용자명 처리
   - 사용자 프로필 조회

3. 게임 세션 테스트

   - 게임 세션 생성
   - 점수 시스템 검증
   - 게임 종료 처리

4. 랭킹 시스템 테스트
   - 다중 사용자 테스트
   - 랭킹 정렬 검증
   - 점수 집계 확인

## 테스트 결과 해석

테스트 실행 시 다음과 같은 결과가 출력됩니다:

- ✅: 테스트 성공
- ❌: 테스트 실패
- ⚠️: 경고 또는 건너뛴 테스트

각 테스트의 세부 결과에는 다음 정보가 포함됩니다:

- 예측된 관광지
- 신뢰도 점수
- GPS 거리 오차
- 획득한 게임 점수
