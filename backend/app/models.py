from sqlalchemy import (
    Column, Integer, String, Numeric, Boolean, DateTime, Text, ForeignKey, JSON, UniqueConstraint
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database import Base

class Store(Base):
    __tablename__ = "stores"

    id = Column(Integer, primary_key=True, index=True)
    store_code = Column(String(50), unique=True, nullable=False, index=True)
    bhf_id = Column(String(10), default="00")
    name = Column(String(255), nullable=False)
    address = Column(Text, nullable=True)
    contact_number = Column(String(50), nullable=True)
    email = Column(String(255), nullable=True)
    tax_id = Column(String(100), nullable=True)
    tpin = Column(String(100), nullable=True)
    sdc_id = Column(String(100), nullable=True)
    mrc_no = Column(String(100), nullable=True)
    currency_symbol = Column(String(10), default="K")
    branch_name = Column(String(100), nullable=True)
    manager_name = Column(String(255), nullable=True)
    manager_id = Column(String(50), nullable=True)
    manager_phone = Column(String(50), nullable=True)
    business_tax_type = Column(String(50), default="VAT_STANDARD")
    digitax_api_key = Column(String(255), nullable=True)
    digitax_environment = Column(String(20), default="sandbox")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    users = relationship("User", back_populates="store", cascade="all, delete-orphan")
    products = relationship("Product", back_populates="store", cascade="all, delete-orphan")
    categories = relationship("Category", back_populates="store", cascade="all, delete-orphan")
    sales = relationship("SaleTransaction", back_populates="store", cascade="all, delete-orphan")
    customers = relationship("Customer", back_populates="store", cascade="all, delete-orphan")
    purchase_orders = relationship("PurchaseOrder", back_populates="store", cascade="all, delete-orphan")
    stock_movements = relationship("StockMovement", back_populates="store", cascade="all, delete-orphan")

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    numeric_id = Column(String(50), nullable=False)
    name = Column(String(255), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(50), nullable=False, default="cashier") # 'owner', 'branch_manager', 'cashier'
    branch_name = Column(String(100), nullable=True)
    phone = Column(String(50), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    store = relationship("Store", back_populates="users")
    __table_args__ = (UniqueConstraint("store_id", "numeric_id", name="uk_user_store_numeric"),)

class Category(Base):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    sector = Column(String(50), default="other")
    icon_path = Column(String(255), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    store = relationship("Store", back_populates="categories")
    products = relationship("Product", back_populates="category")

class Product(Base):
    __tablename__ = "products"

    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="SET NULL"), nullable=True)
    name = Column(String(255), nullable=False)
    sku = Column(String(100), nullable=False, index=True)
    price = Column(Numeric(12, 2), nullable=False)
    unit_cost = Column(Numeric(12, 2), default=0.00)
    stock_level = Column(Integer, default=0)
    sizes = Column(JSON, nullable=True)
    colors = Column(JSON, nullable=True)
    image_path = Column(Text, nullable=True)
    is_tax_inclusive = Column(Boolean, default=True)
    tax_rate = Column(Numeric(5, 2), default=16.00)
    zra_tax_code = Column(String(10), default="A")
    item_cls_cd = Column(String(50), default="10101501")
    is_archived = Column(Boolean, default=False, index=True)
    discount_price = Column(Numeric(12, 2), nullable=True)
    discount_start_date = Column(DateTime(timezone=True), nullable=True)
    discount_end_date = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    store = relationship("Store", back_populates="products")
    category = relationship("Category", back_populates="products")
    stock_movements = relationship("StockMovement", back_populates="product")
    __table_args__ = (UniqueConstraint("store_id", "sku", name="uk_product_store_sku"),)

class Customer(Base):
    __tablename__ = "customers"

    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    phone_number = Column(String(50), nullable=False, index=True)
    email = Column(String(255), nullable=True)
    accumulated_points = Column(Integer, default=0)
    total_spend = Column(Numeric(12, 2), default=0.00)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    store = relationship("Store", back_populates="customers")
    sales = relationship("SaleTransaction", back_populates="customer")
    __table_args__ = (UniqueConstraint("store_id", "phone_number", name="uk_customer_store_phone"),)

class SaleTransaction(Base):
    __tablename__ = "sale_transactions"

    id = Column(Integer, primary_key=True, index=True)
    transaction_uuid = Column(String(100), unique=True, nullable=False, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    total_amount = Column(Numeric(12, 2), nullable=False)
    subtotal = Column(Numeric(12, 2), nullable=False)
    tax_amount = Column(Numeric(12, 2), default=0.00)
    discount_amount = Column(Numeric(12, 2), default=0.00)
    total_cost = Column(Numeric(12, 2), default=0.00)
    gross_profit = Column(Numeric(12, 2), default=0.00)
    tendered_amount = Column(Numeric(12, 2), default=0.00)
    change_amount = Column(Numeric(12, 2), default=0.00)
    payment_method = Column(String(50), nullable=False)
    cashier_id = Column(String(50), nullable=True)
    cashier_name = Column(String(255), nullable=True)
    terminal_name = Column(String(100), nullable=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="SET NULL"), nullable=True)
    points_earned = Column(Integer, default=0)
    points_redeemed = Column(Integer, default=0)
    status = Column(String(50), default="completed")
    
    # ZRA Smart Invoice / DigiTax Metadata
    zra_receipt_number = Column(String(100), nullable=True)
    zra_mark_id = Column(String(100), nullable=True)
    zra_qr_code = Column(Text, nullable=True)
    zra_status = Column(String(50), default="pending")

    timestamp = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    is_synced = Column(Boolean, default=True)

    store = relationship("Store", back_populates="sales")
    customer = relationship("Customer", back_populates="sales")
    items = relationship("SaleItem", back_populates="sale", cascade="all, delete-orphan")

class SaleItem(Base):
    __tablename__ = "sale_items"

    id = Column(Integer, primary_key=True, index=True)
    sale_transaction_id = Column(Integer, ForeignKey("sale_transactions.id", ondelete="CASCADE"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
    product_name = Column(String(255), nullable=False)
    price_at_sale = Column(Numeric(12, 2), nullable=False)
    unit_cost_at_sale = Column(Numeric(12, 2), default=0.00)
    quantity = Column(Integer, nullable=False, default=1)
    tax_rate_at_sale = Column(Numeric(5, 2), default=0.00)
    is_tax_inclusive_at_sale = Column(Boolean, default=True)
    is_refunded = Column(Boolean, default=False)

    sale = relationship("SaleTransaction", back_populates="items")

class PurchaseOrder(Base):
    __tablename__ = "purchase_orders"

    id = Column(Integer, primary_key=True, index=True)
    po_number = Column(String(100), unique=True, nullable=False, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    supplier_name = Column(String(255), nullable=False)
    supplier_tpin = Column(String(100), nullable=True)
    status = Column(String(50), default="pending", index=True) # 'draft', 'pending', 'approved', 'received'
    total_amount = Column(Numeric(12, 2), default=0.00)
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    approved_at = Column(DateTime(timezone=True), nullable=True)

    store = relationship("Store", back_populates="purchase_orders")
    items = relationship("PurchaseOrderItem", back_populates="purchase_order", cascade="all, delete-orphan")

class PurchaseOrderItem(Base):
    __tablename__ = "purchase_order_items"

    id = Column(Integer, primary_key=True, index=True)
    purchase_order_id = Column(Integer, ForeignKey("purchase_orders.id", ondelete="CASCADE"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
    product_name = Column(String(255), nullable=False)
    unit_cost = Column(Numeric(12, 2), default=0.00)
    quantity_ordered = Column(Integer, nullable=False, default=1)
    purchase_order = relationship("PurchaseOrder", back_populates="items")

class StockMovement(Base):
    __tablename__ = "stock_movements"

    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True, index=True)
    product_name = Column(String(255), nullable=False)
    sku = Column(String(100), nullable=False, index=True)
    branch_code = Column(String(10), default="00", index=True)
    branch_name = Column(String(100), nullable=True)
    movement_type = Column(String(10), nullable=False) # '01', '02', '03', '04', '06', '11', '12', '13', '14', '15', '16'
    action_type = Column(String(20), nullable=False) # 'ADD', 'DEDUCT', 'RECOUNT'
    previous_stock = Column(Integer, default=0)
    quantity_changed = Column(Integer, default=0)
    new_stock = Column(Integer, default=0)
    unit_cost = Column(Numeric(12, 2), default=0.00)
    total_cost_impact = Column(Numeric(12, 2), default=0.00)
    reason_category = Column(String(100), nullable=False)
    reason_notes = Column(Text, nullable=True)
    user_id = Column(String(50), nullable=True)
    user_name = Column(String(255), nullable=True)
    is_synced_with_digitax = Column(Boolean, default=False)
    digitax_sar_no = Column(String(100), nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    store = relationship("Store", back_populates="stock_movements")
    product = relationship("Product", back_populates="stock_movements")


class TotReturn(Base):
    """Turnover Tax (TOT) monthly return record — ZRA Zambia."""
    __tablename__ = "tot_returns"

    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True)
    charge_year = Column(Integer, nullable=False, index=True)            # e.g. 2026
    charge_month = Column(Integer, nullable=False, index=True)           # 1–12
    gross_turnover = Column(Numeric(14, 2), nullable=False, default=0.00)  # Total sales for the month
    tot_rate = Column(Numeric(5, 2), nullable=False, default=0.00)         # 0 or 5 (%)
    tot_amount = Column(Numeric(14, 2), nullable=False, default=0.00)      # Tax owed
    due_date = Column(DateTime(timezone=True), nullable=True)              # 14th of following month
    # Status lifecycle: draft → submitted → paid
    status = Column(String(30), nullable=False, default="draft", index=True)
    digitax_reference = Column(String(100), nullable=True)                # ZRA / DigiTax ack ref
    notes = Column(Text, nullable=True)
    submitted_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    store = relationship("Store", backref="tot_returns")
    __table_args__ = (
        UniqueConstraint("store_id", "charge_year", "charge_month", name="uk_tot_store_year_month"),
    )


class AuditLog(Base):
    """Audit Trail Log for security, remote login, tenant resolution, sync, and access control events."""
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    event_type = Column(String(50), nullable=False, index=True)  # e.g., 'LOGIN_SUCCESS', 'LOGIN_FAILURE', 'UNAUTHORIZED_ACCESS_ATTEMPT', 'DATA_SYNC_BATCH'
    tpin = Column(String(100), nullable=True, index=True)
    store_id = Column(Integer, nullable=True, index=True)
    numeric_id = Column(String(50), nullable=True)
    user_id = Column(Integer, nullable=True)
    ip_address = Column(String(50), nullable=True)
    details = Column(Text, nullable=True)
    is_success = Column(Boolean, default=True)

