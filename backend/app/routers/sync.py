import logging
from fastapi import APIRouter, Depends, HTTPException, status
from datetime import datetime
from sqlalchemy.sql import func
from sqlalchemy.orm import Session
from typing import List, Optional
from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access
from app.services.digitax_service import DigiTaxZraService

logger = logging.getLogger("beleka.sync")

router = APIRouter(prefix="/api/v1/sync", tags=["Sync"])


def _resolve_product_id(
    db: Session, store_id: int, local_product_id: Optional[int], product_name: str
) -> Optional[int]:
    """Resolve a branch's local product ID to a valid PostgreSQL product ID.
    
    Strategy:
    1. Try exact ID match within the same store.
    2. Fall back to name match within the same store.
    3. Return None (FK-safe) if no match is found — the sale item is still
       stored with full name, price, cost, and tax data for reporting.
    """
    if local_product_id:
        product = db.query(models.Product).filter(
            models.Product.id == local_product_id,
            models.Product.store_id == store_id,
        ).first()
        if product:
            return product.id

    # Fallback: match by name within the store
    if product_name:
        product = db.query(models.Product).filter(
            models.Product.store_id == store_id,
            models.Product.name == product_name,
        ).first()
        if product:
            return product.id

    # No match found — return None so the SaleItem is stored without FK
    return None

