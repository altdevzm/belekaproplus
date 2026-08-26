import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';
import 'package:beleka_pos/services/printer_service.dart';

// --- DATA PROVIDERS ---

final paymentAccountsProvider = FutureProvider<List<PaymentAccount>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.paymentAccounts.where().sortByCreatedAt().findAll();
});

final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.expenses.where().sortByExpenseDateDesc().findAll();
});

final accountTransfersProvider = FutureProvider<List<AccountTransfer>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.accountTransfers.where().sortByTransferDateDesc().findAll();
});

final cashShiftsProvider = FutureProvider<List<CashShift>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.cashShifts.where().sortByOpeningTimeDesc().findAll();
});

final activeShiftProvider = FutureProvider<CashShift?>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.cashShifts.filter().statusEqualTo('OPEN').findFirst();
});

final activeShiftsListProvider = FutureProvider<List<CashShift>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.cashShifts.filter().statusEqualTo('OPEN').findAll();
});

final refundsProvider = FutureProvider<List<RefundTransaction>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.refundTransactions.where().sortByRefundDateDesc().findAll();
});

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACCOUNTS & FINANCIAL TREASURY',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cash drawer management, cashier shift reconciliation, multi-wallet accounts, expenses, transfers & refunds',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
                Row(
                  children: [
                    // Export & Print Dropdown
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        final export = ref.read(exportServiceProvider);
                        final config = ref.read(storeConfigProvider).value;
                        final accounts = await ref.read(paymentAccountsProvider.future);
                        final expenses = await ref.read(expensesProvider.future);

                        switch (value) {
                          case 'accounts_pdf':
                            export.exportPaymentAccountsToPdf(accounts, config: config);
                            break;
                          case 'expenses_pdf':
                            export.exportExpensesToPdf(expenses, config: config);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'accounts_pdf', child: Row(children: [Icon(Icons.account_balance_wallet_rounded, color: Colors.blue, size: 16), SizedBox(width: 8), Text('Export Accounts (PDF)')])),
                        const PopupMenuItem(value: 'expenses_pdf', child: Row(children: [Icon(Icons.receipt_long_rounded, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Export Expenses (PDF)')])),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withAlpha(20)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.download_rounded, size: 16, color: Colors.white70),
                            const SizedBox(width: 6),
                            Text('Export & Print', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () => _showRecordExpenseModal(context, ref, accentColor),
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: Text('Record Expense', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withAlpha(40),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showTransferModal(context, ref, accentColor),
                      icon: const Icon(Icons.sync_alt_rounded, size: 16),
                      label: Text('Transfer Funds', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.withAlpha(40),
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 20),

          // Tab Bar
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141417),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: accentColor,
              indicatorWeight: 3,
              labelColor: accentColor,
              unselectedLabelColor: Colors.white60,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Dashboard'),
                Tab(icon: Icon(Icons.point_of_sale_rounded, size: 18), text: 'Till & Shift Balancing'),
                Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 18), text: 'Payment Accounts'),
                Tab(icon: Icon(Icons.receipt_rounded, size: 18), text: 'Expenses'),
                Tab(icon: Icon(Icons.sync_alt_rounded, size: 18), text: 'Transfers'),
                Tab(icon: Icon(Icons.assignment_return_rounded, size: 18), text: 'Refunds'),
                Tab(icon: Icon(Icons.analytics_rounded, size: 18), text: 'Reports'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tab View Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(accentColor),
                _buildShiftBalancingTab(accentColor),
                _buildPaymentAccountsTab(accentColor),
                _buildExpensesTab(accentColor),
                _buildTransfersTab(accentColor),
                _buildRefundsTab(accentColor),
                _buildReportsTab(accentColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: DASHBOARD
  // ==========================================
  Widget _buildDashboardTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final accounts = ref.watch(paymentAccountsProvider).value ?? [];
    final expenses = ref.watch(expensesProvider).value ?? [];
    final activeShift = ref.watch(activeShiftProvider).value;

    final totalTreasury = accounts.fold<double>(0.0, (s, a) => s + a.balance);
    final totalExpenses = expenses.fold<double>(0.0, (s, e) => s + e.amount);
    final cashDrawerBalance = accounts.where((a) => a.accountType == 'CASH').fold<double>(0.0, (s, a) => s + a.balance);
    final bankBalance = accounts.where((a) => a.accountType == 'BANK').fold<double>(0.0, (s, a) => s + a.balance);
    final momoBalance = accounts.where((a) => a.accountType.contains('MONEY')).fold<double>(0.0, (s, a) => s + a.balance);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Metric Cards
          GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.3,
            children: [
              _buildKpiCard('NET TREASURY LIQUIDITY', '$currency ${totalTreasury.toStringAsFixed(2)}', '${accounts.length} Active Accounts', Icons.account_balance_rounded, Colors.green),
              _buildKpiCard('CASH IN DRAWER (TILL)', '$currency ${cashDrawerBalance.toStringAsFixed(2)}', activeShift != null ? 'Shift Open (${activeShift.cashierName})' : 'Shift Closed', Icons.point_of_sale_rounded, Colors.blue),
              _buildKpiCard('MOBILE MONEY (AIRTEL/MTN)', '$currency ${momoBalance.toStringAsFixed(2)}', 'Digital wallets liquidity', Icons.phone_android_rounded, Colors.amber),
              _buildKpiCard('MAIN BANK ACCOUNT', '$currency ${bankBalance.toStringAsFixed(2)}', 'Direct commercial banking', Icons.account_balance_wallet_rounded, Colors.purpleAccent),
              _buildKpiCard('TOTAL EXPENSES (OUTFLOW)', '$currency ${totalExpenses.toStringAsFixed(2)}', '${expenses.length} Expense vouchers', Icons.receipt_long_rounded, Colors.redAccent),
              _buildKpiCard('CURRENT SHIFT STATUS', activeShift != null ? 'ACTIVE (OPEN)' : 'CLOSED', activeShift != null ? 'Opened at ${DateFormat('HH:mm').format(activeShift.openingTime)}' : 'Open shift to start sales', Icons.access_time_filled_rounded, activeShift != null ? Colors.green : Colors.grey),
            ],
          ),
          const SizedBox(height: 24),

          // Account Balances Overview Cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wallet Summary
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('TREASURY ACCOUNTS', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.bold)),
                          Icon(Icons.wallet_rounded, color: accentColor, size: 18),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...accounts.map((acc) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: _getAccountColor(acc.accountType).withAlpha(40),
                          child: Icon(_getAccountIcon(acc.accountType), color: _getAccountColor(acc.accountType), size: 18),
                        ),
                        title: Text(acc.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(acc.accountNumber != null ? 'Acc: ${acc.accountNumber}' : acc.accountType, style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
                        trailing: Text('$currency ${acc.balance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                      )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Recent Expenses
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('RECENT EXPENSES & PAYMENTS', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('View all in Expenses Tab', style: GoogleFonts.inter(fontSize: 11, color: accentColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (expenses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No expenses recorded yet', style: GoogleFonts.inter(color: Colors.white38))),
                        )
                      else
                        ...expenses.take(4).map((e) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.category, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('${e.paymentAccountName} • ${DateFormat('dd MMM yyyy').format(e.expenseDate)}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
                                ],
                              ),
                              Text('-$currency ${e.amount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                            ],
                          ),
                        )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: CASH MANAGEMENT & SHIFT RECONCILIATION
  // ==========================================
  Widget _buildShiftBalancingTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final activeShifts = ref.watch(activeShiftsListProvider).value ?? [];
    final shifts = ref.watch(cashShiftsProvider).value ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Tills Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACTIVE TILLS & CASHIER ASSIGNMENTS', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('${activeShifts.length} active till register${activeShifts.length == 1 ? "" : "s"} currently operating', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showOpenShiftModal(context, ref, accentColor),
                icon: const Icon(Icons.person_pin_circle_rounded, size: 16),
                label: const Text('Assign Cashier to a Till'),
                style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Active Tills Grid / List
          if (activeShifts.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.point_of_sale_rounded, size: 48, color: Colors.white.withAlpha(40)),
                    const SizedBox(height: 12),
                    Text('No Active Tills Operating', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text('Assign a cashier to a specific till and set their opening float to begin a shift.', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeShifts.length,
              itemBuilder: (context, index) {
                final shift = activeShifts[index];
                final expectedInDrawer = shift.openingCash + shift.cashSales - shift.cashExpenses - shift.cashRefunds;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F2937), Color(0xFF111827)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(40),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.point_of_sale_rounded, color: Colors.blue, size: 14),
                                    const SizedBox(width: 6),
                                    Text(shift.terminalId.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(6)),
                                child: const Text('SHIFT ACTIVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.greenAccent)),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showCloseShiftModal(context, ref, shift, currency),
                            icon: const Icon(Icons.calculate_rounded, size: 16),
                            label: const Text('Reconcile & Close Till'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: accentColor.withAlpha(40),
                            radius: 18,
                            child: Text(shift.cashierName.isNotEmpty ? shift.cashierName[0].toUpperCase() : 'C', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Assigned Cashier: ${shift.cashierName} (ID: ${shift.cashierId ?? "1001"})', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                              Text('${shift.branchName} • Opened at ${DateFormat('HH:mm, dd MMM yyyy').format(shift.openingTime)}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildShiftStat('Opening Float', '$currency ${shift.openingCash.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Cash Sales (+)', '$currency ${shift.cashSales.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Cash Expenses (-)', '$currency ${shift.cashExpenses.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Cash Refunds (-)', '$currency ${shift.cashRefunds.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Expected in Till Drawer', '$currency ${expectedInDrawer.toStringAsFixed(2)}', isHighlight: true),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),

          // Shift History Table
          Text('PAST SHIFTS & VARIANCE RECONCILIATION AUDIT', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          if (shifts.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1E), borderRadius: BorderRadius.circular(16)),
              child: Center(child: Text('No shift reconciliation records available', style: GoogleFonts.inter(color: Colors.white38))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shifts.length,
              itemBuilder: (context, index) {
                final s = shifts[index];
                final isOver = s.cashVariance > 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: s.status == 'OPEN' ? Colors.green.withAlpha(30) : (s.cashVariance == 0 ? Colors.blue.withAlpha(30) : Colors.red.withAlpha(30)),
                        child: Icon(s.status == 'OPEN' ? Icons.access_time_filled : (s.cashVariance == 0 ? Icons.check_circle : Icons.warning_rounded), color: s.status == 'OPEN' ? Colors.green : (s.cashVariance == 0 ? Colors.blue : Colors.redAccent), size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(s.shiftNumber, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(width: 10),
                                Text('Cashier: ${s.cashierName} (${s.terminalId})', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Opened: ${DateFormat('dd MMM yyyy, HH:mm').format(s.openingTime)} ${s.closingTime != null ? "• Closed: ${DateFormat('HH:mm').format(s.closingTime!)}" : ""}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Expected: $currency ${s.expectedClosingCash.toStringAsFixed(2)} | Actual: $currency ${s.actualClosingCash.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                          const SizedBox(height: 4),
                          Text(
                            s.status == 'OPEN' ? 'SHIFT ACTIVE' : (s.cashVariance == 0 ? 'PERFECT MATCH (K0.00)' : (isOver ? 'OVER: +$currency ${s.cashVariance.toStringAsFixed(2)}' : 'SHORT: -$currency ${s.cashVariance.abs().toStringAsFixed(2)}')),
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: s.status == 'OPEN' ? Colors.green : (s.cashVariance == 0 ? Colors.green : (isOver ? Colors.blue : Colors.redAccent))),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportShiftZReportToPdf(s, config: config, printDirectly: true);
                            },
                            icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                            tooltip: 'Print Shift Z-Report',
                          ),
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportShiftZReportToPdf(s, config: config, printDirectly: false);
                            },
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                            tooltip: 'Export Z-Report to PDF',
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildShiftStat(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.bold, color: isHighlight ? Colors.greenAccent : Colors.white)),
      ],
    );
  }

  // ==========================================
  // TAB 3: PAYMENT ACCOUNTS & TREASURY WALLETS
  // ==========================================
  Widget _buildPaymentAccountsTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final accounts = ref.watch(paymentAccountsProvider).value ?? [];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: () => _showAddAccountModal(context, ref, accentColor),
              icon: const Icon(Icons.add_card_rounded, size: 16),
              label: const Text('Add Treasury Account'),
              style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisExtent: 180,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final acc = accounts[index];
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: _getAccountColor(acc.accountType).withAlpha(40),
                              child: Icon(_getAccountIcon(acc.accountType), color: _getAccountColor(acc.accountType), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(acc.name, style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(acc.accountNumber ?? acc.accountType, style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
                              ],
                            ),
                          ],
                        ),
                        if (acc.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.withAlpha(40), borderRadius: BorderRadius.circular(6)),
                            child: const Text('DEFAULT', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text('Available Balance', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                    Text('$currency ${acc.balance.toStringAsFixed(2)}', style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: EXPENSES
  // ==========================================
  Widget _buildExpensesTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final expenses = ref.watch(expensesProvider).value ?? [];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: () => _showRecordExpenseModal(context, ref, accentColor),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: const Text('Record New Expense'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: expenses.isEmpty
              ? Center(child: Text('No expenses recorded', style: GoogleFonts.inter(color: Colors.white38)))
              : ListView.builder(
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final exp = expenses[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.red.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.receipt_long_rounded, color: Colors.redAccent, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${exp.category} (${exp.expenseNumber})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('Paid from: ${exp.paymentAccountName} • ${exp.notes ?? "No notes"}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                                const SizedBox(height: 2),
                                Text('Date: ${DateFormat('dd MMM yyyy').format(exp.expenseDate)} • Recorded by: ${exp.recordedBy ?? "Admin"}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text('-$currency ${exp.amount.toStringAsFixed(2)}', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportExpenseVoucherToPdf(exp, config: config, printDirectly: true);
                                },
                                icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                                tooltip: 'Print Expense Voucher',
                              ),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportExpenseVoucherToPdf(exp, config: config, printDirectly: false);
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                                tooltip: 'Export Expense Voucher PDF',
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 5: TRANSFERS
  // ==========================================
  Widget _buildTransfersTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final transfers = ref.watch(accountTransfersProvider).value ?? [];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: () => _showTransferModal(context, ref, accentColor),
              icon: const Icon(Icons.sync_alt_rounded, size: 16),
              label: const Text('Transfer Funds'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: transfers.isEmpty
              ? Center(child: Text('No inter-account transfers logged yet', style: GoogleFonts.inter(color: Colors.white38)))
              : ListView.builder(
                  itemCount: transfers.length,
                  itemBuilder: (context, index) {
                    final t = transfers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blue.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.sync_alt_rounded, color: Colors.blue, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.fromAccountName} ➔ ${t.toAccountName}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('Ref: ${t.reference ?? t.transferNumber} • On ${DateFormat('dd MMM yyyy, HH:mm').format(t.transferDate)}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text('$currency ${t.amount.toStringAsFixed(2)}', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportTransferVoucherToPdf(t, config: config, printDirectly: true);
                                },
                                icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                                tooltip: 'Print Transfer Voucher',
                              ),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportTransferVoucherToPdf(t, config: config, printDirectly: false);
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                                tooltip: 'Export Transfer Voucher PDF',
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 6: REFUNDS
  // ==========================================
  Widget _buildRefundsTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final refunds = ref.watch(refundsProvider).value ?? [];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: () => _showRecordRefundModal(context, ref, accentColor),
              icon: const Icon(Icons.assignment_return_rounded, size: 16),
              label: const Text('Record Sales Refund'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: refunds.isEmpty
              ? Center(child: Text('No customer sales refunds recorded', style: GoogleFonts.inter(color: Colors.white38)))
              : ListView.builder(
                  itemCount: refunds.length,
                  itemBuilder: (context, index) {
                    final r = refunds[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.purple.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.assignment_return_rounded, color: Colors.purpleAccent, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r.refundType} Refund (${r.refundNumber})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('Reason: ${r.reason} • Auth: ${r.authorizedBy ?? "Manager"}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text('-$currency ${r.amount.toStringAsFixed(2)}', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportRefundVoucherToPdf(r, config: config, printDirectly: true);
                                },
                                icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                                tooltip: 'Print Refund Voucher',
                              ),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportRefundVoucherToPdf(r, config: config, printDirectly: false);
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                                tooltip: 'Export Refund Voucher PDF',
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 7: FINANCIAL REPORTS
  // ==========================================
  Widget _buildReportsTab(Color accentColor) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final expenses = ref.watch(expensesProvider).value ?? [];
    final accounts = ref.watch(paymentAccountsProvider).value ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FINANCIAL TREASURY & EXPENSE ANALYSIS', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Liquidity by Account Channel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                ...accounts.map((a) => ListTile(
                  leading: Icon(_getAccountIcon(a.accountType), color: _getAccountColor(a.accountType)),
                  title: Text(a.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  subtitle: Text(a.accountType),
                  trailing: Text('$currency ${a.balance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: accentColor)),
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expenses Summary by Category', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                if (expenses.isEmpty)
                  Text('No expenses logged for breakdown', style: GoogleFonts.inter(color: Colors.white38))
                else
                  ...['Rent', 'Utilities', 'Salaries & Wages', 'Transport / Fuel', 'Inventory & Supplies', 'Repairs & Maintenance', 'Marketing', 'Other'].map((cat) {
                    final catExps = expenses.where((e) => e.category == cat);
                    final catTotal = catExps.fold<double>(0.0, (s, e) => s + e.amount);
                    if (catTotal == 0) return const SizedBox.shrink();
                    return ListTile(
                      title: Text(cat, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      subtitle: Text('${catExps.length} vouchers logged'),
                      trailing: Text('$currency ${catTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- MODAL DIALOG HANDLERS ---

  void _showOpenShiftModal(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(context: context, builder: (context) => _OpenShiftModal(accentColor: accentColor));
  }

  void _showCloseShiftModal(BuildContext context, WidgetRef ref, CashShift shift, String currency) {
    showDialog(context: context, builder: (context) => _CloseShiftModal(shift: shift, currency: currency));
  }

  void _showRecordExpenseModal(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(context: context, builder: (context) => _RecordExpenseModal(accentColor: accentColor));
  }

  void _showTransferModal(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(context: context, builder: (context) => _TransferFundsModal(accentColor: accentColor));
  }

  void _showAddAccountModal(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(context: context, builder: (context) => _AddAccountModal(accentColor: accentColor));
  }

  void _showRecordRefundModal(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(context: context, builder: (context) => _RecordRefundModal(accentColor: accentColor));
  }

  Color _getAccountColor(String type) {
    switch (type) {
      case 'CASH':
        return Colors.green;
      case 'BANK':
        return Colors.blue;
      case 'AIRTEL_MONEY':
        return Colors.redAccent;
      case 'MTN_MONEY':
        return Colors.amber;
      case 'ZAMTEL_MONEY':
        return Colors.teal;
      case 'CARD':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  IconData _getAccountIcon(String type) {
    switch (type) {
      case 'CASH':
        return Icons.money_rounded;
      case 'BANK':
        return Icons.account_balance_rounded;
      case 'AIRTEL_MONEY':
      case 'MTN_MONEY':
      case 'ZAMTEL_MONEY':
        return Icons.phone_android_rounded;
      case 'CARD':
        return Icons.credit_card_rounded;
      default:
        return Icons.wallet_rounded;
    }
  }
}

// ==========================================
// MODAL DIALOGS
// ==========================================

class _OpenShiftModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _OpenShiftModal({required this.accentColor});

  @override
  ConsumerState<_OpenShiftModal> createState() => _OpenShiftModalState();
}

class _OpenShiftModalState extends ConsumerState<_OpenShiftModal> {
  final _floatCtrl = TextEditingController(text: '1000.00');
  String? _selectedTill;
  String? _selectedBranch;
  String? _selectedCashierId;

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _open(List<User> users) async {
    final floatVal = double.tryParse(_floatCtrl.text) ?? 0.0;
    final isar = ref.read(isarProvider);
    final currentUser = ref.read(authProvider);

    final selectedUser = users.firstWhere(
      (u) => u.numericId == _selectedCashierId,
      orElse: () => currentUser ?? users.first,
    );

    final cashierName = selectedUser.name;
    final cashierId = selectedUser.numericId;
    final tillName = _selectedTill ?? 'Main Till (POS 1)';
    final branchName = _selectedBranch ?? 'Main Store (HQ)';

    // Check if this till already has an open shift
    final existingTillShift = await isar.cashShifts.filter().terminalIdEqualTo(tillName).and().statusEqualTo('OPEN').findFirst();
    if (existingTillShift != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Warning: $tillName is already open under ${existingTillShift.cashierName}! Reconcile that shift first.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    await isar.writeTxn(() async {
      final shift = CashShift()
        ..shiftNumber = 'SHIFT-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..cashierId = cashierId
        ..cashierName = cashierName
        ..terminalId = tillName
        ..branchName = branchName
        ..openingCash = floatVal
        ..status = 'OPEN';
      await isar.cashShifts.put(shift);

      // Adjust cash drawer balance with opening float
      final cashAccount = await isar.paymentAccounts.filter().accountTypeEqualTo('CASH').findFirst();
      if (cashAccount != null) {
        cashAccount.balance += floatVal;
        await isar.paymentAccounts.put(cashAccount);
      }
    });

    ref.invalidate(activeShiftProvider);
    ref.invalidate(activeShiftsListProvider);
    ref.invalidate(cashShiftsProvider);
    ref.invalidate(paymentAccountsProvider);

    // Pop open cash drawer for float deposit
    try {
      ref.read(printerServiceProvider).openCashDrawer();
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully assigned $cashierName to $tillName with float of K${floatVal.toStringAsFixed(2)}!'), backgroundColor: Colors.green[800]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(allUsersProvider).value ?? [];
    final tills = ref.watch(posTerminalsProvider).value ?? [];
    final branches = ref.watch(storeBranchesProvider).value ?? [];
    final currentUser = ref.watch(authProvider);

    if (_selectedCashierId == null && users.isNotEmpty) {
      _selectedCashierId = currentUser?.numericId ?? users.first.numericId;
    }

    if (_selectedTill == null && tills.isNotEmpty) {
      _selectedTill = '${tills.first.terminalCode} - ${tills.first.name}';
      _selectedBranch = tills.first.branchName;
      if (tills.first.assignedCashierId != null && tills.first.assignedCashierId!.isNotEmpty) {
        _selectedCashierId = tills.first.assignedCashierId;
      }
    }

    if (_selectedBranch == null && branches.isNotEmpty) {
      _selectedBranch = branches.first.name;
    }

    return AlertDialog(
      title: Text('ASSIGN CASHIER TO TILL & OPEN SHIFT', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select the cashier, designated till register, and physical opening cash float:'),
            const SizedBox(height: 16),

            // Cashier Selection Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedCashierId,
              decoration: const InputDecoration(labelText: 'Assign Cashier / User', border: OutlineInputBorder()),
              items: users.map((u) => DropdownMenuItem(
                value: u.numericId,
                child: Text('${u.name} (ID: ${u.numericId} • ${u.role.toUpperCase()})'),
              )).toList(),
              onChanged: (id) => setState(() => _selectedCashierId = id),
            ),
            const SizedBox(height: 12),

            // Till Selection Dropdown (Dynamic from Database)
            DropdownButtonFormField<String>(
              initialValue: _selectedTill,
              decoration: const InputDecoration(labelText: 'Assigned Till / Terminal', border: OutlineInputBorder()),
              items: tills.isEmpty
                  ? [
                      const DropdownMenuItem(
                        value: 'TILL-01 - Main Counter Till 1',
                        child: Text('TILL-01 - Main Counter Till 1'),
                      )
                    ]
                  : tills.map((t) => DropdownMenuItem(
                      value: '${t.terminalCode} - ${t.name}',
                      child: Text('${t.terminalCode} - ${t.name} (${t.branchName})'),
                    )).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedTill = v;
                    final matchingTill = tills.where((t) => '${t.terminalCode} - ${t.name}' == v).firstOrNull;
                    if (matchingTill != null) {
                      _selectedBranch = matchingTill.branchName;
                      if (matchingTill.assignedCashierId != null && matchingTill.assignedCashierId!.isNotEmpty) {
                        _selectedCashierId = matchingTill.assignedCashierId;
                      }
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 12),

            // Branch Selection Dropdown (Dynamic from Database)
            DropdownButtonFormField<String>(
              initialValue: _selectedBranch,
              decoration: const InputDecoration(labelText: 'Store Branch', border: OutlineInputBorder()),
              items: branches.isEmpty
                  ? [
                      const DropdownMenuItem(
                        value: 'Main Store (HQ)',
                        child: Text('Main Store (HQ)'),
                      )
                    ]
                  : branches.map((b) => DropdownMenuItem(
                      value: b.name,
                      child: Text('${b.name} (Code: ${b.code} • ZRA: ${b.bhfId})'),
                    )).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedBranch = v);
              },
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _floatCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Opening Cash Float (K)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => _open(users),
          style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor, foregroundColor: Colors.black),
          child: const Text('Confirm & Assign Till'),
        ),
      ],
    );
  }
}

class _CloseShiftModal extends ConsumerStatefulWidget {
  final CashShift shift;
  final String currency;
  const _CloseShiftModal({required this.shift, required this.currency});

  @override
  ConsumerState<_CloseShiftModal> createState() => _CloseShiftModalState();
}

class _CloseShiftModalState extends ConsumerState<_CloseShiftModal> {
  final _actualCashCtrl = TextEditingController();
  double _expected = 0.0;
  double _variance = 0.0;

  @override
  void initState() {
    super.initState();
    _expected = widget.shift.openingCash + widget.shift.cashSales - widget.shift.cashExpenses - widget.shift.cashRefunds;
    _actualCashCtrl.text = _expected.toStringAsFixed(2);
    _variance = 0.0;
  }

  @override
  void dispose() {
    _actualCashCtrl.dispose();
    super.dispose();
  }

  void _calcVariance(String val) {
    final actual = double.tryParse(val) ?? 0.0;
    setState(() {
      _variance = actual - _expected;
    });
  }

  Future<void> _close() async {
    final actual = double.tryParse(_actualCashCtrl.text) ?? 0.0;
    final isar = ref.read(isarProvider);

    await isar.writeTxn(() async {
      widget.shift.closingTime = DateTime.now();
      widget.shift.expectedClosingCash = _expected;
      widget.shift.actualClosingCash = actual;
      widget.shift.cashVariance = actual - _expected;
      widget.shift.status = 'CLOSED';
      await isar.cashShifts.put(widget.shift);
    });

    ref.invalidate(activeShiftProvider);
    ref.invalidate(cashShiftsProvider);

    // Automatically push end-of-day branch sales to Headquarters Cloud DB
    try {
      ref.read(postgresSyncServiceProvider).syncPendingTransactions();
    } catch (e) {
      debugPrint('Cloud sync on shift close notice: $e');
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('TILL & SHIFT RECONCILIATION', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shift: ${widget.shift.shiftNumber} • Cashier: ${widget.shift.cashierName}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  _row('Opening Float', '${widget.currency} ${widget.shift.openingCash.toStringAsFixed(2)}'),
                  _row('+ Cash Sales', '${widget.currency} ${widget.shift.cashSales.toStringAsFixed(2)}'),
                  _row('- Cash Expenses', '${widget.currency} ${widget.shift.cashExpenses.toStringAsFixed(2)}'),
                  _row('- Cash Refunds', '${widget.currency} ${widget.shift.cashRefunds.toStringAsFixed(2)}'),
                  const Divider(),
                  _row('Expected Cash', '${widget.currency} ${_expected.toStringAsFixed(2)}', bold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _actualCashCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Actual Counted Cash in Drawer (K)', border: OutlineInputBorder()),
              onChanged: _calcVariance,
            ),
            const SizedBox(height: 12),
            Text(
              _variance == 0 ? 'Variance: K0.00 (Balanced)' : (_variance > 0 ? 'Variance: +${widget.currency} ${_variance.toStringAsFixed(2)} (OVER)' : 'Variance: -${widget.currency} ${_variance.abs().toStringAsFixed(2)} (SHORT)'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _variance == 0 ? Colors.green : (_variance > 0 ? Colors.blue : Colors.redAccent)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _close,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
          child: const Text('Close Shift'),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: bold ? Colors.greenAccent : Colors.white)),
        ],
      ),
    );
  }
}

class _RecordExpenseModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _RecordExpenseModal({required this.accentColor});

  @override
  ConsumerState<_RecordExpenseModal> createState() => _RecordExpenseModalState();
}

class _RecordExpenseModalState extends ConsumerState<_RecordExpenseModal> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _category = 'Utilities';
  int? _selectedAccountId;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(List<PaymentAccount> accounts) async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0 || _selectedAccountId == null) return;

    final account = accounts.firstWhere((a) => a.id == _selectedAccountId);
    final isar = ref.read(isarProvider);
    final user = ref.read(authProvider);

    await isar.writeTxn(() async {
      // Deduct account balance
      account.balance -= amount;
      await isar.paymentAccounts.put(account);

      final exp = Expense()
        ..expenseNumber = 'EXP-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..category = _category
        ..amount = amount
        ..paymentAccountId = account.id
        ..paymentAccountName = account.name
        ..recordedBy = user?.name ?? 'Admin'
        ..notes = _notesCtrl.text.trim();
      await isar.expenses.put(exp);

      // If active shift exists and paid from cash till, update cash shift
      if (account.accountType == 'CASH') {
        final activeShift = await isar.cashShifts.filter().statusEqualTo('OPEN').findFirst();
        if (activeShift != null) {
          activeShift.cashExpenses += amount;
          await isar.cashShifts.put(activeShift);
        }
      }
    });

    ref.invalidate(expensesProvider);
    ref.invalidate(paymentAccountsProvider);
    ref.invalidate(activeShiftProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(paymentAccountsProvider).value ?? [];
    if (_selectedAccountId == null && accounts.isNotEmpty) {
      _selectedAccountId = accounts.first.id;
    }

    return AlertDialog(
      title: Text('RECORD BUSINESS EXPENSE', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Expense Category', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Utilities', child: Text('Utilities (Electricity / Water / Internet)')),
                DropdownMenuItem(value: 'Rent', child: Text('Store Rent')),
                DropdownMenuItem(value: 'Salaries & Wages', child: Text('Salaries & Staff Wages')),
                DropdownMenuItem(value: 'Transport / Fuel', child: Text('Transport / Fuel & Logistics')),
                DropdownMenuItem(value: 'Inventory & Supplies', child: Text('Inventory & Packaging Supplies')),
                DropdownMenuItem(value: 'Repairs & Maintenance', child: Text('Repairs & Equipment Maintenance')),
                DropdownMenuItem(value: 'Marketing', child: Text('Marketing & Ads')),
                DropdownMenuItem(value: 'Other', child: Text('Other Expenses')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (K)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedAccountId,
              decoration: const InputDecoration(labelText: 'Payment Wallet / Account', border: OutlineInputBorder()),
              items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (Bal: K${a.balance.toStringAsFixed(2)})'))).toList(),
              onChanged: (id) => setState(() => _selectedAccountId = id),
            ),
            const SizedBox(height: 12),
            TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes / Voucher Details', border: OutlineInputBorder())),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => _save(accounts),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
          child: const Text('Record Expense'),
        ),
      ],
    );
  }
}

class _TransferFundsModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _TransferFundsModal({required this.accentColor});

  @override
  ConsumerState<_TransferFundsModal> createState() => _TransferFundsModalState();
}

class _TransferFundsModalState extends ConsumerState<_TransferFundsModal> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  int? _fromAccountId;
  int? _toAccountId;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _transfer(List<PaymentAccount> accounts) async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0 || _fromAccountId == null || _toAccountId == null || _fromAccountId == _toAccountId) return;

    final fromAcc = accounts.firstWhere((a) => a.id == _fromAccountId);
    final toAcc = accounts.firstWhere((a) => a.id == _toAccountId);
    final isar = ref.read(isarProvider);
    final user = ref.read(authProvider);

    await isar.writeTxn(() async {
      fromAcc.balance -= amount;
      toAcc.balance += amount;
      await isar.paymentAccounts.put(fromAcc);
      await isar.paymentAccounts.put(toAcc);

      final transfer = AccountTransfer()
        ..transferNumber = 'TRF-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..fromAccountId = fromAcc.id
        ..fromAccountName = fromAcc.name
        ..toAccountId = toAcc.id
        ..toAccountName = toAcc.name
        ..amount = amount
        ..reference = _refCtrl.text.trim()
        ..transferredBy = user?.name ?? 'Admin';
      await isar.accountTransfers.put(transfer);
    });

    ref.invalidate(paymentAccountsProvider);
    ref.invalidate(accountTransfersProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(paymentAccountsProvider).value ?? [];

    return AlertDialog(
      title: Text('INTER-ACCOUNT TRANSFER', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _fromAccountId,
              decoration: const InputDecoration(labelText: 'From Account', border: OutlineInputBorder()),
              items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (K${a.balance.toStringAsFixed(2)})'))).toList(),
              onChanged: (id) => setState(() => _fromAccountId = id),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _toAccountId,
              decoration: const InputDecoration(labelText: 'To Account', border: OutlineInputBorder()),
              items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (K${a.balance.toStringAsFixed(2)})'))).toList(),
              onChanged: (id) => setState(() => _toAccountId = id),
            ),
            const SizedBox(height: 12),
            TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Transfer Amount (K)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Reference / Reason', border: OutlineInputBorder())),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => _transfer(accounts),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
          child: const Text('Confirm Transfer'),
        ),
      ],
    );
  }
}

class _AddAccountModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _AddAccountModal({required this.accentColor});

  @override
  ConsumerState<_AddAccountModal> createState() => _AddAccountModalState();
}

class _AddAccountModalState extends ConsumerState<_AddAccountModal> {
  final _nameCtrl = TextEditingController();
  final _accNumCtrl = TextEditingController();
  String _type = 'BANK';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _accNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final isar = ref.read(isarProvider);

    await isar.writeTxn(() async {
      final acc = PaymentAccount()
        ..name = _nameCtrl.text.trim()
        ..accountNumber = _accNumCtrl.text.trim()
        ..accountType = _type
        ..balance = 0.0;
      await isar.paymentAccounts.put(acc);
    });

    ref.invalidate(paymentAccountsProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ADD TREASURY ACCOUNT', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Account Name (e.g. Absa Bank)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Account Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'BANK', child: Text('Bank Account')),
              DropdownMenuItem(value: 'AIRTEL_MONEY', child: Text('Airtel Money')),
              DropdownMenuItem(value: 'MTN_MONEY', child: Text('MTN Mobile Money')),
              DropdownMenuItem(value: 'ZAMTEL_MONEY', child: Text('Zamtel Kwacha')),
              DropdownMenuItem(value: 'CARD', child: Text('Credit / Debit Card Gateway')),
              DropdownMenuItem(value: 'OTHER', child: Text('Other Digital Wallet')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _type = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _accNumCtrl, decoration: const InputDecoration(labelText: 'Account / Merchant Number', border: OutlineInputBorder())),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor, foregroundColor: Colors.black),
          child: const Text('Save Account'),
        ),
      ],
    );
  }
}

class _RecordRefundModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _RecordRefundModal({required this.accentColor});

  @override
  ConsumerState<_RecordRefundModal> createState() => _RecordRefundModalState();
}

class _RecordRefundModalState extends ConsumerState<_RecordRefundModal> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String _type = 'CASH';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0) return;
    final isar = ref.read(isarProvider);
    final user = ref.read(authProvider);

    await isar.writeTxn(() async {
      final refund = RefundTransaction()
        ..refundNumber = 'REF-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..refundType = _type
        ..amount = amount
        ..reason = _reasonCtrl.text.trim().isNotEmpty ? _reasonCtrl.text.trim() : 'Customer Return'
        ..authorizedBy = user?.name ?? 'Manager';
      await isar.refundTransactions.put(refund);

      // Deduct from corresponding account
      final accType = _type == 'CASH' ? 'CASH' : (_type == 'CARD' ? 'CARD' : 'AIRTEL_MONEY');
      final acc = await isar.paymentAccounts.filter().accountTypeEqualTo(accType).findFirst();
      if (acc != null) {
        acc.balance -= amount;
        await isar.paymentAccounts.put(acc);
      }

      // If active shift and cash refund, update shift
      if (_type == 'CASH') {
        final activeShift = await isar.cashShifts.filter().statusEqualTo('OPEN').findFirst();
        if (activeShift != null) {
          activeShift.cashRefunds += amount;
          await isar.cashShifts.put(activeShift);
        }
      }
    });

    ref.invalidate(refundsProvider);
    ref.invalidate(paymentAccountsProvider);
    ref.invalidate(activeShiftProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('RECORD SALES REFUND', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Refund Channel', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('Cash Refund (Drawer)')),
              DropdownMenuItem(value: 'CARD', child: Text('Card Chargeback / Refund')),
              DropdownMenuItem(value: 'MOBILE_MONEY', child: Text('Mobile Money Reverse')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _type = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Refund Amount (K)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _reasonCtrl, decoration: const InputDecoration(labelText: 'Reason for Refund', border: OutlineInputBorder())),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white),
          child: const Text('Authorize Refund'),
        ),
      ],
    );
  }
}
