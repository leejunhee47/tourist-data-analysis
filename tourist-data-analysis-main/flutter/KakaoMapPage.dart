import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'main.dart'; // main.dart에서 PhotoItem 클래스를 import
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class KakaoMapPage extends StatefulWidget {
  final List<PhotoItem>? photos;

  const KakaoMapPage({super.key, this.photos});

  @override
  State<KakaoMapPage> createState() => _KakaoMapPageState();
}

class _KakaoMapPageState extends State<KakaoMapPage> {
  late final WebViewController _controller;
  bool isMapLoaded = false;
  bool isMapInitialized = false;
  Position? currentPosition;
  bool isLocationLoading = false;
  String debugInfo = '';

  // _KakaoMapPageState 클래스 내부에 추가할 메서드들

  final ImagePicker _picker = ImagePicker();
  File? selectedImage;

  // 서버 URL 설정 (실제 서버 주소로 변경)
  final String serverUrl = 'http://192.168.219.102:8000'; // 실제 IP로 변경

  // 위치 정보를 서버로 전송하는 메서드
  Future<void> _sendLocationToServer(Position position) async {
    try {
      final url = Uri.parse('$serverUrl/location');

      final body = json.encode({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('서버로 위치 전송 시도: $body'); // 디버그용

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      print('서버 응답 상태: ${response.statusCode}'); // 디버그용
      print('서버 응답 내용: ${response.body}'); // 디버그용

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        setState(() {
          debugInfo = '서버 전송 성공: ${responseData['message']}';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('위치 정보가 서버로 전송되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('서버 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      print('서버 전송 오류: $e');
      setState(() {
        debugInfo = '서버 전송 실패: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서버 전송 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      // 권한 요청
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.storage,
        Permission.photos,
      ].request();

      bool allGranted = true;
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          allGranted = false;
        }
      });

      if (!allGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('앱을 사용하기 위해서는 카메라와 저장소 권한이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 권한이 허용된 경우에만 이미지 선택 다이얼로그 표시
      showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('카메라로 촬영'),
                  onTap: () {
                    Navigator.pop(context);
                    _getImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('갤러리에서 선택'),
                  onTap: () {
                    Navigator.pop(context);
                    _getImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      print('사진 선택 오류: $e');
    }
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          selectedImage = File(image.path);
        });

        // 선택한 사진을 서버로 전송
        await _uploadImageToServer(File(image.path));
      }
    } catch (e) {
      print('이미지 선택 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 선택 실패: $e')));
      }
    }
  }

