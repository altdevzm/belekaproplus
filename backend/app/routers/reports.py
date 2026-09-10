from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional
from app.database import get_db
from app import models
from app.auth_deps import get_current_user, verify_store_access

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])

@router.get("/summary")
def get_sales_summary(
    store_id: Optional[int] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get aggregated sales, revenue, gross profit, and transaction count.
    If owner/super_admin passes store_id=0 or omits store_id, aggregates across ALL branches
    and returns a per-store breakdown.
    """
    is_admin = current_user.role in ["owner", "super_admin"]
    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    user_tpin = (user_store.tpin or "").strip() if user_store else ""

    if is_admin and current_user.role != "super_admin" and not user_tpin:
        raise HTTPException(
            status_code=403,
            detail="Organization TPIN is not configured for this account.",
        )
    
    if is_admin and (store_id is None or store_id == 0):
        # Query stores belonging to this organization (TPIN)
        if current_user.role != "super_admin" and user_tpin:
            org_stores = db.query(models.Store).filter(models.Store.tpin == user_tpin).all()
        else:
            org_stores = db.query(models.Store).all()

        org_store_ids = [s.id for s in org_stores]

        # Aggregate across all stores for this organization
        total_query = db.query(
            func.count(models.SaleTransaction.id).label("total_transactions"),
            func.coalesce(func.sum(models.SaleTransaction.total_amount), 0).label("total_revenue"),
            func.coalesce(func.sum(models.SaleTransaction.gross_profit), 0).label("total_profit"),
            func.coalesce(func.sum(models.SaleTransaction.tax_amount), 0).label("total_tax")
        ).filter(models.SaleTransaction.store_id.in_(org_store_ids)).first()

        # Breakdown per store within organization
        by_store = []
        for s in org_stores:
            s_query = db.query(
                func.count(models.SaleTransaction.id).label("total_transactions"),
                func.coalesce(func.sum(models.SaleTransaction.total_amount), 0).label("total_revenue"),
                func.coalesce(func.sum(models.SaleTransaction.gross_profit), 0).label("total_profit"),
                func.coalesce(func.sum(models.SaleTransaction.tax_amount), 0).label("total_tax")
            ).filter(models.SaleTransaction.store_id == s.id).first()
            
            by_store.append({
                "store_id": s.id,
                "store_code": s.store_code,
                "store_name": s.name,
                "total_transactions": s_query.total_transactions or 0,
                "total_revenue": float(s_query.total_revenue or 0),
                "total_profit": float(s_query.total_profit or 0),
                "total_tax": float(s_query.total_tax or 0),
            })

        return {
            "store_id": 0,  # 0 indicates HQ multi-store aggregate
            "total_transactions": total_query.total_transactions or 0,
            "total_revenue": float(total_query.total_revenue or 0),
            "total_profit": float(total_query.total_profit or 0),
            "total_tax": float(total_query.total_tax or 0),
            "by_store": by_store,
        }

    target_store_id = store_id or current_user.store_id
    verify_store_access(target_store_id, current_user, db)

    query = db.query(
        func.count(models.SaleTransaction.id).label("total_transactions"),
        func.coalesce(func.sum(models.SaleTransaction.total_amount), 0).label("total_revenue"),
        func.coalesce(func.sum(models.SaleTransaction.gross_profit), 0).label("total_profit"),
        func.coalesce(func.sum(models.SaleTransaction.tax_amount), 0).label("total_tax")
    ).filter(models.SaleTransaction.store_id == target_store_id)

    result = query.first()

    return {
        "store_id": target_store_id,
        "total_transactions": result.total_transactions or 0,
        "total_revenue": float(result.total_revenue or 0),
        "total_profit": float(result.total_profit or 0),
        "total_tax": float(result.total_tax or 0),
    }
