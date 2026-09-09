from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional, List
from pydantic import BaseModel
from app.database import get_db
from app import models, schemas
from app.auth_deps import (
    verify_and_update_password,
    hash_password,
    create_access_token,
    log_audit_event,
    get_current_user,
    require_roles,
)

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

class LoginResponse(BaseModel):
    status: str
    user: schemas.UserResponse
    store: Optional[schemas.StoreResponse] = None
    token: str

@router.post("/login", response_model=LoginResponse)
def cloud_login(req: schemas.LoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate a user via TPIN + User ID (numeric_id) + Password (PIN).
    Resolves Organization/Tenant -> User -> Role -> Store Scope on server side.
    """
    tpin_clean = req.tpin.strip() if req.tpin else None
    numeric_id_clean = req.numeric_id.strip()

    # Step 1: Server-side Tenant/Store Resolution via TPIN
    query = db.query(models.User).filter(
        models.User.numeric_id == numeric_id_clean,
        models.User.is_active == True
    )

    if tpin_clean:
        # Strictly filter users belonging to stores matching this TPIN
        matching_stores = db.query(models.Store).filter(models.Store.tpin == tpin_clean).all()
        if not matching_stores:
            log_audit_event(
                db,
                event_type="LOGIN_FAILURE",
                tpin=tpin_clean,
                numeric_id=numeric_id_clean,
                details=f"Invalid TPIN '{tpin_clean}' — organization not found.",
                is_success=False,
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid TPIN or Organization."
            )
        store_ids = [s.id for s in matching_stores]
        query = query.filter(models.User.store_id.in_(store_ids))

    elif req.company_name and req.company_name.strip():
        c_clean = req.company_name.strip().lower()
        query = query.join(models.Store).filter(
            func.lower(models.Store.name).contains(c_clean) |
            func.lower(models.Store.store_code) == c_clean |
            func.lower(models.Store.branch_name).contains(c_clean) |
            (models.Store.tpin == req.company_name.strip())
        )

    candidate_users = query.all()

    if not candidate_users:
        log_audit_event(
            db,
            event_type="LOGIN_FAILURE",
            tpin=tpin_clean,
            numeric_id=numeric_id_clean,
            details=f"User ID '{numeric_id_clean}' not found in organization.",
            is_success=False,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid TPIN or User ID"
        )

    # Step 2: Server-side Password / PIN Verification
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
        log_audit_event(
            db,
            event_type="LOGIN_FAILURE",
            tpin=tpin_clean,
            numeric_id=numeric_id_clean,
            details="Invalid PIN / Password attempt.",
            is_success=False,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN / Password"
        )

    user = matched_user
    store = db.query(models.Store).filter(models.Store.id == user.store_id).first() if user.store_id else None
    resolved_tpin = store.tpin if store else tpin_clean

    # Step 3: Issue Authenticated Session Token with Tenant & Branch Context
    access_token = create_access_token(data={
        "user_id": user.id,
        "numeric_id": user.numeric_id,
        "role": user.role,
        "store_id": user.store_id,
        "tpin": resolved_tpin,
        "bhf_id": store.bhf_id if store else "00",
    })

    # Step 4: Record Audit Trail Event
    log_audit_event(
        db,
        event_type="LOGIN_SUCCESS",
        tpin=resolved_tpin,
        store_id=user.store_id,
        numeric_id=user.numeric_id,
        user_id=user.id,
        details=f"Login successful for {user.name} (Role: {user.role}, Branch: {user.branch_name or 'HQ'})",
        is_success=True,
    )

    return {
        "status": "authenticated",
        "user": user,
        "store": store,
        "token": access_token
    }


@router.get("/audit-logs", response_model=List[schemas.AuditLogResponse])
def get_audit_logs(
    current_user: models.User = Depends(require_roles(["owner", "super_admin"])),
    db: Session = Depends(get_db)
):
    """
    Retrieve audit trail security logs (restricted to Owner / Super Admin).
    """
    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    user_tpin = (user_store.tpin or "").strip() if user_store else ""

    query = db.query(models.AuditLog)
    if current_user.role != "super_admin" and user_tpin:
        query = query.filter(models.AuditLog.tpin == user_tpin)

    return query.order_by(models.AuditLog.timestamp.desc()).limit(100).all()
