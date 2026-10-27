import 'question.dart';

/// 可分享的积分方案。文件只保存规则与外观，不包含题库或学习记录。
class ScoringProfile {
  final String name;
  final double multiplier;
  final int questionCap;
  final Map<String, (int, int)> baseRanges;
  final List<ScoringRule> rules;
  final int colorValue;
  final double fontSize;
  final double detailFontSize;
  final int displayMs;
  final bool showPopup;
  final int sessionMinimum;
  final int sessionBonus;
  final int sessionPerQuestion;
  final String sessionLabel;

  const ScoringProfile({
    this.name = '经典花样积分',
    this.multiplier = 1,
    this.questionCap = 200000,
    this.baseRanges = defaultRanges,
    this.rules = defaultRules,
    this.colorValue = 0xFFFFB74D,
    this.fontSize = 30,
    this.detailFontSize = 12,
    this.displayMs = 2400,
    this.showPopup = true,
    this.sessionMinimum = 3,
    this.sessionBonus = 300,
    this.sessionPerQuestion = 50,
    this.sessionLabel = '完美一局',
  });

  static const defaultRanges = <String, (int, int)>{
    'choice': (50, 100),
    'multi_choice': (100, 130),
    'fill_blank': (100, 180),
    'long_text': (550, 1550),
    'material': (2000, 4000),
    'word': (10, 15),
  };

  static const rangeNames = <String, String>{
    'choice': '选择题',
    'multi_choice': '多选题',
    'fill_blank': '填空题',
    'long_text': '长文本题',
    'material': '材料题',
    'word': '词语测试',
  };

  static const defaultRules = <ScoringRule>[
    ScoringRule(id: 'perfect', name: '满血通关', multiplier: 1.2, minRatio: .999),
    ScoringRule(id: 'lucky', name: '幸运暴击', multiplier: 1.3, highRoll: true),
    ScoringRule(id: 'first', name: '首杀', multiplier: 2, firstAttemptOnly: true),
    ScoringRule(
      id: 'revenge',
      name: '复仇',
      bonus: 200,
      previouslyWrongOnly: true,
    ),
    ScoringRule(
      id: 'combo20',
      name: '大杀特杀',
      multiplier: 4,
      minCombo: 20,
      group: 'combo',
    ),
    ScoringRule(
      id: 'combo15',
      name: '超神',
      multiplier: 3.5,
      minCombo: 15,
      group: 'combo',
    ),
    ScoringRule(
      id: 'combo12',
      name: '连击×12',
      multiplier: 3,
      minCombo: 12,
      group: 'combo',
    ),
    ScoringRule(
      id: 'combo8',
      name: '连击×8',
      multiplier: 2.5,
      minCombo: 8,
      group: 'combo',
    ),
    ScoringRule(
      id: 'combo5',
      name: '连击×5',
      multiplier: 2,
      minCombo: 5,
      group: 'combo',
    ),
    ScoringRule(
      id: 'combo3',
      name: '连击×3',
      multiplier: 1.5,
      minCombo: 3,
      group: 'combo',
    ),
    ScoringRule(
      id: 'speed5',
      name: '闪电秒杀',
      multiplier: 2.5,
      maxElapsedMs: 5000,
      group: 'speed',
    ),
    ScoringRule(
      id: 'oneShot',
      name: '一击必杀',
      multiplier: 1.5,
      maxElapsedMs: 5000,
      firstAttemptOnly: true,
      minRatio: .999,
    ),
    ScoringRule(
      id: 'speed10',
      name: '快速反应',
      multiplier: 1.5,
      maxElapsedMs: 10000,
      group: 'speed',
    ),
    ScoringRule(
      id: 'speed20',
      name: '稳准快',
      multiplier: 1.2,
      maxElapsedMs: 20000,
      group: 'speed',
    ),
    ScoringRule(
      id: 'lightningCombo',
      name: '闪电连击',
      multiplier: 1.3,
      minCombo: 5,
      maxElapsedMs: 5000,
    ),
    ScoringRule(
      id: 'multiPerfect',
      name: '全中',
      multiplier: 1.5,
      questionType: 'multi_choice',
      minRatio: .999,
    ),
    ScoringRule(
      id: 'materialMaster',
      name: '材料大师',
      multiplier: 1.5,
      materialOnly: true,
      minRatio: .999,
    ),
    ScoringRule(
      id: 'materialFast',
      name: '材料终结者',
      multiplier: 1.5,
      materialOnly: true,
      minRatio: .999,
      maxElapsedMs: 15000,
    ),
    ScoringRule(
      id: 'longHigh',
      name: '高分作答',
      multiplier: 1.5,
      questionType: 'long_text',
      excludeMaterial: true,
      minRatio: .9,
    ),
  ];

