from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel
from app.database import get_db
from app import models, schemas
from app.auth_deps import (
    verify_and_update_password,
    hash_password,
    create_access_token
)

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

class LoginRequest(BaseModel):
    numeric_id: str
    pin: str
    terminal_name: Optional[str] = "TERMINAL"

class LoginResponse(BaseModel):
    status: str
    user: schemas.UserResponse
    store: Optional[schemas.StoreResponse] = None
    token: str

@router.post("/login", response_model=LoginResponse)
def cloud_login(req: LoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate a user (Branch Manager, Owner, Cashier) and issue a cryptographically signed JWT token.
    Automatically upgrades legacy unhashed/SHA-256 PINs to bcrypt.
    """
    user = db.query(models.User).filter(
        models.User.numeric_id == req.numeric_id.strip(),
        models.User.is_active == True
    ).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Login ID or user does not exist in cloud database"
        )

    is_valid, needs_rehash = verify_and_update_password(req.pin, user.password_hash)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN / Password"
        )

    # Auto-upgrade legacy hash to bcrypt on login
    if needs_rehash:
        user.password_hash = hash_password(req.pin)
        db.commit()
        db.refresh(user)

    store = None
    if user.store_id:
        store = db.query(models.Store).filter(models.Store.id == user.store_id).first()

    access_token = create_access_token(data={
        "user_id": user.id,
        "numeric_id": user.numeric_id,
        "role": user.role,
        "store_id": user.store_id,
    })

    return {
        "status": "authenticated",
        "user": user,
        "store": store,
        "token": access_token
    }
