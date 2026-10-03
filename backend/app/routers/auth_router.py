"""Kayıt, giriş, oturum yenileme ve hesap yönetimi uçları."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from .. import auth, models, ratelimit, schemas, sessions
from ..database import get_db

router = APIRouter(prefix="/auth", tags=["auth"])


def _require_password(user: models.User, password: str) -> None:
    """Hassas işlemlerden önce parolayı yeniden sorar.

    Hatalı denemeler girişle aynı sayaca yazılır (15 dakikada 5). 401 yerine 400 döner;
    istemci 401'i oturumun düştüğü şeklinde yorumlayıp çıkış yapıyor.
    """
    email_key = user.email.strip().lower()
    if ratelimit.login_failures_by_email.is_limited(email_key):
        raise ratelimit.too_many()
    if not auth.verify_password(password, user.hashed_password):
        ratelimit.login_failures_by_email.add(email_key)
        raise HTTPException(status_code=400, detail="Mevcut parola hatalı")


@router.post("/register", response_model=schemas.UserOut, status_code=201)
def register(
    payload: schemas.UserCreate, request: Request, db: Session = Depends(get_db)
):
    ratelimit.enforce(ratelimit.register_by_ip, ratelimit.client_ip(request))
    existing = db.query(models.User).filter(models.User.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Bu e-posta zaten kayıtlı")
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


@router.post("/login", response_model=schemas.Token)
def login(
    request: Request,
    form: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    ratelimit.enforce(ratelimit.login_by_ip, ratelimit.client_ip(request))
    # OAuth2 form 'username' alanını e-posta olarak kullanıyoruz.
    email_key = form.username.strip().lower()
    if ratelimit.login_failures_by_email.is_limited(email_key):
        raise ratelimit.too_many()

    user = db.query(models.User).filter(models.User.email == form.username).first()
    # Kullanıcı yoksa da bcrypt çalışır; cevap süresi e-postanın varlığını ele vermez.
    hashed = user.hashed_password if user else auth.DUMMY_PASSWORD_HASH
    if not auth.verify_password(form.password, hashed) or not user:
        ratelimit.login_failures_by_email.add(email_key)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="E-posta veya parola hatalı",
        )
    pair = sessions.issue_tokens(db, user)
    db.commit()
    return pair


@router.post("/refresh", response_model=schemas.Token)
def refresh(
    payload: schemas.RefreshRequest, request: Request, db: Session = Depends(get_db)
):
    """Yenileme token'ını yeni bir erişim + yenileme token'ı çiftiyle değiştirir.

    Kullanılan token iptal edilir; aynı token ikinci kez gelirse o girişin bütün
    token'ları iptal edilir ve 401 döner.
    """
    ratelimit.enforce(ratelimit.refresh_by_ip, ratelimit.client_ip(request))
    return sessions.rotate(db, payload.refresh_token)


@router.post("/logout", status_code=204)
def logout(payload: schemas.RefreshRequest, db: Session = Depends(get_db)):
    """Bu cihazdaki oturumu kapatır (yenileme token'ı iptal edilir)."""
    sessions.revoke(db, payload.refresh_token)
    return None


@router.get("/me", response_model=schemas.UserOut)
def me(current: models.User = Depends(auth.get_current_user)):
    return current


@router.put("/me", response_model=schemas.UserOut)
def update_me(
    payload: schemas.UserUpdate,
    current: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    """Ad ve uyarı tercihini günceller (null gönderilen alan değişmez)."""
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(current, field, value.strip() if isinstance(value, str) else value)
    db.commit()
    db.refresh(current)
    return current


@router.post("/change-password", response_model=schemas.Token)
def change_password(
    payload: schemas.PasswordChange,
    current: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    """Parolayı değiştirir ve diğer bütün cihazlardaki oturumları kapatır.

    Oturum sürümü arttığı için eski erişim token'ları da hemen geçersiz olur. Bu cihaz
    için yeni bir token çifti döner.
    """
    _require_password(current, payload.current_password)
    if payload.current_password == payload.new_password:
        raise HTTPException(status_code=400, detail="Yeni parola eskisiyle aynı olamaz")
    current.hashed_password = auth.hash_password(payload.new_password)
    current.token_version += 1
    sessions.revoke_all(db, current.id)
    pair = sessions.issue_tokens(db, current)
    db.commit()
    return pair


@router.delete("/me", status_code=204)
def delete_account(
    payload: schemas.AccountDelete,
    current: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    """Hesabı ve kullanıcıya ait bütün verileri kalıcı olarak siler."""
    _require_password(current, payload.password)
    uid = current.id
    # İşlemler serilere bağlı olduğu için önce silinir.
    for model in (
        models.Transaction,
        models.RecurringSeries,
        models.Budget,
        models.Goal,
        models.RefreshToken,
        models.DismissedAlert,
    ):
        db.query(model).filter(model.user_id == uid).delete(synchronize_session=False)
    db.delete(current)
    db.commit()
    return None


@router.post("/me/ai-consent", response_model=schemas.UserOut)
def give_ai_consent(
    current: models.User = Depends(auth.get_current_user), db: Session = Depends(get_db)
):
    """Sohbet asistanı için verilerin Google Gemini'ye gönderilmesine onay verir."""
    current.ai_consent_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.commit()
    db.refresh(current)
    return current


@router.delete("/me/ai-consent", response_model=schemas.UserOut)
def withdraw_ai_consent(
    current: models.User = Depends(auth.get_current_user), db: Session = Depends(get_db)
):
    """Onayı geri çeker; sohbet asistanı tekrar onay verilene kadar kullanılamaz."""
    current.ai_consent_at = None
    db.commit()
    db.refresh(current)
    return current
