import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Turnover Tax (TOT) — ZRA Zambia
///
/// ZRA TOT Rules:
///  - Monthly turnover ≤ K2,500  → 0%
///  - Monthly turnover > K2,500  → 5% of gross turnover
///  - Annual turnover > K5,000,000 → must switch to Income Tax
///  - Returns due by 14th of the following month
///  - Records must be kept for 6 years
class TotService {
  final Dio _dio;
  final String baseUrl;

  TotService({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {'Content-Type': 'application/json'},
              ),
            );

  String get _api => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  /// Compile gross turnover for a given month and compute TOT owed.
  Future<TotMonthlySummary?> fetchMonthlySummary({
    required int storeId,
    required int year,
    required int month,
  }) async {
    try {
      final resp = await _dio.get(
        '$_api/api/v1/tot/monthly-summary/$storeId',
        queryParameters: {'year': year, 'month': month},
      );
      if (resp.statusCode == 200) {
        return TotMonthlySummary.fromJson(Map<String, dynamic>.from(resp.data));
      }
    } catch (e) {
      debugPrint('TotService.fetchMonthlySummary error: $e');
    }
    return null;
  }

  /// Full-year turnover check with per-month breakdown.
  Future<TotAnnualCheck?> fetchAnnualCheck({
    required int storeId,
    required int year,
  }) async {
    try {
      final resp = await _dio.get(
        '$_api/api/v1/tot/annual-check/$storeId',
        queryParameters: {'year': year},
      );
      if (resp.statusCode == 200) {
        return TotAnnualCheck.fromJson(Map<String, dynamic>.from(resp.data));
      }
    } catch (e) {
      debugPrint('TotService.fetchAnnualCheck error: $e');
    }
    return null;
  }

  /// File a TOT return for the given month.
  Future<TotReturnResult?> submitReturn({
    required int storeId,
    required int year,
    required int month,
    String? notes,
  }) async {
    try {
      final resp = await _dio.post(
        '$_api/api/v1/tot/submit-return/$storeId',
        data: jsonEncode({
          'charge_year': year,
          'charge_month': month,
          'notes': ?notes,
        }),
      );
      if (resp.statusCode == 200) {
        return TotReturnResult.fromJson(Map<String, dynamic>.from(resp.data));
      }
    } catch (e) {
      debugPrint('TotService.submitReturn error: $e');
    }
    return null;
  }

