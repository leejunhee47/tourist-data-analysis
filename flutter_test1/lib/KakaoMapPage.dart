// KakaoMapPage.dart

import 'dart:async'; // [수정] Timer 사용을 위해 추가
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'PhotoItem.dart';

class KakaoMapPage extends StatefulWidget {
  final User? user;
  final bool isGuest;
  const KakaoMapPage({super.key, this.user, this.isGuest = false})
      : assert(
            user != null || isGuest, 'User must be provided if not a guest.');
  const KakaoMapPage.guest({super.key})
      : user = null,
        isGuest = true;

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
  final bool _isSubmitting = false;
  User? _currentUser;
  Timer? _missionBannerTimer; // [수정] 배너 표시 타이머 변수 추가
  bool _showMissionBanner = false; // [수정] 배너 표시 상태 변수 추가

  // +++ 추가된 상태 변수 +++
  String? _selectedTestPlace;

  // --- Data State (from MainPage) ---
  bool _isLoading = true;
  String? _sessionId;
  final List<PhotoItem> _touristSpotPhotos = [];
  Map<String, Map<String, double>> _placeCoords = {};
  List<Map<String, dynamic>> _rankings = [];
  String? _userId;
  int _totalScore = 0;
  bool _isProfileLoading = true;
  List<dynamic> _visitHistory = [];
  // --- UI State for FAB Menu ---
  bool _isMenuOpen = false;
  final Duration _menuAnimationDuration = const Duration(milliseconds: 250);
  // --- Constants ---
  final String serverUrl =
      'https://tourist-app-783243215272.asia-northeast3.run.app';
  final String baseUrl = 'https://apis.data.go.kr/B551011/PhotoGalleryService1';
  final String serviceKey =
      'AzjIKOxRyY9dTdGHXgvr0WkT9dlnEnpSdLz5+UHvMIm/PhztPInz9ePGb5FS+sHdAVH3GEfFqHEh/oW54s1A1A==';
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
    // +++ 추가된 초기화 코드 +++
    _selectedTestPlace = targetKeywords.isNotEmpty ? targetKeywords[0] : null;

