# Stage 1: Build Flutter Web App
# Use a stable Ubuntu base image to avoid Docker Hub auth issues
FROM ubuntu:22.04 AS flutter_builder

# Set UTF-8 encoding to handle Korean file names
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 1. Install essential packages and dependencies for Flutter
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libgconf-2-4 \
    libglu1-mesa \
    libgtk-3-0 \
    libnss3 \
    libasound2 \
    fonts-droid-fallback \
    chromium-browser \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Flutter SDK
ENV FLUTTER_VERSION="3.22.2"
ENV FLUTTER_CHANNEL="stable"
ENV FLUTTER_HOME="/opt/flutter"
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"
ENV CHROME_EXECUTABLE=/usr/bin/chromium-browser

RUN curl -fL "https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_CHANNEL}/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz" --output flutter.tar.xz && \
    tar -xf flutter.tar.xz -C /opt/ && \
    rm flutter.tar.xz

# 3. Configure Flutter
# Add /opt/flutter to git's safe directories to avoid ownership errors
RUN git config --global --add safe.directory ${FLUTTER_HOME}
RUN flutter doctor -v
RUN flutter config --enable-web
RUN flutter config --no-analytics  # 분석 비활성화

# 4. Build the app
WORKDIR /app
COPY flutter_test1/pubspec.* ./
RUN flutter pub get
COPY flutter_test1/ ./
RUN flutter build web --release --no-tree-shake-icons

# Stage 2: Python Backend
# Use a standard Python image
FROM python:3.11-slim

# Set UTF-8 encoding to handle Korean file names
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install system dependencies and Google Cloud SDK
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    git \
    curl \
    gnupg \
    lsb-release \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && apt-get update && apt-get install -y --no-install-recommends google-cloud-sdk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# GCS에서 모델 다운로드하는 부분은 cloudbuild.yaml로 이동했으므로 제거
# RUN mkdir -p fine_tuned_model && \
#     gsutil cp gs://tourapi-77ca1-models/new_best_model.pth fine_tuned_model/

# Copy and install Python requirements
COPY tourist-data-analysis-main/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# CORRECTED: Copy the backend source code from the build context
COPY tourist-data-analysis-main/ .

# This part is correct: it copies the built frontend from the previous stage
COPY --from=flutter_builder /app/build/web ./static

# Create a non-root user for security
RUN useradd --system --create-home appuser && \
    mkdir -p /app/temp_images && \
    chown -R appuser:appuser /app
USER appuser

# EXPOSE 8000 is removed as it's informational.
# The container will listen on the port specified by the PORT env var from Cloud Run.
CMD uvicorn api:app --host 0.0.0.0 --port ${PORT:-8000} 