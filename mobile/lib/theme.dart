import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Uygulama tema modu. Profil ekranındaki düğme bunu değiştirir; main.dart
/// dinleyip tüm ağacı yeniden çizer. Varsayılan açık (bej) mod, web sitesiyle aynı.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<String> currencyNotifier = ValueNotifier('₺');

class CurrencyService {
  static final Map<String, double> rates = {
    '₺': 1.0,
    '\$': 0.0303, // 1 TRY = 0.0303 USD (approx 33 TRY/USD)
    '€': 0.0278,  // 1 TRY = 0.0278 EUR (approx 36 TRY/EUR)
    '£': 0.0238,  // 1 TRY = 0.0238 GBP (approx 42 TRY/GBP)
  };

  static Future<void> updateRates() async {
    try {
      final res = await http.get(Uri.parse('https://open.er-api.com/v6/latest/TRY'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fetchedRates = data['rates'] as Map<String, dynamic>;
        rates['₺'] = 1.0;
        if (fetchedRates.containsKey('USD')) {
          rates['\$'] = (fetchedRates['USD'] as num).toDouble();
        }
        if (fetchedRates.containsKey('EUR')) {
          rates['€'] = (fetchedRates['EUR'] as num).toDouble();
        }
        if (fetchedRates.containsKey('GBP')) {
          rates['£'] = (fetchedRates['GBP'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('Döviz kurları güncellenemedi, varsayılan kurlar kullanılacak: $e');
    }
  }

  static double convertFromTry(double tryAmount, String targetSymbol) {
    final rate = rates[targetSymbol] ?? 1.0;
    return tryAmount * rate;
  }

  static double convertToTry(double targetAmount, String sourceSymbol) {
    final rate = rates[sourceSymbol] ?? 1.0;
    return targetAmount / rate;
  }
}

/// Temayı ANLIK değeri okuyarak tersine çevirir (yakalanmış eski değere güvenmez).
void toggleThemeMode() {
  themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
}

/// Expenza renk paleti. Web sitesindeki tasarım sistemiyle aynı değerler.
///
/// - AÇIK (varsayılan): bej zemin, antrasit metin, lacivert eylem rengi.
/// - KOYU: antrasit zemin, bej metin, bej eylem rengi.
/// - Kiremit yalnızca uyarı ve gider aşımı içindir; gelir ve "yolunda" durumları
///   lacivert tonuyla gösterilir (kırmızı/yeşil ayrımına dayanmaz).
///
/// Tüm renkler temaya göre değişir → mutable static. [applyMode] tema değişince
/// günceller; ekranlar çalışma anında okuduğu için yeni renkler otomatik yansır.
class AppColors {
  static bool isDark = false;

  // --- Temaya göre değişen nötrler ---
  static Color background = _light.background;
  static Color surface = _light.surface;
  static Color surfaceContainer = _light.surfaceContainer;
  static Color surfaceContainerHigh = _light.surfaceContainerHigh;
  static Color surfaceBright = _light.surfaceBright;
  static Color onSurface = _light.onSurface;
  static Color onSurfaceVariant = _light.onSurfaceVariant;
  static Color outline = _light.outline;
  static Color glass = _light.glass;
  static Color glassBorder = _light.glassBorder;
  static Color primary = _light.accent;
  static Color primaryContainer = _light.accent;
  static Color onPrimary = _light.accentInk;
  static Color navBg = _light.navBg;

  // --- Temaya göre değişen anlamsal renkler ---
  /// Uyarı, limit aşımı, gider vurgusu (kiremit).
  static Color error = _light.error;
  /// Limite yaklaşma (koyu hardal).
  static Color warn = _light.warn;
  /// Gelir, "yolunda", tamamlandı (lacivert tonu).
  static Color positive = _light.positive;
  /// Tahmin, bilgi (açık lacivert).
  static Color info = _light.info;
  static Color errorSoft = _light.errorSoft;
  static Color catBlue = _light.info;
  static Color catPurple = _light.purple;

  static void applyMode(bool dark) {
    final p = dark ? _dark : _light;
    isDark = dark;
    background = p.background;
    surface = p.surface;
    surfaceContainer = p.surfaceContainer;
    surfaceContainerHigh = p.surfaceContainerHigh;
    surfaceBright = p.surfaceBright;
    onSurface = p.onSurface;
    onSurfaceVariant = p.onSurfaceVariant;
    outline = p.outline;
    glass = p.glass;
    glassBorder = p.glassBorder;
    primary = p.accent;
    primaryContainer = p.accent;
    onPrimary = p.accentInk;
    navBg = p.navBg;
    error = p.error;
    warn = p.warn;
    positive = p.positive;
    info = p.info;
    errorSoft = p.errorSoft;
    catBlue = p.info;
    catPurple = p.purple;
  }

  static const _light = _Pal(
    background: Color(0xFFEDE6D9), // Bej 100
    surface: Color(0xFFF7F3EC), // Bej 50, kart
    surfaceContainer: Color(0xFFE3DBCB), // Bej 200, bar zemini
    surfaceContainerHigh: Color(0xFFD3C9B6), // Bej 300
    surfaceBright: Color(0xFFFBF9F4), // input zemini
    onSurface: Color(0xFF26282C), // Antrasit 800
    onSurfaceVariant: Color(0xFF5D5C57), // Gri 600
    outline: Color(0xFF77746D),
    glass: Color(0xFFF7F3EC),
    glassBorder: Color(0xFFD3C9B6), // çizgi
    accent: Color(0xFF1F2F57), // Lacivert 700
    accentInk: Color(0xFFF7F3EC),
    navBg: Color(0xF2EDE6D9),
    error: Color(0xFFA24B26), // Kiremit 600
    warn: Color(0xFF8A6418),
    positive: Color(0xFF1F2F57),
    info: Color(0xFF2E64B5),
    errorSoft: Color(0xFFF1DFD4),
    purple: Color(0xFF5B4FB0),
  );

  static const _dark = _Pal(
    background: Color(0xFF1D1E21), // Antrasit 900
    surface: Color(0xFF26282C), // Antrasit 800
    surfaceContainer: Color(0xFF313439), // Antrasit 700
    surfaceContainerHigh: Color(0xFF3A3D42),
    surfaceBright: Color(0xFF2B2D31),
    onSurface: Color(0xFFEDE6D9),
    onSurfaceVariant: Color(0xFFA9A69E), // Gri 300
    outline: Color(0xFF8E8B84),
    glass: Color(0xFF26282C),
    glassBorder: Color(0xFF3A3D42),
    accent: Color(0xFFEDE6D9),
    accentInk: Color(0xFF1F2F57),
    navBg: Color(0xF21D1E21),
    error: Color(0xFFE0916B),
    warn: Color(0xFFD9AE5B),
    positive: Color(0xFFA9B8DC),
    info: Color(0xFF5B8BD6),
    errorSoft: Color(0xFF4A3329),
    purple: Color(0xFF8A7FE0),
  );
}

class _Pal {
  final Color background,
      surface,
      surfaceContainer,
      surfaceContainerHigh,
      surfaceBright,
      onSurface,
      onSurfaceVariant,
      outline,
      glass,
      glassBorder,
      accent,
      accentInk,
      navBg,
      error,
      warn,
      positive,
      info,
      errorSoft,
      purple;
  const _Pal({
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceBright,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.glass,
    required this.glassBorder,
    required this.accent,
    required this.accentInk,
    required this.navBg,
    required this.error,
    required this.warn,
    required this.positive,
    required this.info,
    required this.errorSoft,
    required this.purple,
  });
}

/// Köşe yarıçapları: bar/rozet, input, kart, büyük panel, hap.
class AppRadius {
  static const double sm = 6;
  static const double md = 14;
  static const double lg = 24;
  static const double xl = 28;
  static const double pill = 999;
}

/// Hareket süreleri ve eğrisi (web ile aynı).
class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 450);
  static const slow = Duration(milliseconds: 700);
  static const curve = Cubic(0.2, 0.7, 0.2, 1);
}

/// Para/sayı için tabular figür.
const List<FontFeature> kTnum = [FontFeature.tabularFigures()];

/// Türkçe büyük harf: 'i' → 'İ', 'ı' → 'I' (Dart'ın toUpperCase'i bunu bilmez).
String trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Ortak metin stilleri. Font ailesi temadan (Jost) gelir; tutarlar DM Mono.
class AppText {
  /// Tutar, oran, tarih gibi rakamlar.
  static TextStyle mono(
          {double size = 15,
          FontWeight weight = FontWeight.w400,
          Color? color}) =>
      GoogleFonts.dmMono(
          fontSize: size,
          fontWeight: weight,
          color: color ?? AppColors.onSurface,
          fontFeatures: kTnum);

  /// Büyük harf, geniş aralıklı etiket (wordmark'taki harf boşluklarından).
  static TextStyle label({double size = 12, Color? color}) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: size * 0.16,
      color: color ?? AppColors.onSurfaceVariant);

  /// Büyük, ince başlık ya da öne çıkan sayı.
  static TextStyle display({double size = 44, Color? color}) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w400,
      letterSpacing: -size * 0.03,
      height: 1.0,
      color: color ?? AppColors.onSurface,
      fontFeatures: kTnum);
}

class AppTheme {
  static ThemeData fromMode(bool isDark) {
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final pill = WidgetStatePropertyAll<OutlinedBorder>(const StadiumBorder());
    final buttonText = WidgetStatePropertyAll(
        GoogleFonts.jost(fontSize: 16, fontWeight: FontWeight.w500));
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.background,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.primary,
        error: AppColors.error,
        onSurface: AppColors.onSurface,
        outline: AppColors.glassBorder,
        outlineVariant: AppColors.glassBorder,
        surfaceContainerHighest: AppColors.surfaceContainer,
      ),
      textTheme: _textTheme(base.textTheme),
      dividerTheme: DividerThemeData(color: AppColors.glassBorder, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.jost(
            fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceBright,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: TextStyle(color: AppColors.outline),
        labelStyle: TextStyle(color: AppColors.onSurfaceVariant),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.glassBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.error)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: pill,
          textStyle: buttonText,
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
          backgroundColor: WidgetStatePropertyAll(AppColors.primary),
          foregroundColor: WidgetStatePropertyAll(AppColors.onPrimary),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: pill,
          textStyle: buttonText,
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
          backgroundColor: WidgetStatePropertyAll(AppColors.primary),
          foregroundColor: WidgetStatePropertyAll(AppColors.onPrimary),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: pill,
          textStyle: buttonText,
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          foregroundColor: WidgetStatePropertyAll(AppColors.onSurface),
          side: WidgetStatePropertyAll(BorderSide(color: AppColors.glassBorder)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.jost(fontSize: 15, fontWeight: FontWeight.w500)),
          foregroundColor: WidgetStatePropertyAll(AppColors.primary),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: StadiumBorder(side: BorderSide(color: AppColors.glassBorder)),
        side: BorderSide(color: AppColors.glassBorder),
        backgroundColor: Colors.transparent,
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.jost(fontSize: 14, color: AppColors.onSurface),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.onSurface,
        contentTextStyle: GoogleFonts.jost(fontSize: 15, color: AppColors.background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceContainer,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.outline),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceContainer),
        trackOutlineColor: WidgetStatePropertyAll(AppColors.glassBorder),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }

  static TextTheme _textTheme(TextTheme t) {
    final scaled = t.copyWith(
      displayLarge: TextStyle(
          fontSize: 52,
          fontWeight: FontWeight.w400,
          letterSpacing: -1.6,
          height: 1.0,
          color: AppColors.onSurface),
      headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.6,
          color: AppColors.onSurface),
      headlineMedium: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w500, color: AppColors.onSurface),
      titleMedium: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.onSurface),
      bodyLarge: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w400, color: AppColors.onSurface),
      bodyMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.onSurface),
      labelMedium: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onSurface),
      labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.9,
          color: AppColors.onSurfaceVariant),
    );
    return GoogleFonts.jostTextTheme(scaled);
  }
}

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
