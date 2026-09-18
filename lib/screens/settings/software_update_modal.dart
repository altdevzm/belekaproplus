import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:beleka_pos/providers/update_provider.dart';
import 'package:beleka_pos/services/update_service.dart';

class SoftwareUpdateModal extends ConsumerStatefulWidget {
  const SoftwareUpdateModal({super.key});

  @override
  ConsumerState<SoftwareUpdateModal> createState() =>
      _SoftwareUpdateModalState();
}

class _SoftwareUpdateModalState extends ConsumerState<SoftwareUpdateModal> {
  String _currentVersion = '1.0.0';
  bool _isChecking = false;
  String? _statusMessage;
  UpdateInfo? _manualUpdateInfo;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentVersion = info.version;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });

    try {
      final service = ref.read(updateServiceProvider);
      final updateInfo = await service.checkForUpdate();
      if (mounted) {
        setState(() {
          _manualUpdateInfo = updateInfo;
          _isChecking = false;
          if (updateInfo != null && updateInfo.hasUpdate) {
            _statusMessage = 'New version v${updateInfo.latestVersion} is available!';
          } else {
            _statusMessage = 'You are already on the latest version (v$_currentVersion).';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _statusMessage = 'Failed to check for updates: $e';
        });
      }
    }
  }

  Future<void> _startDownloadAndInstall(UpdateInfo info) async {
    final isWindows = Platform.isWindows;
    if (!isWindows) {
      try {
        await Process.run('xdg-open', [info.androidDownloadUrl]);
      } catch (_) {}
      return;
    }

    final progressNotifier = ref.read(updateDownloadProgressProvider.notifier);
    progressNotifier.state = 0.0;

    final service = ref.read(updateServiceProvider);
    final success = await service.downloadAndInstall(
      info,
      onProgress: (p) => progressNotifier.state = p,
    );

    if (!success && mounted) {
      progressNotifier.state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Update download failed. Please check your internet connection or download manually from GitHub.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final background = isDark ? const Color(0xFF0F172A) : Colors.white;
    final surface = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final autoUpdateInfo = ref.watch(updateInfoProvider).value;
    final info = _manualUpdateInfo ?? autoUpdateInfo;
    final downloadProgress = ref.watch(updateDownloadProgressProvider);
    final isDownloading = downloadProgress != null;

    final hasUpdate = info != null && info.hasUpdate;

    return Dialog(
      backgroundColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: Color(0xFF059669),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOFTWARE & APP UPDATES',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Check for releases, download latest patches & bug fixes',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Version Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Installed Version',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'v$_currentVersion',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Latest GitHub Release',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_isChecking)
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Checking...',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        )
                      else if (info != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: hasUpdate
                                ? const Color(0xFF059669).withValues(alpha: 0.15)
                                : isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v${info.latestVersion}',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: hasUpdate
                                  ? const Color(0xFF059669)
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        )
                      else
                        Text(
                          'Not Checked',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status message
            if (_statusMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasUpdate
                      ? const Color(0xFFECFDF5)
                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasUpdate
                        ? const Color(0xFFA7F3D0)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasUpdate
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      color: hasUpdate
                          ? const Color(0xFF059669)
                          : theme.colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hasUpdate
                              ? const Color(0xFF065F46)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Downloading Progress Indicator
            if (isDownloading) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF059669).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DOWNLOADING INSTALLER...',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF059669),
                          ),
                        ),
                        Text(
                          '${((downloadProgress) * 100).toInt()}%',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: downloadProgress,
                        backgroundColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF059669),
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The application installer will automatically launch when completed.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Release Notes
            if (hasUpdate && (info.releaseNotes.isNotEmpty)) ...[
              const SizedBox(height: 14),
              Text(
                'Release Notes:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _isChecking || isDownloading
                      ? null
                      : _checkForUpdates,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Check for Updates'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (hasUpdate) ...[
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () => _startDownloadAndInstall(info),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(
                      isDownloading ? 'Downloading...' : 'Download & Install v${info.latestVersion}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
