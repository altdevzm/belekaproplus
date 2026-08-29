from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access, require_roles

router = APIRouter(prefix="/api/v1/products", tags=["Products"])

@router.get("", response_model=List[schemas.ProductResponse])
def get_products(
    store_id: int,
    include_archived: bool = False,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch all inventory products for a specific store branch (tenant-scoped)."""
    verify_store_access(store_id, current_user)
    query = db.query(models.Product).filter(models.Product.store_id == store_id)
    if not include_archived:
        query = query.filter(models.Product.is_archived == False)
    return query.all()

@router.post("", response_model=schemas.ProductResponse, status_code=status.HTTP_201_CREATED)
def create_product(
    product_in: schemas.ProductCreate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """Create or update a product in the cloud PostgreSQL database for a store. Requires Manager or Owner role."""
    verify_store_access(product_in.store_id, current_user)

    if product_in.price < 0 or (product_in.unit_cost is not None and product_in.unit_cost < 0):
        raise HTTPException(status_code=400, detail="Product price and unit cost cannot be negative.")

    existing = db.query(models.Product).filter(
        models.Product.store_id == product_in.store_id,
        models.Product.sku == product_in.sku
    ).first()

    if existing:
        for key, value in product_in.model_dump().items():
            setattr(existing, key, value)
        db.commit()
        db.refresh(existing)
        return existing

    product = models.Product(**product_in.model_dump())
    db.add(product)
    db.commit()
    db.refresh(product)
    return product