  (int, int) rangeFor(Question q) =>
      baseRanges[q.type == QuestionType.longText &&
              (q.material?.trim().isNotEmpty ?? false)
          ? 'material'
          : q.type.dbValue]!;

  ScoringProfile copyWith({
    String? name,
    double? multiplier,
    int? questionCap,
    Map<String, (int, int)>? baseRanges,
    List<ScoringRule>? rules,
    int? colorValue,
    double? fontSize,
    double? detailFontSize,
    int? displayMs,
    bool? showPopup,
    int? sessionMinimum,
    int? sessionBonus,
    int? sessionPerQuestion,
    String? sessionLabel,
  }) => ScoringProfile(
    name: name ?? this.name,
    multiplier: multiplier ?? this.multiplier,
    questionCap: questionCap ?? this.questionCap,
    baseRanges: Map.unmodifiable(baseRanges ?? this.baseRanges),
    rules: List.unmodifiable(rules ?? this.rules),
    colorValue: colorValue ?? this.colorValue,
    fontSize: fontSize ?? this.fontSize,
    detailFontSize: detailFontSize ?? this.detailFontSize,
    displayMs: displayMs ?? this.displayMs,
    showPopup: showPopup ?? this.showPopup,
    sessionMinimum: sessionMinimum ?? this.sessionMinimum,
    sessionBonus: sessionBonus ?? this.sessionBonus,
    sessionPerQuestion: sessionPerQuestion ?? this.sessionPerQuestion,
    sessionLabel: sessionLabel ?? this.sessionLabel,
  );

  void validate() {
    if (name.trim().isEmpty ||
        name.length > 80 ||
        !multiplier.isFinite ||
        multiplier < 0 ||
        multiplier > 1000 ||
        questionCap < 1 ||
        questionCap > 100000000 ||
        fontSize < 12 ||
        fontSize > 96 ||
        !fontSize.isFinite ||
        detailFontSize < 8 ||
        detailFontSize > 48 ||
        !detailFontSize.isFinite ||
        displayMs < 300 ||
        displayMs > 60000 ||
        colorValue < 0 ||
        colorValue > 0xFFFFFFFF ||
        sessionMinimum < 1 ||
        sessionMinimum > 100000 ||
        sessionBonus < 0 ||
        sessionBonus > 100000000 ||
        sessionPerQuestion < 0 ||
        sessionPerQuestion > 1000000 ||
        sessionLabel.trim().isEmpty ||
        sessionLabel.length > 80) {
      throw const FormatException('积分方案参数超出有效范围');
    }
    for (final key in defaultRanges.keys) {
      final range = baseRanges[key];
      if (range == null ||
          range.$1 < 0 ||
          range.$2 < range.$1 ||
          range.$2 > 1000000) {
        throw FormatException('${rangeNames[key]}基础分必须为 0～1000000，且最低分不高于最高分');
      }
    }
    if (rules.length > 100 ||
        rules.map((r) => r.id).toSet().length != rules.length) {
      throw const FormatException('花式规则最多 100 条，规则标识不能重复');
    }
    for (final rule in rules) {
      rule.validate();
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'multiplier': multiplier,
    'questionCap': questionCap,
    'baseRanges': baseRanges.map((k, v) => MapEntry(k, [v.$1, v.$2])),
    'rules': rules.map((r) => r.toJson()).toList(),
    'colorValue': colorValue,
    'fontSize': fontSize,
    'detailFontSize': detailFontSize,
    'displayMs': displayMs,
    'showPopup': showPopup,
    'sessionMinimum': sessionMinimum,
    'sessionBonus': sessionBonus,
    'sessionPerQuestion': sessionPerQuestion,
    'sessionLabel': sessionLabel,
  };

  factory ScoringProfile.fromJson(Map<String, dynamic> json) {
    try {
      final ranges = (json['baseRanges'] as Map).map(
        (key, value) => MapEntry(key as String, (
          (value as List)[0] as int,
          value[1] as int,
        )),
      );
      final result = ScoringProfile(
        name: json['name'] as String,
        multiplier: (json['multiplier'] as num).toDouble(),
        questionCap: json['questionCap'] as int,
        baseRanges: Map.unmodifiable(ranges),
        rules: List.unmodifiable(
          (json['rules'] as List).map(
            (r) => ScoringRule.fromJson(Map<String, dynamic>.from(r as Map)),
          ),
        ),
        colorValue: json['colorValue'] as int,
        fontSize: (json['fontSize'] as num).toDouble(),
        detailFontSize: (json['detailFontSize'] as num).toDouble(),
        displayMs: json['displayMs'] as int,
        showPopup: json['showPopup'] as bool,
        sessionMinimum: json['sessionMinimum'] as int,
        sessionBonus: json['sessionBonus'] as int,
        sessionPerQuestion: json['sessionPerQuestion'] as int,
        sessionLabel: json['sessionLabel'] as String,
      );
      result.validate();
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('积分方案结构不完整或参数类型错误');
    }
  }
}

/// 同组只应用优先级最高的匹配规则；未分组规则可叠加。
class ScoringRule {
  final String id, name, group;
  final double multiplier, minRatio, highRollThreshold;
  final int bonus, minCombo, maxElapsedMs;
  final bool enabled,
      firstAttemptOnly,
      previouslyWrongOnly,
      challengeOnly,
      materialOnly,
      excludeMaterial,
      highRoll;
  final String? questionType;

