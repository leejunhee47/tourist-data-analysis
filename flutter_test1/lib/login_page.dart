// lib/login_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 사용자 취소 예외 처리를 위해 임포트
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'loading_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<void> _loginWithKakao(BuildContext context) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isConnected = await _checkConnectivity();
    if (!isConnected) {
      if (mounted) {
        setState(() {
          _errorMessage = '네트워크에 연결할 수 없습니다.\n인터넷 연결을 확인해주세요.';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // 카카오톡이 설치되어 있는지 확인
      if (await isKakaoTalkInstalled()) {
        try {
          // 카카오톡 로그인 시도
          await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          // 카카오톡 로그인 실패 시 (계정 연결 안됨 등) 카카오계정 로그인으로 fallback
          if (error is PlatformException &&
              (error.code == 'NotSupportError' ||
                  error.code == 'INVALID_REQUEST')) {
            print('카카오톡 로그인 실패, 카카오계정 로그인으로 전환: ${error.message}');
            await UserApi.instance.loginWithKakaoAccount();
          } else {
            // 다른 에러는 그대로 throw
            rethrow;
          }
        }
      } else {
        // 카카오톡이 설치되지 않은 경우 카카오계정 로그인
        await UserApi.instance.loginWithKakaoAccount();
      }

      User user = await UserApi.instance.me();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => LoadingPage(user: user)),
      );
    } catch (error, stackTrace) {
      print('카카오 로그인 에러');
      print('Error: $error');
      print('StackTrace: $stackTrace');

      if (error is PlatformException && error.code == 'CANCELED') {
        // 사용자가 취소한 경우
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _errorMessage = '로그인에 실패했습니다.\n잠시 후 다시 시도해주세요.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startAsGuest(BuildContext context) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isConnected = await _checkConnectivity();
    if (!isConnected) {
      if (mounted) {
        setState(() {
          _errorMessage = '네트워크에 연결할 수 없습니다.\n인터넷 연결을 확인해주세요.';
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoadingPage.guest()),
      );
    }
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                '로그인 오류',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() => _errorMessage = null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                ),
                child: const Text('확인'),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
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
                  onPressed: () => _startAsGuest(context),
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
          if (_errorMessage != null) _buildErrorOverlay(),
        ],
      ),
    );
  }
}
