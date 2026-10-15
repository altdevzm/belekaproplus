from fastapi import APIRouter, Depends, HTTPException, Request, Header, status
from sqlalchemy.orm import Session
from typing import Optional, Dict, Any, List
import json
import logging

from app.database import get_db
from app import models, schemas
from app.services.lenco_service import LencoService
from app.auth_deps import get_current_user, verify_store_access

logger = logging.getLogger("lenco_router")

router = APIRouter(prefix="/api/v1/lenco", tags=["Lenco Payment Gateway & Banking"])

@router.get("/banks")
def list_banks(
    store_id: Optional[int] = None,
    country: str = "zm",
    db: Session = Depends(get_db),
):
    """
    Get list of banks and financial institutions (default: Zambia).
    Uses store's configured API key if available, or official bank catalog.
    """
    api_key = None
    if store_id:
        store = db.query(models.Store).filter(models.Store.id == store_id).first()
        if store and store.lenco_api_key:
            api_key = store.lenco_api_key

    # If no key found for requested store, check any configured store with an active key
    if not api_key:
        active_store = db.query(models.Store).filter(
            models.Store.lenco_api_key != None,
            models.Store.lenco_api_key != "",
        ).first()
        if active_store:
            api_key = active_store.lenco_api_key

    banks = LencoService.get_banks(country=country, api_key=api_key)
    return {"status": True, "data": banks}

@router.post("/resolve-bank-account", response_model=schemas.LencoResolveBankResponse)
def resolve_bank_account(
    req: schemas.LencoResolveBankRequest,
    db: Session = Depends(get_db),
):
    """
    Auto-resolve bank account number and bank ID to retrieve the account holder's name.
    Called on POS when selecting customer's bank of choice and entering the account number.
    """
    api_key = None
    if req.store_id:
        store = db.query(models.Store).filter(models.Store.id == req.store_id).first()
        if store and store.lenco_api_key:
            api_key = store.lenco_api_key

    res = LencoService.resolve_bank_account(
        account_number=req.account_number,
        bank_id=req.bank_id,
        country=req.country or "zm",
        api_key=api_key,
    )

    if not res.get("status"):
        return schemas.LencoResolveBankResponse(
            status=False,
            message=res.get("message", "Unable to resolve account"),
        )

    data = res.get("data") or {}
    bank_info = data.get("bank") or {}

    return schemas.LencoResolveBankResponse(
        status=True,
        message="Account resolved successfully",
        account_name=data.get("accountName"),
        account_number=data.get("accountNumber"),
        bank_name=bank_info.get("name"),
        bank_id=bank_info.get("id"),
    )

@router.post("/resolve-mobile-money")
def resolve_mobile_money(
    req: schemas.LencoResolveMoMoRequest,
    db: Session = Depends(get_db),
):
    """Resolve customer mobile money phone number."""
    api_key = None
    if req.store_id:
        store = db.query(models.Store).filter(models.Store.id == req.store_id).first()
        if store and store.lenco_api_key:
            api_key = store.lenco_api_key

    return LencoService.resolve_mobile_money(
        phone=req.phone,
        operator=req.operator,
        country=req.country or "zm",
        api_key=api_key,
    )

