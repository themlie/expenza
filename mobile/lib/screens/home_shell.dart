import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'analytics_screen.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// Alt navigasyonlu ana kabuk: 5 sekme. Bulanık cam yerine düz bej çubuk ve
/// aktif sekmenin üstünde kayan ince lacivert çizgi.
class HomeShell extends StatefulWidget {
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.onLogout});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Sekmeler ilk açıldıklarında kurulur (ve verilerini o zaman yükler); sonra
  // IndexedStack içinde durumlarını korurlar. Girişte yalnızca ana sayfa yüklenir.
  final _visited = <int>{0};

  final _dashKey = GlobalKey<DashboardScreenState>();
  final _budgetKey = GlobalKey<BudgetsScreenState>();
  final _historyKey = GlobalKey<HistoryScreenState>();
  final _analyticsKey = GlobalKey<AnalyticsScreenState>();

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Ana Sayfa'),
    (Icons.swap_vert_outlined, Icons.swap_vert, 'İşlemler'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Analitik'),
    (Icons.pie_chart_outline, Icons.pie_chart, 'Bütçe'),
    (Icons.person_outline, Icons.person, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(key: _dashKey, onLogout: widget.onLogout),
      HistoryScreen(
        key: _historyKey,
        onTransactionAdded: () {
          _dashKey.currentState?.refresh();
          _budgetKey.currentState?.refresh();
          _analyticsKey.currentState?.refresh();
        },
      ),
      AnalyticsScreen(key: _analyticsKey),
      BudgetsScreen(key: _budgetKey),
      ProfileScreen(onLogout: widget.onLogout),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: [
        for (var i = 0; i < pages.length; i++)
          _visited.contains(i) ? pages[i] : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.navBg,
          border: Border(top: BorderSide(color: AppColors.glassBorder)),
        ),
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _items.length; i++) _navItem(i),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int i) {
    final active = _index == i;
    final color = active ? AppColors.primary : AppColors.onSurfaceVariant;
    final (outlined, filled, label) = _items[i];
    return Expanded(
      child: Press(
        onTap: () => setState(() {
          _index = i;
          _visited.add(i);
        }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.medium,
              curve: AppMotion.curve,
              height: 2,
              width: active ? 28 : 0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedScale(
              scale: active ? 1.08 : 1.0,
              duration: AppMotion.fast,
              child: Icon(active ? filled : outlined, size: 22, color: color),
            ),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
