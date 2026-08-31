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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final license = _result?.license;
    final hwid = _result?.currentHwid ?? 'Loading...';

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : SingleChildScrollView(
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
                                child: Icon(Icons.verified_user_outlined, color: primaryColor, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SYSTEM LICENSE & TIER',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'AUTHENTIC HARDWARE ACTIVATION',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor,
                                        letterSpacing: 0.5,
                                      ),
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
                          icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
                    const SizedBox(height: 16),

                    // License Status Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (_result?.isValid ?? false) ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (_result?.isValid ?? false) ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (_result?.isValid ?? false) ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            color: (_result?.isValid ?? false) ? const Color(0xFF059669) : const Color(0xFFDC2626),
                            size: 24,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (_result?.isValid ?? false) ? 'GENUINE & ACTIVATED' : 'LICENSE LOCKED / EXPIRED',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: (_result?.isValid ?? false) ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _result?.message ?? '',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: (_result?.isValid ?? false) ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Metadata Details
                    _buildDetailRow(context, 'Customer Name', license?.customer ?? 'Unassigned'),
                    _buildDetailRow(context, 'Product', license?.product ?? 'Beleka Pro POS'),
                    _buildDetailRow(context, 'Installation ID', license?.installationId ?? 'N/A'),
                    _buildDetailRow(context, 'License Term', license?.term ?? 'N/A'),
                    _buildDetailRow(
                      context,
                      'Active Duration', 
                      license?.months != null 
                          ? '${license!.months} Month${license.months! > 1 ? 's' : ''}'
                          : (license?.isPermanent == true ? 'Permanent Lifetime' : 'Custom Period'),
                    ),
                    _buildDetailRow(
                      context,
                      'Expiry Date',
                      license?.expiresAt != null
                          ? '${license!.expiresAt!.toLocal().toString().substring(0, 10)} (${license.remainingDays} days left)'
                          : 'Never Expires (Permanent)',
                    ),
                    _buildDetailRow(context, 'Max Tills Allowed', '${license?.maxTills ?? 3} Tills (Standard Limit: 3)'),
                    _buildDetailRow(context, 'Authorized Branches', '${license?.branches ?? 1} Branch'),
                    _buildDetailRow(context, 'Issued Date', license != null ? '${license.issuedAt.year}-${license.issuedAt.month.toString().padLeft(2, '0')}-${license.issuedAt.day.toString().padLeft(2, '0')}' : 'N/A'),

                    const SizedBox(height: 14),

                    // Machine HWID Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.memory_rounded, color: primaryColor, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'HWID:',
                            style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              hwid,
                              style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
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
                              style: GoogleFonts.inter(fontSize: 11, color: primaryColor, fontWeight: FontWeight.bold),
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
                              color: primaryColor,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _showHardwareDetails ? 'Hide Machine Hardware Details' : 'View Machine Hardware Components',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: primaryColor,
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
                          color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MACHINE HARDWARE COMPONENTS',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: theme.colorScheme.onSurfaceVariant,
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
                                    style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      e.value,
                                      textAlign: TextAlign.end,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
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

                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface,
                              side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: const Text('Re-Activate / Upgrade', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
