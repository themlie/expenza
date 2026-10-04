import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../currency.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../wordmark.dart';
import 'account_screen.dart';

/// Profil: kullanıcı kartı, finansal içgörüler, ayarlar, çıkış.
class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_Data> _future;
  bool _notif = true;
  bool? _aiConsent; // null = henüz yüklenmedi
  DateTime? _memberSince; // üyelik tarihi (kayıt)

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Yapay zekâ onayı ve uyarı tercihi sunucuda saklanır.
    ApiClient.instance.getProfile().then((u) {
      if (mounted) {
        setState(() {
          _aiConsent = u.aiConsent;
          _notif = u.alertsEnabled;
          _memberSince = u.createdAt;
        });
      }
    }).catchError((_) {});
  }

  /// Ad değişmiş olabilir; dönünce profil yeniden yüklenir.
  Future<void> _openAccount() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _setNotif(bool value) async {
    setState(() => _notif = value);
    try {
      await ApiClient.instance.updateProfile(alertsEnabled: value);
    } catch (e) {
      if (mounted) {
        setState(() => _notif = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorText(e))));
      }
    }
  }

  Future<void> _setAiConsent(bool value) async {
    try {
      await ApiClient.instance.setAiConsent(value);
      if (mounted) setState(() => _aiConsent = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorText(e))));
      }
    }
  }

  Future<_Data> _load() async {
    final api = ApiClient.instance;
    final r = await Future.wait([api.getMe(), api.getInsights()]);
    return _Data(r[0] as ({String email, String displayName}),
        r[1] as List<InsightModel>);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        color: AppColors.onSurface,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<_Data>(
          future: _future,
          builder: (context, snap) {
            final me = snap.data?.me;
            final insights = snap.data?.insights ?? [];
            final name = (me?.displayName.isNotEmpty ?? false)
                ? me!.displayName
                : 'Kullanıcı';

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 120),
              children: [
                // Başlık
                Rise(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Eyebrow('Hesabın'),
                          const SizedBox(height: 10),
                          Text('Profil', style: AppText.display(size: 38)),
                        ],
                      ),
                      Tooltip(
                        message: 'Hesap ayarları',
                        child: Press(
                          onTap: _openAccount,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: AppColors.glassBorder)),
                            child: Icon(Icons.settings_outlined,
                                size: 19, color: AppColors.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Kullanıcı kartı
                Rise(delayMs: 80, child: _userCard(name, me?.email ?? '')),
                const SizedBox(height: 36),

                // İçgörüler
                Rise(delayMs: 140, child: _sectionTitle('Senin için içgörüler')),
                const SizedBox(height: 14),
                if (snap.connectionState == ConnectionState.waiting)
                  Center(
                      child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ))
                else if (insights.isEmpty)
                  _insightShell(AppColors.outline, Icons.info_outline,
                      'Birkaç işlem ekledikçe içgörüler burada görünecek.')
                else
                  for (var i = 0; i < insights.length; i++)
                    Rise(delayMs: 180 + i * 60, child: _insightCard(insights[i])),
                const SizedBox(height: 36),

                // Ayarlar
                Rise(delayMs: 240, child: _sectionTitle('Ayarlar')),
                const SizedBox(height: 14),
                Rise(delayMs: 280, child: _settings(isDark)),
                const SizedBox(height: 18),

                // Çıkış
                Press(
                  onTap: () {
                    ApiClient.instance.logout();
                    widget.onLogout();
                  },
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, size: 18, color: AppColors.error),
                        const SizedBox(width: 9),
                        Text('Çıkış yap',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.error)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Center(
                  child: ExpenzaWordmark(
                      height: 16, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text('Kişisel finans takibi ve harcama analizi',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.onSurfaceVariant)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.4,
          color: AppColors.onSurface));

  Widget _userCard(String name, String email) {
    return Press(
      onTap: _openAccount,
      child: _userCardBody(name, email),
    );
  }

  Widget _userCardBody(String name, String email) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(_initials(name),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                    color: AppColors.onPrimary)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface)),
                const SizedBox(height: 2),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, color: AppColors.onSurfaceVariant)),
                if (_memberSince != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available_outlined,
                            size: 13, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Text(
                            'Üye: ${DateFormat('MMMM y', 'tr_TR').format(_memberSince!)}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: AppColors.onSurfaceVariant),
        ],
      ),
    );
  }

  Color _toneColor(String tone) => switch (tone) {
        'good' => AppColors.positive,
        'warn' => AppColors.warn,
        _ => AppColors.info,
      };

  IconData _iconFor(String name) => switch (name) {
        'trending_up' => Icons.trending_up,
        'trending_down' => Icons.trending_down,
        'savings' => Icons.savings,
        'pie_chart' => Icons.pie_chart,
        'category' => Icons.category,
        'warning' => Icons.warning_amber_rounded,
        _ => Icons.lightbulb_outline,
      };

  Widget _insightCard(InsightModel ins) {
    final color = _toneColor(ins.tone);
    return _insightShell(color, _iconFor(ins.icon), ins.text, title: ins.title);
  }

  Widget _insightShell(Color color, IconData icon, String text,
      {String? title}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurface)),
                  const SizedBox(height: 4),
                ],
                Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: AppColors.glassBorder)),
        title: Text(title,
            style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w500)),
        content: Text(message,
            style: TextStyle(
                color: AppColors.onSurfaceVariant, fontSize: 16, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Kapat',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _showCurrencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: AppColors.glassBorder)),
          title: Text('Para birimi seç',
              style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w500)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _currencyOption(context, 'Türk Lirası (₺)', '₺'),
              _currencyOption(context, 'Dolar (\$)', '\$'),
              _currencyOption(context, 'Euro (€)', '€'),
              _currencyOption(context, 'Sterlin (£)', '£'),
            ],
          ),
        );
      },
    );
  }

  Widget _currencyOption(BuildContext context, String label, String symbol) {
    final active = currencyNotifier.value == symbol;
    return ListTile(
      title: Text(label, style: TextStyle(color: AppColors.onSurface, fontSize: 17)),
      trailing: active ? Icon(Icons.check, color: AppColors.primary, size: 18) : null,
      onTap: () {
        currencyNotifier.value = symbol;
        Navigator.of(context).pop();
        setState(() {});
      },
    );
  }

  Widget _settings(bool isDark) {
    final curVal = currencyNotifier.value;
    final curLabel = curVal == '₺'
        ? 'Türk Lirası (₺)'
        : curVal == '\$'
            ? 'Dolar (\$)'
            : curVal == '€'
                ? 'Euro (€)'
                : 'Sterlin (£)';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              final dark = mode == ThemeMode.dark;
              return _settingRow(
                AppColors.info,
                dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                'Tema',
                subtitle: dark ? 'Koyu mod' : 'Açık mod',
                trailing: _miniSwitch(dark, (_) => toggleThemeMode()),
              );
            },
          ),
          _divider(),
          _settingRow(AppColors.positive, Icons.attach_money, 'Para birimi',
              value: curLabel, chevron: true, onTap: () {
            _showCurrencyDialog(context);
          }),
          _divider(),
          _settingRow(AppColors.info, Icons.manage_accounts_outlined, 'Hesap',
              subtitle: 'Ad, şifre, hesabı silme',
              chevron: true,
              onTap: _openAccount),
          _divider(),
          _settingRow(AppColors.catPurple, Icons.grid_view, 'Kategoriler',
              value: '${kCategories.length} kategori', chevron: true, onTap: () {
            _showInfoDialog(context, 'Kategoriler',
                'Aktif Kategoriler:\n${kCategories.map((c) => '• $c').join('\n')}');
          }),
          _divider(),
          _settingRow(
            AppColors.warn,
            Icons.notifications_outlined,
            'Bildirimler',
            subtitle: _notif ? 'Bütçe, hedef ve ödeme uyarıları' : 'Kapalı',
            trailing: _miniSwitch(_notif, _setNotif),
          ),
          if (_aiConsent != null) ...[
            _divider(),
            _settingRow(
              AppColors.info,
              Icons.psychology_outlined,
              'Yapay zekâ veri paylaşımı',
              subtitle: _aiConsent!
                  ? 'Sohbet için veriler Google Gemini\'ye gidiyor'
                  : 'Kapalı',
              trailing: _miniSwitch(_aiConsent!, _setAiConsent),
            ),
          ],
          _divider(),
          _settingRow(AppColors.outline, Icons.info_outline, 'Sürüm',
              value: 'v$appVersion'),
        ],
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.only(left: 66),
        child: Container(height: 1, color: AppColors.glassBorder),
      );

  Widget _settingRow(Color iconColor, IconData icon, String title,
      {String? subtitle,
      String? value,
      bool chevron = false,
      Widget? trailing,
      VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        color: AppColors.onSurface)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 14, color: AppColors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (value != null)
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurfaceVariant)),
          if (chevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: AppColors.onSurfaceVariant),
          ],
          ?trailing,
        ],
      ),
    );

    if (onTap != null) {
      return Press(onTap: onTap, child: row);
    }
    return row;
  }

  Widget _miniSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.primary : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: AnimatedAlign(
          duration: AppMotion.medium,
          curve: AppMotion.curve,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: value ? AppColors.onPrimary : AppColors.background,
                shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _Data {
  final ({String email, String displayName}) me;
  final List<InsightModel> insights;
  _Data(this.me, this.insights);
}
