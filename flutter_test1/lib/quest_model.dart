// Quest 모델: 개별 퀘스트의 정보를 담습니다.
class Quest {
  final String questId;
  final String title;
  final String description;
  final String type;
  final String status; // 'active', 'reward_ready', 'reward_claimed' [cite: 28]
  final int points;
  final List<String> completedPlaces; // 방문한 관광지 목록 [cite: 28]
  final int requiredVisits; // [cite: 28]
  final String? themeName; // 테마 미션 관련 필드 [cite: 29]
  final List<String>? targetPlaces; // 목표 관광지 목록 [cite: 30]
  final String? quizQuestion; // 퀴즈 관련 필드 [cite: 30, 31]
  final List<String>? quizOptions; // [cite: 31]
  final bool? isAnswered; // [cite: 31]
  final int currentVisitCount; // 방문 횟수 퀘스트를 위한 필드
  final bool? isCompleted; // 공유 퀘스트, 퀴즈 퀘스트 등의 완료 여부를 위한 필드 (nullable)

  Quest({
    required this.questId,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.points,
    required this.completedPlaces,
    required this.requiredVisits,
    required this.currentVisitCount,
    this.isCompleted,
    this.themeName,
    this.targetPlaces,
    this.quizQuestion,
    this.quizOptions,
    this.isAnswered,
  });

  factory Quest.fromJson(Map<String, dynamic> json) {
    return Quest(
      questId: json['quest_id'],
      title: json['title'],
      description: json['description'],
      type: json['type'],
      status: json['status'],
      points: json['points'],
      completedPlaces: List<String>.from(json['completed_places'] ?? []),
      requiredVisits: json['required_visits'] ?? 0,
      currentVisitCount: json['current_visit_count'] as int? ?? 0,
      isCompleted: json['is_completed'] as bool?,
      themeName: json['theme_name'],
      targetPlaces: json['target_places'] != null
          ? List<String>.from(json['target_places'])
          : null,
      quizQuestion: json['quiz_question'],
      quizOptions: json['quiz_options'] != null
          ? List<String>.from(json['quiz_options'])
          : null,
      isAnswered: json['is_answered'],
    );
  }
}

// QuestProgress 모델: 퀘스트 전체 진행 상황을 담습니다.
class QuestProgress {
  final int totalQuests;
  final int activeQuests; // 진행 중인 퀘스트 [cite: 32]
  final int rewardReadyQuests; // 보상 받을 준비된 퀘스트 [cite: 32, 33]
  final int claimedQuests; // 완료된 퀘스트 [cite: 33]
  final int availableReward; // 받을 수 있는 총 보상 점수 [cite: 33, 34]
  final double progressPercentage; // [cite: 34]

  QuestProgress({
    required this.totalQuests,
    required this.activeQuests,
    required this.rewardReadyQuests,
    required this.claimedQuests,
    required this.availableReward,
    required this.progressPercentage,
  });

  factory QuestProgress.fromJson(Map<String, dynamic> json) {
    return QuestProgress(
      totalQuests: json['total_quests'] ?? 0,
      activeQuests: json['active_quests'] ?? 0,
      rewardReadyQuests: json['reward_ready_quests'] ?? 0,
      claimedQuests: json['claimed_quests'] ?? 0,
      availableReward: json['available_reward'] ?? 0,
      progressPercentage: (json['progress_percentage'] ?? 0.0).toDouble(),
    );
  }
}
