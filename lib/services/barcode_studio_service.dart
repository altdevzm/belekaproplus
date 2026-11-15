import 'dart:math';
import 'dart:typed_data';

import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Supported A4 sticker / cut-and-stick sheet grid presets.
class A4LabelPreset {
  final String id;
  final String label;
  final String subtitle;
  final int columns;
  final int rows;

  const A4LabelPreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.columns,
    required this.rows,
  });

  int get labelsPerPage => columns * rows;

  static const List<A4LabelPreset> presets = [
    A4LabelPreset(
      id: '3x7',
      label: '21 / sheet (3 × 7)',
      subtitle: 'Standard Retail • 63.5 × 38.1 mm',
      columns: 3,
      rows: 7,
    ),
    A4LabelPreset(
      id: '3x8',
      label: '24 / sheet (3 × 8)',
      subtitle: 'Medium Sticker • 64 × 33.9 mm',
      columns: 3,
      rows: 8,
    ),
    A4LabelPreset(
      id: '4x10',
      label: '40 / sheet (4 × 10)',
      subtitle: 'Open Items • 52.5 × 29.7 mm',
      columns: 4,
      rows: 10,
    ),
    A4LabelPreset(
      id: '5x13',
      label: '65 / sheet (5 × 13)',
      subtitle: 'Mini Tags • 38.1 × 21.2 mm',
      columns: 5,
      rows: 13,
    ),
    A4LabelPreset(
      id: '2x6',
      label: '12 / sheet (2 × 6)',
      subtitle: 'Large Shelf/Box • 99 × 42 mm',
      columns: 2,
      rows: 6,
    ),
  ];
}

class BarcodeLabelJob {
  final Product product;
  final int copies;

  const BarcodeLabelJob({
    required this.product,
    required this.copies,
  });

  BarcodeLabelJob copyWith({Product? product, int? copies}) {
    return BarcodeLabelJob(
      product: product ?? this.product,
      copies: copies ?? this.copies,
    );
  }
}

class BarcodeStudioQueueNotifier extends StateNotifier<List<BarcodeLabelJob>> {
  BarcodeStudioQueueNotifier() : super(const []);

  void addOrUpdate(Product product, {int copies = 10}) {
    final safeCopies = copies.clamp(1, 500);
    final idx = state.indexWhere((j) => j.product.id == product.id);
    if (idx >= 0) {
      final updated = [...state];
      updated[idx] = BarcodeLabelJob(
        product: product,
        copies: safeCopies,
      );
      state = updated;
    } else {
      state = [...state, BarcodeLabelJob(product: product, copies: safeCopies)];
    }
  }

  void updateCopies(int productId, int copies) {
    if (copies <= 0) {
      remove(productId);
      return;
    }
    state = state
        .map((j) => j.product.id == productId
            ? j.copyWith(copies: copies.clamp(1, 500))
            : j)
        .toList();
  }

  void refreshProduct(Product product) {
    state = state
        .map((j) => j.product.id == product.id ? j.copyWith(product: product) : j)
        .toList();
  }

  void remove(int productId) {
    state = state.where((j) => j.product.id != productId).toList();
  }

  void clear() {
    state = const [];
  }
}

final barcodeStudioQueueProvider =
    StateNotifierProvider<BarcodeStudioQueueNotifier, List<BarcodeLabelJob>>(
  (ref) => BarcodeStudioQueueNotifier(),
);

final barcodeStudioServiceProvider = Provider<BarcodeStudioService>((ref) {
  return BarcodeStudioService(ref.read(isarProvider));
});

class BarcodeStudioService {
  final Isar _isar;
  static final Random _rng = Random();

  BarcodeStudioService(this._isar);

  /// Generates a valid 13-digit GS1 in-store EAN-13 barcode (prefix `299`,
  /// reserved exclusively for internal store items so it never conflicts with
  /// commercial manufacturer barcodes) guaranteed unique against all existing
  /// products in Isar and any optional extra codes in memory.
  Future<String> generateUniqueEan13({Set<String> excludeCodes = const {}}) async {
    final allProducts = await _isar.products.where().findAll();
    final used = <String>{
      ...allProducts.map((p) => p.sku.trim().toLowerCase()),
      ...excludeCodes.map((c) => c.trim().toLowerCase()),
    };

    for (int attempt = 0; attempt < 50; attempt++) {
      final body = StringBuffer('299');
      for (int i = 0; i < 9; i++) {
        body.write(_rng.nextInt(10));
      }
      final base12 = body.toString();
      final candidate = '$base12${_computeEan13CheckDigit(base12)}';
      if (!used.contains(candidate.toLowerCase())) {
        return candidate;
      }
    }
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final tail = ts.substring(ts.length - 9);
    final base12 = '299$tail';
    return '$base12${_computeEan13CheckDigit(base12)}';
  }

