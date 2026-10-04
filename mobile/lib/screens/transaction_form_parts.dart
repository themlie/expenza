// İşlem ekleme/düzenleme formunun parçaları: kategori önerisi kartı, tarih alanı,
// fiş kaynağı seçimi ve kayıttan sonra gösterilen bütçe uyarısı.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Not yazıldıkça yerel modelden gelen kategori önerisi. [loading] iken "analiz
/// ediliyor" gösterilir; öneri yoksa boş alan kalır.
class SuggestionCard extends StatelessWidget {
  final CategorySuggestion? suggestion;
  final bool loading;
  final String? selected;
  final ValueChanged<String> onAccept;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.loading,
    required this.selected,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const ThinkingDots(),
              const SizedBox(width: 12),
              Text('Kategori analiz ediliyor',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    final s = suggestion;
    if (s == null) return const SizedBox(width: double.infinity);
    final already = selected == s.category;
    final low = s.confidence < 0.6;
    final confColor = low ? AppColors.error : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Önerilen kategori', size: 11),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.medium,
                    switchInCurve: AppMotion.curve,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                          position: Tween(
                                  begin: const Offset(0, 0.3), end: Offset.zero)
                              .animate(a),
                          child: child),
                    ),
                    child: Align(
                      key: ValueKey(s.category),
                      alignment: Alignment.centerLeft,
                      // Dar ekranda güven oranı alt satıra iner, taşmaz.
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Text(s.category, style: AppText.display(size: 30)),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                                '%${(s.confidence * 100).toStringAsFixed(0)} güven',
                                style: AppText.mono(size: 13, color: confColor)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: already
                      ? Row(
                          key: const ValueKey('sel'),
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text('Seçili',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary)),
                          ],
                        )
                      : Press(
                          key: const ValueKey('acc'),
                          onTap: () => onAccept(s.category),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill)),
                            child: Text('Kabul et',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.onPrimary)),
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
                width: 160,
                child: ExBar(value: s.confidence, color: confColor, height: 4)),
            if (low) ...[
              const SizedBox(height: 10),
              Text('Bu notta emin değilim. Kategoriyi yukarıdan sen seç.',
                  style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Model yanıtını beklerken nabız gibi yanıp sönen üç nokta.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            Opacity(
              opacity: () {
                final t = (_c.value - i * 0.15) % 1.0;
                return t < 0.4 ? 0.2 + t / 0.4 * 0.8 : 1.0 - (t - 0.4) / 0.6 * 0.8;
              }(),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
              ),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

/// İşlem tarihi: dokununca takvim açılır; "Dün" ve "Bugün" çipleri tek dokunuşla
/// seçer. Takvim [first] ile [last] arasıyla sınırlıdır.
class TransactionDateField extends StatelessWidget {
  final DateTime value;
  final DateTime first;
  final DateTime last;
  final ValueChanged<DateTime> onChanged;

  const TransactionDateField({
    super.key,
    required this.value,
    required this.first,
    required this.last,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value.isAfter(last)
          ? last
          : (value.isBefore(first) ? first : value),
      firstDate: first,
      lastDate: last,
      helpText: 'İşlem tarihi',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final today = last;
    final yesterday = today.subtract(const Duration(days: 1));
    final label = DateFormat(
            value.year == today.year ? 'd MMMM, EEEE' : 'd MMMM y, EEEE', 'tr_TR')
        .format(value);
    return Press(
      onTap: () => _pick(context),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 19, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tarih',
                      style: TextStyle(fontSize: 16, color: AppColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                          fontSize: 14, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            _dayChip('Dün', yesterday),
            const SizedBox(width: 6),
            _dayChip('Bugün', today),
          ],
        ),
      ),
    );
  }

  Widget _dayChip(String text, DateTime day) {
    final selected = value == day;
    return Press(
      onTap: () => onChanged(day),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.glassBorder),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? AppColors.onPrimary : AppColors.onSurface)),
      ),
    );
  }
}

/// Fiş için kaynak seçtirir: kamera ya da galeri. Vazgeçilirse null.
Future<ImageSource?> pickReceiptSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.pill))),
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Eyebrow('Fiş tara', size: 11),
            ),
            const SizedBox(height: 6),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md)),
              leading: Icon(Icons.photo_camera_outlined,
                  color: AppColors.onSurface),
              title: Text('Kamera',
                  style: TextStyle(fontSize: 17, color: AppColors.onSurface)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md)),
              leading: Icon(Icons.photo_library_outlined,
                  color: AppColors.onSurface),
              title: Text('Galeriden seç',
                  style: TextStyle(fontSize: 17, color: AppColors.onSurface)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text('Fotoğraf telefonunda okunur, sunucuya yüklenmez.',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Kayıt bir bütçeyi %80'in ya da %100'ün üstüne çıkardıysa uyarı gösterir. Eşik bu
/// kayıtla geçildiyse ([BudgetAlertModel.crossed]) uyarı daha uzun kalır.
void showBudgetAlert(
    ScaffoldMessengerState messenger, List<BudgetAlertModel> alerts) {
  if (alerts.isEmpty) return;
  final a = alerts.firstWhere((x) => x.exceeded, orElse: () => alerts.first);
  final more = alerts.length > 1 ? ' (+${alerts.length - 1} bütçe daha)' : '';
  messenger.showSnackBar(SnackBar(
    duration: Duration(seconds: a.crossed ? 6 : 3),
    content: Row(
      children: [
        Icon(a.exceeded ? Icons.error_outline : Icons.warning_amber_rounded,
            color: a.exceeded ? AppColors.error : AppColors.warn, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('${a.message} ${money(a.spent)} / ${money(a.limit)}$more'),
        ),
      ],
    ),
  ));
}
