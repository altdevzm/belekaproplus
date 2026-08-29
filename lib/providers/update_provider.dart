import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((_) => UpdateService());

/// Stores the latest UpdateInfo from GitHub, null = no update / not checked
final updateInfoProvider =
    AsyncNotifierProvider<UpdateNotifier, UpdateInfo?>(() => UpdateNotifier());

class UpdateNotifier extends AsyncNotifier<UpdateInfo?> {
  Timer? _periodicTimer;

  @override
  Future<UpdateInfo?> build() async {
    Future.delayed(const Duration(seconds: 4), _doCheck);
    _periodicTimer?.cancel();
    _periodicTimer =
        Timer.periodic(const Duration(hours: 4), (_) => _doCheck());
    ref.onDispose(() => _periodicTimer?.cancel());
    return null;
  }

  Future<void> _doCheck() async {
    try {
      final service = ref.read(updateServiceProvider);
      final info = await service.checkForUpdate();
      if (info != null && info.hasUpdate) {
        if (await _isSnoozed(info.latestVersion)) return;
        state = AsyncValue.data(info);
      }
    } catch (_) {}
  }

  Future<void> checkNow() async {
    state = const AsyncValue.loading();
    await _doCheck();
  }

  Future<void> snooze() async {
    final current = state.value;
    if (current == null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/update_snooze_${current.latestVersion}.txt');
      await file.writeAsString(
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch.toString(),
      );
    } catch (_) {}
    state = const AsyncValue.data(null);
  }

  Future<bool> _isSnoozed(String version) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/update_snooze_$version.txt');
      if (!await file.exists()) return false;
      final until = int.tryParse(await file.readAsString()) ?? 0;
      return DateTime.now().millisecondsSinceEpoch < until;
    } catch (_) {
      return false;
    }
  }
}

/// Download progress 0.0→1.0, null = idle
final updateDownloadProgressProvider = StateProvider<double?>((ref) => null);
