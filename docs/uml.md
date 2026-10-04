# UML çizimleri

GŞÖA'nın "Ön Analiz" bölümünün istediği beş çizim: kullanım durumu, sınıf, sıra, durum makinesi ve etkinlik. Çizimler koddaki gerçek sınıflara, uçlara ve eşik değerlere göre hazırlandı; kod değiştikçe güncellenmelidir.

Çizimler Mermaid ile yazıldı. GitHub bu dosyayı açınca çizimleri gösterir. Rapora koymak için bir çizimin kodunu [mermaid.live](https://mermaid.live) sayfasına yapıştırıp PNG ya da SVG olarak indirebilir veya `npx @mermaid-js/mermaid-cli -i uml.md` ile dışa aktarabilirsiniz.

## 1. Kullanım durumu (use case) çizimi

Mermaid'de ayrı bir use case çizim türü olmadığı için aktörler köşeli, kullanım durumları oval kutularla gösterildi. Kesikli oklar `include` (her zaman dahil) ve `extend` (isteğe bağlı) ilişkileridir.

```mermaid
flowchart LR
    K["Kullanıcı"]
    G["Google Gemini API"]
    D["Döviz kuru servisi<br/>open.er-api.com"]
    Z["Zamanlayıcı<br/>(backend arka plan görevi)"]

    subgraph S["Expenza"]
        UC1(["Hesap oluştur"])
        UC2(["Giriş yap / çıkış yap"])
        UC3(["Gelir veya gider ekle"])
        UC4(["Kategori önerisi al"])
        UC5(["Fiş tara"])
        UC6(["Her ay tekrarla"])
        UC7(["İşlemleri listele, ara, düzenle, sil"])
        UC8(["Ana sayfa özetini gör"])
        UC9(["Aylık bütçe belirle ve izle"])
        UC10(["Tasarruf hedefi oluştur, katkı ekle"])
        UC11(["Harcama tahmini ve anomalileri gör"])
        UC12(["Kişisel içgörüleri gör"])
        UC13(["Sohbet asistanına soru sor"])
        UC14(["Veri paylaşımına onay ver / geri çek"])
        UC15(["Para birimi seç"])
        UC16(["Tekrarlayan işlemleri üret"])
    end

    K --- UC1 & UC2 & UC3 & UC7 & UC8 & UC9 & UC10 & UC11 & UC12 & UC13 & UC14 & UC15
    UC3 -. include .-> UC4
    UC5 -. extend .-> UC3
    UC6 -. extend .-> UC3
    UC13 -. include .-> UC14
    UC13 --- G
    UC15 --- D
    Z --- UC16
```

| Kullanım durumu | Nerede |
|---|---|
| Hesap oluştur, giriş/çıkış | `POST /auth/register`, `POST /auth/login`; `login_screen.dart` |
| Gelir veya gider ekle | `POST /transactions`; `add_transaction_screen.dart` |
| Kategori önerisi al | `POST /ml/categorize`; `app/ml/categorizer.py` |
| Fiş tara | `ocr_service.dart` (cihaz üzerinde ML Kit, yalnızca mobil) |
| Her ay tekrarla / tekrarlayan işlemleri üret | `app/recurring.py`, `main.py` (saatlik görev) |
| Ana sayfa özeti | `GET /transactions/summary`; `dashboard_screen.dart` |
| Bütçe | `/budgets`; `budgets_screen.dart` |
| Tasarruf hedefi | `/goals`; `goals_screen.dart` |
| Tahmin ve anomaliler | `/analytics/forecast`, `/analytics/anomalies`; `analytics_screen.dart` |
| İçgörüler | `/analytics/insights`; `profile_screen.dart` |
| Sohbet ve onay | `POST /chat`, `/auth/me/ai-consent`; `chat_screen.dart` |
| Para birimi | `CurrencyService` (`theme.dart`); `profile_screen.dart` |

## 2. Sınıf çizimleri

### Veri modeli

`backend/app/models.py` içindeki tablolar. Tutarlar TL olarak saklanır.

```mermaid
classDiagram
    direction LR
    class User {
        +int id
        +str email
        +str hashed_password
        +str display_name
        +datetime created_at
        +datetime ai_consent_at
    }
    class Transaction {
        +int id
        +int user_id
        +Decimal amount
        +TxType type
        +CategoryEnum category
        +bool auto_categorized
        +CategoryEnum suggested_category
        +float suggestion_confidence
        +str suggestion_model
        +bool is_recurring
        +int series_id
        +str note
        +date occurred_on
        +datetime created_at
    }
    class RecurringSeries {
        +int id
        +int user_id
        +Decimal amount
        +TxType type
        +CategoryEnum category
        +str note
        +int day_of_month
        +date start_on
        +date last_generated_on
        +bool active
    }
    class Budget {
        +int id
        +int user_id
        +CategoryEnum category
        +Decimal monthly_limit
    }
    class Goal {
        +int id
        +int user_id
        +str title
        +Decimal target_amount
        +Decimal current_amount
        +date deadline
    }
    class TxType {
        <<enumeration>>
        income
        expense
    }
    class CategoryEnum {
        <<enumeration>>
        Yemek
        Ulaşım
        Faturalar
        Eğlence
        Sağlık
        Eğitim
        Alışveriş
        Diğer
        Toplam
    }

    User "1" --> "0..*" Transaction
    User "1" --> "0..*" RecurringSeries
    User "1" --> "0..*" Budget
    User "1" --> "0..*" Goal
    RecurringSeries "0..1" --> "0..*" Transaction : üretir
    Transaction ..> TxType
    Transaction ..> CategoryEnum
    Budget ..> CategoryEnum
```

`Toplam` yalnızca bütçede kullanılır (aylık toplam bütçe); işlemler için geçerli bir kategori değildir.

### Kategori sınıflandırıcıları

`backend/app/ml/categorizer.py`. Hepsi aynı `predict` sözleşmesini uygular; `categorize()` hangisinin kullanılacağına karar verir.

```mermaid
classDiagram
    class Categorizer {
        <<interface>>
        +str name
        +predict(text) tuple
    }
    class MLCategorizer {
        +name: baseline-svm-v1
        -Pipeline pipe
        +predict(text)
    }
    class RuleBasedCategorizer {
        +name: rule-stub-v1
        +predict(text)
    }
    class GeminiCategorizer {
        +name: gemini-classifier-v1
        +predict(text)
    }
    class categorize {
        <<function>>
        +categorize(text) tuple
    }
    Categorizer <|.. MLCategorizer
    Categorizer <|.. RuleBasedCategorizer
    Categorizer <|.. GeminiCategorizer
    categorize --> MLCategorizer : varsayılan
    categorize --> RuleBasedCategorizer : model dosyası yoksa
    categorize --> GeminiCategorizer : CATEGORIZER=gemini ise önce
```

## 3. Sıra (sequence) çizimleri

### Giriş

```mermaid
sequenceDiagram
    actor K as Kullanıcı
    participant L as LoginScreen
    participant A as ApiClient
    participant B as FastAPI /auth/login
    participant R as ratelimit
    participant DB as Veritabanı

    K->>L: e-posta ve parola, "Giriş Yap"
    L->>A: login(email, parola)
    A->>B: POST /auth/login (form)
    B->>R: IP ve e-posta sınırı kontrolü
    alt sınır aşıldı
        R-->>B: 429
        B-->>A: 429 Çok fazla istek
        A-->>L: hata mesajı
    else sınır içinde
        B->>DB: kullanıcıyı e-postayla bul
        B->>B: bcrypt ile parolayı doğrula
        alt parola yanlış
            B->>R: hatalı denemeyi say
            B-->>A: 401
            A-->>L: "E-posta veya parola hatalı"
        else doğru
            B-->>A: 200 {access_token (JWT, 7 gün)}
            A->>A: token'ı bellekte tut, session = true
            A-->>L: başarılı
            L->>K: ana sayfa (HomeShell)
        end
    end
```

### Gider ekleme ve kategori önerisi

```mermaid
sequenceDiagram
    actor K as Kullanıcı
    participant E as AddTransactionScreen
    participant A as ApiClient
    participant M as /ml/categorize
    participant C as categorize()
    participant T as /transactions
    participant DB as Veritabanı

    K->>E: not yazar ("migros market")
    E->>E: 450 ms bekle (debounce)
    E->>A: categorize(not)
    A->>M: POST /ml/categorize
    M->>C: categorize(not)
    C-->>M: (Yemek, 0.99, baseline-svm-v1)
    M-->>E: öneri kartı
    K->>E: "Kabul et" ya da başka kategori seçer, tutarı girer
    K->>E: "Kaydet"
    E->>E: tutarı seçili para biriminden TL'ye çevir
    E->>A: addTransaction(..., shownSuggestion)
    A->>T: POST /transactions (category, suggested_category, ...)
    T->>DB: işlemi yaz
    opt "Her ay tekrarla" seçili
        T->>DB: seri oluştur ve geçmiş ayları üret
    end
    T-->>A: 201
    A-->>E: başarılı
    E->>K: listeye dön, ana sayfa, bütçe ve analitik yenilenir
```

### Sohbet asistanı ve açık rıza

```mermaid
sequenceDiagram
    actor K as Kullanıcı
    participant S as ChatScreen
    participant A as ApiClient
    participant B as FastAPI
    participant DB as Veritabanı
    participant G as Gemini API

    K->>S: sohbet ekranını açar
    S->>A: hasAiConsent()
    A->>B: GET /auth/me
    B-->>S: ai_consent_at
    alt onay yok
        S->>K: aydınlatma metni ve onay paneli
        K->>S: "Onaylıyorum"
        S->>B: POST /auth/me/ai-consent
        B->>DB: ai_consent_at = şimdi
    end
    K->>S: soru yazar
    S->>B: POST /chat {message}
    B->>B: kullanıcı başına istek sınırı, onay kontrolü
    B->>DB: son 30 işlem, bütçeler, hedefler
    B->>G: systemInstruction (kurallar + veriler), kullanıcı mesajı (ayrı alan)
    alt Gemini cevap verdi
        G-->>B: metin
        B-->>S: {reply}
    else hata
        G-->>B: hata
        B-->>S: 502 "Asistan şu anda yanıt veremiyor"
    end
    S->>K: cevap balonu
```

## 4. Durum makinesi çizimleri

### Kategori bütçesinin durumu

`budgets_screen.dart`'taki eşikler: harcanan / aylık limit oranına göre. Ay değişince harcanan tutar sıfırdan başlar.

```mermaid
stateDiagram-v2
    state "Yolunda" as Yolunda
    state "Dikkat" as Dikkat
    state "Kritik" as Kritik
    state "Aşıldı" as Asildi
    [*] --> Yolunda : bütçe belirlendi
    Yolunda --> Dikkat : oran en az %75
    Dikkat --> Kritik : oran en az %90
    Kritik --> Asildi : oran en az %100
    Dikkat --> Yolunda : limit artırıldı veya gider silindi
    Kritik --> Dikkat : limit artırıldı veya gider silindi
    Asildi --> Kritik : limit artırıldı veya gider silindi
    Dikkat --> Yolunda : yeni ay
    Kritik --> Yolunda : yeni ay
    Asildi --> Yolunda : yeni ay
    Yolunda --> [*] : bütçe silindi
```

### Tekrarlayan işlem serisi

`app/recurring.py`. Durdurulan bir seri yeniden başlatılmaz; işaret tekrar konursa yeni bir seri açılır.

```mermaid
stateDiagram-v2
    [*] --> Aktif : işlem "Her ay tekrarla" ile kaydedildi
    Aktif --> Aktif : ayın günü geldi, işlem üretilir
    Aktif --> Aktif : tutar, tür, kategori veya not düzenlendi, şablon güncellenir
    Aktif --> Aktif : bir ayın kaydı silindi, o ay yeniden üretilmez
    Aktif --> Durduruldu : işaret kaldırıldı (is_recurring = false)
    Durduruldu --> [*]
```

### Uygulama oturumu

`ApiClient.session` ve `_AuthGate` (`main.dart`).

```mermaid
stateDiagram-v2
    state "Giriş ekranı" as Giris
    state "Oturumda" as Oturumda
    [*] --> Giris
    Giris --> Oturumda : giriş başarılı (JWT)
    Oturumda --> Giris : çıkış yap
    Oturumda --> Giris : 401, token süresi doldu veya geçersiz
    Giris --> Giris : 401 hatalı parola, 429 çok fazla deneme
```

## 5. Etkinlik (activity) çizimleri

### Gelir veya gider ekleme

```mermaid
flowchart TD
    A([Başla]) --> B{Gider mi, gelir mi?}
    B -- Gider --> C{Mobil cihaz ve<br/>fiş taranacak mı?}
    C -- Evet --> D[Kamera veya galeriden fiş seç]
    D --> E[ML Kit ile metni oku,<br/>toplam ve işyerini ayrıştır]
    E --> F[Tutar ve notu doldur<br/>TL'den seçili para birimine çevir]
    C -- Hayır --> G[Tutar ve not gir]
    F --> H
    G --> H[Not en az 3 karakterse 450 ms sonra<br/>kategori önerisi iste]
    H --> I[Öneriyi kabul et<br/>ya da kategori seç]
    B -- Gelir --> J[Tutar ve not gir]
    I --> K{Her ay tekrarlansın mı?}
    J --> K
    K -- Evet --> L[Onay penceresi]
    L --> M
    K -- Hayır --> M{Tutar > 0 ve<br/>gider için kategori seçili mi?}
    M -- Hayır --> N[Uyarı göster] --> G
    M -- Evet --> O[POST /transactions]
    O --> P{Sunucu cevabı}
    P -- 201 --> Q[Ana sayfa, bütçe ve analitiği yenile]
    P -- 422 / 401 / ağ hatası --> R[Hata mesajı,<br/>401 ise giriş ekranına dön]
    Q --> S([Bitir])
    R --> S
```

### Tekrarlayan işlemlerin üretilmesi

Sunucu açılışta ve saatte bir `materialize_all()` çalıştırır.

```mermaid
flowchart TD
    A([Zamanlayıcı tetiklendi]) --> B[Aktif serileri al]
    B --> C{Sırada seri var mı?}
    C -- Hayır --> Z([Bitir])
    C -- Evet --> D[Ay = last_generated_on'un ayı]
    D --> E[Sonraki aya geç]
    E --> F[Gün = min day_of_month, ayın son günü]
    F --> G{Bu tarih bugünden sonra mı?}
    G -- Evet --> H[Commit]
    G -- Hayır --> I[İşlemi ekle, last_generated_on = bu tarih]
    I --> E
    H --> J{Benzersizlik ihlali?<br/>başka süreç aynı ayı üretti}
    J -- Evet --> K[Geri al, bu seriyi atla] --> C
    J -- Hayır --> C
```
