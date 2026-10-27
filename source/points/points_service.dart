import 'dart:math';

import '../db/app_database.dart';
import '../models/points.dart';
import '../models/question.dart';
import '../models/scoring_profile.dart';
import 'plugin_service.dart';
import 'scoring_service.dart';

/// 积分规则与数据查询。
///
/// 设计参考射击游戏里的"击杀方式不同得分不同"：
/// 基础分按题型给，再叠加首杀、连击、极速、复仇、满分等倍率与奖励，
/// 倍率可以叠乘，所以一次漂亮的操作能拿到远超基础分的积分。
class PointsService {
  PointsService._();
  static final PointsService instance = PointsService._();

  final _db = AppDatabase.instance;
  final _random = Random();

  /// 单题积分上限。材料题基础分最高 4000，再叠加首杀/连击/挑战倍率，
  /// 上限放宽到 20 万分，避免高分题被硬截断。
  static const int perQuestionCap = 200000;

  /// 挑战模式入场费
  static const int challengeEntryCost = 5000;

  /// 挑战模式基础倍率
  static const double challengeBaseMultiplier = 1.2;

  /// 各题型的基础分区间（1.1.2 起每题随机）
  ///
  /// 选择题 50~100、多选 100~130、填空 100~180、
  /// 长文本 550~1550、材料题 2000~4000。
  static (int, int) baseRangeFor(Question q) {
    return ScoringService.instance.profile.value.rangeFor(q);
  }

  /// 给这道题随机一个基础分（含区间两端）
  int rollBase(Question q) {
    final range = baseRangeFor(q);
    return range.$1 + _random.nextInt(range.$2 - range.$1 + 1);
  }

  /// 兼容旧接口：返回区间中位数（不作为实际得分依据）
  static int baseFor(Question q) {
    final range = baseRangeFor(q);
    return ((range.$1 + range.$2) / 2).round();
  }

  /// 挑战模式连对倍率：1.1 的 (1.1^连对数) 次方，上限 5 倍。
  ///
  /// x=1 → 1.11，x=10 → 约 1.28，x=20 → 约 1.92，x=30 封顶 5.0。
  static double challengeComboMultiplier(int combo) {
    if (combo <= 0) return 1.0;
    final exponent = pow(1.1, combo.toDouble());
    final value = pow(1.1, exponent).toDouble();
    return value > 5.0 ? 5.0 : value;
  }

  String _todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// 计算一次作答应得多少积分（不写库）。
  ///
  /// [score] 本次得分，[combo] 当前连击数（含本次），
  /// [firstAttempt] 该题第一次作答，[previouslyWrong] 之前做错过。
  /// [challenge] 为 true 时套用挑战模式：基础分 ×1.2 + 连对指数倍率。
  PointsAward calculateAward({
    required Question question,
    required double score,
    required int combo,
    required int elapsedMs,
    required bool firstAttempt,
    required bool previouslyWrong,
    bool challenge = false,
    int? basePoints,
    double? challengeMultiplier,
    double? challengeComboFactor,
  }) {
    final settings = ScoringService.instance.profile.value;
    final base = basePoints ?? rollBase(question);
    final total = question.totalScore;
    final ratio = total <= 0 ? 0.0 : (score / total).clamp(0.0, 1.0);

    // 没拿到分就没有积分（也不会打断其它逻辑）
    if (ratio <= 0) {
      return PointsAward(
        points: 0,
        basePoints: 0,
        multiplier: 1,
        bonusPoints: 0,
        hits: [],
      );
    }

    final hits = <PointsHit>[];
    double multiplier = settings.multiplier;
    int bonus = 0;

    // 挑战模式：基础分整体 ×1.2
    if (challenge) {
      final factor = challengeMultiplier ?? challengeBaseMultiplier;
      hits.add(PointsHit(label: '挑战加成', multiplier: factor));
      multiplier *= factor;
    }

    // 独立积分方案中的花式规则。连击和速度组各选择最合适的一条。
    final range = baseRangeFor(question);
    final matching = settings.rules
        .where(
          (rule) => rule.matches(
            question: question,
            combo: combo,
            ratio: ratio,
            elapsedMs: elapsedMs,
            firstAttempt: firstAttempt,
            previouslyWrong: previouslyWrong,
            challenge: challenge,
            basePoints: base,
            range: range,
          ),
        )
        .toList();
    final grouped = <String, ScoringRule>{};
    for (final rule in matching.where((r) => r.group.isNotEmpty)) {
      final previous = grouped[rule.group];
      if (previous == null ||
          (rule.group == 'speed'
              ? (rule.maxElapsedMs > 0 &&
                    (previous.maxElapsedMs == 0 ||
                        rule.maxElapsedMs < previous.maxElapsedMs))
              : rule.minCombo > previous.minCombo)) {
        grouped[rule.group] = rule;
      }
    }
    for (final rule in matching) {
      if (rule.group.isNotEmpty && grouped[rule.group] != rule) continue;
      hits.add(
        PointsHit(
          label: rule.name,
          multiplier: rule.multiplier,
          bonus: rule.bonus,
        ),
      );
      multiplier = min(multiplier * rule.multiplier, 1e12);
      bonus += rule.bonus;
    }
    // 外部插件声明的额外得分规则（只有积分插件开启时才生效）
    for (final rule in PluginService.instance.activeScoreRules) {
      if (!rule.matches(
        question: question,
        combo: combo,
        ratio: ratio,
        elapsedMs: elapsedMs,
        firstAttempt: firstAttempt,
        challenge: challenge,
      )) {
        continue;
      }
      hits.add(
        PointsHit(
          label: rule.label,
          multiplier: rule.multiplier,
          bonus: rule.bonus,
        ),
      );
      multiplier = min(multiplier * rule.multiplier, 1e12);
      bonus += rule.bonus;
    }

    // 挑战模式：连对指数倍率
    if (challenge && combo > 0) {
      final m = challengeComboFactor ?? challengeComboMultiplier(combo);
      if (m > 1.001) {
        hits.add(PointsHit(label: '挑战连对 $combo', multiplier: m));
        multiplier *= m;
      }
    }

    var points = (base * ratio * multiplier).round() + bonus;
    points = min(points, settings.questionCap);

    return PointsAward(
      points: points,
      basePoints: base,
      multiplier: multiplier,
      bonusPoints: bonus,
      hits: hits,
    );
  }

