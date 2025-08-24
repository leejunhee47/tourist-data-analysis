// main.dart

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'login_page.dart'; // 새로 생성할 로그인 페이지

Future main() async {
  // runApp()을 호출하기 전에 위젯 바인딩을 초기화합니다.
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 위젯 바인딩이 완료될 때까지 네이티브 스플래시 화면을 유지합니다.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Kakao SDK 초기화
  KakaoSdk.init(
    nativeAppKey: '4d2efcd88cc61a01eef82592368f8da9',
    javaScriptAppKey: 'aa68c996a365f43a8153e7d4cee31250',
    loggingEnabled: true, // 👈 반드시 true
  );

  // 스플래시 화면을 보여주기 위해 3초간 대기합니다.
  await initialization();

  runApp(
    const MyApp(),
  );
}

Future initialization() async {
  // 3초 동안 지연시켜 스플래시 화면을 표시합니다.
  await Future.delayed(const Duration(seconds: 2));
  // 3초 후 네이티브 스플래시 화면을 제거합니다.
  FlutterNativeSplash.remove();
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
