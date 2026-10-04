"""Hesaplar: kayıt, profil, parola değişikliği ve hesabın silinmesi."""
from sqlalchemy.orm import Session

from .. import auth, models, schemas, sessions
from .errors import RuleViolation


def email_taken(db: Session, email: str) -> bool:
    return db.query(models.User).filter(models.User.email == email).first() is not None


def register(db: Session, payload: schemas.UserCreate) -> models.User:
    user = models.User(
        email=payload.email,
        hashed_password=auth.hash_password(payload.password),
        display_name=payload.display_name,
        token_version=auth.new_token_version(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def update_profile(db: Session, user: models.User, payload: schemas.UserUpdate) -> models.User:
    """Ad ve uyarı tercihini günceller (null gönderilen alan değişmez)."""
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(user, field, value.strip() if isinstance(value, str) else value)
    db.commit()
    db.refresh(user)
    return user


def change_password(db: Session, user: models.User, current: str, new: str) -> schemas.Token:
    """Parolayı değiştirir ve bütün oturumları kapatır; bu cihaz için yeni token çifti döner.

    Oturum sürümü arttığı için eski erişim token'ları da hemen geçersiz olur. Mevcut
    parolanın doğruluğu çağıran tarafta (istek sınırıyla birlikte) denetlenir.
    """
    if current == new:
        raise RuleViolation("Yeni parola eskisiyle aynı olamaz")
    user.hashed_password = auth.hash_password(new)
    user.token_version += 1
    sessions.revoke_all(db, user.id)
    pair = sessions.issue_tokens(db, user)
    db.commit()
    return pair


# Kullanıcıya ait tablolar. İşlemler serilere bağlı olduğu için önce silinir.
USER_DATA = (
    models.Transaction,
    models.RecurringSeries,
    models.Budget,
    models.Goal,
    models.RefreshToken,
    models.DismissedAlert,
)


def delete(db: Session, user: models.User) -> None:
    """Hesabı ve kullanıcıya ait bütün verileri kalıcı olarak siler."""
    for model in USER_DATA:
        db.query(model).filter(model.user_id == user.id).delete(synchronize_session=False)
    db.delete(user)
    db.commit()
