import 'package:isar/isar.dart';

part 'models.g.dart';

@collection
class User {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String numericId; // Unique ID for login (e.g. 1001)
  
  late String name;
  late String passwordHash; 
  late String role; // 'owner', 'branch_manager', 'cashier'
  
  String? branchName; // e.g. 'Main Branch (HQ)', 'Kitwe Retail Store'
  String? branchCode; // e.g. '00', '01'
  String? phone;
  
  @Index()
  bool isActive = true;
}

enum CategorySector {
  pharmacy,
  stationery,
  grocery,
  food,
  restaurant,
  other
}

@collection
class Category {
  Id id = Isar.autoIncrement;

  late String name;
  String iconPath = '';
  
  @enumerated
  CategorySector sector = CategorySector.other;

  Category({
    required this.name, 
    this.iconPath = '', 
    this.sector = CategorySector.other
  });
}

@collection
class Product {
  Id id = Isar.autoIncrement;

  late String name;
  @Index()
  late String sku;
  late double price;
  late int stockLevel;
  late int categoryId;
  
  double unitCost = 0.0;
  
  List<String>? sizes;
  List<String>? colors;
  
  String? imagePath;
  
  bool isTaxInclusive = true;
  double taxRate = 16.0;
  
  // ZRA Smart Invoice / EFD Tax Classification
  String zraTaxCode = 'A'; // 'A' (Standard 16%), 'B' (Zero 0%), 'C' (Exempt 0%), 'E' (Non-VAT), 'TOT' (Turnover 3%)
  String itemClsCd = '10101501';

  // Multi-Branch Store Isolation (bhfId: '00' = HQ, '01' = Branch 1, etc.)
  @Index()
  String branchCode = '00';
  String? branchName;

  // DigiTax Inventory Synchronization Status
  bool isSyncedWithDigitax = false;
  DateTime? lastDigitaxSyncDate;
  
  @Index()
  bool isArchived = false;

  double? discountPrice;
  DateTime? discountStartDate;
  DateTime? discountEndDate;

  // Electronic Scale & Unit of Measure
  bool isWeighted = false; // true = Sold by weight / requires scale
  String unitOfMeasure = 'kg'; // 'kg', 'g', 'pcs', 'unit', 'ltr', 'lb'
  double tareWeight = 0.0; // Default container / tray tare weight in kg
  String? scalePlu; // In-store PLU code for embedded weight barcodes

  Product({
    required this.name,
    required this.sku,
    required this.price,
    required this.stockLevel,
    required this.categoryId,
    this.unitCost = 0.0,
    this.sizes,
    this.colors,
    this.imagePath,
    this.isTaxInclusive = true,
    this.taxRate = 16.0,
    this.zraTaxCode = 'A',
    this.itemClsCd = '10101501',
    this.branchCode = '00',
    this.branchName,
    this.isSyncedWithDigitax = false,
    this.lastDigitaxSyncDate,
    this.isArchived = false,
    this.discountPrice,
    this.discountStartDate,
    this.discountEndDate,
    this.isWeighted = false,
    this.unitOfMeasure = 'kg',
    this.tareWeight = 0.0,
    this.scalePlu,
  });
}

@collection
class SaleTransaction {
  Id id = Isar.autoIncrement;

  late double totalAmount;
  late String paymentMethod;
  late String cashierName;
  late String status;
  late double subtotal;
  late double taxAmount;
  late double discountAmount;
  late double totalCost;
  late double grossProfit;
  double tenderedAmount = 0.0;
  double changeAmount = 0.0;
  int? customerId;
  int pointsEarned;
  int pointsRedeemed;
  @Index()
  late DateTime timestamp;

  @Index(unique: true)
  String? transactionId; // Unique UUID for sync tracking

  bool isSynced = false;
  String? cashierId;
  String? terminalName;

  // B2B Corporate / Tax Invoice Customer Data
  String? customerTpin;
  String? customerBusinessName;
  String? customerAddress;

  // ZRA Smart Invoice / EFD Fiscal Data
  String? zraSdcId;
  String? zraReceiptNumber;
  String? zraMarkId;
  String? zraInternalData;
  String? zraQrCode;
  String? zraInvoiceType;
  String zraStatus = 'pending';

