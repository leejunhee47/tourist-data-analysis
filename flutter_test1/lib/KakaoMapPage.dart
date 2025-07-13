// KakaoMapPage.dart

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'PhotoItem.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

class KakaoMapPage extends StatefulWidget {
  final User? user; // User를 nullable로 변경
  final List<PhotoItem>? photos;
  final String sessionId;
  // ▼▼▼ 추가됨 ▼▼▼
  final Map<String, Map<String, double>> placeCoords;
  // ▼▼▼ 추가 ▼▼▼

  // ▼▼▼ 수정된 생성자 ▼▼▼
  const KakaoMapPage({
    super.key,
    this.user, // required 키워드 제거
    this.photos,
    required this.sessionId,
    required this.placeCoords,
  });
  // ▲▲▲ 수정된 생성자 ▲▲▲

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
  // ▼▼▼ 추가/수정된 상태 변수 ▼▼▼
  final ImagePicker _picker = ImagePicker();
  String? _currentTargetPlace; // 사용자가 사진을 제출하려는 장소를 저장합니다.
  bool _isSubmitting = false; // 제출 중 로딩 인디케이터를 표시하기 위함입니다.
  //final String serverUrl = 'http://220.121.160.203:8000';
  // 실제 서버 IP로 변경해야 합니다.
  final String serverUrl = 'https://tourist-app-783243215272.asia-northeast3.run.app';

