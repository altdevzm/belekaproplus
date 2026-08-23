from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from app.database import get_db
from app import models, schemas

router = APIRouter(prefix="/api/v1/purchases", tags=["Purchase Orders"])

@router.get("", response_model=List[schemas.PurchaseOrderResponse])
def get_purchase_orders(
    store_id: Optional[int] = None,
    status_filter: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Fetch all Purchase Orders for store management."""
    query = db.query(models.PurchaseOrder)
    if store_id:
        query = query.filter(models.PurchaseOrder.store_id == store_id)
    if status_filter:
        query = query.filter(models.PurchaseOrder.status == status_filter)
    return query.order_by(models.PurchaseOrder.created_at.desc()).all()

@router.post("", response_model=schemas.PurchaseOrderResponse, status_code=status.HTTP_201_CREATED)
def create_purchase_order(
    po_in: schemas.PurchaseOrderCreate,
    db: Session = Depends(get_db)
):
    """Create a new Purchase Order document."""
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
    db: Session = Depends(get_db)
):
    """
    Approve & Receive Purchase Order.
    Automatically increments product stock levels in the PostgreSQL database!
    """
    po = db.query(models.PurchaseOrder).filter(models.PurchaseOrder.id == po_id).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found")

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
            product = db.query(models.Product).filter(models.Product.id == item.product_id).first()
            if product:
                product.stock_level += item.quantity_ordered
                product.unit_cost = item.unit_cost # Update latest unit cost

    db.commit()
    db.refresh(po)
    return po
