import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../categories.dart';
import '../models.dart';
import '../theme.dart';
import 'goals_screen.dart';
import 'chat_screen.dart';

// Diğer ekranlar ikon ve rengi buradan alıyor; tanımlar categories.dart'ta.
export '../categories.dart' show categoryColor, categoryIcon;

final tl = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
final _grp = NumberFormat('#,##0', 'tr_TR');

/// Premium para gösterimi: işaret + ₺ + binlik ayraç, küsurat varsa 2 hane.
String money(double v, {bool showSign = false}) {
  final converted = CurrencyService.convertFromTry(v, currencyNotifier.value);
  final neg = converted < 0;
  final abs = converted.abs();
  final whole = abs.truncate();
  final cents = ((abs - whole) * 100).round();
  final sign = neg ? '−' : (showSign ? '+' : '');
  final symbol = currencyNotifier.value;
  final base = '$sign$symbol${_grp.format(whole)}';
  final sep = symbol == '₺' ? ',' : '.';
  return cents == 0 ? base : '$base$sep${cents.toString().padLeft(2, '0')}';
}

class _DashData {
  final SummaryModel summary;
  final List<TransactionModel> recent;
  final List<GoalModel> goals;
  final String name;
  _DashData(this.summary, this.recent, this.goals, this.name);
}

class DashboardScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const DashboardScreen({super.key, required this.onLogout});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashData> _load() async {
    final api = ApiClient.instance;
    // Bakiye ve dağılım backend'de bütün işlemlerden hesaplanır; listeden sadece
    // "Son İşlemler" için birkaç kayıt çekilir.
    final r = await Future.wait([
      api.getSummary(),
      api.getTransactions(limit: 6),
      api.getGoals(),
      api.getMe(),
    ]);
    final me = r[3] as ({String email, String displayName});
    final name = me.displayName.isNotEmpty ? me.displayName : 'Kullanıcı';
    return _DashData(r[0] as SummaryModel, r[1] as List<TransactionModel>,
        r[2] as List<GoalModel>, name);
  }

  void refresh() => setState(() { _future = _load(); });

  String get _greeting {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Günaydın';
    if (h >= 12 && h < 18) return 'İyi günler';
    if (h >= 18 && h < 22) return 'İyi akşamlar';
    return 'İyi geceler';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<_DashData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (snap.hasError) {
              return LoadError(error: snap.error!, onRetry: refresh);
            }
            final d = snap.data!;
            final s = d.summary;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 120),
              children: [
                Rise(child: _header(d.name)),
                const SizedBox(height: 40),
                Rise(delayMs: 80, child: _balance(s.balance)),
                const SizedBox(height: 24),
                Rise(
                    delayMs: 160,
                    child: _incomeExpense(s.totalIncome, s.totalExpense)),
                const SizedBox(height: 16),
                if (d.goals.isNotEmpty)
                  Rise(delayMs: 240, child: _goalLine(d.goals.first)),
                const SizedBox(height: 40),
                Rise(
                    delayMs: 300,
                    child: _spending(s.monthByCategory, s.monthExpense)),
                const SizedBox(height: 40),
                Rise(delayMs: 360, child: _recent(d.recent)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.4,
                color: AppColors.onSurface)),
        if (trailing != null) Eyebrow(trailing),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Press(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Icon(icon, size: 19, color: AppColors.onSurface),
      ),
    );
  }

  // ---- Başlık ----
  Widget _header(String name) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(_greeting),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                      color: AppColors.onSurface)),
            ],
          ),
        ),
        _circleButton(Icons.psychology_outlined, () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChatScreen()),
          );
        }),
        const SizedBox(width: 8),
        _circleButton(
            isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            toggleThemeMode),
      ],
    );
  }

  // ---- Bakiye: ince, büyük, 0'dan sayarak gelir ----
  Widget _balance(double balance) {
    final converted = CurrencyService.convertFromTry(balance, currencyNotifier.value);
    final neg = converted < 0;
    final abs = converted.abs();
    final whole = abs.truncate();
    final cents = ((abs - whole) * 100).round();
    final symbol = currencyNotifier.value;
    final sep = symbol == '₺' ? ',' : '.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Toplam bakiye'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountUp(
                  value: whole.toDouble(),
                  format: (v) =>
                      '${neg ? '−' : ''}$symbol${_grp.format(v.round())}',
                  style: AppText.display(size: 58),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 7, left: 2),
              child: Text('$sep${cents.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: AppColors.onSurfaceVariant,
                      fontFeatures: kTnum)),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Gelir / Gider ----
  Widget _incomeExpense(double income, double expense) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _ieCell('Gelir', income, AppColors.positive, '+')),
            Container(width: 1, color: AppColors.glassBorder),
            Expanded(child: _ieCell('Gider', expense, AppColors.onSurface, '−')),
          ],
        ),
      ),
    );
  }

  Widget _ieCell(String label, double value, Color color, String sign) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label, size: 11),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('$sign${money(value)}',
                style: AppText.display(size: 24, color: color)),
          ),
        ],
      ),
    );
  }

  // ---- Tasarruf hedefi: lacivert panel (web'deki hedef kartı) ----
  Widget _goalLine(GoalModel g) {
    final ink = AppColors.onPrimary;
    return Press(
      onTap: () async {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const GoalsScreen()));
        refresh();
      },
      child: GlassCard(
        color: AppColors.primary,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Eyebrow('Tasarruf hedefi',
                    size: 11, color: ink.withValues(alpha: 0.75)),
                Icon(Icons.arrow_forward, size: 18, color: ink),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(g.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w500, color: ink)),
                ),
                Text('%${(g.progress * 100).toStringAsFixed(0)}',
                    style: AppText.mono(size: 15, color: ink)),
              ],
            ),
            const SizedBox(height: 12),
            ExBar(
                value: g.progress,
                color: ink,
                track: ink.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Text('${money(g.currentAmount)} / ${money(g.targetAmount)}',
                style: AppText.mono(size: 13, color: ink.withValues(alpha: 0.75))),
          ],
        ),
      ),
    );
  }

  // ---- Harcama dağılımı: bu ayın giderleri ----
  Widget _spending(
      List<({String category, double total})> byCategory, double expense) {
    // Backend zaten büyükten küçüğe sıralı gönderir.
    final entries = [for (final c in byCategory) MapEntry(c.category, c.total)];
    final top = entries.take(4).toList();

    Color ramp(int i) => categoryColor(top[i].key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Harcama dağılımı',
            trailing: DateFormat.MMMM('tr_TR').format(DateTime.now())),
        const SizedBox(height: 16),
        GlassCard(
          child: entries.isEmpty
              ? Text('Bu ay henüz gider yok.',
                  style:
                      TextStyle(fontSize: 16, color: AppColors.onSurfaceVariant))
              : Row(
                  children: [
                    SizedBox(
                      width: 124,
                      height: 124,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Halka açılışta incelikten kalınlığa büyür.
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: AppMotion.slow,
                            curve: AppMotion.curve,
                            builder: (context, t, _) => PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                startDegreeOffset: -90,
                                centerSpaceRadius: 44,
                                sections: [
                                  for (var i = 0; i < top.length; i++)
                                    PieChartSectionData(
                                      value: top[i].value,
                                      color: ramp(i),
                                      radius: 2 + 10 * t,
                                      showTitle: false,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Eyebrow('Gider', size: 10),
                              const SizedBox(height: 4),
                              Text(money(expense), style: AppText.mono(size: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = 0; i < top.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: ramp(i),
                                        borderRadius: BorderRadius.circular(3)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(top[i].key,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: AppColors.onSurface)),
                                  ),
                                  Text(
                                      '%${(expense == 0 ? 0 : top[i].value / expense * 100).toStringAsFixed(0)}',
                                      style: AppText.mono(
                                          size: 13,
                                          color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ---- Son işlemler: fiş düzeni (not ..... tutar) ----
  Widget _recent(List<TransactionModel> txs) {
    final list = txs.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Son işlemler'),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Henüz işlem yok. + ile ekle.',
                style:
                    TextStyle(fontSize: 16, color: AppColors.onSurfaceVariant)),
          )
        else
          for (var i = 0; i < list.length; i++)
            Rise(
                delayMs: 400 + i * 60,
                child: _txRow(list[i], i < list.length - 1)),
      ],
    );
  }

  Widget _txRow(TransactionModel t, bool border) {
    final isIncome = t.type == 'income';
    final title = t.note.isEmpty ? t.category : t.note;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: border
            ? Border(bottom: BorderSide(color: AppColors.glassBorder))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LeaderRow(
            left: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface)),
            right: Text('${isIncome ? '+' : '−'}${money(t.amount)}',
                style: AppText.mono(
                    size: 15,
                    color: isIncome ? AppColors.positive : AppColors.onSurface)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: categoryColor(t.category),
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Eyebrow(t.category, size: 11),
              const SizedBox(width: 10),
              Text(t.occurredOn,
                  style:
                      AppText.mono(size: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
