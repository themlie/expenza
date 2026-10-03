// Hedefler: son tarih, durum, düzenleme ve para çekme (sahte backend ile).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:expenza_mobile/screens/goals_screen.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

final _goal = {
  'id': 1,
  'title': 'Tatil',
  'target_amount': 1000.0,
  'current_amount': 200.0,
  'deadline': '${DateTime.now().year + 1}-06-30',
  'created_at': '2026-01-01T00:00:00',
  'progress': 0.2,
  'remaining': 800.0,
  'days_left': 120,
  'months_left': 4,
  'monthly_needed': 200.0,
  'status': 'behind',
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
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

  testWidgets('kartta son tarih, durum ve aylık tutar; düzenleme ve para çekme',
      (tester) async {
    final writes = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const GoalsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('120 gün kaldı'), findsOneWidget);
      expect(find.text('Geride'), findsOneWidget);
      expect(find.text('AYDA GEREKEN'), findsOneWidget);

      // Düzenle: alanlar dolu gelir; son tarih kaldırılıp ad değiştirilir.
      await tester.tap(find.byTooltip('Hedef seçenekleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.text('Hedefi düzenle'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Tatil'), 'Yaz tatili');
      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();
      expect(find.text('Tarih seç'), findsOneWidget);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Hedefi düzenle'), findsNothing);

      // Para çek: birikimden fazlası istenirse sunucunun mesajı gösterilir.
      await tester.tap(find.byTooltip('Hedef seçenekleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Para çek'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '5000');
      await tester.tap(find.text('Çek'));
      await tester.pumpAndSettle();
      expect(find.text('Hedefte bu kadar birikim yok'), findsOneWidget);
    }, () => MockClient((req) async {
          if (req.method != 'GET') writes.add('${req.method} ${req.url.path} ${req.body}');
          if (req.url.path == '/goals') return _json([_goal]);
          if (req.url.path == '/goals/1/withdraw') {
            return _json({'detail': 'Hedefte bu kadar birikim yok'}, 400);
          }
          return _json(_goal);
        }));

    final put = writes.firstWhere((w) => w.startsWith('PUT /goals/1'));
    final body = jsonDecode(put.substring(put.indexOf('{')));
    expect(body['title'], 'Yaz tatili');
    expect(body['target_amount'], 1000);
    expect(body.containsKey('deadline'), isTrue);
    expect(body['deadline'], isNull); // son tarih kaldırıldı
    expect(writes.any((w) => w.startsWith('POST /goals/1/withdraw')), isTrue);
  });
}
