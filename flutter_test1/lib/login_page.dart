// login_page.dart

import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'main_page.dart'; // 새로 생성할 메인 페이지

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false; // 로딩 상태를 관리할 변수

  Future<void> _loginWithKakao(BuildContext context) async {
    // 이미 로딩 중이면 중복 호출 방지
    if (_isLoading) return;

    setState(() {
      _isLoading = true; // 로그인 시도 시 로딩 시작
    });
    
    try {
      print('=== 카카오 로그인 디버깅 시작 ===');
      print('앱 키: 4d2efcd88cc61a01eef82592368f8da9');
      print('패키지명: com.example.flutter_test1');
      print('현재 시간: ${DateTime.now()}');
      
      if (await isKakaoTalkInstalled()) {
        print('카카오톡 앱 설치됨 - 카카오톡으로 로그인 시도');
        await UserApi.instance.loginWithKakaoTalk();
      } else {
        print('카카오톡 앱 미설치 - 웹 로그인 시도');
        await UserApi.instance.loginWithKakaoAccount();
      }
      // ✅ 로그인 성공 후 토큰 확인
      AccessTokenInfo tokenInfo = await UserApi.instance.accessTokenInfo();
      print('✅ 토큰 유저 ID: ${tokenInfo.id}');
      print('✅ 토큰 만료까지 남은 시간: ${tokenInfo.expiresIn}초');
      
      print('로그인 성공 - 사용자 정보 가져오기');
      User user = await UserApi.instance.me();
      print('사용자 ID: ${user.id}');
      print('사용자 닉네임: ${user.kakaoAccount?.profile?.nickname}');
      print('사용자 이메일: ${user.kakaoAccount?.email}');

      if (!mounted) return;
      print('로그인 성공, MainPage로 이동 시도');

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => MainPage(user: user)),
      );
      print('Navigator 호출 완료');
    }on KakaoAuthException catch (e) {
      // 필수! – 실제 원인 코드가 여기 찍힙니다.
      print('❌ KakaoAuthException → ${e.error} / ${e.errorDescription}');
    } on KakaoClientException catch (e) {
      print('❌ KakaoClientException → $e');
    } catch (e) {
      print('❌ unknown error: $e');
    }
    // catch (error, stack) {
    //   print('카카오 로그인 실패: $error');
    //   print('스택트레이스: $stack');
    //   if (!mounted) return;
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해주세요.\n$error')),
    //   );
    // } finally {
    //   setState(() {
    //     _isLoading = false; // 로그인 시도 완료 시 로딩 종료
    //   });
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        // 배경 이미지를 위해 Stack 사용
        children: [
          // 배경 이미지 또는 그라디언트
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF88B04B), // 부드러운 시작 색상
                  Color(0xFFD0E6A5), // 부드러운 끝 색상
                ],
              ),
              // 만약 이미지를 사용하고 싶다면 아래 주석을 해제하고 'assets/background_image.jpg' 와 같은 경로로 설정
              // image: DecorationImage(
              //   image: AssetImage('assets/background_image.jpg'),
              //   fit: BoxFit.cover,
              // ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 앱 로고 또는 아이콘
                const Icon(
                  Icons.travel_explore, // 여행 관련 아이콘
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  '나만의 여행 일지를 만들어보세요!', // 더 매력적인 문구
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black45,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  '지금 바로 여행을 시작해 보세요!',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),
                _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ) // 로딩 중일 때 로딩 인디케이터 표시
                    : GestureDetector(
                        // ElevatedButton 대신 GestureDetector 사용
                        onTap: _isLoading
                            ? null
                            : () => _loginWithKakao(context), // 로딩 중일 때는 탭 비활성화
                        child: Image.asset(
                          'assets/kakao_login_large_wide.png', // 카카오 로그인 버튼 이미지
                          width:
                              MediaQuery.of(context).size.width *
                              0.8, // 화면 너비의 80%
                          // height: 48, // 이미지의 원본 비율을 유지하기 위해 높이 지정은 선택 사항
                        ),
                      ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    // ▼▼▼ 수정된 부분 ▼▼▼
                    // 게스트용 메인 페이지로 바로 이동합니다.
                    print('게스트로 시작하기 버튼 클릭');
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const MainPage.guest(),
                      ),
                    );
                    print('게스트로 시작하기 버튼 클릭 완료');
                    // ▲▲▲ 수정된 부분 ▲▲▲
                  },
                  child: const Text(
                    '게스트로 시작하기',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
