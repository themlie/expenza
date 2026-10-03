"""Model geri bildirimi: kullanıcılar kategori önerisini ne sıklıkla kabul ediyor?

Kayıt anında gösterilen öneri (suggested_category) kullanıcının seçtiği kategoriyle
karşılaştırılır. Model tarafından kullanıcıya sorulmadan atanan kayıtlar
(auto_categorized) dışarıda bırakılır; onlar kullanıcıca doğrulanmamıştır.

Çalıştırma (backend klasöründe):
    python -m ml_training.feedback_report
    python -m ml_training.feedback_report --export ml_training/data/feedback.csv

--export, kullanıcıların seçtiği kategorilerle not metinlerini (text,label) CSV olarak
yazar; doğrulama setini büyütmek ya da yeniden eğitim için kullanılabilir. Dosya kişisel
veri içerir; ml_training/data/ klasörü git'e eklenmez.
"""
import argparse
import csv
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# Güven aralıkları: model "eminim" dediğinde gerçekten ne kadar doğru (kalibrasyon)?
BUCKETS = [(0.0, 0.5), (0.5, 0.8), (0.8, 1.0)]


@dataclass
class Feedback:
    suggested: str
    chosen: str
    confidence: Optional[float]
    model: Optional[str]


def summarize(items: list[Feedback]) -> dict:
    """Kabul oranı, model ve güven aralığı bazında doğruluk, kategori bazında P/R."""
    if not items:
        return {"n": 0}

    def accuracy(rows):
        return sum(f.suggested == f.chosen for f in rows) / len(rows)

    by_model = defaultdict(list)
    for f in items:
        by_model[f.model or "bilinmiyor"].append(f)

    buckets = []
    for low, high in BUCKETS:
        rows = [
            f for f in items
            if f.confidence is not None
            and low <= f.confidence and (f.confidence < high or high == 1.0)
        ]
        if rows:
            buckets.append({"range": f"{low:.1f}-{high:.1f}", "n": len(rows), "accuracy": accuracy(rows)})

    confusion = defaultdict(Counter)  # confusion[seçilen][önerilen]
    for f in items:
        confusion[f.chosen][f.suggested] += 1
    categories = sorted({f.chosen for f in items} | {f.suggested for f in items})
    per_category = {}
    for cat in categories:
        hit = confusion[cat][cat]
        suggested_as_cat = sum(confusion[c][cat] for c in confusion)
        actual = sum(confusion[cat].values())
        per_category[cat] = {
            "n": actual,
            "precision": hit / suggested_as_cat if suggested_as_cat else 0.0,
            "recall": hit / actual if actual else 0.0,
        }

    return {
        "n": len(items),
        "accuracy": accuracy(items),
        "by_model": {m: {"n": len(r), "accuracy": accuracy(r)} for m, r in by_model.items()},
        "by_confidence": buckets,
        "per_category": per_category,
        "confusion": {c: dict(v) for c, v in confusion.items()},
    }


def load_feedback(db) -> list[Feedback]:
    from app.models import Transaction, TxType

    rows = db.query(Transaction).filter(
        Transaction.suggested_category.isnot(None),
        Transaction.auto_categorized.is_(False),
        Transaction.type == TxType.expense,
    )
    return [
        Feedback(t.suggested_category.value, t.category.value, t.suggestion_confidence, t.suggestion_model)
        for t in rows
    ]


def export_labels(db, path: Path) -> int:
    """Kullanıcının kendi seçtiği kategorilerle notları text,label olarak yazar."""
    from app.models import Transaction, TxType

    rows = db.query(Transaction.note, Transaction.category).filter(
        Transaction.type == TxType.expense,
        Transaction.auto_categorized.is_(False),
        Transaction.note != "",
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["text", "label"])
        for note, category in rows:
            writer.writerow([note, category.value])
            count += 1
    return count


def _print(report: dict) -> None:
    if report["n"] == 0:
        print("Henüz kullanıcıca doğrulanmış öneri yok.")
        return
    print(f"Doğrulanmış öneri: {report['n']}   Kabul oranı (doğruluk): {report['accuracy']:.3f}")
    print("\nModel bazında:")
    for model, r in report["by_model"].items():
        print(f"  {model:25s} n={r['n']:<5d} doğruluk={r['accuracy']:.3f}")
    print("\nGüven aralığına göre (kalibrasyon):")
    for b in report["by_confidence"]:
        print(f"  {b['range']:9s} n={b['n']:<5d} doğruluk={b['accuracy']:.3f}")
    print("\nKategori bazında:")
    for cat, r in report["per_category"].items():
        print(f"  {cat:10s} n={r['n']:<5d} precision={r['precision']:.3f} recall={r['recall']:.3f}")


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--export", type=Path, help="text,label CSV dosyası yaz")
    args = parser.parse_args()

    from app.database import SessionLocal

    with SessionLocal() as db:
        _print(summarize(load_feedback(db)))
        if args.export:
            count = export_labels(db, args.export)
            print(f"\n{count} etiketli not yazıldı -> {args.export}")


if __name__ == "__main__":
    main()
