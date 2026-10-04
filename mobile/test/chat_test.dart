// Sohbet geçmişi: önceki turlar asistana gider, ekran kapanınca konuşma kaybolmaz.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:expenza_mobile/api_client.dart';
import 'package:expenza_mobile/screens/chat_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// ChatScreen'i bir düğmeyle açan sayfa (geri dönüp yeniden açmak için).
Widget _host() => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ChatScreen())),
            child: const Text('Aç'),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.chatLog.clear();
  });

  testWidgets('önceki turlar gönderilir; konuşma ekran kapanınca kalır',
      (tester) async {
    final chatBodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(_host());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      Future<void> ask(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
      }

      await ask('Bu ay ne kadar harcadım?');
      await ask('Peki geçen ay?');

      expect(chatBodies[0]['history'], isEmpty);
      expect(chatBodies[1]['history'], [
        {'role': 'user', 'text': 'Bu ay ne kadar harcadım?'},
        {'role': 'model', 'text': 'Cevap 1'},
      ]);
      expect(chatBodies[1]['currency'], 'TRY');

      // Geri dönüp yeniden açınca konuşma duruyor.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      expect(find.text('Peki geçen ay?'), findsOneWidget);
      expect(find.text('Cevap 2'), findsOneWidget);

      // Yeni sohbet geçmişi siler.
      await tester.tap(find.byTooltip('Yeni sohbet'));
      await tester.pumpAndSettle();
      expect(find.text('Peki geçen ay?'), findsNothing);
      expect(ApiClient.instance.chatLog, isEmpty);
    }, () => MockClient((req) async {
          if (req.url.path == '/auth/me') {
            return _json({
              'id': 1,
              'email': 'a@b.co',
              'display_name': 'Sena',
              'created_at': '2026-10-01T10:00:00',
              'alerts_enabled': true,
              'ai_consent_at': '2026-10-01T10:00:00',
            });
          }
          if (req.url.path == '/chat') {
            chatBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            return _json({'reply': 'Cevap ${chatBodies.length}'});
          }
          return _json({});
        }));
  });

  testWidgets('hata mesajları asistana geri gönderilmez', (tester) async {
    var calls = 0;
    Map<String, dynamic>? last;
    await http.runWithClient(() async {
      await tester.pumpWidget(_host());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      for (final text in ['ilk', 'ikinci']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
      }
      expect(find.text('Asistan şu anda yanıt veremiyor.'), findsOneWidget);
      expect(last!['history'], isEmpty);
      await tester.pump(const Duration(milliseconds: 50));
    }, () => MockClient((req) async {
          if (req.url.path == '/auth/me') {
            return _json({'ai_consent_at': '2026-10-01T10:00:00'});
          }
          last = jsonDecode(req.body) as Map<String, dynamic>;
          calls++;
          return calls == 1
              ? _json({'detail': 'Asistan şu anda yanıt veremiyor.'}, 502)
              : _json({'reply': 'tamam'});
        }));
  });
}
