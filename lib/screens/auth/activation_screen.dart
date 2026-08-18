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
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lic', 'json', 'txt'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      await _processActivation(content);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to read license file: $e';
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
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D11),
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
                color: const Color(0xFFC1F11D).withValues(alpha: 0.04),
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
                color: Colors.blueAccent.withValues(alpha: 0.03),
              ),
            ),
          ),

          // Main Center Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 680),
                decoration: BoxDecoration(
                  color: const Color(0xFF141418),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(36),
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
                            color: const Color(0xFFC1F11D).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.3)),
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: Color(0xFFC1F11D),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BELEKA POS ACTIVATION',
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              'HARDWARE-BOUND CRYPTOGRAPHIC LICENSE',
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFC1F11D),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Explanation Notice
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Text(
                        'This POS installation is cryptographically locked to this physical machine. To activate, provide your Hardware ID to your vendor to receive your genuine license.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.65),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

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
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.memory_rounded, color: Color(0xFFC1F11D), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SelectableText(
                              _currentHwid,
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _currentHwid));
                              setState(() => _hasCopied = true);
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) setState(() => _hasCopied = false);
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasCopied ? const Color(0xFF4ADE80) : const Color(0xFFC1F11D),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: Icon(_hasCopied ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                            label: Text(
                              _hasCopied ? 'COPIED!' : 'COPY HWID',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

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
                          color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 22),
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
                                      'Plan: ${_activatedLicense!.term} • Branches: ${_activatedLicense!.branches}',
                                      style: GoogleFonts.ibmPlexMono(color: const Color(0xFF4ADE80), fontSize: 11),
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
                          backgroundColor: const Color(0xFFC1F11D),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: _isLoading 
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.file_upload_outlined, size: 20),
                        label: Text(
                          'IMPORT LICENSE FILE (.LIC)',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
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
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFFC1F11D)),
                            onPressed: _isLoading ? null : _handleTokenSubmit,
                            tooltip: 'Activate Code',
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
                                    style: GoogleFonts.ibmPlexMono(fontSize: 10, color: const Color(0xFFC1F11D), fontWeight: FontWeight.bold),
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

          // Bottom-Right Corner: Backup Restore Action
          Positioned(
            bottom: 20,
            right: 20,
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141418),
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
                      const Icon(Icons.settings_backup_restore_rounded, color: Color(0xFFC1F11D), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'RESTORE SYSTEM BACKUP',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          letterSpacing: 1,
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
