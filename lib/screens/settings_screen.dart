import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/screens/settings/store_config_modal.dart';
import 'package:beleka_pos/screens/settings/user_management_modal.dart';
import 'package:beleka_pos/screens/settings/printer_settings_modal.dart';
import 'package:beleka_pos/screens/settings/loyalty_settings_modal.dart';
import 'package:beleka_pos/screens/settings/backup_settings_modal.dart';
import 'package:beleka_pos/screens/settings/license_info_modal.dart';
import 'package:beleka_pos/screens/settings/network_sync_modal.dart';
import 'package:beleka_pos/widgets/zra_tax_config_modal.dart';
import 'package:beleka_pos/screens/settings/scale_settings_modal.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

import 'package:beleka_pos/core/core.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isOwnerProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sc = getScreenClass(constraints.maxWidth);
                final cols = switch (sc) {
                  ScreenClass.compact || ScreenClass.mobile => 1,
                  ScreenClass.tablet => 2,
                  ScreenClass.desktop => 3,
                  ScreenClass.ultraWide => 4,
                };
                final ratio = switch (sc) {
                  ScreenClass.compact || ScreenClass.mobile => 2.2,
                  ScreenClass.tablet => 1.5,
                  _ => 1.3,
                };

                return GridView.count(
                  crossAxisCount: cols,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: ratio,
                  children: [
                    _buildSettingsCard(
                      context,
                      'System License',
                      'View hardware ID, activation status and plan',
                      Icons.verified_user_rounded,
                      const Color(0xFFC1F11D),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const LicenseInfoModal(),
                      ),
                      buttonLabel: 'View License',
                    ),
                    if (isOwner)
                      _buildSettingsCard(
                        context,
                        'Tax & Compliance',
                        'Configure VAT, GST and tax regulations',
                        Icons.account_balance_rounded,
                        const Color(0xFFC6B4FF),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const StoreConfigModal(),
                        ),
                      ),
                    _buildSettingsCard(
                      context,
                      'Printers & Hardware',
                      'Manage thermal printers and scanners',
                      Icons.print_rounded,
                      const Color(0xFF4ADE80),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const PrinterSettingsModal(),
                      ),
                    ),
                    _buildSettingsCard(
                      context,
                      'Electronic Scale',
                      'Configure RS232, USB and TCP POS weight scales',
                      Icons.scale_rounded,
                      const Color(0xFFC1F11D),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const ScaleSettingsModal(),
                      ),
                      buttonLabel: 'Configure Scale',
                    ),
                    _buildSettingsCard(
                      context,
                      'User Management',
                      'Add or edit staff accounts and permissions',
                      Icons.people_rounded,
                      const Color(0xFF5BBEEA),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const UserManagementModal(),
                      ),
                    ),
                    if (isOwner)
                      _buildSettingsCard(
                        context,
                        'Store Information',
                        'Update company name, address and details',
                        Icons.storefront_rounded,
                        const Color(0xFFFFB3B5),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const StoreConfigModal(),
                        ),
                      ),
                    _buildSettingsCard(
                      context,
                      'Export Data',
                      'Export transactions to CSV for accounting',
                      Icons.download_rounded,
                      const Color(0xFF7DD3A8),
                      onPressed: () async {
                        final db = ref.read(databaseServiceProvider);
                        final transactions = await db.getRecentTransactions(limit: 10000);
                        await ref.read(exportServiceProvider).exportTransactionsToCsv(transactions);
                      },
                      buttonLabel: 'Export CSV',
                    ),
                    _buildSettingsCard(
                      context,
                      'Loyalty Programs',
                      'Setup customer rewards and discount points',
                      Icons.card_giftcard_rounded,
                      Colors.amber,
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const LoyaltySettingsModal(),
                      ),
                    ),
                    _buildSettingsCard(
                      context,
                      'Backup & Security',
                      'Configure automated database backups and storage',
                      Icons.security_rounded,
                      Colors.orangeAccent,
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const BackupSettingsModal(),
                      ),
                    ),
                    if (isOwner)
                      _buildSettingsCard(
                        context,
                        'DigiTax & ZRA Smart Invoice',
                        'Configure DigiTax API Key, Environment & Live Tax Rates',
                        Icons.receipt_long_rounded,
                        const Color(0xFF10B981),
                        buttonLabel: 'Configure',
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const ZraTaxConfigModal(),
                        ),
                      ),
                _buildSettingsCard(
                  context,
                  'Network & Multi-Till Sync',
                  'Configure Master Server IP, Cashier Client Tills & Live LAN Sync',
                  Icons.hub_rounded,
                  const Color(0xFF6366F1),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const NetworkSyncModal(),
                  ),
                ),
                ],
              );
            },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color accent, {
    VoidCallback? onPressed,
    String buttonLabel = 'Configure',
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.35),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed ?? () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF1A1A1E),
                minimumSize: const Size(double.infinity, 42),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Text(
                buttonLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
