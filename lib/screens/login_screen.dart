import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/screens/settings/reset_pin_modal.dart';
import 'package:beleka_pos/screens/auth/backup_restore_modal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:isar/isar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _idController = TextEditingController();
  final _pinController = TextEditingController();
  String _pin = '';
  String? _errorMessage;
  bool _isLoading = false;
  bool _isAdmin = false;
  String? _recognizedName;

  @override
  void initState() {
    super.initState();
    _idController.addListener(_onIdChanged);
  }

  @override
  void dispose() {
    _idController.removeListener(_onIdChanged);
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onIdChanged() async {
    final rawId = _idController.text;
    if (rawId.length > 4) {
      _idController.text = rawId.substring(0, 4);
      _idController.selection = TextSelection.fromPosition(const TextPosition(offset: 4));
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
      final user = users.cast<User?>().firstWhere((u) => u?.numericId == id, orElse: () => null);
      if (user != null) {
        if (_recognizedName != user.name) {
          setState(() {
            _recognizedName = user.name;
            _isAdmin = user.role == 'manager';
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

      // 1. Try local login first
      User? user = await db.login(
        _idController.text.trim(),
        _pin.trim(),
      );

      // 2. If local fails and we have a network connection to manager, try remote login
      if (user == null && networkClient != null) {
        final userData = await networkClient.login(
          _idController.text.trim(),
          _pin.trim(),
          config?.terminalName ?? 'TERMINAL',
        );

        if (userData != null) {
          // Successfully logged in via network.
          // Create/Update user in local database for future offline access.
          final remoteUser = User()
            ..numericId = userData['numericId']
            ..name = userData['name']
            ..role = userData['role']
            ..passwordHash = 'REMOTE_AUTH'; 
          
          await db.isar.writeTxn(() async {
            final existing = await db.isar.users.filter().numericIdEqualTo(remoteUser.numericId).findFirst();
            if (existing != null) {
              remoteUser.id = existing.id;
            }
            await db.isar.users.put(remoteUser);
          });
          user = remoteUser;
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
      final user = users.cast<User?>().firstWhere((u) => u?.numericId == id, orElse: () => null);

      if (user != null) {
        await db.logAttendance(user, type);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${type == 'clock_in' ? 'Clocked IN' : 'Clocked OUT'} successfully for ${user.name}'),
              backgroundColor: const Color(0xFFC1F11D),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0F),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Hero Image & Branding Pane (Full Bleed)
                    Expanded(
                      flex: 5,
                      child: _buildHeroImageSection(),
                    ),
                    // Seam Divider Line
                    Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    // Right Authentication Terminal Pane (Full Bleed)
                    Expanded(
                      flex: 6,
                      child: Container(
                        color: const Color(0xFF111115),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: _buildRightConsole(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Compact layout for smaller screens / vertical displays
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 240,
                      child: _buildHeroImageSection(isCompact: true),
                    ),
                    Container(
                      color: const Color(0xFF111115),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: _buildRightConsole(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Bottom Right Corner Floating Backup Restore Action Button
          Positioned(
            bottom: 20,
            right: 24,
            child: _buildBottomRightRestoreButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRightRestoreButton() {
    return TextButton.icon(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => const BackupRestoreModal(),
        );
      },
      icon: const Icon(Icons.settings_backup_restore, size: 16, color: Colors.white38),
      label: Text(
        'RESTORE BACKUP',
        style: GoogleFonts.ibmPlexMono(fontSize: 10, color: Colors.white38),
      ),
    );
  }

  Widget _buildHeroImageSection({bool isCompact = false}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Retail Image (Fail-safe direct file & asset loader)
        _buildHeroBackground(),

        // Multi-layered Gradient Overlay for High Readability & Seam Blend
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.40),
                Colors.black.withValues(alpha: 0.65),
                const Color(0xFF0E0E12).withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.4),
                const Color(0xFF141418).withValues(alpha: 0.8),
              ],
              stops: const [0.0, 0.7, 1.0],
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
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: _buildLogoBadge(isCompact),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BELEKA POS',
                        style: GoogleFonts.manrope(
                          fontSize: isCompact ? 16 : 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'RETAIL OPERATING SYSTEM',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: isCompact ? 8 : 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFC1F11D),
                          letterSpacing: 2,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFC1F11D),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'NEXT-GEN COMMERCE PLATFORM',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: const Color(0xFFC1F11D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'High-Speed Checkout\n& Intelligent Retail.',
                      style: GoogleFonts.manrope(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Optimized for high-volume transactions, real-time inventory control, and seamless multi-terminal synchronization.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Feature highlights chips
                    _buildFeaturePill(Icons.bolt_rounded, 'Ultra-Low Latency Offline First POS'),
                    const SizedBox(height: 10),
                    _buildFeaturePill(Icons.sync_alt_rounded, 'Automatic Terminal Synchronization'),
                    const SizedBox(height: 10),
                    _buildFeaturePill(Icons.analytics_rounded, 'Real-time Stock & Financial Insights'),
                  ],
                ),

                // Bottom Status Line
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: Color(0xFFC1F11D)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'LOCAL DATABASE ENCRYPTED • ZERO LATENCY',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.7),
                            letterSpacing: 1,
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
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFFCFBDFF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightConsole() {
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
                // Recognized Employee or Default Header
                if (_recognizedName != null) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 12, color: Color(0xFFC1F11D)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'STAFF IDENTIFIED',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: const Color(0xFFC1F11D),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _recognizedName!.toUpperCase(),
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else ...[
                  Text(
                    'TERMINAL AUTHENTICATION',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Enter your Staff ID and PIN to begin shift',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Role Toggle
                _buildRoleToggle(),
                const SizedBox(height: 14),

                // Staff ID Field
                _buildInputField('EMPLOYEE ID', _idController, Icons.person_outline, 'Staff ID or Username'),
                const SizedBox(height: 8),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Secure PIN Field
                _buildInputField('SECURITY PIN', _pinController, Icons.lock_outline, '• • • •', isPassword: true),
                const SizedBox(height: 16),

                // Clock In / Clock Out Buttons
                Row(
                  children: [
                    Expanded(
                      child: _buildAuxButton(
                        Icons.login_rounded,
                        'Clock In',
                        onTap: () => _handleClockAction('clock_in'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildAuxButton(
                        Icons.logout_rounded,
                        'Clock Out',
                        onTap: () => _handleClockAction('clock_out'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Submit / Login Action Button
                Material(
                  color: const Color(0xFFC1F11D),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _isLoading ? null : _handleLogin,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.login_rounded, size: 18, color: Colors.black),
                                const SizedBox(width: 8),
                                Text(
                                  'SIGN IN TO REGISTER',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // Right side of Console: Keypad & Help
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: _buildKeypadSection(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(child: _buildRoleButton('Cashier', !_isAdmin)),
          Expanded(child: _buildRoleButton('Admin & Manager', _isAdmin)),
        ],
      ),
    );
  }

  Widget _buildRoleButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _isAdmin = label.startsWith('Admin')),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 0.12)) : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon, String hint, {bool isPassword = false}) {
    final maxLen = isPassword ? 6 : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            Text(
              isPassword ? 'MAX 6 DIGITS' : 'MAX 4 CHARS',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            readOnly: isPassword, // PIN entered via keypad
            maxLength: maxLen,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            keyboardType: isPassword ? TextInputType.number : TextInputType.text,
            inputFormatters: [
              if (isPassword) FilteringTextInputFormatter.digitsOnly,
              _MaxLengthFormatter(maxLen, () {
                setState(() {
                  _errorMessage = isPassword 
                      ? 'Security PIN cannot exceed 6 digits' 
                      : 'Staff ID cannot exceed 4 characters';
                });
              }),
            ],
            style: GoogleFonts.ibmPlexMono(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: isPassword ? 6 : 1,
            ),
            decoration: InputDecoration(
              hintText: hint.toUpperCase(),
              hintStyle: GoogleFonts.ibmPlexMono(
                color: Colors.white.withValues(alpha: 0.12),
                fontSize: 11,
                letterSpacing: 1,
              ),
              prefixIcon: Icon(icon, size: 16, color: const Color(0xFFCFBDFF).withValues(alpha: 0.5)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.4),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFC1F11D), width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuxButton(IconData icon, String label, {required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'PIN PAD',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFC1F11D),
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '6 DIGITS MAX',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.3),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            ...List.generate(9, (index) => _buildKeyItem((index + 1).toString())),
            _buildKeyItem('backspace', isIcon: true),
            _buildKeyItem('0'),
            _buildKeyItem('check', isIcon: true),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildTextLink('RESET PIN', onTap: () {
              _showInfoDialog(
                'CREDENTIAL_RECOVERY',
                'Staff PINs: Must be reset by a Manager in Settings > User Management.\n\nAdmin Reset: If you are the owner and forgot your Admin PIN, use the "ADMIN RECOVERY" button below to enter your 8-digit terminal recovery code.',
              );
            }),
            _buildTextLink('RESTORE DATA', onTap: () {
              showDialog(
                context: context,
                builder: (context) => const BackupRestoreModal(),
              );
            }),
            _buildTextLink('SUPPORT', onTap: () {
              _showInfoDialog(
                'SYSTEM_SUPPORT',
                'If you are having trouble accessing the terminal, please contact your store administrator.',
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyItem(String val, {bool isIcon = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeypadTap(val),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isIcon ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isIcon
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFCFBDFF).withValues(alpha: 0.08),
            ),
          ),
          alignment: Alignment.center,
          child: isIcon
              ? Icon(
                  val == 'backspace' ? Icons.backspace_outlined : Icons.check_circle_outline_rounded,
                  color: val == 'check' ? const Color(0xFFC1F11D) : Colors.white70,
                  size: 20,
                )
              : Text(
                  val,
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTextLink(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: Colors.white.withValues(alpha: 0.35),
          decoration: onTap != null ? TextDecoration.underline : null,
          decorationColor: Colors.white.withValues(alpha: 0.15),
        ),
      ),
    );
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        title: Text(
          title,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFC1F11D),
            letterSpacing: 2,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5),
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
                style: GoogleFonts.manrope(color: const Color(0xFFC1F11D), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'DISMISS',
              style: GoogleFonts.manrope(
                color: title == 'CREDENTIAL_RECOVERY' ? Colors.white24 : const Color(0xFFC1F11D),
                fontWeight: FontWeight.bold,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        title: Text(
          'ADMIN RECOVERY',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D), fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please enter your 8-digit Recovery Code to reset the Admin PIN.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              style: GoogleFonts.ibmPlexMono(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX',
                hintStyle: GoogleFonts.ibmPlexMono(color: Colors.white10),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.02),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: GoogleFonts.manrope(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12)),
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
                    const SnackBar(content: Text('Invalid Recovery Code'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC1F11D),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('VERIFY', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showAdminPinReset(User admin) {
    showDialog(
      context: context,
      builder: (context) => ResetPinModal(
        user: admin,
        title: 'RECOVER ADMIN ACCESS',
      ),
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
            errorBuilder: (context, error, stackTrace) => _buildHeroPlaceholder(),
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
              color: const Color(0xFFC1F11D), 
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
        color: const Color(0xFFC1F11D), 
        size: isCompact ? 24 : 32,
      ),
    );
  }

  Widget _buildHeroPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A22),
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
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > maxLength) {
      onLimitReached();
      return oldValue;
    }
    return newValue;
  }
}
