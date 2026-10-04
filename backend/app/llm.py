"""Google Gemini API istemcisi.

Sohbet asistanı ve (ayarla açılırsa) kategori sınıflandırıcı bu modülü kullanır.
API anahtarı URL'de değil x-goog-api-key başlığında gönderilir; hata ayrıntıları
istemciye değil sunucu loguna yazılır.
"""
import logging
from typing import Optional, Sequence

import httpx

from .config import settings

log = logging.getLogger(__name__)

API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class GeminiError(Exception):
    """Gemini'den kullanılabilir bir cevap alınamadı."""


def enabled() -> bool:
    return bool(settings.gemini_api_key)


def generate(
    user_text: str,
    *,
    model: str,
    system: Optional[str] = None,
    history: Sequence[tuple[str, str]] = (),
    timeout: float = 30.0,
) -> str:
    """İstek gönderir ve modelin metin cevabını döndürür.

    Kullanıcı metni ile sistem talimatı ayrı alanlarda gider; kullanıcı metni talimatın
    içine yapıştırılmaz.
    """
    if not enabled():
        raise GeminiError("GEMINI_API_KEY tanımlı değil")

    # history: önceki turlar, (rol, metin) çiftleri; rol "user" ya da "model".
    contents = [{"role": role, "parts": [{"text": text}]} for role, text in history]
    contents.append({"role": "user", "parts": [{"text": user_text}]})
    body: dict = {"contents": contents}
    if system:
        body["systemInstruction"] = {"parts": [{"text": system}]}

    try:
        response = httpx.post(
            API_URL.format(model=model),
            json=body,
            headers={"x-goog-api-key": settings.gemini_api_key},
            timeout=timeout,
        )
    except httpx.HTTPError as exc:
        log.warning("Gemini isteği başarısız: %s", type(exc).__name__)
        raise GeminiError("bağlantı hatası") from exc

    if response.status_code != 200:
        log.warning("Gemini %s döndürdü: %s", response.status_code, response.text[:500])
        raise GeminiError(f"HTTP {response.status_code}")

    try:
        return response.json()["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        log.warning("Gemini cevabı beklenen biçimde değil")
        raise GeminiError("beklenmeyen cevap") from exc
