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
    """Fetch active store branches. Regular users only see their assigned store."""
    if current_user.role in ["owner", "super_admin"]:
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
    """Register a new store branch in the PostgreSQL Cloud Database. Requires Owner role."""
    existing = db.query(models.Store).filter(models.Store.store_code == store_in.store_code).first()
    if existing:
        raise HTTPException(status_code=400, detail="Store code already registered")

    store_data = store_in.model_dump()
    
    # Auto-inherit corporate tax & DigiTax credentials from HQ (Store 1) if not provided
    if not store_data.get("tpin") or not store_data.get("digitax_api_key"):
        hq_store = db.query(models.Store).filter(models.Store.id == 1).first()
        if hq_store:
            if not store_data.get("tpin"):
                store_data["tpin"] = hq_store.tpin
            if not store_data.get("digitax_api_key"):
                store_data["digitax_api_key"] = hq_store.digitax_api_key
            if not store_data.get("digitax_environment"):
                store_data["digitax_environment"] = hq_store.digitax_environment
            if not store_data.get("business_tax_type"):
                store_data["business_tax_type"] = hq_store.business_tax_type

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
    verify_store_access(store_id, current_user)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")
    
    update_data = store_in.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(store, field, value)
    
    db.commit()
    db.refresh(store)
    return store
