import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/screens/settings/reset_pin_modal.dart';
import 'package:beleka_pos/screens/auth/backup_restore_modal.dart';
import 'package:beleka_pos/screens/settings/network_sync_modal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:isar/isar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _companyController = TextEditingController();
  final _idController = TextEditingController();
  final _pinController = TextEditingController();
  String _pin = '';
  String? _errorMessage;
  bool _isLoading = false;
  String? _recognizedName;

  @override
  void initState() {
    super.initState();
    _idController.addListener(_onIdChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(storeConfigProvider).value;
      final businessName = config?.businessName;
      if (businessName != null && businessName.isNotEmpty) {
        if (_companyController.text.isEmpty) {
          _companyController.text = businessName;
        }
      }
    });
  }

  @override
  void dispose() {
    _idController.removeListener(_onIdChanged);
    _companyController.dispose();
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onIdChanged() async {
    final rawId = _idController.text;
    if (rawId.length > 4) {
      _idController.text = rawId.substring(0, 4);
      _idController.selection = TextSelection.fromPosition(
        const TextPosition(offset: 4),
      );
      setState(() => _errorMessage = 'Staff ID cannot exceed 4 characters');
      return;
    }

    final id = _idController.text.trim();
    if (id.isEmpty) {
      if (_recognizedName != null) setState(() => _recognizedName = null);
      return;
    }

    // Debounce or just check directly for numeric POS usually 3-4 chars
    if (id.length >= 3) {
      final users = await ref.read(databaseServiceProvider).getAllUsers();
      final user = users.cast<User?>().firstWhere(
        (u) => u?.numericId == id,
        orElse: () => null,
      );
      if (user != null) {
        if (_recognizedName != user.name) {
          setState(() {
            _recognizedName = user.name;
          });
        }
      } else {
        if (_recognizedName != null) setState(() => _recognizedName = null);
      }
    } else {
      if (_recognizedName != null) setState(() => _recognizedName = null);
    }
  }

  void _handleLogin() async {
    final companyName = _companyController.text.trim();
    if (companyName.isEmpty) {
      setState(() => _errorMessage = 'Please enter Company Name');
      return;
    }
    if (_idController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter Staff ID');
      return;
    }
    if (_idController.text.trim().length > 4) {
      setState(() => _errorMessage = 'Staff ID cannot exceed 4 characters');
      return;
    }
    if (_pin.length < 4) {
      setState(() => _errorMessage = 'Enter at least 4 digits');
      return;
    }
    if (_pin.length > 6) {
      setState(() => _errorMessage = 'Security PIN cannot exceed 6 digits');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = ref.read(databaseServiceProvider);
      final networkClient = ref.read(networkClientProvider);
      final config = ref.read(storeConfigProvider).value;
      final cloudDb = ref.read(cloudDatabaseServiceProvider);
      final cloudUrl =
          (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
          ? config.cloudApiUrl!.trim()
          : 'http://23.139.36.20:8003';
      String? enteredTpin = config?.businessName.trim().toLowerCase() ==
              companyName.toLowerCase()
          ? config?.tpin?.trim()
          : null;

      if (enteredTpin == null || enteredTpin.isEmpty) {
        enteredTpin = await cloudDb.resolveOrganizationTpin(
          baseUrl: cloudUrl,
          companyName: companyName,
        );
      }
      if (enteredTpin == null || enteredTpin.isEmpty) {
        setState(() => _errorMessage = 'Company is not registered');
        return;
      }

      // 1. Try local login only when the entered TPIN matches this device's tenant.
      final localTpin = config?.tpin?.trim();
      User? user;
      if (localTpin == null || localTpin.isEmpty || localTpin == enteredTpin) {
        user = await db.login(_idController.text.trim(), _pin.trim());
      }

      if (user != null) {
        if (user.branchCode != null &&
            user.branchCode!.isNotEmpty &&
            config != null) {
          config.bhfId = user.branchCode!;
          if (user.branchName != null && user.branchName!.isNotEmpty) {
            config.branchName = user.branchName;
          }
          await db.isar.writeTxn(() async {
            await db.isar.storeConfigs.put(config);
          });
        }
      }

      // 2. If local fails and we have a network connection to manager, try remote login
      if (user == null && networkClient != null) {
        final userData = await networkClient.login(
          _idController.text.trim(),
          _pin.trim(),
          config?.terminalName ?? 'TERMINAL',
        );

        if (userData != null) {
          final rawRole = (userData['role']?.toString() ?? 'cashier')
              .toLowerCase()
              .trim();
          final resolvedRole =
              (rawRole == 'admin' ||
                  rawRole == 'owner' ||
                  rawRole == 'super_admin')
              ? 'owner'
              : (rawRole == 'manager' || rawRole == 'branch_manager')
              ? 'branch_manager'
              : 'cashier';

          final remoteUser = User()
            ..numericId = userData['numericId']
            ..name = userData['name']
            ..role = resolvedRole
            ..branchCode = userData['branchCode']?.toString() ?? '00'
            ..branchName = userData['branchName']?.toString()
            ..passwordHash = hashPin(_pin.trim());

          await db.isar.writeTxn(() async {
            final existing = await db.isar.users
                .filter()
                .numericIdEqualTo(remoteUser.numericId)
                .findFirst();
            if (existing != null) {
              remoteUser.id = existing.id;
            }
            await db.isar.users.put(remoteUser);
          });
          user = remoteUser;

          // Pull store config (including DigiTax API credentials) from Manager Server
          try {
            final serverInfo = await networkClient.getServerInfo();
            if (serverInfo != null) {
              final activeConfig =
                  config ??
                  await db.isar.storeConfigs.where().findFirst() ??
                  StoreConfig();
              if (serverInfo['digitaxApiKey'] != null &&
                  (serverInfo['digitaxApiKey'] as String).isNotEmpty) {
                activeConfig.digitaxApiKey = serverInfo['digitaxApiKey']
                    .toString();
              }
              if (serverInfo['sdcId'] != null)
                activeConfig.sdcId = serverInfo['sdcId'].toString();
              if (serverInfo['tpin'] != null)
                activeConfig.tpin = serverInfo['tpin'].toString();
              if (serverInfo['businessTaxType'] != null)
                activeConfig.businessTaxType = serverInfo['businessTaxType']
                    .toString();
              if (serverInfo['bhfId'] != null)
                activeConfig.bhfId = serverInfo['bhfId'].toString();
              await db.isar.writeTxn(() async {
                await db.isar.storeConfigs.put(activeConfig);
              });
            }
          } catch (e) {
            debugPrint('LOGIN_STORE_SYNC_NOTICE: $e');
          }
        }
      }

          // 3. Authenticate against Cloud PostgreSQL only when local/LAN auth failed.
        if (user == null) {
        try {
        final cloudAuth = await cloudDb.authenticateUser(
          baseUrl: cloudUrl,
          numericId: _idController.text.trim(),
          pin: _pin.trim(),
          tpin: enteredTpin,
          branchCode: config?.bhfId,
          terminalName: config?.terminalName ?? 'BRANCH-POS',
        );

        if (cloudAuth != null && cloudAuth['user'] is Map) {
          final uData = cloudAuth['user'] as Map;
          final sData = (cloudAuth['store'] is Map)
              ? cloudAuth['store'] as Map
              : null;
          final branchBhfId =
              sData?['bhf_id']?.toString() ??
              uData['branch_code']?.toString() ??
              '00';
          final branchName =
              sData?['branch_name']?.toString() ??
              sData?['name']?.toString() ??
              uData['branch_name']?.toString() ??
              'Main Branch';
          final rawRole =
              uData['role']?.toString().toLowerCase().trim() ?? 'cashier';

          final normalizedRole =
              (rawRole == 'owner' ||
                  rawRole == 'admin' ||
                  rawRole == 'super_admin')
              ? 'owner'
              : (rawRole == 'manager' || rawRole == 'branch_manager')
              ? 'branch_manager'
              : rawRole;

          final remoteUser = User()
            ..numericId =
                uData['numeric_id']?.toString() ?? _idController.text.trim()
            ..name =
                uData['name']?.toString() ??
                (normalizedRole == 'owner' ? 'Owner' : 'Staff')
            ..role = normalizedRole
            ..branchCode = branchBhfId
            ..branchName = branchName
            ..phone = uData['phone']?.toString()
            ..passwordHash = hashPin(_pin.trim())
            ..isActive = true;

          await db.isar.writeTxn(() async {
            final existing = await db.isar.users
                .filter()
                .numericIdEqualTo(remoteUser.numericId)
                .findFirst();
            if (existing != null) {
              remoteUser.id = existing.id;
            }
            await db.isar.users.put(remoteUser);

            // Update local store profile with cloud branch credentials
            final activeConfig =
                config ??
                await db.isar.storeConfigs.where().findFirst() ??
                StoreConfig();
            activeConfig.bhfId = branchBhfId;
            activeConfig.cloudApiUrl = cloudUrl;

            // Save the JWT and credentials so future VPS sync calls can re-authenticate.
            final jwtToken =
                cloudAuth['token']?.toString() ??
                cloudAuth['access_token']?.toString();
            if (jwtToken != null && jwtToken.isNotEmpty) {
              activeConfig.cloudAuthToken = jwtToken;
            }
            activeConfig.cloudAuthUserId = _idController.text.trim();
            activeConfig.cloudAuthPin = _pin.trim();

            // Save cloud store ID from the store data
            if (sData != null && sData['id'] != null) {
              activeConfig.cloudStoreId = (sData['id'] as num).toInt();
            }
            if (sData != null) {
              if (sData['name'] != null)
                activeConfig.businessName = sData['name'].toString();
              if (sData['branch_name'] != null)
                activeConfig.branchName = sData['branch_name'].toString();
              if (sData['tpin'] != null && (sData['tpin'] as String).isNotEmpty)
                  activeConfig.tpin = sData['tpin'].toString();
              if (sData['digitax_api_key'] != null &&
                  (sData['digitax_api_key'] as String).isNotEmpty) {
                activeConfig.digitaxApiKey = sData['digitax_api_key']
                    .toString();
              }
              if (sData['digitax_environment'] != null)
                activeConfig.digitaxEnvironment = sData['digitax_environment']
                    .toString();
              if (sData['business_tax_type'] != null)
                activeConfig.businessTaxType = sData['business_tax_type']
                    .toString();
            }
            await db.isar.storeConfigs.put(activeConfig);
          });
          user = remoteUser;
        }
        } catch (e) {
          debugPrint('Cloud VPS Login notice: $e');
        }
      }

      if (user != null) {
        if (mounted) {
          ref.read(authProvider.notifier).login(user);
        }
      } else {
        setState(() {
          _errorMessage = 'Invalid ID or PIN';
          _pin = '';
          _pinController.clear();
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleClockAction(String type) async {
    if (_idController.text.isEmpty) {
      setState(() => _errorMessage = 'Enter ID to clock');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = ref.read(databaseServiceProvider);
      final id = _idController.text.trim();

      final users = await db.getAllUsers();
      final user = users.cast<User?>().firstWhere(
        (u) => u?.numericId == id,
        orElse: () => null,
      );

      if (user != null) {
        await db.logAttendance(user, type);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${type == 'clock_in' ? 'Clocked IN' : 'Clocked OUT'} successfully for ${user.name}',
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        setState(() => _errorMessage = 'Employee not found');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error logging attendance');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onKeypadTap(String value) {
    setState(() {
      _errorMessage = null;
      if (value == 'backspace') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (value == 'check') {
        _handleLogin();
      } else {
        if (_pin.length < 6) {
          _pin += value;
        } else {
          _errorMessage = "Security PIN cannot exceed 6 digits";
        }
      }
      _pinController.text = _pin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF0B1220)
        : const Color(0xFFF5F7FA);
    final consoleBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Branding Pane (Full Bleed)
                    Expanded(
                      flex: 5,
                      child: _buildHeroImageSection(
                        context,
                        isCompact:
                            constraints.maxHeight < 720 ||
                            constraints.maxWidth < 1000,
                      ),
                    ),
                    // Seam Divider Line
                    Container(width: 1, color: borderColor),
                    // Right Authentication Pane (Full Bleed)
                    Expanded(
                      flex: 6,
                      child: Container(
                        color: consoleBg,
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 24,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: _buildRightConsole(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Dedicated Mobile / Compact Layout
              return _buildMobileLoginLayout(context);
            },
          ),

          // Bottom Right Corner Floating Backup Restore Action Button (Desktop only)
          Positioned(
            bottom: 20,
            right: 24,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (MediaQuery.of(context).size.width < 900)
                  return const SizedBox.shrink();
                return _buildBottomRightRestoreButton(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRightRestoreButton(BuildContext context) {
    const primaryAccent = Color(0xFF1D4ED8);

    return TextButton.icon(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => const BackupRestoreModal(),
        );
      },
      icon: const Icon(
        Icons.settings_backup_restore_rounded,
        size: 15,
        color: primaryAccent,
      ),
      label: Text(
        'RESTORE BACKUP',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: primaryAccent,
        ),
      ),
    );
  }

  Widget _buildHeroImageSection(
    BuildContext context, {
    bool isCompact = false,
  }) {
    const primaryColor = Color(0xFF1D4ED8);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Retail Image
        _buildHeroBackground(),

        // Elegant Directional Gradient Overlay for High Text Legibility
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0F172A).withValues(alpha: 0.75),
                const Color(0xFF0F172A).withValues(alpha: 0.45),
              ],
            ),
          ),
        ),

        // Content on top of image
        Padding(
          padding: EdgeInsets.all(isCompact ? 16.0 : 36.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header Brand Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: _buildLogoBadge(isCompact),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BELEKA POS',
                        style: GoogleFonts.inter(
                          fontSize: isCompact ? 16 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'ENTERPRISE POS SYSTEM',
                        style: GoogleFonts.inter(
                          fontSize: isCompact ? 9 : 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF93C5FD),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if (!isCompact) ...[
                // Main Headline & Value Props
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF60A5FA),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ENTERPRISE COMMERCE ENGINE',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: const Color(0xFFBFDBFE),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'High-Speed Checkout\n& Inventory Control.',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Optimized for high-volume transactions, real-time stock control, multi-terminal sync, and ZRA fiscal compliance.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Feature highlights chips
                    _buildFeaturePill(
                      Icons.bolt_rounded,
                      'Ultra-Low Latency Offline First Architecture',
                    ),
                    const SizedBox(height: 10),
                    _buildFeaturePill(
                      Icons.sync_alt_rounded,
                      'Automatic Multi-Terminal Synchronization',
                    ),
                    const SizedBox(height: 10),
                    _buildFeaturePill(
                      Icons.analytics_rounded,
                      'Real-time Stock & Revenue Analytics',
                    ),
                  ],
                ),

                // Bottom Status Line
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Color(0xFF60A5FA),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ENCRYPTED LOCAL STORAGE • HARDWARE-VERIFIED',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.8),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturePill(IconData icon, String label) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF93C5FD)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }

  // --- Mobile Adaptive Login Layout ---

  Widget _buildMobileLoginLayout(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Mobile App Bar / Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: primaryAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.point_of_sale_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BELEKA POS',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'CASHIER TERMINAL',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: primaryAccent,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const NetworkSyncModal(),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1C283D)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lan_rounded,
                              size: 13,
                              color: primaryAccent,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'LAN TILL',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Terminal & Network Mode Status Indicator
                _buildTerminalBadge(context),
                const SizedBox(height: 14),

                // Staff Identification Banner
                if (_recognizedName != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF059669),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'STAFF IDENTIFIED: ${_recognizedName!.toUpperCase()}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF047857),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Company Name Field
                _buildInputField(
                  context,
                  'COMPANY NAME',
                  _companyController,
                  Icons.business_outlined,
                  'Enter registered company name',
                  isCompanyName: true,
                ),
                const SizedBox(height: 10),

                // Staff ID Field
                _buildInputField(
                  context,
                  'EMPLOYEE ID',
                  _idController,
                  Icons.person_outline,
                  'Staff ID (e.g. 1001)',
                ),
                const SizedBox(height: 10),

                // PIN Dots Display
                _buildPinDotsDisplay(context),
                const SizedBox(height: 10),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                              color: const Color(0xFFB91C1C),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Touch PIN Pad for Mobile
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.6,
                    children: [
                      ...List.generate(
                        9,
                        (index) =>
                            _buildKeyItem(context, (index + 1).toString()),
                      ),
                      _buildKeyItem(context, 'backspace', isIcon: true),
                      _buildKeyItem(context, '0'),
                      _buildKeyItem(context, 'check', isIcon: true),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Clock In / Clock Out Buttons
                Row(
                  children: [
                    Expanded(
                      child: _buildAuxButton(
                        context,
                        Icons.login_rounded,
                        'Clock In',
                        onTap: () => _handleClockAction('clock_in'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildAuxButton(
                        context,
                        Icons.logout_rounded,
                        'Clock Out',
                        onTap: () => _handleClockAction('clock_out'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Submit / Login Action Button (Solid & Borderless)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.login_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'SIGN IN TO REGISTER',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Footer Links
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTextLink(
                      context,
                      'RESET PIN',
                      onTap: () {
                        _showInfoDialog(
                          'CREDENTIAL_RECOVERY',
                          'Staff PINs: Must be reset by a Manager in Settings > User Management.\n\nAdmin Reset: If you are the owner and forgot your Admin PIN, use the "ADMIN RECOVERY" button below to enter your 8-digit terminal recovery code.',
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    _buildTextLink(
                      context,
                      'RESTORE DATA',
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => const BackupRestoreModal(),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    _buildTextLink(
                      context,
                      'SUPPORT',
                      onTap: () {
                        _showInfoDialog(
                          'SYSTEM_SUPPORT',
                          'If you are having trouble accessing the terminal, please contact your store administrator.',
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinDotsDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final containerBg = isDark
        ? const Color(0xFF0B1220)
        : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryColor = Color(0xFF1D4ED8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'PIN:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(6, (index) {
              final isFilled = index < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? primaryColor
                      : (isDark
                            ? const Color(0xFF293548)
                            : const Color(0xFFCBD5E1)),
                ),
              );
            }),
          ),
          if (_pin.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _pin = '';
                _pinController.text = '';
                _errorMessage = null;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'CLEAR',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildRightConsole(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side of Console: Credentials & Form
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Recognized Employee or Default Header with LAN Till Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_recognizedName != null) ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF059669),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'STAFF IDENTIFIED',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _recognizedName!.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ] else ...[
                            Text(
                              'Terminal Authentication',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Enter your Staff ID and PIN to begin shift',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const NetworkSyncModal(),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lan_rounded,
                              size: 14,
                              color: primaryAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LAN TILL IP',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Terminal & Network Mode Status Indicator
                _buildTerminalBadge(context),
                const SizedBox(height: 16),

                // Company Name Field
                _buildInputField(
                  context,
                  'COMPANY NAME',
                  _companyController,
                  Icons.business_outlined,
                  'Enter registered company name',
                  isCompanyName: true,
                ),
                const SizedBox(height: 12),

                // Staff ID Field
                _buildInputField(
                  context,
                  'EMPLOYEE ID',
                  _idController,
                  Icons.person_outline,
                  'Staff ID or Username',
                ),
                const SizedBox(height: 12),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                              color: const Color(0xFFB91C1C),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Secure PIN Field
                _buildInputField(
                  context,
                  'SECURITY PIN',
                  _pinController,
                  Icons.lock_outline,
                  '• • • •',
                  isPassword: true,
                ),
                const SizedBox(height: 16),

                // Clock In / Clock Out Buttons
                Row(
                  children: [
                    Expanded(
                      child: _buildAuxButton(
                        context,
                        Icons.login_rounded,
                        'Clock In',
                        onTap: () => _handleClockAction('clock_in'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildAuxButton(
                        context,
                        Icons.logout_rounded,
                        'Clock Out',
                        onTap: () => _handleClockAction('clock_out'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Submit / Login Action Button (Solid & Borderless)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.login_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'SIGN IN TO REGISTER',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // Right side of Console: Keypad
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: _buildKeypadSection(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalBadge(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final isManager = config?.isManagerMode ?? true;
    final tillCode = config?.terminalName ?? 'TILL-01';
    final serverIp = config?.serverIp ?? '127.0.0.1';

    final badgeColor = isManager
        ? const Color(0xFF1D4ED8)
        : const Color(0xFF059669);
    final containerBg = isDark
        ? badgeColor.withValues(alpha: 0.15)
        : badgeColor.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isManager
                      ? 'STORE HUB • MASTER POS SERVER'
                      : 'CASHIER TILL • $tillCode',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: badgeColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isManager
                      ? '${config?.businessName ?? 'Main Store'} (bhfId: ${config?.bhfId ?? '00'})'
                      : 'Connected to Master POS Host ($serverIp:8080)',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            isManager ? Icons.hub_rounded : Icons.point_of_sale_rounded,
            size: 16,
            color: badgeColor,
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(
    BuildContext context,
    String label,
    TextEditingController controller,
    IconData icon,
    String hint, {
    bool isPassword = false,
    bool isTpin = false,
    bool isCompanyName = false,
    int maxLength = 4,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final int? maxLen = isPassword
      ? 6
      : isCompanyName
        ? null
        : isTpin
          ? 10
          : maxLength;
    final errorText = isPassword
        ? 'Security PIN cannot exceed 6 digits'
        : isTpin
            ? 'TPIN cannot exceed 10 digits'
        : isCompanyName
          ? 'Company name is too long'
          : 'Staff ID cannot exceed 4 characters';
    final fieldBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              isPassword
                  ? 'MAX 6 DIGITS'
                  : isCompanyName
                      ? 'LOOKUP BY NAME'
                      : 'MAX $maxLen DIGITS',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            readOnly: isPassword, // PIN entered via keypad
            maxLength: maxLen,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
            keyboardType: isPassword || isTpin
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: [
              if (isPassword || isTpin)
                FilteringTextInputFormatter.digitsOnly,
              if (maxLen != null)
                _MaxLengthFormatter(maxLen, () {
                setState(() {
                  _errorMessage = errorText;
                });
                }),
            ],
            style: GoogleFonts.inter(
              color: theme.colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: isPassword ? 6 : 1,
            ),
            decoration: InputDecoration(
              hintText: hint.toUpperCase(),
              hintStyle: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
                fontSize: 12,
                letterSpacing: 0.5,
              ),
              prefixIcon: Icon(
                icon,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: fieldBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: primaryAccent, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuxButton(
    BuildContext context,
    IconData icon,
    String label, {
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C283D) : const Color(0xFFE2E8F0);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadSection(BuildContext context) {
    const primaryAccent = Color(0xFF1D4ED8);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PIN PAD',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: primaryAccent,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              '6 DIGITS MAX',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.35,
          children: [
            ...List.generate(
              9,
              (index) => _buildKeyItem(context, (index + 1).toString()),
            ),
            _buildKeyItem(context, 'backspace', isIcon: true),
            _buildKeyItem(context, '0'),
            _buildKeyItem(context, 'check', isIcon: true),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildTextLink(
              context,
              'RESET PIN',
              onTap: () {
                _showInfoDialog(
                  'CREDENTIAL_RECOVERY',
                  'Staff PINs: Must be reset by a Manager in Settings > User Management.\n\nAdmin Reset: If you are the owner and forgot your Admin PIN, use the "ADMIN RECOVERY" button below to enter your 8-digit terminal recovery code.',
                );
              },
            ),
            _buildTextLink(
              context,
              'RESTORE DATA',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => const BackupRestoreModal(),
                );
              },
            ),
            _buildTextLink(
              context,
              'SUPPORT',
              onTap: () {
                _showInfoDialog(
                  'SYSTEM_SUPPORT',
                  'If you are having trouble accessing the terminal, please contact your store administrator.',
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyItem(
    BuildContext context,
    String val, {
    bool isIcon = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final itemBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    return Material(
      color: itemBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _onKeypadTap(val),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          alignment: Alignment.center,
          child: isIcon
              ? Icon(
                  val == 'backspace'
                      ? Icons.backspace_outlined
                      : Icons.check_circle_outline_rounded,
                  color: val == 'check'
                      ? primaryAccent
                      : theme.colorScheme.onSurfaceVariant,
                  size: 18,
                )
              : Text(
                  val,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTextLink(
    BuildContext context,
    String label, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
          decoration: onTap != null ? TextDecoration.underline : null,
          decorationColor: theme.colorScheme.onSurfaceVariant.withValues(
            alpha: 0.4,
          ),
        ),
      ),
    );
  }

  void _showInfoDialog(String title, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: primaryAccent,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: theme.colorScheme.onSurface,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        actions: [
          if (title == 'CREDENTIAL_RECOVERY')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showRecoveryInput();
              },
              child: Text(
                'ADMIN RECOVERY',
                style: GoogleFonts.inter(
                  color: primaryAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'DISMISS',
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRecoveryInput() {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    final fieldBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    const primaryAccent = Color(0xFF1D4ED8);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
        title: Text(
          'ADMIN RECOVERY',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: primaryAccent,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please enter your 8-digit Recovery Code to reset the Admin PIN.',
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: GoogleFonts.jetBrainsMono(
                color: theme.colorScheme.onSurface,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX',
                hintStyle: GoogleFonts.jetBrainsMono(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
                filled: true,
                fillColor: fieldBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: primaryAccent, width: 1.5),
                ),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = controller.text.trim().toUpperCase();
              final db = ref.read(databaseServiceProvider);
              final config = await db.getStoreConfig();

              if (config != null && config.recoveryCodeHash == hashPin(code)) {
                final admin = await db.getAdminUser();
                if (context.mounted) {
                  Navigator.pop(context);
                  if (admin != null) {
                    _showAdminPinReset(admin);
                  }
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid Recovery Code'),
                      backgroundColor: Color(0xFFDC2626),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'VERIFY',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAdminPinReset(User admin) {
    showDialog(
      context: context,
      builder: (context) =>
          ResetPinModal(user: admin, title: 'RECOVER ADMIN ACCESS'),
    );
  }

  Widget _buildHeroBackground() {
    final searchPaths = [
      'assets/images/login_hero.webp',
      'Retail-Terms-every-Modern-Retailer-e1485766463692.webp',
      '${Directory.current.path}/assets/images/login_hero.webp',
      '${Directory.current.path}/Retail-Terms-every-Modern-Retailer-e1485766463692.webp',
      '/home/mrm/Documents/programs/beleka-pos-main/Retail-Terms-every-Modern-Retailer-e1485766463692.webp',
      '/home/mrm/Documents/programs/beleka-pos-main/assets/images/login_hero.webp',
    ];

    for (final path in searchPaths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildHeroPlaceholder(),
          );
        }
      } catch (_) {}
    }

    return Image.asset(
      'assets/images/login_hero.webp',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildHeroPlaceholder(),
    );
  }

  Widget _buildLogoBadge(bool isCompact) {
    final searchPaths = [
      'assets/images/logo.png',
      'beleka logo icon.png',
      '${Directory.current.path}/assets/images/logo.png',
      '${Directory.current.path}/beleka logo icon.png',
      '/home/mrm/Documents/programs/beleka-pos-main/beleka logo icon.png',
      '/home/mrm/Documents/programs/beleka-pos-main/assets/images/logo.png',
    ];

    for (final path in searchPaths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          return Image.file(
            f,
            height: isCompact ? 28 : 40,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.bolt_rounded,
              color: const Color(0xFF60A5FA),
              size: isCompact ? 24 : 32,
            ),
          );
        }
      } catch (_) {}
    }

    return Image.asset(
      'assets/images/logo.png',
      height: isCompact ? 28 : 40,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.bolt_rounded,
        color: const Color(0xFF60A5FA),
        size: isCompact ? 24 : 32,
      ),
    );
  }

  Widget _buildHeroPlaceholder() {
    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: Icon(Icons.storefront_rounded, size: 80, color: Colors.white24),
      ),
    );
  }
}

class _MaxLengthFormatter extends TextInputFormatter {
  final int maxLength;
  final VoidCallback onLimitReached;

  _MaxLengthFormatter(this.maxLength, this.onLimitReached);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > maxLength) {
      onLimitReached();
      return oldValue;
    }
    return newValue;
  }
}
