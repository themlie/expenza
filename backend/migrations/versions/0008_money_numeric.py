"""Para sütunları FLOAT yerine NUMERIC(12, 2)

Tutarlar uygulamada artık Decimal olarak hesaplanıyor (app/money.py). Var olan
değerler kuruşa yuvarlanır. SQLite'ta tablo yeniden oluşturulur (batch).

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-04

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "0008"
down_revision: Union[str, Sequence[str], None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

COLUMNS = {
    "transactions": ["amount"],
    "recurring_series": ["amount"],
    "budgets": ["monthly_limit"],
    "goals": ["target_amount", "current_amount"],
}


def upgrade() -> None:
    for table, columns in COLUMNS.items():
        for column in columns:
            op.execute(f"UPDATE {table} SET {column} = ROUND({column}, 2)")
        with op.batch_alter_table(table) as batch:
            for column in columns:
                batch.alter_column(
                    column,
                    existing_type=sa.Float(),
                    type_=sa.Numeric(12, 2),
                    existing_nullable=False,
                )


def downgrade() -> None:
    for table, columns in COLUMNS.items():
        with op.batch_alter_table(table) as batch:
            for column in columns:
                batch.alter_column(
                    column,
                    existing_type=sa.Numeric(12, 2),
                    type_=sa.Float(),
                    existing_nullable=False,
                )
