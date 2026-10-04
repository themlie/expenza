"""Güvenlik olaylarının loglanması (SEC-21)."""
import logging

import pytest

from app import audit


@pytest.fixture
def events(caplog):
    caplog.set_level(logging.INFO, logger="expenza.security")

    def _events():
        return [r.getMessage() for r in caplog.records if r.name == "expenza.security"]

    return _events


def _names(lines):
    return [line.split()[0].removeprefix("event=") for line in lines]


def test_login_success_and_failure_are_logged_without_secrets(client, user, events):
    client.post("/auth/login", data={"username": user["email"], "password": "yanlis-parola"})
    client.post("/auth/login", data={"username": "yok@example.com", "password": "x" * 8})
    client.post("/auth/login", data={"username": user["email"], "password": user["password"]})

    lines = events()
    assert _names(lines) == ["login_failed", "login_failed", "login"]
    assert "reason=bad_password" in lines[0]
    assert "reason=unknown_email" in lines[1]
    assert f"email={audit.email_id(user['email'])}" in lines[0]
    joined = "\n".join(lines)
    # Açık e-posta, parola ve token loga yazılmaz.
    for secret in (user["email"], "yanlis-parola", user["password"], user["refresh"]):
        assert secret not in joined


def test_lockout_and_rate_limit_are_warnings(client, user, caplog, events):
    for _ in range(6):
        client.post("/auth/login", data={"username": user["email"], "password": "yanlis-parola"})
    assert "login_locked" in _names(events())
    assert any(
        r.levelno == logging.WARNING and "login_locked" in r.getMessage()
        for r in caplog.records
    )


def test_account_events(client, make_user, events):
    u = make_user()
    h = u["headers"]
    assert client.post(
        "/auth/change-password",
        json={"current_password": "yanlis-parola", "new_password": "yeniparola1"},
        headers=h,
    ).status_code == 400
    r = client.post(
        "/auth/change-password",
        json={"current_password": u["password"], "new_password": "yeniparola1"},
        headers=h,
    )
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    client.request("DELETE", "/auth/me", json={"password": "yeniparola1"}, headers=h)

    names = _names(events())
    assert names[:2] == ["register", "login"]
    assert names[2:] == ["reauth_failed", "password_changed", "account_deleted"]


def test_refresh_token_reuse_is_logged(client, user, events):
    assert client.post("/auth/refresh", json={"refresh_token": user["refresh"]}).status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": user["refresh"]}).status_code == 401
    assert "refresh_token_reused" in _names(events())


def test_values_cannot_forge_log_lines(events):
    audit.event("test", reason="kötü\nevent=login user=1")
    (line,) = events()
    assert "\n" not in line
    assert line.count("event=") == 1
