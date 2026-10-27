import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/challenge_preset.dart';
import '../models/question.dart';

class ChallengeService {
  static const _key = 'challenge_presets_v1';
  static const format = 'quiz_app.challenge';

  Future<List<ChallengePreset>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <ChallengePreset>[];
    for (final raw in prefs.getStringList(_key) ?? <String>[]) {
      try {
        result.add(
          ChallengePreset.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        /* An invalid old preset must not hide valid presets. */
      }
    }
    return result;
  }

  Future<void> save(ChallengePreset preset) async {
    ChallengePreset.fromJson(preset.toJson());
    final presets = await list();
    presets.removeWhere((p) => p.id == preset.id);
    presets.insert(0, preset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      presets.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  Future<void> delete(String id) async {
    final presets = (await list())..removeWhere((p) => p.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      presets.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  /// 所有题目不足都会明确报错，不会静默减少题量。
  List<Question> build(
    ChallengePreset preset,
    List<Question> pool, {
    Random? random,
  }) {
    ChallengePreset.fromJson(preset.toJson());
    final picked = <Question>[];
    if (preset.selection == ChallengeSelection.manual) {
      final byId = {for (final q in pool) q.id: q};
      for (final id in preset.questionIds) {
        final q = byId[id];
        if (q == null) throw const FormatException('所选题目已删除或不可访问，请重新选题');
        picked.add(q);
      }
    } else {
      for (var i = 0; i < ChallengePreset.categories.length; i++) {
        final key = ChallengePreset.categories[i];
        final count = preset.counts[key] ?? 0;
        final candidates = pool
            .where((q) => ChallengePreset.categoryOf(q) == key)
            .toList();
        if (candidates.length < count) {
          throw FormatException(
            '${ChallengePreset.categoryNames[i]}需要 $count 题，可用 ${candidates.length} 题',
          );
        }
        candidates.shuffle(random);
        picked.addAll(candidates.take(count));
      }
    }
    if (picked.isEmpty) throw const FormatException('请至少选择一道题');
    if (preset.rules.shuffle) picked.shuffle(random);
    return picked;
  }

  String export(ChallengePreset preset, List<Question> questions) {
    ChallengePreset.fromJson(preset.toJson());
    final selected = preset.selection == ChallengeSelection.manual
        ? build(preset, questions)
        : <Question>[];
    // 文件夹和本地用户编号不跨设备复用；手选题目通过快照移植。
    final config = preset.toJson()..['folderId'] = null;
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': 1,
      'preset': config,
      'questions': selected
          .map(
            (q) => q.toMap()
              ..['creator_id'] = null
              ..['folder_id'] = null,
          )
          .toList(),
    });
  }

  ({ChallengePreset preset, List<Question> questions}) decode(String text) {
    if (text.length > 20 * 1024 * 1024) {
      throw const FormatException('分享文件超过 20 MB');
    }
    try {
      final data = jsonDecode(text);
      if (data is! Map || data['format'] != format || data['version'] != 1) {
        throw const FormatException('不支持的挑战分享格式或版本');
      }
      final preset = ChallengePreset.fromJson(
        Map<String, dynamic>.from(data['preset'] as Map),
      );
      final raw = data['questions'];
      if (raw is! List || raw.length > 10000) {
        throw const FormatException('题目快照无效');
      }
      final questions = raw
          .map((q) => Question.fromMap(Map<String, dynamic>.from(q as Map)))
          .toList();
      final ids = <int>{};
      for (final q in questions) {
        if (q.id == null ||
            q.id! <= 0 ||
            !ids.add(q.id!) ||
            q.stem.trim().isEmpty ||
            !q.totalScore.isFinite ||
            q.totalScore <= 0 ||
            (q.type.isOptionBased &&
                ((q.options?.isEmpty ?? true) ||
                    (q.correctAnswer?.isEmpty ?? true))) ||
            (q.type == QuestionType.fillBlank && (q.blanks?.isEmpty ?? true)) ||
            (q.type == QuestionType.longText &&
                (q.segments?.isEmpty ?? true))) {
          throw const FormatException('分享文件包含无效或重复题目');
        }
      }
      if (preset.selection == ChallengeSelection.manual &&
          (preset.questionIds.any((id) => !ids.contains(id)) ||
              questions.length != preset.questionIds.length)) {
        throw const FormatException('分享文件缺少手选题目，请让发送者重新导出');
      }
      if (preset.selection == ChallengeSelection.random &&
          questions.isNotEmpty) {
        throw const FormatException('随机挑战配置不应附带无关题目');
      }
      return (preset: preset, questions: questions);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('挑战分享文件结构无效');
    }
  }

  /// 验证完整文件后才导入，并将来源编号映射为本地编号。
  Future<ChallengePreset> import(String text) async {
    final decoded = decode(text);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final db = await AppDatabase.instance.database;
    final mapped = <int, int>{};
    await db.transaction((tx) async {
      final existing = await tx.query(
        'questions',
        where: 'is_public = 1 OR creator_id = ?',
        whereArgs: [userId],
      );
      final signatures = {
        for (final row in existing)
          _signature(Question.fromMap(row)): row['id'] as int,
      };
      for (final q in decoded.questions) {
        final signature = _signature(q);
        var id = signatures[signature];
        if (id == null) {
          final row = q.toMap()..remove('id');
          row['creator_id'] = userId;
          row['folder_id'] = null;
          row['is_public'] = 0;
          row['source'] = 'challenge_share';
          row['is_pinned'] = 0;
          id = await tx.insert('questions', row);
          signatures[signature] = id;
        }
        mapped[q.id!] = id;
      }
    });
    final json = decoded.preset.toJson()
      ..['id'] = DateTime.now().microsecondsSinceEpoch.toString()
      ..['folderId'] = null
      ..['questionIds'] = decoded.preset.selection == ChallengeSelection.manual
          ? decoded.preset.questionIds.map((id) => mapped[id]!).toList()
          : <int>[];
    final preset = ChallengePreset.fromJson(json);
    await save(preset);
    return preset;
  }

  String _signature(Question q) => jsonEncode({
    'type': q.type.dbValue,
    'stem': q.stem,
    'material': q.material,
    'options': q.options,
    'answer': q.correctAnswer,
    'blanks': q.blanks?.map((b) => b.toJson()).toList(),
    'segments': q.segments?.map((s) => s.toJson()).toList(),
    'score': q.totalScore,
    'explanation': q.explanation,
  });
}
