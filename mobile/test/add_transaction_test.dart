// İşlem ekleme ekranındaki tarih seçimi.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:expenza_mobile/models.dart';
import 'package:expenza_mobile/screens/add_transaction_screen.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

String _label(DateTime d) => DateFormat('d MMMM', 'tr_TR').format(d);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  // Ekranın tamamı (tarih satırı dahil) kaydırmadan görünsün.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(440, 2400);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('varsayılan bugün; "Dün" seçilince tarih değişir', (tester) async {
    await tester.pumpWidget(_app(const AddTransactionScreen()));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    expect(find.textContaining(_label(today)), findsOneWidget);

    await tester.tap(find.text('Dün'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_label(yesterday)), findsOneWidget);
  });

  testWidgets('satıra dokununca Türkçe takvim açılır', (tester) async {
    await tester.pumpWidget(_app(const AddTransactionScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tarih'));
    await tester.pumpAndSettle();
    expect(find.text('İşlem tarihi'), findsOneWidget);
    expect(find.text('Vazgeç'), findsOneWidget);

    final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final now = DateTime.now();
    // İleri tarih seçilemez.
    expect(picker.lastDate, DateTime(now.year, now.month, now.day));
  });

  testWidgets('düzenlemede işlemin kendi tarihi gösterilir', (tester) async {
    final tx = TransactionModel(
      id: 1, amount: 50, type: 'expense', category: 'Yemek',
      autoCategorized: false, isRecurring: false, note: 'kahve',
      occurredOn: '2026-03-15',
    );
    await tester.pumpWidget(_app(AddTransactionScreen(existing: tx)));
    await tester.pumpAndSettle();
    expect(find.textContaining('15 Mart'), findsOneWidget);
  });
}
