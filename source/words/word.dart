import 'dart:convert';

/// 收录本里的一条词语
class Word {
  final int? id;

  /// 原始词条（保留用户输入的大小写）
  final String word;

  /// 归一化后的词条，用于判重（小写、去首尾空白）
  final String normalized;

  /// 音标，如 /ˈæpəl/
  final String? phonetic;

  /// 词性，可并存多个，如 ['n.', 'v.']
  final List<String> partsOfSpeech;

  /// 释义，可多条
  final List<String> definitions;

  /// 与释义按下标对应；空字符串代表未指定词性。
  final List<String> definitionParts;

  /// 例句
  final String? example;

  /// 个人笔记
  final String? note;

  /// 标签
  final List<String> tags;

  /// 收录次数：同一个词被收录几次就是几
  final int collectCount;

  final int? userId;
  final int isPinned;

  /// 最近一次收录时间
  final String? lastCollectedAt;
  final String createdAt;

  Word({
    this.id,
    required this.word,
    String? normalized,
    this.phonetic,
    List<String>? partsOfSpeech,
    List<String>? definitions,
    List<String>? definitionParts,
    this.example,
    this.note,
    List<String>? tags,
    this.collectCount = 1,
    this.userId,
    this.isPinned = 0,
    this.lastCollectedAt,
    String? createdAt,
  }) : normalized = normalized ?? normalizeWord(word),
       partsOfSpeech = partsOfSpeech ?? <String>[],
       definitions = definitions ?? <String>[],
       definitionParts = definitionParts ?? <String>[],
       tags = tags ?? <String>[],
       createdAt = createdAt ?? DateTime.now().toIso8601String();

