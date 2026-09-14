import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class CloudDatabaseModal extends ConsumerStatefulWidget {
  const CloudDatabaseModal({super.key});

  @override
  ConsumerState<CloudDatabaseModal> createState() => _CloudDatabaseModalState();
}

class _CloudDatabaseModalState extends ConsumerState<CloudDatabaseModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _apiUrlController;
  late TextEditingController _storeIdController;
  late TextEditingController _storeCodeController;
  late TextEditingController _tpinController;
  late TextEditingController _cloudUserIdController;
  late TextEditingController _cloudPinController;

  bool _isCloudSyncEnabled = false;
  bool _isTesting = false;
  bool _isSyncing = false;
  String? _statusMessage;
  bool _isSuccessStatus = false;
  StoreConfig? _config;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController();
    _storeIdController = TextEditingController(text: '1');
    _storeCodeController = TextEditingController(text: 'STORE-001');
    _tpinController = TextEditingController();
    _cloudUserIdController = TextEditingController(text: '1001');
    _cloudPinController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final isar = ref.read(isarProvider);
    _config = await isar.storeConfigs.where().findFirst();
    if (_config != null) {
      setState(() {
        _isCloudSyncEnabled = _config!.isCloudSyncEnabled;
        _apiUrlController.text =
            _config!.cloudApiUrl ?? 'http://23.139.36.20:8003';
        _storeIdController.text = (_config!.cloudStoreId ?? 1).toString();
        _storeCodeController.text = _config!.bhfId.trim().isEmpty
            ? '000'
            : _config!.bhfId.trim().padLeft(3, '0');
        _tpinController.text = _config!.tpin ?? '';
        _cloudUserIdController.text = _config!.cloudAuthUserId ?? '1001';
        _cloudPinController.text = _config!.cloudAuthPin ?? '';
      });
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _storeIdController.dispose();
    _storeCodeController.dispose();
    _tpinController.dispose();
    _cloudUserIdController.dispose();
    _cloudPinController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _statusMessage = 'Connecting to PostgreSQL Cloud Server...';
      _isSuccessStatus = false;
    });

    final cloudService = ref.read(cloudDatabaseServiceProvider);
    final baseUrl = _apiUrlController.text.trim();
    final isConnected = await cloudService.checkConnection(baseUrl);

    if (isConnected && _isCloudSyncEnabled) {
      try {
        final login = await cloudService.authenticateUser(
          baseUrl: baseUrl,
          numericId: _cloudUserIdController.text.trim(),
          pin: _cloudPinController.text.trim(),
          tpin: _tpinController.text.trim(),
          branchCode: _storeCodeController.text.trim(),
        );
        final token =
            login?['token']?.toString() ?? login?['access_token']?.toString();
        if (token != null && token.isNotEmpty && _config != null) {
          await ref.read(isarProvider).writeTxn(() async {
            _config!.cloudAuthToken = token;
            _config!.cloudAuthPin = _cloudPinController.text.trim();
            _config!.cloudAuthUserId = _cloudUserIdController.text.trim();
            await ref.read(isarProvider).storeConfigs.put(_config!);
          });
        }
      } catch (e) {
        setState(() {
          _isTesting = false;
          _isSuccessStatus = false;
          _statusMessage =
              'Server reachable, but cloud authentication failed: $e';
        });
        return;
      }
    }

    setState(() {
      _isTesting = false;
      _isSuccessStatus = isConnected;
      _statusMessage = isConnected
          ? 'Successfully connected to PostgreSQL Cloud DB Service!'
          : 'Failed to connect. Please verify backend URL and database status.';
    });
  }

  Future<void> _triggerManualSync() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Syncing pending offline transactions to Cloud DB...';
      _isSuccessStatus = false;
    });

    try {
      final syncService = ref.read(postgresSyncServiceProvider);
      final syncedCount = await syncService.syncPendingTransactions();
      setState(() {
        _isSyncing = false;
        _isSuccessStatus = true;
        _statusMessage =
            'Sync Complete! $syncedCount sales synced to Cloud PostgreSQL DB.';
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _isSuccessStatus = false;
        _statusMessage = 'Sync Error: ${e.toString()}';
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    final isar = ref.read(isarProvider);
    final storeId = int.tryParse(_storeIdController.text.trim()) ?? 1;

    await isar.writeTxn(() async {
      final config = _config ?? StoreConfig()
        ..businessName = 'Beleka POS Store'
        ..terminalName = 'POS-Main';

      config.isCloudSyncEnabled = _isCloudSyncEnabled;
      config.cloudApiUrl = _apiUrlController.text.trim();
      config.cloudStoreId = storeId;
      config.bhfId = _storeCodeController.text.trim().isEmpty
          ? '000'
          : _storeCodeController.text.trim().padLeft(3, '0');
      config.tpin = _tpinController.text.trim().isEmpty
          ? null
          : _tpinController.text.trim();
      config.cloudAuthUserId = _cloudUserIdController.text.trim();
      config.cloudAuthPin = _cloudPinController.text.trim().isNotEmpty
          ? _cloudPinController.text.trim()
          : config.cloudAuthPin;

      await isar.storeConfigs.put(config);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud PostgreSQL settings saved successfully!'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 550),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: Colors.blue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Cloud PostgreSQL & Multi-Store',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Connect to centralized online PostgreSQL database',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 30),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enable Cloud PostgreSQL Database Sync',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Automatically sync store sales and inventory with online cloud DB',
                ),
                value: _isCloudSyncEnabled,
                onChanged: (val) => setState(() => _isCloudSyncEnabled = val),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiUrlController,
                decoration: const InputDecoration(
                  labelText: 'Cloud API / Database Server URL',
                  hintText:
                      'e.g. https://pos-api.beleka.cloud or http://localhost:8000',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                validator: (val) {
                  if (_isCloudSyncEnabled &&
                      (val == null || val.trim().isEmpty)) {
                    return 'Please enter valid Cloud Database API URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tpinController,
                      decoration: const InputDecoration(
                        labelText: 'Organization TPIN',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                      validator: (val) {
                        if (_isCloudSyncEnabled &&
                            (val == null || val.trim().isEmpty)) {
                          return 'Enter organization TPIN';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _cloudUserIdController,
                      decoration: const InputDecoration(
                        labelText: 'Cloud User ID',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (val) {
                        if (_isCloudSyncEnabled &&
                            (val == null || val.trim().isEmpty)) {
                          return 'Enter cloud user ID';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cloudPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cloud User PIN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
                validator: (val) {
                  if (_isCloudSyncEnabled &&
                      (val == null || val.trim().isEmpty)) {
                    return 'Enter cloud user PIN';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _storeIdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cloud Store ID',
                        hintText: '1',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.store_rounded),
                      ),
                      validator: (val) {
                        if (_isCloudSyncEnabled &&
                            (val == null || int.tryParse(val.trim()) == null)) {
                          return 'Enter valid store ID';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _storeCodeController,
                      decoration: const InputDecoration(
                        labelText: 'BHF ID / Branch Code',
                        hintText: '00 for HQ, 01 for Branch 1',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code_rounded),
                      ),
                      validator: (val) {
                        if (_isCloudSyncEnabled &&
                            !RegExp(r'^\d{2}$').hasMatch(val?.trim() ?? '')) {
                          return 'Enter a 2-digit BHF ID';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isSuccessStatus
                        ? Colors.green.withAlpha(30)
                        : Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isSuccessStatus ? Colors.green : Colors.amber,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSuccessStatus
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: _isSuccessStatus
                            ? Colors.green
                            : Colors.amber[800],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _isSuccessStatus
                                ? Colors.green[900]
                                : Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isTesting ? null : _testConnection,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cable_rounded),
                        label: const Text('Test Connection'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _isSyncing ? null : _triggerManualSync,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync_rounded),
                        label: const Text('Sync Now'),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _saveConfig,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
