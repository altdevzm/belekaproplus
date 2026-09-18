from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access, require_roles, verify_and_update_password

router = APIRouter(prefix="/api/v1/stores", tags=["Stores"])

@router.get("", response_model=List[schemas.StoreResponse])
def get_all_stores(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch active store branches. Returns organization branches for users within a tenant."""
    user_role = (current_user.role or "").strip().lower()
    if user_role == "super_admin":
        return db.query(models.Store).filter(models.Store.is_active == True).all()

    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    user_tpin = (user_store.tpin or "").strip() if user_store else ""

    if user_tpin:
        return db.query(models.Store).filter(
            models.Store.tpin == user_tpin,
            models.Store.is_active == True
        ).all()

    return db.query(models.Store).filter(
        models.Store.id == current_user.store_id,
        models.Store.is_active == True
    ).all()

@router.post("", response_model=schemas.StoreResponse, status_code=status.HTTP_201_CREATED)
def create_store(
    store_in: schemas.StoreCreate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """Register or update a store branch under the user's organization TPIN."""
    store_data = store_in.model_dump()
    store_data["bhf_id"] = (store_data.get("bhf_id") or "000").strip()
    store_data["store_code"] = store_data["bhf_id"]
    
    # Auto-inherit corporate TPIN & DigiTax credentials from owner's / manager's store
    owner_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    if owner_store:
        owner_tpin = (owner_store.tpin or "").strip()
        user_role = (current_user.role or "").strip().lower()
        if user_role != "super_admin" and not owner_tpin and not store_data.get("tpin"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Organization TPIN must be configured before creating branches.",
            )
        if user_role != "super_admin" and owner_tpin:
            store_data["tpin"] = owner_tpin
        if not store_data.get("tpin"):
            store_data["tpin"] = owner_store.tpin
        if store_data["bhf_id"] == "000" and not store_data.get("digitax_api_key"):
            store_data["digitax_api_key"] = owner_store.digitax_api_key
        if not store_data.get("digitax_environment"):
            store_data["digitax_environment"] = owner_store.digitax_environment or "sandbox"
        if not store_data.get("business_tax_type"):
            store_data["business_tax_type"] = owner_store.business_tax_type

    existing = None
    if store_data.get("tpin"):
        existing = db.query(models.Store).filter(
            models.Store.tpin == store_data.get("tpin"),
            models.Store.bhf_id == store_data.get("bhf_id"),
        ).first()

    if not existing:
        existing = db.query(models.Store).filter(
            models.Store.store_code == store_data.get("store_code"),
        ).first()

    if existing:
        # Upsert: Update existing store with new details (e.g. branch name, manager, etc.)
        for key, val in store_data.items():
            if val is not None and key not in ["id"]:
                setattr(existing, key, val)
        existing.is_active = True
        db.commit()
        db.refresh(existing)
        return existing

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
    requested_bhf_id = update_data.get("bhf_id")
    if requested_bhf_id:
        requested_bhf_id = requested_bhf_id.strip()
        update_data["bhf_id"] = requested_bhf_id
        update_data["store_code"] = requested_bhf_id
        duplicate = db.query(models.Store).filter(
            models.Store.tpin == store.tpin,
            models.Store.bhf_id == requested_bhf_id,
            models.Store.id != store_id,
        ).first()
        if duplicate:
            raise HTTPException(status_code=400, detail="BHF ID already registered for this organization")
    update_data.pop("store_code", None)
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

    # Corporate fiscal configuration is owned by HQ and must reach existing
    # branches without overwriting each branch's BHF identity.
    corporate_fields = {
        "tpin",
        "tax_id",
        "business_tax_type",
        "currency_symbol",
        "sdc_id",
        "mrc_no",
    }
    corporate_updates = {
        field: value
        for field, value in update_data.items()
        if field in corporate_fields
    }
    if corporate_updates and current_user.role == "owner":
        organization_stores = db.query(models.Store).filter(
            models.Store.tpin == store.tpin,
            models.Store.id != store.id,
        ).all()
        for branch in organization_stores:
            for field, value in corporate_updates.items():
                setattr(branch, field, value)
    
    db.commit()
    db.refresh(store)
    return store

@router.delete("/{store_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_store(
    store_id: int,
    current_user: models.User = Depends(require_roles(["owner"])),
    db: Session = Depends(get_db)
):
    """Permanently delete a branch and its tenant-scoped data."""
    verify_store_access(store_id, current_user, db)
    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")
    if store.id == current_user.store_id:
        raise HTTPException(status_code=400, detail="The headquarters branch cannot be deleted")
    db.delete(store)
    db.commit()
    return None

@router.post("/company/purge", status_code=status.HTTP_200_OK)
@router.delete("/company/purge", status_code=status.HTTP_200_OK)
def purge_company_account(
    req: schemas.CompanyAccountPurgeRequest,
    current_user: models.User = Depends(require_roles(["owner", "super_admin"])),
    db: Session = Depends(get_db)
):
    """
    Permanently delete the entire company organization account and all its branches,
    including staff users, products, sales transactions, customers, and inventory.
    Requires owner credentials and explicit confirmation phrase.
    """
    phrase = (req.confirm_phrase or "").strip().upper()
    if phrase not in ["DELETE", "DELETE COMPANY", "PURGE"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Confirmation phrase must be 'DELETE' or 'DELETE COMPANY'."
        )
    
    is_valid, _ = verify_and_update_password(req.password, current_user.password_hash)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid owner passcode or PIN."
        )

    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    if not user_store:
        raise HTTPException(status_code=404, detail="Store not found for this user.")

    # Find all stores under this company TPIN (or current store ID)
    if user_store.tpin:
        stores_to_delete = db.query(models.Store).filter(models.Store.tpin == user_store.tpin).all()
    else:
        stores_to_delete = [user_store]

    deleted_count = len(stores_to_delete)
    for store in stores_to_delete:
        db.delete(store)
    db.commit()

    return {
        "success": True,
        "message": f"Company account and {deleted_count} associated branch(es) were permanently deleted.",
        "deleted_stores_count": deleted_count
    }
