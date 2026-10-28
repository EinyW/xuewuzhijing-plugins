import 'package:flutter_test/flutter_test.dart';
import 'package:learning_words/learning_words.dart';
void main() { test('standalone core behavior', () { final w = Word(word: 'Apple', definitions: ['苹果']); expect(Word.fromMap(w.toMap()).normalized, 'apple'); }); }
