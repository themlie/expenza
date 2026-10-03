"""İstemcinin sabit listeleri kendisi tutmaması için ortak bilgiler."""
from fastapi import APIRouter

from ..models import CategoryEnum

router = APIRouter(tags=["meta"])


@router.get("/categories", response_model=list[str])
def categories():
    """İşlem kategorileri. Bütçelerde bunlara ek olarak "Toplam" kullanılabilir."""
    return [c.value for c in CategoryEnum]
