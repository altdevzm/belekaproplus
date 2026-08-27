import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:isar/isar.dart';

/// Notifier to manage authentication state.
class AuthNotifier extends Notifier<User?> {
  @override
  User? build() => null;

  void login(User user) {
    state = user;
  }

  Future<void> logout(WidgetRef ref) async {
    // 1. Try to trigger automatic backup if configured
    try {
      final db = ref.read(databaseServiceProvider);
      final config = await db.isar.storeConfigs.where().findFirst();
      
      if (config != null && config.backupPath != null) {
        await db.backupDatabase(config.backupPath!);
      }
    } catch (e) {
      // Fail silently for backup to ensure user can always log out
    }

    // 2. Clear state
    state = null;
  }
}

/// Provider to track the currently logged-in User.
final authProvider = NotifierProvider<AuthNotifier, User?>(AuthNotifier.new);

/// Convenient provider to check if Corporate Owner / HQ Admin is logged in.
final isOwnerProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return false;
  final role = user.role.toLowerCase().trim();
  return role == 'owner' || role == 'admin' || role == 'super_admin';
});

/// Convenient provider to check if a Headquarters Super Admin is logged in.
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(isOwnerProvider);
});

/// Convenient provider to check if a restricted Branch Manager is logged in.
final isBranchManagerProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return false;
  final role = user.role.toLowerCase().trim();
  return role == 'branch_manager' || role == 'manager';
});

/// Convenient provider to check if any Manager or Owner is logged in.
final isManagerProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return false;
  final role = user.role.toLowerCase().trim();
  return role == 'owner' || role == 'admin' || role == 'super_admin' || role == 'manager' || role == 'branch_manager';
});

/// Convenient provider to check if a Cashier is logged in.
final isCashierProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.role == 'cashier';
});

/// Real-time stream provider to retrieve all active users in the system.
final allUsersProvider = StreamProvider<List<User>>((ref) async* {
  final db = ref.watch(databaseServiceProvider);
  yield await db.isar.users.where().findAll();
  await for (final _ in db.isar.users.watchLazy()) {
    yield await db.isar.users.where().findAll();
  }
});
