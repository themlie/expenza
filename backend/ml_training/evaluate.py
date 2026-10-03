"""Kategori modellerini GERÇEK doğrulama setinde karşılaştır (dürüst metrik).

validation_set.csv eğitimde HİÇ kullanılmamış, gerçek tarzda yazılmış örnekler içerir.
Varsayılan olarak üründeki TF-IDF + SVM modeli ile anahtar kelime kuralları ölçülür;
--gemini ile aynı set Gemini'ye de sorulur (GEMINI_API_KEY gerekir; notlar Google'a gider).

Her model için doğruluk, makro F1 ve metin başına ortalama tahmin süresi yazılır. Üründeki
model için ayrıca kategori bazında rapor, karışıklık matrisi ve yanlış tahminler (hata
analizi) yazılır. --json ile sonuçlar tez tabloları için dosyaya kaydedilir.

Çalıştırma (backend klasöründe):
    python -m ml_training.evaluate
    python -m ml_training.evaluate --gemini --json ml_training/results.json
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Callable, Optional

import joblib
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)

HERE = os.path.dirname(__file__)
VAL_PATH = os.path.join(HERE, "validation_set.csv")
MODEL_PATH = os.path.join(HERE, "..", "app", "ml", "model", "categorizer.joblib")

Predictor = Callable[[str], tuple[Optional[str], float]]


def evaluate(name: str, predict: Predictor, texts: list[str], labels: list[str]) -> dict:
    """Modeli metinler üzerinde tek tek çalıştırır (gerçek kullanımdaki gibi)."""
    predictions, confidences = [], []
    start = time.perf_counter()
    for text in texts:
        category, confidence = predict(text)
        # Cevap alınamayan tahmin (ör. API hatası) yanlış sayılır.
        predictions.append(category or "(cevap yok)")
        confidences.append(confidence)
    elapsed = time.perf_counter() - start
    return {
        "model": name,
        "n": len(texts),
        "accuracy": accuracy_score(labels, predictions),
        "macro_f1": f1_score(labels, predictions, average="macro", zero_division=0),
        "ms_per_text": elapsed / len(texts) * 1000,
        "predictions": predictions,
        "confidences": confidences,
    }


def svm_predictor(model) -> Predictor:
    classes = list(model.classes_)

    def predict(text: str):
        proba = model.predict_proba([text])[0]
        return classes[proba.argmax()], float(proba.max())

    return predict


def rules_predictor() -> Predictor:
    from app.ml.categorizer import RuleBasedCategorizer

    rules = RuleBasedCategorizer()

    def predict(text: str):
        category, confidence = rules.predict(text)
        return category.value, confidence

    return predict


def gemini_predictor() -> Optional[Predictor]:
    from app import llm
    from app.ml.categorizer import GeminiCategorizer

    if not llm.enabled():
        return None
    gemini = GeminiCategorizer()

    def predict(text: str):
        category, confidence = gemini.predict(text)
        return (category.value if category else None), confidence

    return predict


def _error_analysis(result: dict, texts, labels, classes) -> None:
    print("\nKategori bazında rapor:")
    print(classification_report(labels, result["predictions"], zero_division=0))
    print("Karışıklık matrisi (satır=gerçek, sütun=tahmin):")
    cm = confusion_matrix(labels, result["predictions"], labels=classes)
    print(pd.DataFrame(cm, index=classes, columns=classes).to_string())
    print("\n" + "-" * 60)
    print("YANLIŞ TAHMİNLER (hata analizi):")
    errors = 0
    for text, truth, guess, conf in zip(texts, labels, result["predictions"], result["confidences"]):
        if truth != guess:
            errors += 1
            print(f"  '{text}'  →  tahmin: {guess} (%{conf * 100:.0f})  | doğru: {truth}")
    if errors == 0:
        print("  (Hiç hata yok)")
    print(f"\nToplam {errors}/{len(texts)} yanlış.")


def main() -> None:
    # Windows terminali cp1254 olabilir; Türkçe/ok karakterleri için UTF-8'e geç.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    parser = argparse.ArgumentParser(description="Kategori modellerini karşılaştır")
    parser.add_argument("--gemini", action="store_true", help="Gemini'yi de ölç (GEMINI_API_KEY gerekir)")
    parser.add_argument("--json", type=Path, help="sonuçları JSON dosyasına yaz")
    args = parser.parse_args()

    df = pd.read_csv(VAL_PATH).dropna(subset=["text", "label"])
    texts, labels = df["text"].tolist(), df["label"].tolist()
    model = joblib.load(MODEL_PATH)

    results = [
        evaluate("TF-IDF + SVM (üründeki)", svm_predictor(model), texts, labels),
        evaluate("Anahtar kelime kuralları", rules_predictor(), texts, labels),
    ]
    if args.gemini:
        predictor = gemini_predictor()
        if predictor is None:
            print("GEMINI_API_KEY tanımlı değil; Gemini atlandı.\n")
        else:
            results.append(evaluate("Gemini (sıfır örnekli)", predictor, texts, labels))

    print("=" * 72)
    print(f"GERÇEK DOĞRULAMA SETİ — {len(texts)} örnek")
    print("=" * 72)
    print(f"{'Model':28s} {'Doğruluk':>9s} {'Makro F1':>9s} {'ms/metin':>9s}")
    for r in results:
        print(f"{r['model']:28s} {r['accuracy']:9.3f} {r['macro_f1']:9.3f} {r['ms_per_text']:9.2f}")
    print(f"\nÜrün modelinin dosya boyutu: {os.path.getsize(MODEL_PATH) / 1024:.0f} KB")

    _error_analysis(results[0], texts, labels, list(model.classes_))

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        summary = [
            {k: v for k, v in r.items() if k not in ("predictions", "confidences")}
            for r in results
        ]
        args.json.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nSonuçlar yazıldı -> {args.json}")


if __name__ == "__main__":
    main()
