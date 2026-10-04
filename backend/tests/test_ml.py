"""Kategori önerisi ucu ve yerel model."""
from app.ml import categorizer
from app.models import CategoryEnum


def test_categorize_returns_known_category(client, user):
    r = client.post("/ml/categorize", json={"text": "uber ile eve döndüm"}, headers=user["headers"])
    assert r.status_code == 200
    body = r.json()
    assert body["category"] == "Ulaşım"
    assert 0 <= body["confidence"] <= 1
    # Gemini testlerde kapalı; cevap yerel modelden gelmeli.
    assert body["model"] in {"baseline-svm-v1", "rule-stub-v1"}


def test_categorize_rejects_long_text(client, user):
    r = client.post("/ml/categorize", json={"text": "x" * 501}, headers=user["headers"])
    assert r.status_code == 422


def test_trained_model_is_loaded():
    # Model scikit-learn sürümüyle uyumsuz olursa kod sessizce kural tabanlı yedeğe düşer.
    assert categorizer._active.name == "baseline-svm-v1"


def test_rule_stub_fallback():
    stub = categorizer.RuleBasedCategorizer()
    assert stub.predict("eczaneden ilaç")[0] == CategoryEnum.saglik
    assert stub.predict("")[0] == CategoryEnum.diger


def test_committed_hash_matches_model():
    # Model yeniden eğitilip .sha256 dosyası commit'lenmezse burası yakalar.
    categorizer.verify_model(categorizer.MODEL_PATH)


def _copy_model(tmp_path):
    model = tmp_path / "categorizer.joblib"
    model.write_bytes(categorizer.MODEL_PATH.read_bytes())
    return model


def test_tampered_model_is_not_loaded(tmp_path):
    model = _copy_model(tmp_path)
    categorizer.write_hash(model)
    with open(model, "ab") as f:
        f.write(b"\0")
    assert isinstance(categorizer._load_active(model), categorizer.RuleBasedCategorizer)


def test_model_without_hash_is_not_loaded(tmp_path):
    model = _copy_model(tmp_path)
    assert isinstance(categorizer._load_active(model), categorizer.RuleBasedCategorizer)


def test_hash_from_settings_overrides_sidecar(tmp_path, monkeypatch):
    model = _copy_model(tmp_path)
    digest = categorizer.file_sha256(model)
    monkeypatch.setattr(categorizer.settings, "model_sha256", digest.upper())
    assert isinstance(categorizer._load_active(model), categorizer.MLCategorizer)
    monkeypatch.setattr(categorizer.settings, "model_sha256", "0" * 64)
    assert isinstance(categorizer._load_active(model), categorizer.RuleBasedCategorizer)
