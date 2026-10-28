import 'package:flutter_test/flutter_test.dart';
import 'package:learning_challenge/learning_challenge.dart';
void main() { test('standalone core behavior', () { const r = ChallengeRules(maxMistakes: 2); expect(r.passed(percent: 90, mistakes: 2), isFalse); expect(r.comboMultiplier(10000), r.comboCap); }); }
