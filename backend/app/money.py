"""Para tutarları: Python'da Decimal, veritabanında NUMERIC(12, 2).

float ile 0.1 + 0.2 gibi toplamlar 0.30000000000000004 olur; bütçe ve bakiye
hesaplarında bu kuruş farkları birikir. Bu yüzden tutarlar iki ondalığa yuvarlanmış
Decimal olarak tutulur ve toplanır. API sözleşmesi değişmez: istemci yine sayı
gönderir ve alır (gelen değer kuruşa yuvarlanır).

Tahmin ve anomali gibi istatistik hesapları para değil ölçüm olduğu için float ile
yapılır (app/ml/).
"""
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Annotated, Any, Optional

from pydantic import BeforeValidator
from sqlalchemy import Numeric
from sqlalchemy.types import TypeDecorator

CENT = Decimal("0.01")
ZERO = Decimal("0.00")


def to_money(value: Any) -> Decimal:
    """Sayıyı kuruşa yuvarlanmış Decimal'e çevirir (0,005 yukarı yuvarlanır).

    float doğrudan değil metni üzerinden çevrilir: Decimal(0.1) ikili gösterimin
    bütün basamaklarını taşır, Decimal("0.1") taşımaz.
    """
    # Hatalar ValueError olarak yükselir; pydantic bunları 422 cevabına çevirir.
    if isinstance(value, Decimal):
        d = value
    elif isinstance(value, (int, float, str)) and not isinstance(value, bool):
        try:
            d = Decimal(str(value))
        except InvalidOperation:
            raise ValueError("para tutarı sayı olmalı") from None
    else:
        raise ValueError("para tutarı sayı olmalı")
    if not d.is_finite():
        raise ValueError("para tutarı sonlu bir sayı olmalı")
    return d.quantize(CENT, rounding=ROUND_HALF_UP)


# İstek şemalarında: gelen sayı önce kuruşa yuvarlanır, sonra sınırlar denetlenir.
MoneyIn = Annotated[Decimal, BeforeValidator(to_money)]


class Money(TypeDecorator):
    """NUMERIC(12, 2) sütunu; okunan ve yazılan değerler Decimal.

    SQLite gerçek bir ondalık tipi olmadığı için değeri REAL olarak saklar. Her değer
    yazılmadan önce kuruşa yuvarlandığından ve okunurken yeniden yuvarlandığından
    (12 basamağa kadar float bunu kayıpsız taşır) sonuç değişmez. PostgreSQL gibi bir
    veritabanında sütun gerçek NUMERIC olur.
    """

    # asdecimal=False: dönüşümü kendimiz yapıyoruz; SQLAlchemy'nin SQLite'taki
    # "Decimal desteklenmiyor" uyarısı da böylece çıkmaz.
    impl = Numeric(12, 2, asdecimal=False)
    cache_ok = True

    def process_bind_param(self, value: Any, dialect) -> Optional[float]:
        return None if value is None else float(to_money(value))

    def process_result_value(self, value: Any, dialect) -> Optional[Decimal]:
        return None if value is None else to_money(value)
