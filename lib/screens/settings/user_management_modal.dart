import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/users_provider.dart';
import 'package:beleka_pos/screens/settings/add_user_modal.dart';
import 'package:beleka_pos/screens/settings/reset_pin_modal.dart';

class UserManagementModal extends ConsumerWidget {
  const UserManagementModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'STAFF ACCOUNTS',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: const Color(0xFFC1F11D),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white24, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: usersAsync.when(
                data: (users) => _buildStaffList(context, ref, users),
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
                error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.redAccent))),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => const AddUserModal(),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC1F11D),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, color: Colors.black, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'ADD NEW STAFF',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffList(BuildContext context, WidgetRef ref, List<User> users) {
    if (users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text('No staff accounts found.', style: TextStyle(color: Colors.white38)),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return _buildStaffRow(context, ref, user);
        },
      ),
    );
  }

  Widget _buildStaffRow(BuildContext context, WidgetRef ref, User user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFC1F11D).withValues(alpha: 0.1),
            child: Text(
              user.name.isNotEmpty ? user.name[0] : '?', 
              style: const TextStyle(color: Color(0xFFC1F11D), fontWeight: FontWeight.bold)
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${user.role.toUpperCase()} • ID: ${user.numericId}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white24),
            color: const Color(0xFF1A1A1F),
            borderRadius: BorderRadius.circular(12),
            onSelected: (val) {
              if (val == 'edit') {
                showDialog(
                  context: context,
                  builder: (context) => AddUserModal(userToEdit: user),
                );
              } else if (val == 'reset_pin') {
                showDialog(
                  context: context,
                  builder: (context) => ResetPinModal(user: user),
                );
              } else if (val == 'delete') {
                _confirmDelete(context, ref, user);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Staff', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'reset_pin', child: Text('Reset PIN', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'delete', child: Text('Delete Staff', style: TextStyle(color: Colors.redAccent, fontSize: 13))),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text('Delete Staff Account?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to remove ${user.name}? This cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(usersProvider.notifier).deleteUser(user.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
