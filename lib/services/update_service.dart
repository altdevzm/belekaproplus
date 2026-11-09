import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Holds information about the latest available update
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String windowsDownloadUrl;
  final String androidDownloadUrl;
  final String releaseNotes;
  final bool isRequired;
  final bool hasUpdate;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.windowsDownloadUrl,
    required this.androidDownloadUrl,
    required this.releaseNotes,
    required this.isRequired,
    required this.hasUpdate,
  });

  String get platformDownloadUrl =>
      Platform.isAndroid ? androidDownloadUrl : windowsDownloadUrl;
}

class UpdateService {
  static const String _githubManifestUrl =
      'https://github.com/altdevzm/belekaproplus-releases/releases/latest/download/version.json';
  static const String _githubApiUrl =
      'https://api.github.com/repos/altdevzm/belekaproplus-releases/releases/latest';
  static const String _githubRepoBase =
      'https://github.com/altdevzm/belekaproplus-releases/releases';

  final Dio _dio;

  UpdateService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'User-Agent': 'BelekaPOS-Updater',
            'Accept': 'application/vnd.github.v3+json',
          },
        ));

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 1. Direct fetch of static version.json (Fast, no GitHub API 60 req/hr rate limit)
      try {
        final manifestResp = await _dio.get(
          _githubManifestUrl,
          options: Options(
            responseType: ResponseType.json,
            validateStatus: (s) => s != null && s < 400,
          ),
        );

        if (manifestResp.statusCode == 200 && manifestResp.data != null) {
          final mData = manifestResp.data is Map<String, dynamic>
              ? manifestResp.data as Map<String, dynamic>
              : (manifestResp.data is String
                  ? jsonDecode(manifestResp.data as String) as Map<String, dynamic>
                  : null);

          if (mData != null) {
            final latestVer = (mData['version'] as String? ?? '').replaceAll('v', '').trim();
            if (latestVer.isNotEmpty) {
              final winUrl = mData['windows_url'] as String? ??
                  '$_githubRepoBase/download/v$latestVer/Beleka_POS_Setup_v$latestVer.exe';
              final androidUrl = mData['android_url'] as String? ??
                  '$_githubRepoBase/download/v$latestVer/Beleka_POS_v$latestVer.apk';
              final notes = _parseReleaseNotes(mData['release_notes'] as String? ?? '');
              final isReq = mData['required'] == true;
              final hasUpdate = _isNewer(latestVer, currentVersion);

              debugPrint(
                'UPDATER: Manifest checked successfully (latest: $latestVer, current: $currentVersion, hasUpdate: $hasUpdate)',
              );

              return UpdateInfo(
                latestVersion: latestVer,
                currentVersion: currentVersion,
                windowsDownloadUrl: winUrl,
                androidDownloadUrl: androidUrl,
                releaseNotes: notes,
                isRequired: isReq,
                hasUpdate: hasUpdate,
              );
            }
          }
        }
      } catch (manifestErr) {
        debugPrint('UPDATE_MANIFEST_NOTE: Direct manifest fetch: $manifestErr; falling back to GitHub API.');
      }

      // 2. Fallback: GitHub REST API
      final resp = await _dio.get(
        _githubApiUrl,
        options: Options(
          headers: {
            'User-Agent': 'BelekaPOS-Updater',
            'Accept': 'application/vnd.github.v3+json',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (resp.statusCode != 200 || resp.data == null) return null;

      final data = resp.data as Map<String, dynamic>;
      final tagName =
          (data['tag_name'] as String? ?? '').replaceAll('v', '').trim();
      if (tagName.isEmpty) return null;

      final releaseNotes =
          _parseReleaseNotes(data['body'] as String? ?? '');
      final assets = (data['assets'] as List? ?? []);

      String windowsUrl = '';
      String androidUrl = '';

      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = asset['browser_download_url'] as String? ?? '';
        if (name.endsWith('.exe')) {
          windowsUrl = url;
        } else if (name.endsWith('.apk') &&
            !name.contains('generator') &&
            !name.contains('license')) {
          androidUrl = url;
        }
      }

      if (windowsUrl.isEmpty) {
        windowsUrl =
            '$_githubRepoBase/download/v$tagName/Beleka_POS_Setup_v$tagName.exe';
      }
      if (androidUrl.isEmpty) {
        androidUrl =
            '$_githubRepoBase/download/v$tagName/Beleka_POS_v$tagName.apk';
      }

      bool isRequired = false;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name == 'version.json') {
          try {
            final vResp =
                await _dio.get(asset['browser_download_url'] as String);
            if (vResp.statusCode == 200 && vResp.data is Map) {
              isRequired = vResp.data['required'] == true;
            }
          } catch (_) {}
          break;
        }
      }

      final hasUpdate = _isNewer(tagName, currentVersion);

      return UpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        windowsDownloadUrl: windowsUrl,
        androidDownloadUrl: androidUrl,
        releaseNotes: releaseNotes,
        isRequired: isRequired,
        hasUpdate: hasUpdate,
      );
    } on DioException catch (e) {
      debugPrint('UPDATE_CHECK_NETWORK: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('UPDATE_CHECK_ERROR: $e');
      return null;
    }
  }

  /// Download the Windows .exe installer to temp and launch silently.
  Future<bool> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) return false;

    try {
      final tempDir = await getTemporaryDirectory();
      final installerPath =
          '${tempDir.path}${Platform.pathSeparator}beleka_pos_update_${info.latestVersion}.exe';

      debugPrint('UPDATER: Downloading to $installerPath');

      await _dio.download(
        info.windowsDownloadUrl,
        installerPath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      debugPrint('UPDATER: Launching installer with elevation...');

      // On Windows, launching directly via Process.start fails with Error 740 if
      // admin elevation is required. Using 'cmd.exe /c start "" ...' utilizes ShellExecute
      // which properly presents the Windows UAC elevation prompt if needed.
      try {
        await Process.start(
          'cmd.exe',
          [
            '/c',
            'start',
            '',
            installerPath,
            '/VERYSILENT',
            '/SP-',
            '/SUPPRESSMSGBOXES',
            '/FORCECLOSEAPPLICATIONS',
            '/RESTARTAPPLICATIONS',
          ],
          mode: ProcessStartMode.detached,
        );
      } catch (e) {
        debugPrint('UPDATER_CMD_FALLBACK: cmd start failed: $e, trying direct Process.start');
        await Process.start(
          installerPath,
          [
            '/VERYSILENT',
            '/SP-',
            '/SUPPRESSMSGBOXES',
            '/FORCECLOSEAPPLICATIONS',
            '/RESTARTAPPLICATIONS',
          ],
          mode: ProcessStartMode.detached,
        );
      }

      await Future.delayed(const Duration(milliseconds: 1500));
      exit(0);
    } catch (e) {
      debugPrint('UPDATER_INSTALL_ERROR: $e');
      return false;
    }
  }

  bool _isNewer(String latest, String current) {
    try {
      final l = _parseVersion(latest);
      final c = _parseVersion(current);
      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  List<int> _parseVersion(String v) {
    final clean = v.replaceAll('v', '').split('-').first;
    final parts = clean.split('.');
    return List.generate(
        3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
  }

  String _parseReleaseNotes(String body) {
    if (body.isEmpty) return 'Bug fixes and performance improvements.';
    var notes = body
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'#{1,6}\s'), '')
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'\1')
        .trim();
    if (notes.length > 220) notes = '${notes.substring(0, 220)}…';
    return notes;
  }
}
