import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

final usersProvider = AsyncNotifierProvider<UsersNotifier, List<User>>(UsersNotifier.new);

class UsersNotifier extends AsyncNotifier<List<User>> {
  Future<List<User>> _fetchFilteredUsers() async {
    final db = ref.read(databaseServiceProvider);
    final currentUser = ref.read(authProvider);
    final isOwner = ref.read(isOwnerProvider);
    final allUsers = await db.getAllUsers();

    if (isOwner || currentUser == null) {
      return allUsers;
    }

    final mgrBranchCode = currentUser.branchCode?.trim();
    final mgrBranchName = currentUser.branchName?.trim();

    return allUsers.where((u) {
      // Branch Managers cannot see the Owner or Admin users
      final role = u.role.toLowerCase().trim();
      if (role == 'owner' || role == 'admin' || role == 'super_admin') return false;

      // Match by branch code or branch name
      if (mgrBranchCode != null && mgrBranchCode.isNotEmpty && mgrBranchCode != '00') {
        if (u.branchCode == mgrBranchCode) return true;
      }
      if (mgrBranchName != null && mgrBranchName.isNotEmpty) {
        if (u.branchName == mgrBranchName) return true;
      }

      // Show current user (self)
      if (u.numericId == currentUser.numericId) return true;

      return false;
    }).toList();
  }

  @override
  Future<List<User>> build() async {
    return await _fetchFilteredUsers();
  }

  Future<void> saveUser(User user) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(databaseServiceProvider);
      await db.saveUser(user);
      return await _fetchFilteredUsers();
    });
  }

  Future<void> deleteUser(Id id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(databaseServiceProvider);
      await db.deleteUser(id);
      return await _fetchFilteredUsers();
    });
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return await _fetchFilteredUsers();
    });
  }
}
