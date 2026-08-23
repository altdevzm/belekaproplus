import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:beleka_pos/models/models.dart';

class CloudDatabaseService {
  final Dio _dio;

  CloudDatabaseService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {'Content-Type': 'application/json'},
              ),
            );

  /// Test connectivity to the online PostgreSQL Cloud API backend.
  Future<bool> checkConnection(String baseUrl) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final response = await _dio.get('$sanitizedUrl/health');
      return response.statusCode == 200 && response.data['status'] == 'healthy';
    } catch (e) {
      debugPrint('Cloud PostgreSQL DB Connection Check Failed: $e');
      return false;
    }
  }

  /// Authenticate any user (Manager, Cashier, Owner) against Cloud PostgreSQL DB.
  Future<Map<String, dynamic>?> authenticateUser({
    required String baseUrl,
    required String numericId,
    required String pin,
    String? terminalName,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/auth/login',
        data: {
          'numeric_id': numericId.trim(),
          'pin': pin.trim(),
          'terminal_name': terminalName ?? 'POS-TERMINAL',
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('Cloud PostgreSQL Auth Failed: $e');
      return null;
    }
  }

  /// Push/Sync a user or Branch Manager to Cloud PostgreSQL DB.
  Future<bool> syncUser({
    required String baseUrl,
    required int storeId,
    required User user,
    String? plainPin,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/users',
        data: {
          'store_id': storeId,
          'numeric_id': user.numericId,
          'name': user.name,
          'role': user.role,
          'branch_name': user.branchName,
          'phone': user.phone,
          'password_hash': user.passwordHash,
          'is_active': user.isActive,
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Cloud PostgreSQL User Push Failed: $e');
      return false;
    }
  }

  /// Push/Sync a Store Branch to Cloud PostgreSQL DB.
  Future<bool> syncBranch({
    required String baseUrl,
    required StoreBranch branch,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/stores',
        data: {
          'store_code': branch.code,
          'bhf_id': branch.bhfId,
          'name': branch.name,
          'address': branch.address,
          'contact_number': branch.phone,
          'email': branch.email,
          'branch_name': branch.name,
          'manager_name': branch.managerName,
          'manager_id': branch.managerId,
          'manager_phone': branch.managerPhone,
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Cloud PostgreSQL Branch Push Failed: $e');
      return false;
    }
  }

  /// Fetch list of available store branches from Cloud PostgreSQL DB.
  Future<List<Map<String, dynamic>>> getStores(String baseUrl) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final response = await _dio.get('$sanitizedUrl/api/v1/stores');
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching store branches from cloud DB: $e');
      rethrow;
    }
  }

  /// Fetch list of users from Cloud PostgreSQL DB.
  Future<List<Map<String, dynamic>>> getUsers(String baseUrl, {int? storeId}) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final queryParams = storeId != null ? {'store_id': storeId} : null;
      final response = await _dio.get(
        '$sanitizedUrl/api/v1/users',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching users from cloud DB: $e');
      return [];
    }
  }

  /// Sync local offline transactions up to the Cloud PostgreSQL DB.
  Future<List<String>> syncBatchSales({
    required String baseUrl,
    required int storeId,
    required List<SaleTransaction> transactions,
  }) async {
    if (transactions.isEmpty) return [];

    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      
      final salesData = transactions.map((tx) {
        return {
          'transaction_uuid': tx.transactionId ?? 'tx-${DateTime.now().millisecondsSinceEpoch}',
          'store_id': storeId,
          'total_amount': tx.totalAmount,
          'subtotal': tx.subtotal,
          'tax_amount': tx.taxAmount,
          'discount_amount': tx.discountAmount,
          'total_cost': tx.totalCost,
          'gross_profit': tx.grossProfit,
          'tendered_amount': tx.tenderedAmount,
          'change_amount': tx.changeAmount,
          'payment_method': tx.paymentMethod,
          'cashier_id': tx.cashierId,
          'cashier_name': tx.cashierName,
          'terminal_name': tx.terminalName,
          'customer_id': tx.customerId,
          'points_earned': tx.pointsEarned,
          'points_redeemed': tx.pointsRedeemed,
          'items': tx.items.map((item) {
            return {
              'product_id': item.productId,
              'product_name': item.productName,
              'price_at_sale': item.priceAtSale,
              'unit_cost_at_sale': item.unitCostAtSale,
              'quantity': item.quantity,
              'tax_rate_at_sale': item.taxRateAtSale,
              'is_tax_inclusive_at_sale': item.isTaxInclusiveAtSale,
            };
          }).toList(),
        };
      }).toList();

      final payload = {
        'store_id': storeId,
        'sales': salesData,
      };

      final response = await _dio.post(
        '$sanitizedUrl/api/v1/sync/batch',
        data: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final syncedUuids = List<String>.from(response.data['synced_uuids'] ?? []);
        return syncedUuids;
      }
      return [];
    } catch (e) {
      debugPrint('Cloud PostgreSQL sales batch sync failed: $e');
      rethrow;
    }
  }

  /// Fetch list of products from Cloud PostgreSQL DB for a specific store branch.
  Future<List<Map<String, dynamic>>> getProducts(String baseUrl, {required int storeId}) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final response = await _dio.get(
        '$sanitizedUrl/api/v1/products',
        queryParameters: {'store_id': storeId},
      );
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching products from cloud DB: $e');
      return [];
    }
  }
}

