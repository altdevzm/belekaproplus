import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/screens/auth/backup_restore_modal.dart';
import 'package:intl/intl.dart';

class BackupSettingsModal extends ConsumerStatefulWidget {
  const BackupSettingsModal({super.key});

  @override
  ConsumerState<BackupSettingsModal> createState() => _BackupSettingsModalState();
}

class _BackupSettingsModalState extends ConsumerState<BackupSettingsModal> {
  bool _isBackingUp = false;

  Future<void> _pickBackupPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      if (selectedDirectory != null) {
        final db = ref.read(databaseServiceProvider);
        final config = ref.read(storeConfigProvider).value;
        
        if (config != null) {
          config.backupPath = selectedDirectory;
          await db.saveStoreConfig(config);
          // Refresh the provider
          ref.invalidate(storeConfigProvider);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Backup location updated successfully')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting folder: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _runManualBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final config = ref.read(storeConfigProvider).value;
      
      String targetPath = config?.backupPath ?? '';
      if (targetPath.trim().isEmpty) {
        if (Platform.isAndroid) {
          try {
            final dlDir = Directory('/storage/emulated/0/Download/BelekaPOS_Backups');
            if (!await dlDir.exists()) await dlDir.create(recursive: true);
            targetPath = dlDir.path;
          } catch (_) {
            final ext = await getExternalStorageDirectory();
            targetPath = ext != null ? '${ext.path}/BelekaPOS_Backups' : (await getApplicationDocumentsDirectory()).path;
          }
        } else {
          final docs = await getApplicationDocumentsDirectory();
          targetPath = '${docs.path}/BelekaPOS_Backups';
        }

        if (config != null) {
          config.backupPath = targetPath;
          await db.saveStoreConfig(config);
        }
      }

      final backupFilePath = await db.backupDatabase(targetPath);
      ref.invalidate(storeConfigProvider);

      if (mounted) {
        if (backupFilePath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Database backup completed successfully:\n$backupFilePath'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup failed to save to directory'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final config = ref.watch(storeConfigProvider).value;
    final lastBackup = config?.lastBackupDate != null 
        ? DateFormat('dd MMM yyyy, HH:mm').format(config!.lastBackupDate!)
        : 'Never';

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.security_rounded, color: primaryColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Database Backup & Restore',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

              // Backup Path Section
              Text(
                'AUTO-BACKUP LOCATION',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_open_rounded, color: theme.colorScheme.onSurfaceVariant, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (config?.backupPath != null && config!.backupPath!.isNotEmpty)
                                ? config.backupPath!
                                : (Platform.isAndroid ? 'Default (Downloads/BelekaPOS_Backups)' : 'Default (Documents/BelekaPOS_Backups)'),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: _pickBackupPath,
                          child: Text('Change', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: primaryColor)),
                        ),
                      ],
                    ),
                    if (config?.backupPath == null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Automated backups are triggered on logout and shutdown. Select an external drive for maximum security.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706)),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Stats Section
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(context, 'Last Backup', lastBackup, Icons.history_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatTile(context, 'Backup Type', 'Full Snapshot', Icons.data_usage_rounded),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Manual Backup Button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isBackingUp ? null : _runManualBackup,
                  icon: _isBackingUp 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(_isBackingUp ? 'BACKING UP...' : 'RUN MANUAL BACKUP NOW', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const BackupRestoreModal(),
                  ),
                  icon: Icon(Icons.settings_backup_restore_rounded, size: 16, color: primaryColor),
                  label: Text(
                    'RESTORE SYSTEM BACKUP', 
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: primaryColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
