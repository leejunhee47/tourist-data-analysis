// lib/loading_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'KakaoMapPage.dart';
import 'PhotoItem.dart';
import 'game_data_model.dart';
import 'quest_model.dart';
import 'login_page.dart';
import 'config.dart';

class LoadingPage extends StatefulWidget {
  final User? user;
  final bool isGuest;
  // --- [추가] Admin 정보를 위한 필드 ---
  final String? adminUserId;
  final String? adminUsername;

  const LoadingPage({super.key, this.user})
      : isGuest = false,
        adminUserId = null,
        adminUsername = null;

  const LoadingPage.guest({super.key})
      : user = null,
        isGuest = true,
        adminUserId = null,
        adminUsername = null;

  // --- [추가] Admin을 위한 생성자 ---
  const LoadingPage.admin({
    super.key,
    required this.adminUserId,
    required this.adminUsername,
  })  : user = null,
        isGuest = false;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  double _progress = 0.0;
  String _loadingMessage = '여행 준비를 시작합니다...';

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
    '노들섬',
    '낙산공원',
    '은평한옥마을',
    '동대문디자인플라자',
    '창덕궁',
    '올림픽공원_들꽃마루',
    '창경궁',
    '덕수궁',
    '숭례문',
    '롯데타워',
    '봉은사',
    '서울숲',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllGameData();
    });
  }

  void _updateProgress(double value, String message) {
    if (mounted) {
      setState(() {
        _progress = value;
        _loadingMessage = message;
      });
    }
  }

  Future<List<PhotoItem>> _processImages(List<PhotoItem> photos) async {
    List<PhotoItem> processedPhotos = [];
    // 이미지 처리는 CPU를 많이 사용하므로 동시 처리를 제한하여 앱의 반응성을 유지
    int concurrentJobs = 5;
    List<Future<PhotoItem>> futures = [];

    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      futures.add(_resizeAndEncode(photo));

      // 5개씩 묶어서 처리하거나 마지막 아이템일 경우
      if (futures.length == concurrentJobs || i == photos.length - 1) {
        final results = await Future.wait(futures);
        processedPhotos.addAll(results);
        futures.clear(); // 다음 배치를 위해 리스트 비우기

        // 진행 상황 업데이트
        _updateProgress(0.5 + (0.2 * (processedPhotos.length / photos.length)),
            '관광지 이미지 최적화 중... (${processedPhotos.length}/${photos.length})');
      }
    }
    return processedPhotos;
  }

  // [추가] 개별 이미지 리사이징 및 Base64 인코딩 함수
  Future<PhotoItem> _resizeAndEncode(PhotoItem photo) async {
    try {
      final response = await http.get(Uri.parse(photo.galWebImageUrl));
      if (response.statusCode == 200) {
        // 이미지 디코딩
        img.Image? originalImage = img.decodeImage(response.bodyBytes);
        if (originalImage != null) {
          // 이미지 리사이징 (너비 200px, 높이는 비율에 맞게 자동 조절)
          img.Image resizedImage = img.copyResize(originalImage, width: 200);
          // JPEG 형식으로 인코딩
          Uint8List jpgBytes =
              Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
          // Base64 문자열로 변환
          String base64String = base64Encode(jpgBytes);
          // 데이터 URI 형식으로 완성 후 PhotoItem에 저장
          return photo.copyWith(
              base64Thumbnail: 'data:image/jpeg;base64,$base64String');
        }
      }
    } catch (e) {
      print('이미지 처리 오류 (${photo.galTitle}): $e');
    }
    // 실패 시 원본 PhotoItem 반환
    return photo;
  }

  // --- [수정] _getOrCreateUser 함수: 로그인 방식에 따라 다른 API 호출 ---
  Future<Map<String, String>?> _getOrCreateUser() async {
    try {
      if (widget.isGuest) {
        // 게스트 로그인 API 호출
        final response = await http.post(
          Uri.parse('$serverUrl/guest_login/'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          return {'user_id': data['user_id'], 'username': data['username']};
        }
      } else if (widget.user != null) {
        // 카카오 로그인 (기존 로직)
        final String? username = widget.user?.kakaoAccount?.profile?.nickname;
        final String? profileImageUrl =
            widget.user?.kakaoAccount?.profile?.thumbnailImageUrl;

        if (username == null) return null;

        final response = await http.post(
          Uri.parse('$serverUrl/create_user/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': username,
            'profile_image_url': profileImageUrl ?? ''
          }),
        );
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          // API 응답에서 username을 받아올 수 있지만, 카카오 닉네임을 그대로 사용
          return {'user_id': data['user_id'], 'username': username};
        }
      }
    } catch (e) {
      print('User creation/retrieval error: $e');
    }
    return null;
  }

  // --- [수정] _loadAllGameData 함수: 3가지 로그인 방식 처리 ---
  Future<void> _loadAllGameData() async {
    try {
      _updateProgress(0.1, '사용자 정보 확인 중...');
      String? userId;
      String? username;
      // admin, guest, kakao 로그인 여부를 확인하여 userId와 username 설정
      if (widget.adminUserId != null) {
        // 1. Admin 로그인
        userId = widget.adminUserId;
        username = widget.adminUsername;
      } else {
        // 2. Kakao 또는 Guest 로그인
        final userInfo = await _getOrCreateUser();
        if (userInfo == null) throw Exception("사용자 정보를 가져올 수 없습니다.");
        userId = userInfo['user_id'];
        username = userInfo['username'];
      }

      if (userId == null || username == null) {
        throw Exception("유효한 사용자 정보가 없습니다.");
      }

      _updateProgress(0.25, '내 정보 불러오는 중...');
      final userProfile = await _fetchUserProfile(userId);

      _updateProgress(0.5, '관광지 사진 로딩 중...');
      final photoData = await _fetchTouristSpotPhotos();

      List<PhotoItem> originalPhotos = photoData['touristSpotPhotos']!;
      List<PhotoItem> processedPhotos = await _processImages(originalPhotos);
      photoData['touristSpotPhotos'] = processedPhotos;

      final keywordPhotos = await _fetchKeywordSearchPhotos('서울');

      _updateProgress(0.7, '장소 및 랭킹 정보 확인 중...');
      final placeCoords = await _fetchPlaceCoordinates();
      final rankings = await _fetchRankings();

      _updateProgress(0.85, '오늘의 퀘스트 확인 중...');
      final questData = await _fetchQuestsAndProgress(userId);

      _updateProgress(0.95, '여행 세션을 시작합니다...');
      final sessionId = await _startGameSession(userId);

      _updateProgress(1.0, '로딩 완료');
      await Future.delayed(const Duration(milliseconds: 500));

      final gameData = GameData(
        userId: userId,
        username: username, // [추가] username 전달
        sessionId: sessionId,
        currentUser: widget.user,
        isGuest: widget.isGuest,
        isAdmin: widget.adminUserId != null,
        totalScore: userProfile['total_score'],
        visitHistory: userProfile['visit_history'],
        touristSpotPhotos: photoData['touristSpotPhotos']!,
        allSeoulPhotos: photoData['allSeoulPhotos']!,
        keywordSearchedPhotos: keywordPhotos,
        placeCoords: placeCoords,
        rankings: rankings,
        quests: questData['quests'],
        questProgress: questData['questProgress'],
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => KakaoMapPage(gameData: gameData),
          ),
        );
      }
    } catch (e) {
      print("데이터 로딩 중 심각한 오류 발생: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터를 불러오는데 실패했습니다: $e')),
        );
        // [추가] 오류 발생 시 로그인 페이지로 복귀
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  // (이하 다른 함수들은 이전과 거의 동일)
  Future<List<PhotoItem>> _fetchKeywordSearchPhotos(String keyword) async {
    try {
      final url = Uri.parse('$baseUrl/gallerySearchList1').replace(
        queryParameters: {
          'serviceKey': serviceKey,
          'numOfRows': '5000',
          'pageNo': '1',
          'MobileOS': 'ETC',
          'MobileApp': 'AppTest',
          'arrange': 'A',
          'keyword': keyword,
          '_type': 'json',
        },
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final items =
            json.decode(response.body)['response']['body']['items']['item'];
        if (items is List) {
          return items.map((item) => PhotoItem.fromJson(item)).toList();
        }
      }
    } catch (e) {
      print('키워드 검색 사진 로드 오류: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> _fetchUserProfile(String userId) async {
    try {
      final response =
          await http.get(Uri.parse('$serverUrl/user_profile/$userId'));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      print('User profile loading error: $e');
    }
    return {'total_score': 0, 'visit_history': []};
  }

  Future<Map<String, List<PhotoItem>>> _fetchTouristSpotPhotos() async {
    final List<PhotoItem> touristSpotPhotos = [];
    final List<PhotoItem> allSeoulPhotos = [];

    // 서버에서 로컬 이미지 URL 맵 가져오기
    Map<String, String> localImageUrls = {};
    try {
      final response =
          await http.get(Uri.parse('$serverUrl/places/local-images'));
      if (response.statusCode == 200) {
        localImageUrls = Map<String, String>.from(
            json.decode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching local image URLs: $e');
    }

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
      if (response.statusCode != 200) throw Exception('사진 API 로딩 실패');

      final items =
          json.decode(response.body)['response']['body']['items']['item'];
      final photos =
          (items as List).map((item) => PhotoItem.fromJson(item)).toList();
      final seoulPhotos = photos
          .where((p) => p.galPhotographyLocation.toLowerCase().contains('서울'))
          .toList();

      allSeoulPhotos.addAll(seoulPhotos);

      final Map<String, PhotoItem> foundPhotosMap = {};
      final Set<String> keywordsToFind = targetKeywords.toSet();

      for (final keyword in List.from(keywordsToFind)) {
        for (final photo in seoulPhotos) {
          final photoTitleLower = photo.galTitle.toLowerCase();
          bool isMatch = false;
          if (keyword == '롯데타워') {
            if (photoTitleLower.contains('롯데타워') ||
                photoTitleLower.contains('롯데월드타워')) {
              isMatch = true;
            }
          } else {
            if (photoTitleLower.contains(keyword.toLowerCase())) {
              isMatch = true;
            }
          }
          if (isMatch) {
            foundPhotosMap[keyword] = photo;
            keywordsToFind.remove(keyword);
            break;
          }
        }
      }

      for (final keyword in keywordsToFind) {
        foundPhotosMap[keyword] = PhotoItem(
          galContentId: keyword,
          galTitle: keyword,
          galWebImageUrl: '$serverUrl/map_images/$keyword.jpg', // 기본 URL 설정
          galCreatedtime: '',
          galModifiedtime: '',
          galPhotographyMonth: '',
          galPhotographyLocation: keyword,
          galPhotographer: 'N/A',
          galSearchKeyword: keyword,
        );
      }

      for (var keyword in targetKeywords) {
        if (foundPhotosMap.containsKey(keyword)) {
          PhotoItem photoToAdd = foundPhotosMap[keyword]!;

          // 'map_images' 폴더에 해당 관광지 이미지가 있으면 API URL을 덮어쓰기
          if (localImageUrls.containsKey(keyword)) {
            final localPath = localImageUrls[keyword]!;
            final finalImageUrl = '$serverUrl$localPath';

            // 기존 PhotoItem 객체를 복사하여 galWebImageUrl만 변경
            photoToAdd = photoToAdd.copyWith(galWebImageUrl: finalImageUrl);
          }
          touristSpotPhotos.add(photoToAdd);
        }
      }
    } catch (e) {
      print('관광지 사진 로드 오류: $e');
    }
    return {
      'touristSpotPhotos': touristSpotPhotos,
      'allSeoulPhotos': allSeoulPhotos
    };
  }

  Future<Map<String, Map<String, double>>> _fetchPlaceCoordinates() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/places/'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> places = data['places'];
        final Map<String, Map<String, double>> coords = {};
        for (var place in places) {
          coords[place['name']] = {
            'lat': place['latitude'],
            'lng': place['longitude']
          };
        }
        return coords;
      }
    } catch (e) {
      print('Place coordinates loading error: $e');
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> _fetchRankings() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/rankings/'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return List<Map<String, dynamic>>.from(data['rankings']);
      }
    } catch (e) {
      print('Ranking info loading error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> _fetchQuestsAndProgress(String userId) async {
    try {
      final questsResponse =
          await http.get(Uri.parse('$serverUrl/quests/$userId'));
      final progressResponse =
          await http.get(Uri.parse('$serverUrl/quests/$userId/progress'));

      if (questsResponse.statusCode == 200 &&
          progressResponse.statusCode == 200) {
        final questsData = json.decode(utf8.decode(questsResponse.bodyBytes));
        final progressData =
            json.decode(utf8.decode(progressResponse.bodyBytes));
        return {
          'quests': (questsData['quests'] as List)
              .map((q) => Quest.fromJson(q))
              .toList(),
          'questProgress': QuestProgress.fromJson(progressData['progress']),
        };
      }
    } catch (e) {
      print('Quest data loading error: $e');
    }
    return {'quests': [], 'questProgress': null};
  }

  Future<String?> _startGameSession(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/start_game/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId, 'target_places': targetKeywords}),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes))['session_id'];
      }
    } catch (e) {
      print('Game session start error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/seoul_background.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
              BlendMode.darken,
            ),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: _progress),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 10,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Text(
                        '${(value * 100).toInt()}%',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 4.0,
                                color: Colors.black45,
                                offset: Offset(1.0, 1.0),
                              ),
                            ]),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                _loadingMessage,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
