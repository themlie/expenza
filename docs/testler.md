# Testler

Raporun test bölümü için kaynak. Değerler 3 Ekim 2026'daki durumdur; güncel sonuç her push'ta GitHub Actions'ta (`.github/workflows/ci.yml`) görülür.

## Özet

| | Backend | Mobil |
|---|---|---|
| Araç | pytest, pytest-cov | flutter_test, flutter analyze |
| Test sayısı | 109 durum (89 test fonksiyonu, bir kısmı birden fazla girdiyle) | 2 widget testi |
| Kapsam | `app/` paketinin %96'sı (966 satırdan 924'ü) | ölçülmedi |
| Statik analiz | | `flutter analyze`: sorun yok |
| CI | Her push'ta | Her push'ta |

Backend testleri geçici bir SQLite dosyası kullanır, her testten sonra tabloları ve istek sınırlayıcıyı temizler. Gemini'ye gerçek istek atılmaz; ilgili testler istemciyi sahte bir cevapla değiştirir.

## Backend test dosyaları

| Dosya | Durum | Ne doğrulanıyor |
|---|---|---|
| `test_auth.py` | 12 | Kayıt, giriş, hatalı parola ve olmayan kullanıcı için aynı hata, süresi geçmiş, imzasız, `exp` alanı olmayan ve başka anahtarla imzalanmış token'ların reddi, `SECRET_KEY` olmadan backend'in açılmaması |
| `test_authorization.py` | 21 | Korunan 17 ucun token istemesi; bir kullanıcının başkasının işlemlerini, bütçelerini, hedeflerini ve analitiğini görememesi ve değiştirememesi |
| `test_security.py` | 10 | Hatalı paroladan sonra geçici kilit, IP başına giriş ve kayıt sınırı, sohbet sınırı, parola kuralı ve Türkçe mesajları, CORS izinleri, güvenlik başlıkları, API belgelerinin kapatılabilmesi |
| `test_transactions.py` | 13 | Ekleme, modelin kategori ataması, filtreler ve sıralama, kısmi güncelleme, silme, girdi boyutu sınırları |
| `test_recurring.py` | 9 | Ay sonu gününün kaymaması, tekrar çalıştırmada çift kayıt olmaması, silinen ayın geri gelmemesi, serinin durdurulması, düzenlemenin sonraki aylara geçmesi, okuma isteğinin veri yazmaması, benzersizlik kısıtı |
| `test_summary.py` | 3 | Bakiyenin 200'den fazla işlemde doğru hesaplanması, aylık dağılım |
| `test_budgets_goals.py` | 6 | Bütçenin güncellenmesi, yalnızca bu ayın giderlerinin sayılması, toplam bütçe, hedef ilerlemesi |
| `test_analytics_unit.py` | 8 | Tahmin yöntemleri (koşu hızı, son ay, doğrusal trend), anomali eşiği, içgörüler |
| `test_analytics_api.py` | 3 | SQL ile hesaplanan analitik sonuçlarının liste tabanlı hesapla birebir aynı olması |
| `test_ml.py` | 4 | Kategori ucu, uzun metnin reddi, eğitilmiş modelin yüklenmesi, kural tabanlı yedek |
| `test_chat_llm.py` | 11 | Onaysız sohbetin engellenmesi, prompt'ta yalnızca kullanıcının kendi verisinin ve adının olmaması, onayın geri çekilmesi, hata mesajının sızmaması, anahtarın URL'de değil başlıkta gitmesi, yerel modelin varsayılan olması |
| `test_feedback.py` | 6 | Gösterilen önerinin saklanması, model atamalarının geri bildirimden ayrılması, kabul oranı ve kalibrasyon hesapları, etiket dışa aktarımı, değerlendirme aracı |
| `test_migrations.py` | 3 | Migration'ların modellerle uyumu (`alembic check`), eski bir veritabanının veri kaybı olmadan güncellenmesi, eski tekrarlayan kayıtların serilere bağlanması |

## Kapsam ayrıntısı

Kapsamı %90'ın altında kalan modüller ve nedenleri:

| Modül | Kapsam | Kapsanmayan kısım |
|---|---|---|
| `llm.py` | %75 | Gerçek ağ hataları (bağlantı kopması, bozuk cevap) |
| `main.py` | %78 | Arka plan görevinin döngüsü (sunucu çalışırken çalışır) |

Diğer bütün modüller %90 ve üstünde; router'ların ve şemaların tamamı %100.

## Güvenlik testleri (OWASP eşleşmesi)

| OWASP 2021 | İlgili testler |
|---|---|
| A01 Erişim kontrolü | `test_authorization.py` (21) |
| A02 Kriptografik hatalar | `test_auth.py`: secret zorunluluğu, imzasız ve başka anahtarlı token |
| A03 Enjeksiyon | `test_chat_llm.py`: kullanıcı mesajının talimatlardan ayrı gitmesi; SQL tarafı ORM ile parametreli |
| A04 Güvensiz tasarım | `test_security.py`: istek sınırları; `test_recurring.py`: okuma isteğinin yan etkisiz olması |
| A05 Yanlış yapılandırma | `test_security.py`: CORS, güvenlik başlıkları, API belgeleri |
| A07 Kimlik doğrulama | `test_auth.py`, `test_security.py`: kilit, parola kuralı, aynı hata mesajı |

## Eksikler

- Mobil tarafta yalnızca giriş ekranı için widget testi var; diğer ekranlar ve `ApiClient` test edilmiyor.
- Uçtan uca (uygulama + backend birlikte) otomatik test yok; bu akışlar tarayıcıda elle denendi.
- Android ve iOS derlemeleri test ortamında denenmedi (Android SDK ve Mac yok).
- Gemini'ye gerçek istek atan bir test yok (anahtar ve maliyet gerektirir).

## Çalıştırma

```bash
cd backend
pip install -r requirements-dev.txt
pytest --cov=app --cov-report=term-missing
```

```bash
cd mobile
flutter analyze
flutter test
```
