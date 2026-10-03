// Uyarılar ekranı ve işlem kaydedilince gösterilen bütçe uyarısı (sahte backend ile).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:expenza_mobile/screens/add_transaction_screen.dart';
import 'package:expenza_mobile/screens/alerts_screen.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json'});

Map<String, dynamic> _user({bool alerts = true}) => {
      'id': 1,
      'email': 'a@b.co',
      'display_name': 'A',
      'created_at': '2026-10-01T10:00:00',
      'alerts_enabled': alerts,
      'ai_consent_at': null,
    };

const _alerts = [
  {
    'id': 'budget:Yemek:2026-10:100',
    'kind': 'budget',
    'level': 'danger',
    'title': 'Yemek bütçesi aşıldı',
    'message': 'Bu ay limitin %112 seviyesine ulaştın.',
    'category': 'Yemek',
    'amount': 1120.0,
  },
  {
    'id': 'recurring:3:2026-10-06',
    'kind': 'recurring',
    'level': 'info',
    'title': 'Kira ödemesi yaklaşıyor',
    'message': '2 gün sonra otomatik olarak eklenecek.',
    'amount': 7500.0,
    'due_on': '2026-10-06',
  },
];

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

  testWidgets('uyarılar listelenir, kaydırılan uyarı sunucuda kapatılır',
      (tester) async {
    final dismissed = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const AlertsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Yemek bütçesi aşıldı'), findsOneWidget);
      expect(find.text('Kira ödemesi yaklaşıyor'), findsOneWidget);
      expect(find.text('2 uyarı'.toUpperCase()), findsOneWidget);
      expect(find.textContaining('6 Ekim'), findsOneWidget);

      await tester.drag(find.text('Yemek bütçesi aşıldı'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Yemek bütçesi aşıldı'), findsNothing);
    }, () => MockClient((req) async {
          switch (req.url.path) {
            case '/alerts':
              return _json(_alerts);
            case '/auth/me':
              return _json(_user());
            case '/alerts/dismiss':
              dismissed.add(jsonDecode(req.body)['id']);
              return http.Response('', 204);
          }
          return _json({}, 404);
        }));
    expect(dismissed, ['budget:Yemek:2026-10:100']);
  });

  testWidgets('uyarı yoksa ve uyarılar kapalıysa bilgi verir', (tester) async {
    for (final enabled in [true, false]) {
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(AlertsScreen(key: ValueKey(enabled))));
        await tester.pumpAndSettle();
        expect(find.text(enabled ? 'Şu an uyarı yok' : 'Uyarılar kapalı'),
            findsOneWidget);
      }, () => MockClient((req) async => req.url.path == '/auth/me'
          ? _json(_user(alerts: enabled))
          : _json([])));
    }
  });

  testWidgets('bütçeyi aşan gider kaydedilince uyarı gösterilir', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AddTransactionScreen())),
              child: const Text('aç'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '200');
      await tester.tap(find.text('Yemek'));
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      // Sayfa kapandı, uyarı ana ekranda görünüyor.
      expect(find.byType(AddTransactionScreen), findsNothing);
      expect(find.textContaining('Yemek bütçesi aşıldı: %112.'), findsOneWidget);
    }, () => MockClient((req) async {
          if (req.url.path == '/transactions' && req.method == 'POST') {
            return _json({
              'id': 9,
              'amount': 200,
              'type': 'expense',
              'category': 'Yemek',
              'auto_categorized': false,
              'is_recurring': false,
              'note': '',
              'occurred_on': '2026-10-04',
              'budget_alerts': [
                {
                  'category': 'Yemek',
                  'limit': 1000,
                  'spent': 1120,
                  'ratio': 1.12,
                  'level': 'exceeded',
                  'crossed': true,
                  'message': 'Yemek bütçesi aşıldı: %112.',
                }
              ],
            }, 201);
          }
          return _json({'category': 'Yemek', 'confidence': 0.9, 'model': 'svm'});
        }));
  });
}
