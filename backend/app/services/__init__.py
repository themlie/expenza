"""Servis katmanı: iş kuralları burada, HTTP ayrıntıları router'larda.

Router'lar isteği doğrular, servis fonksiyonunu çağırır ve sonucu şemaya çevirir.
Servisler FastAPI'ye bağlı değildir; kural ihlallerinde errors modülündeki istisnaları
fırlatır, main.py bunları HTTP cevabına çevirir.

Aynı katmanın parçası olan diğer modüller: coach (uyarılar, hedef planı), recurring
(tekrarlayan seriler), sessions (oturumlar), export (CSV).
"""
