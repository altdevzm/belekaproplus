import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils.dart';

void main() {
  group('Thermal Paper Size Presets Verification', () {
    test('All 5 standard and specialized thermal sizes are defined with accurate metrics', () {
      expect(ThermalPaperPreset.presets.length, equals(5));

      // 1. 58mm Preset (Small POS, kiosks, mobile)
      final p58 = ThermalPaperPreset.fromWidth(58);
      expect(p58.widthMm, equals(58));
      expect(p58.columnCount, equals(32));
      expect(p58.logoPixelWidth, equals(240));
      expect(p58.escPosSize, equals(PaperSize.mm58));
      expect(p58.singleDivider.length, equals(32));

      // 2. 76mm Preset (Older/business POS)
      final p76 = ThermalPaperPreset.fromWidth(76);
      expect(p76.widthMm, equals(76));
      expect(p76.columnCount, equals(40));
      expect(p76.logoPixelWidth, equals(300));
      expect(p76.escPosSize, equals(PaperSize.mm80));
      expect(p76.singleDivider.length, equals(40));

      // 3. 80mm Preset (Standard retail POS)
      final p80 = ThermalPaperPreset.fromWidth(80);
      expect(p80.widthMm, equals(80));
      expect(p80.columnCount, equals(48));
      expect(p80.logoPixelWidth, equals(384));
      expect(p80.escPosSize, equals(PaperSize.mm80));
      expect(p80.singleDivider.length, equals(48));

      // 4. 110mm Preset (Specialized thermal printing)
      final p110 = ThermalPaperPreset.fromWidth(110);
      expect(p110.widthMm, equals(110));
      expect(p110.columnCount, equals(64));
      expect(p110.logoPixelWidth, equals(512));
      expect(p110.escPosSize, equals(PaperSize.mm80));
      expect(p110.singleDivider.length, equals(64));

      // 5. 112mm Preset (Larger receipts / labels)
      final p112 = ThermalPaperPreset.fromWidth(112);
      expect(p112.widthMm, equals(112));
      expect(p112.columnCount, equals(68));
      expect(p112.logoPixelWidth, equals(540));
      expect(p112.escPosSize, equals(PaperSize.mm80));
      expect(p112.singleDivider.length, equals(68));
    });

    test('Fallback to 80mm when an unknown paper width is provided', () {
      final fallback = ThermalPaperPreset.fromWidth(999);
      expect(fallback.widthMm, equals(80));
      expect(fallback.columnCount, equals(48));
    });
  });
}
