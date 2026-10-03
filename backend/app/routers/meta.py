"""İstemcinin sabit listeleri kendisi tutmaması için ortak bilgiler."""
from fastapi import APIRouter

from ..models import CategoryEnum

router = APIRouter(tags=["meta"])


@router.get("/categories", response_model=list[str])
def categories():
    """İşlem kategorileri. "Toplam" kategori değil, yalnızca toplam bütçe için kullanılır."""
    return [c.value for c in CategoryEnum if c != CategoryEnum.toplam]
