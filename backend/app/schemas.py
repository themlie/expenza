"""Pydantic şemaları — API istek/yanıt sözleşmeleri."""
from datetime import date, datetime, timedelta
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

from .models import BudgetCategory, CategoryEnum, TxType
from .money import MoneyIn


# ---- Auth ----
def _password_policy(value: str) -> str:
    # Mesajlar mobil uygulamada olduğu gibi gösterilir.
    if len(value) < 8:
        raise ValueError("Parola en az 8 karakter olmalı")
    if not any(c.isalpha() for c in value) or not any(c.isdigit() for c in value):
        raise ValueError("Parola en az bir harf ve bir rakam içermeli")
    return value


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(max_length=128)
    display_name: str = Field(default="", max_length=120)

    _check_password = field_validator("password")(_password_policy)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    email: EmailStr
    display_name: str
    created_at: datetime
    alerts_enabled: bool = True
    ai_consent_at: Optional[datetime] = None  # boşsa sohbet asistanına onay yok


class UserUpdate(BaseModel):
    # Gönderilmeyen alan değişmez.
    display_name: Optional[str] = Field(default=None, max_length=120)
    alerts_enabled: Optional[bool] = None


class PasswordChange(BaseModel):
    current_password: str = Field(max_length=128)
    new_password: str = Field(max_length=128)

    _check_password = field_validator("new_password")(_password_policy)


class AccountDelete(BaseModel):
    password: str = Field(max_length=128)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    # Giriş, yenileme ve parola değişikliği cevaplarında dolu gelir.
    refresh_token: Optional[str] = None
    expires_in: Optional[int] = None  # erişim token'ının ömrü (saniye)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=200)


# Girdi sınırları: tutarlar için makul bir üst sınır, not için veritabanı sütunuyla aynı uzunluk.
MAX_AMOUNT = 1_000_000_000
MAX_NOTE = 500
# İşlem tarihi: saat dilimi farkı için yarına kadar, geriye en fazla 10 yıl.
MAX_PAST_DAYS = 3650
# Geçmiş tarihle başlatılan seride aradaki aylar hemen üretilir; bu yüzden sınırlı.
MAX_RECURRING_PAST_DAYS = 366


def _check_tx_date(value: Optional[date]) -> Optional[date]:
    if value is None:
        return value
    today = date.today()
    if value > today + timedelta(days=1):
        raise ValueError("İşlem tarihi ileri bir gün olamaz")
    if value < today - timedelta(days=MAX_PAST_DAYS):
        raise ValueError("İşlem tarihi en fazla 10 yıl önce olabilir")
    return value


# ---- Transactions ----
class TransactionBase(BaseModel):
    amount: MoneyIn = Field(gt=0, le=MAX_AMOUNT)
    type: TxType = TxType.expense
    category: Optional[CategoryEnum] = None  # None => model otomatik atar
    note: str = Field(default="", max_length=MAX_NOTE)
    occurred_on: date = Field(default_factory=date.today)
    is_recurring: bool = False

    _check_date = field_validator("occurred_on")(_check_tx_date)

    @model_validator(mode="after")
    def _recurring_start(self):
        if self.is_recurring and self.occurred_on < date.today() - timedelta(
            days=MAX_RECURRING_PAST_DAYS
        ):
            raise ValueError("Tekrarlayan işlem en fazla 12 ay önceden başlatılabilir")
        return self


class TransactionCreate(TransactionBase):
    # İstemcide gösterilen kategori önerisi (varsa). Model geri bildirimi için saklanır.
    suggested_category: Optional[CategoryEnum] = None
    suggestion_confidence: Optional[float] = Field(default=None, ge=0, le=1)
    suggestion_model: Optional[str] = Field(default=None, max_length=40)


class TransactionUpdate(BaseModel):
    # Tüm alanlar opsiyonel — yalnızca gönderilenler güncellenir.
    amount: Optional[MoneyIn] = Field(default=None, gt=0, le=MAX_AMOUNT)
    type: Optional[TxType] = None
    category: Optional[CategoryEnum] = None
    note: Optional[str] = Field(default=None, max_length=MAX_NOTE)
    occurred_on: Optional[date] = None
    is_recurring: Optional[bool] = None

    _check_date = field_validator("occurred_on")(_check_tx_date)


class TransactionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    amount: float
    type: TxType
    category: CategoryEnum
    auto_categorized: bool
    is_recurring: bool
    series_id: Optional[int] = None
    note: str
    occurred_on: date
    created_at: datetime


class BudgetAlert(BaseModel):
    """İşlem kaydedildiğinde bütçenin %80'ini geçen kategori (ya da toplam bütçe).

    Mesajda tutar yok; tutarı istemci kendi para biriminde gösterir.
    """

    category: str           # kategori adı ya da "Toplam"
    limit: float
    spent: float
    ratio: float            # spent / limit
    level: Literal["warning", "exceeded"]
    crossed: bool           # eşik bu işlemle mi geçildi?
    message: str