  bool _touristMarkersAdded = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _getCurrentLocation();
    debugInfo = "게임 세션 시작 ID: ${widget.sessionId}";
  }

  @override
  void dispose() {
    // 페이지가 닫힐 때 게임 세션을 종료합니다.
    _endGameSession();
    super.dispose();
  }

  Future<void> _endGameSession() async {
    try {
      final url = Uri.parse('$serverUrl/end_game/${widget.sessionId}');
      final response = await http.post(url);
      if (response.statusCode == 200) {
        print('게임 세션 종료 성공: ${response.body}');
      } else {
        print('게임 세션 종료 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('게임 세션 종료 오류: $e');
    }
  }

  // ▼▼▼ 신규: 예측을 위해 이미지, 위치, 타겟을 제출하는 메인 함수 ▼▼▼
  Future<void> _submitPrediction(File imageFile, String targetPlace) async {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 알 수 없어 사진을 전송할 수 없습니다.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      debugInfo = '서버로 예측 요청 전송 중...';
    });
    try {
      final url = Uri.parse('$serverUrl/predict/');
      var request = http.MultipartRequest('POST', url);
      // api.py에 명시된 모든 필수 필드를 추가합니다.
      request.fields['session_id'] = widget.sessionId;
      request.fields['target_place'] = targetPlace;
      request.fields['latitude'] = currentPosition!.latitude.toString();
      request.fields['longitude'] = currentPosition!.longitude.toString();
      // 이미지 파일 추가
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final decodedData = json.decode(responseData);
      if (response.statusCode == 200) {
        final String message = decodedData['message'];
        final int score = decodedData['score_earned'];
        final bool isCorrect = decodedData['is_correct'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('결과: $message (획득 점수: $score점)'),
            backgroundColor: isCorrect ? Colors.green : Colors.orange,
          ),
        );
        setState(() {
          debugInfo = '예측 성공: $message';
        });
      } else {
        throw Exception('예측 실패: ${decodedData['detail']}');
      }
    } catch (e) {
      print('예측 전송 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        debugInfo = '예측 오류: $e';
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  // 수정됨: _getImage는 이제 _submitPrediction을 호출합니다.
  Future<void> _getImage(ImageSource source) async {
    if (_currentTargetPlace == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 지도에서 인증할 관광지를 선택해주세요.')));
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (image != null) {
        // 새로운 예측 함수를 호출합니다.
        await _submitPrediction(File(image.path), _currentTargetPlace!);
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

  // 수정됨: _pickImage는 이제 타겟이 먼저 선택되었는지 확인합니다.
  Future<void> _pickImage() async {
    if (_currentTargetPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 지도에서 인증할 관광지 마커를 눌러 선택해주세요!')),
      );
      return;
    }

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
  }

  // 수정됨: _showPhotoDetail은 이제 사진 제출 프로세스를 시작하는 버튼을 포함합니다.
  void _showPhotoDetail(PhotoItem photo) {
    // 미리 정의된 장소 목록에서 일치하는 장소 이름을 찾습니다.
    final matchedPlace = widget.placeCoords.keys.firstWhere(
      (place) =>
          photo.galTitle.contains(place) ||
          photo.galSearchKeyword.contains(place),
      orElse: () => '',
    );
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                title: Text(
                  photo.galTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Image.network(
                        photo.galWebImageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 200,
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 80,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '제목: ${photo.galTitle}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('위치: ${photo.galPhotographyLocation}'),
                            const SizedBox(height: 16),
                            // ▼▼▼ 추가된 버튼 ▼▼▼
                            if (matchedPlace.isNotEmpty)
                              Center(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: Text('$matchedPlace 인증 사진 찍기'),
                                  onPressed: () {
                                    setState(() {
                                      _currentTargetPlace = matchedPlace;
                                      debugInfo = '타겟 설정: $_currentTargetPlace';
                                    });
                                    Navigator.of(context).pop(); // 다이얼로그 닫기
                                    _pickImage(); // 카메라/갤러리 열기
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[400],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    textStyle: const TextStyle(fontSize: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          try {
            final data = jsonDecode(message.message);
            if (data['type'] == 'markerClick') {
              final String contentId = data['contentId'].toString();
              final photo = widget.photos?.firstWhere(
                (p) => p.galContentId == contentId,
                // orElse: () => null, // PhotoItem.empty()는 적합하지 않으므로 주석 처리
              );
              if (photo != null) {
                _showPhotoDetail(photo);
              }
            }
          } catch (e) {
            print("JavaScript 메시지 파싱 오류: $e");
          }
        },
      )
      ..loadFlutterAsset('assets/kakaomapTest.html');
  }

  void _onMapLoaded() {
    print('지도 로드 완료');
    setState(() {
      debugInfo = '지도 로드 완료, 초기화 대기 중...';
    });
    // 지연 후 지도 초기화 완료로 설정
    Future.delayed(const Duration(milliseconds: 3000), () async {
      if (mounted) {
        setState(() {
          isMapLoaded = true;
          isMapInitialized = true;
          debugInfo = '지도 초기화 완료';
        });

        // 관광지 사진 마커 표시 (먼저 실행)
        await _displayTouristPhotos();

        // 현재 위치가 있으면 지도에 표시
        if (currentPosition != null) {
          await _addCurrentLocationToMap();
        }
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isLocationLoading = true;
      debugInfo = '위치 정보 요청 중...';
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          debugInfo = '위치 서비스가 비활성화됨';
        });
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('위치 서비스가 비활성화되어 있습니다.')));
        setState(() {
          isLocationLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            debugInfo = '위치 권한이 거부됨';
          });
          if (mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('위치 권한이 거부되었습니다.')));
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.'),
            ),
          );
        setState(() {
          isLocationLoading = false;
        });
        return;
      }

      setState(() {
        debugInfo = '위치 좌표 가져오는 중...';
      });
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      setState(() {
        currentPosition = position;
        isLocationLoading = false;
        debugInfo =
            '위치 획득 완료: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      });
      if (isMapInitialized) {
        await _reinitializeMap();
        await _displayTouristPhotos();
        await _addCurrentLocationToMap();
        await Future.delayed(const Duration(milliseconds: 800));
        await _adjustMapBounds();
      } else {
        setState(() {
          debugInfo = '위치는 획득했지만 지도가 아직 초기화되지 않음';
        });
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

  Future<void> _displayTouristPhotos() async {
    if (widget.photos == null || widget.photos!.isEmpty || !isMapInitialized) {
      return;
    }
    print("관광지 사진 ${widget.photos!.length}개를 지도에 표시합니다.");

    for (final photo in widget.photos!) {
      String? matchedPlace;
      for (final placeName in widget.placeCoords.keys) {
        if (photo.galTitle.contains(placeName) ||
            photo.galSearchKeyword.contains(placeName) ||
            photo.galPhotographyLocation.contains(placeName)) {
          matchedPlace = placeName;
          break;
        }
      }

      if (matchedPlace != null) {
        final coords = widget.placeCoords[matchedPlace]!;
        final lat = coords['lat'];
        final lng = coords['lng'];
        final imageUrl = photo.galWebImageUrl;
        final title = photo.galTitle
            .replaceAll("'", "\\'")
            .replaceAll('"', '\\"');
        final contentId = photo.galContentId;

        final jsCode =
            "addPhotoMarker($lat, $lng, '$imageUrl', '$title', '$contentId');";
        try {
          await _controller.runJavaScript(jsCode);
          print("JS 실행: $matchedPlace 마커 추가");
        } catch (e) {
          print("JS 실행 오류 ($matchedPlace): $e");
        }
      }
    }

    setState(() {
      _touristMarkersAdded = true;
    });
    await _adjustMapBounds();
  }

  Future<void> _addCurrentLocationToMap() async {
    if (currentPosition != null && isMapInitialized) {
      try {
        String jsCode =
            '''addCurrentLocationMarker(${currentPosition!.latitude}, ${currentPosition!.longitude}, false);''';
        await _controller.runJavaScript(jsCode);
        await _adjustMapBounds();
      } catch (e) {
        print('현재 위치 마커 추가 JavaScript 실행 오류: $e');
        setState(() {
          debugInfo = 'JS 실행 오류: $e';
        });
      }
    }
  }

  Future<void> _adjustMapBounds() async {
    if (currentPosition == null &&
        (widget.photos == null || widget.photos!.isEmpty)) {
      return;
    }
    List<Map<String, double>> allPoints = [];
    if (currentPosition != null) {
      allPoints.add({
        'lat': currentPosition!.latitude,
        'lng': currentPosition!.longitude,
      });
    }
    if (widget.photos != null) {
      for (final photo in widget.photos!) {
        String? matchedPlace;
        for (final placeName in widget.placeCoords.keys) {
          if (photo.galTitle.contains(placeName) ||
              photo.galSearchKeyword.contains(placeName)) {
            matchedPlace = placeName;
            break;
          }
        }
        if (matchedPlace != null) {
          allPoints.add({
            'lat': widget.placeCoords[matchedPlace]!['lat']!,
            'lng': widget.placeCoords[matchedPlace]!['lng']!,
          });
        }
      }
    }
    if (allPoints.isEmpty) return;
    final pointsJson = jsonEncode(allPoints);
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      await _controller.runJavaScript('fitMapBounds($pointsJson)');
      print('JS fitMapBounds 함수 호출 완료. 좌표 개수: ${allPoints.length}');
    } catch (e) {
      print('JS fitMapBounds 함수 호출 오류: $e');
    }
  }

  Future<void> _reinitializeMap() async {
    if (!isMapInitialized) return;
    try {
      await _controller.runJavaScript('clearAllMarkers();');
      setState(() {
        _touristMarkersAdded = false;
      });
      print('지도 전체 초기화 완료');
    } catch (e) {
      print('지도 초기화 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTargetPlace ?? "서울 관광 지도"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _getCurrentLocation,
              tooltip: '내 위치 새로고침',
            ),
        ],
      ),
      body: Stack(
        // body를 Stack으로 감싸 로딩 인디케이터를 오버레이합니다.
        children: [
          Column(
            children: [
              Container(
                // width: double.infinity,
                // padding: const EdgeInsets.all(8),
                // color: Colors.blue.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Text(
                    //   '디버그 정보:',
                    //   style: TextStyle(
                    //     fontWeight: FontWeight.bold,
                    //     fontSize: 12,
                    //     color: Colors.blue.shade800,
                    //   ),
                    // ),
                    // Text(
                    //   debugInfo,
                    //   style: TextStyle(
                    //     fontSize: 11,
                    //     color: Colors.blue.shade700,
                    //   ),
                    // ),
                    // if (currentPosition != null)
                    //   Text(
                    //     '현재 위치: ${currentPosition!.latitude.toStringAsFixed(6)}, ${currentPosition!.longitude.toStringAsFixed(6)}',
                    //     style: TextStyle(
                    //       fontSize: 11,
                    //       color: Colors.green[700],
                    //       fontWeight: FontWeight.bold,
                    //     ),
                    //   ),
                    if (_currentTargetPlace != null)
                      Text(
                        '선택된 타겟: $_currentTargetPlace',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.purple[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (!isMapLoaded)
                      Container(
                        color: Colors.white.withOpacity(0.9),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                '지도를 불러오는 중...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
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

          // ▼▼▼ 추가됨: 제출 중 로딩 인디케이터 ▼▼▼
          if (_isSubmitting)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '사진을 분석하고 점수를 계산하는 중...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
