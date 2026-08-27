import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/license_service.dart';
import 'package:beleka_pos/services/hwid_service.dart';
import 'package:beleka_pos/screens/auth/activation_screen.dart';

class LicenseInfoModal extends ConsumerStatefulWidget {
  const LicenseInfoModal({super.key});

  @override
  ConsumerState<LicenseInfoModal> createState() => _LicenseInfoModalState();
}

class _LicenseInfoModalState extends ConsumerState<LicenseInfoModal> {
  bool _isLoading = true;
  LicenseVerificationResult? _result;
  Map<String, String>? _hardwareDiag;
  bool _showHardwareDetails = false;
  bool _hasCopiedHwid = false;

  @override
  void initState() {
    super.initState();
    _loadLicenseInfo();
  }

  Future<void> _loadLicenseInfo() async {
    final licenseService = ref.read(licenseServiceProvider);
    final hwidService = ref.read(hwidServiceProvider);
    final res = await licenseService.verifyCurrentMachineLicense();
    final diag = await hwidService.getHardwareDiagnostics();
    if (mounted) {
      setState(() {
        _result = res;
        _hardwareDiag = diag;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final license = _result?.license;
    final hwid = _result?.currentHwid ?? 'Loading...';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 580,
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(32),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.verified_user_outlined, color: Color(0xFFC1F11D), size: 22),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SYSTEM LICENSE',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                'AUTHENTIC HARDWARE ACTIVATION',
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFC1F11D),
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white24),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // License Status Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: (_result?.isValid ?? false)
                          ? const Color(0xFF4ADE80).withValues(alpha: 0.08)
                          : Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (_result?.isValid ?? false)
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.3)
                            : Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (_result?.isValid ?? false) ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          color: (_result?.isValid ?? false) ? const Color(0xFF4ADE80) : Colors.redAccent,
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (_result?.isValid ?? false) ? 'GENUINE & ACTIVATED' : 'LICENSE LOCKED / EXPIRED',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: (_result?.isValid ?? false) ? const Color(0xFF4ADE80) : Colors.redAccent,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _result?.message ?? '',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Metadata Details
                  _buildDetailRow('Customer Name', license?.customer ?? 'Unassigned'),
                  _buildDetailRow('Product', license?.product ?? 'Beleka Pro POS'),
                  _buildDetailRow('Installation ID', license?.installationId ?? 'N/A'),
                  _buildDetailRow('License Term', license?.term ?? 'N/A'),
                  _buildDetailRow(
                    'Active Duration', 
                    license?.months != null 
                        ? '${license!.months} Month${license.months! > 1 ? 's' : ''}'
                        : (license?.isPermanent == true ? 'Permanent Lifetime' : 'Custom Period'),
                  ),
                  _buildDetailRow(
                    'Expiry Date',
                    license?.expiresAt != null
                        ? '${license!.expiresAt!.toLocal().toString().substring(0, 10)} (${license.remainingDays} days left)'
                        : 'Never Expires (Permanent)',
                  ),
                  _buildDetailRow('Max Tills Allowed', '${license?.maxTills ?? 3} Tills (Standard Limit: 3)'),
                  _buildDetailRow('Authorized Branches', '${license?.branches ?? 1} Branch'),
                  _buildDetailRow('Issued Date', license != null ? '${license.issuedAt.year}-${license.issuedAt.month.toString().padLeft(2, '0')}-${license.issuedAt.day.toString().padLeft(2, '0')}' : 'N/A'),

                  const SizedBox(height: 14),

                  // Machine HWID Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.memory_rounded, color: Color(0xFFC1F11D), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'HWID:',
                          style: GoogleFonts.ibmPlexMono(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            hwid,
                            style: GoogleFonts.ibmPlexMono(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: hwid));
                            setState(() => _hasCopiedHwid = true);
                            Future.delayed(const Duration(seconds: 2), () {
                              if (mounted) setState(() => _hasCopiedHwid = false);
                            });
                          },
                          child: Text(
                            _hasCopiedHwid ? 'COPIED' : 'COPY',
                            style: GoogleFonts.ibmPlexMono(fontSize: 10, color: const Color(0xFFC1F11D), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Expandable Hardware Details Section
                  InkWell(
                    onTap: () => setState(() => _showHardwareDetails = !_showHardwareDetails),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _showHardwareDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            color: const Color(0xFFC1F11D),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showHardwareDetails ? 'Hide Machine Hardware Details' : 'View Machine Hardware Components',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFC1F11D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showHardwareDetails && _hardwareDiag != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MACHINE HARDWARE COMPONENTS',
                            style: GoogleFonts.manrope(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Colors.white38,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._hardwareDiag!.entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  e.key,
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    textAlign: TextAlign.end,
                                    style: GoogleFonts.ibmPlexMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              builder: (ctx) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: ActivationScreen(
                                  onActivated: () {
                                    Navigator.pop(ctx);
                                  },
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC1F11D),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Re-Activate / Upgrade', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
          ),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
