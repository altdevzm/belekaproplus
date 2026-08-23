from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app import models, schemas

router = APIRouter(prefix="/api/v1/sync", tags=["Sync"])

@router.post("/batch", status_code=status.HTTP_201_CREATED)
def sync_batch_sales(payload: schemas.SyncBatchRequest, db: Session = Depends(get_db)):
    """
    Receive batch sales transactions from store terminals (offline sync queue).
    Inserts sales & sale items, updates stock levels in PostgreSQL DB.
    """
    synced_uuids = []
    
    # Verify store exists
    store = db.query(models.Store).filter(models.Store.id == payload.store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")

    for sale_in in payload.sales:
        # Check if transaction already exists in Postgres
        existing = db.query(models.SaleTransaction).filter(
            models.SaleTransaction.transaction_uuid == sale_in.transaction_uuid
        ).first()

        if existing:
            synced_uuids.append(sale_in.transaction_uuid)
            continue

        tx = models.SaleTransaction(
            transaction_uuid=sale_in.transaction_uuid,
            store_id=payload.store_id,
            total_amount=sale_in.total_amount,
            subtotal=sale_in.subtotal,
            tax_amount=sale_in.tax_amount,
            discount_amount=sale_in.discount_amount,
            total_cost=sale_in.total_cost,
            gross_profit=sale_in.gross_profit,
            tendered_amount=sale_in.tendered_amount,
            change_amount=sale_in.change_amount,
            payment_method=sale_in.payment_method,
            cashier_id=sale_in.cashier_id,
            cashier_name=sale_in.cashier_name,
            terminal_name=sale_in.terminal_name,
            customer_id=sale_in.customer_id,
            points_earned=sale_in.points_earned,
            points_redeemed=sale_in.points_redeemed,
            status="completed",
            is_synced=True,
        )
        db.add(tx)
        db.flush()

        for item_in in sale_in.items:
            item = models.SaleItem(
                sale_transaction_id=tx.id,
                product_id=item_in.product_id,
                product_name=item_in.product_name,
                price_at_sale=item_in.price_at_sale,
                unit_cost_at_sale=item_in.unit_cost_at_sale,
                quantity=item_in.quantity,
                tax_rate_at_sale=item_in.tax_rate_at_sale,
                is_tax_inclusive_at_sale=item_in.is_tax_inclusive_at_sale,
            )
            db.add(item)

            # Deduct stock level in cloud PostgreSQL database
            if item_in.product_id:
                product = db.query(models.Product).filter(models.Product.id == item_in.product_id).first()
                if product:
                    product.stock_level = max(0, product.stock_level - item_in.quantity)

        synced_uuids.append(sale_in.transaction_uuid)

    db.commit()
    return {"status": "success", "synced_uuids": synced_uuids}