  /// List all TOT returns for a store (optionally filtered by year).
  Future<List<TotReturnRecord>> listReturns({
    required int storeId,
    int? year,
  }) async {
    try {
      final resp = await _dio.get(
        '$_api/api/v1/tot/returns/$storeId',
        queryParameters: {'year': ?year},
      );

      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['returns'] as List<dynamic>? ?? []);
        return list.map((e) => TotReturnRecord.fromJson(Map<String, dynamic>.from(e))).toList();
      }
    } catch (e) {
      debugPrint('TotService.listReturns error: $e');
    }
    return [];
  }

  /// Mark a submitted return as paid.
  Future<bool> markPaid({required int storeId, required int returnId}) async {
    try {
      final resp = await _dio.patch(
        '$_api/api/v1/tot/returns/$storeId/$returnId/mark-paid',
      );
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('TotService.markPaid error: $e');
      return false;
    }
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

class TotMonthlySummary {
  final int storeId;
  final String storeName;
  final String? tpin;
  final int chargeYear;
  final int chargeMonth;
  final String monthName;
  final double grossTurnover;
  final double totRatePercent;
  final double totAmount;
  final String dueDate;
  final double ytdTurnover;
  final double annualLimit;
  final bool overAnnualLimit;
  final bool thresholdWarning;
  final bool alreadyFiled;
  final String? filedStatus;
  final int? filedReturnId;

  TotMonthlySummary({
    required this.storeId,
    required this.storeName,
    this.tpin,
    required this.chargeYear,
    required this.chargeMonth,
    required this.monthName,
    required this.grossTurnover,
    required this.totRatePercent,
    required this.totAmount,
    required this.dueDate,
    required this.ytdTurnover,
    required this.annualLimit,
    required this.overAnnualLimit,
    required this.thresholdWarning,
    required this.alreadyFiled,
    this.filedStatus,
    this.filedReturnId,
  });

  factory TotMonthlySummary.fromJson(Map<String, dynamic> j) => TotMonthlySummary(
        storeId: j['store_id'] ?? 0,
        storeName: j['store_name'] ?? '',
        tpin: j['tpin'],
        chargeYear: j['charge_year'] ?? 0,
        chargeMonth: j['charge_month'] ?? 0,
        monthName: j['month_name'] ?? '',
        grossTurnover: (j['gross_turnover'] ?? 0.0).toDouble(),
        totRatePercent: (j['tot_rate_percent'] ?? 0.0).toDouble(),
        totAmount: (j['tot_amount'] ?? 0.0).toDouble(),
        dueDate: j['due_date'] ?? '',
        ytdTurnover: (j['ytd_turnover'] ?? 0.0).toDouble(),
        annualLimit: (j['annual_limit'] ?? 5000000.0).toDouble(),
        overAnnualLimit: j['over_annual_limit'] ?? false,
        thresholdWarning: j['threshold_warning'] ?? false,
        alreadyFiled: j['already_filed'] ?? false,
        filedStatus: j['filed_status'],
        filedReturnId: j['filed_return_id'],
      );
}

class TotAnnualCheck {
  final int storeId;
  final String storeName;
  final int chargeYear;
  final double annualTurnover;
  final double annualTotDue;
  final double annualLimit;
  final bool eligibleForTot;
  final bool mustSwitchToIncomeTax;
  final bool thresholdWarning80pct;
  final List<TotMonthBreakdown> monthlyBreakdown;

  TotAnnualCheck({
    required this.storeId,
    required this.storeName,
    required this.chargeYear,
    required this.annualTurnover,
    required this.annualTotDue,
    required this.annualLimit,
    required this.eligibleForTot,
    required this.mustSwitchToIncomeTax,
    required this.thresholdWarning80pct,
    required this.monthlyBreakdown,
  });

  factory TotAnnualCheck.fromJson(Map<String, dynamic> j) => TotAnnualCheck(
        storeId: j['store_id'] ?? 0,
        storeName: j['store_name'] ?? '',
        chargeYear: j['charge_year'] ?? 0,
        annualTurnover: (j['annual_turnover'] ?? 0.0).toDouble(),
        annualTotDue: (j['annual_tot_due'] ?? 0.0).toDouble(),
        annualLimit: (j['annual_limit'] ?? 5000000.0).toDouble(),
        eligibleForTot: j['eligible_for_tot'] ?? true,
        mustSwitchToIncomeTax: j['must_switch_to_income_tax'] ?? false,
        thresholdWarning80pct: j['threshold_warning_80pct'] ?? false,
        monthlyBreakdown: ((j['monthly_breakdown'] as List<dynamic>?) ?? [])
            .map((e) => TotMonthBreakdown.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class TotMonthBreakdown {
  final int month;
  final String monthName;
  final double grossTurnover;
  final double totRatePercent;
  final double totAmount;

  TotMonthBreakdown({
    required this.month,
    required this.monthName,
    required this.grossTurnover,
    required this.totRatePercent,
    required this.totAmount,
  });

  factory TotMonthBreakdown.fromJson(Map<String, dynamic> j) => TotMonthBreakdown(
        month: j['month'] ?? 0,
        monthName: j['month_name'] ?? '',
        grossTurnover: (j['gross_turnover'] ?? 0.0).toDouble(),
        totRatePercent: (j['tot_rate_percent'] ?? 0.0).toDouble(),
        totAmount: (j['tot_amount'] ?? 0.0).toDouble(),
      );
}

class TotReturnResult {
  final String status;
  final int returnId;
  final double grossTurnover;
  final double totRatePercent;
  final double totAmount;
  final String dueDate;
  final String? digitaxReference;
  final String filedStatus;
  final String message;

  TotReturnResult({
    required this.status,
    required this.returnId,
    required this.grossTurnover,
    required this.totRatePercent,
    required this.totAmount,
    required this.dueDate,
    this.digitaxReference,
    required this.filedStatus,
    required this.message,
  });

  factory TotReturnResult.fromJson(Map<String, dynamic> j) => TotReturnResult(
        status: j['status'] ?? '',
        returnId: j['return_id'] ?? 0,
        grossTurnover: (j['gross_turnover'] ?? 0.0).toDouble(),
        totRatePercent: (j['tot_rate_percent'] ?? 0.0).toDouble(),
        totAmount: (j['tot_amount'] ?? 0.0).toDouble(),
        dueDate: j['due_date'] ?? '',
        digitaxReference: j['digitax_reference'],
        filedStatus: j['filed_status'] ?? '',
        message: j['message'] ?? '',
      );
}

class TotReturnRecord {
  final int id;
  final int chargeYear;
  final int chargeMonth;
  final String monthName;
  final double grossTurnover;
  final double totRatePercent;
  final double totAmount;
  final String? dueDate;
  final String status;
  final String? digitaxReference;
  final String? submittedAt;

  TotReturnRecord({
    required this.id,
    required this.chargeYear,
    required this.chargeMonth,
    required this.monthName,
    required this.grossTurnover,
    required this.totRatePercent,
    required this.totAmount,
    this.dueDate,
    required this.status,
    this.digitaxReference,
    this.submittedAt,
  });

  factory TotReturnRecord.fromJson(Map<String, dynamic> j) => TotReturnRecord(
        id: j['id'] ?? 0,
        chargeYear: j['charge_year'] ?? 0,
        chargeMonth: j['charge_month'] ?? 0,
        monthName: j['month_name'] ?? '',
        grossTurnover: (j['gross_turnover'] ?? 0.0).toDouble(),
        totRatePercent: (j['tot_rate_percent'] ?? 0.0).toDouble(),
        totAmount: (j['tot_amount'] ?? 0.0).toDouble(),
        dueDate: j['due_date'],
        status: j['status'] ?? 'draft',
        digitaxReference: j['digitax_reference'],
        submittedAt: j['submitted_at'],
      );
}
