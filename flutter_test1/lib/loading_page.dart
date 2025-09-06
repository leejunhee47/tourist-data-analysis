// lib/loading_page.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // [추가] compute 함수를 사용하기 위해 import
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

// --- [수정] 이미지 처리를 위한 Isolate용 최상위 함수 ---
// compute 함수는 최상위 함수 또는 static 메소드만 호출할 수 있습니다.
// 이 함수는 이제 별도의 작업 공간(Isolate)에서 실행됩니다.
Future<PhotoItem> _resizeAndEncodeIsolate(PhotoItem photo) async {
  try {
    final response = await http.get(Uri.parse(photo.galWebImageUrl));
    if (response.statusCode == 200) {
      img.Image? originalImage = img.decodeImage(response.bodyBytes);
      if (originalImage != null) {
        img.Image resizedImage = img.copyResize(originalImage, width: 200);
        Uint8List jpgBytes =
            Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
        String base64String = base64Encode(jpgBytes);
        //copyWith을 사용하여 새로운 PhotoItem 객체를 반환합니다.
        return photo.copyWith(
            base64Thumbnail: 'data:image/jpeg;base64,$base64String');
      }
    }
  } catch (e) {
    // Isolate 내에서 발생하는 오류는 메인 Isolate로 전파되지 않으므로,
    // 여기서 직접 출력하여 디버깅해야 합니다.
    debugPrint('이미지 처리 Isolate 오류 (${photo.galTitle}): $e');
  }
  // 실패 시 원본 PhotoItem을 그대로 반환합니다.
  return photo;
}

class WaveAnimationNotifier extends ChangeNotifier {
  double _phase = 0.0;
  double get phase => _phase;

  void update(Duration elapsed) {
    _phase = (elapsed.inMilliseconds / 2000) * 2 * pi;
    notifyListeners();
  }
}

class LoadingPage extends StatefulWidget {
  final User? user;
  final bool isGuest;
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

  const LoadingPage.admin({
    super.key,
    required this.adminUserId,
    required this.adminUsername,
  })  : user = null,
        isGuest = false;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  String _loadingMessage = '여행 준비를 시작합니다...';

