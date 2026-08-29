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
    Get aggregated sales, revenue, gross profit, and transaction count (tenant-scoped).
    """
    target_store_id = store_id or current_user.store_id
    verify_store_access(target_store_id, current_user)

    query = db.query(
        func.count(models.SaleTransaction.id).label("total_transactions"),
        func.coalesce(func.sum(models.SaleTransaction.total_amount), 0).label("total_revenue"),
        func.coalesce(func.sum(models.SaleTransaction.gross_profit), 0).label("total_profit"),
        func.coalesce(func.sum(models.SaleTransaction.tax_amount), 0).label("total_tax")
    ).filter(models.SaleTransaction.store_id == target_store_id)

    result = query.first()

    return {
        "store_id": target_store_id,
        "total_transactions": result.total_transactions,
        "total_revenue": float(result.total_revenue),
        "total_profit": float(result.total_profit),
        "total_tax": float(result.total_tax),
    }
