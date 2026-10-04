"""Güvenlik olaylarının kaydı (giriş, kayıt, parola, hesap silme, istek sınırı).

Olaylar "expenza.security" logger'ına tek satır, anahtar=değer biçiminde yazılır:

    2026-10-04 12:00:00 WARNING event=login_failed ip=10.0.0.5 email=3f2a9c1b7d04

E-posta adresleri açık yazılmaz; küçük harfe çevrilmiş adresin SHA-256 özetinin ilk 12
karakteri yazılır. Böylece aynı adrese yapılan denemeler ilişkilendirilebilir ama log
dosyası kişisel veri içermez. Parola ve token hiçbir zaman loga yazılmaz.

SECURITY_LOG_FILE tanımlıysa kayıtlar ayrıca o dosyaya (5 MB'lık 5 dosya, dönüşümlü)
yazılır.
"""
import hashlib
import logging
import re
from logging.handlers import RotatingFileHandler
from typing import Optional

from fastapi import Request

from .config import settings

log = logging.getLogger("expenza.security")

_FORMAT = "%(asctime)s %(levelname)s %(message)s"
# Değerlerdeki boşluk ve kontrol karakterleri '_' olur: istemcinin gönderdiği bir
# değer satır sonu ekleyip sahte bir log satırı üretemez.
_UNSAFE = re.compile(r"[\s\x00-\x1f\x7f=]")


def configure() -> None:
    """Logger'a çıktı ekler. Birden çok kez çağrılırsa yeniden eklemez."""
    if getattr(log, "_expenza_configured", False):
        return
    log.setLevel(logging.INFO)
    if not logging.getLogger().handlers:
        # Uvicorn kök logger'a çıktı eklemiyor; yoksa INFO kayıtları kaybolur.
        stream = logging.StreamHandler()
        stream.setFormatter(logging.Formatter(_FORMAT))
        log.addHandler(stream)
    if settings.security_log_file:
        file = RotatingFileHandler(
            settings.security_log_file,
            maxBytes=5 * 1024 * 1024,
            backupCount=5,
            encoding="utf-8",
        )
        file.setFormatter(logging.Formatter(_FORMAT))
        log.addHandler(file)
    log._expenza_configured = True


def email_id(email: str) -> str:
    return hashlib.sha256(email.strip().lower().encode("utf-8")).hexdigest()[:12]


def _clean(value: object) -> str:
    return _UNSAFE.sub("_", str(value))[:200]


def event(
    name: str,
    request: Optional[Request] = None,
    *,
    level: int = logging.INFO,
    user_id: Optional[int] = None,
    email: Optional[str] = None,
    **fields: object,
) -> None:
    parts = [f"event={name}"]
    if request is not None:
        parts.append(f"ip={_clean(request.client.host if request.client else 'unknown')}")
    if user_id is not None:
        parts.append(f"user={user_id}")
    if email:
        parts.append(f"email={email_id(email)}")
    parts += [f"{k}={_clean(v)}" for k, v in fields.items() if v is not None]
    log.log(level, " ".join(parts))
