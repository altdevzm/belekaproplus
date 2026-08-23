import hashlib
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from app.database import get_db
from app import models, schemas

router = APIRouter(prefix="/api/v1/users", tags=["Users"])

class UserSyncBatch(BaseModel):
    store_code: Optional[str] = "HQ-00"
    users: List[schemas.UserCreate]

@router.get("", response_model=List[schemas.UserResponse])
def get_users(store_id: Optional[int] = None, db: Session = Depends(get_db)):
    """Fetch active users from Cloud PostgreSQL."""
    query = db.query(models.User).filter(models.User.is_active == True)
    if store_id:
        query = query.filter(models.User.store_id == store_id)
    return query.all()

@router.post("", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def create_or_update_user(user_in: schemas.UserCreate, db: Session = Depends(get_db)):
    """
    Create or update a user (e.g. Branch Manager) in the Cloud PostgreSQL database.
    """
    # Ensure store exists, or use store_id 1 / create default
    store = db.query(models.Store).filter(models.Store.id == user_in.store_id).first()
    if not store:
        # Fallback to first active store
        store = db.query(models.Store).first()
        if not store:
            store = models.Store(store_code="HQ-00", name="Headquarters Main Store", bhf_id="00")
            db.add(store)
            db.flush()
        user_in.store_id = store.id

    existing = db.query(models.User).filter(
        models.User.numeric_id == user_in.numeric_id
    ).first()

    if existing:
        existing.name = user_in.name
        existing.role = user_in.role
        existing.branch_name = user_in.branch_name
        existing.phone = user_in.phone
        existing.is_active = user_in.is_active if user_in.is_active is not None else True
        if user_in.password_hash:
            existing.password_hash = user_in.password_hash
        existing.store_id = user_in.store_id
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
        password_hash=user_in.password_hash,
        is_active=user_in.is_active if user_in.is_active is not None else True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user

@router.post("/sync", status_code=status.HTTP_200_OK)
def sync_users_batch(payload: UserSyncBatch, db: Session = Depends(get_db)):
    """
    Batch sync users from local POS to Cloud PostgreSQL.
    """
    synced_ids = []
    for u_in in payload.users:
        existing = db.query(models.User).filter(
            models.User.numeric_id == u_in.numeric_id
        ).first()

        if existing:
            existing.name = u_in.name
            existing.role = u_in.role
            existing.branch_name = u_in.branch_name
            existing.phone = u_in.phone
            if u_in.password_hash:
                existing.password_hash = u_in.password_hash
        else:
            new_u = models.User(
                store_id=u_in.store_id,
                numeric_id=u_in.numeric_id,
                name=u_in.name,
                role=u_in.role,
                branch_name=u_in.branch_name,
                phone=u_in.phone,
                password_hash=u_in.password_hash,
                is_active=True,
            )
            db.add(new_u)
        synced_ids.append(u_in.numeric_id)

    db.commit()
    return {"status": "success", "synced_users": synced_ids}
