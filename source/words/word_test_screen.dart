import 'dart:math';

import 'package:flutter/material.dart';

import '../models/word.dart';
import '../services/plugin_service.dart';
import '../services/points_service.dart';
import '../services/word_service.dart';
import '../theme/app_theme.dart';

/// 词语测试方向
enum WordTestDirection {
  /// 看词选义
  wordToMeaning,

  /// 看义选词
  meaningToWord,
}

extension WordTestDirectionName on WordTestDirection {
  String get label => this == WordTestDirection.wordToMeaning ? '看词选义' : '看义选词';
  String get hint => this == WordTestDirection.wordToMeaning
      ? '选出正确的中文释义'
      : '选出对应的英文单词';
}

class _WordQuestion {
  final Word word;
  final String prompt;
  final String answer;
  final List<String> options;
  final int correctIndex;

  _WordQuestion({
    required this.word,
    required this.prompt,
    required this.answer,
    required this.options,
    required this.correctIndex,
  });
}

/// 词语收录本的「开始测试」。
///
/// 答错的词会自动把收录次数 +1（并在收录流水里记一条），
/// 强迫自己把不会的词再滚一遍。
class WordTestScreen extends StatefulWidget {
  final List<Word> words;
  final WordTestDirection direction;

  const WordTestScreen({
    super.key,
    required this.words,
    this.direction = WordTestDirection.wordToMeaning,
  });

  @override
  State<WordTestScreen> createState() => _WordTestScreenState();
}

class _WordTestScreenState extends State<WordTestScreen> {
  final _service = WordService();
  final _random = Random();

  late List<_WordQuestion> _questions;
  int _index = 0;
  int _correct = 0;
  int _earnedPoints = 0;
  int _selected = -1;
  bool _answered = false;
  bool _finished = false;
  final List<Word> _wrongWords = [];
  late WordTestDirection _direction;

  @override
  void initState() {
    super.initState();
    _direction = widget.direction;
    _questions = _buildQuestions(widget.words, _direction);
  }

  List<_WordQuestion> _buildQuestions(
      List<Word> words, WordTestDirection direction) {
    final usable = words.where((w) {
      if (direction == WordTestDirection.wordToMeaning) {
        return w.definitions.isNotEmpty;
      }
      return w.definitions.isNotEmpty && w.word.trim().isNotEmpty;
    }).toList()
      ..shuffle(_random);

    final questions = <_WordQuestion>[];
    for (final w in usable) {
      final answer = direction == WordTestDirection.wordToMeaning
          ? w.definitions.first
          : w.word;

      final pool = <String>{};
      for (final other in usable) {
        if (other.id == w.id) continue;
        final candidate = direction == WordTestDirection.wordToMeaning
            ? other.definitions.first
            : other.word;
        final value = candidate.trim();
        if (value.isNotEmpty && value != answer) pool.add(value);
      }

      // 最多 3 个干扰项；题库太小时就少给几个选项
      final distractors = pool.toList()..shuffle(_random);
      final options = <String>[answer, ...distractors.take(3)]..shuffle(_random);

      questions.add(_WordQuestion(
        word: w,
        prompt: direction == WordTestDirection.wordToMeaning
            ? w.word
            : w.definitions.first,
        answer: answer,
        options: options,
        correctIndex: options.indexOf(answer),
      ));
    }
    return questions;
  }

