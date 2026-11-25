import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/data/digitax_classifications.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/widgets/digitax_classification_picker_dialog.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('Official DigiTax classification dataset counts match documentation', () {
    expect(DigitaxClassifications.productionCodes.length, 1011);
    expect(DigitaxClassifications.sandboxCodes.length, 11);
    expect(DigitaxClassifications.quickPicks.length, 8);

    // Every sandbox code must be present in productionCodes and marked isSandbox
    for (final sb in DigitaxClassifications.sandboxCodes) {
      final found = DigitaxClassifications.findByCode(sb.code);
      expect(found, isNotNull);
      expect(found!.isSandbox, isTrue);
    }

    // Specific Production & VAT Act codes look up cleanly
    expect(
      DigitaxClassifications.findByCode('50221300')?.name,
      'Flour and milled products',
    );
    expect(
      DigitaxClassifications.findByCode('99011021')?.name,
      'Unprocessed milk',
    );
  });

  test('resolveCompliantItemClassCode preserves official Production codes', () {
    expect(
      DigiTaxInventoryService.resolveCompliantItemClassCode(
        explicitClsCode: '50221300',
        zraTaxCode: 'B',
        productName: 'Roller Meal',
      ),
      '50221300',
    );
    // Preserves official Production codes even if previously blocked segment
    expect(
      DigiTaxInventoryService.resolveCompliantItemClassCode(
        explicitClsCode: '53100000',
        zraTaxCode: 'A',
        productName: 'Polo Shirt',
      ),
      '53100000',
    );
    // Rejects unknown legacy 43211500 placeholder
    expect(
      DigiTaxInventoryService.resolveCompliantItemClassCode(
        explicitClsCode: '43211500',
        zraTaxCode: 'A',
        productName: 'USB Cable',
      ),
      '52151501',
    );
  });

  testWidgets('Live mode picker shows Live codes only and hides Sandbox UI', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await DigitaxClassificationPickerDialog.show(
                  context,
                  initialCode: '52151501',
                  isSandboxEnvironment: false,
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(find.text('All Live (1011)'), findsOneWidget);
    expect(find.text('Sandbox TEST (11)'), findsNothing);
    expect(find.text('SANDBOX OK'), findsNothing);

    // Search by keyword across the 1,011 Live codes
    await tester.enterText(find.byType(TextField).first, 'Flour and milled');
    await tester.pumpAndSettle();

    expect(find.text('Flour and milled products'), findsOneWidget);
    expect(find.text('50221300'), findsOneWidget);

    await tester.tap(find.text('Flour and milled products'));
    await tester.pumpAndSettle();

    expect(result, '50221300');
  });

  testWidgets('Sandbox mode picker defaults to 11 Sandbox TEST codes', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await DigitaxClassificationPickerDialog.show(
                  context,
                  initialCode: '56101530',
                  isSandboxEnvironment: true,
                );
              },
              child: const Text('Open Sandbox Picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sandbox Picker'));
    await tester.pumpAndSettle();

    expect(find.text('Sandbox TEST (11)'), findsOneWidget);
    expect(find.text('All Production (1011)'), findsOneWidget);
    expect(find.text('Showing 11 codes'), findsOneWidget);

    await tester.tap(find.text('Storage cabinets'));
    await tester.pumpAndSettle();

    expect(result, '56101530');
  });
}
