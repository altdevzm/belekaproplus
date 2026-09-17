import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/cloud_database_service.dart';
import 'package:beleka_pos/services/backup_service.dart';
import 'package:beleka_pos/screens/auth/backup_restore_modal.dart';
import 'package:intl/intl.dart';

class BackupSettingsModal extends ConsumerStatefulWidget {
  const BackupSettingsModal({super.key});

  @override
  ConsumerState<BackupSettingsModal> createState() => _BackupSettingsModalState();
}

class _BackupSettingsModalState extends ConsumerState<BackupSettingsModal> {
  bool _isBackingUp = false;
  bool _isUploadingCloud = false;
  bool _isDownloadingCloud = false;

  Future<void> _uploadSnapshotToCloud() async {
    final config = ref.read(storeConfigProvider).value;
    final cloudUrl = config?.cloudApiUrl;
    final storeId = config?.cloudStoreId ?? 1;
    final token = config?.cloudAuthToken;

    if (cloudUrl == null || cloudUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud API Server URL is not configured in Store Settings.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploadingCloud = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final backupData = await db.exportBackupData();
      final cloudService = CloudDatabaseService();

      final result = await cloudService.uploadVpsBackup(
        baseUrl: cloudUrl,
        storeId: storeId,
        data: backupData,
        backupName: 'manual_${config?.terminalName ?? "POS"}',
        token: token,
      );

      if (mounted) {
        final records = result?['records_saved'] as Map?;
        final summary = records != null
            ? ' (${records['products'] ?? 0} prods, ${records['users'] ?? 0} staff, ${records['sales'] ?? 0} sales)'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud snapshot successfully saved to VPS server!$summary'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud backup upload failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingCloud = false);
    }
  }

  Future<void> _downloadCloudSnapshot() async {
    final config = ref.read(storeConfigProvider).value;
    final cloudUrl = config?.cloudApiUrl;
    final storeId = config?.cloudStoreId ?? 1;
    final token = config?.cloudAuthToken;

    if (cloudUrl == null || cloudUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud API Server URL is not configured in Store Settings.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isDownloadingCloud = true);
    try {
      final backupService = BackupService();
      final success = await backupService.fetchAndSaveVpsBackup(
        baseUrl: cloudUrl,
        storeId: storeId,
        token: token,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cloud database snapshot downloaded & saved to local backup vault.'),
              backgroundColor: Color(0xFF059669),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to download cloud snapshot.'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud download failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingCloud = false);
    }
  }

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

              // Cloud Snapshot Section
              Text(
                'CLOUD VPS VAULT',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: const Color(0xFF059669),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: _isUploadingCloud ? null : _uploadSnapshotToCloud,
                        icon: _isUploadingCloud 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_upload_rounded, size: 16),
                        label: Text(_isUploadingCloud ? 'UPLOADING...' : 'SAVE TO CLOUD', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: _isDownloadingCloud ? null : _downloadCloudSnapshot,
                        icon: _isDownloadingCloud
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)))
                            : const Icon(Icons.cloud_download_rounded, size: 16, color: Color(0xFF059669)),
                        label: Text(_isDownloadingCloud ? 'PULLING...' : 'PULL FROM VPS', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: const Color(0xFF059669))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF059669)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              Text(
                'LOCAL BACKUP & RESTORE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),

              // Manual Local Backup Button
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: _isBackingUp ? null : _runManualBackup,
                  icon: _isBackingUp 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 16),
                  label: Text(_isBackingUp ? 'SAVING...' : 'RUN LOCAL BACKUP NOW', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const BackupRestoreModal(),
                  ),
                  icon: Icon(Icons.settings_backup_restore_rounded, size: 16, color: primaryColor),
                  label: Text(
                    'RESTORE BACKUP (LOCAL OR CLOUD)', 
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
