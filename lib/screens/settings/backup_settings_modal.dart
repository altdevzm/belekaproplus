import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
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
    final config = ref.read(storeConfigProvider).value;
    if (config?.backupPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a backup location first'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isBackingUp = true);
    try {
      final db = ref.read(databaseServiceProvider);
      await db.backupDatabase(config!.backupPath!);
      
      // backupDatabase already updates lastBackupDate internally
      ref.invalidate(storeConfigProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database backup completed successfully'), backgroundColor: Colors.green),
        );
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
    final config = ref.watch(storeConfigProvider).value;
    final lastBackup = config?.lastBackupDate != null 
        ? DateFormat('dd MMM yyyy, HH:mm').format(config!.lastBackupDate!)
        : 'Never';

    return Dialog(
      backgroundColor: const Color(0xFF111114),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.security_rounded, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Backup & Security',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white24),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Backup Path Section
            Text(
              'AUTO-BACKUP LOCATION',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_open_rounded, color: Colors.white24, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          config?.backupPath ?? 'No location selected',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: config?.backupPath != null ? Colors.white70 : Colors.white24,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: _pickBackupPath,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  if (config?.backupPath == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Automated backups are triggered on logout and shutdown. Select an external drive for maximum security.',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.orangeAccent.withValues(alpha: 0.6)),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Stats Section
            Row(
              children: [
                Expanded(
                  child: _buildStatTile('Last Backup', lastBackup, Icons.history_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile('Backup Type', 'Full Snapshot', Icons.data_usage_rounded),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Manual Backup Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _runManualBackup,
                icon: _isBackingUp 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(_isBackingUp ? 'BACKING UP...' : 'RUN MANUAL BACKUP NOW'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC1F11D),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => const BackupRestoreModal(),
                ),
                icon: const Icon(Icons.settings_backup_restore_rounded, size: 16, color: Color(0xFFC1F11D)),
                label: Text(
                  'RESTORE SYSTEM BACKUP', 
                  style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFFC1F11D)),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: const Color(0xFFC1F11D).withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white38),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
