// ApiClient oturum mantığı: kayıtlı oturumun geri yüklenmesi, 401'de token yenileme,
// paralel isteklerde tek yenileme, oturumun düşmesi ve çıkış. Backend sahte bir HTTP
// istemcisiyle taklit edilir; güvenli depo paketin test deposuyla değiştirilir.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:expenza_mobile/api_client.dart';

const _key = 'expenza.refresh_token';

/// Gerçek backend gibi yenileme token'ını her kullanımda değiştirir ve kullanılmış
/// token'ı reddeder.
class FakeBackend {
  int _n = 0;
  String? validAccess;
  final validRefresh = <String>{};
  int refreshCalls = 0;
  int logoutCalls = 0;
  final calls = <String, int>{}; // "GET /auth/me" -> sayı
  Completer<void>? holdReads; // doluysa GET istekleri tamamlanınca cevap döner

  String issueRefresh() {
    final token = 'r${++_n}';
    validRefresh.add(token);
    return token;
  }

  Map<String, dynamic> _pair() {
    validAccess = 'a${++_n}';
    return {
      'access_token': validAccess,
      'refresh_token': issueRefresh(),
      'token_type': 'bearer',
      'expires_in': 1800,
    };
  }

  http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request req) async {
    final call = '${req.method} ${req.url.path}';
    calls[call] = (calls[call] ?? 0) + 1;
    if (req.method == 'GET' && holdReads != null) await holdReads!.future;
    switch (req.url.path) {
      case '/auth/login':
        return _json(_pair());
      case '/auth/refresh':
        refreshCalls++;
        final token = jsonDecode(req.body)['refresh_token'];
        if (!validRefresh.remove(token)) {
          return _json({'detail': 'Oturum geçersiz'}, 401);
        }
        return _json(_pair());
      case '/auth/logout':
        logoutCalls++;
        validRefresh.clear();
        return http.Response('', 204);
    }
    if (req.headers['Authorization'] != 'Bearer $validAccess') {
      return _json({'detail': 'Geçersiz kimlik bilgisi'}, 401);
    }
    if (req.url.path == '/auth/me') {
      return _json({
        'id': 1,
        'email': 'a@b.co',
        'display_name': 'A',
        'created_at': '2026-10-01T10:00:00',
        'alerts_enabled': true,
        'ai_consent_at': null,
      });
    }
    return _json([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient.instance;
  const storage = FlutterSecureStorage();
  late FakeBackend backend;

  /// Testi sahte backend'le çalıştırır; önce önceki testten kalan oturumu temizler.
  Future<void> run(Future<void> Function() body,
      {Map<String, String> stored = const {}}) {
    return http.runWithClient(() async {
      await api.logout();
      FlutterSecureStorage.setMockInitialValues(Map.of(stored));
      backend.logoutCalls = 0;
      await body();
    }, () => MockClient(backend.handle));
  }

  setUp(() => backend = FakeBackend());

  test('kayıtlı token ile oturum geri yüklenir ve yeni token saklanır', () async {
    final saved = backend.issueRefresh();
    await run(() async {
      api.restoring.value = true;
      await api.restoreSession();
      expect(api.restoring.value, isFalse);
      expect(api.session.value, isTrue);
      final now = await storage.read(key: _key);
      expect(now, isNot(saved)); // token döndürüldü
      expect(backend.validRefresh, contains(now));
    }, stored: {_key: saved});
  });

  test('kayıtlı token yoksa giriş ekranı açılır', () async {
    await run(() async {
      await api.restoreSession();
      expect(api.restoring.value, isFalse);
      expect(api.session.value, isFalse);
      expect(backend.refreshCalls, 0);
    });
  });

  test('401 alan paralel istekler tek bir yenilemeyle devam eder', () async {
    await run(() async {
      await api.login('a@b.co', 'parola123');
      backend.validAccess = 'süresi doldu';
      await Future.wait([api.getGoals(), api.getBudgets(), api.getAlerts()]);
      expect(backend.refreshCalls, 1);
      expect(api.session.value, isTrue);
    });
  });

  test('yenileme reddedilirse oturum düşer ve kayıtlı token silinir', () async {
    await run(() async {
      await api.login('a@b.co', 'parola123');
      backend.validAccess = 'süresi doldu';
      backend.validRefresh.clear(); // ör. başka cihazdan parola değişti
      await expectLater(api.getGoals(), throwsException);
      expect(api.session.value, isFalse);
      expect(api.sessionEndedReason, contains('Oturumun sona erdi'));
      expect(await storage.read(key: _key), isNull);
    });
  });

  test('"Beni hatırla" kapalıysa token cihaza yazılmaz', () async {
    await run(() async {
      await api.login('a@b.co', 'parola123', remember: false);
      expect(api.session.value, isTrue);
      expect(await storage.read(key: _key), isNull);
    });
  });

  test('çıkış sunucudaki oturumu kapatır ve token siler', () async {
    await run(() async {
      await api.login('a@b.co', 'parola123');
      expect(await storage.read(key: _key), isNotNull);
      await api.logout();
      expect(api.session.value, isFalse);
      expect(backend.logoutCalls, 1);
      expect(await storage.read(key: _key), isNull);
    });
  });

  test('aynı anda yapılan aynı GET istekleri tek istekte birleşir', () async {
    await run(() async {
      await api.login('a@b.co', 'parola123');
      // Açılıştaki gibi: ana sayfa ve profil /auth/me'yi aynı anda ister.
      final results = await Future.wait(
          [api.getMe(), api.getProfile(), api.hasAiConsent()]);
      expect(backend.calls['GET /auth/me'], 1);
      expect((results[1] as dynamic).email, 'a@b.co');
      expect(results[2], isFalse);

      // Biten istek saklanmaz; sonraki okuma sunucuya gider.
      await api.getMe();
      expect(backend.calls['GET /auth/me'], 2);
    });
  });

  test('veri değiştiren istekten sonraki okuma eski isteğe katılmaz', () async {
    await run(() async {
      await api.login('a@b.co', 'parola123');
      backend.holdReads = Completer();
      final before = api.getAlerts(); // cevap bekletiliyor
      await api.dismissAlert('budget:Yemek:2026-10:80');
      final after = api.getAlerts();
      backend.holdReads!.complete();
      await Future.wait([before, after]);
      expect(backend.calls['GET /alerts'], 2);
    });
  });
}
