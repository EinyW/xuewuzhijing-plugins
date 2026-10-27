import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'question.dart';

/// Points are normalized to the board, so saved handwriting survives resizing.
class BoardStroke {
  final List<Offset> points;
  final int color;
  final double width;
  final bool eraser;

  BoardStroke({
    required this.points,
    this.color = 0xff25344a,
    this.width = 3,
    this.eraser = false,
  });

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'color': color,
    'width': width,
    'eraser': eraser,
  };

  factory BoardStroke.fromJson(Map<String, dynamic> json) {
    final width = (json['width'] as num).toDouble();
    if (!width.isFinite || width < 1 || width > 60) {
      throw const FormatException('画笔粗细无效');
    }
    final points = (json['points'] as List).map((raw) {
      final pair = raw as List;
      final x = (pair[0] as num).toDouble();
      final y = (pair[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
        throw const FormatException('画板坐标无效');
      }
      return Offset(x, y);
    }).toList();
    return BoardStroke(
      points: points,
      color: json['color'] as int,
      width: width,
      eraser: json['eraser'] == true,
    );
  }
}

class WhiteboardDocument {
  static const version = 1;
  final List<BoardStroke> strokes;
  final List<String> documents;
  final List<Question> questions;
  final double split;
  final bool documentAbove;
  final bool grid;

  /// v1 旧数据只有 strokes；新数据可保存多张画布。
  final List<List<BoardStroke>> pages;
  final int activePage;

  const WhiteboardDocument({
    this.strokes = const [],
    this.documents = const [],
    this.questions = const [],
    this.split = 0.42,
    this.documentAbove = true,
    this.grid = true,
    this.pages = const [],
    this.activePage = 0,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'strokes': strokes.map((s) => s.toJson()).toList(),
    'documents': documents,
    'questions': questions.map((q) => q.toMap()).toList(),
    'split': split,
    'documentAbove': documentAbove,
    'grid': grid,
    if (pages.isNotEmpty)
      'pages': pages
          .map((page) => page.map((s) => s.toJson()).toList())
          .toList(),
    'activePage': activePage,
  };

  factory WhiteboardDocument.fromJson(Map<String, dynamic> json) {
    if (json['version'] != version) {
      throw const FormatException('不支持此画板版本');
    }
    final strokes = (json['strokes'] as List)
        .map((s) => BoardStroke.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    final rawPages = json['pages'];
    final pages = rawPages is List && rawPages.isNotEmpty
        ? rawPages
              .map(
                (page) => (page as List)
                    .map(
                      (s) => BoardStroke.fromJson(Map<String, dynamic>.from(s)),
                    )
                    .toList(),
              )
              .toList()
        : <List<BoardStroke>>[strokes];
    final active = ((json['activePage'] as num?)?.toInt() ?? 0).clamp(
      0,
      pages.length - 1,
    );
    return WhiteboardDocument(
      strokes: pages[active],
      pages: pages,
      activePage: active,
      documents: List<String>.from(json['documents'] ?? []),
      questions: (json['questions'] as List? ?? [])
          .map((q) => Question.fromMap(Map<String, dynamic>.from(q)))
          .toList(),
      split: ((json['split'] as num?)?.toDouble() ?? 0.42).clamp(0.2, 0.8),
      documentAbove: json['documentAbove'] != false,
      grid: json['grid'] != false,
    );
  }
}

/// Clear is undoable as a whole operation, alongside strokes and eraser marks.
class WhiteboardController extends ChangeNotifier {
  List<BoardStroke> _strokes = [];
  final List<List<BoardStroke>> _undo = [];
  final List<List<BoardStroke>> _redo = [];

  List<BoardStroke> get strokes => List.unmodifiable(_strokes);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void restore(List<BoardStroke> strokes) {
    _strokes = List.of(strokes);
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }

  void add(BoardStroke stroke) {
    if (stroke.points.isEmpty) return;
    _snapshot();
    _strokes.add(stroke);
    notifyListeners();
  }

  /// 多笔粘贴、移动和删除作为单次撤销操作。
  void replace(List<BoardStroke> strokes) {
    _snapshot();
    _strokes = List.of(strokes);
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _snapshot();
    _strokes.clear();
    notifyListeners();
  }

  void _snapshot() {
    _undo.add(List.of(_strokes));
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(List.of(_strokes));
    _strokes = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(List.of(_strokes));
    _strokes = _redo.removeLast();
    notifyListeners();
  }
}
