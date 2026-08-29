import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ZRA Tax Reminder Service — Zambia Revenue Authority
///
/// Only shows deadlines relevant to the business's registered tax type.
///
/// Tax type → relevant deadlines:
///   TURNOVER_TAX  → TOT (14th), PAYE (10th), SDL (10th), WHT (14th)
///   VAT_STANDARD  → VAT Suppliers (18th), PAYE (10th), SDL (10th), WHT (14th)
///   COMPOSITE     → VAT Suppliers (18th), TOT (14th), PAYE (10th), SDL (10th), WHT (14th)
///   EXEMPT        → PAYE (10th), SDL (10th) only

final taxReminderServiceProvider = Provider((ref) => TaxReminderService());

enum TaxUrgency { overdue, today, critical, warning, upcoming, clear }

/// A single ZRA tax deadline with its computed payment amount.
class ZraTaxDeadline {
  final String taxCode;       // e.g. "TOT", "VAT", "PAYE"
  final String taxName;       // Full ZRA name
  final DateTime dueDate;
  final DateTime chargeMonth; // First day of the charge month
  final int daysUntilDue;
  final TaxUrgency urgency;
  final String? description;
  final double? amountPayable;    // Actual K amount to pay ZRA
  final double? taxableBase;      // e.g. Gross Turnover / Taxable Sales
  final double? ratePercent;
  // VAT-specific
  final double? outputVat;
  final double? inputVat;
  // TOT-specific
  final bool? nilReturn;
  final bool? isAlreadyFiled;
  final String? filedReference;
  // Extra context
  final Map<String, dynamic>? supplemental;

  ZraTaxDeadline({
    required this.taxCode,
    required this.taxName,
    required this.dueDate,
    required this.chargeMonth,
    required this.daysUntilDue,
    required this.urgency,
    this.description,
    this.amountPayable,
    this.taxableBase,
    this.ratePercent,
    this.outputVat,
    this.inputVat,
    this.nilReturn,
    this.isAlreadyFiled,
    this.filedReference,
    this.supplemental,
  });

  bool get needsAction =>
      urgency == TaxUrgency.overdue ||
      urgency == TaxUrgency.today ||
      urgency == TaxUrgency.critical;

  bool get hasAmount => amountPayable != null;

  /// Build from the backend /api/v1/tax-statement/monthly response tax entry.
  factory ZraTaxDeadline.fromApiEntry(Map<String, dynamic> entry, DateTime today) {
    final due = DateTime.parse(entry['due_date'] as String);
    final diff = due.difference(DateTime(today.year, today.month, today.day)).inDays;
    return ZraTaxDeadline(
      taxCode: entry['tax_code'] as String,
      taxName: entry['tax_name'] as String,
      dueDate: due,
      chargeMonth: DateTime(today.year, today.month > 1 ? today.month - 1 : 12, 1),
      daysUntilDue: diff,
      urgency: TaxReminderService._computeUrgency(diff),
      description: entry['description'] as String?,
      amountPayable: (entry['amount_payable'] as num?)?.toDouble(),
      taxableBase: (entry['taxable_base'] as num?)?.toDouble(),
      ratePercent: (entry['rate_percent'] as num?)?.toDouble(),
      outputVat: (entry['output_vat'] as num?)?.toDouble(),
      inputVat: (entry['input_vat'] as num?)?.toDouble(),
      nilReturn: entry['nil_return'] as bool?,
      isAlreadyFiled: entry['is_filed'] as bool?,
      filedReference: entry['filed_reference'] as String?,
      supplemental: entry['supplemental'] as Map<String, dynamic>?,
    );
  }
}

class TaxReminderService {
  static TaxUrgency _computeUrgency(int daysUntilDue) {
    if (daysUntilDue < 0) return TaxUrgency.overdue;
    if (daysUntilDue == 0) return TaxUrgency.today;
    if (daysUntilDue <= 2) return TaxUrgency.critical;
    if (daysUntilDue <= 7) return TaxUrgency.warning;
    if (daysUntilDue <= 14) return TaxUrgency.upcoming;
    return TaxUrgency.clear;
  }

