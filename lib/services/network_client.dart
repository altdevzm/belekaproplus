import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';

/// Network client that runs on Cashier terminals.
/// It connects to the Manager's API server over the local network.
class NetworkClient {
  final Dio _dio;
  final String serverUrl;
  Timer? _heartbeatTimer;
  Timer? _syncTimer;
  String? _terminalName;
  String? _cashierId;
  String? _cashierName;
  Map<String, dynamic>? _lastAssignmentInfo;

  Map<String, dynamic>? get lastAssignmentInfo => _lastAssignmentInfo;

  /// Clear the cached assignment and cashier info on logout.
  void clearAssignment() {
    _lastAssignmentInfo = null;
    _cashierId = null;
    _cashierName = null;
  }

  NetworkClient({required this.serverUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: serverUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
        ),
      );

  /// Whether the server is reachable.
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // ─── Connection ───────────────────────────────────────────────

  /// Ping the server to check connectivity and announce this terminal.
  Future<bool> testConnection([String? overrideHost, String? terminalCode]) async {
    try {
      final client = overrideHost != null
          ? Dio(
              BaseOptions(
                baseUrl: 'http://$overrideHost:8080',
                connectTimeout: const Duration(seconds: 3),
              ),
            )
          : _dio;

      final code = (terminalCode ?? _terminalName)?.trim().toUpperCase();
      final path = (code != null && code.isNotEmpty)
          ? '/status?terminalCode=$code'
          : '/status';

      final response = await client.get(path);
      _isConnected = response.statusCode == 200;

      // If connected and we know the terminal code, perform registration handshake
      if (_isConnected && code != null && code.isNotEmpty) {
        registerTerminal(
          terminalCode: code,
          name: 'Cashier Till ($code)',
        ).catchError((_) => null);
      }

      return _isConnected;
    } catch (e) {
      _isConnected = false;
      debugPrint('CONNECTION_TEST_FAILED: $e');
      return false;
    }
  }