  /// 判重用：去掉首尾空白与所有空白字符，英文转小写
  static String normalizeWord(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  /// 释义首条，用于列表展示
  String get primaryDefinition =>
      definitions.isEmpty ? '（未填写释义）' : definitions.first;

  /// 词性展示文本，如 "n. / v."
  String get partOfSpeechLabel => partsOfSpeech.join(' / ');

  /// 解析词性：新数据是 JSON 数组，旧数据是 "n." 这样的单个字符串
  static List<String> _decodeParts(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return <String>[];

    // 先试 JSON 数组
    if (text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // 落到下面的分隔符处理
      }
    }

    // 旧格式：单个词性，或 "n. / v." 这种写法
    return text
        .split(RegExp(r'[/,，、;；]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'word': word,
    'normalized': normalized,
    'phonetic': phonetic,
    'part_of_speech': jsonEncode(partsOfSpeech),
    'definitions': jsonEncode(definitions),
    'definition_parts': jsonEncode(definitionParts),
    'example': example,
    'note': note,
    'tags': jsonEncode(tags),
    'collect_count': collectCount,
    'user_id': userId,
    'is_pinned': isPinned,
    'last_collected_at': lastCollectedAt,
    'created_at': createdAt,
  };

  factory Word.fromMap(Map<String, dynamic> m) {
    return Word(
      id: m['id'] as int?,
      word: m['word'] as String,
      normalized: m['normalized'] as String?,
      phonetic: m['phonetic'] as String?,
      partsOfSpeech: _decodeParts(m['part_of_speech']),
      definitions: decodeStringList(m['definitions']),
      definitionParts: _decodeDefinitionParts(m['definition_parts']),
      example: m['example'] as String?,
      note: m['note'] as String?,
      tags: decodeStringList(m['tags']),
      collectCount: (m['collect_count'] as int?) ?? 1,
      userId: m['user_id'] as int?,
      isPinned: (m['is_pinned'] as int?) ?? 0,
      lastCollectedAt: m['last_collected_at'] as String?,
      createdAt: m['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  static List<String> _decodeDefinitionParts(dynamic raw) {
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List)
        return decoded.map((v) => v?.toString() ?? '').toList();
    } catch (_) {
      /* 旧数据按未指定词性处理。 */
    }
    return [];
  }

  /// 兼容 TEXT(JSON 数组) 与直接传入的 List
  static List<String> decodeStringList(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // 不是 JSON，按换行/分号拆
    }
    return text
        .split(RegExp(r'[\n;；]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Word copyWith({
    int? id,
    String? word,
    String? phonetic,
    List<String>? partsOfSpeech,
    List<String>? definitions,
    List<String>? definitionParts,
    String? example,
    String? note,
    List<String>? tags,
    int? collectCount,
    int? userId,
    int? isPinned,
    String? lastCollectedAt,
    String? createdAt,
  }) {
    return Word(
      id: id ?? this.id,
      word: word ?? this.word,
      phonetic: phonetic ?? this.phonetic,
      partsOfSpeech: partsOfSpeech ?? this.partsOfSpeech,
      definitions: definitions ?? this.definitions,
      definitionParts: definitionParts ?? this.definitionParts,
      example: example ?? this.example,
      note: note ?? this.note,
      tags: tags ?? this.tags,
      collectCount: collectCount ?? this.collectCount,
      userId: userId ?? this.userId,
      isPinned: isPinned ?? this.isPinned,
      lastCollectedAt: lastCollectedAt ?? this.lastCollectedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 一次收录动作的结果，便于界面给用户明确反馈
enum CollectOutcome {
  /// 新词，首次收录
  created,

  /// 已存在，收录次数 +1
  incremented,
}

class CollectResult {
  final CollectOutcome outcome;
  final Word word;

  /// 收录后的次数
  int get collectCount => word.collectCount;

  const CollectResult({required this.outcome, required this.word});

  bool get isNew => outcome == CollectOutcome.created;
}

/// 查看收录内容时的排序方式（含升序/降序）
enum WordSort {
  collectCountDesc,
  collectCountAsc,
  recentCollectedDesc,
  createdAtDesc,
  createdAtAsc,
  wordAsc,
  wordDesc,
  tagAsc,
}

extension WordSortName on WordSort {
  String get displayName {
    switch (this) {
      case WordSort.collectCountDesc:
        return '收录次数 降序（多→少）';
      case WordSort.collectCountAsc:
        return '收录次数 升序（少→多）';
      case WordSort.recentCollectedDesc:
        return '最近收录 降序（近→远）';
      case WordSort.createdAtDesc:
        return '收录时间 降序（新→旧）';
      case WordSort.createdAtAsc:
        return '收录时间 升序（旧→新）';
      case WordSort.wordAsc:
        return '词语 A → Z';
      case WordSort.wordDesc:
        return '词语 Z → A';
      case WordSort.tagAsc:
        return '标签 A → Z';
    }
  }

  /// 对应 SQL 的 ORDER BY 片段，置顶始终优先
  String get orderBy {
    switch (this) {
      case WordSort.collectCountDesc:
        return 'is_pinned DESC, collect_count DESC, created_at DESC';
      case WordSort.collectCountAsc:
        return 'is_pinned DESC, collect_count ASC, created_at DESC';
      case WordSort.recentCollectedDesc:
        return 'is_pinned DESC, last_collected_at DESC, created_at DESC';
      case WordSort.createdAtDesc:
        return 'is_pinned DESC, created_at DESC';
      case WordSort.createdAtAsc:
        return 'is_pinned DESC, created_at ASC';
      case WordSort.wordAsc:
        return 'is_pinned DESC, word COLLATE NOCASE ASC';
      case WordSort.wordDesc:
        return 'is_pinned DESC, word COLLATE NOCASE DESC';
      case WordSort.tagAsc:
        return 'is_pinned DESC, tags COLLATE NOCASE ASC, word COLLATE NOCASE ASC';
    }
  }
}

/// 收录次数的快捷筛选
enum WordCountFilter { all, once, twiceOrMore, threeOrMore }

extension WordCountFilterName on WordCountFilter {
  String get displayName {
    switch (this) {
      case WordCountFilter.all:
        return '全部';
      case WordCountFilter.once:
        return '只收录过 1 次';
      case WordCountFilter.twiceOrMore:
        return '收录 ≥ 2 次';
      case WordCountFilter.threeOrMore:
        return '收录 ≥ 3 次（高频）';
    }
  }

  bool matches(int count) {
    switch (this) {
      case WordCountFilter.all:
        return true;
      case WordCountFilter.once:
        return count == 1;
      case WordCountFilter.twiceOrMore:
        return count >= 2;
      case WordCountFilter.threeOrMore:
        return count >= 3;
    }
  }
}

/// 一条收录流水
class WordCollectLog {
  final int? id;
  final int wordId;
  final int? userId;
  final String collectedAt;
  final String source;

  WordCollectLog({
    this.id,
    required this.wordId,
    this.userId,
    String? collectedAt,
    this.source = 'manual',
  }) : collectedAt = collectedAt ?? DateTime.now().toIso8601String();

  factory WordCollectLog.fromMap(Map<String, dynamic> m) => WordCollectLog(
    id: m['id'] as int?,
    wordId: m['word_id'] as int,
    userId: m['user_id'] as int?,
    collectedAt: m['collected_at'] as String,
    source: (m['source'] as String?) ?? 'manual',
  );
}
