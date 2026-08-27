import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/screens/dashboard_screen.dart';
import 'package:beleka_pos/screens/inventory_screen.dart';
import 'package:beleka_pos/screens/sales_screen.dart';
import 'package:beleka_pos/screens/settings_screen.dart';
import 'package:beleka_pos/screens/reports_screen.dart';
import 'package:beleka_pos/screens/terminals_screen.dart';
import 'package:beleka_pos/screens/purchases_screen.dart';
import 'package:beleka_pos/screens/accounts_screen.dart';
import 'package:beleka_pos/screens/branches_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/models/models.dart';
import 'dart:io';

import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/core/core.dart';

enum ScreenType { dashboard, sales, inventory, purchases, accounts, branches, terminals, settings, reports }

final navigationProvider = StateProvider<ScreenType>((ref) {
  // Cashiers default to Sales screen
  final user = ref.watch(authProvider);
  if (user?.role == 'cashier') return ScreenType.sales;
  return ScreenType.dashboard;
});

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentScreen = ref.watch(navigationProvider);
    final theme = Theme.of(context);
    final isManager = ref.watch(isManagerProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AdaptiveLayout(
        compact: (ctx) => _buildMobileLayout(context, ref, currentScreen, isManager, isCompact: true),
        mobile: (ctx) => _buildMobileLayout(context, ref, currentScreen, isManager, isCompact: false),
        tablet: (ctx) => _buildTabletLayout(context, ref, currentScreen, isManager),
        desktop: (ctx) => _buildDesktopLayout(context, ref, currentScreen, isManager, isUltraWide: false),
        ultraWide: (ctx) => _buildDesktopLayout(context, ref, currentScreen, isManager, isUltraWide: true),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    WidgetRef ref,
    ScreenType current,
    bool isManager, {
    required bool isCompact,
  }) {
    final user = ref.watch(authProvider);
    final destinations = _getNavigationDestinations(user);
    final selectedIndex = _getSelectedIndex(current, destinations);

    return Column(
      children: [
        _buildStatusBar(ref, isCompact: isCompact),
        Expanded(child: _buildMainContent(current)),
        NavigationBar(
          selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
          height: 64,
          backgroundColor: const Color(0xFF111114),
          indicatorColor: ref.watch(accentColorProvider).withValues(alpha: 0.18),
          labelBehavior: isCompact
              ? NavigationDestinationLabelBehavior.alwaysHide
              : NavigationDestinationLabelBehavior.onlyShowSelected,
          onDestinationSelected: (i) {
            HapticFeedback.mediumImpact();
            ref.read(navigationProvider.notifier).state = destinations[i].type;
          },
          destinations: destinations
              .map(
                (d) => NavigationDestination(
                  icon: Icon(d.icon, color: Colors.white.withValues(alpha: 0.4), size: 22),
                  selectedIcon: Icon(d.icon, color: ref.watch(accentColorProvider), size: 24),
                  label: d.label,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTabletLayout(
    BuildContext context,
    WidgetRef ref,
    ScreenType current,
    bool isManager,
  ) {
    return Row(
      children: [
        _buildSidebar(context, ref, current, isCompactRail: true),
        Expanded(
          child: Column(
            children: [
              _buildStatusBar(ref, isCompact: false),
              Expanded(child: _buildMainContent(current)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    ScreenType current,
    bool isManager, {
    required bool isUltraWide,
  }) {
    return Row(
      children: [
        _buildSidebar(context, ref, current, isCompactRail: false),
        Expanded(
          child: Column(
            children: [
              _buildStatusBar(ref, isCompact: false),
              Expanded(
                child: isUltraWide
                    ? ConstrainedContent(child: _buildMainContent(current))
                    : _buildMainContent(current),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<_NavDestination> _getNavigationDestinations(User? user) {
    if (user == null) return const [];
    
    final role = user.role.toLowerCase().trim();
    final branch = user.branchCode?.trim();
    final isOwner = role == 'owner' || 
                    role == 'admin' || 
                    role == 'super_admin' || 
                    user.name.toLowerCase().trim() == 'owner' ||
                    user.name.toLowerCase().trim() == 'admin' ||
                    (role == 'manager' && (branch == null || branch.isEmpty || branch == '00'));

    if (isOwner) {
      // Headquarters / Corporate Owner (Can manage branches & multi-stores)
      return const [
        _NavDestination(ScreenType.dashboard, Icons.dashboard_rounded, 'Overview'),
        _NavDestination(ScreenType.inventory, Icons.inventory_2_rounded, 'Stock'),
        _NavDestination(ScreenType.purchases, Icons.shopping_bag_rounded, 'Purchases'),
        _NavDestination(ScreenType.accounts, Icons.account_balance_wallet_rounded, 'Accounts'),
        _NavDestination(ScreenType.branches, Icons.store_rounded, 'Branches'),
        _NavDestination(ScreenType.terminals, Icons.monitor_rounded, 'Terminals'),
        _NavDestination(ScreenType.reports, Icons.assessment_rounded, 'Reports'),
        _NavDestination(ScreenType.settings, Icons.settings_rounded, 'Settings'),
      ];
    } else if (role == 'branch_manager' || role == 'manager') {
      // Branch Manager (No access to create/manage other corporate branches)
      return const [
        _NavDestination(ScreenType.dashboard, Icons.dashboard_rounded, 'Overview'),
        _NavDestination(ScreenType.inventory, Icons.inventory_2_rounded, 'Stock'),
        _NavDestination(ScreenType.purchases, Icons.shopping_bag_rounded, 'Purchases'),
        _NavDestination(ScreenType.accounts, Icons.account_balance_wallet_rounded, 'Accounts'),
        _NavDestination(ScreenType.terminals, Icons.monitor_rounded, 'Terminals'),
        _NavDestination(ScreenType.reports, Icons.assessment_rounded, 'Reports'),
        _NavDestination(ScreenType.settings, Icons.settings_rounded, 'Settings'),
      ];
    } else {
      return const [
        _NavDestination(ScreenType.sales, Icons.point_of_sale_rounded, 'Sales'),
      ];
    }
  }

  int _getSelectedIndex(ScreenType current, List<_NavDestination> list) {
    final idx = list.indexWhere((e) => e.type == current);
    return idx >= 0 ? idx : 0;
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    ScreenType current, {
    required bool isCompactRail,
  }) {
    final user = ref.watch(authProvider);
    final width = isCompactRail ? 72.0 : 140.0;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ..._getNavigationDestinations(user).map(
                    (dest) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSidebarItem(
                        ref,
                        dest.type,
                        dest.icon,
                        dest.label,
                        current,
                        isCompactRail: isCompactRail,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Logo
          if (!isCompactRail)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Consumer(
                builder: (context, ref, child) {
                  final config = ref.watch(storeConfigProvider).value;
                  final logoPath = config?.logoPath;
                  
                  if (logoPath != null && File(logoPath).existsSync()) {
                    return Image.file(
                      File(logoPath),
                      width: 90,
                      height: 90,
                      fit: BoxFit.contain,
                    );
                  }
                  
                  for (final p in ['assets/images/logo.png', 'beleka logo icon.png', '${Directory.current.path}/assets/images/logo.png', '/home/mrm/Documents/programs/beleka-pos-main/beleka logo icon.png']) {
                    if (File(p).existsSync()) {
                      return Image.file(
                        File(p),
                        width: 90,
                        height: 90,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(Icons.bolt_rounded, color: ref.watch(accentColorProvider), size: 32),
                      );
                    }
                  }
                  
                  return Opacity(
                    opacity: 0.6,
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 90,
                      errorBuilder: (context, error, stackTrace) => Icon(Icons.bolt_rounded, color: ref.watch(accentColorProvider), size: 32),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
    bool showLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLoading)
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    WidgetRef ref,
    ScreenType type,
    IconData icon,
    String label,
    ScreenType current, {
    required bool isCompactRail,
  }) {
    final isActive = current == type;
    final itemWidth = isCompactRail ? 56.0 : 120.0;
    final itemHeight = isCompactRail ? 56.0 : 96.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(navigationProvider.notifier).state = type;
        },
        child: Container(
          width: itemWidth,
          height: itemHeight,
          decoration: BoxDecoration(
            color: isActive ? ref.watch(accentColorProvider).withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? ref.watch(accentColorProvider) : Colors.white.withValues(alpha: 0.25),
                size: isCompactRail ? 24 : 36,
              ),
              if (!isCompactRail) ...[
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? ref.watch(accentColorProvider) : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(WidgetRef ref, {required bool isCompact}) {
    final user = ref.watch(authProvider);

    return Container(
      height: 54,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Text(
            isCompact ? 'BELEKA' : 'BELEKA TERMINAL',
            style: GoogleFonts.manrope(
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 20),
            // Date/Time
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final now = DateTime.now();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${now.day}/${now.month}/${now.year}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: ref.watch(accentColorProvider).withValues(alpha: 0.7),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(width: 12),
          // Connection Status
          Consumer(
            builder: (context, ref, child) {
              final config = ref.watch(storeConfigProvider).value;
              if (config == null) return const SizedBox.shrink();

              if (config.isManagerMode) {
                return _buildStatusChip(
                  icon: Icons.lan_rounded,
                  label: isCompact ? 'SRV' : 'SERVER ACTIVE',
                  color: ref.watch(accentColorProvider),
                );
              }

              final isOnlineAsync = ref.watch(networkOnlineProvider);
              return isOnlineAsync.when(
                data: (online) => _buildStatusChip(
                  icon: online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  label: online ? 'ONLINE' : 'OFFLINE',
                  color: online ? Colors.green : Colors.red,
                ),
                loading: () => _buildStatusChip(
                  icon: Icons.sync_rounded,
                  label: isCompact ? '...' : 'CHECKING...',
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                error: (_, _) => _buildStatusChip(
                  icon: Icons.error_outline_rounded,
                  label: isCompact ? 'OFF' : 'NO CONNECTION',
                  color: Colors.red,
                ),
              );
            },
          ),
          const Spacer(),
          // Staff
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ref.watch(accentColorProvider).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ref.watch(accentColorProvider).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 14, color: ref.watch(accentColorProvider)),
                const SizedBox(width: 8),
                Text(
                  (user?.name ?? 'STAFF').toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: ref.watch(accentColorProvider),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Logout
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
            onPressed: () {
              HapticFeedback.heavyImpact();
              ref.read(authProvider.notifier).logout(ref);
            },
            tooltip: 'Sign Out',
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(ScreenType screen) {
    switch (screen) {
      case ScreenType.dashboard:
        return const DashboardScreen();
      case ScreenType.sales:
        return const SalesScreen();
      case ScreenType.inventory:
        return const InventoryScreen();
      case ScreenType.purchases:
        return const PurchasesScreen();
      case ScreenType.accounts:
        return const AccountsScreen();
      case ScreenType.branches:
        return const BranchesScreen();
      case ScreenType.terminals:
        return const TerminalsScreen();
      case ScreenType.settings:
        return const SettingsScreen();
      case ScreenType.reports:
        return const ReportsScreen();
    }
  }
}

class _NavDestination {
  final ScreenType type;
  final IconData icon;
  final String label;

  const _NavDestination(this.type, this.icon, this.label);
}

