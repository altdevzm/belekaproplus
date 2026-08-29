import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/providers/update_provider.dart';
import 'package:beleka_pos/services/update_service.dart';

/// Slim update notification banner that sits above the main content area.
/// Appears only when a newer version is found on GitHub Releases.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateAsync = ref.watch(updateInfoProvider);
    final downloadProgress = ref.watch(updateDownloadProgressProvider);

    return updateAsync.when(
      data: (info) {
        if (info == null || !info.hasUpdate) return const SizedBox.shrink();
        return _BannerContent(info: info, downloadProgress: downloadProgress);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _BannerContent extends ConsumerWidget {
  final UpdateInfo info;
  final double? downloadProgress;

  const _BannerContent({required this.info, this.downloadProgress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownloading = downloadProgress != null;
    final isWindows = Platform.isWindows;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2F1A),
            const Color(0xFF0F2010),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2D5A2D), width: 1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: isDownloading
              ? _buildDownloadingRow(downloadProgress!)
              : _buildReadyRow(context, ref, isWindows),
        ),
      ),
    );
  }

  Widget _buildReadyRow(BuildContext context, WidgetRef ref, bool isWindows) {
    return Row(
      children: [
        // Update icon
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.system_update_alt_rounded,
            color: Color(0xFF2ECC71),
            size: 16,
          ),
        ),
        const SizedBox(width: 12),

        // Version info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'UPDATE AVAILABLE',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF2ECC71),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'v${info.latestVersion}',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2ECC71),
                      ),
                    ),
                  ),
                  if (info.isRequired) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'REQUIRED',
                        style: GoogleFonts.manrope(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  info.releaseNotes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Actions
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!info.isRequired)
              TextButton(
                onPressed: () => ref.read(updateInfoProvider.notifier).snooze(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Later',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white38,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => _startUpdate(context, ref, isWindows),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2ECC71),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: Icon(
                isWindows ? Icons.download_rounded : Icons.open_in_browser_rounded,
                size: 14,
              ),
              label: Text(
                isWindows ? 'Update Now' : 'Download',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadingRow(double progress) {
    final percent = (progress * 100).toInt();
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SizedBox(
            width: 16,
            height: 16,
            child: Padding(
              padding: EdgeInsets.all(7),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2ECC71),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DOWNLOADING UPDATE v${info.latestVersion}',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF2ECC71),
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2ECC71),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF2ECC71)),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'The app will restart automatically when the installer is ready.',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _startUpdate(
      BuildContext context, WidgetRef ref, bool isWindows) async {
    if (!isWindows) {
      // Android / other: open browser
      try {
        await Process.run('xdg-open', [info.androidDownloadUrl]);
      } catch (_) {}
      return;
    }

    // Windows: download + launch installer
    final progressNotifier = ref.read(updateDownloadProgressProvider.notifier);
    progressNotifier.state = 0.0;

    final service = ref.read(updateServiceProvider);
    final success = await service.downloadAndInstall(
      info,
      onProgress: (p) => progressNotifier.state = p,
    );

    if (!success && context.mounted) {
      progressNotifier.state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download failed. Please visit github.com/altdevzm/belekapro to download manually.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 6),
        ),
      );
    }
  }
}
