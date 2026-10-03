// Hesap ayarları: ad, şifre değiştirme ve hesap silme (sahte backend ile).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:expenza_mobile/api_client.dart';
import 'package:expenza_mobile/screens/account_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _me = {
  'id': 1,
  'email': 'sena@example.com',
  'display_name': 'Sena',
  'created_at': '2026-10-01T10:00:00',
  'alerts_enabled': true,
  'ai_consent_at': null,
};

void main() {
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

  testWidgets('ad kaydedilir, şifre hataları gösterilir, hesap silinir',
      (tester) async {
    final writes = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
      await tester.pumpAndSettle();
      expect(find.text('sena@example.com'), findsOneWidget);

      // Ad
      await tester.enterText(find.widgetWithText(TextField, 'Sena'), 'Sena K.');
      await tester.tap(find.text('Adı kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Adın güncellendi.'), findsOneWidget);

      // Yeni şifreler farklı: istek gitmeden uyarı
      await tester.enterText(find.widgetWithText(TextField, 'Mevcut şifre'), 'eski1234');
      await tester.enterText(find.widgetWithText(TextField, 'Yeni şifre'), 'yeni12345');
      await tester.enterText(
          find.widgetWithText(TextField, 'Yeni şifre (tekrar)'), 'baska12345');
      await tester.tap(find.text('Şifreyi değiştir'));
      await tester.pumpAndSettle();
      expect(find.text('Yeni şifreler aynı değil.'), findsOneWidget);
      expect(writes.where((w) => w.contains('change-password')), isEmpty);

      // Mevcut şifre yanlış: sunucunun mesajı gösterilir, oturum açık kalır
      await tester.enterText(
          find.widgetWithText(TextField, 'Yeni şifre (tekrar)'), 'yeni12345');
      await tester.tap(find.text('Şifreyi değiştir'));
      await tester.pumpAndSettle();
      expect(find.text('Mevcut parola hatalı'), findsOneWidget);

      // Hesap silme: şifreyle onay
      await tester.tap(find.text('Hesabı sil'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Şifre'), 'eski1234');
      await tester.tap(find.text('Hesabımı sil'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async {
          if (req.method != 'GET') writes.add('${req.method} ${req.url.path} ${req.body}');
          switch ('${req.method} ${req.url.path}') {
            case 'GET /auth/me':
              return _json(_me);
            case 'PUT /auth/me':
              return _json({..._me, 'display_name': 'Sena K.'});
            case 'POST /auth/change-password':
              return _json({'detail': 'Mevcut parola hatalı'}, 400);
            case 'DELETE /auth/me':
              return http.Response('', 204);
          }
          return _json({}, 404);
        }));

    expect(writes.first, contains('"display_name":"Sena K."'));
    expect(writes.where((w) => w.startsWith('POST /auth/change-password')),
        hasLength(1));
    expect(writes.last, 'DELETE /auth/me {"password":"eski1234"}');
    expect(ApiClient.instance.session.value, isFalse);
    expect(ApiClient.instance.sessionEndedReason, contains('silindi'));
  });
}
