import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/screens/shell_screen.dart';
import 'package:beleka_pos/services/database_service.dart';

void main() {
  group('role and shift integrity', () {
    test('normalizes user roles for cashier routing and access checks', () {
      expect(normalizeUserRole('Cashier'), equals('cashier'));
      expect(normalizeUserRole('OWNER'), equals('owner'));
      expect(normalizeUserRole('Branch_Manager'), equals('branch_manager'));
      expect(normalizeUserRole(null), equals(''));
    });

    test('keeps cashier navigation out of management screens', () {
      expect(
        screenAllowedForRole(ScreenType.dashboard, 'cashier'),
        equals(ScreenType.sales),
      );
      expect(
        screenAllowedForRole(ScreenType.reports, 'Cashier'),
        equals(ScreenType.sales),
      );
      expect(
        screenAllowedForRole(ScreenType.settings, 'cashier'),
        equals(ScreenType.settings),
      );
      expect(
        screenAllowedForRole(ScreenType.dashboard, 'owner'),
        equals(ScreenType.dashboard),
      );
    });

    test('finds the correct open shift for the current terminal only', () {
      final shiftOnTill1 = CashShift()
        ..shiftNumber = 'SHIFT-01'
        ..cashierName = 'Cashier A'
        ..terminalId = 'TILL-01 - Counter 1'
        ..status = 'OPEN';

      final shiftOnTill2 = CashShift()
        ..shiftNumber = 'SHIFT-02'
        ..cashierName = 'Cashier B'
        ..terminalId = 'TILL-02 - Counter 2'
        ..status = 'OPEN';

      expect(
        findOpenShiftForTerminal([
          shiftOnTill1,
          shiftOnTill2,
        ], 'TILL-01 - Counter 1'),
        isNotNull,
      );
      expect(
        findOpenShiftForTerminal([
          shiftOnTill1,
          shiftOnTill2,
        ], 'TILL-02 - Counter 2')?.cashierName,
        equals('Cashier B'),
      );
      expect(
        findOpenShiftForTerminal([
          shiftOnTill1,
          shiftOnTill2,
        ], 'TILL-03 - Counter 3'),
        isNull,
      );
      expect(
        findOpenShiftForTerminal([shiftOnTill1, shiftOnTill2], 'TILL-1'),
        isNull,
      );
    });
  });
}
