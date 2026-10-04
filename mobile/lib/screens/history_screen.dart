import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import 'add_transaction_screen.dart';
import '../format.dart';
import '../widgets/circle_button.dart';

/// İşlem geçmişi: ay seçici, ayın gelir/gider toplamı, tarihe göre gruplu liste,
/// arama ve kategori çipleri; kaydırdıkça 50'şer işlem yüklenir.
/// Sola kaydır→sil, dokun→düzenle.
class HistoryScreen extends StatefulWidget {
  final VoidCallback? onTransactionAdded;
  const HistoryScreen({super.key, this.onTransactionAdded});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  static const _pageSize = 50;

  String? _category;
  String _query = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();

  /// Seçili ay "YYYY-MM"; null ise bütün aylar.
  String? _month = monthKey(DateTime.now());
  List<MonthSummaryModel> _months = [];

  final List<TransactionModel> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  // Filtre değişince eski sayfaların geç gelen cevapları yok sayılır.
  int _generation = 0;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Ay listesini ve ilk sayfayı yeniden yükler (işlem eklenince de çağrılır).
  void refresh() {
    ApiClient.instance.getTransactionMonths().then((m) {
      if (mounted) setState(() => _months = m);
    }).catchError((_) {});
    _reload();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _fetch(0);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_items.length);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorText(e))));
      }
    } finally {
      if (mounted && gen == _generation) setState(() => _loadingMore = false);
    }
  }

  Future<List<TransactionModel>> _fetch(int offset) =>
      ApiClient.instance.getTransactions(
          category: _category,
          q: _query,
          month: _month,
          limit: _pageSize,
          offset: offset);

  void _onScroll() {
    if (_scroll.position.extentAfter < 400) _loadMore();
  }

  void _setMonth(String? month) {
    if (month == _month) return;
    _month = month;
    _reload();
  }

  /// Ay okları takvim ayına göre ilerler; bu aydan ileriye ve en eski işlemin
  /// ayından geriye gidilmez.
  void _shiftMonth(int delta) {
    final cur = DateTime.parse('${_month ?? monthKey(DateTime.now())}-01');
    _setMonth(monthKey(DateTime(cur.year, cur.month + delta)));
  }

  bool get _canGoNext =>
      _month != null && _month!.compareTo(monthKey(DateTime.now())) < 0;

  bool get _canGoPrev =>
      _month != null &&
      _months.isNotEmpty &&
      _month!.compareTo(_months.last.month) > 0;

  MonthSummaryModel? get _selectedSummary {
    for (final m in _months) {
      if (m.month == _month) return m;
    }
    return null;
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      _reload();
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

  /// Seçili ayın (ya da bütün ayların) işlemlerini CSV olarak paylaşır. Mobilde
  /// paylaşım menüsü açılır, webde dosya indirilir.
  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file =
          await ApiClient.instance.exportTransactionsCsv(month: _month);
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(file.bytes, mimeType: 'text/csv', name: file.fileName)
        ],
        fileNameOverrides: [file.fileName],
        subject: 'Expenza işlemleri (${monthLabel(_month)})',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorText(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    final filtered = _category != null || _query.isNotEmpty;
    final summary = _selectedSummary;
    final count = !filtered && summary != null
        ? '${summary.count}'
        : '${_items.length}${_hasMore ? '+' : ''}';
    return Scaffold(
      body: Column(
        children: [
          // ---- Başlık ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Geçmiş'),
                    const SizedBox(height: 10),
                    Text('İşlemler', style: AppText.display(size: 38)),
                    const SizedBox(height: 8),
                    Text(_loading ? ' ' : '$count işlem',
                        style: TextStyle(
                            fontSize: 15, color: AppColors.onSurfaceVariant)),
                  ],
                ),
                Row(
                  children: [
                    CircleIconButton(icon: Icons.file_download_outlined, tooltip: 'CSV olarak dışa aktar', onTap: _exporting ? null : _export),
                    const SizedBox(width: 8),
                    CircleIconButton(icon: isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined, tooltip: 'Temayı değiştir', onTap: toggleThemeMode),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ---- Ay seçici ve ayın toplamları ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _monthBar(),
          ),
          const SizedBox(height: 14),

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
                        _reload();
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
              child: Builder(builder: (context) {
                if (_loading) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: AppColors.onSurface));
                }
                if (_error != null) {
                  return LoadError(error: _error!, onRetry: refresh);
                }
                if (_items.isEmpty) return _empty();
                return _groupedList(_items);
              }),
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

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      child: Press(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(icon,
              size: 20,
              color: enabled
                  ? AppColors.onSurface
                  : AppColors.surfaceContainerHigh),
        ),
      ),
    );
  }

  Widget _monthBar() {
    final summary = _selectedSummary;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      child: Row(
        children: [
          _arrow(Icons.chevron_left, _canGoPrev, () => _shiftMonth(-1),
              'Önceki ay'),
          Expanded(
            child: Press(
              onTap: _pickMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(monthLabel(_month),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurface)),
                    ),
                    Icon(Icons.expand_more,
                        size: 18, color: AppColors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          _arrow(Icons.chevron_right, _canGoNext, () => _shiftMonth(1),
              'Sonraki ay'),
          if (_month != null) ...[
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+${money(summary?.income ?? 0)}',
                    style: AppText.mono(size: 13, color: AppColors.positive)),
                const SizedBox(height: 2),
                Text('−${money(summary?.expense ?? 0)}',
                    style: AppText.mono(size: 13, color: AppColors.onSurface)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickMonth() async {
    final current = monthKey(DateTime.now());
    // Bu ayda henüz işlem yoksa da seçilebilsin.
    final months = [
      if (_months.every((m) => m.month != current))
        MonthSummaryModel(month: current, income: 0, expense: 0, count: 0),
      ..._months,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Eyebrow('Ay seç', size: 11),
              ),
              _monthTile(ctx, '', 'Tüm aylar', null),
              for (final m in months)
                _monthTile(ctx, m.month, monthLabel(m.month), m),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _setMonth(picked.isEmpty ? null : picked);
  }

  Widget _monthTile(
      BuildContext ctx, String value, String label, MonthSummaryModel? m) {
    return ListTile(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      selected: (_month ?? '') == value,
      selectedTileColor: AppColors.surfaceContainer,
      title: Text(label,
          style: TextStyle(fontSize: 16, color: AppColors.onSurface)),
      subtitle: m == null
          ? null
          : Text('${m.count} işlem',
              style:
                  TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
      trailing: m == null
          ? null
          : Text('−${money(m.expense)}',
              style: AppText.mono(size: 13, color: AppColors.onSurfaceVariant)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Widget _chip(String label, String? value) {
    final active = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Press(
        onTap: () {
          _category = value;
          _reload();
        },
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
      groups.putIfAbsent(dayLabel(t.occurredOn), () => []).add(t);
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

    if (_hasMore || _loadingMore) {
      children.add(Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.onSurfaceVariant),
          ),
        ),
      ));
    }

    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      children: children,
    );
  }

  Widget _txRow(TransactionModel t) {
    final isIncome = t.type == 'income';
    final color = categoryColor(t.category);
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
        setState(() => _items.remove(t));
        await ApiClient.instance.deleteTransaction(t.id);
        refresh();
        widget.onTransactionAdded?.call();
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
                        if (t.isRecurring) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.repeat,
                              size: 13, color: AppColors.onSurfaceVariant),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
              _month != null && !(_category != null || _query.isNotEmpty)
                  ? 'Bu ayda işlem yok. Oklarla başka bir aya geçebilirsin.'
                  : 'Farklı bir arama, kategori ya da ay dene.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant)),
        ),
      ],
    );
  }
}
