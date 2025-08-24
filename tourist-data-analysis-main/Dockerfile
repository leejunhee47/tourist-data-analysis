# Python 이미지 사용
FROM python:3.11.5

# 작업 디렉토리 설정 (Linux 스타일 경로로 변경)
WORKDIR /app

# 시스템 빌드 도구 설치 및 캐시 정리 (필요한 경우)
# 이 단계는 pip install이 실패하는 주요 원인 중 하나인 빌드 종속성 문제를 해결합니다.
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc python3-dev build-essential && \
    rm -rf /var/lib/apt/lists/*

# 의존성 파일 복사 및 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY . .

# 컨테이너가 8000번 포트를 외부에 노출하도록 설정
EXPOSE 8000

# 컨테이너 시작 시 실행할 명령어
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]