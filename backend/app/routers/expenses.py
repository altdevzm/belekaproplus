import uuid
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app import models, schemas
from app.auth_deps import get_current_user, verify_store_access, require_roles

router = APIRouter(prefix="/api/v1/expenses", tags=["Expenses"])


def _generate_expense_number(store_id: int) -> str:
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    suffix = uuid.uuid4().hex[:6].upper()
    return f"EXP-{store_id:02d}-{timestamp}-{suffix}"


@router.get("", response_model=List[schemas.ExpenseResponse])
def get_expenses(
    store_id: Optional[int] = Query(None, description="Filter by store/branch ID"),
    category: Optional[str] = Query(None, description="Filter by expense category"),
    branch_code: Optional[str] = Query(None, description="Filter by branch code"),
    search: Optional[str] = Query(None, description="Search keyword in title, notes, or reference"),
    start_date: Optional[datetime] = Query(None, description="Filter start date"),
    end_date: Optional[datetime] = Query(None, description="Filter end date"),
    limit: int = Query(200, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Fetch expense records with multi-criteria filtering and tenant security scoping.
    Owners can view expenses for their entire organization or specific branches.
    Branch managers & cashiers are scoped to their assigned store.
    """
    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    user_tpin = (user_store.tpin or "").strip() if user_store else ""

    query = db.query(models.Expense)

    if current_user.role in ["owner", "super_admin"]:
        # Scoped to organization
        if current_user.role != "super_admin" and user_tpin:
            query = query.join(models.Store).filter(models.Store.tpin == user_tpin)
        
        if store_id and store_id > 0:
            verify_store_access(store_id, current_user, db)
            query = query.filter(models.Expense.store_id == store_id)
    else:
        target_store_id = store_id or current_user.store_id
        verify_store_access(target_store_id, current_user, db)
        query = query.filter(models.Expense.store_id == target_store_id)

    if category:
        query = query.filter(models.Expense.category == category)
    if branch_code:
        query = query.filter(models.Expense.branch_code == branch_code)
    if start_date:
        query = query.filter(models.Expense.expense_date >= start_date)
    if end_date:
        query = query.filter(models.Expense.expense_date <= end_date)
    if search:
        search_pattern = f"%{search.strip()}%"
        query = query.filter(
            (models.Expense.title.ilike(search_pattern))
            | (models.Expense.notes.ilike(search_pattern))
            | (models.Expense.reference_number.ilike(search_pattern))
            | (models.Expense.expense_number.ilike(search_pattern))
        )

    return query.order_by(models.Expense.expense_date.desc()).offset(offset).limit(limit).all()


@router.get("/summary", response_model=schemas.ExpenseSummaryResponse)
def get_expenses_summary(
    store_id: Optional[int] = Query(None),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Get aggregated expense statistics, category breakdown, and branch distribution.
    """
    user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
    user_tpin = (user_store.tpin or "").strip() if user_store else ""

    query = db.query(models.Expense)

    if current_user.role in ["owner", "super_admin"]:
        if current_user.role != "super_admin" and user_tpin:
            query = query.join(models.Store).filter(models.Store.tpin == user_tpin)
        if store_id and store_id > 0:
            verify_store_access(store_id, current_user, db)
            query = query.filter(models.Expense.store_id == store_id)
    else:
        target_store_id = store_id or current_user.store_id
        verify_store_access(target_store_id, current_user, db)
        query = query.filter(models.Expense.store_id == target_store_id)

    if start_date:
        query = query.filter(models.Expense.expense_date >= start_date)
    if end_date:
        query = query.filter(models.Expense.expense_date <= end_date)

    expenses = query.all()

    total_amount = 0.0
    by_category: dict[str, float] = {}
    by_branch: dict[str, float] = {}

    for exp in expenses:
        amt = float(exp.amount or 0.0)
        total_amount += amt
        cat = exp.category or "Other"
        by_category[cat] = round(by_category.get(cat, 0.0) + amt, 2)
        br = exp.branch_name or f"Branch {exp.branch_code}"
        by_branch[br] = round(by_branch.get(br, 0.0) + amt, 2)

    return schemas.ExpenseSummaryResponse(
        total_amount=round(total_amount, 2),
        total_count=len(expenses),
        by_category=by_category,
        by_branch=by_branch,
    )


@router.get("/{expense_id}", response_model=schemas.ExpenseResponse)
def get_expense(
    expense_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Fetch single expense by ID."""
    expense = db.query(models.Expense).filter(models.Expense.id == expense_id).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense record not found")

    verify_store_access(expense.store_id, current_user, db)
    return expense


@router.post("", response_model=schemas.ExpenseResponse, status_code=status.HTTP_201_CREATED)
def create_expense(
    expense_in: schemas.ExpenseCreate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager", "cashier"])),
    db: Session = Depends(get_db),
):
    """
    Record a new operating expense for a store/branch.
    Validates amounts, generates unique expense reference if needed.
    """
    verify_store_access(expense_in.store_id, current_user, db)

    if expense_in.amount <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expense amount must be greater than zero.",
        )

    exp_num = expense_in.expense_number or _generate_expense_number(expense_in.store_id)

    # Ensure unique expense number
    existing = db.query(models.Expense).filter(models.Expense.expense_number == exp_num).first()
    if existing:
        exp_num = _generate_expense_number(expense_in.store_id)

    expense_data = expense_in.model_dump()
    expense_data["expense_number"] = exp_num
    if not expense_data.get("recorded_by"):
        expense_data["recorded_by"] = current_user.name
    if not expense_data.get("recorded_by_id"):
        expense_data["recorded_by_id"] = current_user.numeric_id
    if not expense_data.get("expense_date"):
        expense_data["expense_date"] = datetime.now()

    expense = models.Expense(**expense_data)
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return expense


@router.put("/{expense_id}", response_model=schemas.ExpenseResponse)
def update_expense(
    expense_id: int,
    expense_in: schemas.ExpenseUpdate,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db),
):
    """Update an existing expense record."""
    expense = db.query(models.Expense).filter(models.Expense.id == expense_id).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense record not found")

    verify_store_access(expense.store_id, current_user, db)

    update_data = expense_in.model_dump(exclude_unset=True)
    if "amount" in update_data and update_data["amount"] is not None and update_data["amount"] <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expense amount must be greater than zero.",
        )

    for field, value in update_data.items():
        setattr(expense, field, value)

    db.commit()
    db.refresh(expense)
    return expense


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(
    expense_id: int,
    current_user: models.User = Depends(require_roles(["owner", "branch_manager"])),
    db: Session = Depends(get_db),
):
    """Delete an expense record."""
    expense = db.query(models.Expense).filter(models.Expense.id == expense_id).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense record not found")

    verify_store_access(expense.store_id, current_user, db)

    db.delete(expense)
    db.commit()
    return None
