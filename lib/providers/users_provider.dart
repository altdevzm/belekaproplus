import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';

final usersProvider = AsyncNotifierProvider<UsersNotifier, List<User>>(UsersNotifier.new);

class UsersNotifier extends AsyncNotifier<List<User>> {
  @override
  Future<List<User>> build() async {
    final db = ref.watch(databaseServiceProvider);
    return await db.getAllUsers();
  }

  Future<void> saveUser(User user) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(databaseServiceProvider);
      await db.saveUser(user);
      return await db.getAllUsers();
    });
  }

  Future<void> deleteUser(Id id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(databaseServiceProvider);
      await db.deleteUser(id);
      return await db.getAllUsers();
    });
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(databaseServiceProvider);
      return await db.getAllUsers();
    });
  }
}