  Future<void> _pick(int i) async {
    if (_answered) return;
    final q = _questions[_index];
    final correct = i == q.correctIndex;

    setState(() {
      _selected = i;
      _answered = true;
      if (correct) {
        _correct++;
      } else {
        _wrongWords.add(q.word);
      }
    });

    if (!correct) {
      // 错词收录次数 +1，流水里标记来源为 test
      if (q.word.id != null) {
        await _service.bumpCollectCount(q.word.id!, source: 'test');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${q.word.word}」收录次数 +1'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (PluginService.instance.pointsEnabled) {
      // 词语测试答对：每题随机 10~15 积分
      final points =
          await PointsService.instance.awardWordTest(word: q.word.word);
      if (!mounted) return;
      _earnedPoints += points;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('答对「${q.word.word}」 +$points 积分'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _next() {
    if (!_answered) return;
    if (_index == _questions.length - 1) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _answered = false;
      _selected = -1;
    });
  }

  void _restartWrong() {
    if (_wrongWords.isEmpty) return;
    setState(() {
      _questions = _buildQuestions(
          List<Word>.of(_wrongWords), _direction);
      _index = 0;
      _correct = 0;
      _earnedPoints = 0;
      _wrongWords.clear();
      _selected = -1;
      _answered = false;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('词语测试')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 44, color: context.faintText),
                const SizedBox(height: 12),
                const Text('没有可用于测试的词语',
                    style: TextStyle(fontSize: 15)),
                const SizedBox(height: 6),
                Text(
                  '请先给词语填写释义（看词选义至少需要 2 个有释义的词）',
                  style: TextStyle(fontSize: 12, color: context.mutedText),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _finished
              ? '测试结果'
              : '词语测试 ${_index + 1}/${_questions.length}',
        ),
        bottom: _finished
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: (_index + (_answered ? 1 : 0)) /
                      _questions.length,
                  minHeight: 3,
                ),
              ),
      ),
      body: _finished ? _buildResult() : _buildQuestion(),
    );
  }

  Widget _buildQuestion() {
    final q = _questions[_index];
    final done = _answered;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Chip(
              label: Text(_direction.label,
                  style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            Text(
              _direction.hint,
              style: TextStyle(fontSize: 11.5, color: context.faintText),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: context.subtlePrimary,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
            child: Column(
              children: [
                Text(
                  q.prompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: q.prompt.length > 24 ? 20 : 28,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                ),
                if (_direction == WordTestDirection.wordToMeaning &&
                    (q.word.phonetic ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    q.word.phonetic!,
                    style: TextStyle(
                        fontSize: 13, color: context.mutedText),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(q.options.length, (i) {
          final option = q.options[i];
          final isCorrect = i == q.correctIndex;
          final isPicked = i == _selected;

          Color? bg;
          Color? border;
          if (done) {
            if (isCorrect) {
              bg = context.isDark
                  ? const Color(0xFF1E3A24)
                  : Colors.green[50];
              border = Colors.green;
            } else if (isPicked) {
              bg = context.isDark
                  ? const Color(0xFF3A1E1E)
                  : Colors.red[50];
              border = Colors.red;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: done ? null : () => _pick(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: bg ?? context.subtleSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: border ?? context.subtleBorder,
                    width: border != null ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: done && isCorrect
                          ? Colors.green
                          : done && isPicked
                              ? Colors.red
                              : context.subtlePrimary,
                      child: Text(
                        String.fromCharCode(65 + i),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: done && (isCorrect || isPicked)
                              ? Colors.white
                              : context.scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                    if (done && isCorrect)
                      const Icon(Icons.check_circle,
                          size: 19, color: Colors.green),
                    if (done && isPicked && !isCorrect)
                      const Icon(Icons.cancel, size: 19, color: Colors.red),
                  ],
                ),
              ),
            ),
          );
        }),
        if (done) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.subtleSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selected == q.correctIndex
                      ? '答对了'
                      : '答错了，正确答案：${q.answer}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _selected == q.correctIndex
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${q.word.word}${(q.word.phonetic ?? '').isEmpty ? '' : ' ${q.word.phonetic}'}'
                  ' · ${q.word.partOfSpeechLabel}',
                  style: TextStyle(fontSize: 12, color: context.mutedText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _next,
              child: Text(_index == _questions.length - 1
                  ? '查看结果'
                  : '下一题'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResult() {
    final total = _questions.length;
    final rate = total == 0 ? 0 : (_correct / total * 100).round();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 10),
        Center(
          child: Icon(
            rate >= 80
                ? Icons.emoji_events
                : rate >= 50
                    ? Icons.thumb_up_alt_outlined
                    : Icons.school_outlined,
            size: 64,
            color: rate >= 80 ? Colors.amber[700] : context.scheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '$_correct / $total',
            style: const TextStyle(
                fontSize: 34, fontWeight: FontWeight.bold),
          ),
        ),
        Center(
          child: Text(
            '正确率 $rate%',
            style: TextStyle(fontSize: 13, color: context.mutedText),
          ),
        ),
        if (PluginService.instance.pointsEnabled && _earnedPoints > 0) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              '本次获得 +$_earnedPoints 积分',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.amber[800],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_wrongWords.isEmpty)
          Center(
            child: Text('全部答对，状态不错 🎉',
                style: TextStyle(fontSize: 14, color: context.mutedText)),
          )
        else ...[
          const Text('答错的词（收录次数已 +1）',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._wrongWords.map((w) => Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.refresh, size: 18),
                  title: Text(w.word,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(w.primaryDefinition,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5)),
                  trailing: Text('${w.collectCount + 1} 次',
                      style: TextStyle(
                          fontSize: 11, color: context.faintText)),
                ),
              )),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _restartWrong,
              icon: const Icon(Icons.replay),
              label: Text('再测这些错词（${_wrongWords.length}）'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ),
      ],
    );
  }
}
