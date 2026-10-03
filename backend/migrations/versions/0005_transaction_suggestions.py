"""Kayıt anında gösterilen kategori önerisi (model geri bildirimi)

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-03

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0005"
down_revision: Union[str, Sequence[str], None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

CATEGORY = sa.Enum(
    "yemek", "ulasim", "faturalar", "eglence", "saglik", "egitim", "alisveris",
    "diger", "toplam",
    name="categoryenum",
)


def upgrade() -> None:
    with op.batch_alter_table("transactions", schema=None) as batch_op:
        batch_op.add_column(sa.Column("suggested_category", CATEGORY, nullable=True))
        batch_op.add_column(sa.Column("suggestion_confidence", sa.Float(), nullable=True))
        batch_op.add_column(sa.Column("suggestion_model", sa.String(length=40), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("transactions", schema=None) as batch_op:
        batch_op.drop_column("suggestion_model")
        batch_op.drop_column("suggestion_confidence")
        batch_op.drop_column("suggested_category")
