// main_page.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'KakaoMapPage.dart';
import 'PhotoItem.dart';

class MainPage extends StatefulWidget {
  final User? user; // 카카오 User 객체를 nullable로 변경
  final bool isGuest; // 게스트 여부를 확인하는 플래그 추가

  // 기존 사용자를 위한 생성자
  const MainPage({super.key, required this.user}) : isGuest = false;

  // 게스트 사용자를 위한 이름 있는 생성자 추가
  const MainPage.guest({super.key}) : user = null, isGuest = true;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isLoading = false;
  final List<PhotoItem> _touristSpotPhotos = [];
  final String baseUrl = 'https://apis.data.go.kr/B551011/PhotoGalleryService1';
  final String serviceKey =
      'AzjIKOxRyY9dTdGHXgvr0WkT9dlnEnpSdLz5+UHvMIm/PhztPInz9ePGb5FS+sHdAVH3GEfFqHEh/oW54s1A1A==';
  final String serverUrl = 'https://tourist-app-783243215272.asia-northeast3.run.app';
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
  List<Map<String, dynamic>> _rankings = [];

  String? _userId;
  int _totalScore = 0;
  bool _isProfileLoading = true;
  List<dynamic> _visitHistory = [];
  Map<String, Map<String, double>> _placeCoords = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _fetchRankings();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isProfileLoading = true;
    });

    final userId = await _getOrCreateUser();
    if (userId != null && mounted) {
      setState(() {
        _userId = userId;
      });
      await _fetchUserProfile(userId);
      await _fetchTouristSpotPhotos();
      await _fetchPlaceCoordinates();
    }

    if (mounted) {
      setState(() {
        _isProfileLoading = false;
      });
    }
  }

  Future<void> _fetchPlaceCoordinates() async {
    try {
      final url = Uri.parse('$serverUrl/places/');
      final response = await http.get(url);

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

        if (mounted) {
          setState(() {
            _placeCoords = coords;
          });
          print("✅ 서버로부터 관광지 좌표 로딩 성공!");
        }
      } else {
        print('🚨 관광지 좌표 로딩 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('🚨 관광지 좌표 로딩 오류: $e');
    }
  }

  Future<void> _fetchUserProfile(String userId) async {
    try {
      final url = Uri.parse('$serverUrl/user_profile/$userId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _totalScore = data['total_score'];
            _visitHistory = data['visit_history'];
          });
        }
      } else {
        print('사용자 프로필 로드 실패: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자 점수를 불러오는 데 실패했습니다.')),
          );
        }
      }
    } catch (e) {
      print('사용자 프로필 로드 오류: $e');
    }
  }

  Future<void> _fetchRankings() async {
    try {
      final url = Uri.parse('$serverUrl/rankings/');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _rankings = List<Map<String, dynamic>>.from(data['rankings']);
          });
        }
      } else {
        throw Exception('Failed to load rankings: ${response.statusCode}');
      }
    } catch (e) {
      print('랭킹 정보 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('랭킹 정보를 불러오는 데 실패했습니다: $e')));
      }
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
                      final rank = rankData['rank'];
                      final username = rankData['username'];
                      final score = rankData['total_score'];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 2,
                        child: ListTile(
                          leading: Text(
                            '$rank',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: rank == 1
                                  ? Colors.amber.shade700
                                  : rank == 2
                                  ? Colors.grey.shade600
                                  : rank == 3
                                  ? Colors.brown.shade400
                                  : Colors.black,
                            ),
                          ),
                          title: Text(
                            username,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          trailing: Text(
                            '$score점',
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

  Future<String?> _getOrCreateUser() async {
    // 위젯의 isGuest 플래그를 확인하여 사용자 이름을 결정합니다.
    final String? username = widget.isGuest
        ? "게스트유저"
        : widget.user?.kakaoAccount?.profile?.nickname;
    if (username == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사용자 이름을 가져올 수 없습니다.')));
      }
      return null;
    }

    try {
      final url = Uri.parse('$serverUrl/create_user/');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username}), // "게스트유저" 또는 카카오 닉네임 전송
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final userId = data['user_id'];
        print('사용자 생성 또는 조회 성공: $userId');
        return userId;
      } else {
        throw Exception('Failed to get or create user: ${response.statusCode}');
      }
    } catch (e) {
      print('사용자 생성/가져오기 오류: $e');
      return null;
    }
  }
  // ▲▲▲ 수정된 부분 ▲▲▲

  Future<String?> _startGameSession(String userId, List<String> targets) async {
    try {
      final url = Uri.parse('$serverUrl/start_game/');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId, 'target_places': targets}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        print('게임 세션 시작 성공: ${data['session_id']}');
        return data['session_id'];
      } else {
        throw Exception('Failed to start game session: ${response.statusCode}');
      }
    } catch (e) {
      print('게임 세션 시작 오류: $e');
      return null;
    }
  }

  Future<void> _fetchTouristSpotPhotos() async {
    try {
      final url = Uri.parse('$baseUrl/galleryList1').replace(
        queryParameters: {
          'serviceKey': serviceKey,
          'numOfRows': '1000000',
          'pageNo': '1',
          'MobileOS': 'ETC',
          'MobileApp': 'AppTest',
          'arrange': 'A',
          '_type': 'json',
        },
      );
      final response = await http.get(url);

      List<PhotoItem> allPhotos = [];
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['response']['body']['items']['item'];
        if (items is List) {
          allPhotos = items.map((item) => PhotoItem.fromJson(item)).toList();
        }
      } else {
        throw Exception('Failed to load photos from public API');
      }

      List<PhotoItem> seoulPhotos = allPhotos.where((photo) {
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

      _touristSpotPhotos.clear();
      for (var keyword in targetKeywords) {
        if (foundPhotosMap.containsKey(keyword)) {
          _touristSpotPhotos.add(foundPhotosMap[keyword]!);
        }
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

  Future<void> _initializeGameAndNavigate() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final String? userId = _userId;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      if (_touristSpotPhotos.isEmpty) {
        await _fetchTouristSpotPhotos();
        if (_touristSpotPhotos.isEmpty) {
          throw Exception("관광지 사진을 불러올 수 없습니다. 게임을 시작할 수 없습니다.");
        }
      }

      final String? sessionId = await _startGameSession(userId, targetKeywords);
      if (sessionId == null) {
        throw Exception("게임 세션을 시작할 수 없습니다.");
      }

      if (mounted) {
        print("게임 시작 전 현재 점수: $_totalScore");
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => KakaoMapPage(
              user: widget.user,
              photos: _touristSpotPhotos,
              sessionId: sessionId,
              placeCoords: _placeCoords,
            ),
          ),
        );
        print("지도 페이지에서 복귀. 사용자 프로필(점수)을 새로고침합니다.");
        await Future.delayed(const Duration(milliseconds: 500));
        await _fetchUserProfile(userId);

        print("점수 업데이트 완료: $_totalScore");
        await _fetchRankings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('현재 총 점수: $_totalScore점'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('게임 시작 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('게임 데이터를 불러오는 데 실패했습니다: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // New method to show the collection book dialog
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
            height:
                MediaQuery.of(context).size.height *
                0.4, // Adjust height as needed
            child: _touristSpotPhotos.isEmpty
                ? const Center(child: Text('수집할 관광지 사진이 없습니다.'))
                : Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: (_touristSpotPhotos.length / 4)
                              .ceil(), // 4 images per page
                          itemBuilder: (context, pageIndex) {
                            final int startIndex = pageIndex * 4;
                            final int endIndex = (startIndex + 4).clamp(
                              0,
                              _touristSpotPhotos.length,
                            );
                            final List<PhotoItem> currentPagePhotos =
                                _touristSpotPhotos.sublist(
                                  startIndex,
                                  endIndex,
                                );
                            return GridView.builder(
                              physics:
                                  const NeverScrollableScrollPhysics(), // Disable inner scrolling
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2, // Two columns
                                    childAspectRatio: 1.0, // Square items
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: currentPagePhotos.length,
                              itemBuilder: (context, index) {
                                final photo = currentPagePhotos[index];
                                final bool isVisited = _visitHistory.any(
                                  (visit) =>
                                      visit['target_place'] == photo.galTitle &&
                                      visit['is_correct'],
                                );

                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ColorFiltered(
                                          colorFilter: isVisited
                                              ? const ColorFilter.mode(
                                                  Colors.transparent,
                                                  BlendMode.multiply,
                                                )
                                              : const ColorFilter.matrix(
                                                  <double>[
                                                    0.2126,
                                                    0.7152,
                                                    0.0722,
                                                    0,
                                                    0, // Red
                                                    0.2126,
                                                    0.7152,
                                                    0.0722,
                                                    0,
                                                    0, // Green
                                                    0.2126,
                                                    0.7152,
                                                    0.0722,
                                                    0,
                                                    0, // Blue
                                                    0, 0, 0, 1, 0, // Alpha
                                                  ],
                                                ),
                                          child: Image.network(
                                            photo.galWebImageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
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
                                          maxLines: 2,
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
                      // Page indicators
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

  // Helper for page indicator dots
  Widget buildDot(int index, PageController pageController) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double selectedness = 0.0;
        // 컨트롤러가 클라이언트에 연결되어 있고, 페이지 값이 null이 아닌 경우에만 계산
        if (pageController.hasClients && pageController.page != null) {
          selectedness =
              1 - (pageController.page! - index).abs(); // !를 사용하여 null 아님을 명시
        }
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

  @override
  Widget build(BuildContext context) {
    // isGuest 플래그에 따라 닉네임과 프로필 이미지 URL을 설정합니다.
    String? nickname = widget.isGuest
        ? '게스트'
        : widget.user?.kakaoAccount?.profile?.nickname;
    String? profileImageUrl = widget.isGuest
        ? null
        : widget.user?.kakaoAccount?.profile?.profileImageUrl;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (profileImageUrl != null)
              CircleAvatar(
                backgroundImage: NetworkImage(profileImageUrl),
                radius: 20,
              )
            else
              const CircleAvatar(radius: 20, child: Icon(Icons.person)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    nickname ?? '사용자',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _isProfileLoading
                      ? const Text(
                          '점수 불러오는 중...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      : Text(
                          '점수: $_totalScore점',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.book_outlined), // Collection book icon
            tooltip: '컬렉션 북 보기',
            onPressed: _showCollectionBookDialog, // Call the new method
          ),
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined),
            tooltip: '랭킹 보기',
            onPressed: _showRankingDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "서울 명소 인증 투어",
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "지도를 통해 서울의 아름다운 명소를 방문하고 인증하세요!",
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _initializeGameAndNavigate,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('지도로 서울 관광지 보기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '게임 세션을 준비하는 중입니다...',
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