  // ZRA Credit Note / Fiscal Return Fields
  bool isCreditNote = false;
  String? orgInvoiceNo;
  String? creditNoteReason;

  SaleTransaction({
    required this.totalAmount,
    required this.paymentMethod,
    this.cashierName = '',
    this.status = 'completed',
    this.subtotal = 0.0,
    this.taxAmount = 0.0,
    this.discountAmount = 0.0,
    this.totalCost = 0.0,
    this.grossProfit = 0.0,
    this.tenderedAmount = 0.0,
    this.changeAmount = 0.0,
    this.customerId,
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
    this.isSynced = false,
    this.cashierId,
    this.terminalName,
    this.customerTpin,
    this.customerBusinessName,
    this.customerAddress,
    this.transactionId,
    this.zraSdcId,
    this.zraReceiptNumber,
    this.zraMarkId,
    this.zraInternalData,
    this.zraQrCode,
    this.zraInvoiceType,
    this.zraStatus = 'pending',
    this.isCreditNote = false,
    this.orgInvoiceNo,
    this.creditNoteReason,
  }) : timestamp = DateTime.now() {
    transactionId ??= _generateUuid();
  }

  static String _generateUuid() {
    // Simple enough for our needs without extra dependency
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    return 'tx-$random-${(1000 + (DateTime.now().millisecond * 10)).toString()}';
  }

  final items = IsarLinks<SaleItem>();
}

@collection
class SaleItem {
  Id id = Isar.autoIncrement;

  late int productId;
  late String productName;
  late double priceAtSale;
  double unitCostAtSale = 0.0;
  int quantity = 1;
  double weight = 0.0; // In kg/g
  bool isWeighted = false;
  String unitOfMeasure = 'kg'; // 'kg', 'g', 'pcs', 'unit', 'ltr', 'lb'
  bool isRefunded = false;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.priceAtSale,
    this.unitCostAtSale = 0.0,
    this.quantity = 1,
    this.weight = 0.0,
    this.isWeighted = false,
    this.unitOfMeasure = 'kg',
    this.isRefunded = false,
    this.taxRateAtSale = 0.0,
    this.isTaxInclusiveAtSale = true,
  });

  double taxRateAtSale = 0.0;
  bool isTaxInclusiveAtSale = true;
}

@collection
class AttendanceLog {
  Id id = Isar.autoIncrement;

  late int userId;
  late String username;
  @Index()
  late DateTime timestamp;
  late String type; // 'clock_in', 'clock_out'
}

@collection
class StoreConfig {
  Id id = Isar.autoIncrement;

  late String businessName;
  String? address;
  String? contactNumber;
  String? taxId;
  String? tpin; // ZRA TPIN
  String? sdcId;
  String? mrcNo;
  String? currencySymbol;
  
  // Terminal Identifier
  late String terminalName;
  
  // Branding, Contact & Document Theming
  String? logoPath;
  String? email;
  String? website;
  String? brandColorHex; // Hex string e.g. #C1F11D, #1A73E8, etc.
  String? branchName;
  
  @enumerated
  CategorySector primarySector = CategorySector.other;

  // Security
  String? recoveryCodeHash;
  
  double taxRate = 16.0; // Default VAT in Zambia
  
  // Loyalty Program System Settings
  bool loyaltyEnabled = false;
  double loyaltyEarnRate = 1.0; // Points earned per 1 unit of currency
  double loyaltyRedemptionValue = 0.01; // Currency value per 1 point redeemed

  // Backup & Security
  String? backupPath;
  DateTime? lastBackupDate;

  // Cloud PostgreSQL Database & Multi-Store Configuration
  bool isCloudSyncEnabled = true;
  String? cloudApiUrl = 'http://23.139.36.20:8003';
  int? cloudStoreId = 1;
  String? cloudStoreCode = 'STORE-001';
  DateTime? lastCloudSyncDate;


  // ZRA Smart Invoice / DigiTax API Configuration
  String bhfId = '00'; // ZRA Branch Code ('00' = HQ, '01' = Branch 1, '02' = Branch 2)
  String businessTaxType = 'VAT_STANDARD'; // 'VAT_STANDARD', 'TURNOVER_TAX', 'EXEMPT', 'COMPOSITE'
  String? digitaxApiKey;
  String digitaxEnvironment = 'sandbox'; // 'sandbox', 'production'

