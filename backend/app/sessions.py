"""Oturum yenileme token'ları (refresh token).

Erişim token'ı 30 dakikada dolar. İstemci elindeki yenileme token'ıyla /auth/refresh'e
gelir ve yeni bir çift alır; eski yenileme token'ı o anda iptal edilir (rotation).
İptal edilmiş bir token yeniden kullanılırsa token'ın çalındığı varsayılır ve aynı
girişten türeyen bütün token'lar (aile) iptal edilir. Veritabanında token'ın kendisi
değil SHA-256 özeti tutulur; veritabanı sızsa bile token'lar kullanılamaz.
"""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from . import auth, models, schemas

REFRESH_TOKEN_EXPIRE_DAYS = 30


def _now() -> datetime:
    # Veritabanı sütunları saat dilimi bilgisi tutmuyor; UTC olarak saklanır.
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _hash(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _invalid() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Oturum geçersiz. Lütfen tekrar giriş yap.",
    )


def issue_tokens(
    db: Session, user: models.User, family_id: Optional[str] = None
) -> schemas.Token:
    """Erişim ve yenileme token'ı üretir; commit etmez."""
    raw = secrets.token_urlsafe(32)
    db.add(
        models.RefreshToken(
            user_id=user.id,
            token_hash=_hash(raw),
            family_id=family_id or uuid.uuid4().hex,
            expires_at=_now() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
        )
    )
    return schemas.Token(
        access_token=auth.create_access_token(user),
        refresh_token=raw,
        expires_in=auth.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


def rotate(db: Session, raw: str) -> schemas.Token:
    """Yenileme token'ını yenisiyle değiştirir. Geçersizse 401 döner."""
    token = (
        db.query(models.RefreshToken)
        .filter(models.RefreshToken.token_hash == _hash(raw))
        .first()
    )
    if token is None:
        raise _invalid()
    if token.revoked_at is not None:
        # Daha önce kullanılmış token tekrar geldi: çalınmış olabilir.
        _revoke_family(db, token.family_id)
        db.commit()
        raise _invalid()
    if token.expires_at <= _now():
        raise _invalid()
    user = db.get(models.User, token.user_id)
    if user is None:
        raise _invalid()
    token.revoked_at = _now()
    pair = issue_tokens(db, user, family_id=token.family_id)
    db.commit()
    return pair


def revoke(db: Session, raw: str) -> None:
    """Çıkış: token'ın ailesini iptal eder. Bilinmeyen token sessizce yok sayılır."""
    token = (
        db.query(models.RefreshToken)
        .filter(models.RefreshToken.token_hash == _hash(raw))
        .first()
    )
    if token is not None:
        _revoke_family(db, token.family_id)
        db.commit()


def revoke_all(db: Session, user_id: int) -> None:
    """Kullanıcının bütün oturumlarını iptal eder (parola değişikliği); commit etmez."""
    db.query(models.RefreshToken).filter(
        models.RefreshToken.user_id == user_id,
        models.RefreshToken.revoked_at.is_(None),
    ).update({models.RefreshToken.revoked_at: _now()}, synchronize_session=False)


def _revoke_family(db: Session, family_id: str) -> None:
    db.query(models.RefreshToken).filter(
        models.RefreshToken.family_id == family_id,
        models.RefreshToken.revoked_at.is_(None),
    ).update({models.RefreshToken.revoked_at: _now()}, synchronize_session=False)


def purge_expired(db: Session) -> int:
    """Süresi dolalı bir haftayı geçmiş token'ları siler (yeniden kullanım tespiti için
    iptal edilenler süreleri dolana kadar tutulur)."""
    deleted = (
        db.query(models.RefreshToken)
        .filter(models.RefreshToken.expires_at < _now() - timedelta(days=7))
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted
