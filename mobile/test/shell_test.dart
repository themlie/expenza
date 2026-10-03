// Sekmelerin ilk açılışta yüklenmesi, profil bilgileri ve "Beni hatırla".
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:expenza_mobile/api_client.dart';
import 'package:expenza_mobile/screens/home_shell.dart';
import 'package:expenza_mobile/screens/login_screen.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Her uç için boş ama geçerli cevap.
http.Response _fake(http.Request req) {
  switch (req.url.path) {
    case '/auth/me':
      return _json({
        'id': 1,
        'email': 'a@b.co',
        'display_name': 'Sena',
        'created_at': '2026-10-01T10:00:00',
        'alerts_enabled': true,
        'ai_consent_at': null,
      });
    case '/auth/login':
      return _json({
        'access_token': 'a1',
        'refresh_token': 'r1',
        'token_type': 'bearer',
        'expires_in': 1800,
      });
    case '/transactions/summary':
      return _json({
        'balance': 0,
        'total_income': 0,
        'total_expense': 0,
        'month': '2026-10',
        'month_income': 0,
        'month_expense': 0,
        'month_by_category': [],
      });
    case '/analytics/forecast':
      return _json({
        'current_month_spent': 0,
        'projected_month_end': 0,
        'next_month_prediction': 0,
        'method': 'run_rate',
        'velocity': 'Normal',
        'history': [],
        'by_category': [],
      });
  }
  return _json([]);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(440, 2400);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('girişte yalnızca ana sayfa yüklenir; sekmeler ilk açılışta yüklenir',
      (tester) async {
    final paths = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(HomeShell(onLogout: () {})));
      await tester.pumpAndSettle();

      expect(paths.toSet(), {
        '/transactions/summary',
        '/transactions',
        '/goals',
        '/auth/me',
        '/alerts',
      });
      expect(paths, isNot(contains('/transactions/months')));
      expect(paths, isNot(contains('/analytics/forecast')));
      expect(paths, isNot(contains('/budgets')));

      await tester.tap(find.text('İşlemler'));
      await tester.pumpAndSettle();
      expect(paths, contains('/transactions/months'));

      // Analitik: kategoriler bu ayın özetinden gelir, işlem listesinden değil.
      paths.clear();
      await tester.tap(find.text('Analitik'));
      await tester.pumpAndSettle();
      expect(paths, containsAll(['/analytics/forecast', '/transactions/summary']));
      expect(paths, isNot(contains('/transactions')));

      // Profil: "Premium üye" yerine üyelik tarihi ve gerçek sürüm.
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Premium üye'), findsNothing);
      expect(find.text('Üye: Ekim 2026'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
    }, () => MockClient((req) async {
          paths.add(req.url.path);
          return _fake(req);
        }));
  });

  testWidgets('"Beni hatırla" kapalıysa oturum cihaza yazılmaz', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(LoginScreen(onLoggedIn: () {})));
      await tester.pumpAndSettle();

      expect(find.text('Beni hatırla'), findsOneWidget);
      await tester.tap(find.text('Beni hatırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giriş yap').last);
      await tester.pumpAndSettle();

      expect(ApiClient.instance.session.value, isTrue);
      expect(await const FlutterSecureStorage().read(key: 'expenza.refresh_token'),
          isNull);
      await ApiClient.instance.logout();
    }, () => MockClient((req) async => _fake(req)));
  });
}
