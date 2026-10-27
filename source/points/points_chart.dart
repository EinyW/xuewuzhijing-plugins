import 'dart:math';

import 'package:flutter/material.dart';

import '../models/points.dart';
import '../theme/app_theme.dart';

/// 轻量柱状图（自绘，不依赖第三方图表库）。
///
/// [buckets] 的 key 作为 x 轴标签，points 作为柱高。
/// 数值为 0 的柱子只画一个底座，避免像"断档"。
class PointsBarChart extends StatelessWidget {
  final List<PointsBucket> buckets;

  /// 每隔几个柱子显示一个 x 轴标签（30 天视图太密）
  final int labelEvery;

  /// 是否在柱子上显示数值（只标注最高的几根）
  final bool highlightMax;

  final double height;
  final Color? color;

  const PointsBarChart({
    super.key,
    required this.buckets,
    this.labelEvery = 1,
    this.highlightMax = true,
    this.height = 170,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('暂无数据',
              style: TextStyle(fontSize: 12, color: context.faintText)),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarChartPainter(
          buckets: buckets,
          labelEvery: labelEvery,
          highlightMax: highlightMax,
          barColor: color ?? context.scheme.primary,
          textColor: context.mutedText,
          faintColor: context.faintText,
          gridColor: context.subtleBorder,
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<PointsBucket> buckets;
  final int labelEvery;
  final bool highlightMax;
  final Color barColor;
  final Color textColor;
  final Color faintColor;
  final Color gridColor;

  _BarChartPainter({
    required this.buckets,
    required this.labelEvery,
    required this.highlightMax,
    required this.barColor,
    required this.textColor,
    required this.faintColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = buckets.fold<int>(0, (m, b) => max(m, b.points));
    // 给顶部留出数值标签空间
    const topPadding = 18.0;
    const bottomPadding = 20.0;
    final chartHeight = size.height - topPadding - bottomPadding;
    final n = buckets.length;
    if (n == 0 || chartHeight <= 0) return;

    final slot = size.width / n;
    final barWidth = min(slot * 0.62, 22.0);

    // 基线
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - bottomPadding),
      Offset(size.width, size.height - bottomPadding),
      gridPaint,
    );

    // 顶部参考线
    canvas.drawLine(
      const Offset(0, topPadding),
      Offset(size.width, topPadding),
      Paint()
        ..color = gridColor.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );

    final textPainterCache = <String, TextPainter>{};

    for (int i = 0; i < n; i++) {
      final b = buckets[i];
      final ratio = maxValue == 0 ? 0.0 : b.points / maxValue;
      final h = max(ratio * chartHeight, b.points > 0 ? 3.0 : 0.0);
      final x = slot * i + (slot - barWidth) / 2;
      final y = size.height - bottomPadding - h;

      if (h > 0) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(4),
        );
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              barColor,
              barColor.withValues(alpha: 0.55),
            ],
          ).createShader(rect.outerRect);
        canvas.drawRRect(rect, paint);
      } else {
        // 0 值底座
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - bottomPadding - 2, barWidth, 2),
            const Radius.circular(1),
          ),
          Paint()..color = gridColor,
        );
      }

      // 最高值标注
      if (highlightMax && b.points == maxValue && maxValue > 0) {
        final tp = _text('${b.points}', 10, barColor, FontWeight.w700);
        tp.layout();
        tp.paint(
          canvas,
          Offset(x + barWidth / 2 - tp.width / 2, y - tp.height - 3),
        );
      }

      // x 轴标签
      if (i % labelEvery == 0 || i == n - 1) {
        final label = _shortLabel(b.key);
        final tp = textPainterCache.putIfAbsent(
          label,
          () => _text(label, 9.5, faintColor, FontWeight.normal),
        );
        tp.layout();
        tp.paint(
          canvas,
          Offset(
            x + barWidth / 2 - tp.width / 2,
            size.height - bottomPadding + 5,
          ),
        );
      }
    }
  }

  /// yyyy-MM-dd -> MM/dd，yyyy-MM -> yy/MM
  String _shortLabel(String key) {
    if (key.length == 10) return key.substring(5).replaceAll('-', '/');
    if (key.length == 7) return key.substring(2).replaceAll('-', '/');
    return key;
  }

  TextPainter _text(
      String s, double size, Color color, FontWeight weight) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) {
    return old.buckets != buckets ||
        old.barColor != barColor ||
        old.labelEvery != labelEvery;
  }
}

/// 目标进度环
class PointsProgressRing extends StatelessWidget {
  final double progress;
  final String centerText;
  final String bottomText;
  final double size;
  final Color? color;

  const PointsProgressRing({
    super.key,
    required this.progress,
    required this.centerText,
    required this.bottomText,
    this.size = 108,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          color: c,
          trackColor: context.subtleBorder,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: c,
                ),
              ),
              Text(
                bottomText,
                style: TextStyle(fontSize: 10, color: context.faintText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (min(size.width, size.height) - stroke) / 2,
    );

    canvas.drawArc(
      rect,
      -pi / 2,
      pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -pi / 2,
      pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
