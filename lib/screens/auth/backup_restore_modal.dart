import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/main.dart';
import 'package:beleka_pos/providers/users_provider.dart';

class BackupRestoreModal extends ConsumerStatefulWidget {
  const BackupRestoreModal({super.key});

  @override
  ConsumerState<BackupRestoreModal> createState() => _BackupRestoreModalState();
}

class _BackupRestoreModalState extends ConsumerState<BackupRestoreModal> {
  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;
  Map<String, dynamic>? _previewData;
  String? _selectedFilePath;
  final TextEditingController _pasteController = TextEditingController();
  bool _isPasteMode = false;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'isar'],
        dialogTitle: 'Select Beleka POS Backup File',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        _selectedFilePath = path;
        await _parseAndPreviewFile(path);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to pick file: $e');
    }
  }

  Future<void> _parseAndPreviewFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        setState(() => _errorMessage = 'Selected file does not exist');
        return;
      }

      if (path.endsWith('.json')) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          setState(() {
            _previewData = data;
            _statusMessage = 'Backup verified: ${data['app'] ?? "Beleka POS"} snapshot';
          });
        } else {
          setState(() => _errorMessage = 'Invalid backup format (Expected JSON object)');
        }
      } else {
        setState(() {
          _previewData = {'type': 'Isar binary backup', 'path': path};
          _statusMessage = 'Ready to restore from binary snapshot';
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not read backup file: $e');
    }
  }

  void _parsePastedJson() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please paste JSON backup content');
      return;
    }

    try {
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) {
        setState(() {
          _previewData = data;
          _errorMessage = null;
          _statusMessage = 'JSON backup parsed successfully';
        });
      } else {
        setState(() => _errorMessage = 'Invalid JSON structure');
      }
    } catch (e) {
      setState(() => _errorMessage = 'JSON parse error: $e');
    }
  }

  Future<void> _executeRestore() async {
    if (_previewData == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Restoring database records...';
    });

    try {
      final db = ref.read(databaseServiceProvider);
      Map<String, int> stats;

      if (_isPasteMode || _selectedFilePath?.endsWith('.json') == true) {
        stats = await db.restoreFromJsonMap(_previewData!);
      } else if (_selectedFilePath != null) {
        stats = await db.restoreFromFile(_selectedFilePath!);
      } else {
        throw Exception('No backup source selected');
      }

      // Refresh app providers
      ref.invalidate(hasUsersProvider);
      ref.invalidate(appStartupProvider);
      ref.invalidate(usersProvider);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'System successfully restored! Restored ${stats['users'] ?? 0} staff accounts, ${stats['products'] ?? 0} products, ${stats['categories'] ?? 0} categories, ${stats['transactions'] ?? 0} sales.';
        });

        // Show success snackbar and close after delay
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data restored successfully! All accounts and store data are ready.'),
            backgroundColor: Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );

        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Restore failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
    final innerBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    const primaryAccent = Color(0xFF1D4ED8);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 620,
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.settings_backup_restore_rounded, color: primaryAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RESTORE ACCOUNT & DATA',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'IMPORT SYSTEM SNAPSHOT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: primaryAccent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Mode Selector Tabs
            Container(
              decoration: BoxDecoration(
                color: innerBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      context,
                      'IMPORT BACKUP FILE',
                      !_isPasteMode,
                      Icons.file_open_rounded,
                      () => setState(() => _isPasteMode = false),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildTabButton(
                      context,
                      'PASTE BACKUP DATA',
                      _isPasteMode,
                      Icons.paste_rounded,
                      () => setState(() => _isPasteMode = true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // File Picker Mode or Paste Mode
            if (!_isPasteMode) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 32, color: primaryAccent),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFilePath != null 
                          ? File(_selectedFilePath!).uri.pathSegments.last 
                          : 'Select a .json backup file to restore accounts & data',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _selectedFilePath != null ? primaryAccent : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.folder_open_rounded, size: 16, color: Colors.white),
                      label: Text('BROWSE BACKUP FILE', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _pasteController,
                      maxLines: 5,
                      style: GoogleFonts.jetBrainsMono(color: theme.colorScheme.onSurface, fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Paste raw JSON backup payload here...',
                        hintStyle: GoogleFonts.jetBrainsMono(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 11),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _parsePastedJson,
                        icon: const Icon(Icons.check, size: 14, color: Colors.white),
                        label: Text('VERIFY DATA', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Preview Information Box
            if (_previewData != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF059669)),
                        const SizedBox(width: 8),
                        Text(
                          'SNAPSHOT CONTENT READY TO RESTORE',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF047857),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_previewData!['storeConfig'] != null)
                          _buildStatBadge(context, 'Store: ${_previewData!['storeConfig']['businessName'] ?? "Beleka"}'),
                        if (_previewData!['users'] is List)
                          _buildStatBadge(context, '${(_previewData!['users'] as List).length} Staff Accounts'),
                        if (_previewData!['products'] is List)
                          _buildStatBadge(context, '${(_previewData!['products'] as List).length} Products'),
                        if (_previewData!['categories'] is List)
                          _buildStatBadge(context, '${(_previewData!['categories'] as List).length} Categories'),
                        if (_previewData!['saleTransactions'] is List)
                          _buildStatBadge(context, '${(_previewData!['saleTransactions'] as List).length} Transactions'),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Status or Error Feedback
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(color: const Color(0xFFB91C1C), fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_statusMessage != null && _errorMessage == null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: const Color(0xFF059669),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Action Button
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: (_previewData == null || _isLoading) ? null : _executeRestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryAccent,
                  disabledBackgroundColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFE2E8F0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.restore_page_rounded, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'CONFIRM & RESTORE EVERYTHING',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              fontSize: 12,
                              color: Colors.white,
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

  Widget _buildTabButton(BuildContext context, String label, bool isSelected, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    const primaryAccent = Color(0xFF1D4ED8);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(BuildContext context, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF047857)),
      ),
    );
  }
}
