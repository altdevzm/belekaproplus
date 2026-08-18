import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:beleka_pos/utils/formatters.dart';

final exportServiceProvider = Provider((ref) => ExportService());

class ExportService {
  // --- Brand & Style Helpers ---

  PdfColor _getBrandColor(StoreConfig? config) {
    if (config?.brandColorHex != null && config!.brandColorHex!.isNotEmpty) {
      try {
        String hex = config.brandColorHex!.replaceAll('#', '').trim();
        if (hex.length == 6) hex = 'FF$hex';
        final intVal = int.parse(hex, radix: 16);
        return PdfColor.fromInt(intVal);
      } catch (e) {
        debugPrint('Error parsing brandColorHex: $e');
      }
    }
    return _getSectorColor(config?.primarySector ?? CategorySector.other);
  }

  bool _isColorLight(PdfColor color) {
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue);
    return luminance > 0.65;
  }

  Future<pw.MemoryImage?> _loadLogoImage(StoreConfig? config) async {
    final logoPath = config?.logoPath;
    if (logoPath != null && File(logoPath).existsSync()) {
      try {
        return pw.MemoryImage(File(logoPath).readAsBytesSync());
      } catch (e) {
        debugPrint('Error loading custom logo from path: $e');
      }
    }
    // Fallback to asset logo
    try {
      final byteData = await rootBundle.load('assets/images/logo.png');
      return pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (e) {
      debugPrint('PDF Logo fallback error: $e');
      return null;
    }
  }

  pw.Widget _buildDocumentHeader(
    StoreConfig? config, {
    required String title,
    required PdfColor brandColor,
    pw.MemoryImage? logoImage,
  }) {
    final companyName = (config != null && config.businessName.isNotEmpty)
        ? config.businessName.toUpperCase()
        : 'BELEKA PRO POS';
    final branch = config?.branchName ?? config?.terminalName;
    final address = config?.address;
    final phone = config?.contactNumber;
    final email = config?.email;
    final website = config?.website;
    final tpin = (config?.tpin != null && config!.tpin!.isNotEmpty)
        ? config.tpin!
        : (config?.taxId != null && config!.taxId!.isNotEmpty ? config.taxId! : null);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 58,
                      height: 58,
                      margin: const pw.EdgeInsets.only(right: 14),
                      decoration: pw.BoxDecoration(
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: brandColor, width: 1.5),
                      ),
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: brandColor,
                          ),
                        ),
                        if (branch != null && branch.isNotEmpty)
                          pw.Text(
                            'Branch / Outlet: $branch',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey800,
                            ),
                          ),
                        if (address != null && address.isNotEmpty)
                          pw.Text(
                            address,
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                          ),
                        if ((phone != null && phone.isNotEmpty) || (email != null && email.isNotEmpty))
                          pw.Text(
                            [
                              if (phone != null && phone.isNotEmpty) 'Tel: $phone',
                              if (email != null && email.isNotEmpty) 'Email: $email',
                            ].join('   |   '),
                            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        if (website != null && website.isNotEmpty)
                          pw.Text(
                            website,
                            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.blue800),
                          ),
                        if (tpin != null && tpin.isNotEmpty)
                          pw.Container(
                            margin: const pw.EdgeInsets.only(top: 4),
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.grey200,
                              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                            ),
                            child: pw.Text(
                              'TPIN / TAX PIN: $tpin',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: brandColor,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    title.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          height: 2.5,
          decoration: pw.BoxDecoration(
            color: brandColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  // --- CSV Exports ---

  Future<void> exportTransactionsToCsv(List<SaleTransaction> transactions, {StoreConfig? config}) async {
    List<List<dynamic>> rows = [];
    final currency = config?.currencySymbol ?? 'ZK';
    
    // Header with Company Branding & Contacts
    if (config != null) {
      rows.add(['COMPANY', config.businessName.toUpperCase()]);
      if (config.branchName != null && config.branchName!.isNotEmpty) {
        rows.add(['BRANCH', config.branchName!]);
      }
      if (config.address != null && config.address!.isNotEmpty) {
        rows.add(['ADDRESS', config.address!]);
      }
      if (config.contactNumber != null && config.contactNumber!.isNotEmpty) {
        rows.add(['CONTACT', config.contactNumber!]);
      }
      if (config.email != null && config.email!.isNotEmpty) {
        rows.add(['EMAIL', config.email!]);
      }
      if (config.tpin != null && config.tpin!.isNotEmpty) {
        rows.add(['TPIN', config.tpin!]);
      }
      rows.add(['REPORT', 'Transaction Sales Ledger']);
      rows.add(['GENERATED', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())]);
      rows.add([]); // Spacing
    }

    rows.add([
      'Date & Time',
      'Transaction ID',
      'Cashier',
      'Subtotal ($currency)',
      'Tax ($currency)',
      'Discount ($currency)',
      'Total ($currency)',
      'Payment Method',
      'Status'
    ]);

    double totalCash = 0;
    double totalCard = 0;
    double totalMomo = 0;
    double grandTotal = 0;

    for (var tx in transactions) {
      final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
      final subtotal = tx.subtotal.isNaN ? 0.0 : tx.subtotal;
      final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;
      final discount = tx.discountAmount.isNaN ? 0.0 : tx.discountAmount;

      rows.add([
        DateFormat('yyyy-MM-dd HH:mm').format(tx.timestamp),
        tx.id.toString(),
        tx.cashierName,
        subtotal.isNaN ? '0.00' : subtotal.toStringAsFixed(2),
        tax.isNaN ? '0.00' : tax.toStringAsFixed(2),
        discount.isNaN ? '0.00' : discount.abs().toStringAsFixed(2),
        total.isNaN ? '0.00' : total.toStringAsFixed(2),
        tx.paymentMethod.toUpperCase(),
        tx.status
      ]);

      grandTotal += total;
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        totalCash += total;
      } else if (method.contains('card')) {
        totalCard += total;
      } else if (method.contains('mobile') || method.contains('momo')) {
        totalMomo += total;
      }
    }

    // Summary
    rows.add([]);
    rows.add(['FINANCIAL SUMMARY']);
    rows.add(['Total Cash Collected', '', '', '', '', '', CurrencyFormatter.format(totalCash, currency)]);
    rows.add(['Total Card Collected', '', '', '', '', '', CurrencyFormatter.format(totalCard, currency)]);
    rows.add(['Total Mobile Money', '', '', '', '', '', CurrencyFormatter.format(totalMomo, currency)]);
    rows.add(['GRAND REVENUE TOTAL', '', '', '', '', '', CurrencyFormatter.format(grandTotal, currency)]);

    String csvData = const ListToCsvConverter().convert(rows);
    await _saveFile(Uint8List.fromList(csvData.codeUnits), 'transactions_${DateTime.now().millisecondsSinceEpoch}.csv', extensions: ['csv']);
  }

  // --- PDF Transaction Report ---

  Future<void> exportTransactionsToPdf(List<SaleTransaction> transactions, {StoreConfig? config}) async {
    final pdf = pw.Document();
    final currency = config?.currencySymbol ?? 'ZK';
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);

    // Calculate Summary Data
    double totalCash = 0;
    double totalCard = 0;
    double totalMomo = 0;
    double totalTax = 0;
    double grandTotal = 0;

    for (var tx in transactions) {
      final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
      final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;
      grandTotal += total;
      totalTax += tax;
      
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        totalCash += total;
      } else if (method.contains('card')) {
        totalCard += total;
      } else if (method.contains('mobile') || method.contains('momo')) {
        totalMomo += total;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'Transaction Report',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Time', 'Tx ID', 'Cashier', 'Method', 'Tax ($currency)', 'Total ($currency)'],
            data: transactions.map((tx) {
              final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
              final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;
              return [
                DateFormat('yyyy-MM-dd HH:mm').format(tx.timestamp),
                tx.id.toString(),
                tx.cashierName,
                tx.paymentMethod.toUpperCase(),
                tax.toStringAsFixed(2),
                total.toStringAsFixed(2),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
              fontSize: 9.5,
            ),
            headerDecoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            cellHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 250,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: brandColor, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'PAYMENT SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: brandColor,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 1, color: brandColor),
                  _buildSummaryRow('Total Cash:', CurrencyFormatter.format(totalCash, currency)),
                  _buildSummaryRow('Total Card:', CurrencyFormatter.format(totalCard, currency)),
                  _buildSummaryRow('Total Mobile Money:', CurrencyFormatter.format(totalMomo, currency)),
                  _buildSummaryRow('Total Tax (VAT):', CurrencyFormatter.format(totalTax, currency)),
                  pw.Divider(thickness: 1),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('GRAND TOTAL:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        CurrencyFormatter.format(grandTotal, currency),
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: brandColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}   •   Beleka Pro POS Document Export',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey),
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'transactions_${DateTime.now().millisecondsSinceEpoch}.pdf', extensions: ['pdf']);
  }

  pw.Widget _buildSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9.5)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // --- Excel Transaction Export ---

  Future<void> exportTransactionsToExcel(List<SaleTransaction> transactions, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Transactions'];
    final currency = config?.currencySymbol ?? 'ZK';
    
    // Summary data
    double totalCash = 0;
    double totalCard = 0;
    double totalMomo = 0;
    double grandTotal = 0;

    sheet.appendRow([TextCellValue(config?.businessName.toUpperCase() ?? 'BELEKA PRO POS')]);
    if (config?.branchName != null) {
      sheet.appendRow([TextCellValue('Branch: ${config!.branchName!}')]);
    }
    if (config?.address != null) {
      sheet.appendRow([TextCellValue('Address: ${config!.address!}')]);
    }
    if (config?.tpin != null) {
      sheet.appendRow([TextCellValue('TPIN: ${config!.tpin!}')]);
    }
    sheet.appendRow([TextCellValue('Transaction Report - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('Date & Time'),
      TextCellValue('Transaction ID'),
      TextCellValue('Cashier'),
      TextCellValue('Payment Method'),
      TextCellValue('Subtotal ($currency)'),
      TextCellValue('Tax ($currency)'),
      TextCellValue('Total ($currency)'),
    ]);

    for (var tx in transactions) {
      final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
      final subtotal = tx.subtotal.isNaN ? 0.0 : tx.subtotal;
      final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;

      sheet.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(tx.timestamp)),
        TextCellValue(tx.id.toString()),
        TextCellValue(tx.cashierName),
        TextCellValue(tx.paymentMethod.toUpperCase()),
        DoubleCellValue(subtotal),
        DoubleCellValue(tax),
        DoubleCellValue(total),
      ]);

      grandTotal += total;
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        totalCash += total;
      } else if (method.contains('card')) {
        totalCard += total;
      } else if (method.contains('mobile') || method.contains('momo')) {
        totalMomo += total;
      }
    }

    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('FINANCIAL SUMMARY')]);
    sheet.appendRow([TextCellValue('Total Cash'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(totalCash)]);
    sheet.appendRow([TextCellValue('Total Card'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(totalCard)]);
    sheet.appendRow([TextCellValue('Total Mobile Money'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(totalMomo)]);
    sheet.appendRow([TextCellValue('GRAND TOTAL'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(grandTotal)]);

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'transactions_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  // --- Inventory CSV Export ---

  Future<void> exportInventoryToCsv(List<Product> products, {StoreConfig? config}) async {
    List<List<dynamic>> rows = [];
    final currency = config?.currencySymbol ?? 'ZK';

    if (config != null) {
      rows.add(['COMPANY', config.businessName.toUpperCase()]);
      if (config.branchName != null && config.branchName!.isNotEmpty) {
        rows.add(['BRANCH', config.branchName!]);
      }
      if (config.address != null && config.address!.isNotEmpty) {
        rows.add(['ADDRESS', config.address!]);
      }
      if (config.tpin != null && config.tpin!.isNotEmpty) {
        rows.add(['TPIN', config.tpin!]);
      }
      rows.add(['REPORT', 'Inventory Stock Master Report']);
      rows.add(['GENERATED', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())]);
      rows.add([]);
    }

    rows.add([
      'SKU',
      'Product Name',
      'Category ID',
      'Selling Price ($currency)',
      'Cost Price ($currency)',
      'Stock Level',
      'Stock Valuation ($currency)',
      'Status'
    ]);

    for (var p in products) {
      final valuation = p.unitCost * p.stockLevel;
      rows.add([
        p.sku,
        p.name,
        p.categoryId.toString(),
        p.price.toStringAsFixed(2),
        p.unitCost.toStringAsFixed(2),
        p.stockLevel.toString(),
        valuation.toStringAsFixed(2),
        p.isArchived ? 'Archived' : 'Active'
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    await _saveFile(Uint8List.fromList(csvData.codeUnits), 'inventory_${DateTime.now().millisecondsSinceEpoch}.csv', extensions: ['csv']);
  }

  // --- Inventory PDF Export ---

  Future<void> exportInventoryToPdf(List<Product> products, {StoreConfig? config}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'ZK';

    double totalValuation = 0.0;
    int totalItemsInStock = 0;
    for (var p in products) {
      if (!p.isArchived) {
        totalItemsInStock += p.stockLevel;
        totalValuation += (p.unitCost * p.stockLevel);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'Inventory Stock Report',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['SKU', 'Product Name', 'Price ($currency)', 'Cost ($currency)', 'Stock', 'Status'],
            data: products.map((p) => [
              p.sku,
              p.name,
              p.price.toStringAsFixed(2),
              p.unitCost.toStringAsFixed(2),
              p.stockLevel.toString(),
              p.isArchived ? 'Archived' : 'Active'
            ]).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
              fontSize: 9.5,
            ),
            headerDecoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            cellHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.center,
            },
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 250,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: brandColor, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'STOCK VALUATION SUMMARY',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 1, color: brandColor),
                  _buildSummaryRow('Total Product SKUs:', '${products.length}'),
                  _buildSummaryRow('Total Units In Stock:', '$totalItemsInStock'),
                  pw.Divider(thickness: 1),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL VALUATION:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        CurrencyFormatter.format(totalValuation, currency),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}   •   Beleka Pro POS Document Export',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey),
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'inventory_${DateTime.now().millisecondsSinceEpoch}.pdf', extensions: ['pdf']);
  }

  // --- Daily Summary PDF Export ---

  Future<void> exportDailySummaryToPdf({
    required Map<String, double> stats,
    required List<Map<String, dynamic>> topProducts,
    required Map<String, double> paymentDist,
    StoreConfig? config,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'ZK';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildDocumentHeader(
              config,
              title: 'Daily Sales Summary',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.Text(
              'FINANCIAL OVERVIEW',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: [
                  _buildSummaryRow('Total Revenue:', CurrencyFormatter.format(stats['todayRevenue'] ?? 0.0, currency)),
                  _buildSummaryRow('Gross Profit:', CurrencyFormatter.format(stats['todayProfit'] ?? 0.0, currency)),
                  _buildSummaryRow('Transactions Count:', '${(stats['todayCount'] ?? 0).toInt()} sales'),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'TOP SELLING PRODUCTS',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Product Name', 'Quantity Sold'],
              data: topProducts.map((p) => [p['name'], p['quantity'].toString()]).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                fontSize: 9.5,
              ),
              headerDecoration: pw.BoxDecoration(
                color: brandColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              cellHeight: 24,
              cellStyle: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'PAYMENT DISTRIBUTION',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: paymentDist.entries.map((e) {
                  final val = e.value.isNaN ? 0.0 : e.value;
                  return _buildSummaryRow(e.key.toUpperCase(), CurrencyFormatter.format(val, currency));
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'daily_summary_${DateTime.now().millisecondsSinceEpoch}.pdf', extensions: ['pdf']);
  }

  // --- Excel Exports ---

  Future<void> exportInventoryToExcel(List<Product> products, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Inventory'];
    final currency = config?.currencySymbol ?? 'ZK';
    
    sheet.appendRow([TextCellValue(config?.businessName.toUpperCase() ?? 'BELEKA PRO POS')]);
    if (config?.branchName != null) {
      sheet.appendRow([TextCellValue('Branch: ${config!.branchName!}')]);
    }
    if (config?.address != null) {
      sheet.appendRow([TextCellValue('Address: ${config!.address!}')]);
    }
    if (config?.tpin != null) {
      sheet.appendRow([TextCellValue('TPIN: ${config!.tpin!}')]);
    }
    sheet.appendRow([TextCellValue('Inventory Report - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('SKU'),
      TextCellValue('Product Name'),
      TextCellValue('Price ($currency)'),
      TextCellValue('Cost ($currency)'),
      TextCellValue('Stock Level'),
      TextCellValue('Status'),
    ]);

    for (var p in products) {
      sheet.appendRow([
        TextCellValue(p.sku),
        TextCellValue(p.name),
        DoubleCellValue(p.price),
        DoubleCellValue(p.unitCost),
        IntCellValue(p.stockLevel),
        TextCellValue(p.isArchived ? 'Archived' : 'Active'),
      ]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  Future<void> exportDailySummaryToExcel({
    required Map<String, double> stats,
    required List<Map<String, dynamic>> topProducts,
    required Map<String, double> paymentDist,
    StoreConfig? config,
  }) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Daily Summary'];

    sheet.appendRow([TextCellValue(config?.businessName.toUpperCase() ?? 'BELEKA PRO POS')]);
    if (config?.branchName != null) {
      sheet.appendRow([TextCellValue('Branch: ${config!.branchName!}')]);
    }
    if (config?.tpin != null) {
      sheet.appendRow([TextCellValue('TPIN: ${config!.tpin!}')]);
    }
    sheet.appendRow([TextCellValue('Daily Sales Summary - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
    sheet.appendRow([TextCellValue('Total Revenue'), DoubleCellValue(stats['todayRevenue'] ?? 0.0)]);
    sheet.appendRow([TextCellValue('Total Profit'), DoubleCellValue(stats['todayProfit'] ?? 0.0)]);
    sheet.appendRow([TextCellValue('Transaction Count'), IntCellValue(stats['todayCount']?.toInt() ?? 0)]);
    
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Top Products')]);
    sheet.appendRow([TextCellValue('Product'), TextCellValue('Quantity')]);
    for (var p in topProducts) {
      sheet.appendRow([TextCellValue(p['name']), IntCellValue(p['quantity'])]);
    }

    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Payment Methods')]);
    for (var e in paymentDist.entries) {
      sheet.appendRow([TextCellValue(e.key.toUpperCase()), DoubleCellValue(e.value)]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'daily_summary_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  // --- Helper Methods ---

  Future<void> _saveFile(Uint8List bytes, String fileName, {List<String>? extensions}) async {
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Export',
      fileName: fileName,
      type: extensions != null ? FileType.custom : FileType.any,
      allowedExtensions: extensions,
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
    }
  }

  PdfColor _getSectorColor(CategorySector sector) {
    switch (sector) {
      case CategorySector.pharmacy: return PdfColors.cyan;
      case CategorySector.stationery: return PdfColors.purple;
      case CategorySector.grocery: return PdfColors.green;
      case CategorySector.food: return PdfColors.orange;
      case CategorySector.restaurant: return PdfColors.amber;
      case CategorySector.other: return PdfColor.fromInt(0xFFC1F11D);
    }
  }
}
