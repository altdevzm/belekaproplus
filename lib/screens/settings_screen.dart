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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isOwnerProvider);
    final isManager = ref.watch(isManagerProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (isOwner || isManager) ? 'Settings' : 'Hardware & Till Settings',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (isOwner || isManager)
                    ? 'Manage store configuration, tax compliance, hardware and network sync'
                    : 'Configure local thermal receipt printers, cash drawers, scales and barcode scanners for this till',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 200,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                  children: [
                    // Printers & Hardware (Accessible to Cashiers & Managers)
                    _buildSettingsCard(
                      context,
                      'Printers & Hardware',
                      'Manage thermal receipt printers, cash drawer kick pulse and scanners',
                      Icons.print_rounded,
                      const Color(0xFF4ADE80),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const PrinterSettingsModal(),
                      ),
                    ),
                    // Electronic Scale (Accessible to Cashiers & Managers)
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
                    // Administrative / Manager-Only Settings
                    if (isOwner || isManager) ...[
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
                        'User Management',
                        'Add or edit staff accounts and permissions',
                        Icons.people_rounded,
                        const Color(0xFF5BBEEA),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const UserManagementModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'Store Information',
                        'Update company name, branch details and terminal',
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
                        'Loyalty & Rewards',
                        'Setup customer points, tiers and discounts',
                        Icons.loyalty_rounded,
                        const Color(0xFFFFC078),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const LoyaltySettingsModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'Backup & Reset',
                        'Export database snapshots and manage recovery',
                        Icons.backup_rounded,
                        const Color(0xFF4ADE80),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const BackupSettingsModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'DigiTax & ZRA Smart Invoice',
                        'Configure DigiTax API Key, Branch Code (bhfId) & Live Tax Rates',
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
                        'Master Hub & Multi-POS Sync',
                        'Configure Master Server IP, Cashier Client Tills & Live LAN Sync',
                        Icons.hub_rounded,
                        const Color(0xFF6366F1),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const NetworkSyncModal(),
                        ),
                      ),
                    ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.4),
              height: 1.3,
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
                minimumSize: const Size(double.infinity, 38),
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
