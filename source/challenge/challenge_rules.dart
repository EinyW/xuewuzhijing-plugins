import 'dart:math';

/// 可分享的挑战规则。0 表示不限时或不限错题数。
class ChallengeRules {
  final int entryCost;
  final int timeLimitSeconds;
  final int maxMistakes;
  final double passPercent;
  final double baseMultiplier;
  final double comboBase;
  final double comboCap;
  final bool shuffle;
  final bool allowReview;
  final bool allowSkip;
  final bool showFeedback;
  final bool sessionBonus;

  const ChallengeRules({
    this.entryCost = 0,
    this.timeLimitSeconds = 0,
    this.maxMistakes = 0,
    this.passPercent = 60,
    this.baseMultiplier = 1.2,
    this.comboBase = 1.1,
    this.comboCap = 5,
    this.shuffle = true,
    this.allowReview = true,
    this.allowSkip = true,
    this.showFeedback = true,
    this.sessionBonus = true,
  });

  double comboMultiplier(int combo) {
    if (combo <= 0 || comboBase == 1 || comboCap == 1) return 1;
    // 在计算双指数之前判断封顶，避免大连击产生无穷值。
    final exponent = pow(comboBase, combo).toDouble();
    if (!exponent.isFinite || exponent * log(comboBase) >= log(comboCap)) {
      return comboCap;
    }
    return min(comboCap, pow(comboBase, exponent).toDouble());
  }

  double scorePercent(Iterable<double> scores, Iterable<double> totals) {
    final total = totals.fold<double>(0, (sum, n) => sum + n);
    if (total <= 0) return 0;
    return (scores.fold<double>(0, (sum, n) => sum + n) / total * 100).clamp(
      0,
      100,
    );
  }

  bool passed({
    required double percent,
    required int mistakes,
    bool timedOut = false,
  }) =>
      !timedOut &&
      percent >= passPercent &&
      (maxMistakes == 0 || mistakes < maxMistakes);

  Map<String, dynamic> toJson() => {
    'entryCost': entryCost,
    'timeLimitSeconds': timeLimitSeconds,
    'maxMistakes': maxMistakes,
    'passPercent': passPercent,
    'baseMultiplier': baseMultiplier,
    'comboBase': comboBase,
    'comboCap': comboCap,
    'shuffle': shuffle,
    'allowReview': allowReview,
    'allowSkip': allowSkip,
    'showFeedback': showFeedback,
    'sessionBonus': sessionBonus,
  };

  factory ChallengeRules.fromJson(Map<String, dynamic> json) {
    final defaults = const ChallengeRules().toJson();
    final values = {...defaults, ...json};
    int integer(String key, int max) {
      final value = values[key];
      if (value is! int || value < 0 || value > max) {
        throw FormatException('$key 必须为 0–$max 的整数');
      }
      return value;
    }

    double number(String key, double min, double max) {
      final value = values[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('$key 必须在 $min–$max 之间');
      }
      return value.toDouble();
    }

    bool flag(String key) {
      if (values[key] is! bool) throw FormatException('$key 必须为布尔值');
      return values[key] as bool;
    }

    return ChallengeRules(
      entryCost: integer('entryCost', 100000000),
      timeLimitSeconds: integer('timeLimitSeconds', 604800),
      maxMistakes: integer('maxMistakes', 10000),
      passPercent: number('passPercent', 0, 100),
      baseMultiplier: number('baseMultiplier', 0, 100),
      comboBase: number('comboBase', 1, 10),
      comboCap: number('comboCap', 1, 100),
      shuffle: flag('shuffle'),
      allowReview: flag('allowReview'),
      allowSkip: flag('allowSkip'),
      showFeedback: flag('showFeedback'),
      sessionBonus: flag('sessionBonus'),
    );
  }
}
