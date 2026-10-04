// Ekranların ortak yapı taşları: kart, başlık etiketi, çubuk, sayaç, dokunma
// geri bildirimi, onay penceresi, hata ve belirme animasyonu.
import 'package:flutter/material.dart';

import '../theme.dart';

/// Kart yüzeyi: bej 50 zemin, 1 px çizgi, 24 px köşe.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const GlassCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.surface;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: color == null ? Border.all(color: AppColors.glassBorder) : null,
      ),
      child: child,
    );
  }
}

/// Büyük harf, geniş aralıklı bölüm etiketi ("ÖNERİLEN KATEGORİ").
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  final double size;
  const Eyebrow(this.text, {super.key, this.color, this.size = 12});

  @override
  Widget build(BuildContext context) =>
      Text(trUpper(text), style: AppText.label(size: size, color: color));
}

/// İlk çizimde 0'dan hedefe dolan ilerleme çubuğu; değer değişince yumuşakça kayar.
class ExBar extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final Color? track;
  final double height;
  const ExBar(
      {super.key,
      required this.value,
      this.color,
      this.track,
      this.height = 8});

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: height,
        color: track ?? AppColors.surfaceContainer,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: AppMotion.slow,
          curve: AppMotion.curve,
          builder: (context, t, _) => FractionallySizedBox(
            widthFactor: t,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color ?? AppColors.onSurface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sayıyı 0'dan hedefe sayarak gösterir (bakiye, tahmin gibi öne çıkan rakamlar).
class CountUp extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration duration;
  const CountUp(
      {super.key,
      required this.value,
      required this.format,
      this.style,
      this.duration = const Duration(milliseconds: 900)});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Etrafına dalga yayan küçük nokta: canlı durum ya da bekleyen uyarı için.
class PingDot extends StatefulWidget {
  final Color color;
  final double size;
  const PingDot({super.key, required this.color, this.size = 7});

  @override
  State<PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<PingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + t * 1.8,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.55 * (1 - t)),
                      shape: BoxShape.circle),
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fiş düzenindeki noktalı çizgi: soldaki metni sağdaki tutara bağlar.
class DottedLeader extends StatelessWidget {
  final Color? color;
  const DottedLeader({super.key, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: CustomPaint(
            painter: _DotsPainter(color ?? AppColors.outline.withValues(alpha: 0.6))),
      );
}

/// Fiş satırı: [left] ..... [right]. Noktalar arka planda boydan boya uzanır,
/// iki uçtaki metin [background] rengiyle noktaları örter.
class LeaderRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  final Color? background;
  const LeaderRow(
      {super.key, required this.left, required this.right, this.background});

  @override
  Widget build(BuildContext context) {
    final bg = background ?? AppColors.background;
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        const Positioned.fill(
          child: Align(
            alignment: Alignment(0, 0.35),
            child: SizedBox(width: double.infinity, child: DottedLeader()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: ColoredBox(
                color: bg,
                child: Padding(
                    padding: const EdgeInsets.only(right: 10), child: left),
              ),
            ),
            ColoredBox(
              color: bg,
              child: Padding(
                  padding: const EdgeInsets.only(left: 10), child: right),
            ),
          ],
        ),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Color color;
  _DotsPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawCircle(Offset(x + 0.6, size.height / 2), 0.6, p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

/// Basınca hafifçe küçülen dokunsal sarmalayıcı.
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Press({super.key, required this.child, this.onTap});

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Ortak onay penceresi (silme vb.). Kiremit vurgu yıkıcı işlemler için.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Sil',
  String cancel = 'Vazgeç',
  bool destructive = true,
  IconData icon = Icons.delete_outline,
}) async {
  final accent = destructive ? AppColors.error : AppColors.primary;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.glassBorder)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                    color: AppColors.onSurface)),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                    fontSize: 16, height: 1.5, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(cancel)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: AppColors.surface),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(confirm)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return r ?? false;
}

/// Veri alınamadığında gösterilen ortak hata görünümü (aşağı çekerek de yenilenebilir).
class LoadError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const LoadError({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, color: AppColors.outline, size: 48),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text('Veriler alınamadı.\n$msg',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
            child: TextButton(
                onPressed: onRetry, child: const Text('Tekrar dene'))),
      ],
    );
  }
}

/// Yüklenince aşağıdan yukarı beliren animasyon (web'deki bölüm girişleri gibi).
class Rise extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const Rise({super.key, required this.child, this.delayMs = 0});

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  double _t = 0;
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _t = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _t),
      duration: AppMotion.slow,
      curve: AppMotion.curve,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 20), child: child),
      ),
      child: widget.child,
    );
  }
}