  /// Retrieve server configuration and branch info from the Manager POS.
  Future<Map<String, dynamic>?> getServerInfo([String? overrideHost, String? terminalCode]) async {
    try {
      final client = overrideHost != null
          ? Dio(
              BaseOptions(
                baseUrl: 'http://$overrideHost:8080',
                connectTimeout: const Duration(seconds: 4),
              ),
            )
          : _dio;

      final code = (terminalCode ?? _terminalName)?.trim().toUpperCase();
      final path = (code != null && code.isNotEmpty)
          ? '/status?terminalCode=$code'
          : '/status';

      final response = await client.get(path);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is Map<String, dynamic>) {
          _isConnected = true;
          return data;
        }
      }
      return null;
    } catch (e) {
      _isConnected = false;
      debugPrint('GET_SERVER_INFO_ERROR: $e');
      return null;
    }
  }

  /// Start periodic heartbeat and sync timers.
  void startBackgroundTasks(String terminalName, {String? cashierId, String? cashierName}) {
    _terminalName = terminalName;
    if (cashierId != null) _cashierId = cashierId;
    if (cashierName != null) _cashierName = cashierName;

    // Send immediate heartbeat on startup
    _sendHeartbeat();

    // Heartbeat every 30 seconds
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat();
    });
  }

  /// Stop all background timers.
  void stopBackgroundTasks() {
    _heartbeatTimer?.cancel();
    _syncTimer?.cancel();
    _heartbeatTimer = null;
    _syncTimer = null;
  }

  Future<void> _sendHeartbeat() async {
    try {
      final response = await _dio.post(
        '/terminals/heartbeat',
        data: {
          'terminalName': _terminalName,
          'cashierId': _cashierId,
          'cashierName': _cashierName,
        },
      );
      _isConnected = true;
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is Map<String, dynamic>) {
          _lastAssignmentInfo = data;
        }
      }
    } catch (_) {
      _isConnected = false;
    }
  }

  /// Check this terminal's cashier assignment and shift status from Master POS.
  Future<Map<String, dynamic>?> checkTerminalAssignment(String terminalCode) async {
    try {
      final response = await _dio.post(
        '/terminals/heartbeat',
        data: {
          'terminalName': terminalCode.trim().toUpperCase(),
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is Map<String, dynamic>) {
          _lastAssignmentInfo = data;
          return data;
        }
      }
      return null;
    } catch (e) {
      debugPrint('CHECK_ASSIGNMENT_ERROR: $e');
      return null;
    }
  }

  /// Handshake & register this client till terminal with the Master POS Server.
  Future<Map<String, dynamic>?> registerTerminal({
    required String terminalCode,
    required String name,
    String? deviceIp,
    String? hardwareId,
    String? deviceModel,
    String? branchCode,
  }) async {
    try {
      final code = terminalCode.trim().toUpperCase();
      final response = await _dio.post(
        '/terminals/register',
        data: {
          'terminalCode': code,
          'terminalName': code,
          'name': name,
          'deviceIp': deviceIp,
          'hardwareId': hardwareId,
          'deviceModel': deviceModel,
          'branchCode': branchCode,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        _isConnected = true;
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is Map<String, dynamic>) {
          _lastAssignmentInfo = data;
          return data;
        }
        return {'success': true};
      }
      return null;
    } catch (e) {
      _isConnected = false;
      debugPrint('REGISTER_TERMINAL_ERROR: $e');
      return null;
    }
  }

  // ─── Authentication ───────────────────────────────────────────

  /// Authenticate a cashier against the Manager's user database.
  /// Returns the user data on success, null on failure.
  Future<Map<String, dynamic>?> login(
    String numericId,
    String password,
    String terminalName,
  ) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {
          'numericId': numericId,
          'password': password,
          'terminalName': terminalName,
        },
      );

      if (response.statusCode == 200) {
        final body = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (body['success'] == true) {
          _isConnected = true;
          return body['user'] as Map<String, dynamic>;
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return null; // Invalid credentials
      }
      _isConnected = false;
      rethrow; // Network error
    }
  }

  // ─── Products ─────────────────────────────────────────────────

  /// Fetch all products from the Manager's database.
  Future<List<Product>> fetchProducts() async {
    try {
      final response = await _dio.get('/products');
      final data = response.data is String
          ? jsonDecode(response.data as String) as List
          : response.data as List;

      _isConnected = true;
      return data
          .map((j) => _jsonToProduct(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _isConnected = false;
      debugPrint('FETCH_PRODUCTS_ERROR: $e');
      return [];
    }
  }

  /// Fetch all categories from the Manager's database.
  Future<List<Category>> fetchCategories() async {
    try {
      final response = await _dio.get('/categories');
      final data = response.data is String
          ? jsonDecode(response.data as String) as List
          : response.data as List;

      _isConnected = true;
      return data.map((j) {
        final map = j as Map<String, dynamic>;
        return Category(
          name: map['name'] as String,
          iconPath: map['iconPath'] as String? ?? '',
          sector: CategorySector.values[map['sector'] as int? ?? 5],
        )..id = map['id'] as int;
      }).toList();
    } catch (e) {
      _isConnected = false;
      debugPrint('FETCH_CATEGORIES_ERROR: $e');
      return [];
    }
  }

  // ─── Transactions ─────────────────────────────────────────────

  /// Push a single completed sale to the Manager's server.
  Future<Map<String, dynamic>?> pushTransaction(
    SaleTransaction transaction,
    List<SaleItem> items,
  ) async {
    try {
      final response = await _dio.post(
        '/transactions',
        data: {
          'transaction': _transactionToJson(transaction),
          'items': items.map(_saleItemToJson).toList(),
        },
      );

      _isConnected = true;
      final body = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      return body is Map<String, dynamic> ? body : {'success': true};
    } catch (e) {
      _isConnected = false;
      debugPrint('PUSH_TRANSACTION_ERROR: $e');
      return null;
    }
  }

  /// Push a batch of offline sales to the Manager's server.
  Future<Map<String, dynamic>?> pushBatchTransactions(
    List<Map<String, dynamic>> batch,
  ) async {
    try {
      final response = await _dio.post(
        '/transactions/batch',
        data: {'transactions': batch},
      );

      _isConnected = true;
      final body = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      return body is Map<String, dynamic> ? body : {'synced': 0};
    } catch (e) {
      _isConnected = false;
      debugPrint('BATCH_PUSH_ERROR: $e');
      return null;
    }
  }

  /// Fetch updated ZRA fiscal details for transactions from the Manager server.
  Future<List<Map<String, dynamic>>> fetchTransactionFiscalUpdates() async {
    try {
      final response = await _dio.get('/transactions/updates');
      _isConnected = true;
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      _isConnected = false;
      debugPrint('FETCH_FISCAL_UPDATES_ERROR: $e');
      return [];
    }
  }

  // ─── Terminal Info ────────────────────────────────────────────

  /// Fetch list of active terminals (Manager use).
  Future<List<Map<String, dynamic>>> fetchActiveTerminals() async {
    try {
      final response = await _dio.get('/terminals');
      final data = response.data is String
          ? jsonDecode(response.data as String) as List
          : response.data as List;

      _isConnected = true;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      _isConnected = false;
      return [];
    }
  }

  // ─── User Management ─────────────────────────────────────────

  /// Get all users (Manager use).
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    try {
      final response = await _dio.get('/users');
      final data = response.data is String
          ? jsonDecode(response.data as String) as List
          : response.data as List;
      _isConnected = true;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      _isConnected = false;
      return [];
    }
  }

  /// Create a new user (Manager use).
  Future<bool> createUser({
    required String numericId,
    required String name,
    required String password,
    String role = 'cashier',
  }) async {
    try {
      final response = await _dio.post(
        '/users',
        data: {
          'numericId': numericId,
          'name': name,
          'password': password,
          'role': role,
        },
      );
      final body = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      return body['success'] == true;
    } catch (e) {
      debugPrint('CREATE_USER_ERROR: $e');
      return false;
    }
  }

  /// Query the Manager POS over LAN to verify a 10-digit TPIN using the Manager's
  /// local DB and DigiTax credentials.
  Future<Map<String, dynamic>?> lookupTaxpayerTpin(String tpin) async {
    try {
      final response = await _dio.get(
        '/taxpayers/${tpin.trim()}',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sync a verified or manually entered customer TPIN + business name to the Manager POS.
  Future<void> saveTaxpayerTpin({
    required String tpin,
    required String name,
    String? address,
  }) async {
    try {
      await _dio.post(
        '/taxpayers',
        data: {
          'tpin': tpin.trim(),
          'taxpayer_name': name.trim(),
          if (address != null && address.trim().isNotEmpty)
            'physical_address': address.trim(),
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
    } catch (_) {}
  }

  // ─── JSON Helpers ─────────────────────────────────────────────

  static Product _jsonToProduct(Map<String, dynamic> j) {
    String? img = j['imageBase64'] as String?;
    if (img == null || img.trim().isEmpty) {
      img = j['imagePath'] as String?;
    }

    return Product(
      name: j['name'] as String,
      sku: j['sku'] as String,
      price: (j['price'] as num).toDouble(),
      stockLevel: j['stockLevel'] as int,
      categoryId: j['categoryId'] as int,
      unitCost: (j['unitCost'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusive: j['isTaxInclusive'] as bool? ?? true,
      isDigitaxSyncEnabled:
          j['isDigitaxSyncEnabled'] as bool? ??
          j['is_digitax_sync_enabled'] as bool? ??
          true,
      isSyncedWithDigitax: j['isSyncedWithDigitax'] as bool? ?? false,
      taxRate: (j['taxRate'] as num?)?.toDouble() ?? 16.0,
      zraTaxCode: j['zraTaxCode'] as String? ?? 'A',
      itemClsCd: j['itemClsCd'] as String? ?? '10101501',
      branchCode: j['branchCode'] as String? ?? '00',
      branchName: j['branchName'] as String?,
      unitOfMeasure: j['unitOfMeasure'] as String? ?? 'kg',
      isWeighted: j['isWeighted'] as bool? ?? false,
      tareWeight: (j['tareWeight'] as num?)?.toDouble() ?? 0.0,
      isArchived: j['isArchived'] as bool? ?? false,
      imagePath: img,
      colors: (j['colors'] as List?)?.map((e) => e.toString()).toList(),
    )..id = j['id'] as int;
  }

  static Map<String, dynamic> _transactionToJson(SaleTransaction tx) => {
    'totalAmount': tx.totalAmount,
    'paymentMethod': tx.paymentMethod,
    'cashierName': tx.cashierName,
    'status': tx.status,
    'subtotal': tx.subtotal,
    'taxAmount': tx.taxAmount,
    'discountAmount': tx.discountAmount,
    'totalCost': tx.totalCost,
    'grossProfit': tx.grossProfit,
    'tenderedAmount': tx.tenderedAmount,
    'changeAmount': tx.changeAmount,
    'cashierId': tx.cashierId,
    'terminalName': tx.terminalName,
    'cashShiftNumber': tx.cashShiftNumber,
    'externalPaymentReference': tx.externalPaymentReference,
    'externalPaymentConfirmedBy': tx.externalPaymentConfirmedBy,
    'externalPaymentConfirmedAt': tx.externalPaymentConfirmedAt
        ?.toIso8601String(),
    'transactionId': tx.transactionId,
    'customerTpin': tx.customerTpin,
    'customerBusinessName': tx.customerBusinessName,
    'customerAddress': tx.customerAddress,
    'zraSdcId': tx.zraSdcId,
    'zraReceiptNumber': tx.zraReceiptNumber,
    'zraMarkId': tx.zraMarkId,
    'zraInternalData': tx.zraInternalData,
    'zraQrCode': tx.zraQrCode,
    'zraInvoiceType': tx.zraInvoiceType,
    'zraStatus': tx.zraStatus,
    'orgInvoiceNo': tx.orgInvoiceNo,
    'isCreditNote': tx.isCreditNote,
    'creditNoteReason': tx.creditNoteReason,
    'timestamp': tx.timestamp.toIso8601String(),
  };

  static Map<String, dynamic> _saleItemToJson(SaleItem item) => {
    'productId': item.productId,
    'productName': item.productName,
    'priceAtSale': item.priceAtSale,
    'unitCostAtSale': item.unitCostAtSale,
    'quantity': item.quantity,
    'isRefunded': item.isRefunded,
    'isDigitaxExempt': item.isDigitaxExempt,
    'taxRateAtSale': item.taxRateAtSale,
    'isTaxInclusiveAtSale': item.isTaxInclusiveAtSale,
  };

  void dispose() {
    stopBackgroundTasks();
    _dio.close();
  }
}

/// Provider for the network client.
/// Reads the server IP from StoreConfig.
final networkClientProvider = Provider<NetworkClient?>((ref) {
  final configAsync = ref.watch(storeConfigProvider);

  return configAsync.when(
    data: (config) {
      if (config == null) return null;
      if (config.isManagerMode) return null;

      final ip = config.serverIp;
      if (ip == null || ip.isEmpty) return null;

      return NetworkClient(serverUrl: 'http://$ip:${config.port}');
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final networkOnlineProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(networkClientProvider);
  if (client == null) return Stream.value(false);

  return Stream.periodic(const Duration(seconds: 10)).asyncMap((_) async {
    return await client.testConnection();
  }).distinct();
});