  /// 写入一次答题积分
  Future<PointsAward> awardForQuestion({
    required Question question,
    required double score,
    required int combo,
    required int elapsedMs,
    required bool firstAttempt,
    required bool previouslyWrong,
    String? sessionId,
    bool challenge = false,
    double? challengeMultiplier,
    double? challengeComboFactor,
  }) async {
    await ScoringService.instance.load();
    final award = calculateAward(
      question: question,
      score: score,
      combo: combo,
      elapsedMs: elapsedMs,
      firstAttempt: firstAttempt,
      previouslyWrong: previouslyWrong,
      challenge: challenge,
      challengeMultiplier: challengeMultiplier,
      challengeComboFactor: challengeComboFactor,
    );
    if (award.isEmpty) return award;

    final now = DateTime.now();
    final label = award.hits.isEmpty
        ? '答对'
        : award.hits.map((h) => h.label).join(' · ');

    final event = PointsEvent(
      questionId: question.id,
      questionType: question.type.dbValue,
      eventType: 'answer',
      label: label,
      basePoints: award.basePoints,
      multiplier: award.multiplier,
      bonusPoints: award.bonusPoints,
      points: award.points,
      combo: combo,
      elapsedMs: elapsedMs,
      sessionId: sessionId,
      dayKey: _todayKey(now),
      createdAt: now.toIso8601String(),
    );
    final id = await _db.insert('points_events', event.toMap()..remove('id'));
    await _checkGoal();
    return PointsAward(
        points: award.points,
        basePoints: award.basePoints,
        multiplier: award.multiplier,
        bonusPoints: award.bonusPoints,
        hits: award.hits,
      )
      ..event = PointsEvent(
        id: id,
        questionId: event.questionId,
        questionType: event.questionType,
        eventType: event.eventType,
        label: event.label,
        basePoints: event.basePoints,
        multiplier: event.multiplier,
        bonusPoints: event.bonusPoints,
        points: event.points,
        combo: event.combo,
        elapsedMs: event.elapsedMs,
        sessionId: event.sessionId,
        dayKey: event.dayKey,
        createdAt: event.createdAt,
      );
  }

  /// 整局结算奖励：全对一局有额外加分
  Future<PointsAward> awardSessionBonus({
    required int correctCount,
    required int totalCount,
    required String? sessionId,
  }) async {
    await ScoringService.instance.load();
    final settings = ScoringService.instance.profile.value;
    if (correctCount < settings.sessionMinimum || correctCount != totalCount) {
      return PointsAward(
        points: 0,
        basePoints: 0,
        multiplier: 1,
        bonusPoints: 0,
        hits: [],
      );
    }

    // 题数越多奖励越高
    final bonus =
        settings.sessionBonus + totalCount * settings.sessionPerQuestion;
    final label = '${settings.sessionLabel}（$correctCount/$totalCount）';
    final now = DateTime.now();

    final event = PointsEvent(
      eventType: 'session',
      label: label,
      basePoints: 0,
      multiplier: 1,
      bonusPoints: bonus,
      points: bonus,
      combo: correctCount,
      sessionId: sessionId,
      dayKey: _todayKey(now),
      createdAt: now.toIso8601String(),
    );
    await _db.insert('points_events', event.toMap()..remove('id'));
    await _checkGoal();

    return PointsAward(
      points: bonus,
      basePoints: 0,
      multiplier: 1,
      bonusPoints: bonus,
      hits: [PointsHit(label: label, bonus: bonus)],
    );
  }

