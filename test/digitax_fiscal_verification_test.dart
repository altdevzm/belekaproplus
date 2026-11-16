import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/printer_service.dart';

void main() {
  group('Real-time DigiTax Fiscal Verification Source of Truth', () {
    test('confirmed DigiTax Sale response passes both official & printer checks', () {
      final tx = SaleTransaction(
        totalAmount: 150.0,
        paymentMethod: 'CASH',
        zraSdcId: 'SDC0010002492',
        zraReceiptNumber: 'INV0010002492/38',
        zraMarkId: '3JYZVPTPMYBGHG4A',
        zraInternalData: 'PB3ZSZP3RZR3AUPYBYLUTFJDIA',
        zraQrCode:
            'https://portal.zra.org.zm/common/link/ebm/receipt/indexEbmReceiptData?Data=2002720806000YXO7XG3HRQ7OOWDH',
        zraStatus: 'APPROVED',
        digitaxSaleId: 'sale_01HC3HTDAXQ50E07CWR2A2CFBD',
      );

      final printer = PrinterService();
      expect(DigiTaxInventoryService.isOfficiallyFiscalised(tx), isTrue);
      expect(printer.isFiscalApproved(tx), isTrue);
      expect(
        DigiTaxInventoryService.friendlyFiscalStateLabel(tx),
        equals('APPROVED'),
      );
    });

    test('SUBMITTED_TO_DIGITAX / PENDING / VERIFICATION_REQUIRED never count as fiscalised even with sale_ ID', () {
      final printer = PrinterService();

      for (final state in [
        'PENDING',
        'PENDING_SUBMISSION',
        'SUBMITTED_TO_DIGITAX',
        'VERIFICATION_REQUIRED',
        'RECONCILIATION_REQUIRED',
      ]) {
        final tx = SaleTransaction(
          totalAmount: 50.0,
          paymentMethod: 'CASH',
          zraMarkId: 'sale_01HC3HTDAXQ50E07CWR2A2CFBD',
          zraReceiptNumber: 'PENDING',
          zraQrCode:
              'https://smartinvoice.zra.org.zm/verify?tpin=2004189376&sdc=2004189376001&rcpt=PENDING',
          zraStatus: state,
        );

        expect(
          DigiTaxInventoryService.isOfficiallyFiscalised(tx),
          isFalse,
          reason: '$state must never be treated as officially fiscalised',
        );
        expect(
          printer.isFiscalApproved(tx),
          isFalse,
          reason: '$state must never print as ZRA fiscalised receipt',
        );
      }
    });

    test('fabricated QR or placeholder CONFIRMED signature cannot spoof fiscalisation', () {
      final printer = PrinterService();

      final fabricatedQrTx = SaleTransaction(
        totalAmount: 25.0,
        paymentMethod: 'CASH',
        zraReceiptNumber: 'INV1/12',
        zraMarkId: '3JYZVPTPMYBGHG4A',
        zraQrCode:
            'https://smartinvoice.zra.org.zm/verify?tpin=2004189376&sdc=2004189376001&rcpt=INV1/12',
        zraStatus: 'APPROVED',
      );
      expect(
        DigiTaxInventoryService.isOfficiallyFiscalised(fabricatedQrTx),
        isFalse,
      );
      expect(printer.isFiscalApproved(fabricatedQrTx), isFalse);

      final placeholderSigTx = SaleTransaction(
        totalAmount: 25.0,
        paymentMethod: 'CASH',
        zraReceiptNumber: 'INV1/12',
        zraMarkId: 'CONFIRMED',
        zraQrCode:
            'https://sandboxportal.zra.org.zm/common/link/ebm/receipt/indexEbmReceiptData?Data=ABC',
        zraStatus: 'APPROVED',
      );
      expect(
        DigiTaxInventoryService.isOfficiallyFiscalised(placeholderSigTx),
        isFalse,
      );
      expect(printer.isFiscalApproved(placeholderSigTx), isFalse);
    });

    test('REJECTED and FAILED transactions map to explicit non-fiscal states', () {
      final printer = PrinterService();

      final rejectedTx = SaleTransaction(
        totalAmount: 100.0,
        paymentMethod: 'CASH',
        zraStatus: 'REJECTED: Invalid item classification',
      );
      expect(DigiTaxInventoryService.isOfficiallyFiscalised(rejectedTx), isFalse);
      expect(printer.isFiscalApproved(rejectedTx), isFalse);
      expect(
        DigiTaxInventoryService.friendlyFiscalStateLabel(rejectedTx),
        equals('REJECTED'),
      );

      final authFailedTx = SaleTransaction(
        totalAmount: 100.0,
        paymentMethod: 'CASH',
        zraStatus: 'FAILED: Authentication failed (HTTP 401)',
      );
      expect(
        DigiTaxInventoryService.isOfficiallyFiscalised(authFailedTx),
        isFalse,
      );
      expect(printer.isFiscalApproved(authFailedTx), isFalse);
      expect(
        DigiTaxInventoryService.friendlyFiscalStateLabel(authFailedTx),
        equals('FAILED'),
      );
    });

    test('LOCAL_EXEMPT transactions are cleanly distinguished from ZRA fiscalised', () {
      final printer = PrinterService();
      final localTx = SaleTransaction(
        totalAmount: 40.0,
        paymentMethod: 'CASH',
        zraStatus: 'LOCAL_EXEMPT',
      );
      expect(DigiTaxInventoryService.isOfficiallyFiscalised(localTx), isFalse);
      expect(DigiTaxInventoryService.isLocalExempt(localTx), isTrue);
      expect(printer.isFiscalApproved(localTx), isFalse);
      expect(
        DigiTaxInventoryService.friendlyFiscalStateLabel(localTx),
        equals('LOCAL_EXEMPT'),
      );
    });
  });
}

