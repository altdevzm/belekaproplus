import 'package:isar/isar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';

final storeConfigProvider = StreamProvider<StoreConfig?>((ref) async* {
  final db = ref.watch(databaseServiceProvider);
  yield await db.isar.storeConfigs.where().findFirst();
  await for (final _ in db.isar.storeConfigs.watchLazy()) {
    yield await db.isar.storeConfigs.where().findFirst();
  }
});

final categoriesProvider = StreamProvider<List<Category>>((ref) async* {
  final db = ref.watch(databaseServiceProvider);
  yield await db.isar.categorys.where().findAll();
  await for (final _ in db.isar.categorys.watchLazy()) {
    yield await db.isar.categorys.where().findAll();
  }
});
