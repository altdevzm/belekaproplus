from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access, hash_password, require_roles

router = APIRouter(prefix="/api/v1/users", tags=["Users"])

class UserSyncBatch(BaseModel):
    store_code: Optional[str] = "HQ-00"
    users: List[schemas.UserCreate]

@router.get("", response_model=List[schemas.UserResponse])
def get_users(
    store_id: Optional[int] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch active users from Cloud PostgreSQL (tenant-scoped)."""
    target_store_id = store_id or current_user.store_id
    verify_store_access(target_store_id, current_user, db)

    query = db.query(models.User).filter(
        models.User.is_active == True,
        models.User.store_id == target_store_id
    )
    return query.all()

@router.post("", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def create_or_update_user(
    user_in: schemas.UserCreate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """
    Create or update a user in the Cloud PostgreSQL database.
    Requires Manager or Owner privileges.
    """
    verify_store_access(user_in.store_id, current_user, db)

    store = db.query(models.Store).filter(models.Store.id == user_in.store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")

    # Hash raw PIN/password if provided in password_hash field
    formatted_hash = user_in.password_hash
    if formatted_hash and not (formatted_hash.startswith("$2b$") or formatted_hash.startswith("$2a$")):
        formatted_hash = hash_password(formatted_hash)

    existing = db.query(models.User).filter(
        models.User.numeric_id == user_in.numeric_id,
        models.User.store_id == user_in.store_id
    ).first()

    if existing:
        existing.name = user_in.name
        existing.role = user_in.role
        existing.branch_name = user_in.branch_name
        existing.phone = user_in.phone
        existing.is_active = user_in.is_active if user_in.is_active is not None else True
        if formatted_hash:
            existing.password_hash = formatted_hash
        db.commit()
        db.refresh(existing)
        return existing

    user = models.User(
        store_id=user_in.store_id,
        numeric_id=user_in.numeric_id,
        name=user_in.name,
        role=user_in.role,
        branch_name=user_in.branch_name,
        phone=user_in.phone,
        password_hash=formatted_hash or hash_password("0000"),
        is_active=user_in.is_active if user_in.is_active is not None else True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user

@router.post("/sync", status_code=status.HTTP_200_OK)
def sync_users_batch(
    payload: UserSyncBatch,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """
    Batch sync users from local POS to Cloud PostgreSQL.
    """
    synced_ids = []
    for u_in in payload.users:
        verify_store_access(u_in.store_id, current_user, db)
        formatted_hash = u_in.password_hash
        if formatted_hash and not (formatted_hash.startswith("$2b$") or formatted_hash.startswith("$2a$")):
            formatted_hash = hash_password(formatted_hash)

        existing = db.query(models.User).filter(
            models.User.numeric_id == u_in.numeric_id,
            models.User.store_id == u_in.store_id
        ).first()

        if existing:
            existing.name = u_in.name
            existing.role = u_in.role
            existing.branch_name = u_in.branch_name
            existing.phone = u_in.phone
            if formatted_hash:
                existing.password_hash = formatted_hash
        else:
            new_u = models.User(
                store_id=u_in.store_id,
                numeric_id=u_in.numeric_id,
                name=u_in.name,
                role=u_in.role,
                branch_name=u_in.branch_name,
                phone=u_in.phone,
                password_hash=formatted_hash or hash_password("0000"),
                is_active=True,
            )
            db.add(new_u)
        synced_ids.append(u_in.numeric_id)

    db.commit()
    return {"status": "success", "synced_users": synced_ids}
