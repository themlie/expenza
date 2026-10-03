import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import 'dashboard_screen.dart' show categoryColor, categoryIcon, money;

/// Analitik (İP-4): tahmin paneli, harcama trendi (gerçekleşen + tahmin),
/// harcama hızı, olağandışı harcamalar, en çok harcanan kategoriler.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => AnalyticsScreenState();
}

class AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<_Data> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void refresh() => setState(() { _future = _load(); });

  Future<_Data> _load() async {
    final api = ApiClient.instance;
    final r = await Future.wait([
      api.getForecast(),
      api.getAnomalies(),
      api.getSummary(),
    ]);
    return _Data(r[0] as ForecastModel, r[1] as List<AnomalyModel>,
        r[2] as SummaryModel);
  }

  String _monthShort(String yyyyMm) {
    const m = ['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'];
    final p = yyyyMm.split('-');
    final i = p.length == 2 ? (int.tryParse(p[1]) ?? 1) : 1;
    return (i >= 1 && i <= 12) ? m[i - 1] : yyyyMm;
  }

  // Koyu panel (web'deki "Gelecek ay tahmini" kartı). Koyu modda bir ton açık.
  Color get _panelBg =>
      AppColors.isDark ? AppColors.surfaceContainer : const Color(0xFF26282C);
  static const _panelInk = Color(0xFFEDE6D9);
  static const _panelMuted = Color(0xFFA9A69E);
  static const _panelLine = Color(0xFF44474D);

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<_Data>(
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 120),
              children: [
                Rise(child: _header(isDark)),
                const SizedBox(height: 28),
                Rise(delayMs: 80, child: _forecastCard(d.forecast)),
                const SizedBox(height: 16),
                Rise(delayMs: 160, child: _trendCard(d.forecast)),
                const SizedBox(height: 16),
                Rise(delayMs: 240, child: _velocityCard(d.forecast)),
                const SizedBox(height: 36),
                Rise(delayMs: 300, child: _anomaliesSection(d.anomalies)),
                const SizedBox(height: 36),
                Rise(delayMs: 360, child: _topCategories(d.summary)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _title(String text, {Widget? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(text,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.4,
                  color: AppColors.onSurface)),
        ),
        ?trailing,
      ],
    );
  }

  Widget _header(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(DateFormat('MMMM yyyy', 'tr_TR').format(DateTime.now())),
              const SizedBox(height: 10),
              Text('Analitik', style: AppText.display(size: 38)),
              const SizedBox(height: 8),
              Text('Ay bitmeden ay sonunu gör.',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 12),
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

  // ---- Tahmin paneli ----
  Widget _forecastCard(ForecastModel f) {
    final last = f.history.isNotEmpty ? f.history.last.total : 0.0;
    final hasChange = last > 0;
    final pct = hasChange ? (f.nextMonthPrediction - last) / last * 100 : 0.0;
    final up = pct >= 0;
    return GlassCard(
      color: _panelBg,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Gelecek ay tahmini', color: _panelMuted),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUp(
              value: f.nextMonthPrediction,
              format: money,
              style: AppText.display(size: 52, color: _panelInk),
            ),
          ),
          const SizedBox(height: 14),
          if (hasChange)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: _panelInk.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 14,
                      color: up ? const Color(0xFFE0916B) : const Color(0xFFA9B8DC)),
                  const SizedBox(width: 6),
                  Text('%${pct.abs().toStringAsFixed(0)} geçen aya göre',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _panelInk,
                          fontFeatures: kTnum)),
                ],
              ),
            )
          else
            const Text('Mevcut verilere göre tahmin',
                style: TextStyle(fontSize: 14, color: _panelMuted)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.only(top: 18),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _panelLine))),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                      child: _miniCol('Ay sonu projeksiyonu', f.projectedMonthEnd)),
                  Container(width: 1, color: _panelLine),
                  Expanded(
                      child: _miniCol('Bu ana dek', f.currentMonthSpent,
                          padLeft: true)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCol(String label, double value, {bool padLeft = false}) {
    return Padding(
      padding: EdgeInsets.only(left: padLeft ? 18 : 0, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label, size: 10, color: _panelMuted),
          const SizedBox(height: 8),
          Text(money(value), style: AppText.mono(size: 16, color: _panelInk)),
        ],
      ),
    );
  }

  // ---- Harcama trendi ----
  Widget _trendCard(ForecastModel f) {
    final solid = <double>[...f.history.map((h) => h.total), f.projectedMonthEnd];
    final labels = <String>[
      ...f.history.map((h) => _monthShort(h.month)),
      'Bu ay',
      'Tahmin'
    ];
    if (solid.length < 2) return const SizedBox.shrink();
    final lastIdx = solid.length - 1; // current month (last solid)
    final all = [...solid, f.nextMonthPrediction];
    final maxV = all.reduce((a, b) => a > b ? a : b) * 1.12;
    final minV = all.reduce((a, b) => a < b ? a : b) * 0.85;
    final forecastColor = AppColors.info;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Harcama trendi',
              trailing: const Eyebrow('Geçmiş + tahmin', size: 10)),
          const SizedBox(height: 18),
          SizedBox(
            height: 160,
            // Çizgiler açılışta tabandan yükselir.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.slow,
              curve: AppMotion.curve,
              builder: (context, t, _) {
                double y(double v) => minV + (v - minV) * t;
                final solidSpots = [
                  for (var i = 0; i < solid.length; i++)
                    FlSpot(i.toDouble(), y(solid[i]))
                ];
                final dashedSpots = [
                  FlSpot(lastIdx.toDouble(), y(solid[lastIdx])),
                  FlSpot((lastIdx + 1).toDouble(), y(f.nextMonthPrediction)),
                ];
                return LineChart(
                  duration: Duration.zero,
                  LineChartData(
                    minY: minV,
                    maxY: maxV,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: (maxV - minV) / 2,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: AppColors.glassBorder, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          reservedSize: 28,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= labels.length) {
                              return const SizedBox.shrink();
                            }
                            final isForecast = i == labels.length - 1;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(trUpper(labels[i]),
                                  style: AppText.label(
                                      size: 10,
                                      color: isForecast
                                          ? forecastColor
                                          : AppColors.onSurfaceVariant)),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      // Gerçekleşen (düz)
                      LineChartBarData(
                        spots: solidSpots,
                        isCurved: true,
                        color: AppColors.onSurface,
                        barWidth: 2,
                        dotData: FlDotData(
                          show: true,
                          checkToShowDot: (s, _) => s.x.toInt() == lastIdx,
                          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                              radius: 4,
                              color: AppColors.onSurface,
                              strokeWidth: 2,
                              strokeColor: AppColors.surface),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      // Tahmin (kesikli)
                      LineChartBarData(
                        spots: dashedSpots,
                        isCurved: false,
                        color: forecastColor,
                        barWidth: 2,
                        dashArray: [5, 5],
                        dotData: FlDotData(
                          show: true,
                          checkToShowDot: (s, _) => s.x.toInt() == lastIdx + 1,
                          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                              radius: 5,
                              color: AppColors.surface,
                              strokeColor: forecastColor,
                              strokeWidth: 2),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(AppColors.onSurface, 'Gerçekleşen'),
              const SizedBox(width: 20),
              _legend(forecastColor, 'Tahmin'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      children: [
        Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
      ],
    );
  }

  // ---- Harcama hızı ----
  Widget _velocityCard(ForecastModel f) {
    final day = DateTime.now().day;
    final dailyAvg = day > 0 ? f.currentMonthSpent / day : 0.0;
    final activeIdx = switch (f.velocity) {
      'Düşük' => 0,
      'Normal' => 1,
      'Yüksek' => 2,
      _ => 1,
    };
    final segColors = [
      AppColors.positive,
      AppColors.warn,
      AppColors.error,
      AppColors.surfaceContainerHigh
    ];
    final labelColor = switch (f.velocity) {
      'Düşük' => AppColors.positive,
      'Yüksek' => AppColors.error,
      _ => AppColors.warn,
    };
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: labelColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(Icons.bolt, color: labelColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Harcama hızı', size: 11),
                    const SizedBox(height: 4),
                    Text(f.velocity,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: AppColors.onSurface)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Eyebrow('Günlük ort.', size: 10),
                  const SizedBox(height: 6),
                  Text(money(dailyAvg), style: AppText.mono(size: 15)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 400 + i * 120),
                    curve: AppMotion.curve,
                    builder: (context, t, _) => Opacity(
                      opacity: i == activeIdx ? 1 : 0.35,
                      child: Transform.scale(
                        scaleX: t,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: i == activeIdx ? 8 : 6,
                          decoration: BoxDecoration(
                              color: segColors[i],
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill)),
                        ),
                      ),
                    ),
                  ),
                ),
                if (i < 3) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final e in ['Düşük', 'Normal', 'Yüksek', 'Aşırı'].asMap().entries)
                Text(e.value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            e.key == activeIdx ? FontWeight.w500 : FontWeight.w400,
                        color: e.key == activeIdx
                            ? labelColor
                            : AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Anomaliler ----
  Widget _anomaliesSection(List<AnomalyModel> anomalies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Olağandışı harcamalar',
            trailing: anomalies.isEmpty
                ? null
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.errorSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PingDot(color: AppColors.error, size: 6),
                        const SizedBox(width: 8),
                        Text('${anomalies.length} uyarı',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.error)),
                      ],
                    ),
                  )),
        const SizedBox(height: 8),
        Text('Bir harcama alışkanlığından belirgin biçimde büyükse işaretlenir.',
            style: TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (anomalies.isEmpty)
          GlassCard(
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 20, color: AppColors.positive),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Olağandışı harcama yok.',
                      style: TextStyle(
                          fontSize: 16, color: AppColors.onSurfaceVariant)),
                ),
              ],
            ),
          )
        else
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < anomalies.length; i++)
                  _anomalyRow(anomalies[i], i < anomalies.length - 1),
              ],
            ),
          ),
      ],
    );
  }

  Widget _anomalyRow(AnomalyModel a, bool border) {
    final high = a.severity == 'high';
    final col = high ? AppColors.error : AppColors.warn;
    final cc = categoryColor(a.category);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: border
            ? Border(bottom: BorderSide(color: AppColors.glassBorder))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: cc.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(categoryIcon(a.category), size: 17, color: cc),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.note.isEmpty ? 'Olağandışı ${a.category}' : a.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface)),
                const SizedBox(height: 3),
                Text(a.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('−${money(a.amount)}', style: AppText.mono(size: 14)),
              const SizedBox(height: 4),
              Eyebrow(high ? 'Yüksek' : 'Orta', size: 10, color: col),
            ],
          ),
        ],
      ),
    );
  }

  // ---- En çok harcanan kategoriler ----
  // Bu ayın giderleri backend'de bütün işlemlerden toplanır (büyükten küçüğe gelir).
  Widget _topCategories(SummaryModel summary) {
    final list = summary.monthByCategory
        .take(5)
        .map((c) => MapEntry(c.category, c.total))
        .toList();
    final max = list.isEmpty ? 1.0 : list.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Bu ay en çok harcanan kategoriler'),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('Veri yok',
                      style: TextStyle(
                          fontSize: 16, color: AppColors.onSurfaceVariant)),
                )
              else
                for (final e in list) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: categoryColor(e.key),
                                borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 10),
                          Text(e.key,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurface)),
                        ],
                      ),
                      Text(money(e.value), style: AppText.mono(size: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ExBar(
                      value: max == 0 ? 0 : e.value / max,
                      color: categoryColor(e.key)),
                  const SizedBox(height: 18),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Data {
  final ForecastModel forecast;
  final List<AnomalyModel> anomalies;
  final SummaryModel summary;
  _Data(this.forecast, this.anomalies, this.summary);
}
