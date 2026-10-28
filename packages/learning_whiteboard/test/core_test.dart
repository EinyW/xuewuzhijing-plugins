import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';
import 'package:learning_whiteboard/learning_whiteboard.dart';
void main() { test('standalone core behavior', () { final c = WhiteboardController(); c.add(BoardStroke(points: [const Offset(.1,.1)])); c.undo(); expect(c.strokes, isEmpty); c.redo(); expect(c.strokes.length, 1); c.dispose(); }); }