  // Network Multi-Terminal Settings
  bool isManagerMode = true; // true = Server/Manager, false = Terminal/Cashier
  String? serverIp; // IP of the manager terminal (for client mode)
  int port = 8080;

  // Printer & Hardware Configuration
  String? defaultPrinterName;
  String? defaultPrinterAddress;
  String? defaultPrinterType; // 'usb', 'network', 'bluetooth', 'system'
  String? defaultPrinterModel; // 'generic', 'star', 'system'
  int paperWidthMm = 80;
  bool autoPrintReceipt = true;

  // Cash Drawer Hardware & Driver Settings
  bool autoOpenCashDrawer = true; // Auto-kick drawer on payment completion
  bool openDrawerCashOnly = false; // true = cash/split only, false = all payment methods
  int cashDrawerPin = 2; // 2 = Standard Pin 2 (0x00), 5 = Pin 5 (0x01)
  int cashDrawerPulseOnMs = 50; // Pulse ON duration in ms
  int cashDrawerPulseOffMs = 250; // Pulse OFF duration in ms

  // Electronic Weight Scale Hardware & Driver Settings
  bool scaleEnabled = true;
  String scalePort = 'COM1'; // e.g. 'COM1', 'COM3', '/dev/ttyUSB0', '127.0.0.1:9001'
  int scaleBaudRate = 9600; // 9600, 4800, 19200, 115200
  String scaleProtocol = 'generic'; // 'generic', 'toledo', 'cas', 'avery', 'bridge'
  double defaultTareWeight = 0.0;
}

@collection
class Customer {
  Id id = Isar.autoIncrement;

  late String name;
  
  @Index(unique: true)
  late String phoneNumber;
  
  String? email;
  
  // Loyalty balance
  int accumulatedPoints = 0;
  
  DateTime? createdAt;
  
  double totalSpend = 0.0;

  Customer({
    this.id = Isar.autoIncrement,
    required this.name,
    required this.phoneNumber,
    this.email,
    this.accumulatedPoints = 0,
    this.totalSpend = 0.0,
    this.createdAt,
  });

