// main.dart

import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'login_page.dart'; // 새로 생성할 로그인 페이지

void main() {
  // Kakao SDK 초기화
  KakaoSdk.init(
    nativeAppKey: '4d2efcd88cc61a01eef82592368f8da9',
    javaScriptAppKey: 'aa68c996a365f43a8153e7d4cee31250',
    loggingEnabled: true,   // 👈 반드시 true
  ); // 여기에 발급받은 네이티브 앱 키를 입력하세요.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '나만의 서울 여행',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(), // 시작 페이지를 LoginPage로 변경
    );
  }
}
