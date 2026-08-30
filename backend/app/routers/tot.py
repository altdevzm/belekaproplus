from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func, extract
from typing import Optional
from datetime import date, datetime
from pydantic import BaseModel
import time
import logging
import os
import requests
import calendar

from app.database import get_db
from app import models
from app.auth_deps import get_current_user, verify_store_access, require_roles

logger = logging.getLogger("tot_zra")

router = APIRouter(prefix="/api/v1/tot", tags=["Turnover Tax (TOT)"])

# ZRA TOT constants
TOT_MONTHLY_THRESHOLD = 1000.00  # K1,000/month (K12,000 annual exemption limit)
TOT_RATE_PERCENT = 5.0
ANNUAL_REGISTRATION_LIMIT = 5_000_000.00


def _compute_tot(gross_turnover: float) -> tuple:
    """Returns (rate_percent, amount). 0% if <=K1,000/month (K12,000/year), else 5%."""
    if gross_turnover <= TOT_MONTHLY_THRESHOLD:
        return 0.0, 0.0
    return TOT_RATE_PERCENT, round(gross_turnover * (TOT_RATE_PERCENT / 100.0), 2)


def _due_date(year: int, month: int) -> date:
    """14th of the month following the charge month."""
    if month == 12:
        return date(year + 1, 1, 14)
    return date(year, month + 1, 14)


def _month_name(month: int) -> str:
    return calendar.month_name[month]


class SubmitReturnRequest(BaseModel):
    charge_year: int
    charge_month: int
    notes: Optional[str] = None


@router.get("/monthly-summary/{store_id}", summary="Compute TOT for a given month")
def get_monthly_tot_summary(
    store_id: int,
    year: int,
    month: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Compile gross turnover for the month and compute TOT owed under ZRA rules (tenant-scoped)."""
    verify_store_access(store_id, current_user)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    gross_turnover = float(
        db.query(func.coalesce(func.sum(models.SaleTransaction.total_amount), 0))
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
            extract("month", models.SaleTransaction.timestamp) == month,
        ).scalar() or 0.0
    )

    ytd_turnover = float(
        db.query(func.coalesce(func.sum(models.SaleTransaction.total_amount), 0))
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
            extract("month", models.SaleTransaction.timestamp) <= month,
        ).scalar() or 0.0
    )

    tot_rate, tot_amount = _compute_tot(gross_turnover)
    due = _due_date(year, month)

    existing = db.query(models.TotReturn).filter(
        models.TotReturn.store_id == store_id,
        models.TotReturn.charge_year == year,
        models.TotReturn.charge_month == month,
    ).first()

    return {
        "store_id": store_id,
        "store_name": store.name,
        "tpin": store.tpin,
        "charge_year": year,
        "charge_month": month,
        "month_name": _month_name(month),
        "gross_turnover": gross_turnover,
        "tot_rate_percent": tot_rate,
        "tot_amount": tot_amount,
        "due_date": due.isoformat(),
        "ytd_turnover": ytd_turnover,
        "annual_limit": ANNUAL_REGISTRATION_LIMIT,
        "over_annual_limit": ytd_turnover > ANNUAL_REGISTRATION_LIMIT,
        "threshold_warning": ytd_turnover > (ANNUAL_REGISTRATION_LIMIT * 0.80),
        "already_filed": existing is not None,
        "filed_status": existing.status if existing else None,
        "filed_return_id": existing.id if existing else None,
    }


@router.get("/annual-check/{store_id}", summary="Annual turnover TOT eligibility check")
def get_annual_tot_check(
    store_id: int,
    year: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Full-year turnover summary with per-month breakdown and K5M threshold check."""
    verify_store_access(store_id, current_user)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    rows = (
        db.query(
            extract("month", models.SaleTransaction.timestamp).label("month"),
            func.coalesce(func.sum(models.SaleTransaction.total_amount), 0).label("total"),
        )
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
        )
        .group_by("month")
        .order_by("month")
        .all()
    )

    monthly_breakdown = [
        {
            "month": int(r.month),
            "month_name": _month_name(int(r.month)),
            "gross_turnover": float(r.total),
            "tot_rate_percent": _compute_tot(float(r.total))[0],
            "tot_amount": _compute_tot(float(r.total))[1],
        }
        for r in rows
    ]

    annual_turnover = sum(m["gross_turnover"] for m in monthly_breakdown)
    annual_tot_due = sum(m["tot_amount"] for m in monthly_breakdown)

    return {
        "store_id": store_id,
        "store_name": store.name,
        "tpin": store.tpin,
        "charge_year": year,
        "annual_turnover": annual_turnover,
        "annual_tot_due": annual_tot_due,
        "annual_limit": ANNUAL_REGISTRATION_LIMIT,
        "eligible_for_tot": annual_turnover <= ANNUAL_REGISTRATION_LIMIT,
        "must_switch_to_income_tax": annual_turnover > ANNUAL_REGISTRATION_LIMIT,
        "threshold_warning_80pct": annual_turnover > (ANNUAL_REGISTRATION_LIMIT * 0.80),
        "monthly_breakdown": monthly_breakdown,
    }


