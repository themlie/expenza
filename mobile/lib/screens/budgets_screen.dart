import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../currency.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Bütçe ekranı: toplam bütçe kartı, kategori kartları, alttan açılan
/// ekle/düzenle/sil sayfası. Gerçek backend'e bağlı.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => BudgetsScreenState();
}

class BudgetsScreenState extends State<BudgetsScreen> {
  late Future<List<BudgetModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.getBudgets();
  }

  void refresh() => setState(() { _future = ApiClient.instance.getBudgets(); });

  Color _statusColor(double pct) {
    if (pct >= 90) return AppColors.error;
    if (pct >= 75) return AppColors.warn;
    return AppColors.onSurface;
  }

  ({String label, Color color}) _status(double pct) {
    if (pct >= 100) return (label: 'Aşıldı', color: AppColors.error);
    if (pct >= 90) return (label: 'Kritik', color: AppColors.error);
    if (pct >= 75) return (label: 'Dikkat', color: AppColors.warn);
    return (label: 'Yolunda', color: AppColors.positive);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<List<BudgetModel>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (snap.hasError) {
              return LoadError(error: snap.error!, onRetry: refresh);
            }
            final budgets = snap.data ?? [];
            final categoryBudgets = budgets.where((b) => b.category != kTotalBudget).toList();
            final totalBudget = budgets.firstWhere(
              (b) => b.category == kTotalBudget,
              orElse: () => BudgetModel(id: -1, category: kTotalBudget, monthlyLimit: 0.0, spent: 0.0),
            );

            final spent = totalBudget.id == -1
                ? categoryBudgets.fold(0.0, (s, b) => s + b.spent)
                : totalBudget.spent;
            final limit = totalBudget.monthlyLimit;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 120),
              children: [
                Rise(child: _header(isDark)),
                const SizedBox(height: 28),
                Rise(delayMs: 80, child: _totalCard(limit, spent, totalBudget, budgets)),
                const SizedBox(height: 36),
                Rise(
                  delayMs: 160,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Kategori bütçeleri',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.4,
                              color: AppColors.onSurface)),
                      Press(
                        onTap: () => _openSheet(budgets, null),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 18, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text('Bütçe',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (categoryBudgets.isEmpty)
                  Rise(
                    delayMs: 220,
                    child: GlassCard(
                      child: Text('Henüz bütçe yok. "Bütçe" ile ekle.',
                          style: TextStyle(
                              fontSize: 16, color: AppColors.onSurfaceVariant)),
                    ),
                  )
                else
                  for (var i = 0; i < categoryBudgets.length; i++)
                    Rise(
                        delayMs: 220 + i * 60,
                        child: _budgetCard(categoryBudgets[i], budgets)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(DateFormat('MMMM yyyy', 'tr_TR').format(DateTime.now())),
            const SizedBox(height: 10),
            Text('Bütçe', style: AppText.display(size: 38)),
            const SizedBox(height: 8),
            Text('Aylık limitler',
                style: TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant)),
          ],
        ),
        Press(
          onTap: toggleThemeMode,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder)),
            child: Icon(
                isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 19,
                color: AppColors.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _totalCard(double limit, double spent, BudgetModel totalBudget, List<BudgetModel> all) {
    final remain = limit - spent;
    final pct = limit == 0 ? 0.0 : (spent / limit * 100);
    final color = _statusColor(pct);
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = lastDay - now.day;

    return Press(
      onTap: () => _openSheet(all, totalBudget.id == -1 ? null : totalBudget, isTotal: true),
      child: GlassCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Eyebrow(
                      limit == 0 ? 'Toplam bütçe belirle' : 'Toplam aylık bütçe',
                      size: 11),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: (limit == 0 ? AppColors.onSurfaceVariant : color)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(
                      limit == 0
                          ? 'Limit yok'
                          : '%${pct.toStringAsFixed(0)} kullanıldı',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: limit == 0 ? AppColors.onSurfaceVariant : color,
                          fontFeatures: kTnum)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Kalan', size: 11),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(money(remain),
                            style: AppText.display(
                                size: 40,
                                color: remain < 0
                                    ? AppColors.error
                                    : AppColors.onSurface)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Eyebrow('Limit', size: 11),
                    const SizedBox(height: 8),
                    Text(money(limit),
                        style: AppText.mono(
                            size: 16, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            ExBar(value: pct / 100, color: color, height: 10),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${money(spent)} harcandı',
                    style: AppText.mono(
                        size: 13, color: AppColors.onSurfaceVariant)),
                Text('Ay sonuna $daysLeft gün',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _budgetCard(BudgetModel b, List<BudgetModel> all) {
    final pct = b.monthlyLimit == 0 ? 0.0 : (b.spent / b.monthlyLimit * 100);
    final color = _statusColor(pct);
    final st = _status(pct);
    final cc = categoryColor(b.category);
    return Press(
      onTap: () => _openSheet(all, b),
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: cc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Icon(categoryIcon(b.category), size: 18, color: cc),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(b.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.onSurface)),
                          ),
                          const SizedBox(width: 10),
                          Eyebrow(st.label, size: 10, color: st.color),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: money(b.spent)),
                          TextSpan(
                              text: ' / ${money(b.monthlyLimit)}',
                              style: TextStyle(color: AppColors.onSurfaceVariant)),
                        ]),
                        style: AppText.mono(size: 13),
                      ),
                    ],
                  ),
                ),
                Text('%${pct.toStringAsFixed(0)}',
                    style: AppText.mono(size: 16, color: color)),
              ],
            ),
            const SizedBox(height: 14),
            ExBar(value: pct / 100, color: color),
          ],
        ),
      ),
    );
  }

  // ---- Ekle / Düzenle / Sil alt sayfası ----
  Future<void> _openSheet(List<BudgetModel> all, BudgetModel? editing, {bool isTotal = false}) async {
    final usedCats = all.map((b) => b.category).toSet();
    final available = isTotal
        ? [kTotalBudget]
        : (editing != null
            ? [editing.category]
            : kCategories.where((c) => !usedCats.contains(c)).toList());
    if (available.isEmpty && !isTotal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tüm kategoriler için bütçe tanımlı.')));
      return;
    }

    String chosen = isTotal ? kTotalBudget : (editing?.category ?? available.first);
    final initialLimit = editing != null && editing.monthlyLimit > 0
        ? CurrencyService.convertFromTry(editing.monthlyLimit, currencyNotifier.value)
        : 0.0;
    final limitCtrl = TextEditingController(
        text: initialLimit > 0 ? initialLimit.toStringAsFixed(0) : '');

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl)),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(isTotal
                              ? (editing != null && editing.monthlyLimit > 0 ? 'Toplam bütçeyi düzenle' : 'Toplam bütçe belirle')
                              : (editing != null ? '${editing.category} bütçesi' : 'Yeni bütçe'),
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: -0.4,
                                  color: AppColors.onSurface)),
                        ),
                        Press(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.glassBorder)),
                            child: Icon(Icons.close,
                                size: 20, color: AppColors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (!isTotal) ...[
                      const Eyebrow('Kategori', size: 11),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: available.map((c) {
                          final on = c == chosen;
                          final cc = categoryColor(c);
                          return GestureDetector(
                            onTap: editing != null
                                ? null
                                : () => setSheet(() => chosen = c),
                            child: AnimatedContainer(
                              duration: AppMotion.fast,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: on ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                border: Border.all(
                                    color: on
                                        ? AppColors.primary
                                        : AppColors.glassBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: cc, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(c,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: on
                                              ? AppColors.onPrimary
                                              : AppColors.onSurface)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 22),
                    ],
                    Eyebrow('Aylık limit (${currencyNotifier.value})', size: 11),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBright,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        children: [
                          Text(currencyNotifier.value,
                              style: AppText.mono(
                                  size: 18, color: AppColors.onSurfaceVariant)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: limitCtrl,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              style: AppText.mono(size: 18),
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                hintText: '0',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        if (editing != null) ...[
                          Press(
                            onTap: () async {
                              await ApiClient.instance.deleteBudget(editing.id);
                              if (ctx.mounted) Navigator.pop(ctx);
                              refresh();
                            },
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.glassBorder)),
                              child: Icon(Icons.delete_outline,
                                  color: AppColors.error, size: 21),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Press(
                            onTap: () async {
                              final limit = parseAmountToTry(limitCtrl.text);
                              if (limit == null) return;
                              await ApiClient.instance.upsertBudget(chosen, limit);
                              if (ctx.mounted) Navigator.pop(ctx);
                              refresh();
                            },
                            child: Container(
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppRadius.pill)),
                              child: Text(
                                  editing != null ? 'Kaydet' : 'Bütçe ekle',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.onPrimary)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
