"""SQLAlchemy ORM modelleri — Expenza veri modeli."""
import enum
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import (
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    func,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base
from .money import ZERO, Money


class CategoryEnum(str, enum.Enum):
    """İşlem kategorileri; projedeki tek kaynak budur.

    Mobil uygulama listeyi GET /categories'ten alır. Kural tabanlı sınıflandırıcının
    sözlüğü ve eğitim verisi üreticisi testlerde bu listeye göre doğrulanır
    (tests/test_categories.py). Yeni kategori eklenirse model yeniden eğitilmelidir.
    """

    yemek = "Yemek"
    ulasim = "Ulaşım"
    faturalar = "Faturalar"
    eglence = "Eğlence"
    saglik = "Sağlık"
    egitim = "Eğitim"
    alisveris = "Alışveriş"
    diger = "Diğer"


# Bütçe kapsamı: her işlem kategorisi ve bütün giderleri kapsayan "Toplam". Toplam bir
# işlem kategorisi değildir, işlemlerde kullanılamaz. Liste CategoryEnum'dan türetilir.
BudgetCategory = enum.Enum(
    "BudgetCategory",
    {**{c.name: c.value for c in CategoryEnum}, "toplam": "Toplam"},
    type=str,
)
TOTAL_BUDGET = BudgetCategory.toplam


class TxType(str, enum.Enum):
    income = "income"
    expense = "expense"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(120), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    # Sohbet asistanı için verilerinin Google Gemini'ye gönderilmesine onay verdiği an
    # (UTC). Boşsa onay yok ya da geri çekilmiş.
    ai_consent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    # Erişim token'larındaki "ver" alanıyla karşılaştırılır. Parola değişince artar ve o
    # ana kadar verilmiş bütün erişim token'ları geçersiz olur. Kayıtta rastgele başlar;
    # böylece silinip aynı e-postayla yeniden açılan hesap eski token'ları kabul etmez.
    token_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    # Bütçe, anomali, hedef ve tekrarlayan ödeme uyarıları (Profil > Bildirimler).
    alerts_enabled: Mapped[bool] = mapped_column(default=True, server_default=true())

    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    budgets: Mapped[list["Budget"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class RecurringSeries(Base):
    """Her ay aynı gün tekrarlanan işlemin şablonu (maaş, kira, abonelik gibi).

    Seriye ait işlemler app/recurring.py tarafından üretilir. last_generated_on en son
    üretilen ayın tarihidir; silinen bir kopya bu yüzden yeniden üretilmez.
    """

    __tablename__ = "recurring_series"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    amount: Mapped[Decimal] = mapped_column(Money)
    type: Mapped[TxType] = mapped_column(Enum(TxType))
    category: Mapped[CategoryEnum] = mapped_column(Enum(CategoryEnum))
    note: Mapped[str] = mapped_column(String(500), default="")
    # Kısa aylarda ayın son gününe kayar; sonraki uzun ayda yine bu güne döner.
    day_of_month: Mapped[int] = mapped_column(Integer)
    start_on: Mapped[date] = mapped_column(Date)
    last_generated_on: Mapped[date] = mapped_column(Date)
    active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Transaction(Base):
    __tablename__ = "transactions"
    # Aynı seriden aynı güne iki kayıt düşemez (eşzamanlı üretimde çift kaydı engeller).
    __table_args__ = (
        UniqueConstraint("series_id", "occurred_on", name="uq_transactions_series_day"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    amount: Mapped[Decimal] = mapped_column(Money)
    type: Mapped[TxType] = mapped_column(Enum(TxType), default=TxType.expense)
    category: Mapped[CategoryEnum] = mapped_column(
        Enum(CategoryEnum), default=CategoryEnum.diger
    )
    # Modelin kategoriyi otomatik atayıp atamadığını ve güven skorunu izlemek için.
    auto_categorized: Mapped[bool] = mapped_column(default=False)
    # Kayıt anında kullanıcıya gösterilen model önerisi. Seçilen kategoriyle
    # karşılaştırılarak modelin gerçek kullanımdaki doğruluğu ölçülür
    # (ml_training/feedback_report.py). Öneri gösterilmediyse boştur.
    suggested_category: Mapped[Optional[CategoryEnum]] = mapped_column(
        Enum(CategoryEnum), nullable=True
    )
    suggestion_confidence: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    suggestion_model: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    # Aktif bir tekrarlayan seriye ait mi? Seri durdurulunca False yapılır.
    is_recurring: Mapped[bool] = mapped_column(default=False)
    series_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("recurring_series.id", name="fk_transactions_series_id"),
        nullable=True,
        index=True,
    )
    note: Mapped[str] = mapped_column(String(500), default="")
    occurred_on: Mapped[date] = mapped_column(Date, default=date.today)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="transactions")
    series: Mapped[Optional["RecurringSeries"]] = relationship()


class Budget(Base):
    __tablename__ = "budgets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    category: Mapped[BudgetCategory] = mapped_column(Enum(BudgetCategory))
    monthly_limit: Mapped[Decimal] = mapped_column(Money)

    user: Mapped["User"] = relationship(back_populates="budgets")


class Goal(Base):
    """Tasarruf hedefi (örn. 'Tatil için 10.000₺'). Raporun çekirdek özelliği."""

    __tablename__ = "goals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(120))
    target_amount: Mapped[Decimal] = mapped_column(Money)
    current_amount: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    deadline: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class RefreshToken(Base):
    """Uzun ömürlü yenileme token'ı. Değerin kendisi değil SHA-256 özeti saklanır.

    Her kullanımda iptal edilip aynı ailede yenisi verilir (rotation). İptal edilmiş bir
    token tekrar gelirse token çalınmış sayılır ve bütün aile iptal edilir.
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    family_id: Mapped[str] = mapped_column(String(32), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class DismissedAlert(Base):
    """Kullanıcının kapattığı uyarılar. Uyarı kimlikleri ay bilgisini içerdiği için
    aynı uyarı sonraki ay yeniden gösterilir."""

    __tablename__ = "dismissed_alerts"
    __table_args__ = (
        UniqueConstraint("user_id", "alert_id", name="uq_dismissed_alerts_user_alert"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    alert_id: Mapped[str] = mapped_column(String(120))
    dismissed_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
