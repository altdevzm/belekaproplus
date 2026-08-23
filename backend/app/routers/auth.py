import hashlib
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel
from app.database import get_db
from app import models, schemas

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

class LoginRequest(BaseModel):
    numeric_id: str
    pin: str
    terminal_name: Optional[str] = "TERMINAL"

class LoginResponse(BaseModel):
    status: str
    user: schemas.UserResponse
    store: Optional[schemas.StoreResponse] = None
    token: Optional[str] = None

def verify_pin(plain_pin: str, stored_hash: str) -> bool:
    if plain_pin == stored_hash:
        return True
    hashed = hashlib.sha256(plain_pin.encode('utf-8')).hexdigest()
    return hashed == stored_hash

@router.post("/login", response_model=LoginResponse)
def cloud_login(req: LoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate a user (Branch Manager, Owner, Cashier) from any store or branch against the Cloud PostgreSQL DB.
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

    if not verify_pin(req.pin.strip(), user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN / Password"
        )

    store = None
    if user.store_id:
        store = db.query(models.Store).filter(models.Store.id == user.store_id).first()

    return {
        "status": "authenticated",
        "user": user,
        "store": store,
        "token": f"cloud_jwt_{user.numeric_id}_{user.id}"
    }
