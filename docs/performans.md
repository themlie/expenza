# Performans ölçümleri

Bu belge, GŞÖA'nın kapasite ve ölçeklenebilirlik bölümleri için backend'in yük altındaki davranışını ölçer. Ölçümler `backend/tools/load_test.py` ile yapıldı.

## Yöntem

Test aracı her senaryoda yeni bir kullanıcı açar, ona belirtilen sayıda gider ekler (son bir yıla dağılmış, rastgele kategorilerde) ve ardından uygulamanın açılışta çağırdığı dört okuma ucuna eşzamanlı istek gönderir:

- `GET /transactions/summary`
- `GET /transactions?limit=200`
- `GET /analytics/forecast`
- `GET /budgets`

İstemciler uçları sırayla dolaşır. Her uç için istek sayısı, saniyedeki istek, gecikme yüzdelikleri (p50, p95, p99) ve hata sayısı kaydedilir.

Ölçüm koşulları:

| | |
|---|---|
| Tarih | 3 Ekim 2026 |
| İşlemci | 12th Gen Intel Core i5-1240P (16 mantıksal çekirdek) |
| Bellek | 16 GB |
| İşletim sistemi | Windows 11 |
| Sunucu | uvicorn, tek süreç, erişim logu kapalı |
| Veritabanı | SQLite (dosya), her ölçüm serisinden önce boş |
| Ağ | Aynı makine (localhost); ağ gecikmesi dahil değil |

Sonuçlar bu makineye ve SQLite'a bağlıdır. Mutlak değerlerden çok senaryolar arasındaki fark ve değişikliğin etkisi anlamlıdır.

## İlk ölçüm ve bulunan darboğaz

| Senaryo | Toplam istek/sn | Tahmin ucu p50 | Tahmin ucu p99 | Hata |
|---|---|---|---|---|
| 1.000 işlem, 1 istemci | 46.2 | 24 ms | 154 ms | 0 |
| 1.000 işlem, 8 istemci | 53.5 | 152 ms | 584 ms | 0 |
| 5.000 işlem, 8 istemci | 15.6 | 1154 ms | 2572 ms | 0 |

Kullanıcının işlem sayısı 5.000'e çıkınca tahmin ucu belirgin biçimde yavaşladı ve diğer uçları da yavaşlattı: sunucu tek süreçle çalıştığı için bir uçtaki ağır iş ötekilerin de sırada beklemesine yol açıyordu. Sebep, analitik uçlarının kullanıcının bütün işlemlerini ORM nesnesi olarak belleğe alıp toplamları Python'da hesaplamasıydı.

## Değişiklik

- Tahmin ucu aylık toplamları ve içinde bulunulan ayın kategori dağılımını SQL `GROUP BY` ile hesaplıyor. Hesap mantığı aynı (`forecast_from_totals`), sadece toplamlar veritabanından hazır geliyor.
- Anomali ucu yalnızca gereken altı sütunu okuyor; z-skoru her harcamaya baktığı için kayıtları okumaya devam ediyor.
- İçgörü ucu yalnızca bu ayın ve geçen ayın kayıtlarını okuyor.

Değişikliğin sonucu değiştirmediği `backend/tests/test_analytics_api.py` ile doğrulanıyor: aynı veride uçların cevabı, işlem listesinden hesaplanan sonuçla birebir aynı.

## Değişiklikten sonra

| Senaryo | Toplam istek/sn | Tahmin ucu p50 | Tahmin ucu p99 | Hata |
|---|---|---|---|---|
| 1.000 işlem, 1 istemci | 79.1 | 9 ms | 18 ms | 0 |
| 1.000 işlem, 8 istemci | 89.1 | 72 ms | 260 ms | 0 |
| 5.000 işlem, 8 istemci | 53.5 | 194 ms | 286 ms | 0 |

En ağır senaryoda toplam verim 3,4 kat arttı, tahmin ucunun medyan gecikmesi yaklaşık 6 kat azaldı ve p99 değeri 2,6 saniyeden 0,3 saniyenin altına indi. Hiçbir senaryoda hata oluşmadı.

5.000 işlemlik senaryodaki uç bazında değerler:

| Uç | p50 | p95 | p99 |
|---|---|---|---|
| `GET /transactions/summary` | 188 ms | 249 ms | 282 ms |
| `GET /transactions?limit=200` | 25 ms | 128 ms | 200 ms |
| `GET /analytics/forecast` | 194 ms | 254 ms | 286 ms |
| `GET /budgets` | 102 ms | 163 ms | 207 ms |

## Sınırlar ve sonraki adımlar

- Özet ve tahmin uçlarındaki ay filtresi `extract(year/month)` kullandığı için indeks kullanılamıyor. Tarih aralığıyla filtrelemek ve `(user_id, occurred_on)` üzerine bileşik indeks eklemek bu uçları daha da hızlandırabilir.
- Ölçümler tek süreçli uvicorn ve SQLite içindir. Birden fazla süreç ya da PostgreSQL ile sonuçlar değişir; istek sınırlayıcı da bellek içinde olduğu için çok süreçli kurulumda paylaşılan bir depo gerekir.
- Ağ gecikmesi ölçülmedi. Sunucu uzak bir makinede çalıştığında her isteğe ağ süresi eklenir.

## Tekrar üretme

Backend'i boş bir veritabanıyla başlatın (gerçek kullanıcı verisi olan bir veritabanında çalıştırmayın; test kullanıcıları kalıcı olarak eklenir) ve `backend` klasöründe:

```bash
python -m tools.load_test --url http://localhost:8010 --workers 1 --seconds 15 --transactions 1000
python -m tools.load_test --url http://localhost:8010 --workers 8 --seconds 20 --transactions 1000
python -m tools.load_test --url http://localhost:8010 --workers 8 --seconds 20 --transactions 5000
```
