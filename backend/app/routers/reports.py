from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional
from app.database import get_db
from app import models

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])

@router.get("/summary")
def get_sales_summary(
    store_id: Optional[int] = None,
    db: Session = Depends(get_db)
):
    """
    Get aggregated sales, revenue, gross profit, and transaction count.
    Can be filtered by store_id or aggregated across all stores.
    """
    query = db.query(
        func.count(models.SaleTransaction.id).label("total_transactions"),
        func.coalesce(func.sum(models.SaleTransaction.total_amount), 0).label("total_revenue"),
        func.coalesce(func.sum(models.SaleTransaction.gross_profit), 0).label("total_profit"),
        func.coalesce(func.sum(models.SaleTransaction.tax_amount), 0).label("total_tax")
    )

    if store_id:
        query = query.filter(models.SaleTransaction.store_id == store_id)

    result = query.first()

    return {
        "store_id": store_id or "all_stores",
        "total_transactions": result.total_transactions,
        "total_revenue": float(result.total_revenue),
        "total_profit": float(result.total_profit),
        "total_tax": float(result.total_tax),
    }