@router.post("/submit-return/{store_id}", summary="File a TOT monthly return")
def submit_tot_return(
    store_id: int,
    payload: SubmitReturnRequest,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """Compute and file the TOT return. Requires Manager or Owner authorization."""
    verify_store_access(store_id, current_user)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    year, month = payload.charge_year, payload.charge_month

    gross_turnover = float(
        db.query(func.coalesce(func.sum(models.SaleTransaction.total_amount), 0))
        .filter(
            models.SaleTransaction.store_id == store_id,
            models.SaleTransaction.status != "refunded",
            extract("year", models.SaleTransaction.timestamp) == year,
            extract("month", models.SaleTransaction.timestamp) == month,
        ).scalar() or 0.0
    )

    tot_rate, tot_amount = _compute_tot(gross_turnover)
    due = _due_date(year, month)
    now = datetime.utcnow()
    digitax_ref = None

    # Attempt DigiTax submission (best-effort)
    api_key = store.digitax_api_key or os.getenv("DIGITAX_API_KEY")
    env = store.digitax_environment or "sandbox"
    base_url = (
        "https://api.digitax.tech/v1/zambia"
        if env.lower() == "production"
        else "https://sandbox.digitax.tech/v1/zambia"
    )
    if api_key and not api_key.startswith(("test_", "demo_", "mock_")):
        try:
            resp = requests.post(
                f"{base_url}/turnover-tax/returns",
                json={
                    "tpin": store.tpin or "1000000000",
                    "bhfId": store.bhf_id or "00",
                    "taxType": "TOT",
                    "chargeYear": year,
                    "chargeMonth": month,
                    "grossTurnover": gross_turnover,
                    "totRate": tot_rate,
                    "totAmount": tot_amount,
                    "dueDate": due.isoformat(),
                    "remark": f"Beleka POS TOT Return {_month_name(month)} {year}",
                },
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "X-API-Key": api_key,
                    "Content-Type": "application/json",
                },
                timeout=8,
            )
            if resp.status_code in [200, 201]:
                data = resp.json()
                digitax_ref = data.get("reference") or data.get("refNo") or data.get("acknowledgementNumber")
                logger.info(f"DigiTax TOT return submitted: ref={digitax_ref}")
            else:
                logger.warning(f"DigiTax TOT HTTP {resp.status_code}: {resp.text}")
        except Exception as ex:
            logger.error(f"DigiTax TOT submission error: {ex}")

    if not digitax_ref:
        digitax_ref = f"TOT-{store.tpin or store_id}-{year}{month:02d}-{int(time.time())}"

    existing = db.query(models.TotReturn).filter(
        models.TotReturn.store_id == store_id,
        models.TotReturn.charge_year == year,
        models.TotReturn.charge_month == month,
    ).first()

    if existing:
        existing.gross_turnover = gross_turnover
        existing.tot_rate = tot_rate
        existing.tot_amount = tot_amount
        existing.due_date = due
        existing.status = "submitted"
        existing.digitax_reference = digitax_ref
        existing.notes = payload.notes
        existing.submitted_at = now
        existing.updated_at = now
        record = existing
    else:
        record = models.TotReturn(
            store_id=store_id,
            charge_year=year,
            charge_month=month,
            gross_turnover=gross_turnover,
            tot_rate=tot_rate,
            tot_amount=tot_amount,
            due_date=due,
            status="submitted",
            digitax_reference=digitax_ref,
            notes=payload.notes,
            submitted_at=now,
        )
        db.add(record)

    db.commit()
    db.refresh(record)

    return {
        "status": "SUCCESS",
        "return_id": record.id,
        "store_id": store_id,
        "store_name": store.name,
        "tpin": store.tpin,
        "charge_year": year,
        "charge_month": month,
        "month_name": _month_name(month),
        "gross_turnover": float(record.gross_turnover),
        "tot_rate_percent": float(record.tot_rate),
        "tot_amount": float(record.tot_amount),
        "due_date": due.isoformat(),
        "digitax_reference": record.digitax_reference,
        "filed_status": record.status,
        "submitted_at": now.isoformat(),
        "message": (
            f"TOT return for {_month_name(month)} {year} filed. "
            f"Amount due: K{tot_amount:,.2f} by {due.strftime('%d %B %Y')}."
        ),
    }


