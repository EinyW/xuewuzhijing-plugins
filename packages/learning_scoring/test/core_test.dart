import 'package:flutter_test/flutter_test.dart';
import 'package:learning_scoring/learning_scoring.dart';
void main() { test('standalone core behavior', () { expect(const ScoringProfile().questionCap, greaterThan(0)); }); }
