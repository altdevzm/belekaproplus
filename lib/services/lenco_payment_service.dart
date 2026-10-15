import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';

final lencoPaymentServiceProvider = Provider<LencoPaymentService>((ref) {
  final config = ref.watch(storeConfigProvider).value;
  return LencoPaymentService(config: config);
});

class LencoPaymentService {
  final StoreConfig? config;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ),
  );

  LencoPaymentService({this.config});

  String get _baseUrl {
    if (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty) {
      final url = config!.cloudApiUrl!.trim();
      return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
    return 'http://23.139.36.20:8003';
  }

  int get _storeId => config?.cloudStoreId ?? 1;

  /// Fetch available banks in Zambia (or specified country)
  Future<List<Map<String, dynamic>>> getBanks({String country = 'zm'}) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/api/v1/lenco/banks',
        queryParameters: {'store_id': _storeId, 'country': country},
      );
      if (res.statusCode == 200 && res.data['status'] == true) {
        final List list = res.data['data'] ?? [];
        return list.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (e) {
      debugPrint('Lenco getBanks error: $e');
    }
    // Fallback official Zambian banks list
    return [
      {'id': '002', 'name': 'Absa Bank Zambia', 'country': 'zm'},
      {'id': '004', 'name': 'Stanbic Bank Zambia', 'country': 'zm'},
      {'id': '005', 'name': 'Standard Chartered Bank Zambia', 'country': 'zm'},
      {'id': '009', 'name': 'Zambia National Commercial Bank (Zanaco)', 'country': 'zm'},
      {'id': '010', 'name': 'Indo Zambia Bank', 'country': 'zm'},
      {'id': '014', 'name': 'First National Bank (FNB Zambia)', 'country': 'zm'},
      {'id': '016', 'name': 'Atlas Mara / Access Bank Zambia', 'country': 'zm'},
      {'id': '018', 'name': 'Citibank Zambia', 'country': 'zm'},
      {'id': '025', 'name': 'Ecobank Zambia', 'country': 'zm'},
      {'id': '026', 'name': 'Investrust Bank', 'country': 'zm'},
      {'id': '029', 'name': 'United Bank for Africa (UBA Zambia)', 'country': 'zm'},
    ];
  }

  /// Resolve bank account number and bank ID to retrieve the account holder's name.
  /// (e.g. "Jacob Mjuda")
  Future<Map<String, dynamic>> resolveBankAccount({
    required String accountNumber,
    required String bankId,
    String country = 'zm',
  }) async {
    try {
      final res = await _dio.post(
        '$_baseUrl/api/v1/lenco/resolve-bank-account',
        data: {
          'store_id': _storeId,
          'account_number': accountNumber.trim(),
          'bank_id': bankId.trim(),
          'country': country,
        },
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('Lenco resolveBankAccount error: $e');
    }
    return {
      'status': false,
      'message': 'Failed to resolve bank account details',
    };
  }

  /// Resolve Mobile Money customer name
  Future<Map<String, dynamic>> resolveMobileMoney({
    required String phone,
    required String operator,
    String country = 'zm',
  }) async {
    try {
      final res = await _dio.post(
        '$_baseUrl/api/v1/lenco/resolve-mobile-money',
        data: {
          'store_id': _storeId,
          'phone': phone.trim(),
          'operator': operator.toLowerCase().trim(),
          'country': country,
        },
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('Lenco resolveMobileMoney error: $e');
    }
    return {'status': false, 'message': 'Unable to resolve mobile money account'};
  }

  /// Request payment via Mobile Money STK/USSD prompt on client phone
  Future<Map<String, dynamic>> initiateMobileMoneyPayment({
    required double amount,
    required String reference,
    required String phone,
    required String operator,
    String country = 'zm',
  }) async {
    try {
      final res = await _dio.post(
        '$_baseUrl/api/v1/lenco/collect/mobile-money',
        data: {
          'store_id': _storeId,
          'amount': amount,
          'reference': reference,
          'phone': phone.trim(),
          'operator': operator.toLowerCase().trim(),
          'country': country,
          'bearer': 'merchant',
        },
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('Lenco initiateMobileMoneyPayment error: $e');
    }
    return {'status': false, 'message': 'Failed to initiate Mobile Money collection'};
  }

  /// Poll payment collection status
  Future<Map<String, dynamic>> checkPaymentStatus({required String reference}) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/api/v1/lenco/status/$reference',
        queryParameters: {'store_id': _storeId},
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('Lenco checkPaymentStatus error: $e');
    }
    return {'status': false, 'message': 'Could not check status'};
  }

  /// Fetch merchant's bank accounts configured on Lenco
  Future<List<Map<String, dynamic>>> getStoreAccounts() async {
    try {
      final res = await _dio.get(
        '$_baseUrl/api/v1/lenco/store-accounts',
        queryParameters: {'store_id': _storeId},
      );
      if (res.statusCode == 200 && res.data['status'] == true) {
        final List list = res.data['data'] ?? [];
        return list.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (e) {
      debugPrint('Lenco getStoreAccounts error: $e');
    }
    return [];
  }

  /// Test Lenco API Token credentials
  Future<Map<String, dynamic>> testCredentials({
    required String apiKey,
    String environment = 'sandbox',
  }) async {
    try {
      final res = await _dio.post(
        '$_baseUrl/api/v1/lenco/test-credentials',
        data: {
          'api_key': apiKey.trim(),
          'environment': environment,
        },
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('Lenco testCredentials error: $e');
    }
    return {'status': false, 'message': 'Failed to reach Lenco authentication servers'};
  }
}
