import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZRA Turnover Tax (TOT) Calculation Rules', () {
    test('Turnover <= K1,000/month (K12,000/year) produces 0% TOT (NIL Return)', () {
      const grossTurnover = 950.00;
      final rate = grossTurnover <= 1000.0 ? 0.0 : 5.0;
      final totAmount = grossTurnover <= 1000.0 ? 0.0 : (grossTurnover * 0.05);

      expect(rate, equals(0.0));
      expect(totAmount, equals(0.0));
    });

    test('Turnover > K1,000 produces 5% flat TOT on gross sales', () {
      const grossTurnover = 48500.50;
      final rate = grossTurnover <= 1000.0 ? 0.0 : 5.0;
      final totAmount = double.parse((grossTurnover * 0.05).toStringAsFixed(2));

      expect(rate, equals(5.0));
      expect(totAmount, equals(2425.03));
    });

    test('YTD Threshold Warnings for TOT to Income Tax Migration', () {
      const ytdTurnoverWarning = 4200000.00;
      const ytdTurnoverExceeded = 5150000.00;
      const annualLimit = 5000000.00;

      expect(ytdTurnoverWarning > 4000000.0, isTrue);
      expect(ytdTurnoverWarning > annualLimit, isFalse);

      expect(ytdTurnoverExceeded > annualLimit, isTrue);
    });
  });

  group('Purchase Orders: VAT Regime vs TOT Regime Accounting', () {
    test('VAT Regime: When Input VAT on Purchases exceeds Output VAT, business has VAT Credit / Refund (K0.00 Payable)', () {
      const double grossSales = 11600.00; // 16% inclusive -> K1,600 Output VAT
      const double totalPurchases = 23200.00; // 16% inclusive -> K3,200 Input VAT

      final outputVat = double.parse((grossSales * 16.0 / 116.0).toStringAsFixed(2));
      final inputVat = double.parse((totalPurchases * 16.0 / 116.0).toStringAsFixed(2));

      final netVatPayable = outputVat > inputVat ? (outputVat - inputVat) : 0.00;
      final vatCreditRefund = inputVat > outputVat ? (inputVat - outputVat) : 0.00;

      expect(outputVat, equals(1600.00));
      expect(inputVat, equals(3200.00));
      expect(netVatPayable, equals(0.00)); // Nothing paid to ZRA
      expect(vatCreditRefund, equals(1600.00)); // K1,600 credit carried forward
    });

    test('TOT Regime: Input VAT on Purchases cannot be deducted; TOT is strictly 5% of gross sales', () {
      const double grossSales = 20000.00; // Sales made
      const double totalPurchases = 30000.00; // Purchase orders received (inclusive of supplier VAT)
      const double inventoryCost = totalPurchases; // Entire amount is booked into inventory / COGS

      // Under TOT: Gross sales > K1,000 -> 5% TOT
      final totPayable = double.parse((grossSales * 0.05).toStringAsFixed(2));

      // Under TOT: Purchases do not reduce TOT liability. They are booked as cost of goods sold.
      expect(totPayable, equals(1000.00));
      expect(inventoryCost, equals(30000.00));
    });
  });

  group('VAT Standard Line Item Calculations', () {
    test('16% Tax-Inclusive Price Extraction', () {
      const sellingPrice = 116.00;
      const taxRate = 16.0;

      final basePrice = double.parse((sellingPrice / (1 + (taxRate / 100))).toStringAsFixed(2));
      final taxAmount = double.parse((sellingPrice - basePrice).toStringAsFixed(2));

      expect(basePrice, equals(100.00));
      expect(taxAmount, equals(16.00));
      expect(basePrice + taxAmount, equals(sellingPrice));
    });

    test('16% Tax-Exclusive Price Calculation', () {
      const netPrice = 250.00;
      const taxRate = 16.0;

      final taxAmount = double.parse((netPrice * (taxRate / 100)).toStringAsFixed(2));
      final total = double.parse((netPrice + taxAmount).toStringAsFixed(2));

      expect(taxAmount, equals(40.00));
      expect(total, equals(290.00));
    });
  });

  group('Till Float & Shift Cash Drawer Reconciliation Balancing', () {
    test('Exact Cash Balancing (Zero Variance)', () {
      const double openingCash = 500.00;     // Float
      const double cashSales = 3450.75;       // Cash in
      const double cashDeposits = 200.00;    // Extra float added
      const double cashExpenses = 150.00;    // Petty cash paid
      const double cashRefunds = 75.25;      // Returned item refund
      const double cashWithdrawals = 1000.00;// Mid-day safe drop

      final expectedInDrawer = double.parse((
        openingCash +
        cashSales +
        cashDeposits -
        cashExpenses -
        cashRefunds -
        cashWithdrawals
      ).toStringAsFixed(2));

      expect(expectedInDrawer, equals(2925.50));

      const double countedPhysicalCash = 2925.50;
      final variance = double.parse((countedPhysicalCash - expectedInDrawer).toStringAsFixed(2));

      expect(variance, equals(0.00));
    });

    test('Cash Shortage Detection (Undershoot / Loss)', () {
      const double openingCash = 300.00;
      const double cashSales = 1200.00;
      const double expected = openingCash + cashSales; // 1500.00

      const double countedPhysicalCash = 1450.00; // Cashier is missing K50
      final variance = double.parse((countedPhysicalCash - expected).toStringAsFixed(2));

      expect(variance, equals(-50.00));
      expect(variance < 0, isTrue);
    });

    test('Cash Surplus Detection (Overshoot)', () {
      const double openingCash = 300.00;
      const double cashSales = 1200.00;
      const double expected = openingCash + cashSales; // 1500.00

      const double countedPhysicalCash = 1520.00; // Extra K20 in drawer
      final variance = double.parse((countedPhysicalCash - expected).toStringAsFixed(2));

      expect(variance, equals(20.00));
      expect(variance > 0, isTrue);
    });

    test('Micro-Penny Summations Produce No Ghost Amounts or Binary Float Drift', () {
      double total = 0.0;
      for (int i = 0; i < 1000; i++) {
        total += 19.99;
      }
      final cleanTotal = double.parse(total.toStringAsFixed(2));
      expect(cleanTotal, equals(19990.00));
    });
  });
}
