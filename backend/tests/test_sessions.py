"""Oturum yenileme (refresh token), çıkış ve oturum sürümü."""
from datetime import datetime, timedelta, timezone

import jwt

from app import models
from app.auth import ALGORITHM, SECRET_KEY
from app.database import SessionLocal


def _bearer(token):
    return {"Authorization": f"Bearer {token}"}


def test_login_returns_refresh_token_and_short_lived_access(client, user):
    r = client.post("/auth/login", data={"username": user["email"], "password": "parola123"})
    body = r.json()
    assert body["refresh_token"] and body["expires_in"] == 30 * 60
    claims = jwt.decode(body["access_token"], SECRET_KEY, algorithms=[ALGORITHM])
    assert claims["exp"] - claims["iat"] == 30 * 60


def test_refresh_rotates_and_new_access_token_works(client, user):
    r = client.post("/auth/refresh", json={"refresh_token": user["refresh"]})
    assert r.status_code == 200
    pair = r.json()
    assert pair["refresh_token"] != user["refresh"]
    assert client.get("/auth/me", headers=_bearer(pair["access_token"])).status_code == 200


def test_reused_refresh_token_revokes_the_whole_session(client, user):
    first = client.post("/auth/refresh", json={"refresh_token": user["refresh"]}).json()
    # Eski token ikinci kez geldi: çalınmış sayılır.
    r = client.post("/auth/refresh", json={"refresh_token": user["refresh"]})
    assert r.status_code == 401
    # Aynı girişten türeyen yeni token da artık geçersiz.
    r = client.post("/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert r.status_code == 401


def test_reuse_does_not_affect_other_devices(client, user):
    other = client.post(
        "/auth/login", data={"username": user["email"], "password": "parola123"}
    ).json()
    client.post("/auth/refresh", json={"refresh_token": user["refresh"]})
    client.post("/auth/refresh", json={"refresh_token": user["refresh"]})
    r = client.post("/auth/refresh", json={"refresh_token": other["refresh_token"]})
    assert r.status_code == 200


def test_unknown_and_expired_refresh_tokens_are_rejected(client, user):
    assert client.post("/auth/refresh", json={"refresh_token": "uydurma"}).status_code == 401
    with SessionLocal() as db:
        db.query(models.RefreshToken).update(
            {models.RefreshToken.expires_at: datetime(2000, 1, 1)}
        )
        db.commit()
    assert client.post("/auth/refresh", json={"refresh_token": user["refresh"]}).status_code == 401


def test_refresh_tokens_are_stored_hashed(client, user):
    with SessionLocal() as db:
        stored = [t for (t,) in db.query(models.RefreshToken.token_hash)]
    assert stored and user["refresh"] not in stored
    assert all(len(t) == 64 for t in stored)


def test_logout_revokes_refresh_token(client, user):
    assert client.post("/auth/logout", json={"refresh_token": user["refresh"]}).status_code == 204
    assert client.post("/auth/refresh", json={"refresh_token": user["refresh"]}).status_code == 401
    # Bilinmeyen token ile çıkış hata vermez (bilgi sızdırmaz).
    assert client.post("/auth/logout", json={"refresh_token": "yok"}).status_code == 204


def test_access_token_without_session_version_is_rejected(client, user):
    token = jwt.encode(
        {"sub": user["email"], "exp": datetime.now(timezone.utc) + timedelta(minutes=5)},
        SECRET_KEY,
        algorithm=ALGORITHM,
    )
    assert client.get("/auth/me", headers=_bearer(token)).status_code == 401


def test_old_token_does_not_work_for_recreated_account(client, user):
    old = user["headers"]
    r = client.request("DELETE", "/auth/me", json={"password": "parola123"}, headers=old)
    assert r.status_code == 204
    # Aynı e-postayla yeni hesap: eski hesabın token'ı kabul edilmemeli.
    client.post("/auth/register", json={"email": user["email"], "password": "parola123"})
    assert client.get("/auth/me", headers=old).status_code == 401


def test_refresh_is_rate_limited(client, user):
    codes = {
        client.post("/auth/refresh", json={"refresh_token": "x"}).status_code
        for _ in range(61)
    }
    assert 429 in codes
