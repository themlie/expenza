"""CSV dışa aktarma (OZ-07)."""
import csv
import io


def _rows(r):
    assert r.text.startswith("﻿")
    return list(csv.reader(io.StringIO(r.text.lstrip("﻿")), delimiter=";"))


def test_export_csv_for_a_month(client, user, add_tx, make_user):
    h = user["headers"]
    add_tx(h, amount=1234.5, note="market; ekmek", occurred_on="2026-03-05")
    add_tx(h, amount=5000, type="income", category="Diğer", note="maaş", occurred_on="2026-03-01")
    add_tx(h, amount=10, note="başka ay", occurred_on="2026-02-10")
    add_tx(make_user()["headers"], amount=99, note="başkasının", occurred_on="2026-03-02")

    r = client.get("/transactions/export", params={"month": "2026-03"}, headers=h)
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    assert 'filename="expenza-islemler-2026-03.csv"' in r.headers["content-disposition"]

    rows = _rows(r)
    assert rows[0] == ["Tarih", "Tür", "Kategori", "Tutar (TRY)", "Not", "Tekrarlayan"]
    assert rows[1] == ["2026-03-01", "Gelir", "Diğer", "5000,00", "maaş", "Hayır"]
    assert rows[2] == ["2026-03-05", "Gider", "Yemek", "1234,50", "market; ekmek", "Hayır"]
    assert len(rows) == 3

    all_rows = _rows(client.get("/transactions/export", headers=h))
    assert len(all_rows) == 4


def test_export_neutralizes_formulas(client, user, add_tx):
    add_tx(user["headers"], note="=HYPERLINK(\"http://kotu\")")
    rows = _rows(client.get("/transactions/export", headers=user["headers"]))
    assert rows[1][4].startswith("'=")


def test_export_requires_login_and_valid_month(client, user):
    assert client.get("/transactions/export").status_code == 401
    r = client.get("/transactions/export", params={"month": "2026-13"}, headers=user["headers"])
    assert r.status_code == 400
