import 'package:flutter/foundation.dart';

/// 서버 설정을 관리하는 클래스
/// 디버그 모드에서는 로컬 서버를, 릴리즈 모드에서는 클라우드 서버를 사용합니다.
class ServerConfig {
  // 로컬 서버 URL (개발용)
  static const String _localServerUrl = 'http://10.0.2.2:8000';
  
  // 클라우드 서버 URL (프로덕션용)
  static const String _cloudServerUrl = 'https://tourist-app-783243215272.asia-northeast3.run.app';
  
  /// 현재 모드에 따라 적절한 서버 URL을 반환합니다.
  /// 디버그 모드에서는 로컬 서버를, 릴리즈 모드에서는 클라우드 서버를 사용합니다.
  static String get serverUrl {
    if (kDebugMode) {
      // 디버그 모드에서는 로컬 서버 사용
      return _localServerUrl;
    } else {
      // 릴리즈 모드에서는 클라우드 서버 사용
      return _cloudServerUrl;
    }
  }
  
  /// 현재 서버 설정 정보를 디버깅용으로 반환합니다.
  static String get debugInfo {
    return '''
=== 서버 설정 정보 ===
현재 모드: ${kDebugMode ? '디버그' : '릴리즈'}
서버 URL: $serverUrl
로컬 서버 URL: $_localServerUrl
클라우드 서버 URL: $_cloudServerUrl
==================
''';
  }
  
  /// 로컬 서버 URL을 직접 반환합니다.
  static String get localServerUrl => _localServerUrl;
  
  /// 클라우드 서버 URL을 직접 반환합니다.
  static String get cloudServerUrl => _cloudServerUrl;
} 