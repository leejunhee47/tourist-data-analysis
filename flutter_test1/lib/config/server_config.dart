import 'package:flutter/foundation.dart';

/// 서버 설정을 관리하는 클래스
class ServerConfig {
  /// 현재 모드에 따른 서버 URL을 반환
  static String get serverUrl {
    // kReleaseMode를 사용하여 릴리즈 빌드인지 확인
    if (kReleaseMode) {
      // 릴리즈 빌드에서는 실제 서버 URL 사용
      return 'https://tourist-app-783243215272.asia-northeast3.run.app';
    } else {
      // 디버그 빌드에서는 로컬 서버 사용
      return 'http://10.0.2.2:8000'; // Android 에뮬레이터용
      // return 'http://localhost:8000'; // 실제 디바이스용
    }
  }

  /// 디버그 빌드인지 확인하는 메서드
  static bool _isDebugBuild() {
    // kReleaseMode의 반대값을 사용
    return !kReleaseMode;
  }

  /// API 엔드포인트를 포함한 전체 URL을 반환
  static String getApiUrl(String endpoint) {
    return '$serverUrl/$endpoint';
  }

  /// 현재 모드 정보를 반환 (디버깅용)
  static String get modeInfo {
    return _isDebugBuild() ? 'Debug APK' : 'Release APK';
  }

  /// 빌드 타입 상세 정보 (디버깅용)
  static String get buildInfo {
    return _isDebugBuild() 
        ? 'Debug APK - 로컬 서버 사용 (10.0.2.2:8000)'
        : 'Release APK - 실제 서버 사용 (tourist-app-783243215272.asia-northeast3.run.app)';
  }
  
  /// 서버 연결 테스트용 메서드
  static String get debugInfo {
    return '''
    서버 설정 정보:
    - 현재 모드: ${modeInfo}
    - 서버 URL: $serverUrl
    - 빌드 정보: $buildInfo
    ''';
  }
} 