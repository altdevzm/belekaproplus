import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:beleka_pos/services/hwid_service.dart';
import 'package:beleka_pos/services/license_service.dart';
import 'package:beleka_pos/screens/auth/backup_restore_modal.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  final VoidCallback? onActivated;

  const ActivationScreen({super.key, this.onActivated});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final TextEditingController _tokenController = TextEditingController();
  String _currentHwid = 'Loading HWID...';
  bool _isLoading = false;
  bool _hasCopied = false;
  String? _errorMessage;
  String? _successMessage;
  BelekaLicense? _activatedLicense;
  bool _showDiagnostics = false;
  Map<String, String> _diagnostics = {};
  int _selectedMonths = 12; // 1 to 12 months, or 0 for Lifetime

  @override
  void initState() {
    super.initState();
    _loadHardwareId();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadHardwareId() async {
    final hwidService = ref.read(hwidServiceProvider);
    final hwid = await hwidService.getHardwareId();
    final diag = await hwidService.getHardwareDiagnostics();
    if (mounted) {
      setState(() {
        _currentHwid = hwid;
        _diagnostics = diag;
      });
    }
  }

  Future<void> _handleImportFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: Platform.isAndroid ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isAndroid ? null : ['lic', 'json', 'txt'],
        withData: true, // Crucial for Android 10+ scoped storage in-memory reading
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final picked = result.files.single;
      String content = '';

      if (picked.bytes != null && picked.bytes!.isNotEmpty) {
        content = utf8.decode(picked.bytes!);
      } else if (picked.path != null && picked.path!.isNotEmpty) {
        final file = File(picked.path!);
        if (file.existsSync()) {
          content = await file.readAsString();
        }
      }

      if (content.trim().isEmpty) {
        throw Exception('Selected file is empty or could not be read on this device.');
      }

      await _processActivation(content);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to read license file: $e';
      });
    }
  }

  Future<void> _handleAutoScanStorage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final licenseService = ref.read(licenseServiceProvider);
      final res = await licenseService.verifyCurrentMachineLicense();
      if (res.isValid && res.license != null) {
        setState(() {
          _isLoading = false;
          _successMessage = 'Machine Activated! Verified license for ${res.license!.customer}.';
          _activatedLicense = res.license;
        });
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) {
          if (widget.onActivated != null) {
            widget.onActivated!();
          } else {
            Navigator.of(context).pushReplacementNamed('/login');
          }
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No valid license file found in Downloads or device storage. Please select the file manually or paste the activation code.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Storage scan error: $e';
      });
    }
  }

  Future<void> _handleTokenSubmit() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter an activation code or import a .lic file.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    await _processActivation(token);
  }

  Future<void> _processActivation(String rawText) async {
    final licenseService = ref.read(licenseServiceProvider);
    final result = await licenseService.activateLicense(rawText);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isValid && result.license != null) {
          _successMessage = 'Machine Activated! License verified for ${result.license!.customer}.';
          _activatedLicense = result.license;
          _errorMessage = null;
        } else {
          _errorMessage = result.message;
          _successMessage = null;
        }
      });

      if (result.isValid) {
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) {
          if (widget.onActivated != null) {
            widget.onActivated!();
          } else {
            // Restart / navigate to main app flow
            Navigator.of(context).pushReplacementNamed('/login');
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    const primaryBlue = Color(0xFF2563EB);
    const accentBlue = Color(0xFF3B82F6);
    const highlightBlue = Color(0xFF60A5FA);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Stack(
        children: [
          // Background subtle ambient lights
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentBlue.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.06),
              ),
            ),
          ),

          // Main Center Content
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 24, 
                vertical: isMobile ? 16 : 32,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 680),
                decoration: BoxDecoration(
                  color: const Color(0xFF151F32),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF293548)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(isMobile ? 18 : 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Logo & Brand
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accentBlue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: accentBlue.withValues(alpha: 0.35)),
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: accentBlue,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BELEKA POS ACTIVATION',
                                style: GoogleFonts.manrope(
                                  fontSize: isMobile ? 15 : 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                'HARDWARE-BOUND CRYPTOGRAPHIC LICENSE',
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: isMobile ? 8.5 : 10,
                                  fontWeight: FontWeight.bold,
                                  color: highlightBlue,
                                  letterSpacing: 1.0,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Explanation Notice
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Text(
                        'This POS installation is cryptographically locked to this physical machine. To activate, provide your Hardware ID to your vendor to receive your genuine license.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Hardware ID Card
                    Text(
                      'YOUR MACHINE HARDWARE ID (HWID)',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accentBlue.withValues(alpha: 0.4)),
                      ),
                      child: Flex(
                        direction: isMobile ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment: isMobile ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.memory_rounded, color: accentBlue, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelectableText(
                                  _currentHwid,
                                  style: GoogleFonts.ibmPlexMono(
                                    fontSize: isMobile ? 13 : 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isMobile) const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              final durationStr = _selectedMonths == 0 ? 'Permanent / Lifetime' : '$_selectedMonths Month${_selectedMonths > 1 ? 's' : ''}';
                              final req = 'BELEKA POS ACTIVATION REQUEST\nHardware ID: $_currentHwid\nRequested Term: $durationStr\nMax Tills: 3 Tills (Standard)';
                              Clipboard.setData(ClipboardData(text: req));
                              setState(() => _hasCopied = true);
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) setState(() => _hasCopied = false);
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasCopied ? const Color(0xFF10B981) : primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            icon: Icon(_hasCopied ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                            label: Text(
                              _hasCopied ? 'COPIED REQUEST!' : 'COPY REQUEST',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Subscription Duration Selector (1 to 12 Months)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SELECT DESIRED DURATION',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.white38,
                          ),
                        ),
                        Text(
                          'MAX 3 TILLS INCLUDED',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: highlightBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: accentBlue, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedMonths,
                                dropdownColor: const Color(0xFF151F32),
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down, color: accentBlue),
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                items: [
                                  for (int m = 1; m <= 12; m++)
                                    DropdownMenuItem<int>(
                                      value: m,
                                      child: Text('$m Month${m > 1 ? 's' : ''} License (Up to 3 Tills)'),
                                    ),
                                  const DropdownMenuItem<int>(
                                    value: 0,
                                    child: Text('Permanent / Lifetime (Enterprise)'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedMonths = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Success / Error Feedback Alert
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.inter(color: const Color(0xFFFFB3B5), fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_successMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _successMessage!,
                                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  if (_activatedLicense != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Plan: ${_activatedLicense!.term} • Tills Allowed: ${_activatedLicense!.maxTills} • Branches: ${_activatedLicense!.branches}',
                                      style: GoogleFonts.ibmPlexMono(color: const Color(0xFF34D399), fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Option 1: Import .lic File Button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _handleImportFile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: _isLoading 
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.file_upload_outlined, size: 20),
                        label: Text(
                          'IMPORT LICENSE FILE (.LIC)',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: isMobile ? 12 : 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),

                    if (Platform.isAndroid) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleAutoScanStorage,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentBlue,
                            side: const BorderSide(color: accentBlue, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: Text(
                            'SCAN ANDROID DOWNLOADS / STORAGE',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Divider "OR"
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.08))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR PASTE CODE',
                            style: GoogleFonts.ibmPlexMono(fontSize: 10, color: Colors.white24, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.08))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Option 2: Paste Token Box
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        controller: _tokenController,
                        maxLines: 2,
                        style: GoogleFonts.ibmPlexMono(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Paste BELEKA-LIC-... code here',
                          hintStyle: GoogleFonts.ibmPlexMono(color: Colors.white12, fontSize: 12),
                          contentPadding: const EdgeInsets.all(14),
                          border: InputBorder.none,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.content_paste_rounded, color: Colors.white60, size: 18),
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null && data!.text!.isNotEmpty) {
                                    setState(() {
                                      _tokenController.text = data.text!.trim();
                                    });
                                  }
                                },
                                tooltip: 'Paste from Clipboard',
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_rounded, color: accentBlue),
                                onPressed: _isLoading ? null : _handleTokenSubmit,
                                tooltip: 'Activate Code',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Hardware Diagnostics Expander
                    InkWell(
                      onTap: () => setState(() => _showDiagnostics = !_showDiagnostics),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _showDiagnostics ? 'Hide Hardware Fingerprint' : 'View Hardware Fingerprint Components',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                            ),
                            Icon(
                              _showDiagnostics ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              size: 16,
                              color: Colors.white38,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showDiagnostics) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _diagnostics.entries.map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${e.key}: ',
                                    style: GoogleFonts.ibmPlexMono(fontSize: 10, color: highlightBlue, fontWeight: FontWeight.bold),
                                  ),
                                  Expanded(
                                    child: Text(
                                      e.value.isEmpty ? 'N/A' : e.value,
                                      style: GoogleFonts.ibmPlexMono(fontSize: 10, color: Colors.white60),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Bottom Restore System Backup Link
          Positioned(
            bottom: isMobile ? 10 : 20,
            right: isMobile ? 10 : 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const BackupRestoreModal(),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151F32),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.settings_backup_restore_rounded, color: accentBlue, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'RESTORE SYSTEM BACKUP',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
