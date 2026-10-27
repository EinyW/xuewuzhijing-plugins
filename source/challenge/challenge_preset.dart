import 'challenge_rules.dart';
import 'question.dart';

enum ChallengeSelection { random, manual }

/// 规则与选题方式一并保存；分享文件还可携带题目快照。
class ChallengePreset {
  final String id;
  final String name;
  final ChallengeRules rules;
  final ChallengeSelection selection;
  final Map<String, int> counts;
  final List<int> questionIds;
  final int? folderId;

  static const categories = ['choice', 'multi', 'fill', 'long', 'material'];
  static const categoryNames = ['单选题', '多选题', '填空题', '长文本题', '材料题'];

  const ChallengePreset({
    required this.id,
    required this.name,
    this.rules = const ChallengeRules(),
    this.selection = ChallengeSelection.random,
    this.counts = const {
      'choice': 5,
      'multi': 0,
      'fill': 0,
      'long': 0,
      'material': 0,
    },
    this.questionIds = const [],
    this.folderId,
  });

  static String categoryOf(Question q) => switch (q.type) {
    QuestionType.choice => 'choice',
    QuestionType.multiChoice => 'multi',
    QuestionType.fillBlank => 'fill',
    QuestionType.longText =>
      (q.material?.trim().isNotEmpty ?? false) ? 'material' : 'long',
  };

  int get total => selection == ChallengeSelection.manual
      ? questionIds.length
      : counts.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rules': rules.toJson(),
    'selection': selection.name,
    'counts': counts,
    'questionIds': questionIds,
    'folderId': folderId,
  };

  factory ChallengePreset.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty || name.length > 120) {
      throw const FormatException('挑战名称应为 1–120 个字符');
    }
    final rawCounts = json['counts'];
    if (rawCounts is! Map) throw const FormatException('缺少题量配置');
    final counts = <String, int>{};
    for (final key in categories) {
      final value = rawCounts[key] ?? 0;
      if (value is! int || value < 0 || value > 10000) {
        throw const FormatException('题量应为 0–10000 的整数');
      }
      counts[key] = value;
    }
    final rawIds = json['questionIds'] ?? [];
    if (rawIds is! List ||
        rawIds.length > 10000 ||
        rawIds.any((id) => id is! int || id <= 0)) {
      throw const FormatException('题目编号无效');
    }
    final mode = json['selection'];
    if (mode != 'random' && mode != 'manual') {
      throw const FormatException('选题方式无效');
    }
    if (json['rules'] is! Map) throw const FormatException('缺少挑战规则');
    final folderId = json['folderId'];
    if (folderId != null &&
        (folderId is! int || folderId == 0 || folderId < -1)) {
      throw const FormatException('文件夹编号无效');
    }
    final preset = ChallengePreset(
      id: json['id'] is String ? json['id'] as String : '',
      name: name.trim(),
      rules: ChallengeRules.fromJson(
        Map<String, dynamic>.from(json['rules'] as Map),
      ),
      selection: mode == 'manual'
          ? ChallengeSelection.manual
          : ChallengeSelection.random,
      counts: counts,
      questionIds: List<int>.from(rawIds).toSet().toList(),
      folderId: folderId as int?,
    );
    if (preset.total == 0 || preset.total > 10000) {
      throw const FormatException('挑战必须包含 1–10000 道题');
    }
    return preset;
  }
}
