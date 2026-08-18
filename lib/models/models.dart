import 'package:isar/isar.dart';

part 'models.g.dart';

@collection
class User {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String numericId; // Unique ID for login (e.g. 1001)
  
  late String name;
  late String passwordHash; 
  late String role; // 'manager', 'cashier'
  
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
  double taxRate = 0.0;
  
  @Index()
  bool isArchived = false;

  double? discountPrice;
  DateTime? discountStartDate;
  DateTime? discountEndDate;

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
    this.taxRate = 0.0,
    this.isArchived = false,
    this.discountPrice,
    this.discountStartDate,
    this.discountEndDate,
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
    this.transactionId,
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
  bool isRefunded = false;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.priceAtSale,
    this.unitCostAtSale = 0.0,
    this.quantity = 1,
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