    _currentUser = widget.user;
    _initializeWebView();
    _initializeGameData();
  }

  @override
  void dispose() {
    if (_sessionId != null) {
      _endGameSession();
    }
    _missionBannerTimer?.cancel(); // [수정] 위젯 종료 시 타이머 취소
    super.dispose();
  }

  // +++ START OF NEW METHOD +++
  /// 테스트용으로 현재 위치를 '경복궁'의 좌표로 설정합니다.
  /// 테스트용으로 현재 위치를 선택된 관광지의 좌표로 설정합니다.
  Future<void> _setTestLocationTo(String? placeName) async {
    if (placeName == null) return;

    // 1. 선택된 장소의 좌표 찾기
    if (_placeCoords.containsKey(placeName)) {
      final coords = _placeCoords[placeName]!;
      final testLatitude = coords['lat']!;
      final testLongitude = coords['lng']!;

      // 2. 새로운 Position 객체 생성
      final testPosition = Position(
        latitude: testLatitude,
        longitude: testLongitude,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      // 3. 상태 업데이트 및 지도에 반영
      if (mounted) {
        setState(() {
          currentPosition = testPosition;
        });

        // 4. 지도에 현재 위치 마커 추가하고 중심으로 이동
        if (isMapLoaded) {
          String jsCode =
              'addCurrentLocationMarker(${testPosition.latitude}, ${testPosition.longitude}, true);'; // true to pan
          try {
            await _controller.runJavaScript(jsCode);
          } catch (e) {
            print("JS 테스트 위치 설정 오류: $e");
          }
        }

        // 5. 사용자에게 피드백 제공
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('테스트: 현재 위치를 \'$placeName\'(으)로 설정했습니다.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } else {
      // 좌표 정보를 찾지 못한 경우
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\'$placeName\'의 좌표를 찾을 수 없습니다. 장소 데이터 확인이 필요합니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  // +++ END OF NEW METHOD +++

  // ▼▼▼ All other methods remain the same ▼▼▼
  // _refreshKakaoUser, _initializeGameData, _getOrCreateUser,
  // _fetchUserProfile, _fetchRankings, _fetchPlaceCoordinates,
  // _fetchTouristSpotPhotos, _startGameSession, _endGameSession,
  // _showRankingDialog, _showCollectionBookDialog, buildDot,
  // _initializeWebView, _onMapReady, _displayTouristPhotos,
  // _getCurrentLocation, _addCurrentLocationToMap, _adjustMapBounds,
  // _submitPrediction, _getImage, _recenterMapToCurrentLocation,
  // _pickImage, _showPhotoDetail
  // (Your existing methods go here without any changes)
  Future<void> _refreshKakaoUser() async {
    if (widget.isGuest) return; // 게스트는 새로고침 안함

    try {
      User updatedUser = await UserApi.instance.me();
      if (mounted) {
        setState(() {
          _currentUser = updatedUser; // 상태를 최신 유저 정보로 업데이트
        });
      }
    } catch (error) {
      print('카카오 유저 정보 새로고침 실패: $error'); // 에러 발생 시 기존 정보 유지
    }
  }

  Future<void> _initializeGameData() async {
    setState(() => _isLoading = true);
    await _refreshKakaoUser();
    await _getOrCreateUser();
    if (_userId != null && mounted) {
      await Future.wait([
        _fetchUserProfile(_userId!),
        _fetchTouristSpotPhotos(),
        _fetchPlaceCoordinates(),
        _fetchRankings(),
      ]);
      await _startGameSession();
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _onMapReady();
    }
  }

  Future<void> _getOrCreateUser() async {
    final String? username = widget.isGuest
        ? "게스트유저"
        : _currentUser?.kakaoAccount?.profile?.nickname;
    if (username == null) return;
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/create_user/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username}),
      );
      if (response.statusCode == 200) {
        if (mounted)
          setState(
            () => _userId = json.decode(
              utf8.decode(response.bodyBytes),
            )['user_id'],
          );
      }
    } catch (e) {
      print('User creation/retrieval error: $e');
    }
  }

  Future<void> _fetchUserProfile(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/user_profile/$userId'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _totalScore = data['total_score'];
            _visitHistory = data['visit_history'];
            _isProfileLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isProfileLoading = false);
      print('User profile loading error: $e');
    }
  }

  Future<void> _fetchRankings() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/rankings/'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted)
          setState(
            () => _rankings = List<Map<String, dynamic>>.from(data['rankings']),
          );
      }
    } catch (e) {
      print('Ranking info loading error: $e');
    }
  }

  Future<void> _fetchPlaceCoordinates() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/places/'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> places = data['places'];
        final Map<String, Map<String, double>> coords = {};
        for (var place in places) {
          coords[place['name']] = {
            'lat': place['latitude'],
            'lng': place['longitude'],
          };
        }
        if (mounted) setState(() => _placeCoords = coords);
      }
    } catch (e) {
      print('Place coordinates loading error: $e');
    }
  }

  Future<void> _fetchTouristSpotPhotos() async {
    try {
      final url = Uri.parse('$baseUrl/galleryList1').replace(
        queryParameters: {
          'serviceKey': serviceKey,
          'numOfRows': '6000',
          'pageNo': '1',
          'MobileOS': 'ETC',
          'MobileApp': 'AppTest',
          'arrange': 'A',
          '_type': 'json',
        },
      );
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw Exception('Failed to load photos from public API');
      }

      final items = json.decode(
        response.body,
      )['response']['body']['items']['item'];
      final allPhotos =
          (items as List).map((item) => PhotoItem.fromJson(item)).toList();
      final seoulPhotos = allPhotos.where((photo) {
        final location = photo.galPhotographyLocation.toLowerCase();
        return location.contains('서울특별시') ||
            location.contains('서울시') ||
            location.contains('서울');
      }).toList();
      final Map<String, PhotoItem> foundPhotosMap = {};
      final Set<String> keywordsToFind = targetKeywords.toSet();
      for (final photo in seoulPhotos) {
        if (keywordsToFind.isEmpty) break;
        for (final keyword in List.from(keywordsToFind)) {
          if (photo.galTitle.toLowerCase().contains(keyword.toLowerCase())) {
            foundPhotosMap[keyword] = photo;
            keywordsToFind.remove(keyword);
            break;
          }
        }
      }

      if (keywordsToFind.isNotEmpty) {
        for (final photo in seoulPhotos) {
          if (keywordsToFind.isEmpty) break;
          for (final keyword in List.from(keywordsToFind)) {
            if (photo.galSearchKeyword.toLowerCase().contains(
                      keyword.toLowerCase(),
                    ) ||
                photo.galPhotographyLocation.toLowerCase().contains(
                      keyword.toLowerCase(),
                    )) {
              foundPhotosMap[keyword] = photo;
              keywordsToFind.remove(keyword);
              break;
            }
          }
        }
      }

      if (keywordsToFind.isNotEmpty) {
        print("API에서 찾지 못한 키워드: $keywordsToFind. 로컬 이미지로 대체합니다.");
        for (final keyword in keywordsToFind) {
          final fallbackPhoto = PhotoItem(
            galContentId: keyword,
            galTitle: keyword,
            galWebImageUrl: '$serverUrl/map_images/$keyword.jpg',
            galCreatedtime: '',
            galModifiedtime: '',
            galPhotographyMonth: '',
            galPhotographyLocation: keyword,
            galPhotographer: 'N/A',
            galSearchKeyword: keyword,
          );
          foundPhotosMap[keyword] = fallbackPhoto;
        }
      }

      if (mounted) {
        setState(() {
          _touristSpotPhotos.clear();
          for (var keyword in targetKeywords) {
            if (foundPhotosMap.containsKey(keyword)) {
              _touristSpotPhotos.add(foundPhotosMap[keyword]!);
            }
          }
        });
      }
    } catch (e) {
      print('관광지 사진 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('관광지 사진을 불러오는 데 실패했습니다: $e')));
      }
    }
  }

  Future<void> _startGameSession() async {
    if (_userId == null) return;
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/start_game/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _userId!,
          'target_places': targetKeywords,
        }),
      );
      if (response.statusCode == 200) {
        if (mounted)
          setState(
            () => _sessionId = json.decode(
              utf8.decode(response.bodyBytes),
            )['session_id'],
          );
      }
    } catch (e) {
      print('Game session start error: $e');
    }
  }

  Future<void> _endGameSession() async {
    try {
      await http.post(Uri.parse('$serverUrl/end_game/$_sessionId'));
    } catch (e) {
      print('Game session end error: $e');
    }
  }

  void _showRankingDialog() {
    _fetchRankings().then((_) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.leaderboard, color: Colors.amber),
              SizedBox(width: 8),
              Text('명예의 전당'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _rankings.isEmpty
                ? const Center(child: Text('아직 랭킹 정보가 없습니다.'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _rankings.length,
                    itemBuilder: (context, index) {
                      final rankData = _rankings[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 2,
                        child: ListTile(
                          leading: Text(
                            '${rankData['rank']}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: rankData['rank'] == 1
                                  ? Colors.amber.shade700
                                  : rankData['rank'] == 2
                                      ? Colors.grey.shade600
                                      : rankData['rank'] == 3
                                          ? Colors.brown.shade400
                                          : Colors.black,
                            ),
                          ),
                          title: Text(
                            rankData['username'],
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          trailing: Text(
                            '${rankData['total_score']}점',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
        ),
      );
    });
  }

  void _showCollectionBookDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final PageController pageController = PageController();
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.book, color: Colors.brown),
              SizedBox(width: 8),
              Text('나의 컬렉션 북'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.4,
            child: _touristSpotPhotos.isEmpty
                ? const Center(child: Text('수집할 관광지 사진이 없습니다.'))
                : Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: (_touristSpotPhotos.length / 4).ceil(),
                          itemBuilder: (context, pageIndex) {
                            final startIndex = pageIndex * 4;
                            final endIndex = (startIndex + 4).clamp(
                              0,
                              _touristSpotPhotos.length,
                            );
                            final photos = _touristSpotPhotos.sublist(
                              startIndex,
                              endIndex,
                            );
                            return GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 1.0,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: photos.length,
                              itemBuilder: (context, index) {
                                final photo = photos[index];

                                // (수정 1) 방문 기록의 장소 이름이 사진 제목에 포함되는지 확인하는 정확한 로직으로 변경
                                final isVisited = _visitHistory.any(
                                  (visit) =>
                                      (visit['is_correct'] == true ||
                                          visit['is_correct'] == 1) &&
                                      photo.galTitle.contains(
                                        visit['target_place'],
                                      ),
                                );

                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  elevation: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        // (수정 2) 방문했다면(isVisited: true) 필터를 적용하지 않은 원본 컬러 이미지를,
                                        // 방문하지 않았다면(isVisited: false) 흑백 필터를 적용하도록 구조 변경
                                        child: isVisited
                                            ? Image.network(
                                                photo.galWebImageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    const Center(
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    size: 50,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              )
                                            : ColorFiltered(
                                                colorFilter:
                                                    const ColorFilter.matrix(
                                                  <double>[
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
                                                  ],
                                                ),
                                                child: Image.network(
                                                  photo.galWebImageUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (c, e, s) =>
                                                      const Center(
                                                    child: Icon(
                                                      Icons.broken_image,
                                                      size: 50,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          photo.galTitle,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                      if ((_touristSpotPhotos.length / 4).ceil() > 1)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              (_touristSpotPhotos.length / 4).ceil(),
                              (index) => buildDot(index, pageController),
                            ),
                          ),
                        ),
                    ],
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

  Widget buildDot(int index, PageController pageController) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double selectedness = 0.0;
        if (pageController.hasClients && pageController.page != null) {
          selectedness = 1 - (pageController.page! - index).abs();
        }
        selectedness = selectedness.clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          width: 8.0 + (selectedness * 4),
          height: 8.0 + (selectedness * 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withOpacity(0.5 + (selectedness * 0.5)),
          ),
        );
      },
    );
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => isMapLoaded = true);
            _onMapReady();
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
    if (!isMapLoaded || _isLoading || !mounted) return;
    _displayTouristPhotos();
    _getCurrentLocation(showMessages: false);
  }

  Future<void> _displayTouristPhotos() async {
    if (_touristSpotPhotos.isEmpty || !isMapLoaded) return;
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
        final jsCode =
            "addPhotoMarker(${coords['lat']}, ${coords['lng']}, '${photo.galWebImageUrl}', '${photo.galTitle.replaceAll("'", "\\'")}', '${photo.galContentId}', $isVisited);";
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
      if (mounted && showMessages)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get current location: $e')),
        );
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
    if (currentPosition != null)
      allPoints.add({
        'lat': currentPosition!.latitude,
        'lng': currentPosition!.longitude,
      });
    allPoints.addAll(
      _touristSpotPhotos
          .map((p) => _placeCoords[p.galTitle])
          .where((c) => c != null)
          .cast<Map<String, double>>(),
    );
    if (allPoints.isNotEmpty)
      await _controller.runJavaScript('fitMapBounds(${jsonEncode(allPoints)})');
  }

  Future<void> _submitPrediction(File imageFile, String targetPlace) async {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location is unknown.')),
      );
      return;
    }
    //setState(() => _isSubmitting = true);
    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$serverUrl/predict/'))
            ..fields['session_id'] = _sessionId!
            ..fields['target_place'] = targetPlace
            ..fields['latitude'] = currentPosition!.latitude.toString()
            ..fields['longitude'] = currentPosition!.longitude.toString()
            ..files.add(
              await http.MultipartFile.fromPath('image', imageFile.path),
            );
      final response = await request.send();
      final responseData = json.decode(await response.stream.bytesToString());
      if (response.statusCode == 200) {
        // ▼▼▼ 수정된 부분 시작 ▼▼▼
        final bool isCorrect = responseData['is_correct'];

        if (isCorrect) {
          // 1. 인증에 성공한 관광지의 PhotoItem 찾기
          final photoItem = _touristSpotPhotos.firstWhere(
            (p) => p.galTitle.contains(targetPlace),
            orElse: () => PhotoItem.empty(),
          );

          // 2. PhotoItem의 contentId를 이용해 JS 함수 호출
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
        // ▲▲▲ 수정된 부분 끝 ▲▲▲

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Result: ${responseData['message']} (+${responseData['score_earned']} pts)',
              ),
              backgroundColor:
                  responseData['is_correct'] ? Colors.green : Colors.orange,
            ),
          );
          await _fetchUserProfile(_userId!);
          await _fetchRankings();
        }
      } else {
        throw Exception(responseData['detail']);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      //if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _getImage(ImageSource source) async {
    if (_currentTargetPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a landmark from the map first.'),
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
      if (image != null)
        await _submitPrediction(File(image.path), _currentTargetPlace!);
    } catch (e) {
      print('Image selection error: $e');
    }
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('현재 위치를 가져올 수 없습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => isLocationLoading = false);
    }
  }

  Future<void> _pickImage() async {
    // _currentTargetPlace null 체크 제거 (이미 설정된 상태에서만 호출되므로)
    showModalBottomSheet(
      context: context,
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
          ],
        ),
      ),
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
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            SingleChildScrollView(
              child: Column(
                children: [
                  Image.network(
                    photo.galWebImageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => Container(
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
                          'Title: ${photo.galTitle}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('위치: ${photo.galPhotographyLocation}'),
                        const SizedBox(height: 16),
                        if (matchedPlace.isNotEmpty)
                          Center(
                            child: ElevatedButton.icon(
                              icon: Icon(
                                isVisited
                                    ? Icons.check_circle
                                    : Icons.flag_outlined,
                              ),
                              label: Text(
                                isVisited ? '인증 완료' : '이 장소로 미션 시작',
                              ),
                              onPressed: isVisited
                                  ? () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('이미 방문한 관광지입니다.')),
                                      );
                                    }
                                  : () {
                                      // 1. 먼저 다이얼로그를 닫습니다
                                      Navigator.of(context).pop();

                                      // 2. 잠깐 기다린 후 상태를 업데이트합니다
                                      Future.delayed(
                                          const Duration(milliseconds: 100),
                                          () {
                                        if (mounted) {
                                          // 기존 타이머 취소
                                          _missionBannerTimer?.cancel();

                                          // 상태 업데이트
                                          setState(() {
                                            _currentTargetPlace = matchedPlace;
                                            _showMissionBanner = true;
                                          });

                                          // 배너 숨기기 타이머 설정
                                          _missionBannerTimer = Timer(
                                            const Duration(seconds: 3),
                                            () {
                                              if (mounted) {
                                                setState(() {
                                                  _showMissionBanner = false;
                                                });
                                              }
                                            },
                                          );

                                          // 3. JavaScript 함수 호출 (에러 처리 포함)
                                          _controller
                                              .runJavaScript(
                                            "highlightMarker('${photo.galContentId}')",
                                          )
                                              .catchError((e) {
                                            print(
                                                "JS highlightMarker 호출 오류: $e");
                                          });

                                          // 4. 바로 사진 선택 모달 표시
                                          _pickImage();
                                        }
                                      });
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isVisited ? Colors.grey : Colors.blue[400],
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
          ],
        ),
      ),
    );
  }

  // ### UI Build Methods ###

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // KakaoMap WebView
          WebViewWidget(controller: _controller),

          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),

          // Profile and Score (Top Left)
          // ### MODIFIED SECTION START ###
          // Profile, Score, and Test Button (Top Left)
          // Profile, Score, and Test Button (Top Left)
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 사라졌던 프로필 및 점수 위젯 ---
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
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
                                : const Icon(
                                    Icons.person,
                                    size: 32,
                                    color: Colors.grey,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isGuest
                              ? 'Guest'
                              : _currentUser?.kakaoAccount?.profile?.nickname ??
                                  'User',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.emoji_events, color: Colors.amber),
                        const SizedBox(width: 4),
                        _isProfileLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                '$_totalScore점',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.blue,
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- 테스트 위치 설정 드롭다운 메뉴 ---
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTestPlace,
                        hint: const Text("테스트 위치 선택"),
                        isDense: true,
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedTestPlace = newValue;
                            });
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
          // ### MODIFIED SECTION END ###

          // Target Mission Info
          // [수정] _showMissionBanner 조건 추가
          if (_showMissionBanner && _currentTargetPlace != null)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _isMenuOpen ? 0.0 : 1.0, // Hide when menu is open
                duration: _menuAnimationDuration,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      '현재 미션: $_currentTargetPlace',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ▼▼▼ MODIFIED SECTION: Unified FAB Menu ▼▼▼
          _buildFabMenu(),
          // ▲▲▲ MODIFIED SECTION: Unified FAB Menu ▲▲▲
        ],
      ),
    );
  }

  // --- Helper methods for FAB Menu ---

  /// Builds the entire Floating Action Button menu system.
  Widget _buildFabMenu() {
    // A list of FABs to be displayed.
    final List<Widget> menuButtons = [
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
                  color: Colors.blue,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.my_location),
      ),
      // _buildMenuOption(
      //   distance: 70.0, // Distance from main FAB
      //   tooltip: '인증샷 촬영',
      //   onPressed: _pickImage,
      //   backgroundColor:
      //       _currentTargetPlace != null ? Colors.green : Colors.grey,
      //   foregroundColor: Colors.white,
      //   child: _isSubmitting
      //       ? const SizedBox(
      //           width: 24,
      //           height: 24,
      //           child: CircularProgressIndicator(
      //             color: Colors.white,
      //             strokeWidth: 3,
      //           ),
      //         )
      //       : const Icon(Icons.camera_alt),
      // ),
    ];
    return Positioned(
      bottom: 16,
      right: 16,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // Invisible background to dismiss the menu when tapped
          if (_isMenuOpen)
            GestureDetector(
              onTap: () => setState(() => _isMenuOpen = false),
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),

          // The expanding menu buttons
          ...menuButtons,

          // Main FAB that controls the menu
          FloatingActionButton(
            heroTag: 'mainMenuBtn',
            backgroundColor: _isMenuOpen ? Colors.white : Colors.blue,
            onPressed: () {
              setState(() {
                _isMenuOpen = !_isMenuOpen;
              });
            },
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

  /// Builds a single option in the expanding FAB menu.
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
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                tooltip,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            FloatingActionButton(
              heroTag: tooltip, // Unique heroTag prevents animation errors
              onPressed: () {
                // Close the menu when an option is selected
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

  // The rest of your methods like _buildLoadingIndicator, etc.
  Widget _buildLoadingIndicator() {
    String message = 'Loading map...';
    if (_isLoading) message = 'Preparing game data...';
    if (_isSubmitting) message = 'Analyzing photo and calculating score...';
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProfileBar(String? profileImageUrl, String? nickname) {
    return Positioned(
      top: 40,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage: profileImageUrl != null
                    ? NetworkImage(profileImageUrl)
                    : null,
                radius: 20,
                child:
                    profileImageUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname ?? 'User',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    _isProfileLoading
                        ? const Text(
                            'Loading score...',
                            style: TextStyle(fontSize: 12),
                          )
                        : Text(
                            'Score: $_totalScore',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.book_outlined, color: Colors.blueGrey),
                tooltip: 'View Collection',
                onPressed: _showCollectionBookDialog,
              ),
              IconButton(
                icon: const Icon(
                  Icons.leaderboard_outlined,
                  color: Colors.blueGrey,
                ),
                tooltip: 'View Rankings',
                onPressed: _showRankingDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Positioned(
      bottom: 30,
      right: 16,
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: 'location_button',
            onPressed: isLocationLoading ? null : () => _getCurrentLocation(),
            backgroundColor: Colors.white,
            mini: true,
            child: isLocationLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, color: Colors.blue),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'photo_button',
            onPressed: _pickImage,
            backgroundColor: Colors.white,
            mini: true,
            child: const Icon(Icons.add_a_photo, color: Colors.blue),
          ),
        ],
      ),
    );
  }
}