  const ScoringRule({
    required this.id,
    required this.name,
    this.group = '',
    this.multiplier = 1,
    this.bonus = 0,
    this.minCombo = 0,
    this.maxElapsedMs = 0,
    this.minRatio = 0,
    this.highRollThreshold = .8,
    this.enabled = true,
    this.firstAttemptOnly = false,
    this.previouslyWrongOnly = false,
    this.challengeOnly = false,
    this.materialOnly = false,
    this.excludeMaterial = false,
    this.highRoll = false,
    this.questionType,
  });

  bool matches({
    required Question question,
    required int combo,
    required double ratio,
    required int elapsedMs,
    required bool firstAttempt,
    required bool previouslyWrong,
    required bool challenge,
    required int basePoints,
    required (int, int) range,
  }) {
    final material =
        question.type == QuestionType.longText &&
        (question.material?.trim().isNotEmpty ?? false);
    return enabled &&
        combo >= minCombo &&
        ratio >= minRatio &&
        (maxElapsedMs == 0 || (elapsedMs > 0 && elapsedMs < maxElapsedMs)) &&
        (!firstAttemptOnly || firstAttempt) &&
        (!previouslyWrongOnly || previouslyWrong) &&
        (!challengeOnly || challenge) &&
        (!materialOnly || material) &&
        (!excludeMaterial || !material) &&
        (questionType == null || question.type.dbValue == questionType) &&
        (!highRoll ||
            basePoints >= range.$1 + (range.$2 - range.$1) * highRollThreshold);
  }

  void validate() {
    if (id.isEmpty ||
        id.length > 100 ||
        name.trim().isEmpty ||
        name.length > 80 ||
        group.length > 80 ||
        !multiplier.isFinite ||
        multiplier < 0 ||
        multiplier > 1000 ||
        bonus < 0 ||
        bonus > 100000000 ||
        minCombo < 0 ||
        minCombo > 100000 ||
        maxElapsedMs < 0 ||
        maxElapsedMs > 86400000 ||
        !minRatio.isFinite ||
        minRatio < 0 ||
        minRatio > 1 ||
        !highRollThreshold.isFinite ||
        highRollThreshold < 0 ||
        highRollThreshold > 1 ||
        (questionType != null &&
            !QuestionType.values.any((q) => q.dbValue == questionType)) ||
        (materialOnly && excludeMaterial)) {
      throw FormatException('花式规则「$name」参数无效');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'group': group,
    'multiplier': multiplier,
    'bonus': bonus,
    'minCombo': minCombo,
    'maxElapsedMs': maxElapsedMs,
    'minRatio': minRatio,
    'highRollThreshold': highRollThreshold,
    'enabled': enabled,
    'firstAttemptOnly': firstAttemptOnly,
    'previouslyWrongOnly': previouslyWrongOnly,
    'challengeOnly': challengeOnly,
    'materialOnly': materialOnly,
    'excludeMaterial': excludeMaterial,
    'highRoll': highRoll,
    'questionType': questionType,
  };

  factory ScoringRule.fromJson(Map<String, dynamic> j) => ScoringRule(
    id: j['id'] as String,
    name: j['name'] as String,
    group: j['group'] as String,
    multiplier: (j['multiplier'] as num).toDouble(),
    bonus: j['bonus'] as int,
    minCombo: j['minCombo'] as int,
    maxElapsedMs: j['maxElapsedMs'] as int,
    minRatio: (j['minRatio'] as num).toDouble(),
    highRollThreshold: (j['highRollThreshold'] as num).toDouble(),
    enabled: j['enabled'] as bool,
    firstAttemptOnly: j['firstAttemptOnly'] as bool,
    previouslyWrongOnly: j['previouslyWrongOnly'] as bool,
    challengeOnly: j['challengeOnly'] as bool,
    materialOnly: j['materialOnly'] as bool,
    excludeMaterial: j['excludeMaterial'] as bool,
    highRoll: j['highRoll'] as bool,
    questionType: j['questionType'] as String?,
  );
}
