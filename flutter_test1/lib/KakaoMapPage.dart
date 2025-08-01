// lib/KakaoMapPage.dart

import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'PhotoItem.dart';
import 'game_data_model.dart';
import 'quest_model.dart';
import 'review_model.dart';
import 'config/server_config.dart';

class KakaoMapPage extends StatefulWidget {
  final GameData gameData;
  const KakaoMapPage({super.key, required this.gameData});

  @override
  State<KakaoMapPage> createState() => _KakaoMapPageState();
}

class _KakaoMapPageState extends State<KakaoMapPage> {
  // --- Map and Core State ---
  late final WebViewController _controller;
  bool isMapLoaded = false;
  Position? currentPosition;
  bool isLocationLoading = false;
  final ImagePicker _picker = ImagePicker();
  String? _currentTargetPlace;
  String? _selectedTestPlace;
  File? _lastMissionImage;
  Map<String, String> _localImageUrls = {};

  // --- Data State (초기화 방식 변경) ---
  late String _userId;
  late String? _sessionId;
  late User? _currentUser;
  late bool _isGuest;
  late List<PhotoItem> _touristSpotPhotos;
  late List<PhotoItem> _allSeoulPhotos;
  late Map<String, Map<String, double>> _placeCoords;
  late List<Map<String, dynamic>> _rankings;
  late int _totalScore;
  late List<dynamic> _visitHistory;
  late List<Quest> _quests;
  late QuestProgress? _questProgress;

  // --- UI State for FAB Menu ---
  bool _isMenuOpen = false;
  final Duration _menuAnimationDuration = const Duration(milliseconds: 250);

  // --- Constants ---
  // 서버 URL은 ServerConfig에서 동적으로 가져옴 (디버그/릴리즈 모드에 따라 다름)
  final List<String> targetKeywords = [
    '경복궁',
    '경희궁',
    '광화문',
    '남산서울타워',
    '북촌한옥마을',
    '청계천',
    '독립문',
    '서울도서관',
  ];

  @override
  void initState() {
    super.initState();
    _initializeStateFromGameData();
    _fetchLocalImageUrls();
    _initializeWebView();
    _selectedTestPlace = targetKeywords.isNotEmpty ? targetKeywords[0] : null;
  }

  void _initializeStateFromGameData() {
    final gameData = widget.gameData;
    _userId = gameData.userId;
    _sessionId = gameData.sessionId;
    _currentUser = gameData.currentUser;
    _isGuest = gameData.isGuest;
    _touristSpotPhotos = gameData.touristSpotPhotos;
    _allSeoulPhotos = gameData.allSeoulPhotos;
    _placeCoords = gameData.placeCoords;
    _rankings = gameData.rankings;
    _totalScore = gameData.totalScore;
    _visitHistory = gameData.visitHistory;
    _quests = gameData.quests;
    _questProgress = gameData.questProgress;
  }

  @override
  void dispose() {
    if (_sessionId != null) {
      _endGameSession();
    }
    super.dispose();
  }

