import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import 'add_transaction_screen.dart';
import 'dashboard_screen.dart' show categoryColor, categoryIcon, money;

/// Tam işlem geçmişi — premium: tarihe göre gruplu, arama, kategori çipleri,
/// sola kaydır→sil, dokun→düzenle.
class HistoryScreen extends StatefulWidget {
  final VoidCallback? onTransactionAdded;
  const HistoryScreen({super.key, this.onTransactionAdded});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  late Future<List<TransactionModel>> _future;
  String? _category;
  String _query = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<TransactionModel>> _load() =>
      ApiClient.instance.getTransactions(category: _category, q: _query);

  void refresh() => setState(() { _future = _load(); });

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      refresh();
    });
  }

  Future<void> _edit(TransactionModel tx) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => AddTransactionScreen(existing: tx)));
    if (ok == true) {
      refresh();
      widget.onTransactionAdded?.call();
    }
  }

  Future<void> _openAdd() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
    );
    if (added == true) {
      refresh();
      widget.onTransactionAdded?.call();
    }
  }

  /// occurred_on (YYYY-MM-DD) -> "Bugün" / "Dün" / "12 Haziran".
  String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return DateFormat('d MMMM', 'tr_TR').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      body: Column(
        children: [
          // ---- Başlık ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
            child: FutureBuilder<List<TransactionModel>>(
              future: _future,
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow(DateFormat('MMMM yyyy', 'tr_TR')
                            .format(DateTime.now())),
                        const SizedBox(height: 10),
                        Text('İşlemler', style: AppText.display(size: 38)),
                        const SizedBox(height: 8),
                        Text('$count işlem',
                            style: TextStyle(
                                fontSize: 15,
                                color: AppColors.onSurfaceVariant)),
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
                            isDark
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                            size: 19,
                            color: AppColors.onSurface),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 22),

          // ---- Arama ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: AppColors.surfaceBright,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 19, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearch,
                      style:
                          TextStyle(fontSize: 17, color: AppColors.onSurface),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'İşlem veya not ara…',
                        hintStyle:
                            TextStyle(color: AppColors.outline, fontSize: 17),
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    Press(
                      onTap: () {
                        _searchCtrl.clear();
                        _query = '';
                        refresh();
                      },
                      child: Icon(Icons.cancel,
                          size: 18, color: AppColors.outline),
                    ),
                ],
              ),
            ),
          ),

          // ---- Kategori çipleri ----
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              children: [
                _chip('Tümü', null),
                ...kCategories.map((c) => _chip(c, c)),
              ],
            ),
          ),

          // ---- Liste ----
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => refresh(),
              color: AppColors.onSurface,
              backgroundColor: AppColors.surface,
              child: FutureBuilder<List<TransactionModel>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(
                            color: AppColors.onSurface));
                  }
                  if (snap.hasError) {
                    return LoadError(error: snap.error!, onRetry: refresh);
                  }
                  final txs = snap.data ?? [];
                  if (txs.isEmpty) return _empty();
                  return _groupedList(txs);
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Press(
          onTap: _openAdd,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: AppColors.onPrimary, size: 22),
                const SizedBox(width: 8),
                Text('İşlem ekle',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final active = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Press(
        onTap: () => setState(() {
          _category = value;
          refresh();
        }),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: active ? AppColors.primary : AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: categoryColor(value), shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: active ? AppColors.onPrimary : AppColors.onSurface)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupedList(List<TransactionModel> txs) {
    // Tarihe göre grupla (backend zaten tarihe göre azalan sıralı döner).
    final groups = <String, List<TransactionModel>>{};
    for (final t in txs) {
      groups.putIfAbsent(_dateLabel(t.occurredOn), () => []).add(t);
    }

    final children = <Widget>[];
    var n = 0;
    groups.forEach((label, items) {
      final net = items.fold(
          0.0, (s, t) => s + (t.type == 'income' ? t.amount : -t.amount));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Eyebrow(label, size: 11),
            // money() eksi işaretini kendisi ekler; artıyı showSign ile ister.
            Text(money(net, showSign: true),
                style: AppText.mono(size: 13, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ));
      for (final t in items) {
        // İlk ekrandaki satırlar sırayla belirir; aşağıdakiler beklemeden gelir.
        children.add(Rise(delayMs: n < 10 ? n * 50 : 0, child: _txRow(t)));
        n++;
      }
    });

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: children,
    );
  }

  Widget _txRow(TransactionModel t) {
    final isIncome = t.type == 'income';
    final color = categoryColor(t.category);
    final time = DateTime.tryParse(t.occurredOn);
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
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
      confirmDismiss: (_) => _confirmDelete(t),
      onDismissed: (_) async {
        await ApiClient.instance.deleteTransaction(t.id);
        refresh();
      },
      child: Press(
        onTap: () => _edit(t),
        child: Container(
          color: AppColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(categoryIcon(t.category), size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LeaderRow(
                      left: Text(t.note.isEmpty ? t.category : t.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurface)),
                      right: Text('${isIncome ? '+' : '−'}${money(t.amount)}',
                          style: AppText.mono(
                              size: 15,
                              color: isIncome
                                  ? AppColors.positive
                                  : AppColors.onSurface)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Eyebrow(t.category, size: 11),
                        if (time != null && (time.hour != 0 || time.minute != 0)) ...[
                          const SizedBox(width: 10),
                          Text(DateFormat('HH:mm').format(time),
                              style: AppText.mono(
                                  size: 12, color: AppColors.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(TransactionModel t) async {
    return showConfirmDialog(context,
        title: 'İşlemi sil?',
        message:
            '"${t.note.isEmpty ? t.category : t.note}" kalıcı olarak silinecek.');
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(Icons.search_off, size: 40, color: AppColors.outline),
        const SizedBox(height: 16),
        Center(
            child: Text('Sonuç bulunamadı',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurface))),
        const SizedBox(height: 6),
        Center(
            child: Text('Farklı bir arama veya kategori dene.',
                style: TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant))),
      ],
    );
  }
}