  /// Build deadline list from a full API tax-statement response.
  /// Filters to only actionable (≤14 days or overdue) items.
  List<ZraTaxDeadline> fromApiResponse(
    Map<String, dynamic> apiResponse, {
    bool allDeadlines = false,
  }) {
    final today = DateTime.now();
    final entries = (apiResponse['taxes'] as List<dynamic>? ?? []);
    final deadlines = entries
        .map((e) => ZraTaxDeadline.fromApiEntry(Map<String, dynamic>.from(e), today))
        .where((d) => allDeadlines || d.urgency != TaxUrgency.clear)
        .toList();
    deadlines.sort((a, b) => a.daysUntilDue.compareTo(b.daysUntilDue));
    return deadlines;
  }

  /// Lightweight local computation for the banner chip — no API call needed.
  /// Returns upcoming deadlines for the CURRENT charge month based on tax type.
  List<ZraTaxDeadline> getLocalDeadlines({
    required String businessTaxType,
    DateTime? referenceDate,
  }) {
    final today = referenceDate ?? DateTime.now();
    // Charge month = previous month (filing for last month)
    final chargeYear = today.month == 1 ? today.year - 1 : today.year;
    final chargeMonth = today.month == 1 ? 12 : today.month - 1;
    final chargeMonthStart = DateTime(chargeYear, chargeMonth, 1);

    final deadlines = <ZraTaxDeadline>[];

    void add(String code, String name, int dueDay, String desc) {
      final m = chargeMonth + 1 > 12 ? 1 : chargeMonth + 1;
      final y = chargeMonth + 1 > 12 ? chargeYear + 1 : chargeYear;
      final due = DateTime(y, m, dueDay);
      final diff = due.difference(DateTime(today.year, today.month, today.day)).inDays;
      final urgency = _computeUrgency(diff);
      if (urgency == TaxUrgency.clear) return; // outside 14-day window
      deadlines.add(ZraTaxDeadline(
        taxCode: code,
        taxName: name,
        dueDate: due,
        chargeMonth: chargeMonthStart,
        daysUntilDue: diff,
        urgency: urgency,
        description: desc,
      ));
    }

    // ── Tax-type-specific ──────────────────────────────────────────────────
    switch (businessTaxType) {
      case 'TURNOVER_TAX':
        add('TOT', 'Turnover Tax (TOT)', 14,
            '5% on gross monthly turnover > K2,500');
      case 'VAT_STANDARD':
        add('VAT', 'Value Added Tax — Suppliers', 18,
            '16% VAT (Output VAT less Input VAT)');
      case 'COMPOSITE':
        add('VAT', 'Value Added Tax — Suppliers', 18,
            '16% VAT (Output VAT less Input VAT)');
        add('TOT', 'Turnover Tax (TOT)', 14,
            '5% on gross monthly turnover > K2,500');
      case 'EXEMPT':
        break; // No VAT/TOT
    }

    deadlines.sort((a, b) => a.daysUntilDue.compareTo(b.daysUntilDue));
    return deadlines;
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  String urgencyLabel(ZraTaxDeadline d) {
    switch (d.urgency) {
      case TaxUrgency.overdue:  return '${(-d.daysUntilDue)}d OVERDUE';
      case TaxUrgency.today:    return 'DUE TODAY';
      case TaxUrgency.critical: return '${d.daysUntilDue}d LEFT';
      case TaxUrgency.warning:  return '${d.daysUntilDue}d LEFT';
      case TaxUrgency.upcoming: return '${d.daysUntilDue}d';
      case TaxUrgency.clear:    return 'OK';
    }
  }

  Color urgencyColor(TaxUrgency urgency) {
    switch (urgency) {
      case TaxUrgency.overdue:  return const Color(0xFFFF4444);
      case TaxUrgency.today:    return const Color(0xFFFF6B00);
      case TaxUrgency.critical: return const Color(0xFFFF8C00);
      case TaxUrgency.warning:  return const Color(0xFFF5C842);
      case TaxUrgency.upcoming: return const Color(0xFF5DD39E);
      case TaxUrgency.clear:    return const Color(0xFF5DD39E);
    }
  }
}
