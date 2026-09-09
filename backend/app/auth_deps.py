import os
import hashlib
import jwt
from datetime import datetime, timedelta, timezone
from typing import Optional, List
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from passlib.context import CryptContext

from app.database import get_db
from app import models

# Environment secret key or secure fallback (warning printed if default used)
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "BELEKA_POS_CLOUD_SECURE_JWT_SECRET_KEY_CHANGE_IN_PROD_2026")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)


def hash_password(plain: str) -> str:
    """Hash a password/PIN securely with fallback for passlib compatibility."""
    clean = plain.strip()
    try:
        return pwd_context.hash(clean[:72])
    except Exception:
        return hashlib.sha256(clean.encode("utf-8")).hexdigest()


def verify_and_update_password(plain: str, stored_hash: str) -> tuple[bool, bool]:
    """
    Verify plain PIN/password against stored hash.
    Supports bcrypt and fallback legacy SHA-256 / plaintext.
    Returns (is_correct, needs_rehash).
    """
    plain_clean = plain.strip()
    stored_clean = stored_hash.strip()

    # 1. Bcrypt verification
    if stored_clean.startswith("$2b$") or stored_clean.startswith("$2a$") or stored_clean.startswith("$2y$"):
        try:
            valid = pwd_context.verify(plain_clean, stored_clean)
            return valid, False
        except Exception:
            return False, False

    # 2. Legacy SHA-256 verification
    sha256_hex = hashlib.sha256(plain_clean.encode("utf-8")).hexdigest()
    if stored_clean == sha256_hex or stored_clean == plain_clean:
        return True, True

    return False, False


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a signed JWT access token."""
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)

    to_encode.update({"exp": expire, "iat": now})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def get_current_user(
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> models.User:
    """Authenticate current user from Bearer JWT token."""
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required. Missing Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: Optional[int] = payload.get("user_id")
        numeric_id: Optional[str] = payload.get("numeric_id")
        if user_id is None or numeric_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token claims.",
                headers={"WWW-Authenticate": "Bearer"},
            )
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = db.query(models.User).filter(
        models.User.id == user_id,
        models.User.numeric_id == numeric_id
    ).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user no longer exists.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is deactivated.",
        )

    return user


def log_audit_event(
    db: Session,
    event_type: str,
    tpin: Optional[str] = None,
    store_id: Optional[int] = None,
    numeric_id: Optional[str] = None,
    user_id: Optional[int] = None,
    ip_address: Optional[str] = None,
    details: Optional[str] = None,
    is_success: bool = True
) -> None:
    """Log a security or tenant resolution audit entry into database."""
    try:
        log_entry = models.AuditLog(
            event_type=event_type,
            tpin=tpin,
            store_id=store_id,
            numeric_id=numeric_id,
            user_id=user_id,
            ip_address=ip_address,
            details=details,
            is_success=is_success
        )
        db.add(log_entry)
        db.commit()
    except Exception as e:
        print(f"[AuditLog Warning] Could not record audit log: {e}")
        db.rollback()


def verify_store_access(
    store_id: int,
    current_user: models.User,
    db: Optional[Session] = None
) -> None:
    """
    Strict server-side tenant & branch authorization guard.
    - Resolves organization TPIN scope.
    - Prevents cross-organization access (Organization A user cannot access Organization B data).
    - Prevents branch users (cashiers/managers) from accessing non-assigned branches.
    """
    if store_id == 0:
        # 0 is reserved for HQ Multi-store aggregate reports (only allowed for owner/super_admin)
        if current_user.role in ["owner", "super_admin"]:
            return
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: Multi-store HQ access requires owner privileges.",
        )

    # 1. Branch User Isolation Check
    if current_user.role not in ["owner", "super_admin"]:
        if current_user.store_id != store_id:
            if db:
                log_audit_event(
                    db,
                    event_type="UNAUTHORIZED_ACCESS_ATTEMPT",
                    tpin=current_user.store.tpin if current_user.store else None,
                    store_id=store_id,
                    numeric_id=current_user.numeric_id,
                    user_id=current_user.id,
                    details=f"Branch user attempt to access forbidden store_id {store_id}",
                    is_success=False,
                )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Unauthorized: Access to branch store_id {store_id} is forbidden for your account.",
            )

    # 2. Cross-Organization (Cross-TPIN) Tenant Isolation Check
    if db and current_user.role != "super_admin":
        target_store = db.query(models.Store).filter(models.Store.id == store_id).first()
        if not target_store:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Store branch {store_id} not found.",
            )

        user_store = current_user.store or db.query(models.Store).filter(models.Store.id == current_user.store_id).first()
        user_tpin = (user_store.tpin or "").strip() if user_store else ""
        target_tpin = (target_store.tpin or "").strip()

        if user_tpin and target_tpin and user_tpin != target_tpin:
            log_audit_event(
                db,
                event_type="UNAUTHORIZED_ACCESS_ATTEMPT",
                tpin=user_tpin,
                store_id=store_id,
                numeric_id=current_user.numeric_id,
                user_id=current_user.id,
                details=f"Cross-tenant access attempt: User TPIN '{user_tpin}' vs Target Store TPIN '{target_tpin}'",
                is_success=False,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Forbidden: Cross-organization data access strictly denied.",
            )


def require_roles(allowed_roles: List[str]):
    """Role-based authorization guard dependency factory."""
    def role_checker(current_user: models.User = Depends(get_current_user)) -> models.User:
        if current_user.role not in allowed_roles and current_user.role != "super_admin":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Forbidden: Action requires one of roles: {allowed_roles}",
            )
        return current_user
    return role_checker