@router.post("/batch", status_code=status.HTTP_201_CREATED)
def sync_batch_sales(
    payload: schemas.SyncBatchRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Receive batch sales transactions from store terminals (offline sync queue).
    Inserts sales & sale items, updates stock levels in PostgreSQL DB.
    Auto-fiscalizes un-fiscalized sales with DigiTax if API key present.
    Requires authentication & store verification.
    """
    logger.info(
        "SYNC_BATCH: Received %d sales from user=%s (store_id=%d)",
        len(payload.sales), current_user.numeric_id, payload.store_id
    )
    verify_store_access(payload.store_id, current_user, db)
    
    store = db.query(models.Store).filter(models.Store.id == payload.store_id).first()
    if not store:
        logger.error("SYNC_BATCH: Store %d not found. Rejecting batch.", payload.store_id)
        raise HTTPException(status_code=404, detail="Store branch not found")

    synced_uuids = []

    for sale_in in payload.sales:
        # Financial validation: prevent negative sales or invalid amounts
        if sale_in.total_amount < 0 or sale_in.subtotal < 0 or sale_in.discount_amount < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid financial amount in transaction {sale_in.transaction_uuid}: negative totals not allowed."
            )

        # Check if transaction already exists in Postgres
        existing = db.query(models.SaleTransaction).filter(
            models.SaleTransaction.transaction_uuid == sale_in.transaction_uuid
        ).first()

        if existing:
            if existing.store_id != payload.store_id:
                logger.error(
                    "SYNC_BATCH: UUID collision for %s: existing store_id=%d, requested store_id=%d",
                    sale_in.transaction_uuid, existing.store_id, payload.store_id
                )
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"Transaction UUID already belongs to store {existing.store_id}.",
                )
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

        items_for_fiscal = []
        for item_in in sale_in.items:
            if item_in.quantity <= 0 or item_in.price_at_sale < 0:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid sale item quantity ({item_in.quantity}) or price ({item_in.price_at_sale})"
                )

            # FK-safe product resolution: map local Isar ID to PostgreSQL ID
            resolved_product_id = _resolve_product_id(
                db, payload.store_id, item_in.product_id, item_in.product_name
            )
            if item_in.product_id and not resolved_product_id:
                logger.info(
                    "SYNC_BATCH: Product ID %d ('%s') not found in store %d — storing without FK.",
                    item_in.product_id, item_in.product_name, payload.store_id
                )

            item = models.SaleItem(
                sale_transaction_id=tx.id,
                product_id=resolved_product_id,
                product_name=item_in.product_name,
                price_at_sale=item_in.price_at_sale,
                unit_cost_at_sale=item_in.unit_cost_at_sale,
                quantity=item_in.quantity,
                tax_rate_at_sale=item_in.tax_rate_at_sale,
                is_tax_inclusive_at_sale=item_in.is_tax_inclusive_at_sale,
            )
            db.add(item)

            # Resolve ZRA tax code: use value from client if provided, else look up
            # the product record; fall back to 'C' (Exempt) if tax_rate==0 else 'A' (16%)
            resolved_tax_code = item_in.zra_tax_code if item_in.zra_tax_code else None

            # Deduct stock level in cloud PostgreSQL database and resolve tax code
            product_rec = None
            if resolved_product_id:
                product_rec = db.query(models.Product).filter(
                    models.Product.id == resolved_product_id,
                    models.Product.store_id == payload.store_id
                ).first()
                if product_rec:
                    product_rec.stock_level = max(0, product_rec.stock_level - item_in.quantity)
                    if not resolved_tax_code:
                        resolved_tax_code = product_rec.zra_tax_code if product_rec.zra_tax_code else None

            if not resolved_tax_code:
                resolved_tax_code = "C" if float(item_in.tax_rate_at_sale or 0) == 0 else "A"

            items_for_fiscal.append({
                "product_id": item_in.product_id,
                "product_name": item_in.product_name,
                "price_at_sale": float(item_in.price_at_sale),
                "quantity": item_in.quantity,
                "zra_tax_code": resolved_tax_code,
                "tax_rate_at_sale": float(item_in.tax_rate_at_sale),
            })

        # Auto-fiscalize via DigiTax on cloud backend if API key configured and transaction not yet fiscalized
        if store.digitax_api_key and store.digitax_api_key.strip():
            try:
                store_config = {
                    "digitax_api_key": store.digitax_api_key,
                    "digitax_environment": store.digitax_environment,
                    "tpin": store.tpin or "1000000000",
                    "sdc_id": store.sdc_id or "SDC-ZM-001",
                    "bhf_id": store.bhf_id or "00",
                }
                tx_dict = {
                    "transaction_uuid": tx.transaction_uuid,
                    "total_amount": float(tx.total_amount),
                    "cashier_id": tx.cashier_id,
                    "cashier_name": tx.cashier_name,
                }
                res = DigiTaxZraService.fiscalize_sale_invoice(store_config, tx_dict, items_for_fiscal)
                if res and res.get("zra_receipt_number"):
                    tx.zra_receipt_number = res.get("zra_receipt_number")
                    tx.zra_mark_id = res.get("zra_mark_id")
                    tx.zra_qr_code = res.get("zra_qr_code")
                    tx.zra_status = "APPROVED"
                    if res.get("tax_amount") is not None:
                        tx.tax_amount = res["tax_amount"]
                    if res.get("subtotal") is not None and res["subtotal"] > 0:
                        tx.subtotal = res["subtotal"]
            except Exception as e:
                print(f"Backend auto-fiscalize notice for {tx.transaction_uuid}: {e}")

        synced_uuids.append(sale_in.transaction_uuid)

    try:
        db.commit()
    except Exception:
        db.rollback()
        logger.exception(
            "SYNC_BATCH: Commit failed for store_id=%d (user=%s); batch was rolled back",
            payload.store_id, current_user.numeric_id
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Branch data was not stored. Retry the same batch; no records were committed.",
        )
    logger.info(
        "SYNC_BATCH: Committed %d transactions for store_id=%d (user=%s)",
        len(synced_uuids), payload.store_id, current_user.numeric_id
    )
    return {"status": "success", "synced_uuids": synced_uuids}

@router.get("/export-backup")
def export_vps_backup(
    store_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Exports a complete backup snapshot of the VPS cloud database for a given store (or organization stores for owner).
    Enforces strict organization (TPIN) scoping on server side.
    """
    verify_store_access(store_id, current_user, db)

    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    user_tpin = (user_store.tpin or "").strip() if user_store else ""

    if current_user.role in ["owner", "super_admin"] and (store_id == 0 or user_tpin):
        org_query = db.query(models.Store)
        if current_user.role != "super_admin" and user_tpin:
            org_query = org_query.filter(models.Store.tpin == user_tpin)
        org_stores = org_query.all()
        org_store_ids = [s.id for s in org_stores]
        store = db.query(models.Store).filter(models.Store.id == store_id, models.Store.id.in_(org_store_ids)).first() or (org_stores[0] if org_stores else None)
        if not store:
            raise HTTPException(status_code=404, detail="Store branch not found in organization")

        users = db.query(models.User).filter(models.User.store_id.in_(org_store_ids)).all()
        categories = db.query(models.Category).filter(models.Category.store_id.in_(org_store_ids)).all()
        products = db.query(models.Product).filter(models.Product.store_id.in_(org_store_ids)).all()
        sales = db.query(models.SaleTransaction).filter(models.SaleTransaction.store_id.in_(org_store_ids)).all()
        customers = db.query(models.Customer).filter(models.Customer.store_id.in_(org_store_ids)).all()
        stock_movements = db.query(models.StockMovement).filter(models.StockMovement.store_id.in_(org_store_ids)).all()
    else:
        store = db.query(models.Store).filter(models.Store.id == store_id).first()
        if not store:
            raise HTTPException(status_code=404, detail="Store branch not found")

        users = db.query(models.User).filter(models.User.store_id == store_id).all()
        categories = db.query(models.Category).filter(models.Category.store_id == store_id).all()
        products = db.query(models.Product).filter(models.Product.store_id == store_id).all()
        sales = db.query(models.SaleTransaction).filter(models.SaleTransaction.store_id == store_id).all()
        customers = db.query(models.Customer).filter(models.Customer.store_id == store_id).all()
        stock_movements = db.query(models.StockMovement).filter(models.StockMovement.store_id == store_id).all()

    def serialize_obj(obj):
        if obj is None:
            return None
        d = {}
        for column in obj.__table__.columns:
            val = getattr(obj, column.name)
            if hasattr(val, 'isoformat'):
                val = val.isoformat()
            elif isinstance(val, (int, float, str, bool, list, dict, type(None))):
                pass
            else:
                val = str(val)
            d[column.name] = val
        return d

    sales_data = []
    for s in sales:
        s_dict = serialize_obj(s)
        items = db.query(models.SaleItem).filter(models.SaleItem.sale_transaction_id == s.id).all()
        s_dict["items"] = [serialize_obj(i) for i in items]
        sales_data.append(s_dict)

    backup_payload = {
        "backup_version": "1.0",
        "exported_at": str(db.query(func.now()).scalar() or ""),
        "store": serialize_obj(store),
        "stores": [serialize_obj(s) for s in org_stores] if current_user.role in ["owner", "super_admin"] and (store_id == 0 or user_tpin) else [serialize_obj(store)],
        "users": [serialize_obj(u) for u in users],
        "categories": [serialize_obj(c) for c in categories],
        "products": [serialize_obj(p) for p in products],
        "sales": sales_data,
        "customers": [serialize_obj(cust) for cust in customers],
        "stock_movements": [serialize_obj(sm) for sm in stock_movements],
    }

    return backup_payload

