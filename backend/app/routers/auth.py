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

def _login_response(user: models.User, store: models.Store, db: Session):
    access_token = create_access_token(data={
        "user_id": user.id,
        "numeric_id": user.numeric_id,
        "role": user.role,
        "store_id": user.store_id,
        "tpin": store.tpin,
        "bhf_id": store.bhf_id,
    })
    log_audit_event(
        db,
        event_type="LOGIN_SUCCESS",
        tpin=store.tpin,
        store_id=user.store_id,
        numeric_id=user.numeric_id,
        user_id=user.id,
        details=f"Login successful; tenant resolved by TPIN, role={user.role}, branch={store.branch_name or 'HQ'}, scope_store_id={user.store_id}",
        is_success=True,
    )
    return {
        "status": "authenticated",
        "user": user,
        "store": store,
        "token": access_token,
    }

@router.post("/register", response_model=LoginResponse, status_code=status.HTTP_201_CREATED)
def register_organization(req: schemas.RegistrationRequest, db: Session = Depends(get_db)):
    """Create a new organization, its HQ branch, and its owner atomically."""
    business_name = req.business_name.strip()
    tpin = req.tpin.strip()
    numeric_id = req.numeric_id.strip()
    requested_store_code = req.store_code.strip()
    store_code = requested_store_code or f"{tpin}-HQ"

    if not business_name or not tpin or not numeric_id or not req.pin.strip():
        raise HTTPException(status_code=400, detail="Business name, TPIN, User ID, and password are required.")

    if db.query(models.Store).filter(models.Store.tpin == tpin).first():
        raise HTTPException(status_code=409, detail="An organization with this TPIN already exists.")
    if db.query(models.Store).filter(models.Store.store_code == store_code).first():
        if requested_store_code == "HQ-00":
            store_code = f"{tpin}-HQ"
        else:
            raise HTTPException(status_code=409, detail="This branch code is already registered.")

    store = models.Store(
        store_code=store_code,
        bhf_id="00",
        name=business_name,
        branch_name=req.branch_name.strip() or "Headquarters (HQ)",
        tpin=tpin,
        is_active=True,
    )
    db.add(store)
    db.flush()

    owner = models.User(
        store_id=store.id,
        numeric_id=numeric_id,
        name=req.owner_name.strip() or "Owner",
        password_hash=hash_password(req.pin),
        role="owner",
        branch_name=store.branch_name,
        is_active=True,
    )
    db.add(owner)
    db.commit()
    db.refresh(owner)
    db.refresh(store)
    return _login_response(owner, store, db)

@router.post("/resolve-organization", response_model=schemas.OrganizationLookupResponse)
def resolve_organization(req: schemas.OrganizationLookupRequest, db: Session = Depends(get_db)):
    """Resolve an exact company name to its tenant TPIN for login."""
    company_name = req.company_name.strip()
    if not company_name:
        raise HTTPException(status_code=400, detail="Company name is required.")

    matches = db.query(models.Store).filter(
        func.lower(models.Store.name) == company_name.lower(),
        models.Store.is_active == True,
    ).all()
    tpins = {store.tpin.strip() for store in matches if store.tpin and store.tpin.strip()}
    if not tpins:
        raise HTTPException(status_code=404, detail="Company not found.")
    if len(tpins) > 1:
        raise HTTPException(
            status_code=409,
            detail="More than one active organization uses this company name. Contact your administrator.",
        )

    store = matches[0]
    return {"company_name": store.name, "tpin": next(iter(tpins))}

@router.post("/login", response_model=LoginResponse)
def cloud_login(req: schemas.LoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate a user via TPIN + User ID (numeric_id) + Password (PIN).
    Resolves Organization/Tenant -> User -> Role -> Store Scope on server side.
    """
    tpin_clean = req.tpin.strip() if req.tpin else None
    numeric_id_clean = req.numeric_id.strip()

    if not tpin_clean:
        log_audit_event(
            db,
            event_type="LOGIN_FAILURE",
            numeric_id=numeric_id_clean,
            details="Remote login rejected because TPIN is required.",
            is_success=False,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="TPIN, User ID, and password are required.",
        )

    # Step 1: Server-side Tenant/Store Resolution via TPIN
    query = db.query(models.User).filter(
        models.User.numeric_id == numeric_id_clean,
        models.User.is_active == True
    )

    # Strictly resolve the organization by TPIN before checking the user ID.
    matching_stores = db.query(models.Store).filter(
        models.Store.tpin == tpin_clean,
        models.Store.is_active == True,
    ).all()
    if not matching_stores:
        log_audit_event(
            db,
            event_type="LOGIN_FAILURE",
            tpin=tpin_clean,
            numeric_id=numeric_id_clean,
            details="TPIN did not resolve to an active organization.",
            is_success=False,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid TPIN or Organization."
        )
    branch_code = req.branch_code.strip() if req.branch_code else None
    if branch_code:
        branch_code_normalized = branch_code.casefold()
        matching_stores = [
            store for store in matching_stores
            if (store.bhf_id or '').strip().casefold() == branch_code_normalized
            or (store.store_code or '').strip().casefold() == branch_code_normalized
        ]
        if not matching_stores:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid TPIN or branch code.",
            )
    store_ids = [s.id for s in matching_stores]
    query = query.filter(models.User.store_id.in_(store_ids))

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
    matched_users = []
    needs_rehash = False
    for u in candidate_users:
        is_valid, user_needs_rehash = verify_and_update_password(req.pin, u.password_hash)
        if is_valid:
            if user_needs_rehash:
                u.password_hash = hash_password(req.pin)
                needs_rehash = True
            matched_users.append(u)

    if len(matched_users) != 1:
        log_audit_event(
            db,
            event_type="LOGIN_FAILURE",
            tpin=tpin_clean,
            numeric_id=numeric_id_clean,
            details="Invalid or ambiguous PIN / Password attempt within the resolved organization.",
            is_success=False,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or ambiguous credentials."
        )

    if needs_rehash:
        db.commit()
        db.refresh(matched_users[0])

    matched_user = matched_users[0]

    user = matched_user
    store = db.query(models.Store).filter(models.Store.id == user.store_id).first() if user.store_id else None
    resolved_tpin = store.tpin if store else tpin_clean

    # Step 3: Issue authenticated session token with database-derived tenant and branch context.
    return _login_response(user, store, db)


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
    elif current_user.role != "super_admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Organization TPIN is not configured for this account.",
        )

    return query.order_by(models.AuditLog.timestamp.desc()).limit(100).all()
