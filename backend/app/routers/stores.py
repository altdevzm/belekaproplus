from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app import models, schemas

router = APIRouter(prefix="/api/v1/stores", tags=["Stores"])

@router.get("", response_model=List[schemas.StoreResponse])
def get_all_stores(db: Session = Depends(get_db)):
    """Fetch all active store branches for multi-store selection."""
    return db.query(models.Store).filter(models.Store.is_active == True).all()

@router.post("", response_model=schemas.StoreResponse, status_code=status.HTTP_201_CREATED)
def create_store(store_in: schemas.StoreCreate, db: Session = Depends(get_db)):
    """Register a new store branch in the PostgreSQL Cloud Database."""
    existing = db.query(models.Store).filter(models.Store.store_code == store_in.store_code).first()
    if existing:
        raise HTTPException(status_code=400, detail="Store code already registered")

    store = models.Store(**store_in.model_dump())
    db.add(store)
    db.commit()
    db.refresh(store)
    return store

@router.put("/{store_id}", response_model=schemas.StoreResponse)
def update_store(store_id: int, store_in: schemas.StoreUpdate, db: Session = Depends(get_db)):
    """Update store details, TPIN, or DigiTax credentials on Cloud PostgreSQL DB."""
    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")
    
    update_data = store_in.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(store, field, value)
    
    db.commit()
    db.refresh(store)
    return store
