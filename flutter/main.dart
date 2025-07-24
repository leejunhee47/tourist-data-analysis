import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:xml/xml.dart';
import 'KakaoMapPage.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '서울 관광사진',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PhotoGalleryPage(),
    );
  }
}

class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});

  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  List<PhotoItem> photos = [];
  bool isLoading = false;
  bool hasMoreData = true;
  int currentPage = 1;
  final int numOfRows = 5000;

  // API 정보
  final String baseUrl = 'https://apis.data.go.kr/B551011/PhotoGalleryService1';
  final String serviceKey =
      'AzjIKOxRyY9dTdGHXgvr0WkT9dlnEnpSdLz5+UHvMIm/PhztPInz9ePGb5FS+sHdAVH3GEfFqHEh/oW54s1A1A==';

  @override
  void initState() {
    super.initState();
    fetchPhotos();
  }

  Future<void> fetchPhotos({bool isRefresh = false}) async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      if (isRefresh) {
        currentPage = 1;
        photos.clear();
        hasMoreData = true;
      }
    });

    try {
      final url = Uri.parse('$baseUrl/galleryList1').replace(
        queryParameters: {
          'serviceKey': serviceKey,
          'numOfRows': numOfRows.toString(),
          'pageNo': currentPage.toString(),
          'MobileOS': 'ETC',
          'MobileApp': 'AppTest',
          'arrange': 'A',
          '_type': 'json',
        },
      );

      print('API 호출 URL: $url'); // 디버그용

      final response = await http.get(url);

      print('응답 상태코드: ${response.statusCode}'); // 디버그용
      print(
        '응답 내용 (처음 200자): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
      ); // 디버그용

      if (response.statusCode == 200) {
        List<PhotoItem> newPhotos = [];

        // JSON 응답인지 XML 응답인지 확인
        final responseBody = response.body.trim();

        if (responseBody.startsWith('{') || responseBody.startsWith('[')) {
          // JSON 응답 처리
          try {
            final data = json.decode(responseBody);
            print('JSON 데이터 구조: ${data.keys}'); // 디버그용

            // API 응답 구조 확인
            if (data['response'] != null &&
                data['response']['body'] != null &&
                data['response']['body']['items'] != null) {
              final items = data['response']['body']['items']['item'];
              print(
                '아이템 개수: ${items is List ? items.length : (items != null ? 1 : 0)}',
              ); // 디버그용

              if (items != null) {
                List<PhotoItem> allPhotos = [];
                if (items is List) {
                  allPhotos = items
                      .map((item) => PhotoItem.fromJson(item))
                      .toList();
                } else {
                  // 단일 아이템인 경우
                  allPhotos = [PhotoItem.fromJson(items)];
                }

                // 디버그: 실제 데이터 확인
                print('=== 실제 사진 데이터 샘플 (처음 3개) ===');
                for (
                  int i = 0;
                  i < (allPhotos.length > 3 ? 3 : allPhotos.length);
                  i++
                ) {
                  final photo = allPhotos[i];
                  print('제목: ${photo.galTitle}');
                  print('위치: ${photo.galPhotographyLocation}');
                  print('키워드: ${photo.galSearchKeyword}');
                  print('---');
                }

                // 서울특별시 사진만 필터링
                newPhotos = allPhotos.where((photo) {
                  final title = photo.galTitle.toLowerCase();
                  final location = photo.galPhotographyLocation.toLowerCase();
                  final keyword = photo.galSearchKeyword.toLowerCase();

                  final isSeoulPhoto =
                      location.contains('서울특별시') ||
                      location.contains('서울시') ||
                      location.contains('서울') ||
                      title.contains('서울') ||
                      keyword.contains('서울') ||
                      title.contains('seoul') ||
                      location.contains('seoul') ||
                      keyword.contains('seoul');

                  // 디버그: 서울 사진 발견 시 로그
                  if (isSeoulPhoto) {
                    print(
                      '서울 사진 발견: ${photo.galTitle} - ${photo.galPhotographyLocation}',
                    );
                  }

                  return isSeoulPhoto;
                }).toList();

                print('필터링된 서울 사진 개수: ${newPhotos.length}'); // 디버그용
              }
            } else if (data['resultCode'] != null &&
                data['resultCode'] != '0000') {
              // API 에러 응답 처리
              print('API 에러: ${data['resultMsg']}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('API 에러: ${data['resultMsg']}')),
              );
            } else if (data['response'] != null &&
                data['response']['body'] != null &&
                data['response']['body']['items'] == '') {
              // 빈 결과 처리
              print('더 이상 데이터가 없습니다.');
              hasMoreData = false;
            } else {
              print('예상하지 못한 JSON 구조: $data');
            }
          } catch (e) {
            print('JSON 파싱 에러: $e');
          }
        } else if (responseBody.startsWith('<')) {
          // XML 응답 처리
          try {
            final document = XmlDocument.parse(responseBody);
            final items = document.findAllElements('item');
            print('XML 아이템 개수: ${items.length}'); // 디버그용

            List<PhotoItem> allPhotos = items.map((item) {
              return PhotoItem.fromXml(item);
            }).toList();

            // 서울특별시 사진만 필터링
            newPhotos = allPhotos.where((photo) {
              final title = photo.galTitle.toLowerCase();
              final location = photo.galPhotographyLocation.toLowerCase();
              final keyword = photo.galSearchKeyword.toLowerCase();

              return location.contains('서울특별시') ||
                  location.contains('서울시') ||
                  location.contains('서울') ||
                  title.contains('서울') ||
                  keyword.contains('서울') ||
                  title.contains('seoul') ||
                  location.contains('seoul') ||
                  keyword.contains('seoul');
            }).toList();

            print('필터링된 서울 사진 개수: ${newPhotos.length}'); // 디버그용
          } catch (e) {
            print('XML 파싱 에러: $e');
          }
        } else {
          print('알 수 없는 응답 형식: ${responseBody.substring(0, 100)}');
        }

        setState(() {
          if (newPhotos.isEmpty) {
            hasMoreData = false;
          } else {
            if (isRefresh) {
              photos = newPhotos;
            } else {
              photos.addAll(newPhotos);
            }
            currentPage++;
          }
        });

        print('현재 사진 개수: ${photos.length}'); // 디버그용
      } else {
        print('HTTP 에러: ${response.statusCode}, 응답: ${response.body}');
        throw Exception('Failed to load photos: ${response.statusCode}');
      }
    } catch (e) {
      print('API 호출 에러: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사진을 불러오는데 실패했습니다: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('서울 관광사진'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      KakaoMapPage(photos: photos), // photos 데이터 전달
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : () => fetchPhotos(isRefresh: true),
          ),
        ],
      ),
      body: photos.isEmpty && !isLoading
          ? const Center(
              child: Text(
                '사진을 불러올 수 없습니다.\n새로고침을 눌러주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (!isLoading &&
                    hasMoreData &&
                    scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200) {
                  fetchPhotos();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: photos.length + (isLoading ? 4 : 0),
                itemBuilder: (context, index) {
                  if (index >= photos.length) {
                    return const Card(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final photo = photos[index];
                  return GestureDetector(
                    onTap: () => _showPhotoDetail(photo),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: Image.network(
                                photo.galWebImageUrl,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: const Center(
                                      child: Icon(
                                        Icons.image_not_supported,
                                        color: Colors.grey,
                                        size: 50,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  photo.galTitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  photo.galPhotographer,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showPhotoDetail(PhotoItem photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(
                  photo.galTitle,
                  style: const TextStyle(fontSize: 16),
                ),
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
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 50,
                              ),
                            ),
                          );
                        },
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
                            Text('촬영자: ${photo.galPhotographer}'),
                            const SizedBox(height: 4),
                            Text('촬영일: ${photo.galPhotographyMonth}'),
                            const SizedBox(height: 4),
                            Text('위치: ${photo.galPhotographyLocation}'),
                            const SizedBox(height: 8),
                            if (photo.galSearchKeyword.isNotEmpty)
                              Text(
                                '키워드: ${photo.galSearchKeyword}',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontSize: 12,
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
}

class PhotoItem {
  final String galContentId;
  final String galTitle;
  final String galWebImageUrl;
  final String galCreatedtime;
  final String galModifiedtime;
  final String galPhotographyMonth;
  final String galPhotographyLocation;
  final String galPhotographer;
  final String galSearchKeyword;

  PhotoItem({
    required this.galContentId,
    required this.galTitle,
    required this.galWebImageUrl,
    required this.galCreatedtime,
    required this.galModifiedtime,
    required this.galPhotographyMonth,
    required this.galPhotographyLocation,
    required this.galPhotographer,
    required this.galSearchKeyword,
  });

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      galContentId: json['galContentId']?.toString() ?? '',
      galTitle: json['galTitle']?.toString() ?? '제목 없음',
      galWebImageUrl: json['galWebImageUrl']?.toString() ?? '',
      galCreatedtime: json['galCreatedtime']?.toString() ?? '',
      galModifiedtime: json['galModifiedtime']?.toString() ?? '',
      galPhotographyMonth: json['galPhotographyMonth']?.toString() ?? '',
      galPhotographyLocation: json['galPhotographyLocation']?.toString() ?? '',
      galPhotographer: json['galPhotographer']?.toString() ?? '촬영자 미상',
      galSearchKeyword: json['galSearchKeyword']?.toString() ?? '',
    );
  }

  factory PhotoItem.fromXml(XmlElement xml) {
    return PhotoItem(
      galContentId: xml.findElements('galContentId').first.innerText,
      galTitle: xml.findElements('galTitle').isNotEmpty
          ? xml.findElements('galTitle').first.innerText
          : '제목 없음',
      galWebImageUrl: xml.findElements('galWebImageUrl').isNotEmpty
          ? xml.findElements('galWebImageUrl').first.innerText
          : '',
      galCreatedtime: xml.findElements('galCreatedtime').isNotEmpty
          ? xml.findElements('galCreatedtime').first.innerText
          : '',
      galModifiedtime: xml.findElements('galModifiedtime').isNotEmpty
          ? xml.findElements('galModifiedtime').first.innerText
          : '',
      galPhotographyMonth: xml.findElements('galPhotographyMonth').isNotEmpty
          ? xml.findElements('galPhotographyMonth').first.innerText
          : '',
      galPhotographyLocation:
          xml.findElements('galPhotographyLocation').isNotEmpty
          ? xml.findElements('galPhotographyLocation').first.innerText
          : '',
      galPhotographer: xml.findElements('galPhotographer').isNotEmpty
          ? xml.findElements('galPhotographer').first.innerText
          : '촬영자 미상',
      galSearchKeyword: xml.findElements('galSearchKeyword').isNotEmpty
          ? xml.findElements('galSearchKeyword').first.innerText
          : '',
    );
  }
}
