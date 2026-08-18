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

/// Convenient provider to check if an Admin is logged in.
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.role == 'admin';
});

/// Convenient provider to check if a Manager or Admin is logged in.
final isManagerProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.role == 'manager' || user?.role == 'admin';
});

/// Convenient provider to check if a Cashier is logged in.
final isCashierProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.role == 'cashier';
});
