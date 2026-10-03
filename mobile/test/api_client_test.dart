// ApiClient oturum mantığı: kayıtlı oturumun geri yüklenmesi, 401'de token yenileme,
// paralel isteklerde tek yenileme, oturumun düşmesi ve çıkış. Backend sahte bir HTTP
// istemcisiyle taklit edilir; güvenli depo paketin test deposuyla değiştirilir.
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
}
