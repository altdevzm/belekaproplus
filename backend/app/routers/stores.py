from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access, require_roles

router = APIRouter(prefix="/api/v1/stores", tags=["Stores"])

@router.get("", response_model=List[schemas.StoreResponse])
def get_all_stores(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch active store branches. Regular users only see their assigned store; owners see organization branches."""
    if current_user.role in ["owner", "super_admin"]:
        user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
        user_tpin = (user_store.tpin or "").strip() if user_store else ""
        if user_tpin and current_user.role != "super_admin":
            return db.query(models.Store).filter(
                models.Store.tpin == user_tpin,
                models.Store.is_active == True
            ).all()
        if current_user.role != "super_admin":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Organization TPIN is not configured for this account.",
            )
        return db.query(models.Store).filter(models.Store.is_active == True).all()

    return db.query(models.Store).filter(
        models.Store.id == current_user.store_id,
        models.Store.is_active == True
    ).all()

@router.post("", response_model=schemas.StoreResponse, status_code=status.HTTP_201_CREATED)
def create_store(
    store_in: schemas.StoreCreate,
    current_user: models.User = Depends(require_roles(["owner"])),
    db: Session = Depends(get_db)
):
    """Register a new store branch under the owner's organization TPIN. Requires Owner role."""
    existing = db.query(models.Store).filter(models.Store.store_code == store_in.store_code).first()
    if existing:
        raise HTTPException(status_code=400, detail="Store code already registered")

    store_data = store_in.model_dump()
    
    # Auto-inherit corporate TPIN & DigiTax credentials from owner's store
    owner_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    if owner_store:
        owner_tpin = (owner_store.tpin or "").strip()
        if current_user.role != "super_admin" and not owner_tpin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Organization TPIN must be configured before creating branches.",
            )
        if current_user.role != "super_admin":
            # Never accept tenant identity from a non-super-admin request body.
            store_data["tpin"] = owner_tpin
        if not store_data.get("tpin"):
            store_data["tpin"] = owner_store.tpin
        if not store_data.get("digitax_api_key"):
            store_data["digitax_api_key"] = owner_store.digitax_api_key
        if not store_data.get("digitax_environment"):
            store_data["digitax_environment"] = owner_store.digitax_environment
        if not store_data.get("business_tax_type"):
            store_data["business_tax_type"] = owner_store.business_tax_type

    store = models.Store(**store_data)
    db.add(store)
    db.commit()
    db.refresh(store)
    return store

@router.put("/{store_id}", response_model=schemas.StoreResponse)
def update_store(
    store_id: int,
    store_in: schemas.StoreUpdate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """Update store details, TPIN, or DigiTax credentials on Cloud PostgreSQL DB (tenant-scoped)."""
    verify_store_access(store_id, current_user, db)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")
    
    update_data = store_in.model_dump(exclude_unset=True)
    if "tpin" in update_data and current_user.role != "super_admin":
        current_tpin = (store.tpin or "").strip()
        requested_tpin = (update_data["tpin"] or "").strip()
        if requested_tpin != current_tpin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only a super admin may change organization tenant identity.",
            )
        update_data.pop("tpin")
    for field, value in update_data.items():
        setattr(store, field, value)
    
    db.commit()
    db.refresh(store)
    return store
