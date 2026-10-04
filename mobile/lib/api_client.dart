import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Expenza backend REST istemcisi.
///
/// Taban URL derleme sırasında verilebilir (yayın için, HTTPS):
///   flutter build web --dart-define=API_BASE_URL=https://api.ornek.com
/// Verilmezse geliştirme adresleri kullanılır:
/// - Android emülatör: 10.0.2.2 (host makineye köprü)
/// - Web/masaüstü/iOS sim: localhost
///
/// Oturum: girişte kısa ömürlü bir erişim token'ı (30 dk) ve uzun ömürlü bir yenileme
/// token'ı (30 gün) gelir. Erişim token'ı yalnızca bellekte tutulur. "Beni hatırla"
/// seçiliyse yenileme token'ı cihazın güvenli deposuna yazılır (Android Keystore, iOS
/// Keychain, web'de WebCrypto ile şifrelenmiş localStorage) ve uygulama açılınca
/// [restoreSession] oturumu bununla geri yükler. Bir istek 401 alırsa token bir kez
/// yenilenip istek tekrarlanır.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _token;
  String? _refreshToken;
  bool _remember = true;
  // Aynı anda 401 alan istekler tek bir yenileme isteğini bekler. Yenileme token'ı her
  // kullanımda değiştiği için iki paralel yenileme oturumu düşürürdü.
  Future<bool>? _refreshing;

  static const _storage = FlutterSecureStorage();
  static const _refreshKey = 'expenza.refresh_token';

  bool get isLoggedIn => _token != null;

  /// Oturum durumu: girişte true; çıkışta ya da oturum yenilenemeyince false.
  final ValueNotifier<bool> session = ValueNotifier(false);

  /// Açılışta kayıtlı oturum kontrol edilirken true (açılış ekranı gösterilir).
  final ValueNotifier<bool> restoring = ValueNotifier(true);

  /// Oturum sunucu tarafından düşürüldüyse giriş ekranında gösterilecek mesaj.
  String? sessionEndedReason;

  // Backend portu. (8000 bu makinede başka bir süreç tarafından kullanıldığı
  // için 8010 seçildi — uvicorn'u bu portla başlat.)
  static const int port = 8010;

  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    // Web'de dart:io yok; foundation'ın platform bilgisini kullanıyoruz.
    if (kIsWeb) {
      // Sayfanın sunulduğu host üzerinden API'ye bağlan. Böylece hem PC'de
      // (localhost) hem de telefonda (PC'nin LAN IP'si) ek ayar gerekmeden çalışır.
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      return 'http://$host:$port';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$port'; // Android emülatör host köprüsü
    }
    return 'http://localhost:$port';
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  Map<String, String> get _headers => {
        ..._jsonHeaders,
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _u(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  // Aynı anda yapılan aynı GET istekleri tek istekte birleştirilir: girişte bütün
  // sekmeler aynı karede yüklenir ve örneğin /auth/me üç kez istenirdi. Yalnızca
  // devam eden istekler paylaşılır (önbellek yok). Veri değiştiren bir istek ya da
  // oturum değişikliği birleştirmeyi sıfırlar; sonraki okumalar eski cevabı almaz.
  final _inflight = <String, Future<http.Response>>{};

  Future<http.Response> _send(String method, String path,
      {Object? body, Map<String, String>? query}) {
    if (method != 'GET') {
      _inflight.clear();
      return _sendNow(method, path, body: body, query: query);
    }
    final key = _u(path, query).toString();
    final pending = _inflight[key];
    if (pending != null) return pending;
    final request = _sendNow(method, path, query: query);
    _inflight[key] = request;
    request.whenComplete(() {
      if (identical(_inflight[key], request)) _inflight.remove(key);
    }).ignore();
    return request;
  }

  /// İsteği gönderir; 401 gelirse token'ı bir kez yenileyip tekrar dener.
  Future<http.Response> _sendNow(String method, String path,
      {Object? body, Map<String, String>? query}) async {
    final encoded = body == null ? null : jsonEncode(body);
    Future<http.Response> go() {
      final uri = _u(path, query);
      switch (method) {
        case 'GET':
          return http.get(uri, headers: _headers);
        case 'POST':
          return http.post(uri, headers: _headers, body: encoded);
        case 'PUT':
          return http.put(uri, headers: _headers, body: encoded);
        default:
          return http.delete(uri, headers: _headers, body: encoded);
      }
    }

    final usedToken = _token;
    var r = await go();
    if (r.statusCode == 401 && _refreshToken != null) {
      // Başka bir istek token'ı bu arada yenilediyse doğrudan tekrar dene.
      if (_token != usedToken || await _refresh()) r = await go();
    }
    if (r.statusCode >= 400) throw _err(r);
    return r;
  }

  Future<dynamic> _json(String method, String path,
      {Object? body, Map<String, String>? query}) async {
    final r = await _send(method, path, body: body, query: query);
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  // ---- Oturum ----

  Future<bool> _refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;
    final r = await http.post(_u('/auth/refresh'),
        headers: _jsonHeaders,
        body: jsonEncode({'refresh_token': refreshToken}));
    if (r.statusCode != 200) {
      // 401: token geçersiz ya da iptal edilmiş; bir daha denenmez.
      if (r.statusCode == 401) await _forgetTokens();
      return false;
    }
    await _storeTokens(jsonDecode(r.body));
    return true;
  }

  Future<void> _storeTokens(Map<String, dynamic> j) async {
    _token = j['access_token'] as String;
    _refreshToken = j['refresh_token'] as String?;
    if (_remember && _refreshToken != null) {
      try {
        await _storage.write(key: _refreshKey, value: _refreshToken);
      } catch (_) {
        // Güvenli depo yoksa (ör. web'de HTTPS olmayan bir adres) oturum yalnızca
        // uygulama açık kaldığı sürece devam eder.
      }
    }
  }

  Future<void> _forgetTokens() async {
    _token = null;
    _refreshToken = null;
    try {
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }

  void _endSession(String? reason) {
    sessionEndedReason = reason;
    _token = null;
    _inflight.clear();
    chatLog.clear();
    session.value = false;
  }

  /// Uygulama açılışında kayıtlı oturumu geri yükler. Kayıtlı token yoksa, geçersizse
  /// ya da sunucuya ulaşılamazsa giriş ekranı gösterilir.
  Future<void> restoreSession() async {
    try {
      final saved = await _storage.read(key: _refreshKey);
      if (saved != null) {
        _refreshToken = saved;
        _remember = true;
        if (await _refresh().timeout(const Duration(seconds: 8))) {
          session.value = true;
        }
      }
    } catch (_) {
      // Depo okunamadı ya da sunucu cevap vermedi. Token silinmez; sunucuya
      // ulaşılabildiğinde bir sonraki açılışta oturum geri gelir.
    } finally {
      restoring.value = false;
    }
  }

  Future<void> register(String email, String password, String name) async {
    final r = await http.post(_u('/auth/register'),
        headers: _jsonHeaders,
        body: jsonEncode(
            {'email': email, 'password': password, 'display_name': name}));
    if (r.statusCode >= 400) {
      throw _err(r);
    }
  }

  /// [remember] false ise oturum cihaza kaydedilmez; uygulama kapanınca biter.
  Future<void> login(String email, String password, {bool remember = true}) async {
    // OAuth2 password flow form-encoded bekler.
    final r = await http.post(
      _u('/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (r.statusCode >= 400) throw _err(r);
    _remember = remember;
    if (!remember) await _forgetTokens();
    await _storeTokens(jsonDecode(r.body));
    sessionEndedReason = null;
    _inflight.clear(); // önceki hesabın yarım kalan istekleri paylaşılmasın
    chatLog.clear();
    session.value = true;
  }

  /// Çıkış: bu cihazdaki oturumu sunucuda kapatır ve kayıtlı token'ı siler.
  Future<void> logout() async {
    final refreshToken = _refreshToken;
    _endSession(null);
    await _forgetTokens();
    if (refreshToken != null) {
      try {
        await http.post(_u('/auth/logout'),
            headers: _jsonHeaders,
            body: jsonEncode({'refresh_token': refreshToken}));
      } catch (_) {
        // Sunucuya ulaşılamadıysa token süresi dolunca zaten geçersiz olur.
      }
    }
  }

  // ---- Hesap ----

  Future<({String email, String displayName})> getMe() async {
    final j = await _json('GET', '/auth/me');
    return (email: j['email'] as String, displayName: j['display_name'] as String);
  }

  /// Profil bilgileri (üyelik tarihi, uyarı tercihi, yapay zekâ onayı dahil).
  Future<UserModel> getProfile() async =>
      UserModel.fromJson(await _json('GET', '/auth/me'));

  /// Yalnızca verilen alanlar güncellenir.
  Future<UserModel> updateProfile({String? displayName, bool? alertsEnabled}) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (alertsEnabled != null) body['alerts_enabled'] = alertsEnabled;
    return UserModel.fromJson(await _json('PUT', '/auth/me', body: body));
  }

  /// Parolayı değiştirir. Diğer cihazlardaki oturumlar kapanır, bu cihaz devam eder.
  /// Mevcut parola yanlışsa "Mevcut parola hatalı" hatası fırlatır.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final j = await _json('POST', '/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    await _storeTokens(j);
  }

  /// Hesabı ve bütün verileri kalıcı olarak siler; ardından giriş ekranına dönülür.
  Future<void> deleteAccount(String password) async {
    await _send('DELETE', '/auth/me', body: {'password': password});
    await _forgetTokens();
    _endSession('Hesabın ve bütün verilerin silindi.');
  }

  // ---- İşlemler ----

  /// [offset] ile sayfalama: ilk sayfa 0, sonraki sayfa [limit] kadar ileri.
  /// Dönen liste [limit]'ten kısaysa başka kayıt yoktur.
  Future<List<TransactionModel>> getTransactions({
    String? category,
    String? type,
    String? month,
    String? q,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (offset > 0) params['offset'] = '$offset';
    if (category != null) params['category'] = category;
    if (type != null) params['type'] = type;
    if (month != null) params['month'] = month;
    if (q != null && q.isNotEmpty) params['q'] = q;
    final list = await _json('GET', '/transactions', query: params) as List;
    return list.map((e) => TransactionModel.fromJson(e)).toList();
  }

  /// İşlem olan aylar (yeniden eskiye) ve her ayın gelir/gider toplamı.
  Future<List<MonthSummaryModel>> getTransactionMonths() async {
    final list = await _json('GET', '/transactions/months') as List;
    return list.map((e) => MonthSummaryModel.fromJson(e)).toList();
  }

  /// Bakiye ve toplamlar (tüm işlemler) ile bir ayın kategori dağılımı.
  /// [month] "YYYY-MM"; verilmezse içinde bulunulan ay.
  Future<SummaryModel> getSummary({String? month}) async {
    return SummaryModel.fromJson(await _json('GET', '/transactions/summary',
        query: month == null ? null : {'month': month}));
  }

  /// Dönen işlemin [TransactionModel.budgetAlerts] alanı bütçe uyarılarını taşır.
  Future<TransactionModel> updateTransaction(
    int id, {
    double? amount,
    String? type,
    String? category,
    String? note,
    String? occurredOn,
    bool? isRecurring,
  }) async {
    final body = <String, dynamic>{};
    if (amount != null) body['amount'] = amount;
    if (type != null) body['type'] = type;
    if (category != null) body['category'] = category;
    if (note != null) body['note'] = note;
    if (occurredOn != null) body['occurred_on'] = occurredOn;
    if (isRecurring != null) body['is_recurring'] = isRecurring;
    return TransactionModel.fromJson(
        await _json('PUT', '/transactions/$id', body: body));
  }

  /// [occurredOn] "YYYY-MM-DD"; verilmezse bugün. Dönen işlemin
  /// [TransactionModel.budgetAlerts] alanı bütçe uyarılarını taşır.
  Future<TransactionModel> addTransaction({
    required double amount,
    required String type,
    String? category,
    String note = '',
    String? occurredOn,
    bool isRecurring = false,
    CategorySuggestion? shownSuggestion,
  }) async {
    final body = <String, dynamic>{
      'amount': amount,
      'type': type,
      'note': note,
      'is_recurring': isRecurring,
    };
    if (category != null) body['category'] = category;
    if (occurredOn != null) body['occurred_on'] = occurredOn;
    // Ekranda gösterilen öneri: seçilen kategoriyle karşılaştırılıp modelin gerçek
    // kullanımdaki doğruluğu ölçülür (backend ml_training/feedback_report.py).
    if (shownSuggestion != null) {
      body['suggested_category'] = shownSuggestion.category;
      body['suggestion_confidence'] = shownSuggestion.confidence;
      body['suggestion_model'] = shownSuggestion.model;
    }
    return TransactionModel.fromJson(
        await _json('POST', '/transactions', body: body));
  }

  Future<void> deleteTransaction(int id) async {
    await _send('DELETE', '/transactions/$id');
  }

  /// İşlem kategorileri (backend'deki liste; "Toplam" dahil değil).
  Future<List<String>> getCategories() async {
    final list = await _json('GET', '/categories') as List;
    return list.cast<String>();
  }

  // ---- Bütçeler ----

  Future<List<BudgetModel>> getBudgets() async {
    final list = await _json('GET', '/budgets') as List;
    return list.map((e) => BudgetModel.fromJson(e)).toList();
  }

  Future<BudgetModel> upsertBudget(String category, double limit) async {
    return BudgetModel.fromJson(await _json('POST', '/budgets',
        body: {'category': category, 'monthly_limit': limit}));
  }

  Future<void> deleteBudget(int id) async {
    await _send('DELETE', '/budgets/$id');
  }

  // ---- Uyarılar ----

  /// O anki uyarılar, önemliden önemsize. Bildirimler kapalıysa boş liste.
  Future<List<AlertModel>> getAlerts() async {
    final list = await _json('GET', '/alerts') as List;
    return list.map((e) => AlertModel.fromJson(e)).toList();
  }

  /// Uyarıyı kapatır; aynı uyarı bir daha gösterilmez.
  Future<void> dismissAlert(String id) async {
    await _send('POST', '/alerts/dismiss', body: {'id': id});
  }

  // ---- Analitik ----

  Future<ForecastModel> getForecast() async =>
      ForecastModel.fromJson(await _json('GET', '/analytics/forecast'));

  Future<List<AnomalyModel>> getAnomalies() async {
    final list = await _json('GET', '/analytics/anomalies') as List;
    return list.map((e) => AnomalyModel.fromJson(e)).toList();
  }

  Future<List<InsightModel>> getInsights() async {
    final list = await _json('GET', '/analytics/insights') as List;
    return list.map((e) => InsightModel.fromJson(e)).toList();
  }

  // ---- Tasarruf hedefleri ----

  Future<List<GoalModel>> getGoals() async {
    final list = await _json('GET', '/goals') as List;
    return list.map((e) => GoalModel.fromJson(e)).toList();
  }

  /// [deadline] "YYYY-MM-DD"; bugünden önce olamaz.
  Future<GoalModel> createGoal(String title, double target,
      {String? deadline}) async {
    final body = <String, dynamic>{'title': title, 'target_amount': target};
    if (deadline != null) body['deadline'] = deadline;
    return GoalModel.fromJson(await _json('POST', '/goals', body: body));
  }

  /// Yalnızca verilen alanlar güncellenir. Son tarihi kaldırmak için
  /// [clearDeadline] true verilir.
  Future<GoalModel> updateGoal(
    int id, {
    String? title,
    double? targetAmount,
    String? deadline,
    bool clearDeadline = false,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (targetAmount != null) body['target_amount'] = targetAmount;
    if (deadline != null) body['deadline'] = deadline;
    if (clearDeadline) body['deadline'] = null;
    return GoalModel.fromJson(await _json('PUT', '/goals/$id', body: body));
  }

  Future<GoalModel> contributeGoal(int id, double amount) async {
    return GoalModel.fromJson(
        await _json('POST', '/goals/$id/contribute', body: {'amount': amount}));
  }

  /// Hedefte biriken paradan geri alır. Birikimden fazlası istenirse hata fırlatır.
  Future<GoalModel> withdrawGoal(int id, double amount) async {
    return GoalModel.fromJson(
        await _json('POST', '/goals/$id/withdraw', body: {'amount': amount}));
  }

  Future<void> deleteGoal(int id) async {
    await _send('DELETE', '/goals/$id');
  }

  // ---- Yapay zekâ ----

  /// Hero model: not metninden kategori önerisi (canlı).
  Future<CategorySuggestion> categorize(String text) async {
    return CategorySuggestion.fromJson(
        await _json('POST', '/ml/categorize', body: {'text': text}));
  }

  /// Sohbet asistanı için veri paylaşımı onayı verilmiş mi?
  Future<bool> hasAiConsent() async {
    final j = await _json('GET', '/auth/me');
    return j['ai_consent_at'] != null;
  }

  /// Onayı verir (true) ya da geri çeker (false).
  Future<void> setAiConsent(bool value) async {
    await _send(value ? 'POST' : 'DELETE', '/auth/me/ai-consent');
  }

  /// Sohbet geçmişi. Yalnızca bellekte tutulur (cihaza ve sunucuya yazılmaz);
  /// çıkışta ve oturum düşünce silinir. Asistan önceki mesajları hatırlasın diye
  /// son [chatHistoryTurns] tur her soruyla birlikte gönderilir.
  final chatLog = <ChatTurn>[];
  static const chatHistoryTurns = 20;

  /// AI Chatbot: Gemini asistanı ile sohbet. [currency] ekranda kullanılan para
  /// birimi (TRY, USD, EUR, GBP), [rate] 1 TRY'nin o birimdeki karşılığı; asistan
  /// tutarları bu birimde yazar. Başarılı soru ve cevap [chatLog]'a eklenir.
  Future<String> sendChatMessage(String message,
      {String currency = 'TRY', double rate = 1}) async {
    final recent = chatLog.length > chatHistoryTurns
        ? chatLog.sublist(chatLog.length - chatHistoryTurns)
        : chatLog;
    final j = await _json('POST', '/chat', body: {
      'message': message,
      'currency': currency,
      'rate': rate,
      'history': [for (final t in recent) t.toJson()],
    });
    final reply = j['reply'] as String;
    chatLog
      ..add(ChatTurn(fromUser: true, text: message))
      ..add(ChatTurn(fromUser: false, text: reply));
    return reply;
  }

  Exception _err(http.Response r) {
    // Oturum açıkken 401: token yenilenemedi; giriş ekranına dönülür.
    if (r.statusCode == 401 && session.value) {
      _endSession('Oturumun sona erdi. Lütfen tekrar giriş yap.');
      _forgetTokens();
    }
    try {
      final detail = jsonDecode(r.body)['detail'];
      // Doğrulama hatası (422) bir liste döner; ilk mesaj kullanıcıya gösterilir.
      if (detail is List && detail.isNotEmpty) {
        final msg = (detail.first['msg'] ?? '')
            .toString()
            .replaceFirst('Value error, ', '');
        if (msg.isNotEmpty) return Exception(msg);
      }
      return Exception(detail?.toString() ?? 'Hata ${r.statusCode}');
    } catch (_) {
      return Exception('Hata ${r.statusCode}');
    }
  }
}
