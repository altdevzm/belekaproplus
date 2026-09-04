import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localSqlServiceProvider = Provider<LocalSqlService>((ref) {
  throw UnimplementedError('Initialize localSqlServiceProvider in main.dart');
});

class LocalSqlService {
  static Database? _database;

  Database get db {
    if (_database == null) {
      throw StateError('Local SQL Database is not initialized');
    }
    return _database!;
  }

  /// Initialize local SQLite SQL database with FFI desktop support.
  static Future<LocalSqlService> init({Directory? customDirectory}) async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final targetDir = customDirectory ?? await getApplicationSupportDirectory();
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }
    final dbPath = p.join(targetDir.path, 'beleka_pos_local.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createSqlTables(db);
      },
      onOpen: (db) async {
        await _createSqlTables(db);
      },
    );

    debugPrint('Local SQLite SQL Database initialized successfully at: $dbPath');
    return LocalSqlService();
  }

  static Future<void> _createSqlTables(Database db) async {
    // 1. Stores Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_code TEXT UNIQUE NOT NULL,
        bhf_id TEXT DEFAULT '00',
        name TEXT NOT NULL,
        address TEXT,
        contact_number TEXT,
        email TEXT,
        tax_id TEXT,
        tpin TEXT,
        sdc_id TEXT,
        mrc_no TEXT,
        currency_symbol TEXT DEFAULT 'K',
        branch_name TEXT,
        business_tax_type TEXT DEFAULT 'VAT_STANDARD',
        digitax_api_key TEXT,
        digitax_environment TEXT DEFAULT 'sandbox',
        is_active INTEGER DEFAULT 1,
        created_at TEXT
      );
    ''');

    // 2. Users Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id INTEGER,
        numeric_id TEXT NOT NULL,
        name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'cashier',
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        UNIQUE(store_id, numeric_id)
      );
    ''');

    // 3. Categories Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id INTEGER,
        name TEXT NOT NULL,
        sector TEXT DEFAULT 'other',
        icon_path TEXT
      );
    ''');

    // 4. Products Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id INTEGER,
        category_id INTEGER,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        price REAL NOT NULL,
        unit_cost REAL DEFAULT 0.0,
        stock_level INTEGER DEFAULT 0,
        is_tax_inclusive INTEGER DEFAULT 1,
        tax_rate REAL DEFAULT 16.0,
        zra_tax_code TEXT DEFAULT 'A',
        item_cls_cd TEXT DEFAULT '10101501',
        is_archived INTEGER DEFAULT 0,
        discount_price REAL,
        created_at TEXT,
        UNIQUE(store_id, sku)
      );
    ''');

    // 5. Customers Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id INTEGER,
        name TEXT NOT NULL,
        phone_number TEXT UNIQUE NOT NULL,
        email TEXT,
        accumulated_points INTEGER DEFAULT 0,
        total_spend REAL DEFAULT 0.0,
        created_at TEXT
      );
    ''');

    // 6. Sale Transactions Table (Local SQL Cache & Sync Queue)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_uuid TEXT UNIQUE NOT NULL,
        store_id INTEGER,
        total_amount REAL NOT NULL,
        subtotal REAL NOT NULL,
        tax_amount REAL DEFAULT 0.0,
        discount_amount REAL DEFAULT 0.0,
        total_cost REAL DEFAULT 0.0,
        gross_profit REAL DEFAULT 0.0,
        tendered_amount REAL DEFAULT 0.0,
        change_amount REAL DEFAULT 0.0,
        payment_method TEXT NOT NULL,
        cashier_id TEXT,
        cashier_name TEXT,
        terminal_name TEXT,
        status TEXT DEFAULT 'completed',
        zra_receipt_number TEXT,
        zra_mark_id TEXT,
        zra_qr_code TEXT,
        zra_status TEXT DEFAULT 'pending',
        timestamp TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      );
    ''');

    // 7. Sale Items Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_transaction_id INTEGER REFERENCES sale_transactions(id) ON DELETE CASCADE,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        price_at_sale REAL NOT NULL,
        unit_cost_at_sale REAL DEFAULT 0.0,
        quantity INTEGER NOT NULL DEFAULT 1,
        tax_rate_at_sale REAL DEFAULT 0.0,
        is_tax_inclusive_at_sale INTEGER DEFAULT 1,
        is_refunded INTEGER DEFAULT 0
      );
    ''');

    // 8. Suppliers Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        tpin TEXT,
        contact_person TEXT,
        phone_number TEXT,
        email TEXT,
        address TEXT,
        balance REAL DEFAULT 0.0,
        total_purchases REAL DEFAULT 0.0,
        created_at TEXT
      );
    ''');

    // 9. Purchase Orders Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        po_number TEXT UNIQUE NOT NULL,
        store_id INTEGER,
        supplier_id INTEGER,
        supplier_name TEXT NOT NULL,
        supplier_tpin TEXT,
        status TEXT DEFAULT 'pending',
        subtotal REAL DEFAULT 0.0,
        discount_amount REAL DEFAULT 0.0,
        tax_amount REAL DEFAULT 0.0,
        total_amount REAL DEFAULT 0.0,
        expected_delivery_date TEXT,
        notes TEXT,
        created_at TEXT,
        approved_at TEXT
      );
    ''');

    // 10. Purchase Order Items Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_order_id INTEGER REFERENCES purchase_orders(id) ON DELETE CASCADE,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        unit_cost REAL DEFAULT 0.0,
        quantity_ordered INTEGER NOT NULL DEFAULT 1,
        quantity_received INTEGER DEFAULT 0,
        quantity_damaged INTEGER DEFAULT 0,
        discount REAL DEFAULT 0.0,
        tax_rate REAL DEFAULT 0.0,
        batch_number TEXT,
        expiry_date TEXT
      );
    ''');

    // 11. Goods Received Notes Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goods_received_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        grn_number TEXT UNIQUE NOT NULL,
        po_number TEXT NOT NULL,
        supplier_name TEXT NOT NULL,
        received_date TEXT NOT NULL,
        received_by TEXT,
        warehouse_branch TEXT DEFAULT 'Main Branch',
        total_items_received INTEGER DEFAULT 0,
        notes TEXT,
        created_at TEXT
      );
    ''');

    // 12. Purchase Invoices Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT UNIQUE NOT NULL,
        supplier_invoice_number TEXT,
        po_number TEXT NOT NULL,
        supplier_name TEXT NOT NULL,
        total_amount REAL DEFAULT 0.0,
        amount_paid REAL DEFAULT 0.0,
        balance_due REAL DEFAULT 0.0,
        payment_status TEXT DEFAULT 'unpaid',
        due_date TEXT,
        created_at TEXT
      );
    ''');

    // 13. Purchase Returns Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_number TEXT UNIQUE NOT NULL,
        supplier_name TEXT NOT NULL,
        po_number TEXT,
        total_amount REAL DEFAULT 0.0,
        reason TEXT NOT NULL,
        refund_method TEXT DEFAULT 'Supplier Credit Note',
        created_at TEXT
      );
    ''');

    // 14. Payment Accounts / Treasury Wallets Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        account_type TEXT NOT NULL,
        account_number TEXT,
        balance REAL DEFAULT 0.0,
        currency TEXT DEFAULT 'ZMW',
        is_default INTEGER DEFAULT 0,
        created_at TEXT
      );
    ''');

    // 15. Expenses Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_number TEXT UNIQUE NOT NULL,
        category TEXT NOT NULL,
        amount REAL DEFAULT 0.0,
        payment_account_id INTEGER,
        payment_account_name TEXT NOT NULL,
        recorded_by TEXT,
        branch TEXT DEFAULT 'Main Branch',
        reference_number TEXT,
        notes TEXT,
        receipt_image_path TEXT,
        expense_date TEXT,
        created_at TEXT
      );
    ''');

    // 16. Account Transfers Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transfer_number TEXT UNIQUE NOT NULL,
        from_account_id INTEGER,
        from_account_name TEXT NOT NULL,
        to_account_id INTEGER,
        to_account_name TEXT NOT NULL,
        amount REAL DEFAULT 0.0,
        reference TEXT,
        transferred_by TEXT,
        transfer_date TEXT,
        created_at TEXT
      );
    ''');

    // 17. Cash Shifts (Till Reconciliation) Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_number TEXT UNIQUE NOT NULL,
        cashier_id TEXT,
        cashier_name TEXT NOT NULL,
        terminal_id TEXT DEFAULT 'POS-1',
        branch_name TEXT DEFAULT 'Main Branch',
        opening_time TEXT NOT NULL,
        closing_time TEXT,
        opening_cash REAL DEFAULT 0.0,
        cash_sales REAL DEFAULT 0.0,
        cash_expenses REAL DEFAULT 0.0,
        cash_refunds REAL DEFAULT 0.0,
        cash_received REAL DEFAULT 0.0,
        cash_deposits REAL DEFAULT 0.0,
        cash_withdrawals REAL DEFAULT 0.0,
        expected_closing_cash REAL DEFAULT 0.0,
        actual_closing_cash REAL DEFAULT 0.0,
        cash_variance REAL DEFAULT 0.0,
        status TEXT DEFAULT 'OPEN',
        notes TEXT,
        created_at TEXT
      );
    ''');

    // 18. Refund Transactions Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS refund_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        refund_number TEXT UNIQUE NOT NULL,
        sale_transaction_uuid TEXT,
        refund_type TEXT NOT NULL,
        amount REAL DEFAULT 0.0,
        reason TEXT NOT NULL,
        authorized_by TEXT,
        refund_date TEXT,
        created_at TEXT
      );
    ''');

    // 19. Store Branches Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS store_branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        bhf_id TEXT DEFAULT '00',
        tpin TEXT DEFAULT '1000000000',
        address TEXT,
        phone TEXT,
        email TEXT,
        manager_id TEXT,
        manager_name TEXT,
        manager_phone TEXT,
        is_hq INTEGER DEFAULT 0,
        status TEXT DEFAULT 'ONLINE',
        zra_status TEXT DEFAULT 'FISCALIZED',
        sales_today REAL DEFAULT 0.0,
        created_at TEXT
      );
    ''');

    // 20. POS Terminals / Tills Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pos_terminals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        terminal_code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        branch_code TEXT DEFAULT '00',
        branch_name TEXT DEFAULT 'Main Branch (HQ)',
        device_ip TEXT,
        serial_number TEXT,
        assigned_cashier_id TEXT,
        assigned_cashier_name TEXT,
        status TEXT DEFAULT 'ACTIVE',
        digitax_bhf_id TEXT DEFAULT '00',
        sales_today REAL DEFAULT 0.0,
        last_active TEXT,
        created_at TEXT
      );
    ''');

    // 21. Stock Movements Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        sku TEXT NOT NULL,
        branch_code TEXT DEFAULT '00',
        branch_name TEXT,
        movement_type TEXT NOT NULL,
        action_type TEXT NOT NULL,
        previous_stock INTEGER NOT NULL,
        quantity_changed INTEGER NOT NULL,
        new_stock INTEGER NOT NULL,
        unit_cost REAL DEFAULT 0.0,
        total_cost_impact REAL DEFAULT 0.0,
        reason_category TEXT NOT NULL,
        reason_notes TEXT,
        user_id TEXT,
        user_name TEXT,
        is_synced_with_digitax INTEGER DEFAULT 0,
        digitax_sar_no TEXT,
        timestamp TEXT NOT NULL
      );
    ''');

    // Create SQL Indexes for high performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_synced ON sale_transactions(is_synced);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_uuid ON sale_transactions(transaction_uuid);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_prod ON stock_movements(product_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_branch ON stock_movements(branch_code);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_time ON stock_movements(timestamp);');
  }

  // --- SQL HELPER METHODS ---

  /// Execute raw SELECT SQL query
  Future<List<Map<String, dynamic>>> query(String sql, [List<dynamic>? arguments]) async {
    return await db.rawQuery(sql, arguments);
  }

  /// Insert record into a SQL table
  Future<int> insert(String table, Map<String, dynamic> values) async {
    return await db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Update records in a SQL table
  Future<int> update(String table, Map<String, dynamic> values, {String? where, List<dynamic>? whereArgs}) async {
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }

  /// Delete records from a SQL table
  Future<int> delete(String table, {String? where, List<dynamic>? whereArgs}) async {
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  /// Execute custom SQL statement
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {
    await db.execute(sql, arguments);
  }

  /// Get pending unsynced sales from local SQL database
  Future<List<Map<String, dynamic>>> getUnsyncedSales() async {
    return await db.rawQuery('SELECT * FROM sale_transactions WHERE is_synced = 0');
  }

  /// Mark transactions as synced after uploading to cloud PostgreSQL DB
  Future<void> markSalesAsSynced(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final placeholders = List.filled(uuids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE sale_transactions SET is_synced = 1 WHERE transaction_uuid IN ($placeholders)',
      uuids,
    );
  }
}
