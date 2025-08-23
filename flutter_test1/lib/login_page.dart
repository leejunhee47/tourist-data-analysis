// lib/login_page.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'loading_page.dart';
import 'config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;

  final TextEditingController _adminUsernameController =
      TextEditingController();
  final TextEditingController _adminPasswordController =
      TextEditingController();

  // --- [추가] 애니메이션 컨트롤러 ---
  late AnimationController _dialogAnimationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _dialogAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _dialogAnimationController,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _dialogAnimationController.dispose();
    _adminUsernameController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }
  // --- [추가 종료] ---

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
      if (await isKakaoTalkInstalled()) {
        try {
          await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          if (error is PlatformException &&
              (error.code == 'NotSupportError' ||
                  error.code == 'INVALID_REQUEST')) {
            print('카카오톡 로그인 실패, 카카오계정 로그인으로 전환: ${error.message}');
            await UserApi.instance.loginWithKakaoAccount();
          } else {
            rethrow;
          }
        }
      } else {
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

  // --- [수정] 어드민 로그인 다이얼로그 UI 개선 ---
  void _showAdminLoginDialog() {
    _dialogAnimationController.forward(from: 0.0);
    showDialog(
      context: context,
      builder: (context) {
        bool isAdminLoading = false;
        String? adminError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return ScaleTransition(
              scale: _scaleAnimation,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                titlePadding: EdgeInsets.zero,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                title: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: Colors.white),
                      SizedBox(width: 12),
                      Text(
                        '어드민 로그인',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    TextField(
                      controller: _adminUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _adminPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      obscureText: true,
                    ),
                    if (adminError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          adminError!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  ElevatedButton.icon(
                    icon: isAdminLoading
                        ? const SizedBox.shrink()
                        : const Icon(Icons.login),
                    label: isAdminLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('로그인'),
                    onPressed: isAdminLoading
                        ? null
                        : () async {
                            setDialogState(() {
                              isAdminLoading = true;
                              adminError = null;
                            });

                            try {
                              final response = await http.post(
                                Uri.parse('$serverUrl/admin_login/'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({
                                  'username': _adminUsernameController.text,
                                  'password': _adminPasswordController.text,
                                }),
                              );

                              if (response.statusCode == 200) {
                                final data = json
                                    .decode(utf8.decode(response.bodyBytes));
                                if (mounted) {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (context) => LoadingPage.admin(
                                        adminUserId: data['user_id'],
                                        adminUsername: data['username'],
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                final errorData = json
                                    .decode(utf8.decode(response.bodyBytes));
                                setDialogState(() {
                                  adminError = errorData['detail'] ?? '로그인 실패';
                                });
                              }
                            } catch (e) {
                              setDialogState(() {
                                adminError = '오류가 발생했습니다.';
                              });
                            } finally {
                              setDialogState(() {
                                isAdminLoading = false;
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.travel_explore,
                      size: 80, color: Colors.white),
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
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
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _showAdminLoginDialog,
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
                    child: const Text('어드민으로 로그인'),
                  ),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) _buildErrorOverlay(),
        ],
      ),
    );
  }
}
