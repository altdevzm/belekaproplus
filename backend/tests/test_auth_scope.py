import hashlib

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app import models, schemas
from app.auth_deps import verify_store_access
from app.database import Base
from app.routers.auth import cloud_login, register_organization, resolve_organization


def make_db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    return sessionmaker(bind=engine)()


def add_store(db, store_id, code, tpin, bhf_id):
    store = models.Store(
        id=store_id,
        store_code=code,
        name=code,
        tpin=tpin,
        bhf_id=bhf_id,
        is_active=True,
    )
    db.add(store)
    return store


def add_user(db, user_id, store_id, numeric_id, role="cashier"):
    user = models.User(
        id=user_id,
        store_id=store_id,
        numeric_id=numeric_id,
        name=numeric_id,
        role=role,
        password_hash=hashlib.sha256(b"1234").hexdigest(),
        is_active=True,
    )
    db.add(user)
    return user


def test_tpin_id_password_resolves_exact_branch_and_scope():
    db = make_db()
    add_store(db, 1, "HQ-00", "TENANT-1", "00")
    add_store(db, 2, "BR-01", "TENANT-1", "01")
    add_store(db, 3, "OTHER", "TENANT-2", "01")
    branch_user = add_user(db, 20, 2, "2001")
    hq_user = add_user(db, 30, 1, "1001", role="owner")
    db.commit()

    login = cloud_login(
        schemas.LoginRequest(tpin="TENANT-1", numeric_id="2001", pin="1234"),
        db,
    )
    assert login["user"].id == branch_user.id
    assert login["user"].store_id == 2
    assert login["store"].bhf_id == "01"

    with pytest.raises(HTTPException) as branch_error:
        verify_store_access(1, branch_user, db)
    assert branch_error.value.status_code == 403

    with pytest.raises(HTTPException) as tenant_error:
        verify_store_access(3, hq_user, db)
    assert tenant_error.value.status_code == 403


def test_registration_creates_tpin_scoped_hq_owner_and_session():
    db = make_db()

    response = register_organization(
        schemas.RegistrationRequest(
            business_name="Acme Retail",
            tpin="TENANT-NEW",
            numeric_id="1001",
            pin="1234",
        ),
        db,
    )

    assert response["store"].name == "Acme Retail"
    assert response["store"].tpin == "TENANT-NEW"
    assert response["store"].bhf_id == "00"
    assert response["user"].numeric_id == "1001"
    assert response["user"].role == "owner"
    assert response["token"]

    with pytest.raises(HTTPException) as duplicate_error:
        register_organization(
            schemas.RegistrationRequest(
                business_name="Other Retail",
                tpin="TENANT-NEW",
                numeric_id="2001",
                pin="1234",
            ),
            db,
        )
    assert duplicate_error.value.status_code == 409


def test_registration_allows_hq_for_multiple_organizations():
    db = make_db()

    first = register_organization(
        schemas.RegistrationRequest(
            business_name="First Retail",
            tpin="TENANT-FIRST",
            numeric_id="1001",
            pin="1234",
        ),
        db,
    )
    second = register_organization(
        schemas.RegistrationRequest(
            business_name="Second Retail",
            tpin="TENANT-SECOND",
            numeric_id="1001",
            pin="1234",
        ),
        db,
    )

    assert first["store"].bhf_id == "00"
    assert second["store"].bhf_id == "00"
    assert first["store"].store_code != second["store"].store_code


def test_company_name_resolves_to_one_tenant_tpin():
    db = make_db()
    add_store(db, 1, "ACME-HQ", "TENANT-ACME", "00")
    db.query(models.Store).filter(models.Store.id == 1).update({"name": "Acme Retail"})
    db.commit()

    result = resolve_organization(
        schemas.OrganizationLookupRequest(company_name=" acme retail "),
        db,
    )
    assert result["company_name"] == "Acme Retail"
    assert result["tpin"] == "TENANT-ACME"


def test_remote_login_requires_tpin():
    db = make_db()
    add_store(db, 1, "HQ-00", "TENANT-1", "00")
    add_user(db, 20, 1, "1001", role="owner")
    db.commit()

    with pytest.raises(HTTPException) as error:
        cloud_login(schemas.LoginRequest(numeric_id="1001", pin="1234"), db)
    assert error.value.status_code == 401
    assert "TPIN" in error.value.detail


def test_ambiguous_credentials_do_not_guess_a_branch():
    db = make_db()
    add_store(db, 1, "BR-01", "TENANT-1", "01")
    add_store(db, 2, "BR-02", "TENANT-1", "02")
    add_user(db, 20, 1, "2001")
    add_user(db, 21, 2, "2001")
    db.commit()

    with pytest.raises(HTTPException) as error:
        cloud_login(
            schemas.LoginRequest(tpin="TENANT-1", numeric_id="2001", pin="1234"),
            db,
        )
    assert error.value.status_code == 401
    assert "ambiguous" in error.value.detail


def test_branch_code_disambiguates_same_credentials_within_tenant():
    db = make_db()
    add_store(db, 1, "BR-01", "TENANT-1", "01")
    add_store(db, 2, "BR-02", "TENANT-1", "02")
    first_user = add_user(db, 20, 1, "2001")
    add_user(db, 21, 2, "2001")
    db.commit()

    response = cloud_login(
        schemas.LoginRequest(
            tpin="TENANT-1",
            branch_code="02",
            numeric_id="2001",
            pin="1234",
        ),
        db,
    )
    assert response["user"].id != first_user.id
    assert response["store"].bhf_id == "02"
