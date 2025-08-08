// review_model.dart (가상 경로)

class UserInfo {
  final String username;
  final String? profileImageUrl;

  UserInfo({required this.username, this.profileImageUrl});

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      username: json['username'] as String,
      profileImageUrl: json['profile_image_url'] as String?,
    );
  }
}

class Review {
  final String reviewId;
  final String userId;
  final String placeName;
  final String reviewText;
  final String? imageUrl;
  final String createdAt;
  final int scoreEarned;
  final UserInfo userInfo; // [추가]

  Review({
    required this.reviewId,
    required this.userId,
    required this.placeName,
    required this.reviewText,
    this.imageUrl,
    required this.createdAt,
    required this.scoreEarned,
    required this.userInfo, // [추가]
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      reviewId: json['review_id'] as String,
      userId: json['user_id'] as String,
      placeName: json['place_name'] as String,
      reviewText: json['review_text'] as String,
      imageUrl: json['image_url'] as String?,
      createdAt: json['created_at'] as String,
      scoreEarned: json['score_earned'] as int,
      // [수정] user_info 필드를 파싱하도록 수정
      userInfo: UserInfo.fromJson(json['user_info']),
    );
  }
}
