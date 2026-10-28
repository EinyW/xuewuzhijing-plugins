import 'dart:convert';

enum QuestionType { choice, multiChoice, fillBlank, longText }

extension QuestionTypeName on QuestionType {
  String get dbValue {
    switch (this) {
      case QuestionType.choice: return 'choice';
      case QuestionType.multiChoice: return 'multi_choice';
      case QuestionType.fillBlank: return 'fill_blank';
      case QuestionType.longText: return 'long_text';
    }
  }

  String get displayName {
    switch (this) {
      case QuestionType.choice: return '选择题';
      case QuestionType.multiChoice: return '多选题';
      case QuestionType.fillBlank: return '填空题';
      case QuestionType.longText: return '长文本题';
    }
  }

  /// 选项类题目：答案存在 correctAnswer 字段里（单选是 "A"，多选是 "A,C"）
  bool get isOptionBased =>
      this == QuestionType.choice || this == QuestionType.multiChoice;

  bool get isMultiSelect => this == QuestionType.multiChoice;
}

QuestionType questionTypeFromString(String s) {
  switch (s) {
    case 'choice': return QuestionType.choice;
    case 'multi_choice': return QuestionType.multiChoice;
    case 'fill_blank': return QuestionType.fillBlank;
    case 'long_text': return QuestionType.longText;
    default: throw ArgumentError('未知题型: $s');
  }
}

class BlankSegment {
  final String answer;
  final List<String> keywords;
  BlankSegment({required this.answer, required this.keywords});

  Map<String, dynamic> toJson() => {'answer': answer, 'keywords': keywords};
  factory BlankSegment.fromJson(Map<String, dynamic> j) => BlankSegment(
        answer: j['answer'] as String,
        keywords: List<String>.from(j['keywords'] ?? []),
      );
}

class TextSegment {
  final List<String> keywords;
  TextSegment({required this.keywords});

  Map<String, dynamic> toJson() => {'keywords': keywords};
  factory TextSegment.fromJson(Map<String, dynamic> j) => TextSegment(
        keywords: List<String>.from(j['keywords'] ?? []),
      );
}

class Question {
  final int? id;
  final QuestionType type;
  final String stem;
  final String? material;
  final List<String>? options;
  final String? correctAnswer;
  final List<BlankSegment>? blanks;
  final List<TextSegment>? segments;
  final double totalScore;
  final String? explanation;
  final int? creatorId;
  final int isPublic;
  final String? source;
  final String createdAt;
  final int? folderId;
  final int isPinned;

  Question({
    this.id,
    required this.type,
    required this.stem,
    this.material,
    this.options,
    this.correctAnswer,
    this.blanks,
    this.segments,
    this.totalScore = 0,
    this.explanation,
    this.creatorId,
    this.isPublic = 1,
    this.source,
    String? createdAt,
    this.folderId,
    this.isPinned = 0,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  double get perSegmentScore {
    if (type != QuestionType.longText) return 0;
    final n = segments?.length ?? 0;
    if (n == 0) return 0;
    return totalScore / n;
  }

  /// 选项字母列表（多选题用），例如 "A,C" -> ['A', 'C']
  static List<String> parseAnswerLetters(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>[];
    return raw
        .split(RegExp(r'[,，、;；\s]+'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  /// 多选题的正确答案字母列表
  List<String> get correctAnswerLetters =>
      parseAnswerLetters(correctAnswer);

  /// 把选项字母列表拼成存储用的字符串
  static String joinAnswerLetters(Iterable<String> letters) {
    final list = letters.map((e) => e.toUpperCase()).toSet().toList()..sort();
    return list.join(',');
  }

  Map<String, dynamic> toMap() {
    String? correctAnswerJson;
    if (type.isOptionBased) {
      correctAnswerJson = correctAnswer;
    } else if (type == QuestionType.fillBlank) {
      correctAnswerJson = jsonEncode(blanks!.map((b) => b.toJson()).toList());
    }

    return {
      'id': id,
      'type': type.dbValue,
      'stem': stem,
      'material': material,
      'options': options != null ? jsonEncode(options) : null,
      'correct_answer': correctAnswerJson,
      'segments': segments != null
          ? jsonEncode(segments!.map((s) => s.toJson()).toList())
          : null,
      'total_score': totalScore,
      'explanation': explanation,
      'creator_id': creatorId,
      'is_public': isPublic,
      'source': source ?? 'manual',
      'created_at': createdAt,
      'folder_id': folderId,
      'is_pinned': isPinned,
    };
  }

  /// 从 map 构造
  /// 兼容两种来源：
  ///   - 数据库/旧导出的字符串形式
  ///   - 手写 JSON 的直接数组形式
  factory Question.fromMap(Map<String, dynamic> map) {
    final type = questionTypeFromString(map['type'] as String);

    // options
    List<String>? options;
    if (map['options'] != null) {
      final raw = map['options'];
      if (raw is List) {
        options = List<String>.from(raw);
      } else {
        options = List<String>.from(jsonDecode(raw as String));
      }
    }

    // correct_answer / blanks
    String? correctAnswer;
    List<BlankSegment>? blanks;
    if (type.isOptionBased) {
      correctAnswer = map['correct_answer'] as String?;
    } else if (type == QuestionType.fillBlank &&
        map['correct_answer'] != null) {
      final raw = map['correct_answer'];
      final List list;
      if (raw is List) {
        list = raw;
      } else {
        list = jsonDecode(raw as String) as List;
      }
      blanks = list
          .map((e) => BlankSegment.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // segments
    List<TextSegment>? segments;
    if (map['segments'] != null) {
      final raw = map['segments'];
      final List list;
      if (raw is List) {
        list = raw;
      } else {
        list = jsonDecode(raw as String) as List;
      }
      segments = list
          .map((e) => TextSegment.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return Question(
      id: map['id'] as int?,
      type: type,
      stem: map['stem'] as String,
      material: map['material'] as String?,
      options: options,
      correctAnswer: correctAnswer,
      blanks: blanks,
      segments: segments,
      totalScore: (map['total_score'] as num?)?.toDouble() ?? 0,
      explanation: map['explanation'] as String?,
      creatorId: map['creator_id'] as int?,
      isPublic: (map['is_public'] as int?) ?? 1,
      source: map['source'] as String?,
      createdAt: map['created_at'] as String? ??
          DateTime.now().toIso8601String(),
      folderId: map['folder_id'] as int?,
      isPinned: (map['is_pinned'] as int?) ?? 0,
    );
  }

  Question copyWith({int? id, int? folderId, int? isPinned}) {
    return Question(
      id: id ?? this.id,
      type: type,
      stem: stem,
      material: material,
      options: options,
      correctAnswer: correctAnswer,
      blanks: blanks,
      segments: segments,
      totalScore: totalScore,
      explanation: explanation,
      creatorId: creatorId,
      isPublic: isPublic,
      source: source,
      createdAt: createdAt,
      folderId: folderId ?? this.folderId,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}