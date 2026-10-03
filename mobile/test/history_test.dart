// Geçmiş ekranı: ay seçici ve sayfalama (sahte backend ile).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:expenza_mobile/screens/history_screen.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('bu ay açılır, kaydırınca sonraki sayfa, okla önceki ay gelir',
      (tester) async {
    final now = DateTime.now();
    final thisMonth = _key(now);
    final lastMonth = _key(DateTime(now.year, now.month - 1));
    final requests = <Map<String, String>>[];

    // Bu ayda 70 işlem: ilk sayfa 50, ikinci sayfa 20.
    http.Response handle(http.Request req) {
      if (req.url.path == '/transactions/months') {
        return http.Response.bytes(
            utf8.encode(jsonEncode([
              {'month': thisMonth, 'income': 1000, 'expense': 700, 'count': 70},
              {'month': lastMonth, 'income': 0, 'expense': 30, 'count': 1},
            ])),
            200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      final q = req.url.queryParameters;
      requests.add(q);
      final offset = int.parse(q['offset'] ?? '0');
      final total = q['month'] == thisMonth ? 70 : 1;
      final n = (total - offset).clamp(0, int.parse(q['limit']!));
      final day = q['month'] == thisMonth ? '$thisMonth-01' : '$lastMonth-15';
      final list = [
        for (var i = 0; i < n; i++)
          {
            'id': offset + i + 1,
            'amount': 10,
            'type': 'expense',
            'category': 'Yemek',
            'auto_categorized': false,
            'is_recurring': false,
            'note': 'işlem ${offset + i + 1}',
            'occurred_on': day,
          }
      ];
      return http.Response.bytes(utf8.encode(jsonEncode(list)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }

    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const HistoryScreen()));
      await tester.pumpAndSettle();

      expect(requests.first['month'], thisMonth);
      expect(requests.first['limit'], '50');
      expect(find.text('70 işlem'), findsOneWidget);

      // Listenin sonuna kaydır: ikinci sayfa offset=50 ile istenir.
      await tester.drag(find.text('işlem 1'), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(requests.any((q) => q['offset'] == '50'), isTrue);
      await tester.drag(find.byType(ListView).last, const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(find.text('işlem 70'), findsOneWidget);
      expect(requests.where((q) => q['offset'] == '100'), isEmpty); // 20 < 50: son sayfa

      // Sonraki ay oku kapalı (bu aydan ileri gidilmez); önceki ay açık.
      await tester.tap(find.byTooltip('Sonraki ay'));
      await tester.pumpAndSettle();
      expect(requests.last['month'], thisMonth);

      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();
      expect(requests.last['month'], lastMonth);
      expect(requests.last.containsKey('offset'), isFalse);
      expect(find.text('işlem 1'), findsOneWidget);
      expect(find.text('işlem 70'), findsNothing);
    }, () => MockClient((req) async => handle(req)));
  });
}
