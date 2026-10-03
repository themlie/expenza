import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models.dart';
import '../ocr_service.dart';
import '../theme.dart';
import 'dashboard_screen.dart' show categoryColor, categoryIcon;

/// Harcama/Gelir ekleme veya düzenleme.
/// Gider notu yazıldıkça GERÇEK eğitilmiş model (/ml/categorize) canlı öneri verir;
/// öneri kartı web sitesindeki canlı önizlemeyle aynı dili kullanır.
class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? existing;
  const AddTransactionScreen({super.key, this.existing});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _type = 'expense';
  String? _selectedCategory;
  bool _busy = false;
  Timer? _debounce;

  CategorySuggestion? _suggestion;
  bool _suggesting = false;
  bool _isRecurring = false;

  bool get _isEdit => widget.existing != null;
  bool get _isIncome => _type == 'income';

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      final displayAmount = CurrencyService.convertFromTry(ex.amount, currencyNotifier.value);
      _amount.text = displayAmount.toStringAsFixed(displayAmount % 1 == 0 ? 0 : 2);
      _note.text = ex.note;
      _type = ex.type;
      _selectedCategory = ex.category;
      _isRecurring = ex.isRecurring;
    }
    _note.addListener(_onNote);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onNote() {
    _debounce?.cancel();
    if (_isIncome) {
      setState(() => _suggestion = null);
      return;
    }
    final text = _note.text.trim();
    if (text.length < 3) {
      setState(() {
        _suggestion = null;
        _suggesting = false;
      });
      return;
    }
    setState(() => _suggesting = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final s = await ApiClient.instance.categorize(text);
        if (mounted) setState(() => _suggestion = s);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _suggesting = false);
      }
    });
  }

  void _setType(String t) {
    setState(() {
      _type = t;
      if (!_isEdit) {
        _selectedCategory = null;
        _suggestion = null;
        _isRecurring = false;
      }
    });
  }

  void _pick(String c) {
    setState(() => _selectedCategory = c);
  }

  // Fiş OCR: kamera/galeriden fiş oku → tutar+işyeri doldur → model kategorize etsin.
  Future<void> _scanReceipt() async {
    // Kaynak seç: kamera / galeri
    final source = await showModalBottomSheet<ImageSource>(
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
    if (source == null) return;

    _toast('Fiş okunuyor…');
    try {
      final scan = await OcrService.scan(source);
      if (scan == null) return;
      setState(() {
        if (scan.amount != null) {
          // Fiş tutarı TL; alan seçili para biriminde, kaydederken TL'ye geri çevrilir.
          final shown =
              CurrencyService.convertFromTry(scan.amount!, currencyNotifier.value);
          _amount.text = shown.toStringAsFixed(shown % 1 == 0 ? 0 : 2);
        }
        if (scan.merchant.isNotEmpty) _note.text = scan.merchant;
      });
      if (scan.amount == null) {
        _toast('Tutar okunamadı, elle gir', error: true);
      } else {
        _toast('Fiş okundu, kontrol edip kaydet');
      }
    } catch (e) {
      _toast('Fiş okunamadı: ${e.toString()}', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: AppColors.background, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ],
      ),
    ));
  }

  Future<void> _save() async {
    final enteredAmount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (enteredAmount == null || enteredAmount <= 0) {
      _toast('Lütfen tutar gir', error: true);
      return;
    }
    final amountInTry = CurrencyService.convertToTry(enteredAmount, currencyNotifier.value);
    if (!_isIncome && _selectedCategory == null) {
      _toast('Lütfen kategori seç', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await ApiClient.instance.updateTransaction(
          widget.existing!.id,
          amount: amountInTry,
          type: _type,
          category: _selectedCategory ??
              (_isIncome ? 'Diğer' : widget.existing!.category),
          note: _note.text.trim(),
          isRecurring: _isRecurring,
        );
      } else {
        await ApiClient.instance.addTransaction(
          amount: amountInTry,
          type: _type,
          category: _selectedCategory, // null → backend modelle/Diğer atar
          note: _note.text.trim(),
          isRecurring: _isRecurring,
          // Öneri hâlâ yükleniyorsa (not değişmiş olabilir) gönderilmez.
          shownSuggestion: !_isIncome && !_suggesting ? _suggestion : null,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    final accent = _isIncome ? AppColors.positive : AppColors.onSurface;
    final hasAmount = _amount.text.trim().isNotEmpty;
    final title = _isEdit
        ? (_isIncome ? 'Geliri düzenle' : 'Gideri düzenle')
        : (_isIncome ? 'Gelir ekle' : 'Harcama ekle');

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 130),
            children: [
              // Başlık
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleBtn(Icons.chevron_left,
                      () => Navigator.of(context).maybePop()),
                  Text(title,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurface)),
                  _circleBtn(
                      isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      toggleThemeMode),
                ],
              ),
              const SizedBox(height: 26),

              // Gider/Gelir segmenti
              Rise(child: _segmented()),
              const SizedBox(height: 14),

              // Fiş tara (gider + mobil)
              if (!_isIncome && OcrService.supported) ...[
                Rise(
                  delayMs: 60,
                  child: Press(
                    onTap: _scanReceipt,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.document_scanner_outlined,
                              size: 19, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('Fiş tara',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
              ] else
                const SizedBox(height: 18),

              // Tutar
              Rise(
                delayMs: 100,
                child: Column(
                  children: [
                    const Eyebrow('Tutar'),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: AppMotion.fast,
                          style: AppText.display(size: 36, color: accent)
                              .copyWith(fontWeight: FontWeight.w300),
                          child: Text(_isIncome
                              ? '+${currencyNotifier.value}'
                              : '−${currencyNotifier.value}'),
                        ),
                        const SizedBox(width: 6),
                        IntrinsicWidth(
                          child: TextField(
                            controller: _amount,
                            autofocus: !_isEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.center,
                            onChanged: (_) => setState(() {}),
                            style: AppText.display(size: 60),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: '0',
                              hintStyle: AppText.display(
                                  size: 60, color: AppColors.surfaceContainerHigh),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: AppMotion.medium,
                      curve: AppMotion.curve,
                      width: hasAmount ? 180 : 110,
                      height: 2,
                      decoration: BoxDecoration(
                          color: hasAmount
                              ? AppColors.primary
                              : AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.pill)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),

              // Kategori (sadece gider)
              if (!_isIncome) ...[
                const Eyebrow('Kategori'),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.8,
                  children: [
                    for (var i = 0; i < kCategories.length; i++)
                      Rise(delayMs: 140 + i * 35, child: _catCell(kCategories[i])),
                  ],
                ),
                const SizedBox(height: 26),
              ],

              // Not + canlı öneri
              const Eyebrow('Not'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBright,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: TextField(
                  controller: _note,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 17, height: 1.45, color: AppColors.onSurface),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'örn. Migros\'tan haftalık market alışverişi…',
                    hintStyle:
                        TextStyle(color: AppColors.outline, fontSize: 17),
                  ),
                ),
              ),
              if (!_isIncome)
                AnimatedSize(
                  duration: AppMotion.medium,
                  curve: AppMotion.curve,
                  alignment: Alignment.topCenter,
                  child: _suggestionCard(),
                ),
              const SizedBox(height: 18),
              _recurringRow(),
            ],
          ),

          // Kaydet barı (düz zemin + üst çizgi)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.glassBorder)),
              ),
              child: Press(
                onTap: _busy ? null : _save,
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: _busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.onPrimary))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check,
                                size: 19, color: AppColors.onPrimary),
                            const SizedBox(width: 8),
                            Text(
                                _isEdit ? 'Değişiklikleri kaydet' : 'Kaydet',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.onPrimary)),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Press(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder)),
        child: Icon(icon, size: 20, color: AppColors.onSurface),
      ),
    );
  }

  Widget _segmented() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: _isIncome ? Alignment.centerRight : Alignment.centerLeft,
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _segTab('Gider', Icons.south, !_isIncome,
                  () => _setType('expense')),
              _segTab('Gelir', Icons.north, _isIncome,
                  () => _setType('income')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segTab(
      String label, IconData icon, bool active, VoidCallback onTap) {
    final color = active ? AppColors.onPrimary : AppColors.onSurfaceVariant;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _catCell(String c) {
    final on = _selectedCategory == c;
    final color = categoryColor(c);
    return GestureDetector(
      onTap: () => _pick(c),
      child: AnimatedScale(
        scale: on ? 1.04 : 1.0,
        duration: AppMotion.fast,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            color: on ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: on ? AppColors.primary : AppColors.glassBorder,
                width: on ? 1.5 : 1),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(categoryIcon(c), size: 18, color: color),
              ),
              const SizedBox(height: 8),
              Text(c,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                      color: on ? AppColors.onSurface : AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestionCard() {
    if (_suggesting) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const _ThinkingDots(),
              const SizedBox(width: 12),
              Text('Kategori analiz ediliyor',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    final s = _suggestion;
    if (s == null) return const SizedBox(width: double.infinity);
    final already = _selectedCategory == s.category;
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
                          onTap: () => _pick(s.category),
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

  Widget _recurringRow() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
      child: Row(
        children: [
          Icon(Icons.repeat, size: 19, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Her ay tekrarla',
              style: TextStyle(fontSize: 16, color: AppColors.onSurface),
            ),
          ),
          Switch(
            value: _isRecurring,
            onChanged: (val) async {
              if (val) {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Her ay tekrarlansın mı?',
                  message:
                      'Bu ${_isIncome ? 'gelir' : 'gider'} her ay aynı gün otomatik olarak eklenecek. '
                      'İstediğin zaman bu işlemi düzenleyip işareti kaldırarak durdurabilirsin.',
                  confirm: 'Evet',
                  cancel: 'Hayır',
                  destructive: false,
                  icon: Icons.repeat,
                );
                setState(() => _isRecurring = confirm);
              } else {
                setState(() => _isRecurring = false);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Model yanıtını beklerken nabız gibi yanıp sönen üç nokta.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
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
