from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Dict, Any
from app.database import get_db
from app import models
from app.services.digitax_service import DigiTaxZraService

router = APIRouter(prefix="/api/v1/zra", tags=["ZRA Smart Invoice & DigiTax"])

@router.get("/tax-codes")
@router.get("/tax-rates")
def get_zra_tax_rates(api_key: str = None, env: str = "sandbox"):
    """
    Fetch official ZRA tax category codes and rates directly from DigiTax.
    """
    return DigiTaxZraService.fetch_tax_rates(api_key=api_key, env=env)

@router.post("/fiscalize-sale")
def fiscalize_transaction(
    store_id: int,
    transaction_uuid: str,
    db: Session = Depends(get_db)
):
    """
    Fiscalize a sale transaction through DigiTax API -> ZRA VSDC servers.
    Updates PostgreSQL sale transaction with ZRA SDC Receipt Number, Mark ID, and QR Code.
    """
    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store branch not found")

    tx = db.query(models.SaleTransaction).filter(
        models.SaleTransaction.transaction_uuid == transaction_uuid
    ).first()

    if not tx:
        raise HTTPException(status_code=404, detail="Sale transaction not found")

    # Fetch items for transaction
    items = db.query(models.SaleItem).filter(models.SaleItem.sale_transaction_id == tx.id).all()
    items_list = []
    for item in items:
        prod = db.query(models.Product).filter(models.Product.id == item.product_id).first()
        items_list.append({
            "product_id": item.product_id,
            "product_name": item.product_name,
            "price_at_sale": float(item.price_at_sale),
            "quantity": item.quantity,
            "zra_tax_code": prod.zra_tax_code if prod else "A",
            "item_cls_cd": prod.item_cls_cd if prod else "10101501",
            "tax_rate_at_sale": float(item.tax_rate_at_sale),
        })

    store_config = {
        "digitax_api_key": store.digitax_api_key,
        "digitax_environment": store.digitax_environment,
        "tpin": store.tpin or "1000000000",
        "sdc_id": store.sdc_id or "SDC-ZM-001",
    }

    tx_dict = {
        "transaction_uuid": tx.transaction_uuid,
        "total_amount": float(tx.total_amount),
        "cashier_id": tx.cashier_id,
        "cashier_name": tx.cashier_name,
    }

    result = DigiTaxZraService.fiscalize_sale_invoice(store_config, tx_dict, items_list)

    # Save ZRA fiscal metadata to PostgreSQL
    tx.zra_receipt_number = result["zra_receipt_number"]
    tx.zra_mark_id = result["zra_mark_id"]
    tx.zra_qr_code = result["zra_qr_code"]
    tx.zra_status = "APPROVED"
    db.commit()

    return result

@router.post("/stock-movement")
def sync_stock_movement(
    store_id: int,
    branch_code: str,
    item_code: str,
    item_name: str,
    quantity: float,
    movement_type: str = "01",
    unit_cost: float = 0.0,
    selling_price: float = 0.0,
    tax_code: str = "A",
    db: Session = Depends(get_db)
):
    """
    Sync an isolated branch stock movement to DigiTax VSDC under the company API key.
    """
    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    store_config = {
        "digitax_api_key": store.digitax_api_key if store else None,
        "digitax_environment": store.digitax_environment if store else "sandbox",
        "tpin": store.tpin if store else "1000000000",
    }

    return DigiTaxZraService.sync_stock_movement(
        store_config=store_config,
        branch_code=branch_code,
        item_code=item_code,
        item_name=item_name,
        quantity=quantity,
        movement_type=movement_type,
        unit_cost=unit_cost,
        selling_price=selling_price,
        tax_code=tax_code
    )

@router.post("/items/save")
def save_digitax_item(
    payload: Dict[str, Any],
    api_key: Optional[str] = None,
    env: str = "sandbox",
    tpin: str = "1000000000",
    bhf_id: str = "00",
):
    """
    Register or update an item on DigiTax / ZRA Smart Invoice VSDC.
    """
    store_config = {
        "digitax_api_key": api_key,
        "digitax_environment": env,
        "tpin": tpin,
        "bhf_id": bhf_id,
    }
    return DigiTaxZraService.save_item(store_config, payload)

@router.post("/items/batch-sync")
def batch_sync_digitax_items(
    payload: Dict[str, Any],
    api_key: Optional[str] = None,
    env: str = "sandbox",
    tpin: str = "1000000000",
    bhf_id: str = "00",
):
    """
    Batch sync products catalog and stock levels to DigiTax VSDC.
    """
    store_config = {
        "digitax_api_key": api_key or payload.get("api_key"),
        "digitax_environment": env or payload.get("environment", "sandbox"),
        "tpin": tpin or payload.get("tpin", "1000000000"),
        "bhf_id": bhf_id or payload.get("bhf_id", "00"),
    }
    items_list = payload.get("items", [])
    branch_code = payload.get("branch_code", bhf_id)
    return DigiTaxZraService.batch_sync_items(store_config, items_list, branch_code)

@router.get("/items")
def get_digitax_remote_items(
    api_key: Optional[str] = None,
    env: str = "sandbox",
    bhf_id: str = "00",
):
    """
    Pull items from DigiTax VSDC down to POS.
    """
    store_config = {
        "digitax_api_key": api_key,
        "digitax_environment": env,
        "bhf_id": bhf_id,
    }
    return DigiTaxZraService.fetch_remote_items(store_config, bhf_id)