  Future<void> _endGameSession() async {
    try {
      await http.post(Uri.parse('${ServerConfig.serverUrl}/end_game/$_sessionId'));
    } catch (e) {
      print('Game session end error: $e');
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              setState(() => isMapLoaded = true);
              _onMapReady();
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            if (data['type'] == 'markerClick') {
              final photo = _touristSpotPhotos.firstWhere(
                (p) => p.galContentId == data['contentId'].toString(),
              );
              _showPhotoDetail(photo);
            }
          } catch (e) {
            print("JS message parsing error: $e");
          }
        },
      )
      ..loadFlutterAsset('assets/kakaomapTest.html');
  }

  void _onMapReady() {
    if (!isMapLoaded || !mounted) return;
    _displayTouristPhotos();
    _getCurrentLocation(showMessages: false);
  }

  Future<void> _fetchUserProfile() async {
    try {
      final response =
          await http.get(Uri.parse('${ServerConfig.serverUrl}/user_profile/$_userId'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _totalScore = data['total_score'];
            _visitHistory = data['visit_history'];
          });
        }
      }
    } catch (e) {
      print('User profile refresh error: $e');
    }
  }

  Future<void> _fetchRankings() async {
    try {
      final response = await http.get(Uri.parse('${ServerConfig.serverUrl}/rankings/'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(
            () => _rankings = List<Map<String, dynamic>>.from(data['rankings']),
          );
        }
      }
    } catch (e) {
      print('Ranking info loading error: $e');
    }
  }

  Future<void> _fetchQuestsAndProgress() async {
    try {
      final questsResponse =
          await http.get(Uri.parse('${ServerConfig.serverUrl}/quests/$_userId'));
      final progressResponse =
          await http.get(Uri.parse('${ServerConfig.serverUrl}/quests/$_userId/progress'));

      if (questsResponse.statusCode == 200 &&
          progressResponse.statusCode == 200) {
        final questsData = json.decode(utf8.decode(questsResponse.bodyBytes));
        final progressData =
            json.decode(utf8.decode(progressResponse.bodyBytes));
        if (mounted) {
          setState(() {
            _quests = (questsData['quests'] as List)
                .map((q) => Quest.fromJson(q))
                .toList();
            _questProgress = QuestProgress.fromJson(progressData['progress']);
          });
        }
      }
    } catch (e) {
      print('Quest data refresh error: $e');
    }
  }

  Future<void> _setTestLocationTo(String? placeName) async {
    if (placeName == null) return;
    if (_placeCoords.containsKey(placeName)) {
      final coords = _placeCoords[placeName]!;
      final testPosition = Position(
        latitude: coords['lat']!,
        longitude: coords['lng']!,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      if (mounted) {
        setState(() => currentPosition = testPosition);
        if (isMapLoaded) {
          String jsCode =
              'addCurrentLocationMarker(${testPosition.latitude}, ${testPosition.longitude}, true);';
          try {
            await _controller.runJavaScript(jsCode);
          } catch (e) {
            print("JS 테스트 위치 설정 오류: $e");
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('테스트: 현재 위치를 \'$placeName\'(으)로 설정했습니다.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\'$placeName\'의 좌표를 찾을 수 없습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // [추가] 백엔드에서 로컬 이미지 URL 맵을 가져오는 함수
  Future<void> _fetchLocalImageUrls() async {
    try {
      final response =
          await http.get(Uri.parse('${ServerConfig.serverUrl}/places/local-images'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _localImageUrls = Map<String, String>.from(data);
          });
        }
      }
    } catch (e) {
      print('Error fetching local image URLs: $e');
    }
  }

  Future<void> _displayTouristPhotos() async {
    if (_touristSpotPhotos.isEmpty || !isMapLoaded) return;

    // 서버 주소 (URL 조합을 위해)
    final String serverBaseUrl = ServerConfig.serverUrl;

    for (final photo in _touristSpotPhotos) {
      String? matchedPlace;
      for (final placeName in _placeCoords.keys) {
        if (photo.galTitle.contains(placeName) ||
            photo.galSearchKeyword.contains(placeName) ||
            photo.galPhotographyLocation.contains(placeName)) {
          matchedPlace = placeName;
          break;
        }
      }

      if (matchedPlace != null) {
        final coords = _placeCoords[matchedPlace]!;
        final isVisited = _visitHistory.any(
          (v) =>
              v['target_place'] == matchedPlace &&
              (v['is_correct'] == true || v['is_correct'] == 1),
        );

        // ▼▼▼ [수정] 이미지 URL 선택 로직 ▼▼▼
        // 1. 로컬 이미지 맵에서 장소 이름으로 이미지 경로를 찾습니다.
        final String? localImagePath = _localImageUrls[matchedPlace];

        // 2. 로컬 이미지가 있으면 서버 주소와 결합하고, 없으면 기존 API 이미지를 사용합니다.
        final String imageUrl = localImagePath != null
            ? '$serverBaseUrl$localImagePath'
            : photo.galWebImageUrl;
        // ▲▲▲ [수정] 이미지 URL 선택 로직 ▲▲▲

        final jsCode =
            "addPhotoMarker(${coords['lat']}, ${coords['lng']}, '$imageUrl', '${photo.galTitle.replaceAll("'", "\\'")}', '${photo.galContentId}', $isVisited);";
        try {
          await _controller.runJavaScript(jsCode);
        } catch (e) {
          print("JS 마커 추가 오류 ($matchedPlace): $e");
        }
      } else {
        print("'${photo.galTitle}'에 대한 좌표를 찾지 못했습니다.");
      }
    }
    _adjustMapBounds();
  }

  Future<void> _getCurrentLocation({bool showMessages = true}) async {
    setState(() => isLocationLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          throw Exception('Location permissions are denied.');
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() => currentPosition = position);
        await _addCurrentLocationToMap();
      }
    } catch (e) {
      if (mounted && showMessages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get current location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLocationLoading = false);
    }
  }

  Future<void> _addCurrentLocationToMap() async {
    if (currentPosition != null && isMapLoaded) {
      String jsCode =
          'addCurrentLocationMarker(${currentPosition!.latitude}, ${currentPosition!.longitude}, false);';
      await _controller.runJavaScript(jsCode);
      _adjustMapBounds();
    }
  }

  Future<void> _adjustMapBounds() async {
    if (!isMapLoaded) return;
    List<Map<String, double>> allPoints = [];
    if (currentPosition != null) {
      allPoints.add(
        {'lat': currentPosition!.latitude, 'lng': currentPosition!.longitude},
      );
    }
    for (final photo in _touristSpotPhotos) {
      String? matchedPlace;
      for (final placeName in _placeCoords.keys) {
        if (photo.galTitle.contains(placeName)) {
          matchedPlace = placeName;
          break;
        }
      }
      if (matchedPlace != null && _placeCoords.containsKey(matchedPlace)) {
        allPoints.add(_placeCoords[matchedPlace]!);
      }
    }

    if (allPoints.isNotEmpty) {
      await _controller.runJavaScript('fitMapBounds(${jsonEncode(allPoints)})');
    }
  }

  Future<void> _clearMissionHighlight() async {
    if (!mounted) return;
    _controller.runJavaScript("resetAllMarkerBorders();").catchError((e) {
      print("JS resetAllMarkerBorders 호출 오류: $e");
    });
    _controller.runJavaScript("hideMissionText();").catchError((e) {
      print("JS hideMissionText 호출 오류: $e");
    });
    setState(() {
      _currentTargetPlace = null;
    });
  }

  Future<void> _submitPrediction(File imageFile, String targetPlace) async {
    await _clearMissionHighlight();

    if (currentPosition == null) {
      _showPredictionResultOverlay(
        isCorrect: false,
        message: '현재 위치를 알 수 없습니다. 위치 서비스를 확인해주세요.',
        scoreEarned: 0,
      );
      return;
    }

    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('${ServerConfig.serverUrl}/predict/'))
            ..fields['session_id'] = _sessionId!
            ..fields['target_place'] = targetPlace
            ..fields['latitude'] = currentPosition!.latitude.toString()
            ..fields['longitude'] = currentPosition!.longitude.toString()
            ..files.add(
              await http.MultipartFile.fromPath('image', imageFile.path),
            );
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (response.statusCode == 200) {
        final bool isCorrect = responseData['is_correct'];
        final String message = responseData['message'];
        final int scoreEarned = responseData['score_earned'] ?? 0;

        if (isCorrect) {
          final photoItem = _touristSpotPhotos.firstWhere(
            (p) => p.galTitle.contains(targetPlace),
            orElse: () => PhotoItem.empty(),
          );
          if (photoItem.galContentId.isNotEmpty) {
            try {
              await _controller.runJavaScript(
                "updateMarkerToVisited('${photoItem.galContentId}')",
              );
            } catch (e) {
              print("JS updateMarkerToVisited 호출 오류: $e");
            }
          }
        }

        if (mounted) {
          _showPredictionResultOverlay(
            isCorrect: isCorrect,
            message: message,
            scoreEarned: scoreEarned,
          );
          _fetchUserProfile();
          _fetchRankings();
          _fetchQuestsAndProgress();

          if (isCorrect) {
            setState(() {
              _lastMissionImage = imageFile;
            });
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                _promptForReview(targetPlace);
              }
            });
          }
        }
      } else {
        throw Exception(responseData['detail'] ?? '서버에서 오류가 발생했습니다.');
      }
    } on SocketException {
      if (mounted) {
        _showPredictionResultOverlay(
          isCorrect: false,
          message: '네트워크 연결을 확인해주세요.',
          scoreEarned: 0,
        );
      }
    } catch (e) {
      if (mounted) {
        _showPredictionResultOverlay(
          isCorrect: false,
          message: '오류가 발생했습니다: $e',
          scoreEarned: 0,
        );
      }
    }
  }

  Future<void> _getImage(ImageSource source) async {
    if (_currentTargetPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 지도에서 미션을 시작할 장소를 선택해주세요.'),
        ),
      );
      return;
    }
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        await _submitPrediction(File(image.path), _currentTargetPlace!);
      } else {
        print("이미지 선택이 취소되었습니다.");
        await _clearMissionHighlight();
      }
    } catch (e) {
      print('Image selection error: $e');
      await _clearMissionHighlight();
    }
  }

  void _showAutoDismissingOverlay({
    required Widget child,
    required Duration duration,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FadeIn(
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: child,
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Timer(duration, () {
      overlayEntry.remove();
    });
  }

  Future<void> _recenterMapToCurrentLocation() async {
    if (isLocationLoading) return;
    setState(() => isLocationLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('위치 서비스가 비활성화되었습니다.');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          throw Exception('위치 권한이 거부되었습니다.');
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() => currentPosition = position);
        if (isMapLoaded) {
          String jsCode =
              'addCurrentLocationMarker(${position.latitude}, ${position.longitude}, true);';
          await _controller.runJavaScript(jsCode);
        }
        _showAutoDismissingOverlay(
          duration: const Duration(seconds: 2),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25.0),
                color: Colors.black.withOpacity(0.75),
              ),
              child: const Text(
                '📍 현재 위치로 지도를 이동했습니다.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('현재 위치를 가져올 수 없습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => isLocationLoading = false);
    }
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.pop(ctx);
                _getImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('앨범에서 선택'),
              onTap: () {
                Navigator.pop(ctx);
                _getImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('취소'),
              onTap: () {
                Navigator.pop(ctx);
                _clearMissionHighlight();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPredictionResultOverlay({
    required bool isCorrect,
    required String message,
    required int scoreEarned,
  }) {
    if (!mounted) return;
    final Widget resultTitle = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isCorrect ? Icons.check_circle : Icons.cancel,
          color: isCorrect ? Colors.green : Colors.red,
          size: 28,
        ),
        const SizedBox(width: 10),
        Text(
          isCorrect ? '예측 성공!' : '예측 실패',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ],
    );
    Widget resultContent;
    if (isCorrect) {
      resultContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("정답입니다!",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          if (scoreEarned > 0) ...[
            const SizedBox(height: 12),
            Text(
              '+$scoreEarned 점',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue),
            ),
          ],
        ],
      );
    } else {
      String serverMessage = message;
      try {
        final RegExp distanceRegex = RegExp(r'(\d+(\.\d+)?)\s*m');
        final Match? match = distanceRegex.firstMatch(serverMessage);
        if (match != null && match.group(1) != null) {
          final double distanceInMeters = double.parse(match.group(1)!);
          if (distanceInMeters >= 1000) {
            final double distanceInKm = distanceInMeters / 1000.0;
            serverMessage = serverMessage.replaceFirst(
                match.group(0)!, '${distanceInKm.toStringAsFixed(2)} km');
          }
        }
      } catch (e) {
        print("선택적 거리 변환 실패: $e");
      }
      String mainMessage = serverMessage;
      String details = '';
      if (serverMessage.contains('. ')) {
        final parts = serverMessage.split('. ');
        mainMessage = '${parts[0]}.';
        details = parts.length > 1
            ? parts.sublist(1).join('. ').replaceAll(', ', '\n')
            : '';
      }
      resultContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mainMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(details,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
          ]
        ],
      );
    }
    final overlayContent = Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40.0),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 4.0))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [resultTitle, const SizedBox(height: 20), resultContent],
        ),
      ),
    );
    _showAutoDismissingOverlay(
      child: overlayContent,
      duration: const Duration(seconds: 3),
    );
  }

  void _showRankingDialog() {
    _fetchRankings().then((_) {
      if (!mounted) return;

      final topThree = _rankings.where((r) => r['rank'] <= 3).toList();
      final rest = _rankings.where((r) => r['rank'] > 3).toList();
      topThree.sort((a, b) => a['rank'].compareTo(b['rank']));
      Map<String, dynamic>? first, second, third;
      for (var data in topThree) {
        if (data['rank'] == 1) first = data;
        if (data['rank'] == 2) second = data;
        if (data['rank'] == 3) third = data;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.only(top: 24),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          backgroundColor: Colors.grey[50],
          title: const Text('명예의 전당',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.55,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (topThree.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 24.0, horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (second != null) _buildPodiumItem(second, context),
                          if (first != null)
                            _buildPodiumItem(first, context, isFirst: true),
                          if (third != null) _buildPodiumItem(third, context),
                        ],
                      ),
                    ),
                  _rankings.isEmpty
                      ? const Center(child: Text('아직 랭킹 정보가 없습니다.'))
                      : ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: rest.length,
                          itemBuilder: (context, index) {
                            final rankData = rest[index];
                            final String? userImageUrl =
                                rankData['profile_image_url'];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Card(
                                elevation: 0,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: Text('${rankData['rank']}',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[700])),
                                  title: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Colors.grey[200],
                                        child: userImageUrl != null &&
                                                userImageUrl.isNotEmpty
                                            ? ClipOval(
                                                child: Image.network(
                                                  userImageUrl,
                                                  fit: BoxFit.cover,
                                                  width: 40,
                                                  height: 40,
                                                  loadingBuilder:
                                                      (c, child, p) => p == null
                                                          ? child
                                                          : const Center(
                                                              child:
                                                                  CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2)),
                                                  errorBuilder: (c, e, s) =>
                                                      const Icon(Icons.person,
                                                          color: Colors.grey),
                                                ),
                                              )
                                            : const Icon(Icons.person,
                                                color: Colors.grey),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(rankData['username'],
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w500)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Text('${rankData['total_score']}점',
                                      style: const TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'))
          ],
        ),
      );
    });
  }

  void _showCollectionBookDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool showWeekly = true;
        final Set<String> brokenUrls = {};

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final currentList =
                showWeekly ? _touristSpotPhotos : _allSeoulPhotos;
            final displayList = currentList
                .where((p) => !brokenUrls.contains(p.galWebImageUrl))
                .toList();

            Widget errorBuilder(String url, Object error) {
              final bool isPermanentError =
                  error is NetworkImageLoadException && error.statusCode == 404;
              if (isPermanentError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!brokenUrls.contains(url)) {
                    setState(() => brokenUrls.add(url));
                  }
                });
              }
              return const SizedBox.shrink();
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0)),
              titlePadding: const EdgeInsets.all(0),
              title: const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Icon(Icons.book, color: Colors.brown),
                    SizedBox(width: 8),
                    Text('나의 컬렉션 북')
                  ],
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Container(
                        width: 300,
                        height: 40,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => showWeekly = true),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: showWeekly
                                        ? const Color(0xFF0F2C3A)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text("미션 관광지 보기",
                                      style: TextStyle(
                                          color: showWeekly
                                              ? Colors.white
                                              : Colors.black54,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => showWeekly = false),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: !showWeekly
                                        ? const Color(0xFF0F2C3A)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text("서울 관광지 보기",
                                      style: TextStyle(
                                          color: !showWeekly
                                              ? Colors.white
                                              : Colors.black54,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: displayList.isEmpty
                          ? const Center(child: Text('수집할 관광지 사진이 없습니다.'))
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.8,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: displayList.length,
                              itemBuilder: (context, index) {
                                final photo = displayList[index];

                                // ▼▼▼ [수정] 이미지 URL과 제목을 결정하기 위한 로직 수정 ▼▼▼
                                String? matchedPlace;
                                // 1. 사진 정보와 일치하는 장소 이름을 찾습니다. (지도와 동일한 로직)
                                for (final placeName in _placeCoords.keys) {
                                  if (photo.galTitle.contains(placeName) ||
                                      photo.galSearchKeyword
                                          .contains(placeName) ||
                                      photo.galPhotographyLocation
                                          .contains(placeName)) {
                                    matchedPlace = placeName;
                                    break;
                                  }
                                }

                                final isVisited = _visitHistory.any((visit) =>
                                    (visit['is_correct'] == true ||
                                        visit['is_correct'] == 1) &&
                                    photo.galTitle
                                        .contains(visit['target_place']));

                                // 2. 로컬 이미지 경로를 가져옵니다.
                                final String? localImagePath =
                                    matchedPlace != null
                                        ? _localImageUrls[matchedPlace]
                                        : null;

                                // 3. 최종 이미지 URL과 제목을 결정합니다.
                                final String finalImageUrl;
                                final String finalTitle;

                                if (localImagePath != null) {
                                  // 로컬 이미지가 있으면 로컬 이미지와 장소 이름 사용
                                  finalImageUrl = '${ServerConfig.serverUrl}$localImagePath';
                                  finalTitle = matchedPlace!; // 장소 이름을 제목으로 사용
                                } else {
                                  // 로컬 이미지가 없으면 API 이미지와 제목 사용
                                  finalImageUrl = photo.galWebImageUrl;
                                  finalTitle = photo.galTitle; // 원래 API 제목 사용
                                }
                                // ▲▲▲ [수정] 로직 종료 ▲▲▲

                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: (!showWeekly || isVisited)
                                            ? Image.network(
                                                finalImageUrl, // [수정] finalImageUrl 사용
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    errorBuilder(
                                                        finalImageUrl, e))
                                            : ColorFiltered(
                                                colorFilter: const ColorFilter
                                                    .matrix(<double>[
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  1,
                                                  0,
                                                ]),
                                                child: Image.network(
                                                    finalImageUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (c, e, s) =>
                                                        errorBuilder(
                                                            finalImageUrl, e)),
                                              ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          finalTitle,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'))
              ],
            );
          },
        );
      },
    );
  }

  // [추가] 장소별 리뷰 목록을 가져오는 함수
  Future<List<Review>> _fetchPlaceReviews(String placeName) async {
    try {
      final encodedPlaceName = Uri.encodeComponent(placeName);
      final response = await http
          .get(Uri.parse('${ServerConfig.serverUrl}/reviews/place/$encodedPlaceName'));
      if (response.statusCode == 200) {
        final List<dynamic> reviewList =
            json.decode(utf8.decode(response.bodyBytes));
        return reviewList.map((json) => Review.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load reviews for $placeName');
      }
    } catch (e) {
      print("장소별 리뷰 로딩 오류: $e");
      return [];
    }
  }

  // [추가] 날짜 포맷팅을 위한 헬퍼 함수
  String _formatReviewDate(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return DateFormat('yyyy.MM.dd HH:mm').format(dateTime);
    } catch (e) {
      return isoString;
    }
  }

  // [추가] 특정 장소에 대한 나의 리뷰만 가져오는 함수
  Future<List<Review>> _fetchMyPlaceReviews(String placeName) async {
    try {
      final encodedPlaceName = Uri.encodeComponent(placeName);
      final response = await http.get(Uri.parse(
          '${ServerConfig.serverUrl}/reviews/user/$_userId/place/$encodedPlaceName'));
      if (response.statusCode == 200) {
        final List<dynamic> reviewList =
            json.decode(utf8.decode(response.bodyBytes));
        return reviewList.map((json) => Review.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load my reviews for $placeName');
      }
    } catch (e) {
      print("나의 장소별 리뷰 로딩 오류: $e");
      return [];
    }
  }

  // [추가] 특정 장소에 대한 나의 리뷰를 보여주는 다이얼로그
  void _showMyPlaceReviewsDialog(String placeName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('\'$placeName\'에 대한 나의 리뷰'),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<Review>>(
              future: _fetchMyPlaceReviews(placeName),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('리뷰를 불러오는 데 실패했습니다.'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      '이 장소에 대한 리뷰를 아직 작성하지 않았습니다.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final reviews = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: reviews.length,
                  itemBuilder: (context, index) {
                    final review = reviews[index];
                    final userInfo = review.userInfo;
                    final userImageUrl = userInfo.profileImageUrl;

                    final String? reviewImageUrl = review.imageUrl;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (reviewImageUrl != null &&
                              reviewImageUrl.isNotEmpty)
                            Image.network(
                              reviewImageUrl,
                              width: double.infinity,
                              height: 150,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 150,
                                  color: Colors.grey[200],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.grey),
                                );
                              },
                            ),
                          ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey[200],
                              child: userImageUrl != null &&
                                      userImageUrl.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        userImageUrl,
                                        fit: BoxFit.cover,
                                        width: 40,
                                        height: 40,
                                        errorBuilder: (c, e, s) => const Icon(
                                            Icons.person,
                                            color: Colors.grey),
                                      ),
                                    )
                                  : const Icon(Icons.person,
                                      color: Colors.grey),
                            ),
                            title: Text(userInfo.username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(review.reviewText),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _formatReviewDate(review.createdAt),
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  void _showPhotoDetail(PhotoItem photo) {
    final matchedPlace = targetKeywords.firstWhere(
      (p) => photo.galTitle.contains(p),
      orElse: () => '',
    );
    final bool isVisited = _visitHistory.any(
      (visit) =>
          visit['target_place'] == matchedPlace &&
          (visit['is_correct'] == true || visit['is_correct'] == 1),
    );

    final String? localImagePath = _localImageUrls[matchedPlace];
    final String finalImageUrl = localImagePath != null
                    ? '${ServerConfig.serverUrl}$localImagePath'
        : photo.galWebImageUrl;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(12))),
              title: Text(photo.galTitle,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop())
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height *
                            0.4, // 화면 높이의 40%로 제한
                      ),
                      // [수정] photo.galWebImageUrl 대신 finalImageUrl 사용
                      child: Image.network(
                        finalImageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => Container(
                          height: 200,
                          color: Colors.grey[300],
                          child: const Center(
                              child: Icon(Icons.broken_image,
                                  size: 80, color: Colors.grey)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Title: ${photo.galTitle}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('위치: ${photo.galPhotographyLocation}'),
                          const SizedBox(height: 16),
                          if (matchedPlace.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  icon: Icon(isVisited
                                      ? Icons.check_circle
                                      : Icons.flag_outlined),
                                  label: Text(
                                      isVisited ? '다시 인증하기' : '이 장소로 미션 시작'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    Future.delayed(
                                        const Duration(milliseconds: 100), () {
                                      if (mounted) {
                                        setState(() {
                                          _currentTargetPlace = matchedPlace;
                                        });
                                        final coords =
                                            _placeCoords[matchedPlace];
                                        if (coords != null) {
                                          _controller
                                              .runJavaScript(
                                                  "showMissionTextOnMarker(${coords['lat']}, ${coords['lng']}, '$matchedPlace')")
                                              .catchError((e) {
                                            print(
                                                "JS showMissionTextOnMarker 호출 오류: $e");
                                          });
                                        }
                                        _controller
                                            .runJavaScript(
                                                "highlightMarker('${photo.galContentId}')")
                                            .catchError((e) {
                                          print("JS highlightMarker 호출 오류: $e");
                                        });
                                        _pickImage();
                                      }
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[400],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    textStyle: const TextStyle(fontSize: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // 심플한 리뷰 버튼들 - 세로 배치
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // 모든 리뷰 보기 버튼
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                          color: Colors.teal.shade400,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: TextButton.icon(
                                        icon: Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                          color: Colors.teal.shade600,
                                        ),
                                        label: Text(
                                          '\'$matchedPlace\' 리뷰 모두 보기',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.teal.shade600,
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _showPlaceReviewsDialog(matchedPlace);
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(25),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // 나의 리뷰 보기 버튼
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                          color: Colors.teal.shade600,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: TextButton.icon(
                                        icon: Icon(
                                          Icons.person_outline,
                                          size: 18,
                                          color: Colors.teal.shade600,
                                        ),
                                        label: Text(
                                          '나의 리뷰 보기',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.teal.shade600,
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _showMyPlaceReviewsDialog(
                                              matchedPlace);
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(25),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
    );
  }

  void _showQuestDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final displayQuests =
                _quests.where((q) => q.status != 'failed').toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              titlePadding: const EdgeInsets.all(0),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              backgroundColor: Colors.grey[100],
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
                    Icon(Icons.assignment, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      '오늘의 퀘스트',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    if (_questProgress != null)
                      _buildProgressBar(_questProgress!),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: displayQuests.length,
                        itemBuilder: (context, index) {
                          final quest = displayQuests[index];
                          switch (quest.status) {
                            case 'active':
                              return _buildActiveQuestCard(
                                  quest, setDialogState);
                            case 'reward_ready':
                              return _buildRewardReadyCard(
                                  quest, setDialogState);
                            case 'reward_claimed':
                              return _buildCompletedQuestCard(quest);
                            default:
                              return Card(
                                  child: ListTile(title: Text(quest.title)));
                          }
                        },
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'))
              ],
            );
          },
        );
      },
    );
  }

  IconData _getIconForQuestType(String type) {
    switch (type) {
      case 'theme_mission':
        return Icons.palette_outlined;
      case 'visit_count':
        return Icons.hiking;
      case 'history_quiz':
        return Icons.school_outlined;
      default:
        return Icons.tour_outlined;
    }
  }

  Widget _buildProgressBar(QuestProgress progress) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress.progressPercentage / 100,
            minHeight: 12,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('🎁 보상 대기: ${progress.rewardReadyQuests}개'),
            Text('획득 가능: +${progress.availableReward}점',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveQuestCard(Quest quest, StateSetter setDialogState) {
    final questIcon = _getIconForQuestType(quest.type);

    if (quest.type == 'history_quiz' && quest.isAnswered != true) {
      return Card(
        elevation: 2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          backgroundColor: Colors.blue.withOpacity(0.05),
          leading: Icon(questIcon, color: Colors.blue.shade700),
          title: Text(
            quest.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text('퀴즈를 풀어보세요! (+${quest.points}점)',
              style: TextStyle(color: Colors.grey.shade600)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quest.quizQuestion ?? '문제를 불러오는 데 실패했습니다.',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 12),
                  ...(quest.quizOptions ?? []).asMap().entries.map((entry) {
                    int index = entry.key;
                    String option = entry.value;
                    return InkWell(
                      onTap: () async {
                        await _submitQuizAnswer(
                            quest.questId, index, setDialogState);
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 12.0),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.grey.shade300)),
                        child: Row(
                          children: [
                            Text('${index + 1}. ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Expanded(child: Text(option)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: ListTile(
        leading: Icon(questIcon, color: Colors.blue.shade700),
        title: Text(
          quest.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
            '목표: ${quest.completedPlaces.length} / ${quest.requiredVisits}',
            style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }

  Widget _buildRewardReadyCard(Quest quest, StateSetter setDialogState) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.orange.shade300, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.orange[50],
      child: ListTile(
        leading: const Text('🎁', style: TextStyle(fontSize: 24)),
        title: Text(
          quest.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('보상: +${quest.points}점',
            style: TextStyle(
                color: Colors.orange.shade800, fontWeight: FontWeight.w500)),
        trailing: ElevatedButton(
          onPressed: () => _claimReward(quest.questId, setDialogState),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 2),
          child: const Text('받기'),
        ),
      ),
    );
  }

  Widget _buildCompletedQuestCard(Quest quest) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      color: Colors.grey[300],
      child: ListTile(
        leading: Icon(Icons.check_circle, color: Colors.green.shade600),
        title: Text(
          quest.title,
          style: TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 15,
            color: Colors.grey.shade700,
          ),
        ),
        subtitle: Text('보상 +${quest.points}점 획득 완료',
            style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }

  Future<void> _submitQuizAnswer(
      String questId, int answerIndex, StateSetter setDialogState) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.serverUrl}/quests/quiz/answer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'quest_id': questId,
          'answer_index': answerIndex
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final result = data['result'];
        final bool isCorrect = result['is_correct'];

        _showQuestResultOverlay(
          isCorrect: isCorrect,
          message: result['message'],
          scoreEarned: 0,
        );

        await Future.wait([_fetchQuestsAndProgress(), _fetchUserProfile()]);
        setDialogState(() {});
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes));
        _showQuestResultOverlay(
          isCorrect: false,
          message: error['detail'] ?? '답변 제출에 실패했습니다.',
          scoreEarned: 0,
        );
      }
    } catch (e) {
      print('퀴즈 답변 제출 오류: $e');
      _showQuestResultOverlay(
        isCorrect: false,
        message: '네트워크 오류가 발생했습니다.',
        scoreEarned: 0,
      );
    }
  }

  void _showQuestResultOverlay({
    required bool isCorrect,
    required String message,
    required int scoreEarned,
  }) {
    if (!mounted) return;

    final Widget resultTitle = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isCorrect ? Icons.check_circle : Icons.cancel,
          color: isCorrect ? Colors.green : Colors.red,
          size: 28,
        ),
        const SizedBox(width: 10),
        Text(
          isCorrect ? '성공!' : '실패',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ],
    );

    Widget resultContent;
    if (isCorrect && scoreEarned > 0) {
      resultContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          Text(
            '+$scoreEarned 점',
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ],
      );
    } else {
      resultContent = Text(message,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 18));
    }

    final overlayContent = Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40.0),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 4.0))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [resultTitle, const SizedBox(height: 20), resultContent],
        ),
      ),
    );

    _showAutoDismissingOverlay(
      child: overlayContent,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _claimReward(String questId, StateSetter setDialogState) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.serverUrl}/quests/reward'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'quest_id': questId}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final result = data['result'];
        final int rewardPoints = result['reward_points'] ?? 0;

        _showQuestResultOverlay(
          isCorrect: true,
          message: '퀘스트 완료!',
          scoreEarned: rewardPoints,
        );

        await Future.wait([_fetchQuestsAndProgress(), _fetchUserProfile()]);
        setDialogState(() {});
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes));
        _showQuestResultOverlay(
          isCorrect: false,
          message: error['detail'] ?? '보상 받기에 실패했습니다.',
          scoreEarned: 0,
        );
      }
    } catch (e) {
      print('보상 받기 오류: $e');
    }
  }

  void _promptForReview(String placeName) {
    if (!mounted || _lastMissionImage == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(children: [
          Icon(Icons.rate_review_outlined, color: Colors.orange),
          SizedBox(width: 10),
          Text('리뷰 작성')
        ]),
        content: Text(
          '\'$placeName\' 방문은 어떠셨나요?\n리뷰를 작성하고 보너스 20점을 받으세요!',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _lastMissionImage = null;
              });
            },
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showReviewDialog(placeName, _lastMissionImage!);
            },
            child: const Text('리뷰 작성하기'),
          ),
        ],
      ),
    );
  }

  void _showReviewDialog(String placeName, File imageFile) {
    final reviewController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('\'$placeName\' 리뷰'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.file(imageFile, height: 180, fit: BoxFit.cover),
              ),
              const SizedBox(height: 20),
              Form(
                key: formKey,
                child: TextFormField(
                  controller: reviewController,
                  autofocus: true,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: '20자 이상으로 리뷰를 작성해주세요.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 20) {
                      return '리뷰는 20자 이상이어야 합니다.';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _lastMissionImage = null;
              });
            },
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop();
                _submitReview(placeName, reviewController.text, imageFile);
              }
            },
            child: const Text('제출'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReview(
      String placeName, String reviewText, File imageFile) async {
    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('${ServerConfig.serverUrl}/reviews/'))
            ..fields['user_id'] = _userId
            ..fields['place_name'] = placeName
            ..fields['review_text'] = reviewText
            ..files.add(
              await http.MultipartFile.fromPath('image', imageFile.path),
            );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (mounted) {
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          final int scoreEarned = data['score_earned'] ?? 0;
          _showQuestResultOverlay(
            isCorrect: true,
            message: '리뷰가 등록되었습니다!',
            scoreEarned: scoreEarned,
          );
          _fetchUserProfile();
          _fetchRankings();
        } else {
          final error = json.decode(utf8.decode(response.bodyBytes));
          _showQuestResultOverlay(
              isCorrect: false,
              message: error['detail'] ?? '리뷰 등록에 실패했습니다.',
              scoreEarned: 0);
        }
      }
    } catch (e) {
      if (mounted) {
        _showQuestResultOverlay(
            isCorrect: false, message: '네트워크 오류가 발생했습니다.', scoreEarned: 0);
      }
      print('리뷰 제출 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _lastMissionImage = null;
        });
      }
    }
  }

  Future<List<Review>> _fetchMyReviews() async {
    try {
              final response = await http.get(Uri.parse('${ServerConfig.serverUrl}/reviews/$_userId'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> reviewList = data['reviews'];
        return reviewList.map((json) => Review.fromJson(json)).toList();
      }
    } catch (e) {
      print("나의 리뷰 로딩 오류: $e");
    }
    return [];
  }

  // [추가] 장소별 리뷰 목록을 보여주는 다이얼로그 함수
  void _showPlaceReviewsDialog(String placeName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('\'$placeName\' 방문 후기'),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<Review>>(
              future: _fetchPlaceReviews(placeName),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('리뷰를 불러오는 데 실패했습니다.'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('아직 작성된 리뷰가 없습니다.'));
                }

                final reviews = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: reviews.length,
                  itemBuilder: (context, index) {
                    final review = reviews[index];
                    final userInfo = review.userInfo;
                    final userImageUrl = userInfo.profileImageUrl;

                    final String? reviewImageUrl = review.imageUrl;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (reviewImageUrl != null &&
                              reviewImageUrl.isNotEmpty)
                            Image.network(
                              reviewImageUrl,
                              width: double.infinity,
                              height: 150,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 150,
                                  color: Colors.grey[200],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.grey),
                                );
                              },
                            ),
                          ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey[200],
                              child: userImageUrl != null &&
                                      userImageUrl.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        userImageUrl,
                                        fit: BoxFit.cover,
                                        width: 40,
                                        height: 40,
                                        errorBuilder: (c, e, s) => const Icon(
                                            Icons.person,
                                            color: Colors.grey),
                                      ),
                                    )
                                  : const Icon(Icons.person,
                                      color: Colors.grey),
                            ),
                            title: Text(userInfo.username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(review.reviewText),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _formatReviewDate(review.createdAt),
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  void _showMyReviewsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('나의 리뷰 목록'),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<Review>>(
              future: _fetchMyReviews(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('리뷰를 불러오는 데 실패했습니다.'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('작성한 리뷰가 없습니다.'));
                }

                final reviews = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: reviews.length,
                  itemBuilder: (context, index) {
                    final review = reviews[index];
                    final userInfo = review.userInfo;
                    final userImageUrl = userInfo.profileImageUrl;

                    final String? reviewImageUrl = review.imageUrl;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (reviewImageUrl != null &&
                              reviewImageUrl.isNotEmpty)
                            Image.network(
                              reviewImageUrl, // 수정된 URL 사용
                              width: double.infinity,
                              height: 150,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  height: 150,
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                print('리뷰 이미지 로드 오류: $error');
                                return Container(
                                  height: 150,
                                  color: Colors.grey[200],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.grey),
                                );
                              },
                            ),
                          ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey[200],
                              child: userImageUrl != null &&
                                      userImageUrl.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        userImageUrl,
                                        fit: BoxFit.cover,
                                        width: 40,
                                        height: 40,
                                        errorBuilder: (c, e, s) => const Icon(
                                            Icons.person,
                                            color: Colors.grey),
                                      ),
                                    )
                                  : const Icon(Icons.person,
                                      color: Colors.grey),
                            ),
                            title: Text(review.placeName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                review.reviewText,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuOption({
    required double distance,
    required String tooltip,
    required VoidCallback onPressed,
    required Widget child,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return AnimatedPositioned(
      duration: _menuAnimationDuration,
      curve: Curves.easeInOut,
      bottom: _isMenuOpen ? distance : 0,
      right: 0,
      child: AnimatedOpacity(
        duration: _menuAnimationDuration,
        opacity: _isMenuOpen ? 1.0 : 0.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
                ],
              ),
              child: Text(tooltip,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            FloatingActionButton(
              heroTag: tooltip,
              onPressed: () {
                setState(() => _isMenuOpen = false);
                onPressed();
              },
              tooltip: tooltip,
              backgroundColor: backgroundColor ?? Colors.white,
              foregroundColor: foregroundColor ?? Colors.blue,
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  Color _getPodiumColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey[400]!;
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.blue;
    }
  }

  Widget _buildPodiumItem(Map<String, dynamic> rankData, BuildContext context,
      {bool isFirst = false}) {
    final rank = rankData['rank'];
    final username = rankData['username'];
    final score = rankData['total_score'];
    final String? userImageUrl = rankData['profile_image_url'];
    final double avatarRadius = isFirst ? 45 : 35;
    final double iconSize = isFirst ? 45 : 35;
    final EdgeInsets padding = EdgeInsets.only(bottom: isFirst ? 20.0 : 0);
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: Colors.blue.withOpacity(0.3),
                child: CircleAvatar(
                  radius: avatarRadius - 3,
                  backgroundColor: Colors.white,
                  child: userImageUrl != null && userImageUrl.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            userImageUrl,
                            fit: BoxFit.cover,
                            width: (avatarRadius - 3) * 2,
                            height: (avatarRadius - 3) * 2,
                            loadingBuilder: (c, child, p) => p == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                            errorBuilder: (c, e, s) => Icon(Icons.person,
                                size: iconSize, color: Colors.grey[400]),
                          ),
                        )
                      : Icon(Icons.person,
                          size: iconSize, color: Colors.grey[400]),
                ),
              ),
              Positioned(
                bottom: -10,
                child: Container(
                  padding: EdgeInsets.all(isFirst ? 6 : 5),
                  decoration: BoxDecoration(
                    color: _getPodiumColor(rank),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text('$rank',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              const style =
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
              final maxWidth = avatarRadius * 2;
              final textPainter = TextPainter(
                text: TextSpan(text: username, style: style),
                maxLines: 1,
                textDirection: ui.TextDirection.ltr,
              )..layout();

              return SizedBox(
                width: maxWidth,
                child: textPainter.size.width > maxWidth
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(username, style: style))
                    : Text(username, style: style, textAlign: TextAlign.center),
              );
            },
          ),
          const SizedBox(height: 2),
          Text('$score pts',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[200],
                            child: _currentUser?.kakaoAccount?.profile
                                        ?.thumbnailImageUrl !=
                                    null
                                ? Image.network(
                                    _currentUser!.kakaoAccount!.profile!
                                        .thumbnailImageUrl!,
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                  )
                                : const Icon(Icons.person,
                                    size: 32, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isGuest
                              ? 'Guest'
                              : _currentUser?.kakaoAccount?.profile?.nickname ??
                                  'User',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.emoji_events, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '$_totalScore점',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1), blurRadius: 4)
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTestPlace,
                        hint: const Text("테스트 위치 선택"),
                        isDense: true,
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() => _selectedTestPlace = newValue);
                            _setTestLocationTo(newValue);
                          }
                        },
                        items: targetKeywords
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value,
                                style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildFabMenu(),
        ],
      ),
    );
  }

  Widget _buildFabMenu() {
    final List<Widget> menuButtons = [
      _buildMenuOption(
        distance: 310.0,
        tooltip: '나의 리뷰',
        onPressed: _showMyReviewsDialog,
        child: const Icon(Icons.rate_review_outlined),
      ),
      _buildMenuOption(
        distance: 250.0,
        tooltip: '퀘스트 목록',
        onPressed: _showQuestDialog,
        child: const Icon(Icons.assignment_turned_in_outlined),
      ),
      _buildMenuOption(
        distance: 190.0,
        tooltip: '컬렉션 북',
        onPressed: _showCollectionBookDialog,
        child: const Icon(Icons.book_outlined),
      ),
      _buildMenuOption(
        distance: 130.0,
        tooltip: '랭킹',
        onPressed: _showRankingDialog,
        child: const Icon(Icons.leaderboard_outlined),
      ),
      _buildMenuOption(
        distance: 70.0,
        tooltip: '현재 위치',
        onPressed: _recenterMapToCurrentLocation,
        child: isLocationLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.blue, strokeWidth: 3))
            : const Icon(Icons.my_location),
      ),
    ];
    return Positioned(
      bottom: 16,
      right: 16,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          if (_isMenuOpen)
            GestureDetector(
              onTap: () => setState(() => _isMenuOpen = false),
              child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height),
            ),
          ...menuButtons,
          FloatingActionButton(
            heroTag: 'mainMenuBtn',
            backgroundColor: _isMenuOpen ? Colors.white : Colors.blue,
            onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
            child: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _isMenuOpen
                  ? const AlwaysStoppedAnimation<double>(1)
                  : const AlwaysStoppedAnimation<double>(0),
            ),
          ),
        ],
      ),
    );
  }
}

class FadeIn extends StatefulWidget {
  final Widget child;
  const FadeIn({super.key, required this.child});

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: widget.child,
    );
  }
}
