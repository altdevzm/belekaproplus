import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
// isar imported above at line 6


/// Tracks connected terminals on the Manager's server.
class TerminalInfo {
  final String terminalName;
  final String cashierId;
  final String cashierName;
  final DateTime connectedAt;
  DateTime lastHeartbeat;
  double salesToday;
  int transactionCount;

  TerminalInfo({
    required this.terminalName,
    required this.cashierId,
    required this.cashierName,
    required this.connectedAt,
    DateTime? lastHeartbeat,
    this.salesToday = 0.0,
    this.transactionCount = 0,
  }) : lastHeartbeat = lastHeartbeat ?? connectedAt;

  Map<String, dynamic> toJson() => {
        'terminalName': terminalName,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'connectedAt': connectedAt.toIso8601String(),
        'lastHeartbeat': lastHeartbeat.toIso8601String(),
        'salesToday': salesToday,
        'transactionCount': transactionCount,
      };
}

/// The local LAN API server that runs ONLY on the Manager's terminal.
/// It exposes an HTTP REST API over the local network so that
/// cashier terminals can authenticate, fetch products, and push sales.
class ApiService {
  final DatabaseService _db;
  HttpServer? _server;
  final Map<String, TerminalInfo> _activeTerminals = {};
  final _terminalUpdateController = StreamController<List<TerminalInfo>>.broadcast();

  ApiService(this._db);

  Stream<List<TerminalInfo>> get terminalsStream => _terminalUpdateController.stream;

  void _notifyTerminals() {
    _terminalUpdateController.add(_activeTerminals.values.toList());
  }

  /// The IP address this server is listening on.
  String? get hostIp => _hostIp;
  String? _hostIp;

  /// The port this server is listening on.
  int get port => _port;
  int _port = 8080;

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// Immutable snapshot of the active terminals map.
  Map<String, TerminalInfo> get activeTerminals =>
      Map.unmodifiable(_activeTerminals);

  // ─── Lifecycle ────────────────────────────────────────────────

