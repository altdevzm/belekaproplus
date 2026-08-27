import 'package:intl/intl.dart';

class CurrencyFormatter {
  /// Formats an amount with a currency symbol.
  /// 
  /// Resulting format:
  /// Positive: ZMW 344.00
  /// Negative: -ZMW 344.00
  static String format(double amount, String symbol) {
    if (amount.isNaN) return '${symbol.toUpperCase()} 0.00';
    
    final formatter = NumberFormat("#,##0.00");
    final absAmount = amount.abs();
    final formattedValue = formatter.format(absAmount);
    
    // Note: Dash and Bracket formatting removed as per user request.
    // Negative values should be handled via UI colors/icons.
    return '${symbol.toUpperCase()} $formattedValue';
  }

  /// Shorthand for simple formatting without a sign prefix for negative numbers
  /// (if needed for list headers or specific UI elements)
  static String formatSimple(double amount, String symbol) {
    final cleanSymbol = symbol.toUpperCase().trim();
    return '$cleanSymbol ${amount.abs().toStringAsFixed(2)}';
  }

  /// Formats tax and fiscal breakdown amounts with 4 decimal places matching DigiTax/ZRA VSDC precision
  /// Result: ZK 12.0000 or ZK 1.6552
  static String formatTaxPrecision(double amount, String symbol) {
    if (amount.isNaN) return '${symbol.toUpperCase().trim()} 0.0000';
    final formatter = NumberFormat("#,##0.0000");
    final absAmount = amount.abs();
    final formattedValue = formatter.format(absAmount);
    return '${symbol.toUpperCase().trim()} $formattedValue';
  }
}
