import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/circle_button.dart';

// Hedef kartlarının ayırt edici renkleri: kategori paletiyle aynı aile.
const _paletteLight = [
  Color(0xFF2E64B5),
  Color(0xFF1E9A85),
  Color(0xFF8A4FA0),
  Color(0xFFB8761F),
  Color(0xFFC25B7E),
  Color(0xFF5B4FB0),
];
const _paletteDark = [
  Color(0xFF5B8BD6),
  Color(0xFF2AA38D),
  Color(0xFFA776C2),
  Color(0xFFBA7E2C),
  Color(0xFFC66A88),
  Color(0xFF8A7FE0),
];
const _icons = [
  Icons.flight,
  Icons.shield_outlined,
  Icons.laptop_mac,
  Icons.home_outlined,
  Icons.directions_car_filled_outlined,
  Icons.card_giftcard,
];

/// Tasarruf hedefleri: lacivert özet paneli, hedef kartları (son tarih, durum, ayda
/// ayrılması gereken tutar), ekle/düzenle, katkı ve para çekme alt sayfaları,
/// sola kaydır→sil. Renk/ikon indekse göre atanır.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late Future<List<GoalModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.getGoals();
  }

  void _refresh() => setState(() => _future = ApiClient.instance.getGoals());

  Color _color(int i) {
    final p = AppColors.isDark ? _paletteDark : _paletteLight;
    return p[i % p.length];
  }

  IconData _icon(int i) => _icons[i % _icons.length];

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      floatingActionButton: FutureBuilder<List<GoalModel>>(
        future: _future,
        builder: (context, snap) {
          if ((snap.data ?? []).isEmpty) return const SizedBox.shrink();
          return Press(
            onTap: () => _openForm(),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: AppColors.onPrimary, size: 22),
                  const SizedBox(width: 8),
                  Text('Hedef ekle',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onPrimary)),
                ],
              ),
            ),
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<List<GoalModel>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (snap.hasError) {
              return LoadError(error: snap.error!, onRetry: _refresh);
            }
            final goals = snap.data ?? [];
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 120),
              children: [
                Rise(child: _header(isDark, goals.length)),
                const SizedBox(height: 28),
                if (goals.isEmpty)
                  Rise(delayMs: 80, child: _empty())
                else ...[
                  Rise(delayMs: 80, child: _summary(goals)),
                  const SizedBox(height: 16),
                  for (var i = 0; i < goals.length; i++)
                    Rise(delayMs: 160 + i * 60, child: _goalCard(goals[i], i)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(bool isDark, int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).maybePop()),
            CircleIconButton(icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, onTap: toggleThemeMode),
          ],
        ),
        const SizedBox(height: 24),
        Eyebrow(count > 0 ? '$count aktif hedef' : 'Hedef yok'),
        const SizedBox(height: 10),
        Text('Tasarruf hedefleri', style: AppText.display(size: 36)),
      ],
    );
  }

  // ---- Özet: lacivert panel (web'deki hedef kartı) ----
  Widget _summary(List<GoalModel> goals) {
    final saved = goals.fold(
        0.0, (s, g) => s + (g.currentAmount.clamp(0, g.targetAmount)));
    final target = goals.fold(0.0, (s, g) => s + g.targetAmount);
    final done = goals.where((g) => g.progress >= 1).length;
    final pct = target == 0 ? 0.0 : saved / target;
    final ink = AppColors.onPrimary;

    return GlassCard(
      color: AppColors.primary,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Eyebrow('Toplam birikim',
                    size: 11, color: ink.withValues(alpha: 0.75)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text('$done tamamlandı',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ink,
                        fontFeatures: kTnum)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUp(
                value: saved,
                format: money,
                style: AppText.display(size: 46, color: ink)),
          ),
          const SizedBox(height: 6),
          Text('/ ${money(target)}',
              style: AppText.mono(size: 14, color: ink.withValues(alpha: 0.75))),
          const SizedBox(height: 18),
          ExBar(
              value: pct,
              color: ink,
              track: ink.withValues(alpha: 0.2),
              height: 8),
        ],
      ),
    );
  }

  Widget _goalCard(GoalModel g, int index) {
    final color = _color(index);
    final complete = g.progress >= 1;
    final barColor = complete ? AppColors.positive : color;
    final pct = (g.progress * 100).clamp(0, 100).toInt();

    return Dismissible(
      key: ValueKey(g.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: AppColors.surface, size: 20),
            const SizedBox(height: 3),
            Text('Sil',
                style: TextStyle(
                    color: AppColors.surface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(g),
      onDismissed: (_) async {
        await ApiClient.instance.deleteGoal(g.id);
        _refresh();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle),
                  child: Icon(_icon(index), size: 19, color: barColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(g.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.onSurface)),
                          ),
                          if (complete) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.check_circle,
                                size: 14, color: AppColors.positive),
                            const SizedBox(width: 4),
                            Eyebrow('Tamamlandı',
                                size: 10, color: AppColors.positive),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: money(g.currentAmount.clamp(0, g.targetAmount))),
                          TextSpan(
                              text: ' / ${money(g.targetAmount)}',
                              style:
                                  TextStyle(color: AppColors.onSurfaceVariant)),
                        ]),
                        style: AppText.mono(size: 13),
                      ),
                    ],
                  ),
                ),
                Text('%$pct',
                    style: AppText.mono(
                        size: 16,
                        color: complete ? AppColors.positive : AppColors.onSurface)),
                _menu(g),
              ],
            ),
            if (g.deadline != null && !complete) ...[
              const SizedBox(height: 12),
              _deadlineLine(g),
            ],
            const SizedBox(height: 14),
            ExBar(value: g.progress, color: barColor),
            const SizedBox(height: 16),
            if (complete)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.positive.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_outlined, size: 17, color: AppColors.positive),
                    const SizedBox(width: 8),
                    Text('Hedefe ulaşıldı',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.positive)),
                  ],
                ),
              )
            else
              Row(
                children: [
                  // Dar ekranda "Ayda gereken" alta geçer.
                  Expanded(
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Eyebrow('Kalan', size: 10),
                            const SizedBox(height: 4),
                            Text(money(g.remaining),
                                style: AppText.mono(size: 15)),
                          ],
                        ),
                        if (g.monthlyNeeded != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Eyebrow('Ayda gereken', size: 10),
                              const SizedBox(height: 4),
                              Text(money(g.monthlyNeeded!),
                                  style: AppText.mono(size: 15)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Press(
                    onTap: () => _openContribute(g, color),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.glassBorder)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 17, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text('Katkı ekle',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static const _statusText = {
    'on_track': 'Yolunda',
    'behind': 'Geride',
    'overdue': 'Süresi geçti',
  };

  Color _statusColor(String status) => switch (status) {
        'on_track' => AppColors.positive,
        'behind' => AppColors.warn,
        _ => AppColors.error,
      };

  String _dateText(String iso) {
    final d = DateTime.parse(iso);
    final sameYear = d.year == DateTime.now().year;
    return DateFormat(sameYear ? 'd MMMM' : 'd MMMM y', 'tr_TR').format(d);
  }

  Widget _deadlineLine(GoalModel g) {
    final days = g.daysLeft ?? 0;
    final left = days < 0
        ? '${-days} gün geçti'
        : days == 0
            ? 'son gün bugün'
            : '$days gün kaldı';
    final status = _statusText[g.status];
    return Row(
      children: [
        Icon(Icons.event_outlined, size: 15, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text('${_dateText(g.deadline!)} · $left',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
        ),
        if (status != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: _statusColor(g.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Text(status,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _statusColor(g.status))),
          ),
      ],
    );
  }

  Widget _menu(GoalModel g) {
    return PopupMenuButton<String>(
      tooltip: 'Hedef seçenekleri',
      icon: Icon(Icons.more_vert, size: 20, color: AppColors.onSurfaceVariant),
      color: AppColors.surface,
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            _openForm(editing: g);
          case 'withdraw':
            _openWithdraw(g);
          case 'delete':
            if (await _confirmDelete(g)) {
              await ApiClient.instance.deleteGoal(g.id);
              _refresh();
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
        if (g.currentAmount > 0)
          const PopupMenuItem(value: 'withdraw', child: Text('Para çek')),
        const PopupMenuItem(value: 'delete', child: Text('Sil')),
      ],
    );
  }

  Widget _error(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(message,
              style: TextStyle(fontSize: 14, color: AppColors.error)),
        );

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder)),
            child: Icon(Icons.savings_outlined,
                size: 30, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Text('Henüz hedefin yok',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text(
              'İlk tasarruf hedefini oluştur ve birikimlerini takip etmeye başla.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, height: 1.5, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 24),
          Press(
            onTap: () => _openForm(),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 26),
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 19, color: AppColors.onPrimary),
                  const SizedBox(width: 8),
                  Text('İlk hedefini ekle',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onPrimary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Alt sayfa kabuğu ----
  Future<void> _sheet(Widget Function(BuildContext, StateSetter) builder) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
              border: Border.all(color: AppColors.glassBorder),
            ),
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                ),
                builder(ctx, setSheet),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetTitle(BuildContext ctx, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.4,
                    color: AppColors.onSurface)),
          ),
          const SizedBox(width: 12),
          Press(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.glassBorder)),
              child:
                  Icon(Icons.close, size: 20, color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Eyebrow(t, size: 11),
      );

  Widget _inputBox({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceBright,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: child,
      );

  static const _bare = InputDecoration(
    isCollapsed: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  );

  Widget _primaryButton(String label, VoidCallback onTap) => Press(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onPrimary)),
        ),
      );

  /// Yeni hedef ya da [editing] verilirse düzenleme. Son tarih isteğe bağlı.
  Future<void> _openForm({GoalModel? editing}) async {
    final nameCtrl = TextEditingController(text: editing?.title ?? '');
    final targetCtrl = TextEditingController(
        text: editing == null ? '' : amountFieldText(editing.targetAmount));
    DateTime? deadline =
        editing?.deadline == null ? null : DateTime.parse(editing!.deadline!);
    String? error;
    var busy = false;

    await _sheet((ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle(ctx, editing == null ? 'Yeni hedef' : 'Hedefi düzenle'),
            _fieldLabel('Hedef adı'),
            _inputBox(
              child: TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 17, color: AppColors.onSurface),
                decoration: _bare.copyWith(
                    hintText: 'örn. Yeni telefon',
                    hintStyle:
                        TextStyle(color: AppColors.outline, fontSize: 17)),
              ),
            ),
            const SizedBox(height: 20),
            _fieldLabel('Hedef tutar (${currencyNotifier.value})'),
            _inputBox(
              child: Row(
                children: [
                  Text(currencyNotifier.value,
                      style: AppText.mono(
                          size: 18, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: targetCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: AppText.mono(size: 18),
                      decoration: _bare.copyWith(hintText: '0'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _fieldLabel('Son tarih (isteğe bağlı)'),
            Press(
              onTap: () async {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final initial = deadline != null && !deadline!.isBefore(today)
                    ? deadline!
                    : DateTime(today.year, today.month + 6, today.day);
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: initial,
                  firstDate: today,
                  lastDate: DateTime(today.year + 30),
                  helpText: 'Hedefin son tarihi',
                  cancelText: 'Vazgeç',
                  confirmText: 'Seç',
                );
                if (picked != null) setSheet(() => deadline = picked);
              },
              child: _inputBox(
                child: Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 19, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          deadline == null
                              ? 'Tarih seç'
                              : DateFormat('d MMMM y', 'tr_TR').format(deadline!),
                          style: TextStyle(
                              fontSize: 17,
                              color: deadline == null
                                  ? AppColors.outline
                                  : AppColors.onSurface)),
                    ),
                    if (deadline != null)
                      Press(
                        onTap: () => setSheet(() => deadline = null),
                        child: Icon(Icons.cancel,
                            size: 18, color: AppColors.outline),
                      ),
                  ],
                ),
              ),
            ),
            _error(error),
            const SizedBox(height: 26),
            _primaryButton(
                busy
                    ? 'Kaydediliyor…'
                    : (editing == null ? 'Hedef oluştur' : 'Kaydet'), () async {
              if (busy) return;
              final name = nameCtrl.text.trim();
              final target = parseAmountToTry(targetCtrl.text);
              if (name.isEmpty || target == null) {
                setSheet(() => error = 'Hedef adı ve tutarı gir.');
                return;
              }
              final iso = deadline == null
                  ? null
                  : DateFormat('yyyy-MM-dd').format(deadline!);
              setSheet(() {
                busy = true;
                error = null;
              });
              try {
                if (editing == null) {
                  await ApiClient.instance.createGoal(name, target, deadline: iso);
                } else {
                  await ApiClient.instance.updateGoal(editing.id,
                      title: name,
                      targetAmount: target,
                      deadline: iso,
                      clearDeadline: iso == null && editing.deadline != null);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _refresh();
              } catch (e) {
                setSheet(() {
                  busy = false;
                  error = errorText(e);
                });
              }
            }),
          ],
        ));
  }

  /// Hedefte biriken paradan geri alma.
  Future<void> _openWithdraw(GoalModel g) async {
    final amtCtrl = TextEditingController();
    String? error;
    await _sheet((ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle(ctx, '${g.title}: para çek'),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text('Birikim ${money(g.currentAmount)}',
                  style: AppText.mono(
                      size: 14, color: AppColors.onSurfaceVariant)),
            ),
            _fieldLabel('Tutar (${currencyNotifier.value})'),
            _inputBox(
              child: Row(
                children: [
                  Text(currencyNotifier.value,
                      style: AppText.mono(
                          size: 18, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: amtCtrl,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: AppText.mono(size: 18),
                      decoration: _bare.copyWith(hintText: '0'),
                    ),
                  ),
                ],
              ),
            ),
            _error(error),
            const SizedBox(height: 26),
            _primaryButton('Çek', () async {
              final amount = parseAmountToTry(amtCtrl.text);
              if (amount == null) {
                setSheet(() => error = 'Tutar gir.');
                return;
              }
              try {
                await ApiClient.instance.withdrawGoal(g.id, amount);
                if (ctx.mounted) Navigator.pop(ctx);
                _refresh();
              } catch (e) {
                setSheet(() => error = errorText(e));
              }
            }),
          ],
        ));
  }

  Future<void> _openContribute(GoalModel g, Color color) async {
    final amtCtrl = TextEditingController();
    final rate = CurrencyService.rates[currencyNotifier.value] ?? 1.0;
    final remain = g.remaining * rate;
    final quick = [500.0, 1000.0, 2500.0]
        .map((q) => q * rate)
        .where((q) => q <= remain)
        .toList();
    if (remain > 0 && !quick.contains(remain)) quick.add(remain);

    await _sheet((ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle(ctx, '${g.title}: katkı ekle'),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                  'Kalan ${money(g.remaining)} · Hedef ${money(g.targetAmount)}',
                  style: AppText.mono(
                      size: 14, color: AppColors.onSurfaceVariant)),
            ),
            _fieldLabel('Tutar (${currencyNotifier.value})'),
            _inputBox(
              child: Row(
                children: [
                  Text(currencyNotifier.value,
                      style: AppText.mono(
                          size: 18, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: amtCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: AppText.mono(size: 18),
                      decoration: _bare.copyWith(hintText: '0'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quick
                  .map((q) => Press(
                        onTap: () =>
                            setSheet(() => amtCtrl.text = q.toStringAsFixed(0)),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(color: AppColors.glassBorder)),
                          child: Text(
                              '+${currencyNotifier.value}${q.toStringAsFixed(0)}',
                              style: AppText.mono(size: 14)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 26),
            _primaryButton('Ekle', () async {
              final amount = parseAmountToTry(amtCtrl.text);
              if (amount == null) return;
              await ApiClient.instance.contributeGoal(g.id, amount);
              if (ctx.mounted) Navigator.pop(ctx);
              _refresh();
            }),
          ],
        ));
  }

  Future<bool> _confirmDelete(GoalModel g) {
    return showConfirmDialog(context,
        title: 'Hedefi sil?',
        message: '"${g.title}" hedefi ve birikimi silinecek.');
  }
}
