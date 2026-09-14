import 'package:isar/isar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

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
    final config = await db.isar.storeConfigs.where().findFirst();
    final cloudUrl = config?.cloudApiUrl?.trim();
    final token = config?.cloudAuthToken?.trim();
    List<Map<String, dynamic>> cloudStores = [];
    if (cloudUrl != null && cloudUrl.isNotEmpty && token != null && token.isNotEmpty) {
      try {
        cloudStores = await ref.read(cloudDatabaseServiceProvider).getStores(
          cloudUrl,
          authToken: token,
        );
      } catch (_) {}
    }
    for (final b in branches) {
      final bhfId = b.bhfId.trim().padLeft(2, '0');
      final cloudStore = cloudStores.where(
        (store) => store['bhf_id']?.toString().trim().padLeft(2, '0') == bhfId,
      ).firstOrNull;
        final rawCloudStoreId = cloudStore?['id'];
        final parsedCloudStoreId = rawCloudStoreId is num
          ? rawCloudStoreId.toInt()
          : int.tryParse(rawCloudStoreId?.toString() ?? '') ?? 0;
          final cloudStoreId = parsedCloudStoreId > 0
            ? parsedCloudStoreId
            : b.cloudStoreId;
      if (cloudStoreId > 0 && cloudUrl != null && token != null) {
        try {
          final backup = await ref.read(cloudDatabaseServiceProvider).downloadVpsBackup(
            baseUrl: cloudUrl,
            storeId: cloudStoreId,
            token: token,
          );
          final now = DateTime.now();
          final start = DateTime(now.year, now.month, now.day);
          final sales = (backup?['sales'] as List? ?? const []).where((raw) {
            final value = raw['timestamp'] ?? raw['created_at'];
            final timestamp = DateTime.tryParse(value?.toString() ?? '');
            return timestamp != null && !timestamp.isBefore(start);
          });
          b.salesToday = sales.fold<double>(0.0, (sum, raw) {
            final amount = raw['total_amount'];
            final numeric = amount is num ? amount : num.tryParse(amount?.toString() ?? '');
            return sum + (numeric?.toDouble() ?? 0.0);
          });
          if (b.cloudStoreId != cloudStoreId) {
            b.cloudStoreId = cloudStoreId;
            await db.isar.writeTxn(() async => db.isar.storeBranchs.put(b));
          }
          continue;
        } catch (_) {}
      }
      b.salesToday = await db.getTodaySalesForBranch(
        b.code,
        branchBhfId: b.bhfId,
        branchName: b.name,
        branchCloudStoreId: cloudStoreId > 0 ? cloudStoreId : null,
      );
    }
    return branches;
  }

  yield await loadWithLiveSales();

  // Refresh independently of local branch writes so HQ cards reflect sales
  // recorded on a remote branch without requiring navigation or restart.
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 15));
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
