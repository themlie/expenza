import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Uyarılar: bütçe, bütçe hızı, hedef, olağandışı harcama ve yaklaşan ödemeler.
/// Uyarılar backend'de o anki verilerden hesaplanır (GET /alerts). Kaydırarak ya da
/// çarpıyla kapatılan uyarı bir daha gösterilmez; aynı türün sonraki ayki uyarısı gelir.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<({List<AlertModel> alerts, bool enabled})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({List<AlertModel> alerts, bool enabled})> _load() async {
    final api = ApiClient.instance;
    final r = await Future.wait([api.getAlerts(), api.getProfile()]);
    return (
      alerts: r[0] as List<AlertModel>,
      enabled: (r[1] as UserModel).alertsEnabled,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _dismiss(List<AlertModel> list, AlertModel a) async {
    setState(() => list.remove(a));
    try {
      await ApiClient.instance.dismissAlert(a.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errorText(e))));
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<({List<AlertModel> alerts, bool enabled})>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (snap.hasError) {
              return LoadError(error: snap.error!, onRetry: _refresh);
            }
            final d = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 52, 20, 40),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _header(),
                const SizedBox(height: 28),
                if (!d.enabled)
                  _empty(Icons.notifications_off_outlined, 'Uyarılar kapalı',
                      'Profil > Bildirimler\'den açabilirsin.')
                else if (d.alerts.isEmpty)
                  _empty(Icons.check_circle_outline, 'Şu an uyarı yok',
                      'Bütçen aşılmaya yaklaşınca ya da hedefin geride kalınca burada görünecek.')
                else ...[
                  Eyebrow('${d.alerts.length} uyarı'),
                  const SizedBox(height: 12),
                  for (var i = 0; i < d.alerts.length; i++)
                    Rise(
                      delayMs: i * 50,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _item(d.alerts, d.alerts[i]),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text('Kapatmak için sola kaydır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.outline)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Press(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(Icons.chevron_left, size: 22, color: AppColors.onSurface),
          ),
        ),
        const SizedBox(width: 14),
        Text('Uyarılar',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                color: AppColors.onSurface)),
      ],
    );
  }

  Widget _empty(IconData icon, String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.outline),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, height: 1.4, color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _item(List<AlertModel> list, AlertModel a) {
    final color = alertColor(a.level);
    final amountLabel = _amountLabel(a);
    return Dismissible(
      key: ValueKey(a.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _dismiss(list, a),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Icon(Icons.close, color: AppColors.onSurfaceVariant),
      ),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(alertIcon(a.kind), size: 19, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurface)),
                  const SizedBox(height: 4),
                  Text(a.message,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.onSurfaceVariant)),
                  if (amountLabel != null || a.dueOn != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        if (amountLabel != null)
                          _meta(amountLabel, money(a.amount!)),
                        if (a.dueOn != null) _meta('Tarih', _date(a.dueOn!)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Kapat',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: AppColors.outline),
              onPressed: () => _dismiss(list, a),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String label, String value) {
    return Text.rich(TextSpan(children: [
      TextSpan(
          text: '$label  ',
          style: TextStyle(fontSize: 13, color: AppColors.outline)),
      TextSpan(
          text: value,
          style: AppText.mono(size: 13, color: AppColors.onSurface)),
    ]));
  }

  String? _amountLabel(AlertModel a) {
    if (a.amount == null) return null;
    return switch (a.kind) {
      'budget' => 'Bu ay harcanan',
      'budget_pace' => 'Ay sonu tahmini',
      'goal' => a.level == 'danger' ? 'Kalan' : 'Ayda gereken',
      _ => 'Tutar',
    };
  }

  String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMMM', 'tr_TR').format(d);
  }
}

/// Uyarı seviyesinin rengi (ana sayfa bandı ve rozet de kullanır).
Color alertColor(String level) => switch (level) {
      'danger' => AppColors.error,
      'warning' => AppColors.warn,
      _ => AppColors.info,
    };

IconData alertIcon(String kind) => switch (kind) {
      'budget' => Icons.pie_chart_outline,
      'budget_pace' => Icons.speed,
      'anomaly' => Icons.warning_amber_rounded,
      'goal' => Icons.flag_outlined,
      'recurring' => Icons.repeat,
      _ => Icons.notifications_none,
    };
