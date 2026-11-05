import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app import models, schemas
from app.database import Base
from app.routers.sync import export_vps_backup, sync_batch_sales


@pytest.fixture
def db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    session = sessionmaker(bind=engine)()
    hq = models.Store(id=1, store_code="HQ-00", name="HQ", tpin="TENANT-1", bhf_id="00")
    branch = models.Store(id=2, store_code="BR-01", name="Branch 1", tpin="TENANT-1", bhf_id="01")
    other = models.Store(id=3, store_code="OTHER", name="Other", tpin="TENANT-2", bhf_id="01")
    session.add_all([hq, branch, other])
    session.commit()
    try:
        yield session, hq, branch, other
    finally:
        session.close()


def sale_payload(uuid):
    return schemas.SyncBatchRequest(
        store_id=2,
        sales=[schemas.SaleTransactionCreate(
            transaction_uuid=uuid,
            store_id=2,
            total_amount=10,
            subtotal=10,
            payment_method="Cash",
            items=[schemas.SaleItemBase(
                product_name="Test product",
                price_at_sale=10,
                quantity=1,
            )],
        )],
    )


def branch_user():
    return models.User(
        id=20,
        store_id=2,
        numeric_id="2001",
        name="Branch cashier",
        role="cashier",
        password_hash="unused",
        is_active=True,
    )


def test_batch_is_idempotent_and_stores_branch_data(db):
    session, _, branch, _ = db
    user = branch_user()
    result = sync_batch_sales(sale_payload("branch-tx-1"), user, session)
    assert result["synced_uuids"] == ["branch-tx-1"]

    retry = sync_batch_sales(sale_payload("branch-tx-1"), user, session)
    assert retry["synced_uuids"] == ["branch-tx-1"]
    assert session.query(models.SaleTransaction).count() == 1
    assert session.query(models.SaleTransaction).one().store_id == branch.id


def test_uuid_cannot_move_between_branches(db):
    session, _, _, _ = db
    first_user = branch_user()
    sync_batch_sales(sale_payload("collision-tx"), first_user, session)

    second_store = models.Store(id=4, store_code="BR-02", name="Branch 2", tpin="TENANT-1", bhf_id="02")
    session.add(second_store)
    session.commit()
    second_user = models.User(
        id=21,
        store_id=4,
        numeric_id="4001",
        name="Branch 2 cashier",
        role="cashier",
        password_hash="unused",
        is_active=True,
    )
    payload = sale_payload("collision-tx")
    payload.store_id = 4

    with pytest.raises(HTTPException) as error:
        sync_batch_sales(payload, second_user, session)
    assert error.value.status_code == 409
    assert session.query(models.SaleTransaction).count() == 1


def test_hq_export_is_tenant_scoped(db):
    session, hq, branch, other = db
    user = models.User(
        id=30,
        store_id=hq.id,
        numeric_id="1001",
        name="Owner",
        role="owner",
        password_hash="unused",
        is_active=True,
    )
    sync_batch_sales(sale_payload("hq-export-tx"), branch_user(), session)

    backup = export_vps_backup(0, user, session)
    assert {store["id"] for store in backup["stores"]} == {hq.id, branch.id}
    assert len(backup["sales"]) == 1
    assert backup["sales"][0]["store_id"] == branch.id
    assert other.id not in {store["id"] for store in backup["stores"]}


def test_branch_owner_export_contains_only_requested_branch(db):
    session, _, branch, _ = db
    branch_owner = models.User(
        id=31,
        store_id=branch.id,
        numeric_id="2002",
        name="Branch owner",
        role="owner",
        password_hash="unused",
        is_active=True,
    )
    session.add(branch_owner)
    session.commit()
    sync_batch_sales(sale_payload("branch-export-tx"), branch_user(), session)

    backup = export_vps_backup(branch.id, branch_owner, session)

    assert [store["id"] for store in backup["stores"]] == [branch.id]
    assert len(backup["sales"]) == 1
    assert backup["sales"][0]["store_id"] == branch.id


def test_auto_fiscalization_preserves_recorded_sale_amounts(db, monkeypatch):
    session, _, branch, _ = db
    branch.digitax_api_key = "configured-test-key"
    payload = schemas.SyncBatchRequest(
        store_id=branch.id,
        sales=[schemas.SaleTransactionCreate(
            transaction_uuid="fiscal-total-mismatch",
            store_id=branch.id,
            total_amount=37,
            subtotal=31.89,
            tax_amount=5.11,
            tendered_amount=100,
            change_amount=63,
            payment_method="Cash",
            items=[schemas.SaleItemBase(
                product_name="Test product",
                price_at_sale=37,
                quantity=1,
                tax_rate_at_sale=16,
                is_digitax_exempt=False,
            )],
        )],
    )

    monkeypatch.setattr(
        "app.routers.sync.DigiTaxZraService.fiscalize_sale_invoice",
        lambda *_args, **_kwargs: {
            "status": "SUCCESS",
            "zra_receipt_number": "INV1/6",
            "zra_mark_id": "signed-mark",
            "tax_amount": 2.76,
            "subtotal": 17.24,
        },
    )

    sync_batch_sales(payload, branch_user(), session)

    transaction = session.query(models.SaleTransaction).filter_by(
        transaction_uuid="fiscal-total-mismatch",
    ).one()
    assert float(transaction.total_amount) == 37
    assert float(transaction.subtotal) == 31.89
    assert float(transaction.tax_amount) == 5.11
    assert float(transaction.tendered_amount) == 100
    assert float(transaction.change_amount) == 63
    assert transaction.zra_status == "APPROVED"


def test_sale_sync_preserves_product_report_snapshot_and_weight(db, monkeypatch):
    session, _, branch, _ = db
    branch.digitax_api_key = "configured-test-key"
    payload = schemas.SyncBatchRequest(
        store_id=branch.id,
        sales=[schemas.SaleTransactionCreate(
            transaction_uuid="weighted-report-line",
            store_id=branch.id,
            total_amount=15,
            subtotal=12.93,
            tax_amount=2.07,
            payment_method="Cash",
            items=[schemas.SaleItemBase(
                product_id=501,
                product_name="Apples",
                product_sku_at_sale="APPLE-KG",
                price_at_sale=20,
                discount_amount_at_sale=2,
                quantity=1,
                weight=0.75,
                is_weighted=True,
                unit_of_measure="kg",
                tax_rate_at_sale=16,
                is_digitax_exempt=False,
            )],
        )],
    )
    fiscal_items = {}

    def fake_fiscalize(_config, _transaction, items):
        fiscal_items["items"] = items
        return {"zra_receipt_number": "INV1/7"}

    monkeypatch.setattr(
        "app.routers.sync.DigiTaxZraService.fiscalize_sale_invoice",
        fake_fiscalize,
    )
    sync_batch_sales(payload, branch_user(), session)

    item = session.query(models.SaleItem).one()
    assert item.product_sku_at_sale == "APPLE-KG"
    assert float(item.discount_amount_at_sale) == 2
    assert float(item.weight) == 0.75
    assert item.is_weighted is True
    assert item.unit_of_measure == "kg"
    assert fiscal_items["items"][0]["quantity"] == 0.75
