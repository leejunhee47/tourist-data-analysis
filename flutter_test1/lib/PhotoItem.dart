import 'package:xml/xml.dart';

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
  String? base64Thumbnail;

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
    this.base64Thumbnail,
  });

  factory PhotoItem.empty() {
    return PhotoItem(
        galContentId: '',
        galTitle: '',
        galWebImageUrl: '',
        galCreatedtime: '',
        galModifiedtime: '',
        galPhotographyMonth: '',
        galPhotographyLocation: '',
        galPhotographer: '',
        galSearchKeyword: '',
        base64Thumbnail: null);
  }

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

  PhotoItem copyWith({
    String? galContentId,
    String? galTitle,
    String? galWebImageUrl,
    String? galCreatedtime,
    String? galModifiedtime,
    String? galPhotographyMonth,
    String? galPhotographyLocation,
    String? galPhotographer,
    String? galSearchKeyword,
    String? base64Thumbnail, // [수정] 함수에 파라미터 추가
  }) {
    return PhotoItem(
      galContentId: galContentId ?? this.galContentId,
      galTitle: galTitle ?? this.galTitle,
      galWebImageUrl: galWebImageUrl ?? this.galWebImageUrl,
      galCreatedtime: galCreatedtime ?? this.galCreatedtime,
      galModifiedtime: galModifiedtime ?? this.galModifiedtime,
      galPhotographyMonth: galPhotographyMonth ?? this.galPhotographyMonth,
      galPhotographyLocation:
          galPhotographyLocation ?? this.galPhotographyLocation,
      galPhotographer: galPhotographer ?? this.galPhotographer,
      galSearchKeyword: galSearchKeyword ?? this.galSearchKeyword,
      base64Thumbnail:
          base64Thumbnail ?? this.base64Thumbnail, // [수정] 객체 생성 시 값 전달
    );
  }
}
