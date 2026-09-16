import hashlib
import pytest
from datetime import datetime
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app import models, schemas
from app.database import Base
from app.routers.expenses import create_expense, get_expenses, get_expenses_summary, update_expense, delete_expense
from app.routers.sync import sync_batch_expenses, export_vps_backup


def make_db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    return sessionmaker(bind=engine)()


def add_store(db, store_id, code, tpin, bhf_id, name="Test Branch"):
    store = models.Store(
        id=store_id,
        store_code=code,
        name=name,
        branch_name=name,
        tpin=tpin,
        bhf_id=bhf_id,
        is_active=True,
    )
    db.add(store)
    return store


def add_user(db, user_id, store_id, numeric_id, name="Test User", role="owner"):
    user = models.User(
        id=user_id,
        store_id=store_id,
        numeric_id=numeric_id,
        name=name,
        role=role,
        password_hash=hashlib.sha256(b"1234").hexdigest(),
        is_active=True,
    )
    db.add(user)
    return user


def test_create_and_get_expense():
    db = make_db()
    store = add_store(db, 1, "HQ-00", "TPIN-100", "00", name="HQ Branch")
    owner = add_user(db, 1, 1, "1001", name="Owner Alice", role="owner")
    db.commit()

    # Create expense
    exp_in = schemas.ExpenseCreate(
        store_id=1,
        title="Generator Diesel 50 Litres",
        category="Transport / Fuel",
        amount=1250.50,
        payment_account="Cash in Till",
        branch_code="00",
        branch_name="HQ Branch",
        notes="Emergency generator refill",
    )
    created = create_expense(exp_in, owner, db)

    assert created.id is not None
    assert created.title == "Generator Diesel 50 Litres"
    assert float(created.amount) == 1250.50
    assert created.recorded_by == "Owner Alice"
    assert created.expense_number.startswith("EXP-")

    # Fetch expenses
    expenses = get_expenses(store_id=1, category=None, branch_code=None, search=None, start_date=None, end_date=None, limit=50, offset=0, current_user=owner, db=db)
    assert len(expenses) == 1
    assert expenses[0].title == "Generator Diesel 50 Litres"


def test_expenses_summary():
    db = make_db()
    store = add_store(db, 1, "HQ-00", "TPIN-100", "00", name="HQ Branch")
    owner = add_user(db, 1, 1, "1001", name="Owner Alice", role="owner")
    db.commit()

    create_expense(
        schemas.ExpenseCreate(
            store_id=1,
            title="Office Rent",
            category="Rent",
            amount=5000.00,
        ),
        owner,
        db,
    )
    create_expense(
        schemas.ExpenseCreate(
            store_id=1,
            title="Internet Fiber",
            category="Utilities",
            amount=800.00,
        ),
        owner,
        db,
    )

    summary = get_expenses_summary(store_id=1, start_date=None, end_date=None, current_user=owner, db=db)
    assert summary.total_amount == 5800.00
    assert summary.total_count == 2
    assert summary.by_category["Rent"] == 5000.00
    assert summary.by_category["Utilities"] == 800.00


def test_sync_batch_expenses():
    db = make_db()
    store = add_store(db, 1, "HQ-00", "TPIN-100", "00", name="HQ Branch")
    user = add_user(db, 1, 1, "1001", name="Alice", role="owner")
    db.commit()

    batch_req = schemas.SyncBatchExpensesRequest(
        store_id=1,
        expenses=[
            schemas.ExpenseCreate(
                store_id=1,
                expense_number="EXP-LOCAL-001",
                title="Cleaning Supplies",
                category="Supplies & Stationery",
                amount=150.00,
                branch_code="00",
                branch_name="HQ Branch",
            ),
            schemas.ExpenseCreate(
                store_id=1,
                expense_number="EXP-LOCAL-002",
                title="Water Utility Bill",
                category="Utilities",
                amount=320.00,
                branch_code="00",
                branch_name="HQ Branch",
            ),
        ],
    )

    res = sync_batch_expenses(batch_req, user, db)
    assert res["status"] == "success"
    assert res["synced_count"] == 2

    # Verify backup export contains expenses
    backup = export_vps_backup(1, user, db)
    assert "expenses" in backup
    assert len(backup["expenses"]) == 2
