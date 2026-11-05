import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/services/local_sql_service.dart';

void main() {
  test('initializes the database and persists a stock movement', () async {
    final directory = await Directory.systemTemp.createTemp(
      'beleka-local-sql-',
    );
    final service = await LocalSqlService.init(customDirectory: directory);

    try {
      await service.insert('stock_movements', {
        'product_id': 1,
        'product_name': 'Test item',
        'sku': 'TEST-1',
        'movement_type': '06',
        'action_type': 'ADD',
        'previous_stock': 8,
        'quantity_changed': 50,
        'new_stock': 58,
        'reason_category': 'Adjustment',
        'timestamp': DateTime.now().toIso8601String(),
      });

      final movements = await service.query(
        'SELECT * FROM stock_movements WHERE product_id = ?',
        [1],
      );

      expect(movements, hasLength(1));
      expect(movements.single['new_stock'], 58);
    } finally {
      await service.close();
      await directory.delete(recursive: true);
    }
  });
}
