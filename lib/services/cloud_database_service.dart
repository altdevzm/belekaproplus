import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:beleka_pos/models/models.dart';

class CloudAuthException implements Exception {
  final String message;

  const CloudAuthException(this.message);

  @override
  String toString() => message;
}

class CloudDatabaseService {
  final Dio _dio;

  CloudDatabaseService({Dio? dio})
    : _dio =
          dio ??
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
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.get('$sanitizedUrl/health');
      return response.statusCode == 200 && response.data['status'] == 'healthy';
    } catch (e) {
      debugPrint('Cloud PostgreSQL DB Connection Check Failed: $e');
      return false;
    }
  }

  /// Authenticate any user (Manager, Cashier, Owner) against Cloud PostgreSQL DB via TPIN + ID + Password.
  Future<Map<String, dynamic>?> authenticateUser({
    required String baseUrl,
    required String numericId,
    required String pin,
    String? tpin,
    String? branchCode,
    String? companyName,
    String? terminalName,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final payload = <String, dynamic>{
        'numeric_id': numericId.trim(),
        'pin': pin.trim(),
        'terminal_name': terminalName ?? 'POS-TERMINAL',
      };
      if (tpin != null && tpin.trim().isNotEmpty) {
        payload['tpin'] = tpin.trim();
      }
      if (branchCode != null && branchCode.trim().isNotEmpty) {
        payload['branch_code'] = branchCode.trim();
      }
      if (companyName != null && companyName.trim().isNotEmpty) {
        payload['company_name'] = companyName.trim();
      }
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/auth/login',
        data: payload,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      throw const CloudAuthException(
        'Cloud login returned an invalid response.',
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      debugPrint('Cloud PostgreSQL Auth Failed: $detail');
      throw CloudAuthException(detail?.toString() ?? 'Cloud login failed.');
    } catch (e) {
      debugPrint('Cloud PostgreSQL Auth Failed: $e');
      if (e is CloudAuthException) rethrow;
      throw CloudAuthException('Cloud login failed: $e');
    }
  }

  /// Register a new organization with its TPIN-scoped HQ owner account.
  Future<Map<String, dynamic>?> registerOrganization({
    required String baseUrl,
    required String businessName,
    required String tpin,
    required String numericId,
    required String pin,
    String ownerName = 'Owner',
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/auth/register',
        data: {
          'business_name': businessName.trim(),
          'tpin': tpin.trim(),
          'numeric_id': numericId.trim(),
          'pin': pin.trim(),
          'owner_name': ownerName.trim().isEmpty ? 'Owner' : ownerName.trim(),
          'store_code': '${tpin.trim()}-HQ',
          'branch_name': 'Headquarters (HQ)',
          'terminal_name': 'MANAGER-01',
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw const CloudAuthException(
        'Cloud registration returned an invalid response.',
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      throw CloudAuthException(
        detail?.toString() ?? 'Cloud registration failed.',
      );
    } catch (e) {
      if (e is CloudAuthException) rethrow;
      throw CloudAuthException('Cloud registration failed: $e');
    }
  }

  /// Resolve a company name to its tenant TPIN before authentication.
  Future<String?> resolveOrganizationTpin({
    required String baseUrl,
    required String companyName,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/auth/resolve-organization',
        data: {'company_name': companyName.trim()},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return (response.data['tpin'] as String?)?.trim();
      }
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      throw CloudAuthException(detail?.toString() ?? 'Company lookup failed.');
    }
  }

  Options? _buildAuthOptions(String? authToken) {
    if (authToken != null && authToken.trim().isNotEmpty) {
      return Options(headers: {'Authorization': 'Bearer ${authToken.trim()}'});
    }
    return null;
  }

  /// Push/Sync a user or Branch Manager to Cloud PostgreSQL DB.
  Future<bool> syncUser({
    required String baseUrl,
    required int storeId,
    required User user,
    String? plainPin,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/users',
        data: {
          'store_id': storeId,
          'numeric_id': user.numericId,
          'name': user.name,
          'role': user.role,
          'branch_name': user.branchName,
          'phone': user.phone,
          'password_hash': plainPin?.trim().isNotEmpty == true
              ? plainPin!.trim()
              : user.passwordHash,
          'is_active': user.isActive,
        },
        options: _buildAuthOptions(authToken),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      debugPrint('Cloud PostgreSQL User Push Failed: $detail');
      throw CloudAuthException(
        detail?.toString() ?? 'Cloud user synchronization failed.',
      );
    } catch (e) {
      debugPrint('Cloud PostgreSQL User Push Failed: $e');
      throw CloudAuthException('Cloud user synchronization failed: $e');
    }
  }

  Future<bool> deleteUser({
    required String baseUrl,
    required int storeId,
    required String numericId,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.delete(
        '$sanitizedUrl/api/v1/users/by-numeric/${Uri.encodeComponent(numericId)}',
        queryParameters: {'store_id': storeId},
        options: _buildAuthOptions(authToken),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } on DioException catch (e) {
      // Deletion is idempotent: a prior successful delete should not block
      // cleanup of the corresponding local account.
      if (e.response?.statusCode == 404) return true;
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      throw CloudAuthException(
        detail?.toString() ?? 'Cloud user deletion failed.',
      );
    }
  }

  /// Push/Sync a Store Branch to Cloud PostgreSQL DB.
  /// Returns the backend store_id (int) on success, or null on failure.
  Future<int?> syncBranch({
    required String baseUrl,
    required StoreBranch branch,
    String? tpin,
    String? digitaxApiKey,
    String? digitaxEnvironment,
    String? businessTaxType,
    String? currencySymbol,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final data = {
        // BHF ID is the canonical branch identity. store_code remains only
        // for compatibility with older backend records.
        'store_code': branch.bhfId,
        'bhf_id': branch.bhfId,
        'name': branch.name,
        'address': branch.address,
        'contact_number': branch.phone,
        'email': branch.email,
        'branch_name': branch.name,
        'manager_name': branch.managerName,
        'manager_id': branch.managerId,
        'manager_phone': branch.managerPhone,
        if (tpin != null && tpin.isNotEmpty) 'tpin': tpin,
        if (digitaxApiKey != null && digitaxApiKey.isNotEmpty)
          'digitax_api_key': digitaxApiKey,
        'digitax_environment': digitaxEnvironment ?? 'sandbox',
        'business_tax_type': businessTaxType ?? 'VAT_STANDARD',
        'currency_symbol': currencySymbol ?? 'K',
      };
      final response = branch.cloudStoreId > 0
          ? await _dio.put(
              '$sanitizedUrl/api/v1/stores/${branch.cloudStoreId}',
              data: data,
              options: _buildAuthOptions(authToken),
            )
          : await _dio.post(
              '$sanitizedUrl/api/v1/stores',
              data: data,
              options: _buildAuthOptions(authToken),
            );
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Return the backend store id from the response for local mapping
        final data = response.data;
        if (data is Map && data['id'] != null) {
          return (data['id'] as num).toInt();
        }
        return 0; // success but no id in response
      }
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      debugPrint('Cloud PostgreSQL Branch Push Failed: $detail');
      throw CloudAuthException(
        detail?.toString() ?? 'Cloud branch synchronization failed.',
      );
    } catch (e) {
      debugPrint('Cloud PostgreSQL Branch Push Failed: $e');
      rethrow;
    }
  }

  Future<bool> deleteBranch({
    required String baseUrl,
    required int storeId,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.delete(
        '$sanitizedUrl/api/v1/stores/$storeId',
        options: _buildAuthOptions(authToken),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ?? e.message)
          : e.message;
      throw CloudAuthException(
        detail?.toString() ?? 'Cloud branch deletion failed.',
      );
    }
  }

  /// Push/Update store configuration (TPIN, DigiTax Key, Environment, etc.) on Cloud DB
  Future<bool> updateStoreConfig({
    required String baseUrl,
    required int storeId,
    required Map<String, dynamic> data,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.put(
        '$sanitizedUrl/api/v1/stores/$storeId',
        data: data,
        options: _buildAuthOptions(authToken),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Cloud PostgreSQL Store Config Update Failed: $e');
      return false;
    }
  }

  /// Fetch list of available store branches from Cloud PostgreSQL DB.
  Future<List<Map<String, dynamic>>> getStores(
    String baseUrl, {
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.get(
        '$sanitizedUrl/api/v1/stores',
        options: _buildAuthOptions(authToken),
      );
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
  Future<List<Map<String, dynamic>>> getUsers(
    String baseUrl, {
    int? storeId,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final queryParams = storeId != null ? {'store_id': storeId} : null;
      final response = await _dio.get(
        '$sanitizedUrl/api/v1/users',
        queryParameters: queryParams,
        options: _buildAuthOptions(authToken),
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
    String? authToken,
  }) async {
    if (transactions.isEmpty) return [];

    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      final salesData = transactions.map((tx) {
        return {
          'transaction_uuid':
              tx.transactionId ?? 'tx-${DateTime.now().millisecondsSinceEpoch}',
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

      final payload = {'store_id': storeId, 'sales': salesData};

      final response = await _dio.post(
        '$sanitizedUrl/api/v1/sync/batch',
        data: payload,
        options: _buildAuthOptions(authToken),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final syncedUuids = List<String>.from(
          response.data['synced_uuids'] ?? [],
        );
        return syncedUuids;
      }
      return [];
    } catch (e) {
      debugPrint('Cloud PostgreSQL sales batch sync failed: $e');
      rethrow;
    }
  }

  Future<bool> syncInventorySnapshot({
    required String baseUrl,
    required int storeId,
    required List<Product> products,
    required List<StockMovement> movements,
    String? authToken,
  }) async {
    final sanitizedUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final response = await _dio.post(
      '$sanitizedUrl/api/v1/sync/inventory',
      data: {
        'store_id': storeId,
        'products': products
            .map(
              (product) => {
                'sku': product.sku,
                'name': product.name,
                'price': product.price,
                'unit_cost': product.unitCost,
                'stock_level': product.stockLevel,
                'category_id': product.categoryId,
                'is_tax_inclusive': product.isTaxInclusive,
                'tax_rate': product.taxRate,
                'zra_tax_code': product.zraTaxCode,
                'item_cls_cd': product.itemClsCd,
                'is_archived': product.isArchived,
                'discount_price': product.discountPrice,
              },
            )
            .toList(),
        'stock_movements': movements
            .map(
              (movement) => {
                'product_id': movement.productId,
                'product_name': movement.productName,
                'sku': movement.sku,
                'branch_code': movement.branchCode,
                'branch_name': movement.branchName,
                'movement_type': movement.movementType,
                'action_type': movement.actionType,
                'previous_stock': movement.previousStock,
                'quantity_changed': movement.quantityChanged,
                'new_stock': movement.newStock,
                'unit_cost': movement.unitCost,
                'total_cost_impact': movement.totalCostImpact,
                'reason_category': movement.reasonCategory,
                'reason_notes': movement.reasonNotes,
                'user_id': movement.userId,
                'user_name': movement.userName,
                'timestamp': movement.timestamp.toIso8601String(),
              },
            )
            .toList(),
      },
      options: _buildAuthOptions(authToken),
    );
    return response.statusCode == 200;
  }

  /// Fetch list of products from Cloud PostgreSQL DB for a specific store branch.
  Future<List<Map<String, dynamic>>> getProducts(
    String baseUrl, {
    required int storeId,
    String? authToken,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.get(
        '$sanitizedUrl/api/v1/products',
        queryParameters: {'store_id': storeId},
        options: _buildAuthOptions(authToken),
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

  /// Download a full database backup export snapshot from the VPS backend.
  Future<Map<String, dynamic>?> downloadVpsBackup({
    required String baseUrl,
    required int storeId,
    String? token,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.get(
        '$sanitizedUrl/api/v1/sync/export-backup',
        queryParameters: {'store_id': storeId},
        options: _buildAuthOptions(token),
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('VPS Cloud Backup Download Failed: $e');
      return null;
    }
  }

  /// Permanently purge the company organization account and all branches on the VPS.
  Future<Map<String, dynamic>> purgeCompanyAccount({
    required String baseUrl,
    required String authToken,
    required String confirmPhrase,
    required String password,
  }) async {
    try {
      final sanitizedUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _dio.post(
        '$sanitizedUrl/api/v1/stores/company/purge',
        data: {
          'confirm_phrase': confirmPhrase.trim(),
          'password': password.trim(),
        },
        options: _buildAuthOptions(authToken),
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': true, 'message': 'Company account successfully purged.'};
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail']?.toString() ?? e.message)
          : (e.message ?? 'Purge request failed');
      throw Exception(detail);
    } catch (e) {
      throw Exception('Failed to purge cloud company account: $e');
    }
  }
}

