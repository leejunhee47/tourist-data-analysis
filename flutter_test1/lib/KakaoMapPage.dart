// KakaoMapPage.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'PhotoItem.dart';
import 'quest_model.dart';

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
  Timer? _missionBannerTimer;
  bool _showMissionBanner = false;
  // +++ 추가된 상태 변수 +++
  String? _selectedTestPlace;
  // --- Data State (from MainPage) ---
  bool _isLoading = true;
  String? _sessionId;
  // MODIFIED: Added _allSeoulPhotos list to store other photos.
  final List<PhotoItem> _touristSpotPhotos = [];
  final List<PhotoItem> _allSeoulPhotos = [];
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

  List<Quest> _quests = [];
  QuestProgress? _questProgress;
  bool _isQuestLoading = false;

  @override
  void initState() {
    super.initState();
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
    _missionBannerTimer?.cancel();
    super.dispose();
  }

  /// 테스트용으로 현재 위치를 선택된 관광지의 좌표로 설정합니다.
  Future<void> _setTestLocationTo(String? placeName) async {
    if (placeName == null) return;
    if (_placeCoords.containsKey(placeName)) {
      final coords = _placeCoords[placeName]!;
      final testLatitude = coords['lat']!;
      final testLongitude = coords['lng']!;
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
      if (mounted) {
        setState(() {
          currentPosition = testPosition;
        });
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
          content: Text('\'$placeName\'의 좌표를 찾을 수 없습니다. 장소 데이터 확인이 필요합니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshKakaoUser() async {
    if (widget.isGuest) return;
    try {
      User updatedUser = await UserApi.instance.me();
      if (mounted) {
        setState(() {
          _currentUser = updatedUser;
        });
      }
    } catch (error) {
      print('카카오 유저 정보 새로고침 실패: $error');
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
        _fetchQuestsAndProgress(),
      ]);
      await _startGameSession();
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _onMapReady();
    }
  }

  // 퀘스트 정보와 진행 상황을 모두 가져오는 새 함수 추가
  Future<void> _fetchQuestsAndProgress() async {
    if (_userId == null) return;
    setState(() => _isQuestLoading = true);
    try {
      // API에서 퀘스트 목록과 진행 상황을 동시에 가져옵니다.
      final questsResponse =
          await http.get(Uri.parse('$serverUrl/quests/$_userId'));
      final progressResponse =
          await http.get(Uri.parse('$serverUrl/quests/$_userId/progress'));

      if (questsResponse.statusCode == 200 &&
          progressResponse.statusCode == 200) {
        final questsData = json.decode(utf8.decode(questsResponse.bodyBytes));

        // ▼▼▼ 디버깅 코드 추가 ▼▼▼
        print('--- 서버로부터 받은 퀘스트 목록 ---');
        print(jsonEncode(questsData));
        // ▲▲▲ 디버깅 코드 추가 ▲▲▲

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
      } else {
        // 에러 처리
        print('퀘스트 또는 진행상황 로드 실패');
      }
    } catch (e) {
      print('퀘스트 데이터 로딩 오류: $e');
    } finally {
      if (mounted) setState(() => _isQuestLoading = false);
    }
  }

  // ### MODIFIED METHOD START ###
  Future<void> _getOrCreateUser() async {
    final String? username = widget.isGuest
        ? "게스트유저"
        : _currentUser?.kakaoAccount?.profile?.nickname;

    // 카카오 프로필 썸네일 URL을 가져옵니다.
    final String? profileImageUrl = widget.isGuest
        ? ""
        : _currentUser?.kakaoAccount?.profile?.thumbnailImageUrl;

    if (username == null) return;
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/create_user/'),
        headers: {'Content-Type': 'application/json'},
        // 요청 본문에 프로필 이미지 URL을 추가합니다.
        body: json.encode({
          'username': username,
          'profile_image_url': profileImageUrl ?? '',
        }),
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
  // ### MODIFIED METHOD END ###

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

  // MODIFIED: This method now populates both mission photos and other Seoul photos.
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

      // +추가된 부분: 필터링된 모든 서울 사진을 별도 리스트에 저장 +++
      if (mounted) {
        setState(() {
          _allSeoulPhotos.clear();
          _allSeoulPhotos.addAll(seoulPhotos);
        });
      }

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
          // Populate mission photos
          _touristSpotPhotos.clear();
          for (var keyword in targetKeywords) {
            if (foundPhotosMap.containsKey(keyword)) {
              _touristSpotPhotos.add(foundPhotosMap[keyword]!);
            }
          }
          // Populate other Seoul photos by excluding mission photos
          final Set<String> missionPhotoIds =
              _touristSpotPhotos.map((p) => p.galContentId).toSet();
          _allSeoulPhotos.clear();
          _allSeoulPhotos.addAll(seoulPhotos
              .where((p) => !missionPhotoIds.contains(p.galContentId)));
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

  // ### MODIFIED METHOD START ###
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
          title: const Text(
            '명예의 전당',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
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
                            final username = rankData['username'];
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
                                  leading: Text(
                                    '${rankData['rank']}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  // MODIFIED: 사용자 이름이 길 경우 좌우 스크롤이 가능하도록 수정
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
                                                  loadingBuilder: (context,
                                                          child, progress) =>
                                                      progress == null
                                                          ? child
                                                          : const Center(
                                                              child:
                                                                  CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2)),
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
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
                                          child: Text(
                                            username,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Text(
                                    '${rankData['total_score']}점',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
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
              child: const Text('닫기'),
            ),
          ],
        ),
      );
    });
  }
  // ### MODIFIED METHOD END ###

  // MODIFIED: This entire method is rewritten to support toggling between mission and Seoul photos.
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

            // ### MODIFIED METHOD START ###
            // 수정된 에러 핸들러: 실패 시 빈 공간을 반환
            Widget errorBuilder(String url, Object error) {
              final bool isPermanentError =
                  error is NetworkImageLoadException && error.statusCode == 404;

              // 404 오류인 경우에만 목록에서 영구적으로 제거합니다.
              if (isPermanentError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!brokenUrls.contains(url)) {
                    setState(() {
                      brokenUrls.add(url);
                    });
                  }
                });
              }

              // 모든 오류에 대해 빈 위젯을 반환하여 보이지 않게 처리합니다.
              return const SizedBox.shrink();
            }
            // ### MODIFIED METHOD END ###

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
                    Text('나의 컬렉션 북'),
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
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                                  child: Text(
                                    "미션 관광지 보기",
                                    style: TextStyle(
                                      color: showWeekly
                                          ? Colors.white
                                          : Colors.black54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
                                  child: Text(
                                    "서울 관광지 보기",
                                    style: TextStyle(
                                      color: !showWeekly
                                          ? Colors.white
                                          : Colors.black54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 세로 스크롤이 가능한 그리드 뷰
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
                                final isVisited = _visitHistory.any((visit) =>
                                    (visit['is_correct'] == true ||
                                        visit['is_correct'] == 1) &&
                                    photo.galTitle
                                        .contains(visit['target_place']));
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
                                            // 컬러 이미지
                                            ? Image.network(
                                                photo.galWebImageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    errorBuilder(
                                                        photo.galWebImageUrl,
                                                        e),
                                              )
                                            // 흑백 이미지
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
                                                  photo.galWebImageUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (c, e, s) =>
                                                      errorBuilder(
                                                          photo.galWebImageUrl,
                                                          e),
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
                  child: const Text('닫기'),
                ),
              ],
            );
          },
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

  // MODIFIED: This function is no longer needed at the class level.
  // It has been moved inside the `_showCollectionBookDialog`'s `StatefulBuilder`.
  // Widget buildDot(...) { ... }

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

  /// ▼▼▼ [수정] 거리 표기 단위를 1000m 이상일 때 km로 변환 ▼▼▼
  void _showPredictionResultOverlay({
    required bool isCorrect,
    required String message,
    required int scoreEarned,
  }) {
    if (!mounted) return;

    // --- 결과 표시 위젯의 컨텐츠 생성 ---
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
          const Text(
            "정답입니다!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
          if (scoreEarned > 0) ...[
            const SizedBox(height: 12),
            Text(
              '+$scoreEarned 점',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ],
      );
    } else {
      String serverMessage = message;
      // 사용자의 실제 거리만 조건부로 km로 변환하는 로직
      try {
        final RegExp distanceRegex = RegExp(r'(\d+(\.\d+)?)\s*m');
        final Match? match = distanceRegex.firstMatch(serverMessage);

        if (match != null && match.group(0) != null && match.group(1) != null) {
          final double distanceInMeters = double.parse(match.group(1)!);

          // 변환 조건: 1000m 이상일 경우
          if (distanceInMeters >= 1000) {
            final double distanceInKm = distanceInMeters / 1000.0;
            final String formattedKm = distanceInKm.toStringAsFixed(2);
            // replaceFirst를 사용해 첫 번째로 발견된 거리만 km로 변경
            serverMessage =
                serverMessage.replaceFirst(match.group(0)!, '$formattedKm km');
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
        details = parts.length > 1 ? parts[1].replaceAll(', ', '\n') : '';
      }
      resultContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mainMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              details,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
            )
          ]
        ],
      );
    }

    // --- 다이얼로그 스타일의 컨테이너 위젯 ---
    final overlayContent = Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40.0), // 좌우 여백
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10.0,
              offset: Offset(0.0, 4.0),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            resultTitle,
            const SizedBox(height: 20),
            resultContent,
          ],
        ),
      ),
    );

    // --- 자동 사라짐 오버레이 표시 ---
    _showAutoDismissingOverlay(
      child: overlayContent,
      duration: const Duration(seconds: 3),
    );
  }
  // ▲▲▲ 수정 완료 ▲▲▲

  Future<void> _submitPrediction(File imageFile, String targetPlace) async {
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
          http.MultipartRequest('POST', Uri.parse('$serverUrl/predict/'))
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
          // 수정된 오버레이 함수 호출 (await 없음)
          _showPredictionResultOverlay(
            isCorrect: isCorrect,
            message: message,
            scoreEarned: scoreEarned,
          );
          // UI 표시와 동시에 데이터 새로고침
          _fetchUserProfile(_userId!);
          _fetchRankings();
          _fetchQuestsAndProgress();
        }
      } else {
        throw Exception(responseData['detail'] ?? '서버에서 오류가 발생했습니다.');
      }
    } on SocketException {
      // 네트워크 연결이 없는 경우
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

  /// ▼▼▼ [수정] 재사용 가능한 자동 사라짐 오버레이 함수 ▼▼▼
  void _showAutoDismissingOverlay({
    required Widget child,
    required Duration duration,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FadeIn(
        child: IgnorePointer(
          // UI 뒤의 다른 위젯 터치를 막지 않음
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
        // 간단한 텍스트 토스트 표시
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('현재 위치를 가져올 수 없습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => isLocationLoading = false);
    }
  }
  // ▲▲▲ 수정 완료 ▲▲▲

  Future<void> _pickImage() async {
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
                                isVisited ? '다시 인증하기' : '이 장소로 미션 시작',
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                Future.delayed(
                                    const Duration(milliseconds: 100), () {
                                  if (mounted) {
                                    _missionBannerTimer?.cancel();
                                    setState(() {
                                      _currentTargetPlace = matchedPlace;
                                      _showMissionBanner = true;
                                    });
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
                                    _controller
                                        .runJavaScript(
                                      "highlightMarker('${photo.galContentId}')",
                                    )
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
          if (_showMissionBanner && _currentTargetPlace != null)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _isMenuOpen ? 0.0 : 1.0,
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
          _buildFabMenu(),
        ],
      ),
    );
  }

  Widget _buildFabMenu() {
    final List<Widget> menuButtons = [
      _buildMenuOption(
        // <--- 새로운 퀘스트 버튼 추가
        distance: 250.0, // 다른 버튼과 겹치지 않게 거리 조정
        tooltip: '퀘스트 목록',
        onPressed: _showQuestDialog, // 퀘스트 다이얼로그를 여는 함수
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
                  color: Colors.blue,
                  strokeWidth: 3,
                ),
              )
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
                height: MediaQuery.of(context).size.height,
              ),
            ),
          ...menuButtons,
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

  // 퀘스트 목록 다이얼로그 표시
  void _showQuestDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // StatefulBuilder를 사용해 다이얼로그 내부 상태만 업데이트
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('오늘의 퀘스트'),
              content: SizedBox(
                width: double.maxFinite,
                child: _isQuestLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_questProgress != null)
                            _buildProgressBar(_questProgress!), // 진행상황 바
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _quests.length,
                              itemBuilder: (context, index) {
                                final quest = _quests[index];
                                // 퀘스트 상태에 따라 다른 카드 위젯 반환
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
                                        child:
                                            ListTile(title: Text(quest.title)));
                                }
                              },
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
      },
    );
  }

  // 진행 상황 바 위젯
  Widget _buildProgressBar(QuestProgress progress) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress.progressPercentage / 100,
          minHeight: 10,
          borderRadius: BorderRadius.circular(5),
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

  // "진행 중" 상태의 퀘스트 카드
  // "진행 중" 상태의 퀘스트 카드
  Widget _buildActiveQuestCard(Quest quest, StateSetter setDialogState) {
    // 퀘스트 타입이 'history_quiz'이고 아직 풀지 않았다면 퀴즈 UI를 보여줌
    if (quest.type == 'history_quiz' && quest.isAnswered != true) {
      return Card(
        color: Colors.blue[50],
        child: ExpansionTile(
          // ExpansionTile로 질문과 답변을 감싸서 UI를 깔끔하게 만듭니다.
          key: PageStorageKey(quest.questId), // 스크롤 시 상태 유지를 위해 Key 추가
          title: Text(quest.title),
          subtitle: Text('퀴즈를 풀어보세요! (+${quest.points}점)'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quest.quizQuestion ?? '문제를 불러오는 데 실패했습니다.',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  // quizOptions를 기반으로 선택지를 만듭니다.
                  ...(quest.quizOptions ?? []).asMap().entries.map((entry) {
                    int idx = entry.key;
                    String option = entry.value;
                    return ListTile(
                      title: Text(option),
                      onTap: () async {
                        // 답변을 선택하면 API를 호출합니다.
                        await _submitQuizAnswer(quest.questId, idx);
                        // 기존 다이얼로그를 닫고, 새로고침된 정보로 다시 엽니다.
                        if (mounted) {
                          Navigator.of(context).pop();
                          _showQuestDialog();
                        }
                      },
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // 'history_quiz'가 아닌 다른 'active' 퀘스트 (예: theme_mission)
    return Card(
      child: ListTile(
        leading: const Icon(Icons.tour),
        title: Text(quest.title),
        subtitle: Text(
            '목표: ${quest.completedPlaces.length} / ${quest.requiredVisits}'),
      ),
    );
  }

  // "보상 받기" 상태의 퀘스트 카드
  Widget _buildRewardReadyCard(Quest quest, StateSetter setDialogState) {
    return Card(
      color: Colors.orange[100],
      child: ListTile(
        leading: const Text('🎁', style: TextStyle(fontSize: 24)),
        title: Text(quest.title),
        subtitle: Text('보상: +${quest.points}점'),
        trailing: ElevatedButton(
          onPressed: () => _claimReward(quest.questId, setDialogState),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('보상 받기'),
        ),
      ),
    );
  }

  // 퀴즈 답변 제출 API 호출
  Future<void> _submitQuizAnswer(String questId, int answerIndex) async {
    if (_userId == null) return;
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/quests/quiz/answer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId!,
          'quest_id': questId,
          'answer_index': answerIndex,
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final result = data['result'];

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: result['is_correct'] ? Colors.green : Colors.red,
          ),
        );
        // 답변 제출 후 퀘스트 목록과 프로필 정보(점수) 새로고침
        await Future.wait(
            [_fetchQuestsAndProgress(), _fetchUserProfile(_userId!)]);
      }
    } catch (e) {
      print('퀴즈 답변 제출 오류: $e');
    }
  }

  // 보상 받기 API 호출
  Future<void> _claimReward(String questId, StateSetter setDialogState) async {
    if (_userId == null) return;
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/quests/reward'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId!,
          'quest_id': questId,
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final result = data['result'];
        final int rewardPoints = result['reward_points'] ?? 0;

        // 보상 획득 애니메이션/알림 표시
        showDialog(
          context: context,
          builder: (dContext) => AlertDialog(
            title: const Text('🎉 축하합니다!'),
            content: Text('+$rewardPoints점을 획득했습니다!'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dContext),
                  child: const Text('확인'))
            ],
          ),
        );

        // 보상 수령 후 퀘스트 목록과 프로필 정보(점수) 새로고침
        await Future.wait(
            [_fetchQuestsAndProgress(), _fetchUserProfile(_userId!)]);

        // 다이얼로그 UI 갱신
        setDialogState(() {});
      }
    } catch (e) {
      print('보상 받기 오류: $e');
    }
  }

  // "완료" 상태의 퀘스트 카드
  Widget _buildCompletedQuestCard(Quest quest) {
    return Card(
      color: Colors.grey[300],
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(quest.title,
            style: const TextStyle(decoration: TextDecoration.lineThrough)),
        subtitle: Text('보상 +${quest.points}점 획득 완료'),
      ),
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

  // 순위에 따라 적절한 메달 색상을 반환하는 함수
  Color _getPodiumColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber; // 금색
      case 2:
        return Colors.grey[400]!; // 은색
      case 3:
        return const Color(0xFFCD7F32); // 동색
      default:
        return Colors.blue;
    }
  }

  // ### MODIFIED METHOD START ###
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
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                            errorBuilder: (context, error, stackTrace) => Icon(
                                Icons.person,
                                size: iconSize,
                                color: Colors.grey[400]),
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
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // MODIFIED: 사용자 이름이 길 경우 좌우 스크롤이 가능하도록 너비를 제한
          Builder(
            builder: (context) {
              const style =
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
              final maxWidth = avatarRadius * 2;

              // TextPainter를 사용해 텍스트의 실제 너비를 계산합니다.
              final textPainter = TextPainter(
                text: TextSpan(text: username, style: style),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout();

              // 텍스트 너비가 최대 너비보다 크면 스크롤 뷰를 사용합니다.
              if (textPainter.size.width > maxWidth) {
                return SizedBox(
                  width: maxWidth,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(username, style: style),
                  ),
                );
              } else {
                // 그렇지 않으면 일반 Text 위젯을 사용해 중앙 정렬합니다.
                return Text(username,
                    style: style, textAlign: TextAlign.center);
              }
            },
          ),
          const SizedBox(height: 2),
          Text(
            '$score pts',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// ▼▼▼ [추가] 오버레이 애니메이션을 위한 별도 위젯 ▼▼▼
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

    // 애니메이션 시작
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
