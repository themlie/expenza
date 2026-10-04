"""İşlemlerin CSV olarak dışa aktarılması.

Dosya Türkçe Excel'de çift tıklayınca düzgün açılacak biçimde yazılır: UTF-8 BOM
(Türkçe karakterler için), ';' ayırıcı ve virgüllü ondalık. Tutarlar veritabanındaki
gibi TRY'dir.
"""
import csv
import io
from collections.abc import Iterable

from . import models

HEADER = ["Tarih", "Tür", "Kategori", "Tutar (TRY)", "Not", "Tekrarlayan"]
_TYPE_LABELS = {models.TxType.expense: "Gider", models.TxType.income: "Gelir"}
# Excel bu karakterlerle başlayan hücreyi formül sayar (CSV injection). Başına
# kesme işareti eklenir; hücre düz metin olarak görünür.
_FORMULA_START = ("=", "+", "-", "@", "\t", "\r")


def _text(value: str) -> str:
    return "'" + value if value.startswith(_FORMULA_START) else value


def _amount(value: float) -> str:
    return f"{value:.2f}".replace(".", ",")


def transactions_csv(transactions: Iterable[models.Transaction]) -> str:
    out = io.StringIO()
    out.write("﻿")
    writer = csv.writer(out, delimiter=";", lineterminator="\r\n")
    writer.writerow(HEADER)
    for t in transactions:
        writer.writerow([
            t.occurred_on.isoformat(),
            _TYPE_LABELS[t.type],
            t.category.value,
            _amount(t.amount),
            _text(t.note or ""),
            "Evet" if t.is_recurring else "Hayır",
        ])
    return out.getvalue()
