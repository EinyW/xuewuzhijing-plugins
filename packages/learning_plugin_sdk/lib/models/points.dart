/// 一次积分获得的记录
class PointsEvent {
  final int? id;
  final int? questionId;
  final String? questionType;

  /// answer = 答题得分，session = 整局奖励
  final String eventType;

  /// 展示名，例如「首杀 · 连击×5」
  final String label;

  /// 基础分（按题型）
  final int basePoints;

  /// 倍率（连击、速度等叠加后的总倍率）
  final double multiplier;

  /// 额外加分（复仇、完美一局等固定奖励）
  final int bonusPoints;

  /// 最终得分
  final int points;

  /// 当时的连击数
  final int combo;

  /// 作答耗时（毫秒）
  final int elapsedMs;

  final String? sessionId;

  /// yyyy-MM-dd，便于按天聚合
  final String dayKey;

  final String createdAt;

  const PointsEvent({
    this.id,
    this.questionId,
    this.questionType,
    this.eventType = 'answer',
    required this.label,
    this.basePoints = 0,
    this.multiplier = 1,
    this.bonusPoints = 0,
    required this.points,
    this.combo = 0,
    this.elapsedMs = 0,
    this.sessionId,
    required this.dayKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': 1,
        'question_id': questionId,
        'question_type': questionType,
        'event_type': eventType,
        'label': label,
        'base_points': basePoints,
        'multiplier': multiplier,
        'bonus_points': bonusPoints,
        'points': points,
        'combo': combo,
        'elapsed_ms': elapsedMs,
        'session_id': sessionId,
        'day_key': dayKey,
        'created_at': createdAt,
      };

  factory PointsEvent.fromMap(Map<String, dynamic> m) => PointsEvent(
        id: m['id'] as int?,
        questionId: m['question_id'] as int?,
        questionType: m['question_type'] as String?,
        eventType: (m['event_type'] as String?) ?? 'answer',
        label: m['label'] as String,
        basePoints: (m['base_points'] as int?) ?? 0,
        multiplier: ((m['multiplier'] as num?) ?? 1).toDouble(),
        bonusPoints: (m['bonus_points'] as int?) ?? 0,
        points: (m['points'] as int?) ?? 0,
        combo: (m['combo'] as int?) ?? 0,
        elapsedMs: (m['elapsed_ms'] as int?) ?? 0,
        sessionId: m['session_id'] as String?,
        dayKey: m['day_key'] as String,
        createdAt: m['created_at'] as String,
      );
}

/// 一条得分规则命中
class PointsHit {
  final String label;
  final double multiplier;
  final int bonus;

  const PointsHit({
    required this.label,
    this.multiplier = 1,
    this.bonus = 0,
  });

  bool get hasMultiplier => multiplier > 1.0;
  bool get hasBonus => bonus > 0;
}

/// 判分后算出的积分明细
class PointsAward {
  final int points;
  final int basePoints;
  final double multiplier;
  final int bonusPoints;
  final List<PointsHit> hits;

  /// 写库后返回的完整事件
  PointsEvent? event;

  PointsAward({
    required this.points,
    required this.basePoints,
    required this.multiplier,
    required this.bonusPoints,
    required this.hits,
  });

  /// 简短说明，用于答题页浮层
  String get summary {
    if (hits.isEmpty) return '+$points';
    return '+$points（${hits.map((h) => h.label).join(' · ')}）';
  }

  bool get isEmpty => points <= 0;
}

/// 每天/每月的汇总
class PointsBucket {
  final String key;
  final int points;
  final int count;

  const PointsBucket({
    required this.key,
    required this.points,
    this.count = 0,
  });
}

/// 目标分数
class PointsGoal {
  final int? id;
  final int target;
  final String? title;

  /// 0 = 累计目标（老模式）；>0 = 每 N 天一个周期
  final int periodDays;

  final String createdAt;
  final String? achievedAt;

  const PointsGoal({
    this.id,
    required this.target,
    this.title,
    this.periodDays = 0,
    required this.createdAt,
    this.achievedAt,
  });

  bool get achieved => achievedAt != null;

  bool get isPeriodic => periodDays > 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'target': target,
        'title': title,
        'period_days': periodDays,
        'created_at': createdAt,
        'achieved_at': achievedAt,
      };

  factory PointsGoal.fromMap(Map<String, dynamic> m) => PointsGoal(
        id: m['id'] as int?,
        target: m['target'] as int,
        title: m['title'] as String?,
        periodDays: (m['period_days'] as int?) ?? 0,
        createdAt: m['created_at'] as String,
        achievedAt: m['achieved_at'] as String?,
      );
}

/// 周期目标的当前进度
class GoalCycleProgress {
  /// 当前是第几个周期（从 1 开始）
  final int cycleIndex;

  /// 本周期已获得积分
  final int earned;

  /// 每周期目标
  final int target;

  final DateTime start;
  final DateTime end;

  /// 已经达成目标的周期数
  final int completedCycles;

  const GoalCycleProgress({
    required this.cycleIndex,
    required this.earned,
    required this.target,
    required this.start,
    required this.end,
    required this.completedCycles,
  });

  double get ratio =>
      target <= 0 ? 0 : (earned / target).clamp(0.0, 1.0);

  bool get achieved => earned >= target;

  /// 本周期剩余天数
  int get daysLeft {
    final left = end.difference(DateTime.now()).inSeconds;
    return left <= 0 ? 0 : (left / 86400).ceil();
  }
}

/// 段位：根据累计积分给一个称号，纯本地展示
class PointsRank {
  final String name;
  final int min;

  /// 下一段位所需积分；null 表示已到顶
  final int? nextAt;

  const PointsRank({required this.name, required this.min, this.nextAt});

  static const List<PointsRank> ranks = [
    PointsRank(name: '启程', min: 0, nextAt: 1000),
    PointsRank(name: '青铜', min: 1000, nextAt: 3000),
    PointsRank(name: '白银', min: 3000, nextAt: 6000),
    PointsRank(name: '黄金', min: 6000, nextAt: 12000),
    PointsRank(name: '铂金', min: 12000, nextAt: 20000),
    PointsRank(name: '钻石', min: 20000, nextAt: 35000),
    PointsRank(name: '大师', min: 35000, nextAt: 60000),
    PointsRank(name: '宗师', min: 60000, nextAt: 100000),
    PointsRank(name: '王者', min: 100000),
  ];

  static PointsRank of(int total) {
    PointsRank result = ranks.first;
    for (final r in ranks) {
      if (total >= r.min) result = r;
    }
    return result;
  }

  /// 到下一段位的进度（0~1），满级返回 1
  static double progress(int total, PointsRank rank) {
    if (rank.nextAt == null) return 1;
    final span = rank.nextAt! - rank.min;
    if (span <= 0) return 1;
    final done = (total - rank.min) / span;
    return done.clamp(0.0, 1.0);
  }
}
