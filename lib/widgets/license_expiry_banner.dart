import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/license_service.dart';
import 'package:beleka_pos/screens/auth/activation_screen.dart';
import 'package:beleka_pos/main.dart';

/// Riverpod provider that periodically re-verifies the license every hour
/// while the app is running. If the license has expired mid-session, it
/// automatically invalidates appStartupProvider — locking the app.
final licensePeriodicCheckProvider = Provider<void>((ref) {
  final licenseService = ref.read(licenseServiceProvider);

  Timer? timer;

  void checkNow() async {
    try {
      final result = await licenseService.verifyCurrentMachineLicense();
      if (!result.isValid) {
        // License expired or tampered mid-session → force re-lock
        ref.invalidate(appStartupProvider);
      }
    } catch (_) {}
  }

  // Check every hour
  timer = Timer.periodic(const Duration(hours: 1), (_) => checkNow());

  ref.onDispose(() => timer?.cancel());
});

/// A slim banner that appears above main content only when the active license
/// is about to expire (1 week / 7 days or fewer remaining).
/// Completely hidden when license is healthy (>7 days) or permanent.
class LicenseExpiryBanner extends ConsumerWidget {
  const LicenseExpiryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kick off the periodic re-check while shell is mounted
    ref.watch(licensePeriodicCheckProvider);

    final licenseService = ref.read(licenseServiceProvider);
    final license = licenseService.activeLicense;

    // No banner for permanent, no-license, or healthy (>7 days) licenses
    if (license == null || license.expiresAt == null) return const SizedBox.shrink();
    if (license.isExpired) return const SizedBox.shrink(); // handled by startup gate
    final days = license.remainingDays;
    // Only display reminder 1 week before expiry (≤7 days)
    if (days > 7) return const SizedBox.shrink();

    final isCritical = days <= 3;

    final bgColor = isCritical
        ? const Color(0xFF3B0A0A)
        : const Color(0xFF2D1F00);
    final borderColor = isCritical
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    final iconColor = isCritical
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    final textColor = isCritical
        ? const Color(0xFFFCA5A5)
        : const Color(0xFFFDE68A);

    final message = isCritical
        ? '⚠️ LICENSE EXPIRING IN $days DAY${days != 1 ? 'S' : ''}! Renew immediately to avoid a system lock.'
        : '🕒 License expires in $days days. Please renew before expiry.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning_rounded : Icons.schedule_rounded,
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _openActivationScreen(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'RENEW',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openActivationScreen(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivationScreen(
          onActivated: () {
            ref.invalidate(appStartupProvider);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

/// A compact card for the Dashboard showing license expiry countdown.
/// Only displayed when the license is about to expire (1 week / 7 days or fewer)
/// or if it has expired. Hidden when healthy (>7 days) to keep dashboard clean.
class LicenseExpiryDashboardCard extends ConsumerWidget {
  const LicenseExpiryDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseService = ref.read(licenseServiceProvider);
    final license = licenseService.activeLicense;

    if (license == null || license.expiresAt == null) return const SizedBox.shrink();

    final days = license.isExpired ? 0 : license.remainingDays;

    // Do NOT show reminder if there is still plenty of time (>7 days remaining)
    if (!license.isExpired && days > 7) return const SizedBox.shrink();

    final isCritical = days <= 3;
    final isExpired = license.isExpired;

    final Color primaryColor;
    final Color bgColor;
    final Color borderColor;
    final IconData icon;
    final String statusLabel;

    if (isExpired) {
      primaryColor = const Color(0xFFEF4444);
      bgColor = const Color(0xFF3B0A0A);
      borderColor = const Color(0xFFEF4444);
      icon = Icons.lock_rounded;
      statusLabel = 'EXPIRED';
    } else if (isCritical) {
      primaryColor = const Color(0xFFEF4444);
      bgColor = const Color(0xFF2D0A0A);
      borderColor = const Color(0xFFEF4444);
      icon = Icons.warning_rounded;
      statusLabel = 'CRITICAL';
    } else {
      primaryColor = const Color(0xFFF59E0B);
      bgColor = const Color(0xFF1F1400);
      borderColor = const Color(0xFFF59E0B);
      icon = Icons.schedule_rounded;
      statusLabel = 'EXPIRING SOON';
    }

    final expiryStr = license.expiresAt != null
        ? license.expiresAt!.toLocal().toString().substring(0, 10)
        : 'Never';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'LICENSE STATUS',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: primaryColor.withValues(alpha: 0.8),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: primaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isExpired
                      ? 'License expired on $expiryStr'
                      : '$days day${days != 1 ? 's' : ''} remaining · Expires: $expiryStr',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                if (!isExpired && days <= 7) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (days / 7).clamp(0.0, 1.0),
                      backgroundColor: primaryColor.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      minHeight: 4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Consumer(
            builder: (context, ref, _) => GestureDetector(
              onTap: () => _openActivation(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isExpired ? 'ACTIVATE' : 'RENEW',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: isExpired ? Colors.white : Colors.black,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openActivation(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivationScreen(
          onActivated: () {
            ref.invalidate(appStartupProvider);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