  Future<void> _uploadImageToServer(File imageFile) async {
    try {
      final url = Uri.parse('$serverUrl/upload-image');

      var request = http.MultipartRequest('POST', url);

      // 이미지 파일 추가
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      // 위치 정보도 함께 전송
      if (currentPosition != null) {
        request.fields['latitude'] = currentPosition!.latitude.toString();
        request.fields['longitude'] = currentPosition!.longitude.toString();
      }

      request.fields['timestamp'] = DateTime.now().toIso8601String();

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('사진이 서버로 전송되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('서버 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      print('이미지 업로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 업로드 실패: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _getCurrentLocation();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('페이지 로드 시작: $url');
            setState(() {
              debugInfo = '페이지 로드 시작...';
            });
          },
          onPageFinished: (String url) {
            print('페이지 로드 완료: $url');
            setState(() {
              debugInfo = '페이지 로드 완료';
            });
            _onMapLoaded();
          },
          onWebResourceError: (WebResourceError error) {
            print('웹 리소스 오류: $error');
            setState(() {
              debugInfo = '웹 리소스 오류: ${error.description}';
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          print('JavaScript 메시지: ${message.message}');
          setState(() {
            debugInfo = 'JS 메시지: ${message.message}';
          });
        },
      )
      ..loadFlutterAsset('assets/kakaomapTest.html');
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isLocationLoading = true;
      debugInfo = '위치 정보 요청 중...';
    });

    try {
      // 위치 서비스 활성화 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('위치 서비스 활성화: $serviceEnabled');

      if (!serviceEnabled) {
        setState(() {
          debugInfo = '위치 서비스가 비활성화됨';
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('위치 서비스가 비활성화되어 있습니다.')));
        }
        setState(() {
          isLocationLoading = false;
        });
        return;
      }

      // 위치 권한 확인
      LocationPermission permission = await Geolocator.checkPermission();
      print('현재 위치 권한: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('권한 요청 결과: $permission');

        if (permission == LocationPermission.denied) {
          setState(() {
            debugInfo = '위치 권한이 거부됨';
          });
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('위치 권한이 거부되었습니다.')));
          }
          setState(() {
            isLocationLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          debugInfo = '위치 권한이 영구적으로 거부됨';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.'),
            ),
          );
        }
        setState(() {
          isLocationLoading = false;
        });
        return;
      }

      // 현재 위치 가져오기
      setState(() {
        debugInfo = '위치 좌표 가져오는 중...';
      });

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      print('현재 위치 획득: ${position.latitude}, ${position.longitude}');

      setState(() {
        currentPosition = position;
        isLocationLoading = false;
        debugInfo =
            '위치 획득 완료: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      });

      // 서버로 위치 전송 추가
      await _sendLocationToServer(position);

      // 지도가 초기화된 후 현재 위치 표시
      if (isMapInitialized) {
        await _addCurrentLocationToMap();
      } else {
        setState(() {
          debugInfo = '위치는 획득했지만 지도가 아직 초기화되지 않음';
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '현재 위치: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('위치 가져오기 오류: $e');
      setState(() {
        isLocationLoading = false;
        debugInfo = '위치 오류: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('현재 위치를 가져올 수 없습니다: $e')));
      }
    }
  }

  Future<void> _addCurrentLocationToMap() async {
    if (currentPosition != null && isMapInitialized) {
      try {
        print(
          'JavaScript 실행 시도: 위도=${currentPosition!.latitude}, 경도=${currentPosition!.longitude}',
        );

        // JavaScript 함수 존재 확인
        String checkFunctionJs = '''
          (function() {
            if (typeof addCurrentLocationMarker === 'function') {
              return 'function_exists';
            } else {
              return 'function_not_found';
            }
          })();
        ''';

        final functionCheck = await _controller.runJavaScriptReturningResult(
          checkFunctionJs,
        );
        print('JavaScript 함수 존재 확인: $functionCheck');

        if (functionCheck.toString().contains('function_not_found')) {
          setState(() {
            debugInfo = 'JavaScript 함수가 존재하지 않음';
          });
          return;
        }

        // 현재 위치 마커 추가
        String jsCode =
            '''
          try {
            console.log('addCurrentLocationMarker 호출: ${currentPosition!.latitude}, ${currentPosition!.longitude}');
            addCurrentLocationMarker(${currentPosition!.latitude}, ${currentPosition!.longitude});
            'marker_added_successfully';
          } catch (error) {
            console.error('마커 추가 오류:', error);
            'error: ' + error.message;
          }
        ''';

        final result = await _controller.runJavaScriptReturningResult(jsCode);
        print('JavaScript 실행 결과: $result');

        setState(() {
          debugInfo = '마커 추가 시도 완료: $result';
        });
      } catch (e) {
        print('현재 위치 마커 추가 JavaScript 실행 오류: $e');
        setState(() {
          debugInfo = 'JS 실행 오류: $e';
        });
      }
    } else {
      print(
        '마커 추가 실패 - 위치: ${currentPosition != null}, 지도 초기화: $isMapInitialized',
      );
      setState(() {
        debugInfo =
            '마커 추가 실패 - 위치: ${currentPosition != null}, 지도 초기화: $isMapInitialized';
      });
    }
  }

  void _onMapLoaded() {
    print('지도 로드 완료');
    setState(() {
      debugInfo = '지도 로드 완료, 초기화 대기 중...';
    });

    // 지연 후 지도 초기화 완료로 설정
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() {
          isMapLoaded = true;
          isMapInitialized = true;
          debugInfo = '지도 초기화 완료';
        });

        // 현재 위치가 있으면 지도에 표시
        if (currentPosition != null) {
          _addCurrentLocationToMap();
        }
      }
    });
  }

  // 테스트용 가짜 위치 추가
  void _addTestLocation() {
    setState(() {
      // 서울 시청 좌표
      currentPosition = Position(
        latitude: 37.5665,
        longitude: 126.978,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      debugInfo = '테스트 위치 설정: 서울 시청';
    });

    if (isMapInitialized) {
      _addCurrentLocationToMap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("내 위치 찾기"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: _pickImage,
            tooltip: '사진 추가',
          ),
          if (isLocationLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _getCurrentLocation,
              tooltip: '내 위치 새로고침',
            ),
          // 서버 전송 버튼 추가
          if (currentPosition != null)
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed: () => _sendLocationToServer(currentPosition!),
              tooltip: '서버로 위치 전송',
            ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _addTestLocation,
            tooltip: '테스트 위치 (서울 시청)',
          ),
        ],
      ),
      body: Column(
        children: [
          // 디버그 정보 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '디버그 정보:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  debugInfo,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (currentPosition != null)
                  Text(
                    '현재 위치: ${currentPosition!.latitude.toStringAsFixed(6)}, ${currentPosition!.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  '지도 로드: $isMapLoaded, 초기화: $isMapInitialized',
                  style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                ),
              ],
            ),
          ),
          // 지도 영역
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (!isMapLoaded)
                  Container(
                    color: Colors.white,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('지도를 불러오는 중...'),
                        ],
                      ),
                    ),
                  ),
                if (isLocationLoading && isMapLoaded)
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text(
                            '현재 위치를 찾고 있습니다...',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (currentPosition == null &&
                    !isLocationLoading &&
                    isMapLoaded)
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_off,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '위치를 찾을 수 없습니다. 새로고침 또는 테스트 버튼을 눌러주세요.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
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
