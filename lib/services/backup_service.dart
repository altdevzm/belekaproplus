import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/services/cloud_database_service.dart';

class BackupService {
  final CloudDatabaseService _cloudDbService;

  BackupService({CloudDatabaseService? cloudDbService})
      : _cloudDbService = cloudDbService ?? CloudDatabaseService();

  /// Gets the root folder dedicated to local and VPS backups.
  Future<Directory> _getBackupRootDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docsDir.path, 'BelekaPOS_Backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Backup local Isar & SQLite database files into Documents/BelekaPOS_Backups/local_db/
  Future<bool> createLocalBackup(Isar isar) async {
    try {
      final rootDir = await _getBackupRootDirectory();
      final localBackupDir = Directory(p.join(rootDir.path, 'local_db'));
      if (!await localBackupDir.exists()) {
        await localBackupDir.create(recursive: true);
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      // 1. Isar Database Snapshot
      final docsDir = await getApplicationDocumentsDirectory();
      final isarPath = p.join(docsDir.path, 'default.isar');
      final isarFile = File(isarPath);

      if (await isarFile.exists()) {
        final backupIsarPath = p.join(localBackupDir.path, 'local_isar_$timestamp.isar');
        await isarFile.copy(backupIsarPath);
        debugPrint('Local Isar DB backed up to: $backupIsarPath');
      } else {
        // Fallback: Copy via Isar copyToFile
        final backupIsarPath = p.join(localBackupDir.path, 'local_isar_$timestamp.isar');
        await isar.copyToFile(backupIsarPath);
        debugPrint('Local Isar DB backed up via copyToFile to: $backupIsarPath');
      }

      // 2. Local SQLite DB Snapshot (if exists)
      final sqlitePath = p.join(docsDir.path, 'beleka_local_sql.db');
      final sqliteFile = File(sqlitePath);
      if (await sqliteFile.exists()) {
        final backupSqlitePath = p.join(localBackupDir.path, 'local_sqlite_$timestamp.db');
        await sqliteFile.copy(backupSqlitePath);
        debugPrint('Local SQLite DB backed up to: $backupSqlitePath');
      }

      return true;
    } catch (e) {
      debugPrint('Local Database Backup Failed: $e');
      return false;
    }
  }

  /// Download VPS cloud database snapshot and save into Documents/BelekaPOS_Backups/vps_cloud/
  Future<bool> fetchAndSaveVpsBackup({
    required String baseUrl,
    required int storeId,
    String? token,
  }) async {
    try {
      final rootDir = await _getBackupRootDirectory();
      final vpsBackupDir = Directory(p.join(rootDir.path, 'vps_cloud'));
      if (!await vpsBackupDir.exists()) {
        await vpsBackupDir.create(recursive: true);
      }

      final data = await _cloudDbService.downloadVpsBackup(
        baseUrl: baseUrl,
        storeId: storeId,
        token: token,
      );

      if (data == null) {
        debugPrint('VPS backup download returned null payload.');
        return false;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFilePath = p.join(vpsBackupDir.path, 'vps_backup_${storeId}_$timestamp.json');

      final file = File(backupFilePath);
      await file.writeAsString(jsonEncode(data), flush: true);
      debugPrint('VPS Cloud DB backed up to: $backupFilePath');

      return true;
    } catch (e) {
      debugPrint('VPS Cloud Database Backup Failed: $e');
      return false;
    }
  }

  /// Execute full backup sequence (Local + VPS Cloud if configured).
  Future<Map<String, bool>> performFullExitBackup({
    required Isar isar,
    String? cloudBaseUrl,
    int? storeId,
    String? token,
  }) async {
    final results = <String, bool>{
      'local': false,
      'vps': false,
    };

    // 1. Perform Local DB Backup
    results['local'] = await createLocalBackup(isar);

    // 2. Perform VPS Backup (if server URL & store ID are available)
    if (cloudBaseUrl != null && cloudBaseUrl.trim().isNotEmpty && storeId != null && storeId > 0) {
      results['vps'] = await fetchAndSaveVpsBackup(
        baseUrl: cloudBaseUrl,
        storeId: storeId,
        token: token,
      );
    }

    // 3. Clean up older backups (keep last 14 days)
    await rotateOldBackups(maxDays: 14);

    return results;
  }

  /// Deletes backup files older than [maxDays].
  Future<void> rotateOldBackups({int maxDays = 14}) async {
    try {
      final rootDir = await _getBackupRootDirectory();
      final cutoffDate = DateTime.now().subtract(Duration(days: maxDays));

      final subDirs = [
        Directory(p.join(rootDir.path, 'local_db')),
        Directory(p.join(rootDir.path, 'vps_cloud')),
      ];

      for (final subDir in subDirs) {
        if (!await subDir.exists()) continue;
        final files = subDir.listSync();
        for (final entity in files) {
          if (entity is File) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoffDate)) {
              await entity.delete();
              debugPrint('Deleted old backup file: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Backup rotation error: $e');
    }
  }
}