  static int _computeEan13CheckDigit(String twelveDigits) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final d = int.parse(twelveDigits[i]);
      sum += (i % 2 == 0) ? d : d * 3;
    }
    final mod = sum % 10;
    return mod == 0 ? 0 : 10 - mod;
  }

  static bool isValidEan13(String code) {
    if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
    final expected = _computeEan13CheckDigit(code.substring(0, 12));
    return int.parse(code[12]) == expected;
  }

  /// Builds a multi-page A4 PDF sheet containing all queued labels.
  Future<Uint8List> buildA4LabelSheetPdf({
    required List<BarcodeLabelJob> jobs,
    required A4LabelPreset preset,
    required String currencySymbol,
    String? storeName,
    bool showPrice = true,
    bool showStoreName = true,
    bool showCutGuides = true,
  }) async {
    final doc = pw.Document(
      title: 'Beleka POS - Barcode Studio A4 Sheet',
      author: storeName ?? 'Beleka POS',
    );

    final expanded = <Product>[];
    for (final job in jobs) {
      final sku = job.product.sku.trim();
      if (sku.isEmpty) continue;
      for (int i = 0; i < job.copies; i++) {
        expanded.add(job.product);
      }
    }

    if (expanded.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Text(
              'Add products to Barcode Studio to generate your A4 label sheet.',
              style: const pw.TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
      return doc.save();
    }

    final perPage = preset.labelsPerPage;
    final totalPages = (expanded.length / perPage).ceil();
    const marginPt = 8.0 * PdfPageFormat.mm;
    final usableWidth = PdfPageFormat.a4.width - (marginPt * 2);
    final usableHeight = PdfPageFormat.a4.height - (marginPt * 2);
    final cellW = usableWidth / preset.columns;
    final cellH = usableHeight / preset.rows;

    for (int pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final start = pageIdx * perPage;
      final end = min(start + perPage, expanded.length);
      final pageItems = expanded.sublist(start, end);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(marginPt),
          build: (context) {
            return pw.Column(
              children: List.generate(preset.rows, (r) {
                return pw.Row(
                  children: List.generate(preset.columns, (c) {
                    final idx = r * preset.columns + c;
                    if (idx >= pageItems.length) {
                      return pw.SizedBox(width: cellW, height: cellH);
                    }
                    final product = pageItems[idx];
                    return _buildLabelCell(
                      product: product,
                      width: cellW,
                      height: cellH,
                      preset: preset,
                      currencySymbol: currencySymbol,
                      storeName: storeName,
                      showPrice: showPrice,
                      showStoreName: showStoreName,
                      showCutGuides: showCutGuides,
                    );
                  }),
                );
              }),
            );
          },
        ),
      );
    }

    return doc.save();
  }

  pw.Widget _buildLabelCell({
    required Product product,
    required double width,
    required double height,
    required A4LabelPreset preset,
    required String currencySymbol,
    required String? storeName,
    required bool showPrice,
    required bool showStoreName,
    required bool showCutGuides,
  }) {
    final code = product.sku.trim();
    final useEan13 = isValidEan13(code);
    final barcodeType = useEan13 ? pw.Barcode.ean13() : pw.Barcode.code128();
    final isDense = preset.columns >= 5;
    final storeFontSize = isDense ? 4.8 : (preset.columns == 4 ? 5.4 : 6.0);
    final nameFontSize = isDense ? 6.4 : (preset.columns == 4 ? 7.2 : 8.2);
    final priceFontSize = isDense ? 7.2 : (preset.columns == 4 ? 8.4 : 9.6);
    final quietZoneH = isDense ? 6.0 : 10.0;
    final barcodeHeight = (height * (isDense ? 0.40 : 0.44)).clamp(18.0, 44.0);

    return pw.Container(
      width: width,
      height: height,
      padding: pw.EdgeInsets.symmetric(
        horizontal: isDense ? 3.5 : 6,
        vertical: isDense ? 3 : 5,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: showCutGuides
            ? pw.Border.all(
                color: PdfColors.grey400,
                width: 0.45,
                style: pw.BorderStyle.dashed,
              )
            : null,
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Top header: Store Name + Price (or centered Store Name)
          if ((showStoreName &&
                  storeName != null &&
                  storeName.trim().isNotEmpty) ||
              showPrice)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (showStoreName &&
                    storeName != null &&
                    storeName.trim().isNotEmpty)
                  pw.Expanded(
                    child: pw.Text(
                      storeName.trim().toUpperCase(),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        fontSize: storeFontSize,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  )
                else
                  pw.Spacer(),
                if (showPrice)
                  pw.Container(
                    padding: pw.EdgeInsets.symmetric(
                      horizontal: isDense ? 3 : 5,
                      vertical: isDense ? 1 : 1.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(2.5),
                    ),
                    child: pw.Text(
                      '$currencySymbol ${product.price.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: priceFontSize,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ),
              ],
            ),

          // Product Title
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Text(
              product.name,
              maxLines: isDense ? 1 : 2,
              overflow: pw.TextOverflow.clip,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: nameFontSize,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),

          // Crisp vector barcode with clean quiet zones for 100% scanner accuracy
          pw.Expanded(
            child: pw.Container(
              width: double.infinity,
              padding: pw.EdgeInsets.symmetric(horizontal: quietZoneH),
              alignment: pw.Alignment.center,
              child: pw.BarcodeWidget(
                barcode: barcodeType,
                data: code,
                width: width - (quietZoneH * 2) - 8,
                height: barcodeHeight,
                drawText: true,
                textPadding: 2,
                textStyle: pw.TextStyle(
                  fontSize: isDense ? 5.6 : 6.8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> printA4Sheet({
    required Uint8List pdfBytes,
    String jobName = 'Beleka_Barcode_Labels_A4',
  }) async {
    await Printing.layoutPdf(
      name: jobName,
      format: PdfPageFormat.a4,
      onLayout: (_) async => pdfBytes,
    );
  }

  Future<void> shareOrSaveA4Pdf({
    required Uint8List pdfBytes,
    String filename = 'Beleka_Barcode_Labels_A4.pdf',
  }) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }
}

