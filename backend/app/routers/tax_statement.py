"""
ZRA Tax Payment Statement API
Returns actual computed tax figures the business owes to ZRA for a given month,
scoped strictly to the business's registered tax type.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func, extract
from datetime import date, datetime
import calendar
import logging

from app.database import get_db
from app import models
from app.auth_deps import get_current_user, verify_store_access

logger = logging.getLogger("tax_statement")

router = APIRouter(prefix="/api/v1/tax-statement", tags=["ZRA Tax Statement"])

# ── ZRA Constants ──────────────────────────────────────────────────────────────
VAT_RATE = 16.0          # %
TOT_RATE = 5.0           # %
TOT_THRESHOLD = 1000.00  # monthly (K12,000 annual exemption limit)
SDL_RATE = 0.005         # 0.5% of gross payroll
WHT_RATE = 0.15          # 15% on eligible service/rental payments


def _due_date(charge_year: int, charge_month: int, due_day: int) -> date:
    m = charge_month + 1
    y = charge_year
    if m > 12:
        m = 1
        y += 1
    return date(y, m, due_day)


def _month_label(year: int, month: int) -> str:
    return f"{calendar.month_name[month]} {year}"


def _vat_figures(db: Session, store_id: int, year: int, month: int) -> dict:
    items = (
        db.query(
            models.SaleItem.price_at_sale,
            models.SaleItem.quantity,
            models.SaleItem.tax_rate_at_sale,
            models.SaleItem.is_tax_inclusive_at_sale,
            models.SaleItem.is_refunded,
        )
        .join(models.SaleTransaction, models.SaleItem.sale_transaction_id == models.SaleTransaction.id)
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
            extract("month", models.SaleTransaction.timestamp) == month,
            models.SaleItem.is_refunded == False,
        )
        .all()
    )

    gross_sales = 0.0
    output_vat = 0.0
    net_sales_ex_vat = 0.0

    for item in items:
        line = round(float(item.price_at_sale) * int(item.quantity), 2)
        rate = float(item.tax_rate_at_sale or 0.0)
        gross_sales += line
        if rate > 0:
            if item.is_tax_inclusive_at_sale:
                # DigiTax / ZRA standard line-level formula:
                taxable_base = round(line / (1.0 + (rate / 100.0)), 2)
                vat = round(line - taxable_base, 2)
                output_vat += vat
                net_sales_ex_vat += taxable_base
            else:
                vat = round(line * (rate / 100.0), 2)
                output_vat += vat
                net_sales_ex_vat += line
        else:
            net_sales_ex_vat += line

    po_total = float(
        db.query(func.coalesce(func.sum(models.PurchaseOrder.total_amount), 0))
        .filter(
            models.PurchaseOrder.store_id == store_id,
            models.PurchaseOrder.status == "received",
            extract("year", models.PurchaseOrder.created_at) == year,
            extract("month", models.PurchaseOrder.created_at) == month,
        )
        .scalar() or 0.0
    )
    taxable_po = round(po_total / (1.0 + (VAT_RATE / 100.0)), 2)
    input_vat = round(po_total - taxable_po, 2)
    net_purchases_ex_vat = taxable_po

    net_vat_payable = max(0.0, output_vat - input_vat)
    vat_refund_claim = max(0.0, input_vat - output_vat)

    return {
        "gross_sales_inclusive": round(gross_sales, 2),
        "taxable_sales_ex_vat": round(net_sales_ex_vat, 2),
        "output_vat": round(output_vat, 2),
        "total_purchases_inclusive": round(po_total, 2),
        "net_purchases_ex_vat": round(net_purchases_ex_vat, 2),
        "input_vat": round(input_vat, 2),
        "net_vat_payable": round(net_vat_payable, 2),
        "vat_refund_claim": round(vat_refund_claim, 2),
        "vat_rate_percent": VAT_RATE,
        "due_day": 18,
    }


def _tot_figures(db: Session, store_id: int, year: int, month: int) -> dict:
    gross_turnover = float(
        db.query(func.coalesce(func.sum(models.SaleTransaction.total_amount), 0))
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
            extract("month", models.SaleTransaction.timestamp) == month,
        )
        .scalar() or 0.0
    )

    if gross_turnover <= TOT_THRESHOLD:
        tot_rate = 0.0
        tot_amount = 0.0
    else:
        tot_rate = TOT_RATE
        tot_amount = round(gross_turnover * TOT_RATE / 100.0, 2)

    ytd = float(
        db.query(func.coalesce(func.sum(models.SaleTransaction.total_amount), 0))
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
            extract("month", models.SaleTransaction.timestamp) <= month,
        )
        .scalar() or 0.0
    )

    return {
        "gross_turnover": round(gross_turnover, 2),
        "tot_threshold": TOT_THRESHOLD,
        "tot_rate_percent": tot_rate,
        "tot_amount": tot_amount,
        "ytd_turnover": round(ytd, 2),
        "annual_limit": 5_000_000.00,
        "over_annual_limit": ytd > 5_000_000.00,
        "threshold_warning_80pct": ytd > 4_000_000.00,
        "nil_return": tot_amount == 0.0,
        "due_day": 14,
    }


@router.get("/monthly/{store_id}", summary="ZRA Monthly Tax Payment Statement")
def get_monthly_tax_statement(
    store_id: int,
    year: int,
    month: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns actual ZRA tax figures the business owes for the given month (tenant-scoped).
    """
    verify_store_access(store_id, current_user, db)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    tax_type = store.business_tax_type or "VAT_STANDARD"
    month_label = _month_label(year, month)
    taxes = []

    if tax_type == "TURNOVER_TAX":
        tot = _tot_figures(db, store_id, year, month)
        filed = db.query(models.TotReturn).filter(
            models.TotReturn.store_id == store_id,
            models.TotReturn.charge_year == year,
            models.TotReturn.charge_month == month,
        ).first()
        taxes.append({
            "tax_code": "TOT",
            "tax_name": "Turnover Tax (TOT)",
            "description": f"5% on gross monthly turnover above K{TOT_THRESHOLD:,.0f}",
            "gross_sales": tot["gross_turnover"],
            "taxable_base": tot["gross_turnover"],
            "rate_percent": tot["tot_rate_percent"],
            "amount_payable": tot["tot_amount"],
            "nil_return": tot["nil_return"],
            "due_date": _due_date(year, month, 14).isoformat(),
            "due_day": 14,
            "is_filed": filed is not None,
            "filed_status": filed.status if filed else None,
            "filed_reference": filed.digitax_reference if filed else None,
            "supplemental": {
                "ytd_turnover": tot["ytd_turnover"],
                "annual_limit": tot["annual_limit"],
                "over_annual_limit": tot["over_annual_limit"],
                "threshold_warning_80pct": tot["threshold_warning_80pct"],
            },
        })

    if tax_type in ("VAT_STANDARD", "COMPOSITE"):
        vat = _vat_figures(db, store_id, year, month)
        taxes.append({
            "tax_code": "VAT",
            "tax_name": "Value Added Tax (VAT) — Suppliers",
            "description": "16% VAT on taxable supplies (Output VAT less Input VAT)",
            "gross_sales": vat["gross_sales_inclusive"],
            "taxable_base": vat["taxable_sales_ex_vat"],
            "rate_percent": VAT_RATE,
            "output_vat": vat["output_vat"],
            "input_vat": vat["input_vat"],
            "amount_payable": vat["net_vat_payable"],
            "vat_refund_claim": vat["vat_refund_claim"],
            "nil_return": vat["net_vat_payable"] == 0.0 and vat["vat_refund_claim"] == 0.0,
            "due_date": _due_date(year, month, 18).isoformat(),
            "due_day": 18,
            "is_filed": False,
            "supplemental": {
                "total_purchases_inclusive": vat["total_purchases_inclusive"],
                "net_purchases_ex_vat": vat["net_purchases_ex_vat"],
            },
        })

    total_auto_computed = sum(
        t["amount_payable"] for t in taxes
        if t["amount_payable"] is not None
    )

    return {
        "store_id": store_id,
        "store_name": store.name,
        "tpin": store.tpin or "Not Set",
        "bhf_id": store.bhf_id or "00",
        "business_tax_type": tax_type,
        "charge_year": year,
        "charge_month": month,
        "month_label": month_label,
        "generated_at": datetime.utcnow().isoformat(),
        "total_auto_computed_payable": round(total_auto_computed, 2),
        "taxes": taxes,
        "zra_filing_reference_url": "https://www.zra.org.zm",
    }
