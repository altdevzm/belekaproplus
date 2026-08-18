import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/export_service.dart';

void main() {
  group('Company Profile, TPIN, and Document Branding Exports Test', () {
    test('StoreConfig holds company branding, logo, TPIN, contacts and document colors', () {
      final config = StoreConfig()
        ..businessName = 'Acme Mega Supermarket'
        ..branchName = 'Northmead Mall'
        ..address = 'Plot 442, Great East Road, Lusaka'
        ..contactNumber = '+260 977 112233'
        ..email = 'finance@acmemega.com'
        ..website = 'www.acmemega.com'
        ..tpin = '1009876543'
        ..taxId = 'VAT-9988'
        ..taxRate = 16.0
        ..currencySymbol = 'ZK'
        ..terminalName = 'POS-CHECKOUT-01'
        ..logoPath = '/path/to/logo.png'
        ..brandColorHex = '#1A73E8';

      expect(config.businessName, equals('Acme Mega Supermarket'));
      expect(config.branchName, equals('Northmead Mall'));
      expect(config.address, equals('Plot 442, Great East Road, Lusaka'));
      expect(config.contactNumber, equals('+260 977 112233'));
      expect(config.email, equals('finance@acmemega.com'));
      expect(config.website, equals('www.acmemega.com'));
      expect(config.tpin, equals('1009876543'));
      expect(config.brandColorHex, equals('#1A73E8'));
    });

    test('ExportService provider instantiates cleanly', () {
      final exportService = ExportService();
      expect(exportService, isNotNull);
    });
  });
}