  /// 词语测试答对：每题随机 10~15 分
  Future<int> awardWordTest({String? word}) async {
    await ScoringService.instance.load();
    final settings = ScoringService.instance.profile.value;
    final range = settings.baseRanges['word']!;
    final base = range.$1 + _random.nextInt(range.$2 - range.$1 + 1);
    final points = min(
      (base * settings.multiplier).round(),
      settings.questionCap,
    );
    final now = DateTime.now();
    await _db.insert(
      'points_events',
      PointsEvent(
        eventType: 'word_test',
        label: word == null ? '词语测试' : '词语测试 · $word',
        basePoints: base,
        multiplier: settings.multiplier,
        points: points,
        dayKey: _todayKey(now),
        createdAt: now.toIso8601String(),
      ).toMap()..remove('id'),
    );
    await _checkGoal();
    return points;
  }

  /// 挑战模式等场景消耗积分。
  /// 返回 false 表示余额不足（不会写任何记录）。
  Future<bool> spend(int points, String label) async {
    if (points <= 0) return true;
    final total = await totalPoints();
    if (total < points) return false;

    final now = DateTime.now();
    await _db.insert(
      'points_events',
      PointsEvent(
        eventType: 'spend',
        label: label,
        points: -points,
        dayKey: _todayKey(now),
        createdAt: now.toIso8601String(),
      ).toMap()..remove('id'),
    );
    return true;
  }

  // ---------------- 查询 ----------------

