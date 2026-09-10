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
