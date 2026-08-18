import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/api_service.dart';
import 'package:beleka_pos/services/sync_service.dart';

/// Orchestrates the multi-terminal network features.
/// It monitors the StoreConfig to determine whether this terminal 
/// acts as a Manager (Server) or as a Cashier (Client Sync).
class NetworkManager {
  final Ref _ref;
  bool _isInit = false;

  NetworkManager(this._ref);

  void initialize() {
    if (_isInit) return;
    _isInit = true;

    debugPrint('NETWORK_MANAGER: Initializing connectivity controls...');

    // 1. Listen for Store Configuration changes (Manager vs Terminal mode)
    _ref.listen(storeConfigProvider, (previous, next) {
      final config = next.value;
      if (config == null) return;

      _updateLifecycle(config, _ref.read(authProvider));
    }, fireImmediately: true);

    // 2. Listen for Authentication changes (Sync only when logged in)
    _ref.listen(authProvider, (previous, next) {
      final config = _ref.read(storeConfigProvider).value;
      if (config == null) return;

      _updateLifecycle(config, next);
    });
  }

  void _updateLifecycle(StoreConfig config, User? user) {
    if (config.isManagerMode) {
      // MANAGER MODE (SERVER)
      final apiService = _ref.read(apiServiceProvider);
      if (!apiService.isRunning) {
        debugPrint('NETWORK_MANAGER: Starting Manager Server on port ${config.port}...');
        apiService.start(port: config.port);
      }
      
      // Stop any client sync loops
      _ref.read(syncServiceProvider).stopSyncLoops();
      
    } else {
      // TERMINAL MODE (CLIENT SYNC)
      // Stop server if running
      final apiService = _ref.read(apiServiceProvider);
      if (apiService.isRunning) {
        debugPrint('NETWORK_MANAGER: Stopping Server (Switching to Terminal mode)');
        apiService.stop();
      }

      // Sync only if a user is logged in
      final syncService = _ref.read(syncServiceProvider);
      if (user != null) {
        debugPrint('NETWORK_MANAGER: Starting Sync for Terminal [${config.terminalName}]');
        syncService.startSyncLoops(config.terminalName);
      } else {
        syncService.stopSyncLoops();
      }
    }
  }
}

/// Singleton-like provider for the Network Manager.
/// The manager should be initialized in the app's root (e.g., ShellScreen).
final networkManagerProvider = Provider<NetworkManager>((ref) {
  return NetworkManager(ref);
});
