# 통합 서버 GCP 배포 가이드

## 🚀 개요
이 가이드는 Flutter 프론트엔드와 Python 백엔드를 통합한 서버를 Google Cloud Platform(GCP)에 배포하는 방법을 설명합니다.

## 📋 사전 요구사항

### 1. GCP 계정 및 프로젝트 설정
```bash
# GCP CLI 설치 (Windows)
# https://cloud.google.com/sdk/docs/install 에서 다운로드

# 로그인
gcloud auth login

# 프로젝트 생성 (선택사항)
gcloud projects create YOUR_PROJECT_ID

# 프로젝트 설정
gcloud config set project YOUR_PROJECT_ID
```

### 2. 필요한 API 활성화
```bash
# Cloud Build API 활성화
gcloud services enable cloudbuild.googleapis.com

# Cloud Run API 활성화
gcloud services enable run.googleapis.com

# Container Registry API 활성화
gcloud services enable containerregistry.googleapis.com
```

### 3. Firebase 설정 (이미 완료된 경우 건너뛰기)
- Firebase 프로젝트와 GCP 프로젝트 연결
- 서비스 계정 키 파일 준비

## 🛠️ 배포 단계

### 1단계: 소스 코드 준비
```bash
# 현재 디렉토리 구조 확인
ls -la
# 다음 파일들이 있어야 함:
# - Dockerfile
# - cloudbuild.yaml
# - .dockerignore
# - tourist-data-analysis-main/
# - flutter_test1/
```

### 2단계: Cloud Build 실행
```bash
# Cloud Build 트리거 실행
gcloud builds submit --config cloudbuild.yaml .

# 또는 태그 지정하여 빌드
gcloud builds submit --config cloudbuild.yaml --substitutions=_BUILD_ID=v1.0.0 .
```

### 3단계: 배포 확인
```bash
# Cloud Run 서비스 상태 확인
gcloud run services list --region=asia-northeast3

# 서비스 URL 확인
gcloud run services describe tourist-app --region=asia-northeast3 --format="value(status.url)"
```

## 🔧 환경 변수 설정 (필요시)

### Firebase 서비스 계정 키 설정
```bash
# Secret Manager에 Firebase 키 저장
gcloud secrets create firebase-key --data-file=path/to/firebase-key.json

# Cloud Run 서비스에 시크릿 연결
gcloud run services update tourist-app \
    --region=asia-northeast3 \
    --set-env-vars="GOOGLE_APPLICATION_CREDENTIALS=/secrets/firebase-key.json" \
    --set-secrets="/secrets/firebase-key.json=firebase-key:latest"
```

## 📊 모니터링 및 로그

### 로그 확인
```bash
# Cloud Run 로그 확인
gcloud logs read "resource.type=cloud_run_revision" --limit=50

# 실시간 로그 모니터링
gcloud logs tail "resource.type=cloud_run_revision"
```

### 성능 모니터링
- GCP Console > Cloud Run > tourist-app > 지표 탭에서 확인
- 요청 수, 응답 시간, 오류율 등 모니터링 가능

## 🚨 문제 해결

### 빌드 실패 시
```bash
# 빌드 로그 확인
gcloud builds log [BUILD_ID]

# 일반적인 문제:
# 1. requirements.txt의 패키지 호환성 문제
# 2. Flutter 빌드 시간 초과 (cloudbuild.yaml의 timeout 증가)
# 3. 메모리 부족 (Dockerfile의 빌드 스테이지 최적화)
```

### 배포 후 접속 불가 시
```bash
# 서비스 상태 확인
gcloud run services describe tourist-app --region=asia-northeast3

# 포트 설정 확인 (8000번 포트 사용)
# 환경 변수 확인
# Firebase 연결 상태 확인
```

## 💰 비용 최적화

### 권장 설정
- **메모리**: 2Gi (AI 모델 로드용)
- **CPU**: 2개 (멀티코어 처리)
- **최대 인스턴스**: 10개 (트래픽에 따라 조정)
- **최소 인스턴스**: 0개 (비용 절약)

### 예상 비용 (월간)
- 낮은 트래픽 (1000 요청/월): $5-10
- 중간 트래픽 (10000 요청/월): $20-40
- 높은 트래픽 (100000 요청/월): $100-200

## 🔄 업데이트 및 롤백

### 새 버전 배포
```bash
# 새 버전 빌드 및 배포
gcloud builds submit --config cloudbuild.yaml .
```

### 이전 버전으로 롤백
```bash
# 이전 리비전 목록 확인
gcloud run revisions list --service=tourist-app --region=asia-northeast3

# 특정 리비전으로 롤백
gcloud run services update-traffic tourist-app \
    --region=asia-northeast3 \
    --to-revisions=REVISION_NAME=100
```

## 📱 도메인 연결 (선택사항)

### 커스텀 도메인 설정
```bash
# 도메인 매핑 생성
gcloud run domain-mappings create \
    --service=tourist-app \
    --domain=yourdomain.com \
    --region=asia-northeast3
```

## 🎯 성능 최적화

### 권장 사항
1. **CDN 설정**: Cloud CDN으로 정적 파일 캐싱
2. **압축**: gzip 압축 활성화
3. **이미지 최적화**: WebP 형식 사용
4. **캐싱**: Redis 또는 Memcached 사용 고려

## 📞 지원 및 문의

배포 중 문제가 발생하면:
1. 빌드 로그 확인
2. Cloud Run 서비스 로그 확인
3. Firebase 연결 상태 확인
4. 네트워크 및 방화벽 설정 확인

---

**배포 완료 후 서비스 URL로 접속하여 정상 작동을 확인하세요!** 🎉 