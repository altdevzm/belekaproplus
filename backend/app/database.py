import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Cloud PostgreSQL database connection string
# Standard env format: postgresql://user:password@host:5432/dbname
DATABASE_URL = os.getenv(
    "DATABASE_URL", 
    "postgresql://postgres:postgres@localhost:5432/beleka_pos_cloud"
)

# Handle Heroku / Supabase style postgres:// URLs
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

try:
    if DATABASE_URL.startswith("sqlite"):
        engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
    else:
        engine = create_engine(
            DATABASE_URL,
            pool_pre_ping=True,
            pool_size=10,
            max_overflow=20
        )
        # Test connection
        with engine.connect() as conn:
            pass
except Exception as e:
    print(f"[Warning] PostgreSQL connection failed ({e}). Falling back to SQLite local database (beleka_cloud.db)...")
    DATABASE_URL = "sqlite:///./beleka_cloud.db"
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def seed_initial_data():
    """Seed default Store 1 (HQ Store) and Admin User if DB is empty.
    
    Uses SHA-256 hashing for the default PIN which is supported by
    auth_deps.verify_and_update_password and auto-upgrades to bcrypt on first login.
    """
    import hashlib
    from app import models

    # Ensure all tables exist on current engine
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()

    # --- Seed Store 1 (HQ) ---
    try:
        hq_store = db.query(models.Store).filter(models.Store.id == 1).first()
        if not hq_store:
            hq_store = models.Store(
                id=1,
                store_code="HQ-00",
                bhf_id="00",
                name="Main Branch (HQ)",
                address="Corporate Headquarters",
                contact_number="+260970000000",
                email="hq@belekapos.com",
                currency_symbol="K",
                branch_name="Main Branch (HQ)",
                manager_name="HQ Manager",
                manager_id="1001",
                business_tax_type="VAT_STANDARD",
                digitax_environment="sandbox",
                is_active=True,
            )
            db.add(hq_store)
            db.commit()
            db.refresh(hq_store)
            print("[Backend DB Seed] Initialized default Store 1 (HQ Store).")
    except Exception as e:
        print(f"[Backend DB Seed Warning] Store seed failed: {e}")
        db.rollback()

    # --- Seed default HQ owner/admin user ---
    try:
        hq_store = db.query(models.Store).filter(models.Store.id == 1).first()
        if not hq_store:
            print("[Backend DB Seed Warning] Cannot seed user: Store 1 not found.")
            db.close()
            return

        admin_user = db.query(models.User).filter(
            models.User.numeric_id == "1001",
            models.User.store_id == hq_store.id,
        ).first()
        if not admin_user:
            # Use SHA-256 hash — auto-upgraded to bcrypt on first login via auth_deps
            pin_hash = hashlib.sha256("0000".encode("utf-8")).hexdigest()
            admin_user = models.User(
                store_id=hq_store.id,
                numeric_id="1001",
                name="HQ Owner / Admin",
                password_hash=pin_hash,
                role="owner",
                branch_name="Main Branch (HQ)",
                is_active=True,
            )
            db.add(admin_user)
            db.commit()
            print("[Backend DB Seed] Initialized default HQ Owner user (numeric_id='1001', PIN='0000').")
    except Exception as e:
        print(f"[Backend DB Seed Warning] User seed failed: {e}")
        db.rollback()
    finally:
        db.close()

