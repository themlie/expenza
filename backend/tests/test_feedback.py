"""Model geri bildirimi (öneri kabul oranı) ve model karşılaştırma aracı."""
import csv

from app import models
from app.database import SessionLocal
from ml_training.evaluate import evaluate
from ml_training.feedback_report import Feedback, export_labels, load_feedback, summarize


def _stored(note):
    with SessionLocal() as db:
        return db.query(models.Transaction).filter(models.Transaction.note == note).one()


def test_suggestion_shown_in_the_app_is_stored(client, user):
    r = client.post(
        "/transactions",
        json={
            "amount": 40, "type": "expense", "category": "Ulaşım", "note": "taksi",
            "suggested_category": "Yemek", "suggestion_confidence": 0.62,
            "suggestion_model": "baseline-svm-v1",
        },
        headers=user["headers"],
    )
    assert r.status_code == 201
    tx = _stored("taksi")
    assert tx.suggested_category == models.CategoryEnum.yemek
    assert tx.category == models.CategoryEnum.ulasim
    assert tx.suggestion_confidence == 0.62 and tx.suggestion_model == "baseline-svm-v1"


def test_model_assigned_rows_are_not_counted_as_user_feedback(client, user, add_tx):
    client.post(
        "/transactions", json={"amount": 10, "type": "expense", "note": "migros market"},
        headers=user["headers"],
    )
    assert _stored("migros market").auto_categorized is True
    add_tx(user["headers"], category="Yemek", note="kahve",
           suggested_category="Yemek", suggestion_confidence=0.9, suggestion_model="m")

    with SessionLocal() as db:
        feedback = load_feedback(db)
    assert [(f.suggested, f.chosen) for f in feedback] == [("Yemek", "Yemek")]


def test_summary_metrics():
    items = [
        Feedback("Yemek", "Yemek", 0.95, "svm"),
        Feedback("Yemek", "Yemek", 0.85, "svm"),
        Feedback("Yemek", "Ulaşım", 0.60, "svm"),
        Feedback("Ulaşım", "Ulaşım", 0.30, "gemini"),
    ]
    s = summarize(items)
    assert s["n"] == 4 and s["accuracy"] == 0.75
    assert s["by_model"]["svm"] == {"n": 3, "accuracy": 2 / 3}
    assert [(b["range"], b["n"], b["accuracy"]) for b in s["by_confidence"]] == [
        ("0.0-0.5", 1, 1.0), ("0.5-0.8", 1, 0.0), ("0.8-1.0", 2, 1.0),
    ]
    assert s["per_category"]["Yemek"] == {"n": 2, "precision": 2 / 3, "recall": 1.0}
    assert s["per_category"]["Ulaşım"] == {"n": 2, "precision": 1.0, "recall": 0.5}


def test_summary_without_feedback():
    assert summarize([]) == {"n": 0}


def test_export_writes_user_labelled_notes(tmp_path, user, add_tx):
    add_tx(user["headers"], category="Sağlık", note="eczane")
    add_tx(user["headers"], category="Yemek", note="")  # boş not yazılmaz
    out = tmp_path / "feedback.csv"
    with SessionLocal() as db:
        assert export_labels(db, out) == 1
    with out.open(encoding="utf-8") as f:
        assert list(csv.reader(f)) == [["text", "label"], ["eczane", "Sağlık"]]


def test_evaluate_reports_accuracy_and_counts_missing_answers_as_wrong():
    answers = {"a": ("Yemek", 0.9), "b": (None, 0.0), "c": ("Ulaşım", 0.7)}
    result = evaluate("sahte", lambda t: answers[t], ["a", "b", "c"], ["Yemek", "Ulaşım", "Ulaşım"])
    assert result["n"] == 3
    assert result["accuracy"] == 2 / 3
    assert result["predictions"][1] == "(cevap yok)"
    assert result["ms_per_text"] >= 0