  Future<int> totalPoints() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(points), 0) AS t FROM points_events',
      [],
    );
    return ((rows.first['t'] as num?) ?? 0).toInt();
  }

  Future<int> pointsBetween(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(points), 0) AS t FROM points_events '
      'WHERE created_at >= ? AND created_at < ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return ((rows.first['t'] as num?) ?? 0).toInt();
  }

  /// 今日 / 近7天 / 近30天 / 近半年 / 全部
  Future<Map<String, int>> summaryTotals() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final all = await totalPoints();
    return {
      'today': await pointsBetween(
        startOfToday,
        startOfToday.add(const Duration(days: 1)),
      ),
      'week': await pointsBetween(
        now.subtract(const Duration(days: 7)),
        now.add(const Duration(minutes: 1)),
      ),
      'month': await pointsBetween(
        now.subtract(const Duration(days: 30)),
        now.add(const Duration(minutes: 1)),
      ),
      'halfYear': await pointsBetween(
        now.subtract(const Duration(days: 182)),
        now.add(const Duration(minutes: 1)),
      ),
      'all': all,
    };
  }

  /// 某段时间内每天的积分（缺的天补 0），用于柱状图
  Future<List<PointsBucket>> dailyBuckets({
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final rows = await _db.rawQuery(
      'SELECT day_key, SUM(points) AS t, COUNT(*) AS c FROM points_events '
      'GROUP BY day_key',
      [],
    );
    final map = <String, PointsBucket>{};
    for (final r in rows) {
      final key = r['day_key'] as String;
      map[key] = PointsBucket(
        key: key,
        points: ((r['t'] as num?) ?? 0).toInt(),
        count: ((r['c'] as num?) ?? 0).toInt(),
      );
    }

    final result = <PointsBucket>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final key = _todayKey(d);
      result.add(map[key] ?? PointsBucket(key: key, points: 0));
    }
    return result;
  }

  /// 近 N 个月每月的积分（缺的月补 0）
  Future<List<PointsBucket>> monthlyBuckets({int months = 6}) async {
    final now = DateTime.now();
    final rows = await _db.rawQuery(
      "SELECT substr(day_key, 1, 7) AS m, SUM(points) AS t, COUNT(*) AS c "
      'FROM points_events GROUP BY m',
      [],
    );
    final map = <String, PointsBucket>{};
    for (final r in rows) {
      final key = r['m'] as String;
      map[key] = PointsBucket(
        key: key,
        points: ((r['t'] as num?) ?? 0).toInt(),
        count: ((r['c'] as num?) ?? 0).toInt(),
      );
    }

    final result = <PointsBucket>[];
    for (int i = months - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      result.add(map[key] ?? PointsBucket(key: key, points: 0));
    }
    return result;
  }

  /// 按得分方式聚合（首杀、连击、秒杀…），用于"最擅长的方式"排行。
  /// 消耗（挑战模式入场费）不算得分方式，排除掉。
  Future<List<PointsBucket>> byLabel({int limit = 8}) async {
    final rows = await _db.rawQuery(
      "SELECT label, SUM(points) AS t, COUNT(*) AS c FROM points_events "
      "WHERE event_type != 'spend' "
      'GROUP BY label ORDER BY t DESC LIMIT ?',
      [limit],
    );
    return rows
        .map(
          (r) => PointsBucket(
            key: r['label'] as String,
            points: ((r['t'] as num?) ?? 0).toInt(),
            count: ((r['c'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  Future<List<PointsEvent>> recentEvents({int limit = 30}) async {
    final rows = await _db.query(
      'points_events',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(PointsEvent.fromMap).toList();
  }

  /// 连续有积分的天数
  Future<int> streakDays() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT day_key FROM points_events ORDER BY day_key DESC',
      [],
    );
    if (rows.isEmpty) return 0;
    final keys = rows.map((r) => r['day_key'] as String).toList();

    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    // 今天还没做题时，从昨天开始算连击
    if (keys.first != _todayKey(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    int streak = 0;
    final set = keys.toSet();
    while (set.contains(_todayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ---------------- 目标 ----------------

  Future<PointsGoal?> currentGoal() async {
    final rows = await _db.query(
      'points_goals',
      where: 'achieved_at IS NULL',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PointsGoal.fromMap(rows.first);
  }

  Future<List<PointsGoal>> goalHistory() async {
    final rows = await _db.query('points_goals', orderBy: 'created_at DESC');
    return rows.map(PointsGoal.fromMap).toList();
  }

  /// 设置新目标（会先把未达成的旧目标标记为已结束）
  ///
  /// [periodDays] 为 0 表示旧的"累计目标"；大于 0 表示每 N 天一个周期，
  /// 每个周期都要重新冲刺 [target] 分。
  Future<void> setGoal(int target, {String? title, int periodDays = 0}) async {
    final now = DateTime.now().toIso8601String();
    final current = await currentGoal();
    if (current != null) {
      // 未达成但被新目标取代，直接标记时间，历史里仍可看到
      await _db.update(
        'points_goals',
        {'achieved_at': now},
        where: 'id = ?',
        whereArgs: [current.id],
      );
    }
    final db = await _db.database;
    await db.insert('points_goals', {
      'target': target,
      'title': title,
      'period_days': periodDays,
      'created_at': now,
    });
    await _checkGoal();
  }

  Future<void> clearGoal() async {
    final current = await currentGoal();
    if (current == null) return;
    await _db.delete('points_goals', where: 'id = ?', whereArgs: [current.id]);
  }

  /// 计算目标的当前进度。
  ///
  /// 周期目标：按 created_at 起算，每 [periodDays] 天一个周期，
  /// 统计当前周期内获得的积分，并数出已经达标的周期数。
  Future<GoalCycleProgress> goalProgress(PointsGoal goal) async {
    final now = DateTime.now();

    if (!goal.isPeriodic) {
      final earned = await totalPoints();
      return GoalCycleProgress(
        cycleIndex: 1,
        earned: earned,
        target: goal.target,
        start: DateTime.tryParse(goal.createdAt) ?? now,
        end: now,
        completedCycles: earned >= goal.target ? 1 : 0,
      );
    }

    final created = DateTime.tryParse(goal.createdAt) ?? now;
    final period = Duration(days: goal.periodDays);
    var elapsed = now.difference(created);
    if (elapsed.isNegative) elapsed = Duration.zero;
    final cycleIndex = elapsed.inMicroseconds ~/ period.inMicroseconds;

    final start = created.add(period * cycleIndex);
    final end = start.add(period);
    final earned = await pointsBetween(
      start,
      now.isBefore(end) ? now.add(const Duration(minutes: 1)) : end,
    );

    // 统计已经达标的周期（最多回看 60 个，避免目标放太久）
    var completed = 0;
    final lookback = cycleIndex > 60 ? 60 : cycleIndex;
    for (int i = 0; i < lookback; i++) {
      final s = created.add(period * i);
      final e = s.add(period);
      final p = await pointsBetween(s, e);
      if (p >= goal.target) completed++;
    }

    return GoalCycleProgress(
      cycleIndex: cycleIndex + 1,
      earned: earned,
      target: goal.target,
      start: start,
      end: end,
      completedCycles: completed,
    );
  }

  /// 达标后自动标记（只对累计目标生效；周期目标一直保留）
  Future<void> _checkGoal() async {
    final goal = await currentGoal();
    if (goal == null || goal.isPeriodic) return;
    final total = await totalPoints();
    if (total >= goal.target) {
      await _db.update(
        'points_goals',
        {'achieved_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [goal.id],
      );
    }
  }

  /// 清空积分（设置里的"重置积分数据"会用到）
  Future<void> resetAll() async {
    await _db.rawDelete('DELETE FROM points_events', []);
    await _db.rawDelete('DELETE FROM points_goals', []);
  }
}
