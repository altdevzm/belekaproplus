from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access, require_roles

router = APIRouter(prefix="/api/v1/purchases", tags=["Purchase Orders"])

@router.get("", response_model=List[schemas.PurchaseOrderResponse])
def get_purchase_orders(
    store_id: Optional[int] = None,
    status_filter: Optional[str] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch all Purchase Orders for store management (tenant-scoped)."""
    target_store_id = store_id or current_user.store_id
    verify_store_access(target_store_id, current_user)

    query = db.query(models.PurchaseOrder).filter(models.PurchaseOrder.store_id == target_store_id)
    if status_filter:
        query = query.filter(models.PurchaseOrder.status == status_filter)
    return query.order_by(models.PurchaseOrder.created_at.desc()).all()

@router.post("", response_model=schemas.PurchaseOrderResponse, status_code=status.HTTP_201_CREATED)
def create_purchase_order(
    po_in: schemas.PurchaseOrderCreate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """Create a new Purchase Order document. Requires Manager or Owner role."""
    verify_store_access(po_in.store_id, current_user)

    existing = db.query(models.PurchaseOrder).filter(models.PurchaseOrder.po_number == po_in.po_number).first()
    if existing:
        raise HTTPException(status_code=400, detail="Purchase Order number already exists")

    po = models.PurchaseOrder(
        po_number=po_in.po_number,
        store_id=po_in.store_id,
        supplier_name=po_in.supplier_name,
        supplier_tpin=po_in.supplier_tpin,
        total_amount=po_in.total_amount,
        notes=po_in.notes,
        status="pending"
    )
    db.add(po)
    db.flush()

    for item_in in po_in.items:
        item = models.PurchaseOrderItem(
            purchase_order_id=po.id,
            product_id=item_in.product_id,
            product_name=item_in.product_name,
            unit_cost=item_in.unit_cost,
            quantity_ordered=item_in.quantity_ordered,
            quantity_received=0
        )
        db.add(item)

    db.commit()
    db.refresh(po)
    return po

@router.post("/{po_id}/approve", response_model=schemas.PurchaseOrderResponse)
def approve_and_receive_purchase_order(
    po_id: int,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """
    Approve & Receive Purchase Order.
    Requires Manager or Owner role and tenant ownership authorization.
    Automatically increments product stock levels in the PostgreSQL database!
    """
    po = db.query(models.PurchaseOrder).filter(models.PurchaseOrder.id == po_id).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found")

    verify_store_access(po.store_id, current_user)

    if po.status in ["approved", "received"]:
        raise HTTPException(status_code=400, detail="Purchase Order is already approved and received")

    # Update PO Status & timestamp
    po.status = "received"
    po.approved_at = datetime.now()

    # Automatically increment inventory stock level for each ordered item
    items = db.query(models.PurchaseOrderItem).filter(models.PurchaseOrderItem.purchase_order_id == po.id).all()
    for item in items:
        item.quantity_received = item.quantity_ordered
        if item.product_id:
            product = db.query(models.Product).filter(
                models.Product.id == item.product_id,
                models.Product.store_id == po.store_id
            ).first()
            if product:
                product.stock_level += item.quantity_ordered
                product.unit_cost = item.unit_cost # Update latest unit cost

    db.commit()
    db.refresh(po)
    return po