@router.post("/collect/mobile-money")
def initiate_mobile_money_collection(
    req: schemas.LencoMobileMoneyRequest,
    db: Session = Depends(get_db),
):
    """
    Initiate Mobile Money collection from customer.
    Customer receives USSD/push prompt on phone to enter PIN/password.
    """
    store = db.query(models.Store).filter(models.Store.id == req.store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    res = LencoService.initiate_mobile_money_collection(
        amount=req.amount,
        reference=req.reference,
        phone=req.phone,
        operator=req.operator,
        country=req.country or "zm",
        bearer=req.bearer or "merchant",
        api_key=store.lenco_api_key,
    )

    # If matching transaction exists, update its Lenco metadata
    tx = db.query(models.SaleTransaction).filter(
        models.SaleTransaction.transaction_uuid == req.reference,
        models.SaleTransaction.store_id == req.store_id,
    ).first()

    if tx:
        tx.lenco_reference = req.reference
        tx.lenco_status = "pay-offline"
        tx.payment_method = "MOBILE MONEY"
        tx.payment_details = {
            "phone": req.phone,
            "operator": req.operator,
            "gateway": "lenco",
        }
        db.commit()

    return res

@router.get("/status/{reference}")
def get_payment_status(
    reference: str,
    store_id: Optional[int] = None,
    db: Session = Depends(get_db),
):
    """
    Check collection status from Lenco API and update database record.
    """
    api_key = None
    store = None
    if store_id:
        store = db.query(models.Store).filter(models.Store.id == store_id).first()
        if store and store.lenco_api_key:
            api_key = store.lenco_api_key

    res = LencoService.get_collection_status(reference=reference, api_key=api_key)
    
    # Check if we should update local transaction
    if res.get("status") and res.get("data"):
        data = res["data"]
        remote_status = data.get("status")
        
        query = db.query(models.SaleTransaction).filter(
            (models.SaleTransaction.transaction_uuid == reference) |
            (models.SaleTransaction.lenco_reference == reference)
        )
        if store_id:
            query = query.filter(models.SaleTransaction.store_id == store_id)
        
        tx = query.first()
        if tx and remote_status:
            tx.lenco_status = remote_status
            if remote_status == "successful":
                tx.status = "completed"
            db.commit()

    return res

@router.get("/store-accounts")
def get_store_lenco_accounts(
    store_id: int,
    db: Session = Depends(get_db),
):
    """Retrieve the store's configured Lenco bank account details for direct bank transfers."""
    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    if not store.lenco_api_key:
        return {
            "status": True,
            "message": "Demo mode (no API key configured)",
            "data": [
                {
                    "id": "demo-acc-1",
                    "details": {
                        "accountName": store.name or "Beleka Store Account",
                        "accountNumber": "9130001234567",
                        "bank": "Absa Bank Zambia",
                    },
                    "currency": store.currency_symbol or "ZMW",
                    "availableBalance": "0.00",
                }
            ],
        }

    return LencoService.get_accounts(api_key=store.lenco_api_key)

@router.post("/test-credentials")
def test_lenco_credentials(
    req: schemas.LencoTestCredentialsRequest,
):
    """Test validity of a Lenco API Token."""
    # If in sandbox mode and using mock/testing token
    if req.environment == "sandbox" and (
        not req.api_key or any(req.api_key.strip().lower().startswith(p) for p in ["sandbox", "demo", "test"])
    ):
        return {
            "status": True,
            "message": "Connected to Lenco Sandbox (Simulated Mode)",
            "accounts": [
                {
                    "id": "sandbox-demo-1",
                    "details": {
                        "accountName": "Beleka Demo Sandbox Account",
                        "accountNumber": "9130001234567",
                        "bank": "Absa Bank Zambia",
                    },
                    "currency": "ZMW",
                    "availableBalance": "50000.00",
                }
            ],
        }

    res = LencoService.get_accounts(api_key=req.api_key)
    if res.get("status"):
        return {
            "status": True,
            "message": "Lenco API connection successful! Authenticated with merchant account.",
            "accounts": res.get("data", []),
        }
    return {
        "status": False,
        "message": res.get("message", "Authentication failed. Please verify your Lenco API Token in your Lenco Dashboard."),
    }

@router.post("/webhook")
async def universal_lenco_webhook(
    request: Request,
    x_lenco_signature: Optional[str] = Header(None, alias="X-Lenco-Signature"),
    db: Session = Depends(get_db),
):
    """
    Universal multi-tenant webhook endpoint for Lenco.
    Lenco sends events here (collection.successful, collection.failed, transaction.credit).
    Dispatches directly to the matching tenant store and transaction.
    """
    raw_body = await request.body()
    try:
        payload = json.loads(raw_body.decode("utf-8"))
    except Exception:
        payload = {}

    event = payload.get("event")
    data = payload.get("data") or {}
    reference = data.get("reference") or data.get("lencoReference")

    logger.info(f"Lenco universal webhook received: event={event}, reference={reference}")

    # Optional signature verification across active stores
    # In multi-tenant, if a signature header is present, we check matching stores
    is_verified = True
    if x_lenco_signature:
        stores = db.query(models.Store).filter(
            models.Store.lenco_api_key.isnot(None),
            models.Store.lenco_enabled == True
        ).all()
        matched = False
        for s in stores:
            if LencoService.verify_webhook_signature(raw_body, x_lenco_signature, s.lenco_api_key):
                matched = True
                break
        if stores and not matched:
            logger.warning("Webhook signature mismatch for incoming Lenco event")
            # In production log warning; we still process if reference matches a real transaction

    # Process events
    if event == "collection.successful" and reference:
        tx = db.query(models.SaleTransaction).filter(
            (models.SaleTransaction.transaction_uuid == reference) |
            (models.SaleTransaction.lenco_reference == reference)
        ).first()
        if tx:
            tx.lenco_status = "successful"
            tx.status = "completed"
            db.commit()
            logger.info(f"Sale transaction {tx.transaction_uuid} marked COMPLETED via Lenco webhook")

    elif event == "collection.failed" and reference:
        tx = db.query(models.SaleTransaction).filter(
            (models.SaleTransaction.transaction_uuid == reference) |
            (models.SaleTransaction.lenco_reference == reference)
        ).first()
        if tx:
            tx.lenco_status = "failed"
            db.commit()

    elif event == "transaction.credit":
        # Bank Transfer credited to store's Lenco account!
        # Match by reference in narration or explicit reference
        narration = data.get("narration", "")
        account_id = data.get("accountId")
        logger.info(f"Lenco bank account credited: accountId={account_id}, narration={narration}")

    # Lenco expects HTTP 200 OK
    return {"status": True, "message": "Webhook received and processed successfully"}