class TransactionSaved(TransactionOut):
    """POST ve PUT cevabı: işlem ve (varsa) bütçe uyarıları."""

    budget_alerts: list[BudgetAlert] = []


class CategoryTotal(BaseModel):
    category: str
    total: float


class MonthSummary(BaseModel):
    month: str               # "YYYY-MM"
    income: float
    expense: float
    count: int


class TransactionSummary(BaseModel):
    balance: float           # tüm zamanlar: gelir - gider
    total_income: float
    total_expense: float
    month: str               # "YYYY-MM", istenen ay (varsayılan: içinde bulunulan ay)
    month_income: float
    month_expense: float
    month_by_category: list[CategoryTotal]  # bu ayın giderleri, büyükten küçüğe


# ---- Budgets ----
class BudgetCreate(BaseModel):
    category: BudgetCategory  # kategori ya da "Toplam" (bütün giderler)
    monthly_limit: MoneyIn = Field(gt=0, le=MAX_AMOUNT)


class BudgetOut(BaseModel):
    # Router hesaplanan alanları sonradan atıyor; atama da doğrulanır, böylece Decimal
    # değerler float'a çevrilir.
    model_config = ConfigDict(from_attributes=True, validate_assignment=True)
    id: int
    category: BudgetCategory
    monthly_limit: float
    spent: float = 0.0  # bu ayın harcaması, router doldurur


# ---- ML ----
class CategorizeRequest(BaseModel):
    text: str = Field(max_length=500)  # işlem notu sütunuyla aynı sınır


class CategorizeResponse(BaseModel):
    category: CategoryEnum
    confidence: float
    model: str  # hangi modelin yanıtladığı (stub / svm / berturk)


# ---- Analytics (İP-4) ----
class MonthTotal(BaseModel):
    month: str
    total: float


class CategoryProjection(BaseModel):
    category: str
    projected: float


class ForecastResponse(BaseModel):
    current_month_spent: float
    projected_month_end: float
    next_month_prediction: float
    method: str        # trend | last_month | run_rate
    velocity: str      # Yüksek | Normal | Düşük
    history: list[MonthTotal]
    by_category: list[CategoryProjection]


class AnomalyItem(BaseModel):
    transaction_id: int
    amount: float
    category: str
    note: str
    occurred_on: str
    z_score: float
    severity: str      # high | medium
    reason: str
    category_mean: float


class InsightItem(BaseModel):
    icon: str
    tone: str          # good | warn | neutral
    title: str
    text: str


# ---- Savings goals ----
def _check_deadline(value: Optional[date]) -> Optional[date]:
    if value is not None and value < date.today():
        raise ValueError("Son tarih bugünden önce olamaz")
    return value


class GoalCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    target_amount: MoneyIn = Field(gt=0, le=MAX_AMOUNT)
    deadline: Optional[date] = None

    _check_deadline = field_validator("deadline")(_check_deadline)


class GoalUpdate(BaseModel):
    # Gönderilmeyen alan değişmez; deadline için null gönderilirse son tarih kaldırılır.
    title: Optional[str] = Field(default=None, min_length=1, max_length=120)
    target_amount: Optional[MoneyIn] = Field(default=None, gt=0, le=MAX_AMOUNT)
    deadline: Optional[date] = None

    _check_deadline = field_validator("deadline")(_check_deadline)


class GoalContribute(BaseModel):
    amount: MoneyIn = Field(gt=0, le=MAX_AMOUNT)


GoalStatus = Literal["completed", "no_deadline", "on_track", "behind", "overdue"]


class GoalOut(BaseModel):
    # Router hesaplanan alanları sonradan atıyor; atama da doğrulanır, böylece Decimal
    # değerler float'a çevrilir.
    model_config = ConfigDict(from_attributes=True, validate_assignment=True)
    id: int
    title: str
    target_amount: float
    current_amount: float
    deadline: Optional[date] = None
    created_at: datetime
    # Aşağıdakiler router'da hesaplanır (bkz. goals.py).
    progress: float = 0.0             # 0..1
    remaining: float = 0.0
    days_left: Optional[int] = None   # son tarih yoksa boş, geçtiyse negatif
    months_left: Optional[int] = None
    monthly_needed: Optional[float] = None  # hedefe yetişmek için ayda ayrılması gereken
    status: GoalStatus = "no_deadline"


# ---- Uyarılar ----
class AlertOut(BaseModel):
    id: str                  # kapatmak için; ay bilgisini içerir (ör. budget:Yemek:2026-10:80)
    kind: Literal["budget", "budget_pace", "anomaly", "goal", "recurring"]
    level: Literal["info", "warning", "danger"]
    title: str
    message: str
    category: Optional[str] = None
    amount: Optional[float] = None   # istemci kendi para biriminde gösterir
    ref_id: Optional[int] = None     # ilgili işlem, hedef ya da seri
    due_on: Optional[date] = None


class AlertDismiss(BaseModel):
    id: str = Field(min_length=1, max_length=120)