  Customer copyWith({
    Id? id,
    String? name,
    String? phoneNumber,
    String? email,
    int? accumulatedPoints,
    double? totalSpend,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      accumulatedPoints: accumulatedPoints ?? this.accumulatedPoints,
      totalSpend: totalSpend ?? this.totalSpend,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

@collection
class Supplier {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String name;

  String? tpin;
  String? contactPerson;
  String? phoneNumber;
  String? email;
  String? address;
  double balance = 0.0; // Outstanding balance owed to supplier
  double totalPurchases = 0.0;
  
  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class PurchaseOrder {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String poNumber;

  late int storeId;
  int? supplierId;
  late String supplierName;
  String? supplierTpin;
  late String status; // 'draft', 'pending', 'approved', 'received', 'cancelled'
  double subtotal = 0.0;
  double discountAmount = 0.0;
  double taxAmount = 0.0;
  double totalAmount = 0.0;
  DateTime? expectedDeliveryDate;
  String? notes;
  
  @Index()
  DateTime createdAt = DateTime.now();
  
  DateTime? approvedAt;

  final items = IsarLinks<PurchaseOrderItem>();
}

@collection
class PurchaseOrderItem {
  Id id = Isar.autoIncrement;

  int? productId;
  late String productName;
  double unitCost = 0.0;
  int quantityOrdered = 1;
  int quantityReceived = 0;
  int quantityDamaged = 0;
  double discount = 0.0;
  double taxRate = 0.0;
  String? batchNumber;
  DateTime? expiryDate;
}

@collection
class GoodsReceivedNote {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String grnNumber;

  late String poNumber;
  late String supplierName;
  DateTime receivedDate = DateTime.now();
  String? receivedBy;
  String warehouseBranch = 'Main Branch';
  int totalItemsReceived = 0;
  String? notes;
  
  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class PurchaseInvoice {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String invoiceNumber;

  String? supplierInvoiceNumber;
  late String poNumber;
  late String supplierName;
  double totalAmount = 0.0;
  double amountPaid = 0.0;
  double balanceDue = 0.0;
  late String paymentStatus; // 'unpaid', 'partial', 'paid'
  DateTime? dueDate;
  
  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class PurchaseReturn {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String returnNumber;

  late String supplierName;
  String? poNumber;
  double totalAmount = 0.0;
  late String reason; // 'Damaged Goods', 'Expired Stock', 'Wrong Item Received', 'Excess Delivery'
  String refundMethod = 'Supplier Credit Note'; // 'Cash Refund', 'Supplier Credit Note'
  
  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class PaymentAccount {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String name; // 'Cash in Till', 'Main Bank Account', 'Airtel Money', 'MTN Money', 'Zamtel Money', 'Visa/Mastercard'

  late String accountType; // 'CASH', 'BANK', 'AIRTEL_MONEY', 'MTN_MONEY', 'ZAMTEL_MONEY', 'CARD', 'OTHER'
  String? accountNumber;
  double balance = 0.0;
  String currency = 'ZMW';
  bool isDefault = false;

  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class Expense {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String expenseNumber;

  late String category; // 'Rent', 'Utilities', 'Salaries & Wages', 'Transport / Fuel', 'Inventory & Supplies', 'Repairs', 'Marketing', 'Other'
  double amount = 0.0;
  int? paymentAccountId;
  late String paymentAccountName;
  String? recordedBy;
  String branch = 'Main Branch';
  String? referenceNumber;
  String? notes;
  String? receiptImagePath;
  
  @Index()
  DateTime expenseDate = DateTime.now();

  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class AccountTransfer {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String transferNumber;

  int? fromAccountId;
  late String fromAccountName;
  int? toAccountId;
  late String toAccountName;
  double amount = 0.0;
  String? reference;
  String? transferredBy;

  @Index()
  DateTime transferDate = DateTime.now();

  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class CashShift {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String shiftNumber;

  String? cashierId;
  late String cashierName;
  String terminalId = 'POS-1';
  String branchName = 'Main Branch';
  DateTime openingTime = DateTime.now();
  DateTime? closingTime;
  
  double openingCash = 0.0;
  double cashSales = 0.0;
  double cashExpenses = 0.0;
  double cashRefunds = 0.0;
  double cashReceived = 0.0;
  double cashDeposits = 0.0;
  double cashWithdrawals = 0.0;
  
  double expectedClosingCash = 0.0;
  double actualClosingCash = 0.0;
  double cashVariance = 0.0; // Actual - Expected
  
  late String status; // 'OPEN', 'CLOSED'
  String? notes;

  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class RefundTransaction {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String refundNumber;

  String? saleTransactionUuid;
  late String refundType; // 'CASH', 'CARD', 'MOBILE_MONEY', 'CREDIT_NOTE'
  double amount = 0.0;
  late String reason;
  String? authorizedBy;
  
  @Index()
  DateTime refundDate = DateTime.now();

  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class StoreBranch {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String code; // e.g. 'HQ-001', 'KT-002', 'ND-003'

  late String name;
  
  @Index()
  late String bhfId; // ZRA Branch Code ('00' = HQ, '01', '02', etc.)
  
  String tpin = '1000000000';
  String? sdcId;
  String? mrcNo;
  String? address;
  String? phone;
  String? email;
  
  String? managerId;
  String? managerName;
  String? managerPhone;
  
  bool isHQ = false;
  String status = 'ONLINE'; // 'ONLINE', 'OFFLINE'
  String zraStatus = 'FISCALIZED'; // 'FISCALIZED', 'PENDING'
  double salesToday = 0.0;
  
  @Index()
  DateTime createdAt = DateTime.now();
}

@collection
class PosTerminal {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String terminalCode; // e.g. 'TILL-01', 'POS-01', 'TILL-CBD-02'

  late String name; // e.g. 'Main Counter Till 1'
  String branchCode = '00';
  String branchName = 'Main Branch (HQ)';
  
  String? deviceIp;
  String? serialNumber;
  
  String? assignedCashierId;
  String? assignedCashierName;
  
  String status = 'ACTIVE'; // 'ACTIVE', 'INACTIVE', 'MAINTENANCE'
  String digitaxBhfId = '00'; // DigiTax Branch / Till ID
  
  double salesToday = 0.0;
  
  @Index()
  DateTime lastActive = DateTime.now();
  
  @Index()
  DateTime createdAt = DateTime.now();
}