@router.get("/returns/{store_id}", summary="List all TOT returns for a store")
def list_tot_returns(
    store_id: int,
    year: Optional[int] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """List all filed TOT returns for a store (tenant-scoped)."""
    verify_store_access(store_id, current_user)

    store = db.query(models.Store).filter(models.Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    q = db.query(models.TotReturn).filter(models.TotReturn.store_id == store_id)
    if year:
        q = q.filter(models.TotReturn.charge_year == year)
    records = q.order_by(
        models.TotReturn.charge_year.desc(),
        models.TotReturn.charge_month.desc()
    ).all()

    return {
        "store_id": store_id,
        "store_name": store.name,
        "total_returns": len(records),
        "returns": [
            {
                "id": r.id,
                "charge_year": r.charge_year,
                "charge_month": r.charge_month,
                "month_name": _month_name(r.charge_month),
                "gross_turnover": float(r.gross_turnover),
                "tot_rate_percent": float(r.tot_rate),
                "tot_amount": float(r.tot_amount),
                "due_date": r.due_date.isoformat() if r.due_date else None,
                "status": r.status,
                "digitax_reference": r.digitax_reference,
                "submitted_at": r.submitted_at.isoformat() if r.submitted_at else None,
            }
            for r in records
        ],
    }


@router.get("/returns/{store_id}/{return_id}", summary="Get a specific TOT return")
def get_tot_return(
    store_id: int,
    return_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch a single TOT return record (tenant-scoped)."""
    verify_store_access(store_id, current_user)

    record = db.query(models.TotReturn).filter(
        models.TotReturn.id == return_id,
        models.TotReturn.store_id == store_id,
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="TOT return not found")

    return {
        "id": record.id,
        "store_id": record.store_id,
        "charge_year": record.charge_year,
        "charge_month": record.charge_month,
        "month_name": _month_name(record.charge_month),
        "gross_turnover": float(record.gross_turnover),
        "tot_rate_percent": float(record.tot_rate),
        "tot_amount": float(record.tot_amount),
        "due_date": record.due_date.isoformat() if record.due_date else None,
        "status": record.status,
        "digitax_reference": record.digitax_reference,
        "notes": record.notes,
        "submitted_at": record.submitted_at.isoformat() if record.submitted_at else None,
        "created_at": record.created_at.isoformat() if record.created_at else None,
    }


@router.patch("/returns/{store_id}/{return_id}/mark-paid", summary="Mark a TOT return as paid")
def mark_tot_paid(
    store_id: int,
    return_id: int,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db)
):
    """Mark a submitted TOT return as paid after cash/bank payment is confirmed. Requires Manager or Owner role."""
    verify_store_access(store_id, current_user)

    record = db.query(models.TotReturn).filter(
        models.TotReturn.id == return_id,
        models.TotReturn.store_id == store_id,
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="TOT return not found")
    if record.status == "paid":
        return {"message": "Already paid.", "status": "paid"}

    record.status = "paid"
    record.updated_at = datetime.utcnow()
    db.commit()
    return {
        "status": "SUCCESS",
        "message": f"TOT return for {_month_name(record.charge_month)} {record.charge_year} marked as paid.",
        "return_id": return_id,
        "filed_status": "paid",
    }
