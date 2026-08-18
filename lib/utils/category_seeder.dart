import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';

class CategorySeeder {
  static const List<String> defaultCategories = [
    'GENERAL',
    'PHARMACY',
    'STATIONERY',
    'GROCERIES',
    'FOOD',
    'RESTAURANT',
    'ELECTRONICS',
    'CLOTHING',
  ];

  static Future<void> seed(DatabaseService db) async {
    final existingCount = await db.isar.categorys.count();
    if (existingCount > 0) return;

    final categories = defaultCategories.map((name) => Category(name: name)).toList();
    await db.isar.writeTxn(() async {
      await db.isar.categorys.putAll(categories);
    });
  }
}
