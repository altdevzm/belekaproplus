from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
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
    company_name: Optional[str] = None
    terminal_name: Optional[str] = "TERMINAL"

class LoginResponse(BaseModel):
    status: str
    user: schemas.UserResponse
    store: Optional[schemas.StoreResponse] = None
    token: str

@router.post("/login", response_model=LoginResponse)
def cloud_login(req: LoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate a user (Branch Manager, Owner, Cashier) with multi-tenant store filtering.
    Requires Company Name / Code, Staff ID, and PIN.
    """
    query = db.query(models.User).filter(
        models.User.numeric_id == req.numeric_id.strip(),
        models.User.is_active == True
    )

    if req.company_name and req.company_name.strip():
        c_clean = req.company_name.strip().lower()
        query = query.join(models.Store).filter(
            func.lower(models.Store.name).contains(c_clean) |
            func.lower(models.Store.store_code) == c_clean |
            func.lower(models.Store.branch_name).contains(c_clean) |
            (models.Store.tpin == req.company_name.strip())
        )

    candidate_users = query.all()

    if not candidate_users:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Company Name or Staff ID"
        )

    matched_user = None
    for u in candidate_users:
        is_valid, needs_rehash = verify_and_update_password(req.pin, u.password_hash)
        if is_valid:
            if needs_rehash:
                u.password_hash = hash_password(req.pin)
                db.commit()
                db.refresh(u)
            matched_user = u
            break

    if not matched_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN / Password"
        )

    user = matched_user
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
