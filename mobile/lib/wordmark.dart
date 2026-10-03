import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// EXPENZA wordmark'ı (expenza-wordmark.svg ile aynı çizgiler, 610×100 birim).
///
/// [animate] açıkken harfler soldan sağa sırayla "çizilir" (web sitesindeki
/// açılışla aynı). Küçük boyutta çizgi kalınlaştırılır; dosyadaki 1,8 birimlik
/// çizgi 20 px yükseklikte görünmez kalır.
class ExpenzaWordmark extends StatefulWidget {
  final double height;
  final Color? color;
  final bool animate;
  final Duration duration;
  final Duration delay;

  /// Çizgi kalınlığı (mantıksal piksel). Boşsa boyuta göre seçilir.
  final double? strokeWidth;

  const ExpenzaWordmark({
    super.key,
    this.height = 20,
    this.color,
    this.animate = false,
    this.duration = const Duration(milliseconds: 1600),
    this.delay = Duration.zero,
    this.strokeWidth,
  });

  @override
  State<ExpenzaWordmark> createState() => _ExpenzaWordmarkState();
}

class _ExpenzaWordmarkState extends State<ExpenzaWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.animate ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      Future.delayed(widget.delay, () {
        if (!mounted) return;
        final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        reduce ? _c.value = 1 : _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final stroke = widget.strokeWidth ??
        (h < 40 ? 1.4 : (h * 0.018).clamp(1.4, 6.0).toDouble());
    return Semantics(
      label: 'Expenza',
      image: true,
      child: SizedBox(
        height: h,
        width: h * 6.1,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _WordmarkPainter(
              progress: _c.value,
              color: widget.color ?? AppColors.onSurface,
              strokePx: stroke,
            ),
          ),
        ),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokePx;
  _WordmarkPainter(
      {required this.progress, required this.color, required this.strokePx});

  static final List<Path> _strokes = _build();

  static List<Path> _build() {
    Path e(double dx) => Path()
      ..moveTo(dx + 56, 4)
      ..lineTo(dx + 2, 4)
      ..lineTo(dx + 2, 88)
      ..lineTo(dx + 56, 88);
    Path bar(double dx, double y, double x1, double x2) => Path()
      ..moveTo(dx + x1, y)
      ..lineTo(dx + x2, y);
    Path line(double dx, double x1, double y1, double x2, double y2) => Path()
      ..moveTo(dx + x1, y1)
      ..lineTo(dx + x2, y2);
    return [
      e(0),
      bar(0, 46, 2, 44),
      line(80, 2, 4, 32, 39),
      line(80, 70, 4, 39, 39),
      line(80, 39, 48, 70, 88),
      line(80, 32, 48, 2, 88),
      Path()
        ..moveTo(174 + 2, 88)
        ..lineTo(174 + 2, 4)
        ..lineTo(174 + 28, 4)
        ..cubicTo(174 + 68, 4, 174 + 68, 47, 174 + 28, 47)
        ..lineTo(174 + 2, 47),
      e(266),
      bar(266, 46, 2, 44),
      Path()
        ..moveTo(348 + 2, 88)
        ..lineTo(348 + 2, 4)
        ..lineTo(348 + 66, 88)
        ..lineTo(348 + 66, 4),
      Path()
        ..moveTo(440 + 2, 4)
        ..lineTo(440 + 67, 4)
        ..lineTo(440 + 2, 88)
        ..lineTo(440 + 67, 88),
      Path()
        ..moveTo(532 + 2, 88)
        ..lineTo(532 + 34, 4)
        ..lineTo(532 + 67, 88),
      bar(532, 59, 14, 55),
    ];
  }

  // Her çizginin başlama anı (0..1). Harfler sırayla, ikincil çizgiler biraz geç.
  static const _starts = [
    0.00, 0.10, 0.06, 0.09, 0.12, 0.15, 0.16, 0.26, 0.36, 0.34, 0.43, 0.52, 0.64
  ];
  static const _span = 0.36;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 100;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokePx / scale
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    for (var i = 0; i < _strokes.length; i++) {
      final raw = ((progress - _starts[i]) / _span).clamp(0.0, 1.0);
      if (raw <= 0) continue;
      final t = Curves.easeInOutCubic.transform(raw);
      if (t >= 1) {
        canvas.drawPath(_strokes[i], paint);
        continue;
      }
      for (final ui.PathMetric m in _strokes[i].computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      old.progress != progress || old.color != color || old.strokePx != strokePx;
}
