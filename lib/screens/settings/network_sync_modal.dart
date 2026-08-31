import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/services/sync_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';

class NetworkSyncModal extends ConsumerStatefulWidget {
  const NetworkSyncModal({super.key});

  @override
  ConsumerState<NetworkSyncModal> createState() => _NetworkSyncModalState();
}

class _NetworkSyncModalState extends ConsumerState<NetworkSyncModal> {
  late TextEditingController _serverIpController;
  late TextEditingController _terminalController;
  
  bool _isManagerMode = true;
  String _localIp = 'Detecting...';
  bool _isTesting = false;
  bool _isSyncing = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    final config = ref.read(storeConfigProvider).value;
    _isManagerMode = config?.isManagerMode ?? true;
    _serverIpController = TextEditingController(text: config?.serverIp ?? '');
    _terminalController = TextEditingController(text: config?.terminalName ?? 'TILL-01');
    _detectLocalIp();
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _detectLocalIp() async {
    String detected = '127.0.0.1';
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            detected = addr.address;
            break;
          }
        }
        if (detected != '127.0.0.1') break;
      }
      if (detected == '127.0.0.1') {
        final info = NetworkInfo();
        final wifiIp = await info.getWifiIP();
        if (wifiIp != null && wifiIp.isNotEmpty) detected = wifiIp;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _localIp = detected);
    }
  }

  Future<void> _saveNetworkConfig() async {
    final db = ref.read(databaseServiceProvider);
    final existing = await db.getStoreConfig();
    final config = existing ?? StoreConfig();
    config.isManagerMode = _isManagerMode;
    config.serverIp = _serverIpController.text.trim();
    config.terminalName = _terminalController.text.trim();
    
    await db.saveStoreConfig(config);
    ref.invalidate(storeConfigProvider);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isManagerMode ? 'Saved as Master Hub (Server IP: $_localIp)' : 'Saved as Cashier Till (Connecting to ${_serverIpController.text.trim()})'),
          backgroundColor: const Color(0xFF6366F1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    final ip = _serverIpController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _testResult = 'Please enter the Master POS IP address.';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final client = NetworkClient(serverUrl: 'http://$ip:8080');
    final success = await client.testConnection();

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testResult = success 
            ? 'Connection Successful! Connected to Master POS ($ip:8080).' 
            : 'Connection Failed. Please check that Master POS is running and on the same Wi-Fi.';
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    final syncService = ref.read(syncServiceProvider);
    await syncService.syncMetadata();
    final synced = await syncService.syncPendingTransactions();

    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Catalog synchronized. Pushed $synced pending transactions.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: 580,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.hub_rounded, color: primaryColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NETWORK & MULTI-TILL SYNC',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Connect multiple cash registers over local Wi-Fi / LAN',
                                style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 16),

              // Mode Selector Toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isManagerMode ? 'MASTER HUB / SERVER MODE (TILL 1)' : 'CASHIER / CLIENT TILL MODE (TILL 2+)',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isManagerMode 
                                ? 'This computer is the Master POS holding the primary database for other tills.' 
                                : 'This till connects to the Master POS to download stock and push sales.',
                            style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isManagerMode,
                      onChanged: (val) => setState(() => _isManagerMode = val),
                      activeThumbColor: primaryColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Dynamic Section based on mode
              if (_isManagerMode) ...[
                // MASTER HUB DETAILS
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.router_rounded, color: Color(0xFF059669), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'MASTER POS IP ADDRESS',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              children: [
                                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text('HUB ACTIVE :8080', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _localIp,
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF065F46),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _localIp));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Copied Master IP: $_localIp to clipboard')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: const Text('Copy IP'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Note: On your other tills (Till 2, Till 3), enter this exact IP address into their "Master Server IP" field.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF047857), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // CASHIER / CLIENT TILL CONFIG
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MASTER POS SERVER IP *',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _serverIpController,
                      style: GoogleFonts.inter(fontSize: 14, color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'e.g. 192.168.1.150',
                        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        prefixIcon: Icon(Icons.dns_rounded, color: theme.colorScheme.onSurfaceVariant, size: 18),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primaryColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting 
                                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor))
                                : const Icon(Icons.network_check_rounded, size: 16),
                            label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSyncing ? null : _syncNow,
                            icon: _isSyncing 
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.sync_rounded, size: 16),
                            label: Text(_isSyncing ? 'Syncing...' : 'Sync Catalog Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_testSuccess ?? false) ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (_testSuccess ?? false) ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            Icon((_testSuccess ?? false) ? Icons.check_circle_rounded : Icons.error_rounded, color: (_testSuccess ?? false) ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _testResult!,
                                style: GoogleFonts.inter(fontSize: 12, color: (_testSuccess ?? false) ? const Color(0xFF059669) : const Color(0xFFDC2626), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              const SizedBox(height: 16),
              // Till Identifier
              Text(
                'THIS TILL REGISTER CODE *',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _terminalController,
                style: GoogleFonts.inter(fontSize: 14, color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'e.g. TILL-01, TILL-02',
                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.point_of_sale_rounded, color: theme.colorScheme.onSurfaceVariant, size: 18),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primaryColor),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Save Button
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _saveNetworkConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    'SAVE NETWORK CONFIGURATION',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 0.5, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
