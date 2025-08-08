// lib/game_data_model.dart

import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'PhotoItem.dart';
import 'quest_model.dart';

// 로딩 페이지에서 미리 불러와 지도 페이지로 전달할 데이터 묶음
class GameData {
  final String userId;
  final String? sessionId;
  final User? currentUser;
  final bool isGuest;
  final List<PhotoItem> touristSpotPhotos;
  final List<PhotoItem> allSeoulPhotos;
  final List<PhotoItem> keywordSearchedPhotos;
  final Map<String, Map<String, double>> placeCoords;
  final List<Map<String, dynamic>> rankings;
  final int totalScore;
  final List<dynamic> visitHistory;
  final List<Quest> quests;
  final QuestProgress? questProgress;

  GameData({
    required this.userId,
    this.sessionId,
    this.currentUser,
    required this.isGuest,
    required this.touristSpotPhotos,
    required this.allSeoulPhotos,
    required this.keywordSearchedPhotos,
    required this.placeCoords,
    required this.rankings,
    required this.totalScore,
    required this.visitHistory,
    required this.quests,
    this.questProgress,
  });
}
