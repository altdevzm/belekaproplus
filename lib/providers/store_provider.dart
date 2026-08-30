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

final storeBranchesProvider = StreamProvider<List<StoreBranch>>((ref) async* {
  final db = ref.watch(databaseServiceProvider);

  Future<List<StoreBranch>> loadWithLiveSales() async {
    final branches = await db.isar.storeBranchs.where().sortByCode().findAll();
    for (final b in branches) {
      final liveSales = await db.getTodaySalesForBranch(b.code, branchBhfId: b.bhfId, branchName: b.name);
      b.salesToday = liveSales;
    }
    return branches;
  }

  yield await loadWithLiveSales();

  // Watch both storeBranchs collection and saleTransactions collection for real-time updates
  await for (final _ in db.isar.storeBranchs.watchLazy()) {
    yield await loadWithLiveSales();
  }
});

final posTerminalsProvider = StreamProvider<List<PosTerminal>>((ref) async* {
  final db = ref.watch(databaseServiceProvider);

  Future<List<PosTerminal>> loadWithLiveSales() async {
    final terminals = await db.isar.posTerminals.where().sortByTerminalCode().findAll();
    for (final t in terminals) {
      final liveSales = await db.getTodaySalesForTerminal(t.terminalCode, terminalName: t.name, cashierId: t.assignedCashierId);
      t.salesToday = liveSales;
    }
    return terminals;
  }

  yield await loadWithLiveSales();

  await for (final _ in db.isar.posTerminals.watchLazy()) {
    yield await loadWithLiveSales();
  }
});