  Future<void> start({int port = 8080}) async {
    if (_server != null) return; // already running

    _port = port;

    final router = Router();
    _registerRoutes(router);

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    // Detect the device's LAN IP
    try {
      final info = NetworkInfo();
      _hostIp = await info.getWifiIP();
    } catch (_) {
      _hostIp = null;
    }
    _hostIp ??= '0.0.0.0';

    _server = await shelf_io.serve(handler, '0.0.0.0', _port);
    debugPrint('SERVER_STARTED: Beleka POS API running on $_hostIp:$_port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _activeTerminals.clear();
    debugPrint('SERVER_STOPPED');
  }

  // ─── Route Registration ───────────────────────────────────────

  void _registerRoutes(Router router) {
    router.get('/status', _handleStatus);
    router.get('/health', _handleStatus);
    router.get('/info', _handleStatus);
    router.post('/auth/login', _handleLogin);
    router.get('/products', _handleGetProducts);
    router.get('/categories', _handleGetCategories);
    router.post('/transactions', _handlePostTransaction);
    router.post('/transactions/batch', _handleBatchTransactions);
    router.get('/terminals', _handleGetTerminals);
    router.post('/terminals/heartbeat', _handleHeartbeat);

    // User management (Manager only)
    router.get('/users', _handleGetUsers);
    router.post('/users', _handleCreateUser);
    router.delete('/users/<id>', _handleDeleteUser);
  }

  // ─── Handlers ─────────────────────────────────────────────────

  Future<Response> _handleStatus(Request request) async {
    final config = await _db.getStoreConfig();
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'serverName': config?.businessName ?? 'Beleka POS Manager',
        'businessName': config?.businessName ?? 'Beleka POS',
        'branchName': config?.branchName ?? 'Main Branch',
        'branchCode': (config?.bhfId != null && config!.bhfId.isNotEmpty) ? config.bhfId : '00',
        'bhfId': (config?.bhfId != null && config!.bhfId.isNotEmpty) ? config.bhfId : '00',
        'currencySymbol': config?.currencySymbol ?? 'ZK',
        'tpin': config?.tpin ?? '',
        'businessTaxType': config?.businessTaxType ?? 'TURNOVER_TAX',
        'maxTills': 3,
        'timestamp': DateTime.now().toIso8601String(),
        'activeTerminals': _activeTerminals.length,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _handleLogin(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final numericId = body['numericId'] as String?;
      final password = body['password'] as String?;
      final terminalName = body['terminalName'] as String?;

      if (numericId == null || password == null) {
        return Response(400,
            body: jsonEncode({'error': 'numericId and password required'}),
            headers: _jsonHeaders);
      }

      final hashedPin = hashPin(password);
      final user = await _db.isar.users
          .filter()
          .numericIdEqualTo(numericId)
          .passwordHashEqualTo(hashedPin)
          .findFirst();

      if (user == null || !user.isActive) {
        return Response(401,
            body: jsonEncode({'error': 'Invalid credentials or inactive user'}),
            headers: _jsonHeaders);
      }

      // Enforce Till Capacity Limit (Max 3 Tills default)
      if (terminalName != null && terminalName.isNotEmpty) {
        final existingTerminals = await _db.isar.posTerminals.where().findAll();
        final isKnownTerminal = existingTerminals.any((t) => t.terminalCode == terminalName || t.name == terminalName) ||
            _activeTerminals.containsKey(terminalName);

        if (!isKnownTerminal && (_activeTerminals.length >= 3 || existingTerminals.length >= 3)) {
          return Response(403,
              body: jsonEncode({
                'error': 'Maximum till limit reached (Max 3 tills allowed on this license). Upgrade your license to connect additional tills.'
              }),
              headers: _jsonHeaders);
        }

        _activeTerminals[terminalName] = TerminalInfo(
          terminalName: terminalName,
          cashierId: user.numericId,
          cashierName: user.name,
          connectedAt: DateTime.now(),
        );
        _notifyTerminals();
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'user': {
            'id': user.id,
            'numericId': user.numericId,
            'name': user.name,
            'role': user.role,
          },
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetProducts(Request request) async {
    try {
      final products = await _db.getAllProducts();
      final jsonList = products.map(_productToJson).toList();
      return Response.ok(jsonEncode(jsonList), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetCategories(Request request) async {
    try {
      final categories = await _db.getAllCategories();
      final jsonList = categories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'iconPath': c.iconPath,
                'sector': c.sector.index,
              })
          .toList();
      return Response.ok(jsonEncode(jsonList), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handlePostTransaction(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final txData = body['transaction'] as Map<String, dynamic>;
      final itemsData = body['items'] as List<dynamic>;

      final transaction = _jsonToTransaction(txData);
      final items =
          itemsData.map((i) => _jsonToSaleItem(i as Map<String, dynamic>)).toList();

      // DEDUPLICATION: Check if this transaction already exists on the server
      if (transaction.transactionId != null) {
        final existing = await _db.isar.saleTransactions
            .filter()
            .transactionIdEqualTo(transaction.transactionId)
            .findFirst();
        if (existing != null) {
          return Response.ok(
            jsonEncode({'success': true, 'transactionId': existing.id, 'duplicate': true}),
            headers: _jsonHeaders,
          );
        }
      }

      await _db.saveTransaction(transaction, items);

      // Update terminal stats if known
      if (transaction.terminalName != null && _activeTerminals.containsKey(transaction.terminalName)) {
        final info = _activeTerminals[transaction.terminalName]!;
        info.salesToday += transaction.totalAmount;
        info.transactionCount += 1;
        info.lastHeartbeat = DateTime.now();
        _notifyTerminals();
      }

      return Response.ok(
        jsonEncode({'success': true, 'transactionId': transaction.id}),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleBatchTransactions(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final batch = body['transactions'] as List<dynamic>;
      int successCount = 0;

      for (final entry in batch) {
        try {
          final txData = entry['transaction'] as Map<String, dynamic>;
          final itemsData = entry['items'] as List<dynamic>;

          final transaction = _jsonToTransaction(txData);
          final items = itemsData
              .map((i) => _jsonToSaleItem(i as Map<String, dynamic>))
              .toList();

          await _db.saveTransaction(transaction, items);
          successCount++;

          // Update terminal stats
          if (transaction.terminalName != null && _activeTerminals.containsKey(transaction.terminalName)) {
            final info = _activeTerminals[transaction.terminalName]!;
            info.salesToday += transaction.totalAmount;
            info.transactionCount += 1;
            info.lastHeartbeat = DateTime.now();
          }
        } catch (e) {
          debugPrint('BATCH_SYNC_ERROR: $e');
        }
      }
      _notifyTerminals();

      return Response.ok(
        jsonEncode({
          'success': true,
          'synced': successCount,
          'total': batch.length,
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Response _handleGetTerminals(Request request) {
    // Clean up stale terminals (no heartbeat for 5 minutes)
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _activeTerminals
        .removeWhere((_, info) => info.lastHeartbeat.isBefore(cutoff));

    final list = _activeTerminals.values.map((t) => t.toJson()).toList();
    return Response.ok(jsonEncode(list), headers: _jsonHeaders);
  }

  Future<Response> _handleHeartbeat(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final terminalName = body['terminalName'] as String?;

      if (terminalName != null && _activeTerminals.containsKey(terminalName)) {
        _activeTerminals[terminalName]!.lastHeartbeat = DateTime.now();
        _notifyTerminals();
      }

      return Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetUsers(Request request) async {
    try {
      final users = await _db.getAllUsers();
      final jsonList = users
          .map((u) => {
                'id': u.id,
                'numericId': u.numericId,
                'name': u.name,
                'role': u.role,
                'passwordHash': u.passwordHash,
                'branchCode': u.branchCode,
                'branchName': u.branchName,
                'isActive': u.isActive,
              })
          .toList();
      return Response.ok(jsonEncode(jsonList), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleCreateUser(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final String numericId = body['numericId'] as String;
      
      // Check for uniqueness
      final existing = await _db.getUserByNumericId(numericId);
      if (existing != null) {
        return Response.forbidden(
          jsonEncode({'success': false, 'error': 'Staff ID already exists'}),
          headers: _jsonHeaders,
        );
      }

      final user = User()
        ..numericId = numericId
        ..name = body['name'] as String
        ..passwordHash = hashPin(body['password'] as String)
        ..role = body['role'] as String? ?? 'cashier'
        ..isActive = true;

      await _db.saveUser(user);

      return Response.ok(
        jsonEncode({'success': true, 'userId': user.id}),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleDeleteUser(Request request, String id) async {
    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response(400,
            body: jsonEncode({'error': 'Invalid user ID'}),
            headers: _jsonHeaders);
      }
      await _db.deleteUser(userId);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  // ─── JSON Helpers ─────────────────────────────────────────────

  static Map<String, dynamic> _productToJson(Product p) => {
        'id': p.id,
        'name': p.name,
        'sku': p.sku,
        'price': p.price,
        'stockLevel': p.stockLevel,
        'categoryId': p.categoryId,
        'unitCost': p.unitCost,
        'isTaxInclusive': p.isTaxInclusive,
        'taxRate': p.taxRate,
        'isArchived': p.isArchived,
        'discountPrice': p.discountPrice,
        'imagePath': p.imagePath,
      };

  static SaleTransaction _jsonToTransaction(Map<String, dynamic> j) {
    final tx = SaleTransaction(
      totalAmount: (j['totalAmount'] as num).toDouble(),
      paymentMethod: j['paymentMethod'] as String,
      cashierName: j['cashierName'] as String? ?? '',
      status: j['status'] as String? ?? 'completed',
      subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (j['taxAmount'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (j['discountAmount'] as num?)?.toDouble() ?? 0.0,
      totalCost: (j['totalCost'] as num?)?.toDouble() ?? 0.0,
      grossProfit: (j['grossProfit'] as num?)?.toDouble() ?? 0.0,
      tenderedAmount: (j['tenderedAmount'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (j['changeAmount'] as num?)?.toDouble() ?? 0.0,
      isSynced: true,
      cashierId: j['cashierId'] as String?,
      terminalName: j['terminalName'] as String?,
      transactionId: j['transactionId'] as String?,
    );
    return tx;
  }

  static SaleItem _jsonToSaleItem(Map<String, dynamic> j) {
    return SaleItem(
      productId: j['productId'] as int,
      productName: j['productName'] as String,
      priceAtSale: (j['priceAtSale'] as num).toDouble(),
      unitCostAtSale: (j['unitCostAtSale'] as num?)?.toDouble() ?? 0.0,
      quantity: j['quantity'] as int? ?? 1,
      isRefunded: j['isRefunded'] as bool? ?? false,
      taxRateAtSale: (j['taxRateAtSale'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusiveAtSale: j['isTaxInclusiveAtSale'] as bool? ?? true,
    );
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};
}

/// Riverpod provider for the API service.
final apiServiceProvider = Provider<ApiService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return ApiService(db);
});
