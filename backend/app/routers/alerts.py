"""Uygulama içi uyarılar (bütçe, bütçe hızı, hedef, olağandışı harcama, yaklaşan ödeme)."""
from fastapi import APIRouter, Depends
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import coach, models, schemas
from ..auth import get_current_user
from ..database import get_db

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("", response_model=list[schemas.AlertOut])
def list_alerts(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """O anki uyarılar, önemliden önemsize. Bildirimler kapalıysa boş liste döner."""
    return coach.collect_alerts(db, user)


@router.post("/dismiss", status_code=204)
def dismiss_alert(
    payload: schemas.AlertDismiss,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Uyarıyı kapatır. Aynı uyarı (aynı kimlik) bir daha gösterilmez."""
    db.add(models.DismissedAlert(user_id=user.id, alert_id=payload.id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()  # zaten kapatılmış
    return None
