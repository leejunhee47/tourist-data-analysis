// login_page.dart

import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
// import 'main_page.dart'; // 더 이상 사용하지 않음
import 'KakaoMapPage.dart'; // KakaoMapPage를 임포트

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  Future<void> _loginWithKakao(BuildContext context) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      if (await isKakaoTalkInstalled()) {
        await UserApi.instance.loginWithKakaoTalk();
      } else {
        await UserApi.instance.loginWithKakaoAccount();
      }

      User user = await UserApi.instance.me();
      if (!mounted) return;

      // ▼▼▼ 수정된 부분 ▼▼▼
      // MainPage 대신 KakaoMapPage로 사용자를 전달합니다.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => KakaoMapPage(user: user)),
      );
      // ▲▲▲ 수정된 부분 ▲▲▲
    } catch (error) {
      print('카카오 로그인 실패: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해주세요.')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startAsGuest(BuildContext context) {
    if (_isLoading) return;

    // ▼▼▼ 추가된 부분 ▼▼▼
    // 게스트용 MainPage.guest() 대신 KakaoMapPage.guest()를 사용합니다.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const KakaoMapPage.guest()),
    );
    // ▲▲▲ 추가된 부분 ▲▲▲
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/seoul_background.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.4),
                  BlendMode.darken,
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.travel_explore, size: 80, color: Colors.white),
                const SizedBox(height: 24),
                const Text(
                  '나만의 여행 일지를 만들어보세요!',
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
                      )
                    : GestureDetector(
                        onTap: () => _loginWithKakao(context),
                        child: Image.asset(
                          'assets/kakao_login_large_wide.png',
                          width: MediaQuery.of(context).size.width * 0.8,
                        ),
                      ),
                const SizedBox(height: 20),
                TextButton(
                  // ▼▼▼ 수정된 부분 ▼▼▼
                  onPressed: () => _startAsGuest(context),
                  // ▲▲▲ 수정된 부분 ▲▲▲
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Colors.white70),
                    ),
                  ),
                  child: const Text('게스트로 시작하기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
