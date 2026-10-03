""""Toplam" işlem kategorisi olmaktan çıkarıldı (yalnızca bütçe kapsamı)

Önceki sürümde API "Toplam"ı işlem kategorisi olarak da kabul ediyordu. Böyle kayıtlar
"Diğer"e taşınır; kayıt anındaki öneri "Toplam" ise öneri bilgisi silinir. Bütçelerdeki
"Toplam" olduğu gibi kalır. Sütun tipleri değişmez (SQLite'ta enum metin olarak tutulur).

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-03

"""
from typing import Sequence, Union

from alembic import op


revision: str = "0007"
down_revision: Union[str, Sequence[str], None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enum sütunları değerin adını saklar ("Toplam" değil "toplam").
    op.execute("UPDATE transactions SET category = 'diger' WHERE category = 'toplam'")
    op.execute("UPDATE recurring_series SET category = 'diger' WHERE category = 'toplam'")
    op.execute(
        "UPDATE transactions SET suggested_category = NULL, suggestion_confidence = NULL, "
        "suggestion_model = NULL WHERE suggested_category = 'toplam'"
    )


def downgrade() -> None:
    # Hangi kaydın eskiden "Toplam" olduğu bilinmediği için geri alınacak bir şey yok.
    pass
