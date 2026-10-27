import 'package:flutter/material.dart';

import '../models/points.dart';
import '../services/points_service.dart';
import '../services/scoring_service.dart';
import '../theme/app_theme.dart';
import '../widgets/points_chart.dart';
import 'scoring_settings_screen.dart';

/// 积分中心：总分、段位、目标、趋势与往期数据
class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final _service = PointsService.instance;

  bool _loading = true;

  int _total = 0;
  int _streak = 0;
  Map<String, int> _summary = {};
  List<PointsBucket> _daily30 = [];
  List<PointsBucket> _monthly6 = [];
  List<PointsBucket> _byLabel = [];
  List<PointsEvent> _recent = [];
  PointsGoal? _goal;
  GoalCycleProgress? _goalProgress;
  List<PointsGoal> _goalHistory = [];

  /// 0=近30天 1=近半年 2=往期某月
  int _chartMode = 0;

  /// 往期选中的月份
  DateTime _historyMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// 选中月份每天的积分
  List<PointsBucket> _monthBuckets = [];
  bool _monthLoading = false;

  /// 区间汇总选中的键
  String _rangeKey = 'today';

  static const _rangeOptions = [
    ('today', '今日'),
    ('week', '近7天'),
    ('month', '近30天'),
    ('halfYear', '近半年'),
    ('all', '全部'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await ScoringService.instance.load();
    final now = DateTime.now();
    final total = await _service.totalPoints();
    final summary = await _service.summaryTotals();
    final streak = await _service.streakDays();
    final daily = await _service.dailyBuckets(
      from: now.subtract(const Duration(days: 29)),
      to: now,
    );
    final monthly = await _service.monthlyBuckets(months: 6);
    final byLabel = await _service.byLabel();
    final recent = await _service.recentEvents(limit: 20);
    final goal = await _service.currentGoal();
    final progress = goal == null ? null : await _service.goalProgress(goal);
    final history = await _service.goalHistory();

    if (!mounted) return;
    setState(() {
      _total = total;
      _summary = summary;
      _streak = streak;
      _daily30 = daily;
      _monthly6 = monthly;
      _byLabel = byLabel;
      _recent = recent;
      _goal = goal;
      _goalProgress = progress;
      _goalHistory = history;
      _loading = false;
    });
    await _loadMonth(_historyMonth);
  }

  /// 读取指定月份每天的数据（只在切换月份时查一次）
  Future<void> _loadMonth(DateTime month) async {
    if (!mounted) return;
    setState(() => _monthLoading = true);
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    final buckets = await _service.dailyBuckets(from: start, to: end);
    if (!mounted) return;
    setState(() {
      _monthBuckets = buckets;
      _monthLoading = false;
    });
  }

  PointsRank get _rank => PointsRank.of(_total);
  double get _rankProgress => PointsRank.progress(_total, _rank);

  Future<void> _editGoal() async {
    final targetCtrl = TextEditingController(
      text: _goal == null ? '${_total + 5000}' : '${_goal!.target}',
    );
    final daysCtrl = TextEditingController(text: '${_goal?.periodDays ?? 7}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_goal == null ? '设定目标' : '修改目标'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '可以按周期给自己定任务：每 N 天拿到 N 分，'
                '周期从保存时开始算，每个周期重新冲刺。'
                '填 0 天表示累计目标。当前累计 $_total 分。',
                style: TextStyle(fontSize: 12, color: ctx.mutedText),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '每周期目标积分',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [500, 1000, 3000, 5000]
                    .map(
                      (v) => ActionChip(
                        label: Text('$v'),
                        onPressed: () => targetCtrl.text = '$v',
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: daysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '周期天数（1~365，0 = 累计目标）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event_repeat),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children:
                    [
                          ('每天', 1),
                          ('7 天', 7),
                          ('14 天', 14),
                          ('30 天', 30),
                          ('累计', 0),
                        ]
                        .map(
                          (e) => ActionChip(
                            label: Text(e.$1),
                            onPressed: () => daysCtrl.text = '${e.$2}',
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final value = int.tryParse(targetCtrl.text.trim());
    var period = int.tryParse(daysCtrl.text.trim()) ?? 0;
    targetCtrl.dispose();
    daysCtrl.dispose();
    if (ok != true || value == null || value <= 0) return;
    if (period < 0) period = 0;
    if (period > 365) period = 365;
    await _service.setGoal(value, periodDays: period);
    await _load();
  }

  Future<void> _deleteGoal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除目标'),
        content: const Text('删除后当前进度不再显示，历史记录里的目标仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.clearGoal();
    await _load();
  }

  void _showGoalHistory() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '目标记录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _goalHistory.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('还没有设定过目标'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _goalHistory.length,
                      itemBuilder: (_, i) {
                        final g = _goalHistory[i];
                        final done = g.achieved;
                        return ListTile(
                          leading: Icon(
                            done ? Icons.emoji_events : Icons.flag_outlined,
                            color: done ? Colors.amber[700] : context.faintText,
                          ),
                          title: Text(
                            g.isPeriodic
                                ? '每 ${g.periodDays} 天 ${g.target} 分'
                                : '${g.target} 分',
                          ),
                          subtitle: Text(
                            '${_fmtDate(g.createdAt)} 设定'
                            '${g.isPeriodic ? ' · 周期目标' : ''}'
                            '${done ? ' · ${_fmtDate(g.achievedAt!)} 结束' : ' · 进行中'}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickHistoryMonth() async {
    final now = DateTime.now();
    final months = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return d;
    });

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择要查看的月份',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: months.length,
                itemBuilder: (_, i) {
                  final d = months[i];
                  return ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text('${d.year} 年 ${d.month} 月'),
                    trailing:
                        d.year == _historyMonth.year &&
                            d.month == _historyMonth.month
                        ? Icon(Icons.check, color: ctx.scheme.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, d),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _historyMonth = picked;
      _chartMode = 2;
    });
    await _loadMonth(picked);
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('积分中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '目标记录',
            onPressed: _showGoalHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _heroCard(),
                  const SizedBox(height: 14),
                  _goalCard(),
                  const SizedBox(height: 14),
                  _summaryCard(),
                  const SizedBox(height: 14),
                  _chartCard(),
                  const SizedBox(height: 14),
                  _labelRankCard(),
                  const SizedBox(height: 14),
                  _recentCard(),
                  const SizedBox(height: 14),
                  _rulesCard(),
                ],
              ),
            ),
    );
  }

  // ---------------- 顶部：总分 / 段位 / 连击 ----------------

  Widget _heroCard() {
    final scheme = context.scheme;
    final nextAt = _rank.nextAt;
    final remaining = nextAt == null ? 0 : (nextAt - _total).clamp(0, 1 << 30);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.28)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber[300], size: 20),
              const SizedBox(width: 6),
              Text(
                '段位 · ${_rank.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        color: Colors.orangeAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '连续 $_streak 天',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$_total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 46,
              height: 1.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '累计积分',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _rankProgress,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber[300]!),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nextAt == null ? '已达到最高段位，继续刷新自己的记录吧' : '距离下一段位还差 $remaining 分',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 目标 ----------------

  Widget _goalCard() {
    final goal = _goal;
    final cycle = _goalProgress;
    final achieved = goal == null
        ? false
        : (goal.isPeriodic
              ? (cycle?.achieved ?? false)
              : _total >= goal.target);
    final progress = goal == null
        ? 0.0
        : (goal.isPeriodic
              ? (cycle?.ratio ?? 0)
              : (_total / goal.target).clamp(0.0, 1.0));

    String title;
    String subtitle;
    if (goal == null) {
      title = '设定一个目标';
      subtitle = '按周期定量，或定一个累计目标';
    } else if (goal.isPeriodic) {
      title = achieved ? '本周期已达成 🎉' : '第 ${cycle?.cycleIndex ?? 1} 周期';
      subtitle =
          '每 ${goal.periodDays} 天 ${goal.target} 分 · '
          '本周期 ${cycle?.earned ?? 0} 分 · '
          '还剩 ${cycle?.daysLeft ?? goal.periodDays} 天';
      if ((cycle?.completedCycles ?? 0) > 0) {
        subtitle += ' · 已完成 ${cycle!.completedCycles} 个周期';
      }
    } else {
      title = achieved ? '目标已达成 🎉' : '当前目标';
      subtitle = '累计目标 ${goal.target} 分 · 已获得 $_total 分';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            PointsProgressRing(
              progress: progress,
              centerText: goal == null
                  ? '未设定'
                  : '${(progress * 100).toStringAsFixed(0)}%',
              bottomText: goal == null
                  ? '目标'
                  : (goal.isPeriodic
                        ? '${cycle?.earned ?? 0}/${goal.target}'
                        : '${goal.target} 分'),
              color: achieved ? Colors.amber[700] : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        achieved ? Icons.emoji_events : Icons.flag_outlined,
                        size: 18,
                        color: achieved ? Colors.amber[700] : context.mutedText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: context.mutedText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: _editGoal,
                        child: Text(goal == null ? '设定目标' : '修改'),
                      ),
                      if (goal != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _deleteGoal,
                          child: const Text('删除'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 区间汇总 ----------------

  Widget _summaryCard() {
    final value = _summary[_rangeKey] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.summarize_outlined,
                  size: 17,
                  color: context.mutedText,
                ),
                const SizedBox(width: 6),
                const Text(
                  '区间汇总',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '$value 分',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: _rangeOptions.map((o) {
                final selected = o.$1 == _rangeKey;
                return ChoiceChip(
                  label: Text(o.$2, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() => _rangeKey = o.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _miniStat('今日', _summary['today'] ?? 0),
                _miniStat('近7天', _summary['week'] ?? 0),
                _miniStat('近30天', _summary['month'] ?? 0),
                _miniStat('近半年', _summary['halfYear'] ?? 0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, int value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: context.faintText)),
        ],
      ),
    );
  }

  // ---------------- 图表 ----------------

  Widget _chartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, size: 17, color: context.mutedText),
                const SizedBox(width: 6),
                const Text(
                  '积分趋势',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_chartMode == 2)
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: Text(
                      '${_historyMonth.year}/${_historyMonth.month}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _pickHistoryMonth,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                _modeChip(0, '近30天'),
                _modeChip(1, '近半年'),
                _modeChip(2, '往期数据'),
              ],
            ),
            const SizedBox(height: 12),
            if (_chartMode == 0)
              PointsBarChart(buckets: _daily30, labelEvery: 5, height: 180)
            else if (_chartMode == 1)
              PointsBarChart(buckets: _monthly6, labelEvery: 1, height: 180)
            else
              _historyChart(),
            const SizedBox(height: 6),
            Text(
              _chartMode == 0
                  ? '最近 30 天每天获得的积分'
                  : _chartMode == 1
                  ? '最近 6 个月每月获得的积分'
                  : '选定月份每天获得的积分',
              style: TextStyle(fontSize: 11, color: context.faintText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(int mode, String label) {
    final selected = _chartMode == mode;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        if (mode == 2) {
          _pickHistoryMonth();
        } else {
          setState(() => _chartMode = mode);
        }
      },
    );
  }

  /// 往期：显示选中月份，数据在切换月份时已查好
  Widget _historyChart() {
    if (_monthLoading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final sum = _monthBuckets.fold<int>(0, (a, b) => a + b.points);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '当月合计 $sum 分',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        PointsBarChart(buckets: _monthBuckets, labelEvery: 5, height: 150),
      ],
    );
  }

  // ---------------- 得分方式排行 ----------------

  Widget _labelRankCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.whatshot, size: 17, color: context.mutedText),
                const SizedBox(width: 6),
                const Text(
                  '得分方式排行',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '连击、首杀、秒杀用得越多，排名越靠前',
              style: TextStyle(fontSize: 11, color: context.faintText),
            ),
            const SizedBox(height: 10),
            if (_byLabel.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '还没有得分记录，去做几道题吧',
                    style: TextStyle(fontSize: 12, color: context.faintText),
                  ),
                ),
              )
            else
              ..._byLabel.asMap().entries.map((e) {
                final i = e.key;
                final b = e.value;
                final maxPoints = _byLabel.first.points;
                final ratio = maxPoints == 0 ? 0.0 : b.points / maxPoints;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: i == 0
                                ? Colors.amber[800]
                                : context.faintText,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.key,
                              style: const TextStyle(fontSize: 12.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 5,
                                backgroundColor: context.subtleBorder,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${b.points} 分',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${b.count} 次',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: context.faintText,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ---------------- 最近获得 ----------------

  Widget _recentCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 17,
                  color: context.mutedText,
                ),
                const SizedBox(width: 6),
                const Text(
                  '最近获得',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${_recent.length} 条',
                  style: TextStyle(fontSize: 11, color: context.faintText),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    '暂无记录',
                    style: TextStyle(fontSize: 12, color: context.faintText),
                  ),
                ),
              )
            else
              ..._recent.take(12).map((e) {
                final isSession = e.eventType == 'session';
                final isSpend = e.eventType == 'spend';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSpend
                              ? Colors.red.withValues(alpha: 0.12)
                              : isSession
                              ? Colors.amber.withValues(alpha: 0.16)
                              : context.subtlePrimary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isSpend
                              ? Icons.remove_circle_outline
                              : isSession
                              ? Icons.emoji_events
                              : Icons.bolt,
                          size: 16,
                          color: isSpend
                              ? Colors.red
                              : isSession
                              ? Colors.amber[800]
                              : context.scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.label,
                              style: const TextStyle(fontSize: 12.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_fmtDate(e.createdAt)}'
                              '${e.elapsedMs > 0 ? ' · ${(e.elapsedMs / 1000).toStringAsFixed(1)}s' : ''}'
                              '${e.multiplier > 1 ? ' · ×${e.multiplier.toStringAsFixed(1)}' : ''}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: context.faintText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        isSpend ? '${e.points}' : '+${e.points}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSpend ? Colors.red : context.scheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ---------------- 规则说明 ----------------

  Widget _rulesCard() {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Icon(Icons.help_outline, size: 19, color: context.mutedText),
          title: const Text(
            '积分规则',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            ..._rules.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 130),
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.subtlePrimary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.$1,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: context.mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '不同组的规则可以叠加，同组只应用一条。'
                '当前方案「${ScoringService.instance.profile.value.name}」，'
                '全局倍率 ×${ScoringService.instance.profile.value.multiplier}，'
                '单题最高 ${ScoringService.instance.profile.value.questionCap} 分。',
                style: TextStyle(fontSize: 11, color: context.faintText),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '积分只增加，不会因为答错而扣除；连击会在答错时中断。'
              '所有积分保存在本机。',
              style: TextStyle(fontSize: 11, color: context.faintText),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ScoringSettingsScreen(),
                  ),
                );
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.tune),
              label: const Text('编辑花样积分'),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, String)> get _rules {
    final profile = ScoringService.instance.profile.value;
    const names = {
      'choice': '选择题',
      'multi_choice': '多选题',
      'fill_blank': '填空题',
      'long_text': '长文本题',
      'material': '材料题',
      'word': '词语测试',
    };
    return [
      ('得分率', '按本题得分比例结算，答对一半拿一半基础分'),
      for (final range in profile.baseRanges.entries)
        (
          names[range.key] ?? range.key,
          '随机基础分 ${range.value.$1}～${range.value.$2}',
        ),
      for (final rule in profile.rules.where((r) => r.enabled))
        (
          rule.name,
          [
            '倍率 ×${rule.multiplier}',
            if (rule.bonus > 0) '额外 +${rule.bonus}',
            if (rule.minCombo > 0) '连击 ≥ ${rule.minCombo}',
            if (rule.maxElapsedMs > 0) '用时 < ${rule.maxElapsedMs / 1000} 秒',
            if (rule.minRatio > 0)
              '得分率 ≥ ${(rule.minRatio * 100).toStringAsFixed(1)}%',
            if (rule.firstAttemptOnly) '首次作答',
            if (rule.previouslyWrongOnly) '曾经答错',
            if (rule.challengeOnly) '挑战模式',
            if (rule.materialOnly) '材料题',
            if (rule.excludeMaterial) '排除材料题',
            if (rule.questionType != null)
              names[rule.questionType] ?? rule.questionType!,
            if (rule.highRoll) '基础分达到区间 ${rule.highRollThreshold * 100}% 位置',
            if (rule.group.isNotEmpty) '互斥组 ${rule.group}',
          ].join(' · '),
        ),
      (
        profile.sessionLabel,
        '整局全对且不少于 ${profile.sessionMinimum} 题，'
            '奖励 ${profile.sessionBonus} + 题数 × ${profile.sessionPerQuestion}',
      ),
    ];
  }
}
