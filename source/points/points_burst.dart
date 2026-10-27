import 'package:flutter/material.dart';

import '../models/points.dart';
import '../models/scoring_profile.dart';
import '../services/scoring_service.dart';

/// 答题页 AppBar 里的实时积分（红框位置）。
///
/// 数值变化时滚动增长；旁边显示本次操作的倍率。
class AppBarScore extends StatefulWidget {
  final int points;

  /// 最近一次的倍率（没有则显示 ×1.0）
  final double multiplier;

  /// 挑战模式：当前连对题数
  final int streak;

  /// 是否挑战模式
  final bool challenge;

  const AppBarScore({
    super.key,
    required this.points,
    this.multiplier = 1,
    this.streak = 0,
    this.challenge = false,
  });

  @override
  State<AppBarScore> createState() => _AppBarScoreState();
}

class _AppBarScoreState extends State<AppBarScore> {
  late int _from;
  late int _to;
  bool _pulse = false;

  @override
  void initState() {
    super.initState();
    _from = 0;
    _to = widget.points;
  }

  @override
  void didUpdateWidget(covariant AppBarScore old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points) {
      _from = old.points;
      _to = widget.points;
      _pulse = true;
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _pulse = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? Colors.amber[300]! : Colors.amber[800]!;

    return TweenAnimationBuilder<double>(
      key: ValueKey(_to),
      tween: Tween(begin: _from.toDouble(), end: _to.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final shown = value.round();
        return AnimatedScale(
          scale: _pulse ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, size: 16, color: accent),
                const SizedBox(width: 2),
                Text(
                  '$shown',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (widget.challenge && widget.streak > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '连对 ${widget.streak}',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange[800],
                    ),
                  ),
                ] else if ((widget.multiplier - 1).abs() > .01) ...[
                  const SizedBox(width: 4),
                  Text(
                    '×${widget.multiplier.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.0,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 仿 COD 的得分弹层：总倍率 + 大字加分 + 逐条花式得分。
///
/// 从 AppBar 积分的位置向下弹出，2.4 秒后自动消失。
class PointsBurstOverlay extends StatefulWidget {
  final PointsAward award;

  /// AppBar 积分控件的全局位置与尺寸（弹层的锚点）
  final Offset anchor;
  final Size anchorSize;
  final VoidCallback onDone;
  final ScoringProfile? profile;

  const PointsBurstOverlay({
    super.key,
    required this.award,
    required this.anchor,
    required this.anchorSize,
    required this.onDone,
    this.profile,
  });

  @override
  State<PointsBurstOverlay> createState() => _PointsBurstOverlayState();
}

class _PointsBurstOverlayState extends State<PointsBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final ScoringProfile _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.profile ?? ScoringService.instance.profile.value;
    _c =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: _settings.displayMs),
          )
          ..forward()
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) widget.onDone();
          });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end) => CurvedAnimation(
    parent: _c,
    curve: Interval(begin, end, curve: Curves.easeOutCubic),
  );

  @override
  Widget build(BuildContext context) {
    final award = widget.award;
    final hits = award.hits.take(8).toList();
    final accent = Color(_settings.colorValue);
    final screen = MediaQuery.sizeOf(context);
    final estimatedHeight =
        40 +
        _settings.fontSize +
        (hits.length + 1) * (_settings.detailFontSize * 1.5 + 2);
    final top = (widget.anchor.dy + widget.anchorSize.height + 6).clamp(
      8.0,
      (screen.height - estimatedHeight - 8).clamp(8.0, double.infinity),
    );

    // 内容出现在 AppBar 积分下方，右对齐屏幕右侧
    return Positioned(
      top: top,
      right: 10,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // 整体：0-0.12 淡入放大，0.9-1.0 淡出
            final opacity = _c.value < 0.12
                ? _c.value / 0.12
                : (_c.value > 0.9 ? (1 - _c.value) / 0.1 : 1.0);
            final scale = 0.92 + 0.08 * _interval(0, 0.16).value;

            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topRight,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: (screen.height - top - 8).clamp(
                      1.0,
                      double.infinity,
                    ),
                  ),
                  width: (MediaQuery.sizeOf(context).width - 20).clamp(
                    160.0,
                    360.0,
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xEE101223), Color(0xF21A1430)],
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 第一行：总倍率 + 大字加分 + 已得分
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if ((award.multiplier - 1).abs() > .01)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text(
                                    '×${award.multiplier.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                '+${award.points}',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: _settings.fontSize,
                                  height: 1.0,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: accent.withValues(alpha: 0.6),
                                      blurRadius: 14,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '已得分',
                                  style: TextStyle(
                                    color: accent.withValues(alpha: 0.95),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hits.isNotEmpty) const SizedBox(height: 6),
                        // 逐条花式得分，依次滑入
                        ...List.generate(hits.length, (i) {
                          final start = 0.08 + i * 0.06;
                          final a = _interval(
                            start,
                            (start + 0.12).clamp(0.0, 1.0),
                          );
                          return ClipRect(
                            child: Transform.translate(
                              offset: Offset(24 * (1 - a.value), 0),
                              child: Opacity(
                                opacity: a.value,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: _hitLine(hits[i], accent),
                                ),
                              ),
                            ),
                          );
                        }),
                        if (award.hits.length > hits.length)
                          Text(
                            '另 ${award.hits.length - hits.length} 项加成',
                            style: TextStyle(
                              color: accent,
                              fontSize: _settings.detailFontSize,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _hitLine(PointsHit hit, Color accent) {
    final effects = <String>[
      if ((hit.multiplier - 1).abs() > .001)
        '×${hit.multiplier.toStringAsFixed(2)}',
      if (hit.bonus > 0) '+${hit.bonus}',
    ];
    final mult = effects.isEmpty ? '×1.00' : effects.join('  ');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mult,
            style: TextStyle(
              color: Colors.white,
              fontSize: _settings.detailFontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            hit.label,
            style: TextStyle(
              color: accent,
              fontSize: _settings.detailFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 在 [anchorKey] 下方弹出一次得分动画。
///
/// 返回移除函数，调用方可提前移除（例如页面销毁）。
VoidCallback? showPointsBurst({
  required BuildContext context,
  required GlobalKey anchorKey,
  required PointsAward award,
  ScoringProfile? profile,
}) {
  final settings = profile ?? ScoringService.instance.profile.value;
  if (award.points <= 0 || !settings.showPopup) return null;
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (box == null || overlay == null) return null;

  final anchor = box.localToGlobal(Offset.zero);
  late OverlayEntry entry;
  var removed = false;

  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => PointsBurstOverlay(
      award: award,
      anchor: anchor,
      anchorSize: box.size,
      onDone: remove,
      profile: settings,
    ),
  );
  overlay.insert(entry);
  return remove;
}
