// lib/loading_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'KakaoMapPage.dart';
import 'PhotoItem.dart';
import 'game_data_model.dart';
import 'quest_model.dart';

class LoadingPage extends StatefulWidget {
  final User? user;
  final bool isGuest;

  const LoadingPage({super.key, this.user, this.isGuest = false})
      : assert(
            user != null || isGuest, 'User must be provided if not a guest.');

  const LoadingPage.guest({super.key})
      : user = null,
        isGuest = true;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  // --- 진행 상태를 위한 변수 추가 ---
  double _progress = 0.0;
  String _loadingMessage = '여행 준비를 시작합니다...';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllGameData();
    });
  }

  // 진행률과 메시지를 업데이트하는 헬퍼 함수
  void _updateProgress(double value, String message) {
    if (mounted) {
      setState(() {
        _progress = value;
        _loadingMessage = message;
      });
    }
  }

  // 데이터를 순차적으로 불러오며 진행률을 업데이트하도록 수정
  Future<void> _loadAllGameData() async {
    try {
      // 1. 사용자 정보 가져오기 또는 생성하기
      _updateProgress(0.1, '사용자 정보 확인 중...');
      final userId = await _getOrCreateUser();
      if (userId == null) throw Exception("사용자 ID를 가져올 수 없습니다.");

      // 2. 사용자 프로필 정보 가져오기
      _updateProgress(0.25, '내 정보 불러오는 중...');
      final userProfile = await _fetchUserProfile(userId);

      // 3. 관광지 사진 정보 가져오기
      _updateProgress(0.5, '관광지 사진 로딩 중...');
      final photoData = await _fetchTouristSpotPhotos();

      // 4. 장소 좌표 및 랭킹 정보 가져오기
      _updateProgress(0.7, '장소 및 랭킹 정보 확인 중...');
      final placeCoords = await _fetchPlaceCoordinates();
      final rankings = await _fetchRankings();

      // 5. 퀘스트 정보 가져오기
      _updateProgress(0.85, '오늘의 퀘스트 확인 중...');
      final questData = await _fetchQuestsAndProgress(userId);

      // 6. 게임 세션 시작
      _updateProgress(0.95, '여행 세션을 시작합니다...');
      final sessionId = await _startGameSession(userId);

      _updateProgress(1.0, '로딩 완료');
      await Future.delayed(
          const Duration(milliseconds: 500)); // 완료 메시지를 잠시 보여주기 위함

      // GameData 객체 생성
      final gameData = GameData(
        userId: userId,
        sessionId: sessionId,
        currentUser: widget.user,
        isGuest: widget.isGuest,
        totalScore: userProfile['total_score'],
        visitHistory: userProfile['visit_history'],
        touristSpotPhotos: photoData['touristSpotPhotos']!,
        allSeoulPhotos: photoData['allSeoulPhotos']!,
        placeCoords: placeCoords,
        rankings: rankings,
        quests: questData['quests'],
        questProgress: questData['questProgress'],
      );

      // 데이터 로딩이 완료되면 지도 페이지로 이동합니다.
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
      }
    }
  }

  // (이하 데이터 로딩 함수들은 이전과 동일)
  Future<String?> _getOrCreateUser() async {
    final String? username =
        widget.isGuest ? "게스트유저" : widget.user?.kakaoAccount?.profile?.nickname;
    final String? profileImageUrl = widget.isGuest
        ? ""
        : widget.user?.kakaoAccount?.profile?.thumbnailImageUrl;

    if (username == null) return null;
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/create_user/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(
            {'username': username, 'profile_image_url': profileImageUrl ?? ''}),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes))['user_id'];
      }
    } catch (e) {
      print('User creation/retrieval error: $e');
    }
    return null;
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
          if (photo.galTitle.toLowerCase().contains(keyword.toLowerCase())) {
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
          galWebImageUrl: '$serverUrl/map_images/$keyword.jpg',
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
          touristSpotPhotos.add(foundPhotosMap[keyword]!);
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
              // --- 게이지 UI (수정된 부분) ---
              TweenAnimationBuilder<double>(
                tween: Tween(end: _progress),
                duration:
                    const Duration(milliseconds: 400), // 부드러운 전환을 위한 애니메이션 시간
                builder: (context, value, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: value, // 애니메이션이 적용된 값 사용
                          strokeWidth: 10,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeCap: StrokeCap.round, // 게이지 끝을 둥글게 처리
                        ),
                      ),
                      Text(
                        '${(value * 100).toInt()}%', // 애니메이션이 적용된 값 사용
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
              // --- 진행 메시지 ---
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
