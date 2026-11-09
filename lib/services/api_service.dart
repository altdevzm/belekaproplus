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
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
// isar imported above at line 6


/// Tracks connected terminals on the Manager's server.
class TerminalInfo {
  final String terminalName;
  String cashierId;
  String cashierName;
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
  final Ref? ref;
  HttpServer? _server;
  final Map<String, TerminalInfo> _activeTerminals = {};
  final _terminalUpdateController = StreamController<List<TerminalInfo>>.broadcast();

  ApiService(this._db, {this.ref});

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

    // Detect the device's LAN IP (supports Wi-Fi, Ethernet, and multi-adapter)
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            _hostIp = addr.address;
            break;
          }
        }
        if (_hostIp != null && _hostIp != '0.0.0.0' && _hostIp != '127.0.0.1') break;
      }
    } catch (_) {
      try {
        final info = NetworkInfo();
        _hostIp = await info.getWifiIP();
      } catch (_) {}
    }
    _hostIp ??= '127.0.0.1';

    _server = await shelf_io.serve(handler, '0.0.0.0', _port);
    debugPrint('SERVER_STARTED: Beleka POS API running on $_hostIp:$_port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _activeTerminals.clear();
    debugPrint('SERVER_STOPPED');
  }

  void removeTerminal(String terminalCode) {
    final code = terminalCode.trim().toUpperCase();
    _activeTerminals.remove(code);
    _notifyTerminals();
  }

  void resetTerminalShiftSales(String terminalCode) {
    final code = terminalCode.trim().toUpperCase();
    if (_activeTerminals.containsKey(code)) {
      _activeTerminals[code]!.salesToday = 0.0;
      _activeTerminals[code]!.transactionCount = 0;
      _notifyTerminals();
    }
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
    router.get('/transactions/updates', _handleGetTransactionUpdates);
    router.get('/terminals', _handleGetTerminals);
    router.post('/terminals/register', _handleRegisterTerminal);
    router.post('/terminals/handshake', _handleRegisterTerminal);
    router.post('/terminals/heartbeat', _handleHeartbeat);

    // User management (Manager only)
    router.get('/users', _handleGetUsers);
    router.post('/users', _handleCreateUser);
    router.delete('/users/<id>', _handleDeleteUser);
  }

  // ─── Handlers ─────────────────────────────────────────────────

  Future<Response> _handleStatus(Request request) async {
    final config = await _db.getStoreConfig();
    
    // Auto-discover and register till if terminal code/name was supplied in query or header
    final paramCode = request.url.queryParameters['terminalCode'] ??
        request.url.queryParameters['terminalName'] ??
        request.headers['x-terminal-code'];
    if (paramCode != null && paramCode.trim().isNotEmpty) {
      final code = paramCode.trim().toUpperCase();
      try {
        final existingTerminals = await _db.isar.posTerminals.where().findAll();
        final exists = existingTerminals.any((t) => t.terminalCode == code);
        if (exists || existingTerminals.length < 3) {
          PosTerminal terminal = existingTerminals.firstWhere(
            (t) => t.terminalCode == code,
            orElse: () => PosTerminal()
              ..terminalCode = code
              ..name = 'Cashier Till ($code)'
              ..branchCode = (config?.bhfId != null && config!.bhfId.isNotEmpty) ? config.bhfId : '00'
              ..branchName = config?.branchName ?? 'Main Branch',
          );
          terminal.status = 'ACTIVE';
          terminal.lastActive = DateTime.now();
          await _db.isar.writeTxn(() async {
            await _db.isar.posTerminals.putByTerminalCode(terminal);
          });
          _activeTerminals[code] = TerminalInfo(
            terminalName: code,
            cashierId: terminal.assignedCashierId ?? '',
            cashierName: terminal.assignedCashierName ?? 'Unassigned Cashier',
            connectedAt: DateTime.now(),
          );
          _notifyTerminals();
          ref?.invalidate(posTerminalsProvider);
        }
      } catch (e) {
        debugPrint('STATUS_AUTO_REGISTER_NOTICE: $e');
      }
    }

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
        'digitaxApiKey': config?.digitaxApiKey ?? '',
        'digitaxEnvironment': config?.digitaxEnvironment ?? 'sandbox',
        'sdcId': config?.sdcId ?? '',
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

        // Enforce till assignment: if the till is unassigned or assigned to someone else,
        // prevent cashiers from logging in.
        PosTerminal? existingTerm;
        try {
          existingTerm = existingTerminals.firstWhere(
            (t) => t.terminalCode == terminalName || t.name == terminalName,
          );
        } catch (_) {}

        if (user.role == 'cashier') {
          if (existingTerm == null ||
              existingTerm.assignedCashierId == null ||
              existingTerm.assignedCashierId!.isEmpty) {
            return Response(403,
                body: jsonEncode({
                  'error': 'Till "$terminalName" is not currently assigned to any cashier. Please ask your Store Manager on the Master POS to assign this till and open your shift before logging in.'
                }),
                headers: _jsonHeaders);
          }

          if (existingTerm.assignedCashierId != user.numericId) {
            return Response(403,
                body: jsonEncode({
                  'error': 'Till "$terminalName" is assigned to ${existingTerm.assignedCashierName ?? existingTerm.assignedCashierId}. You cannot sell on this till. Please ask the Manager to reassign.'
                }),
                headers: _jsonHeaders);
          }

          // Check if active open shift exists
          final openShift = await _db.isar.cashShifts
              .filter()
              .statusEqualTo('OPEN')
              .and()
              .group((q) => q
                  .terminalIdEqualTo(terminalName)
                  .or()
                  .terminalIdEqualTo('${existingTerm!.terminalCode} - ${existingTerm.name}')
                  .or()
                  .terminalIdContains(existingTerm.terminalCode))
              .findFirst();

          if (openShift == null) {
            return Response(403,
                body: jsonEncode({
                  'error': 'No open shift found for Till "$terminalName". Please ask your Store Manager on the Master POS to open your shift before logging in.'
                }),
                headers: _jsonHeaders);
          }

          // Check if shift schedule has expired
          if (openShift.notes != null && openShift.notes!.contains('SCHEDULE:')) {
            try {
              final schedPart = openShift.notes!.split('SCHEDULE:').last.split(';').first;
              final times = schedPart.split('|');
              if (times.length >= 2) {
                final endTime = DateTime.parse(times[1].trim());
                if (DateTime.now().isAfter(endTime)) {
                  return Response(403,
                      body: jsonEncode({
                        'error': 'Shift for Till "$terminalName" ended at ${times[1].trim().substring(11, 16)}. Please ask your Store Manager to close or extend your shift.'
                      }),
                      headers: _jsonHeaders);
                }
              }
            } catch (_) {}
          }
        }

        _activeTerminals[terminalName] = TerminalInfo(
          terminalName: terminalName,
          cashierId: user.numericId,
          cashierName: user.name,
          connectedAt: DateTime.now(),
        );

        // Persist terminal to Isar so the admin dashboard watchLazy() stream
        // fires and the connected till appears on the terminals screen.
        try {
          PosTerminal terminal = existingTerm ?? (PosTerminal()
            ..terminalCode = terminalName
            ..name = terminalName);
          terminal.status = 'ACTIVE';
          terminal.lastActive = DateTime.now();
          await _db.isar.writeTxn(() async {
            await _db.isar.posTerminals.putByTerminalCode(terminal);
          });
          ref?.invalidate(posTerminalsProvider);
        } catch (e) {
          debugPrint('LOGIN_TERMINAL_PERSIST_NOTICE: $e');
        }

        _notifyTerminals();
      }

      final config = await _db.getStoreConfig();

      return Response.ok(
        jsonEncode({
          'success': true,
          'user': {
            'id': user.id,
            'numericId': user.numericId,
            'name': user.name,
            'role': user.role,
          },
          'store': {
            'businessName': config?.businessName ?? 'Beleka POS',
            'branchName': config?.branchName ?? 'Main Branch',
            'bhfId': (config?.bhfId != null && config!.bhfId.isNotEmpty) ? config.bhfId : '00',
            'tpin': config?.tpin ?? '',
            'businessTaxType': config?.businessTaxType ?? 'TURNOVER_TAX',
            'digitaxApiKey': config?.digitaxApiKey ?? '',
            'digitaxEnvironment': config?.digitaxEnvironment ?? 'sandbox',
            'sdcId': config?.sdcId ?? '',
          }
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
            jsonEncode({
              'success': true,
              'transactionId': existing.id,
              'duplicate': true,
              'zraReceiptNumber': existing.zraReceiptNumber,
              'zraMarkId': existing.zraMarkId,
              'zraQrCode': existing.zraQrCode,
              'zraInternalData': existing.zraInternalData,
              'zraSdcId': existing.zraSdcId,
              'zraInvoiceType': existing.zraInvoiceType,
              'zraStatus': existing.zraStatus,
            }),
            headers: _jsonHeaders,
          );
        }
      }

      // Link transaction to current open shift for this terminal if not already assigned
      if (transaction.cashShiftNumber == null || transaction.cashShiftNumber!.isEmpty) {
        final openShift = await _db.getOpenShiftForTerminal(transaction.terminalName ?? 'TILL-01');
        if (openShift != null) {
          transaction.cashShiftNumber = openShift.shiftNumber;
        }
      }

      await _db.saveTransaction(transaction, items);

      // Instantly fiscalize with DigiTax on Manager server if API Key present & not yet fiscalized
      if (ref != null && (transaction.zraReceiptNumber == null || transaction.zraReceiptNumber!.isEmpty)) {
        try {
          final digitaxService = ref!.read(digitaxInventoryServiceProvider);
          await digitaxService.fiscalizeSaleTransaction(transaction, items);
        } catch (e) {
          debugPrint('LAN_SERVER_FISCALIZE_NOTICE: $e');
        }
      }

      // Update terminal stats if known
      if (transaction.terminalName != null && _activeTerminals.containsKey(transaction.terminalName)) {
        final info = _activeTerminals[transaction.terminalName]!;
        info.salesToday += transaction.totalAmount;
        info.transactionCount += 1;
        info.lastHeartbeat = DateTime.now();
        _notifyTerminals();
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'transactionId': transaction.id,
          'zraReceiptNumber': transaction.zraReceiptNumber,
          'zraMarkId': transaction.zraMarkId,
          'zraQrCode': transaction.zraQrCode,
          'zraInternalData': transaction.zraInternalData,
          'zraSdcId': transaction.zraSdcId,
          'zraInvoiceType': transaction.zraInvoiceType,
          'zraStatus': transaction.zraStatus,
        }),
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
      final List<Map<String, dynamic>> syncedItems = [];

      for (final entry in batch) {
        try {
          final txData = entry['transaction'] as Map<String, dynamic>;
          final itemsData = entry['items'] as List<dynamic>;

          final transaction = _jsonToTransaction(txData);
          final items = itemsData
              .map((i) => _jsonToSaleItem(i as Map<String, dynamic>))
              .toList();

          // Link transaction to current open shift for this terminal if not already assigned
      if (transaction.cashShiftNumber == null || transaction.cashShiftNumber!.isEmpty) {
        final openShift = await _db.getOpenShiftForTerminal(transaction.terminalName ?? 'TILL-01');
        if (openShift != null) {
          transaction.cashShiftNumber = openShift.shiftNumber;
        }
      }

      await _db.saveTransaction(transaction, items);

          // Instantly fiscalize with DigiTax on Manager server if needed
          if (ref != null && (transaction.zraReceiptNumber == null || transaction.zraReceiptNumber!.isEmpty)) {
            try {
              final digitaxService = ref!.read(digitaxInventoryServiceProvider);
              await digitaxService.fiscalizeSaleTransaction(transaction, items);
            } catch (e) {
              debugPrint('LAN_SERVER_BATCH_FISCALIZE_NOTICE: $e');
            }
          }

          successCount++;

          syncedItems.add({
            'transactionId': transaction.transactionId ?? 'INV-${transaction.id}',
            'zraReceiptNumber': transaction.zraReceiptNumber,
            'zraMarkId': transaction.zraMarkId,
            'zraQrCode': transaction.zraQrCode,
            'zraInternalData': transaction.zraInternalData,
            'zraSdcId': transaction.zraSdcId,
            'zraInvoiceType': transaction.zraInvoiceType,
            'zraStatus': transaction.zraStatus,
          });

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
          'fiscalUpdates': syncedItems,
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetTransactionUpdates(Request request) async {
    try {
      final approvedTx = await _db.isar.saleTransactions
          .filter()
          .zraReceiptNumberIsNotNull()
          .findAll();

      final jsonList = approvedTx.map((tx) => {
        'transactionId': tx.transactionId,
        'zraReceiptNumber': tx.zraReceiptNumber,
        'zraMarkId': tx.zraMarkId,
        'zraQrCode': tx.zraQrCode,
        'zraInternalData': tx.zraInternalData,
        'zraSdcId': tx.zraSdcId,
        'zraInvoiceType': tx.zraInvoiceType,
        'zraStatus': tx.zraStatus,
      }).toList();

      return Response.ok(jsonEncode(jsonList), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetTerminals(Request request) async {
    try {
      final terminals = await _db.isar.posTerminals.where().findAll();
      final openShifts = await _db.isar.cashShifts
          .filter()
          .statusEqualTo('OPEN')
          .findAll();

      final jsonList = terminals.map((t) {
        final shift = openShifts
            .where((s) =>
                s.terminalId == '${t.terminalCode} - ${t.name}' ||
                s.terminalId == t.terminalCode ||
                s.terminalId == t.name)
            .firstOrNull;
        String? tSchedStart;
        String? tSchedEnd;
        if (shift?.notes != null && shift!.notes!.contains('SCHEDULE:')) {
          try {
            final part = shift.notes!.split('SCHEDULE:').last.split(';').first;
            final times = part.split('|');
            if (times.isNotEmpty) tSchedStart = times[0].trim();
            if (times.length > 1) tSchedEnd = times[1].trim();
          } catch (_) {}
        }
        tSchedStart ??= shift?.openingTime.toIso8601String();

        return {
          'id': t.id,
          'terminalCode': t.terminalCode,
          'name': t.name,
          'deviceIp': t.deviceIp,
          'serialNumber': t.serialNumber,
          'status': t.status,
          'branchCode': t.branchCode,
          'assignedCashierId': t.assignedCashierId,
          'assignedCashierName': t.assignedCashierName,
          'isShiftOpen': shift != null,
          'shiftNumber': shift?.shiftNumber,
          'openingCash': shift?.openingCash ?? 0.0,
          'shiftStartTime': tSchedStart,
          'shiftEndTime': tSchedEnd,
          'salesToday': t.salesToday,
          'lastActive': t.lastActive.toIso8601String(),
        };
      }).toList();
      return Response.ok(jsonEncode(jsonList), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleRegisterTerminal(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final terminalCode = (body['terminalCode'] as String?)?.trim().toUpperCase() ?? 'TILL-01';
      final name = (body['name'] as String?)?.trim() ?? 'Cashier Till ($terminalCode)';
      final deviceIp = body['deviceIp'] as String?;
      final hardwareId = body['hardwareId'] as String?;
      final branchCode = body['branchCode'] as String?;

      if (terminalCode.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'terminalCode required'}), headers: _jsonHeaders);
      }

      final existingTerminals = await _db.isar.posTerminals.where().findAll();
      final exists = existingTerminals.any((t) => t.terminalCode == terminalCode);

      if (!exists && existingTerminals.length >= 3) {
        return Response(403,
            body: jsonEncode({
              'error': 'Maximum till limit reached (Max 3 tills allowed on this license). Upgrade your license to connect additional tills.'
            }),
            headers: _jsonHeaders);
      }

      PosTerminal terminal = existingTerminals.firstWhere(
        (t) => t.terminalCode == terminalCode,
        orElse: () => PosTerminal()
          ..terminalCode = terminalCode
          ..name = name,
      );

      terminal.name = name;
      if (deviceIp != null && deviceIp.isNotEmpty) terminal.deviceIp = deviceIp;
      if (hardwareId != null && hardwareId.isNotEmpty) terminal.serialNumber = hardwareId;
      if (branchCode != null && branchCode.isNotEmpty) terminal.branchCode = branchCode;
      terminal.status = 'ACTIVE';
      terminal.lastActive = DateTime.now();

      await _db.isar.writeTxn(() async {
        await _db.isar.posTerminals.putByTerminalCode(terminal);
      });

      _activeTerminals[terminalCode] = TerminalInfo(
        terminalName: terminalCode,
        cashierId: terminal.assignedCashierId ?? '',
        cashierName: terminal.assignedCashierName ?? 'Unassigned Cashier',
        connectedAt: DateTime.now(),
      );
      _notifyTerminals();
      ref?.invalidate(posTerminalsProvider);

      final openShift = await _db.isar.cashShifts
          .filter()
          .terminalIdContains(terminalCode)
          .and()
          .statusEqualTo('OPEN')
          .findFirst();

      final config = await _db.getStoreConfig();

      String? regSchedStart;
      String? regSchedEnd;
      if (openShift?.notes != null && openShift!.notes!.contains('SCHEDULE:')) {
        try {
          final part = openShift.notes!.split('SCHEDULE:').last.split(';').first;
          final times = part.split('|');
          if (times.isNotEmpty) regSchedStart = times[0].trim();
          if (times.length > 1) regSchedEnd = times[1].trim();
        } catch (_) {}
      }
      regSchedStart ??= openShift?.openingTime.toIso8601String();

      return Response.ok(
        jsonEncode({
          'success': true,
          'terminalId': terminal.id,
          'terminalCode': terminal.terminalCode,
          'assignedCashierId': terminal.assignedCashierId,
          'assignedCashierName': terminal.assignedCashierName,
          'isShiftOpen': openShift != null,
          'shiftNumber': openShift?.shiftNumber,
          'openingCash': openShift?.openingCash ?? 0.0,
          'shiftStartTime': regSchedStart,
          'shiftEndTime': regSchedEnd,
          'storeConfig': {
            'businessName': config?.businessName ?? 'Beleka POS',
            'branchName': config?.branchName ?? 'Main Branch',
            'bhfId': (config?.bhfId != null && config!.bhfId.isNotEmpty) ? config.bhfId : '00',
            'tpin': config?.tpin ?? '',
            'businessTaxType': config?.businessTaxType ?? 'TURNOVER_TAX',
            'digitaxApiKey': config?.digitaxApiKey ?? '',
            'digitaxEnvironment': config?.digitaxEnvironment ?? 'sandbox',
            'sdcId': config?.sdcId ?? '',
          }
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleHeartbeat(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final terminalName = (body['terminalName'] as String?)?.trim().toUpperCase();
      final cashierId = body['cashierId'] as String?;
      final cashierName = body['cashierName'] as String?;

      if (terminalName != null && terminalName.isNotEmpty) {
        if (_activeTerminals.containsKey(terminalName)) {
          final info = _activeTerminals[terminalName]!;
          info.lastHeartbeat = DateTime.now();
          if (cashierId != null && cashierId.isNotEmpty) {
            info.cashierId = cashierId;
          }
          if (cashierName != null && cashierName.isNotEmpty) {
            info.cashierName = cashierName;
          }
        } else {
          final existingTerminals = await _db.isar.posTerminals.where().findAll();
          final isKnown = existingTerminals.any((t) => t.terminalCode == terminalName);
          if (isKnown || existingTerminals.length < 3) {
            _activeTerminals[terminalName] = TerminalInfo(
              terminalName: terminalName,
              cashierId: cashierId ?? '',
              cashierName: cashierName ?? 'Cashier',
              connectedAt: DateTime.now(),
            );
          }
        }

        // Keep lastActive up to date in Isar, and auto re-create if missing or deleted
        final term = await _db.isar.posTerminals
            .filter()
            .terminalCodeEqualTo(terminalName)
            .findFirst();

        final config = await _db.getStoreConfig();
        PosTerminal termToSave = term ?? (PosTerminal()
          ..terminalCode = terminalName
          ..name = 'Cashier Till ($terminalName)'
          ..branchCode = (config?.bhfId != null && config!.bhfId.isNotEmpty) ? config.bhfId : '00'
          ..branchName = config?.branchName ?? 'Main Branch');

        termToSave.lastActive = DateTime.now();
        termToSave.status = 'ACTIVE';

        await _db.isar.writeTxn(() async {
          await _db.isar.posTerminals.putByTerminalCode(termToSave);
        });

        _notifyTerminals();
        ref?.invalidate(posTerminalsProvider);

        final openShift = await _db.isar.cashShifts
            .filter()
            .statusEqualTo('OPEN')
            .and()
            .group((q) => q
                .terminalIdEqualTo(terminalName)
                .or()
                .terminalIdEqualTo('${termToSave.terminalCode} - ${termToSave.name}')
                .or()
                .terminalIdContains(terminalName))
            .findFirst();

        String? schedStart;
        String? schedEnd;
        if (openShift?.notes != null && openShift!.notes!.contains('SCHEDULE:')) {
          try {
            final part = openShift.notes!.split('SCHEDULE:').last.split(';').first;
            final times = part.split('|');
            if (times.isNotEmpty) schedStart = times[0].trim();
            if (times.length > 1) schedEnd = times[1].trim();
          } catch (_) {}
        }
        schedStart ??= openShift?.openingTime.toIso8601String();

        return Response.ok(
          jsonEncode({
            'status': 'ok',
            'assignedCashierId': termToSave.assignedCashierId,
            'assignedCashierName': termToSave.assignedCashierName,
            'isShiftOpen': openShift != null,
            'shiftNumber': openShift?.shiftNumber,
            'openingCash': openShift?.openingCash ?? 0.0,
            'shiftStartTime': schedStart,
            'shiftEndTime': schedEnd,
          }),
          headers: _jsonHeaders,
        );
      }

      return Response.ok(jsonEncode({'status': 'ok'}), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  // ─── User Management ─────────────────────────────────────────

  Future<Response> _handleGetUsers(Request request) async {
    try {
      final users = await _db.isar.users.where().findAll();
      final jsonList = users
          .map((u) => {
                'id': u.id,
                'numericId': u.numericId,
                'name': u.name,
                'role': u.role,
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
      final numericId = body['numericId'] as String?;
      final name = body['name'] as String?;
      final password = body['password'] as String?;
      final role = body['role'] as String? ?? 'cashier';

      if (numericId == null || name == null || password == null) {
        return Response(400,
            body: jsonEncode({'error': 'numericId, name, password required'}),
            headers: _jsonHeaders);
      }

      final existing = await _db.isar.users
          .filter()
          .numericIdEqualTo(numericId)
          .findFirst();

      if (existing != null) {
        return Response(400,
            body: jsonEncode({'error': 'User with this ID already exists'}),
            headers: _jsonHeaders);
      }

      final user = User()
        ..numericId = numericId
        ..name = name
        ..passwordHash = hashPin(password)
        ..role = role
        ..isActive = true;

      await _db.isar.writeTxn(() async {
        await _db.isar.users.put(user);
      });

      return Response.ok(
          jsonEncode({'success': true, 'userId': user.id}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleDeleteUser(Request request) async {
    try {
      final idStr = request.params['id'];
      if (idStr == null) {
        return Response(400,
            body: jsonEncode({'error': 'User ID required'}),
            headers: _jsonHeaders);
      }
      final id = int.tryParse(idStr);
      if (id == null) {
        return Response(400,
            body: jsonEncode({'error': 'Invalid User ID'}),
            headers: _jsonHeaders);
      }

      await _db.isar.writeTxn(() async {
        await _db.isar.users.delete(id);
      });

      return Response.ok(jsonEncode({'success': true}), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  // ─── JSON Helpers ─────────────────────────────────────────────

  static Map<String, dynamic> _productToJson(Product p) {
    String? imageBase64;
    if (p.imagePath != null && p.imagePath!.trim().isNotEmpty) {
      if (p.imagePath!.startsWith('data:image')) {
        imageBase64 = p.imagePath;
      } else {
        final file = File(p.imagePath!);
        if (file.existsSync()) {
          try {
            final bytes = file.readAsBytesSync();
            if (bytes.length <= 1024 * 1024) {
              final ext = p.imagePath!.split('.').last.toLowerCase();
              final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
              imageBase64 = 'data:$mime;base64,${base64Encode(bytes)}';
            }
          } catch (e) {
            debugPrint('Image base64 encoding error: $e');
          }
        }
      }
    }

    return {
      'id': p.id,
      'name': p.name,
      'sku': p.sku,
      'price': p.price,
      'unitCost': p.unitCost,
      'stockLevel': p.stockLevel,
      'categoryId': p.categoryId,
      'isTaxInclusive': p.isTaxInclusive,
      'taxRate': p.taxRate,
      'isArchived': p.isArchived,
      'imagePath': p.imagePath,
      'imageBase64': imageBase64,
    };
  }

  static SaleTransaction _jsonToTransaction(Map<String, dynamic> j) {
    final tx = SaleTransaction(
      totalAmount: (j['totalAmount'] as num).toDouble(),
      paymentMethod: j['paymentMethod'] as String? ?? 'CASH',
      cashierName: j['cashierName'] as String? ?? 'Cashier',
      status: j['status'] as String? ?? 'completed',
      subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (j['taxAmount'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (j['discountAmount'] as num?)?.toDouble() ?? 0.0,
      totalCost: (j['totalCost'] as num?)?.toDouble() ?? 0.0,
      grossProfit: (j['grossProfit'] as num?)?.toDouble() ?? 0.0,
      tenderedAmount: (j['tenderedAmount'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (j['changeAmount'] as num?)?.toDouble() ?? 0.0,
      cashierId: j['cashierId'] as String?,
      terminalName: j['terminalName'] as String?,
      transactionId: j['transactionId'] as String?,
      customerTpin: j['customerTpin'] as String?,
      customerBusinessName: j['customerBusinessName'] as String?,
      customerAddress: j['customerAddress'] as String?,
      zraSdcId: j['zraSdcId'] as String?,
      zraReceiptNumber: j['zraReceiptNumber'] as String?,
      zraMarkId: j['zraMarkId'] as String?,
      zraInternalData: j['zraInternalData'] as String?,
      zraQrCode: j['zraQrCode'] as String?,
      zraInvoiceType: j['zraInvoiceType'] as String?,
      zraStatus: j['zraStatus'] as String? ?? 'pending',
      orgInvoiceNo: j['orgInvoiceNo'] as String?,
      isCreditNote: j['isCreditNote'] as bool? ?? false,
      creditNoteReason: j['creditNoteReason'] as String?,
    );
    tx.cashShiftNumber = j['cashShiftNumber'] as String?;
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
      isDigitaxExempt: j['isDigitaxExempt'] as bool? ?? false,
      taxRateAtSale: (j['taxRateAtSale'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusiveAtSale: j['isTaxInclusiveAtSale'] as bool? ?? true,
    );
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};
}

/// Riverpod provider for the API service.
final apiServiceProvider = Provider<ApiService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return ApiService(db, ref: ref);
});