  late final Ticker _ticker;
  final WaveAnimationNotifier _waveNotifier = WaveAnimationNotifier();

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
    _ticker = createTicker((elapsed) {
      _waveNotifier.update(elapsed);
    });
    _ticker.start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllGameData();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _waveNotifier.dispose();
    super.dispose();
  }

  void _updateProgress(double value, String message) {
    if (mounted) {
      setState(() {
        _progress = value;
        _loadingMessage = message;
      });
    }
  }

  // --- [수정] 이미지 처리 로직을 compute를 사용하도록 변경 ---
  Future<List<PhotoItem>> _processImages(List<PhotoItem> photos) async {
    List<PhotoItem> processedPhotos = [];
    int concurrentJobs = 5; // 동시에 처리할 작업 수
    List<Future<PhotoItem>> futures = [];

    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      // compute를 사용하여 _resizeAndEncodeIsolate 함수를 별도의 Isolate에서 실행합니다.
      futures.add(compute(_resizeAndEncodeIsolate, photo));

      // 동시에 처리할 작업 수가 채워지거나 마지막 사진일 경우, 모든 작업이 끝날 때까지 기다립니다.
      if (futures.length == concurrentJobs || i == photos.length - 1) {
        final results = await Future.wait(futures);
        processedPhotos.addAll(results);
        futures.clear(); // 다음 배치를 위해 리스트를 비웁니다.

        // 진행률을 업데이트합니다.
        _updateProgress(0.5 + (0.2 * (processedPhotos.length / photos.length)),
            '관광지 이미지 최적화 중... (${processedPhotos.length}/${photos.length})');
      }
    }
    return processedPhotos;
  }

  // ▼▼▼ 이 함수는 이제 사용되지 않으므로 삭제하거나 주석 처리해도 됩니다. ▼▼▼
  // Future<PhotoItem> _resizeAndEncode(PhotoItem photo) async { ... }

  // (이하 다른 함수들은 변경 사항 없음)

  Future<Map<String, String>?> _getOrCreateUser() async {
    try {
      if (widget.isGuest) {
        final response = await http.post(
          Uri.parse('$serverUrl/guest_login/'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          return {'user_id': data['user_id'], 'username': data['username']};
        }
      } else if (widget.user != null) {
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
          return {'user_id': data['user_id'], 'username': username};
        }
      }
    } catch (e) {
      debugPrint('User creation/retrieval error: $e');
    }
    return null;
  }

  Future<void> _loadAllGameData() async {
    try {
      _updateProgress(0.1, '사용자 정보 확인 중...');
      String? userId;
      String? username;
      if (widget.adminUserId != null) {
        userId = widget.adminUserId;
        username = widget.adminUsername;
      } else {
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
        username: username,
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
        quests: questData['quests'] as List<Quest>,
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
      debugPrint("데이터 로딩 중 심각한 오류 발생: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터를 불러오는데 실패했습니다: $e')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

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
      debugPrint('키워드 검색 사진 로드 오류: $e');
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
      debugPrint('User profile loading error: $e');
    }
    return {'total_score': 0, 'visit_history': []};
  }

  Future<Map<String, List<PhotoItem>>> _fetchTouristSpotPhotos() async {
    final List<PhotoItem> touristSpotPhotos = [];
    final List<PhotoItem> allSeoulPhotos = [];
    Map<String, String> localImageUrls = {};
    try {
      final response =
          await http.get(Uri.parse('$serverUrl/places/local-images'));
      if (response.statusCode == 200) {
        localImageUrls = Map<String, String>.from(
            json.decode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      debugPrint('Error fetching local image URLs: $e');
    }

    try {
      final url = Uri.parse('$baseUrl/galleryList1').replace(
        queryParameters: {
          'serviceKey': serviceKey,
          'numOfRows': '6000',
          'pageNo': '1',
          'MobileOS': 'ETC',
          'MobileApp': '픽앤트립',
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
          PhotoItem photoToAdd = foundPhotosMap[keyword]!;
          if (localImageUrls.containsKey(keyword)) {
            final localPath = localImageUrls[keyword]!;
            final finalImageUrl = '$serverUrl$localPath';
            photoToAdd = photoToAdd.copyWith(galWebImageUrl: finalImageUrl);
          }
          touristSpotPhotos.add(photoToAdd);
        }
      }
    } catch (e) {
      debugPrint('관광지 사진 로드 오류: $e');
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
      debugPrint('Place coordinates loading error: $e');
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
      debugPrint('Ranking info loading error: $e');
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
      debugPrint('Quest data loading error: $e');
    }
    // ▼▼▼ [FIX] Return a list with the explicit type <Quest> ▼▼▼
    return {'quests': <Quest>[], 'questProgress': null};
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
      debugPrint('Game session start error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // (UI 관련 코드는 변경 없음)
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
              SizedBox(
                width: 150,
                height: 150,
                child: AnimatedBuilder(
                  animation: _waveNotifier,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: WaveProgressPainter(
                        phase: _waveNotifier.phase,
                        progress: _progress,
                      ),
                      child: child,
                    );
                  },
                  child: Center(
                    child: Text(
                      '${(_progress * 100).toInt()}%',
                      style: const TextStyle(
                          fontSize: 32,
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
                  ),
                ),
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

// (WaveProgressPainter 클래스는 변경 없음)
class WaveProgressPainter extends CustomPainter {
  final double phase;
  final double progress;

  WaveProgressPainter({required this.phase, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, backgroundPaint);

    final wavePaint = Paint()..color = Colors.white.withOpacity(0.8);
    final wavePaint2 = Paint()..color = Colors.white.withOpacity(0.5);

    final path = Path();
    final path2 = Path();

    final waveHeight = (1 - progress) * size.height;

    path.moveTo(0, waveHeight);
    path2.moveTo(0, waveHeight);

    for (double i = 0; i < size.width; i++) {
      final y = sin((i / size.width * 2 * pi) + phase) * 5;
      path.lineTo(i, waveHeight + y);
      final y2 = sin((i / size.width * 2 * pi) + phase + pi) * 5;
      path2.lineTo(i, waveHeight + y2);
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();

    final circleClip = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(circleClip);

    canvas.drawPath(path2, wavePaint2);
    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
