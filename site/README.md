# Expenza web sitesi

Expenza kişisel finans uygulamasının tanıtım sayfası. Derleme adımı yok, düz HTML, CSS ve JavaScript.

```
index.html          sayfa
assets/styles.css   renkler, animasyonlar, duyarlı düzen
assets/app.js       mobil menü ve canlı önizleme kartı
assets/favicon.svg
```

## Yerelde açmak

`site` klasöründe:

```bash
python -m http.server 8095
```

Sonra tarayıcıda http://localhost:8095 adresini aç.

## Doldurulacak yerler

- SSS bölümünde `[İLETİŞİM E-POSTASI]` ve `[FİYAT BİLGİSİ]`
- "Giriş yap" ve "Hesap oluştur" bağlantıları şimdilik `#`; uygulamanın web adresi belli olunca güncellenecek
- Alt bilgideki İletişim, Gizlilik ve Kullanım koşulları bağlantıları

Canlı önizleme kartı basit bir kelime eşleştirmesiyle çalışır. Uygulamadaki asıl kategori modeli (TF-IDF + SVM) `backend/app/ml/` altında.

`main` dalına `site/` içinde bir değişiklik push'lanınca `.github/workflows/pages.yml` siteyi GitHub Pages'e yayınlar.
