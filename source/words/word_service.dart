import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/word.dart';

class WordService {
  final _db = AppDatabase.instance;

  Future<int?> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  /// 收录本列表
  /// - [sort] 控制排序方式（支持收录次数升/降序等）
  /// - [keyword] 按词语/释义/笔记/标签模糊搜索
  /// - [tag] 只看带某个标签的词
  /// - [countFilter] 按收录次数筛选
  /// - [onlyMine] 仅看自己收录的
  Future<List<Word>> listWords({
    WordSort sort = WordSort.collectCountDesc,
    String keyword = '',
    String? tag,
    WordCountFilter countFilter = WordCountFilter.all,
    bool onlyMine = true,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    if (onlyMine) {
      final userId = await _currentUserId();
      where.add('user_id = ?');
      args.add(userId);
    }

    final kw = keyword.trim();
    if (kw.isNotEmpty) {
      where.add(
        '(word LIKE ? OR definitions LIKE ? OR note LIKE ? OR tags LIKE ? OR phonetic LIKE ?)',
      );
      final like = '%$kw%';
      args.addAll([like, like, like, like, like]);
    }

    final rows = await _db.query(
      'words',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: sort.orderBy,
    );

    var list = rows.map(Word.fromMap).toList();

    // 标签与收录次数在内存里过滤，避免拼复杂的 LIKE
    final t = tag?.trim();
    if (t != null && t.isNotEmpty) {
      list = list
          .where(
            (w) => w.tags.any(
              (tag) => tag.trim().toLowerCase() == t.toLowerCase(),
            ),
          )
          .toList();
    }
    if (countFilter != WordCountFilter.all) {
      list = list.where((w) => countFilter.matches(w.collectCount)).toList();
    }

    return list;
  }

  /// 收录本里出现过的所有标签，按使用频次从高到低
  Future<List<String>> listTags({bool onlyMine = true}) async {
    final userId = await _currentUserId();
    final rows = await _db.query(
      'words',
      columns: ['tags'],
      where: onlyMine ? 'user_id = ?' : null,
      whereArgs: onlyMine ? [userId] : null,
    );

    final counter = <String, int>{};
    for (final r in rows) {
      for (final tag in Word.decodeStringList(r['tags'])) {
        final normalized = tag.trim().toLowerCase();
        if (normalized.isNotEmpty)
          counter[normalized] = (counter[normalized] ?? 0) + 1;
      }
    }

    final tags = counter.keys.toList()
      ..sort((a, b) {
        final c = counter[b]!.compareTo(counter[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return tags;
  }

  /// 统计信息：总词数、总收录次数
  Future<Map<String, int>> stats({bool onlyMine = true}) async {
    final userId = await _currentUserId();
    final rows = await _db.rawQuery(
      onlyMine
          ? 'SELECT COUNT(*) AS cnt, COALESCE(SUM(collect_count), 0) AS total '
                'FROM words WHERE user_id = ?'
          : 'SELECT COUNT(*) AS cnt, COALESCE(SUM(collect_count), 0) AS total '
                'FROM words',
      onlyMine ? [userId] : [],
    );
    if (rows.isEmpty) return {'count': 0, 'total': 0};
    return {
      'count': (rows.first['cnt'] as int?) ?? 0,
      'total': ((rows.first['total'] as num?) ?? 0).toInt(),
    };
  }

  /// 收录一个词。
  /// 已存在（同一用户、归一化后相同）则收录次数 +1，并返回是否为新词。
  Future<CollectResult> collect(Word w) async {
    final userId = w.userId ?? await _currentUserId();
    final now = DateTime.now().toIso8601String();

    final existing = await _db.query(
      'words',
      where: 'normalized = ? AND user_id = ?',
      whereArgs: [w.normalized, userId],
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final old = Word.fromMap(row);
      final newCount = old.collectCount + 1;

      // 本次填写了内容就用新内容覆盖，留空的字段保留原值
      final merged = old.copyWith(
        word: w.word.isNotEmpty ? w.word : old.word,
        phonetic: _pick(w.phonetic, old.phonetic),
        partsOfSpeech: w.partsOfSpeech.isNotEmpty
            ? w.partsOfSpeech
            : old.partsOfSpeech,
        definitions: w.definitions.isNotEmpty ? w.definitions : old.definitions,
        definitionParts: w.definitions.isNotEmpty
            ? w.definitionParts
            : old.definitionParts,
        example: _pick(w.example, old.example),
        note: _pick(w.note, old.note),
        tags: w.tags.isNotEmpty ? w.tags : old.tags,
        collectCount: newCount,
        lastCollectedAt: now,
      );

      await _db.update(
        'words',
        {
          'word': merged.word,
          'phonetic': merged.phonetic,
          'part_of_speech': merged.toMap()['part_of_speech'],
          'definitions': merged.toMap()['definitions'],
          'definition_parts': merged.toMap()['definition_parts'],
          'example': merged.example,
          'note': merged.note,
          'tags': merged.toMap()['tags'],
          'collect_count': newCount,
          'last_collected_at': now,
        },
        where: 'id = ?',
        whereArgs: [old.id],
      );

      await _addLog(old.id!, userId, now);
      return CollectResult(outcome: CollectOutcome.incremented, word: merged);
    }

    final id = await _db.insert(
      'words',
      w.copyWith(userId: userId, collectCount: 1, lastCollectedAt: now).toMap()
        ..remove('id'),
    );

    await _addLog(id, userId, now);
    return CollectResult(
      outcome: CollectOutcome.created,
      word: w.copyWith(
        id: id,
        userId: userId,
        collectCount: 1,
        lastCollectedAt: now,
      ),
    );
  }

  /// 测试答错时调用：收录次数 +1，并记一条来源为 test 的流水
  Future<void> bumpCollectCount(int wordId, {String source = 'test'}) async {
    final rows = await _db.query('words', where: 'id = ?', whereArgs: [wordId]);
    if (rows.isEmpty) return;
    final old = Word.fromMap(rows.first);
    final now = DateTime.now().toIso8601String();
    await _db.update(
      'words',
      {'collect_count': old.collectCount + 1, 'last_collected_at': now},
      where: 'id = ?',
      whereArgs: [wordId],
    );
    await _addLog(wordId, old.userId, now, source: source);
  }

  Future<void> _addLog(
    int wordId,
    int? userId,
    String at, {
    String source = 'manual',
  }) async {
    await _db.insert('word_collect_logs', {
      'word_id': wordId,
      'user_id': userId,
      'collected_at': at,
      'source': source,
    });
  }

  String? _pick(String? incoming, String? fallback) {
    if (incoming == null) return fallback;
    final t = incoming.trim();
    return t.isEmpty ? fallback : t;
  }

  /// 编辑保存（不改动收录次数）
  Future<int> updateWord(Word w) async {
    final map = w.toMap();
    return await _db.update(
      'words',
      {
        'word': w.word,
        'normalized': w.normalized,
        'phonetic': w.phonetic,
        'part_of_speech': map['part_of_speech'],
        'definitions': map['definitions'],
        'definition_parts': map['definition_parts'],
        'example': w.example,
        'note': w.note,
        'tags': map['tags'],
      },
      where: 'id = ?',
      whereArgs: [w.id],
    );
  }

  /// 手动调整收录次数（≥1）
  Future<void> setCollectCount(int id, int count) async {
    final safe = count < 1 ? 1 : count;
    await _db.update(
      'words',
      {'collect_count': safe},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 再收录一次（列表页快捷 +1）
  Future<Word?> collectAgain(int id) async {
    final rows = await _db.query('words', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final w = Word.fromMap(rows.first);
    final result = await collect(w);
    return result.word;
  }

  Future<void> togglePin(int id) async {
    final rows = await _db.query('words', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final cur = (rows.first['is_pinned'] as int?) ?? 0;
    await _db.update(
      'words',
      {'is_pinned': cur == 1 ? 0 : 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteWord(int id) async {
    await _db.rawDelete('DELETE FROM word_collect_logs WHERE word_id = ?', [
      id,
    ]);
    return await _db.delete('words', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.rawDelete(
      'DELETE FROM word_collect_logs WHERE word_id IN ($placeholders)',
      ids,
    );
    return await _db.rawDelete(
      'DELETE FROM words WHERE id IN ($placeholders)',
      ids,
    );
  }

  /// 某个词的收录流水（最近 N 条）
  Future<List<WordCollectLog>> collectLogs(int wordId, {int limit = 50}) async {
    final rows = await _db.query(
      'word_collect_logs',
      where: 'word_id = ?',
      whereArgs: [wordId],
      orderBy: 'collected_at DESC',
    );
    return rows.take(limit).map(WordCollectLog.fromMap).toList();
  }
}
