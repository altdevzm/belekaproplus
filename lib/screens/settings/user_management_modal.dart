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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final usersAsync = ref.watch(usersProvider);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.people_rounded, color: primaryColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'STAFF ACCOUNTS & PERMISSIONS',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: usersAsync.when(
                data: (users) => _buildStaffList(context, ref, users),
                loading: () => Center(child: CircularProgressIndicator(color: primaryColor)),
                error: (e, s) => Center(child: Text('Error loading staff: $e', style: const TextStyle(color: Color(0xFFDC2626)))),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => const AddUserModal(),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'ADD NEW STAFF ACCOUNT',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffList(BuildContext context, WidgetRef ref, List<User> users) {
    final theme = Theme.of(context);
    if (users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text('No staff accounts found.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isDark ? primaryColor.withValues(alpha: 0.2) : primaryColor.withValues(alpha: 0.1),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', 
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)
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
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.role.toUpperCase()} • ID: ${user.numericId}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurfaceVariant),
            color: isDark ? const Color(0xFF151F32) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            ),
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
              PopupMenuItem(value: 'edit', child: Text('Edit Staff Details', style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13))),
              PopupMenuItem(value: 'reset_pin', child: Text('Reset PIN Code', style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13))),
              PopupMenuItem(value: 'delete', child: Text('Delete Staff Account', style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600))),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, User user) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        title: Text('Delete Staff Account?', style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to remove ${user.name}? This action cannot be undone.', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(usersProvider.notifier).deleteUser(user.id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }
}
