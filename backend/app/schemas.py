from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel, ConfigDict

class StoreBase(BaseModel):
    store_code: str
    bhf_id: Optional[str] = "00"
    name: str
    address: Optional[str] = None
    contact_number: Optional[str] = None
    email: Optional[str] = None
    tax_id: Optional[str] = None
    tpin: Optional[str] = None
    sdc_id: Optional[str] = None
    mrc_no: Optional[str] = None
    currency_symbol: Optional[str] = "K"
    branch_name: Optional[str] = None
    manager_name: Optional[str] = None
    manager_id: Optional[str] = None
    manager_phone: Optional[str] = None
    business_tax_type: Optional[str] = "VAT_STANDARD"
    digitax_api_key: Optional[str] = None
    digitax_environment: Optional[str] = "sandbox"

class StoreCreate(StoreBase):
    pass

class StoreUpdate(BaseModel):
    store_code: Optional[str] = None
    bhf_id: Optional[str] = None
    name: Optional[str] = None
    address: Optional[str] = None
    contact_number: Optional[str] = None
    email: Optional[str] = None
    tax_id: Optional[str] = None
    tpin: Optional[str] = None
    sdc_id: Optional[str] = None
    mrc_no: Optional[str] = None
    currency_symbol: Optional[str] = None
    branch_name: Optional[str] = None
    manager_name: Optional[str] = None
    manager_id: Optional[str] = None
    manager_phone: Optional[str] = None
    business_tax_type: Optional[str] = None
    digitax_api_key: Optional[str] = None
    digitax_environment: Optional[str] = None

class StoreResponse(StoreBase):
    id: int
    is_active: Optional[bool] = True
    created_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

class UserBase(BaseModel):
    numeric_id: str
    name: str
    role: str
    branch_name: Optional[str] = None
    phone: Optional[str] = None
    is_active: Optional[bool] = True

class UserCreate(UserBase):
    store_id: Optional[int] = 1
    password_hash: str

class UserResponse(UserBase):
    id: int
    store_id: Optional[int] = None
    created_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

class ProductBase(BaseModel):
    sku: str
    name: str
    price: float
    unit_cost: Optional[float] = 0.0
    stock_level: Optional[int] = 0
    category_id: Optional[int] = None
    is_tax_inclusive: Optional[bool] = True
    tax_rate: Optional[float] = 16.0
    zra_tax_code: Optional[str] = "A"
    item_cls_cd: Optional[str] = "10101501"
    is_archived: Optional[bool] = False
    discount_price: Optional[float] = None

class ProductCreate(ProductBase):
    store_id: int

class ProductResponse(ProductBase):
    id: int
    store_id: int
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class SaleItemBase(BaseModel):
    product_id: Optional[int] = None
    product_name: str
    price_at_sale: float
    unit_cost_at_sale: Optional[float] = 0.0
    quantity: int
    tax_rate_at_sale: Optional[float] = 0.0
    is_tax_inclusive_at_sale: Optional[bool] = True
    zra_tax_code: Optional[str] = None

class SaleTransactionCreate(BaseModel):
    transaction_uuid: str
    store_id: int
    total_amount: float
    subtotal: float
    tax_amount: Optional[float] = 0.0
    discount_amount: Optional[float] = 0.0
    total_cost: Optional[float] = 0.0
    gross_profit: Optional[float] = 0.0
    tendered_amount: Optional[float] = 0.0
    change_amount: Optional[float] = 0.0
    payment_method: str
    cashier_id: Optional[str] = None
    cashier_name: Optional[str] = None
    terminal_name: Optional[str] = None
    customer_id: Optional[int] = None
    points_earned: Optional[int] = 0
    points_redeemed: Optional[int] = 0
    items: List[SaleItemBase]

class SyncBatchRequest(BaseModel):
    store_id: int
    sales: List[SaleTransactionCreate]

class PurchaseOrderItemBase(BaseModel):
    product_id: Optional[int] = None
    product_name: str
    unit_cost: float
    quantity_ordered: int

class PurchaseOrderCreate(BaseModel):
    po_number: str
    store_id: int
    supplier_name: str
    supplier_tpin: Optional[str] = None
    total_amount: float
    notes: Optional[str] = None
    items: List[PurchaseOrderItemBase]

class PurchaseOrderResponse(BaseModel):
    id: int
    po_number: str
    store_id: int
    supplier_name: str
    supplier_tpin: Optional[str] = None
    status: str
    total_amount: float
    notes: Optional[str] = None
    created_at: datetime
    approved_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

class LoginRequest(BaseModel):
    numeric_id: str
    pin: str
    tpin: Optional[str] = None
    branch_code: Optional[str] = None
    company_name: Optional[str] = None
    terminal_name: Optional[str] = "TERMINAL"

class RegistrationRequest(BaseModel):
    business_name: str
    tpin: str
    numeric_id: str
    pin: str
    owner_name: str = "Owner"
    store_code: str = "HQ-00"
    branch_name: str = "Headquarters (HQ)"
    terminal_name: Optional[str] = "MANAGER-01"

class OrganizationLookupRequest(BaseModel):
    company_name: str

class OrganizationLookupResponse(BaseModel):
    company_name: str
    tpin: str

class AuditLogResponse(BaseModel):
    id: int
    timestamp: datetime
    event_type: str
    tpin: Optional[str] = None
    store_id: Optional[int] = None
    numeric_id: Optional[str] = None
    user_id: Optional[int] = None
    ip_address: Optional[str] = None
    details: Optional[str] = None
    is_success: bool
    model_config = ConfigDict(from_attributes=True)

