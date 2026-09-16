import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';

class RecordExpenseModal extends ConsumerStatefulWidget {
  final Expense? existingExpense;

  const RecordExpenseModal({super.key, this.existingExpense});

  @override
  ConsumerState<RecordExpenseModal> createState() => _RecordExpenseModalState();
}

class _RecordExpenseModalState extends ConsumerState<RecordExpenseModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _referenceController;
  late TextEditingController _notesController;

  late String _selectedCategory;
  late String _selectedPaymentAccount;
  late String _selectedBranch;
  late DateTime _selectedDate;
  bool _printVoucherOnSave = false;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _categories = const [
    {'name': 'Transport / Fuel', 'icon': Icons.local_gas_station_rounded, 'color': Color(0xFFF59E0B)},
    {'name': 'Utilities', 'icon': Icons.bolt_rounded, 'color': Color(0xFF3B82F6)},
    {'name': 'Rent', 'icon': Icons.business_rounded, 'color': Color(0xFF8B5CF6)},
    {'name': 'Salaries & Wages', 'icon': Icons.badge_rounded, 'color': Color(0xFF10B981)},
    {'name': 'Supplies & Stationery', 'icon': Icons.inventory_2_rounded, 'color': Color(0xFF06B6D4)},
    {'name': 'Repairs & Maintenance', 'icon': Icons.build_rounded, 'color': Color(0xFFEF4444)},
    {'name': 'Marketing & Advertising', 'icon': Icons.campaign_rounded, 'color': Color(0xFFEC4899)},
    {'name': 'Taxes & Licenses', 'icon': Icons.account_balance_rounded, 'color': Color(0xFF6366F1)},
    {'name': 'Meals & Refreshments', 'icon': Icons.restaurant_rounded, 'color': Color(0xFF14B8A6)},
    {'name': 'Other', 'icon': Icons.more_horiz_rounded, 'color': Color(0xFF64748B)},
  ];

  final List<String> _paymentAccounts = const [
    'Cash in Till',
    'Main Bank Account',
    'Airtel Money',
    'MTN Mobile Money',
    'Zamtel Kwacha',
    'Visa / Debit Card',
    'Petty Cash Box',
  ];

  final List<String> _quickSuggestions = const [
    'Generator Fuel 20L',
    'ZESCO Electricity Units',
    'Store Internet Fiber Bill',
    'Water Utility Bill',
    'Office Cleaning Supplies',
    'Receipt Printer Paper Rolls',
    'Airtime & Communication',
    'Staff Overtime Lunch',
    'Transport / Delivery Fare',
    'Lighting / Bulb Replacement',
  ];

  @override
  void initState() {
    super.initState();
    final exp = widget.existingExpense;
    _titleController = TextEditingController(text: exp?.notes ?? '');
    _amountController = TextEditingController(text: exp != null ? exp.amount.toStringAsFixed(2) : '');
    _referenceController = TextEditingController(text: exp?.referenceNumber ?? '');
    _notesController = TextEditingController(text: exp?.notes ?? '');

    _selectedCategory = exp?.category ?? _categories.first['name'];
    _selectedPaymentAccount = exp?.paymentAccountName ?? _paymentAccounts.first;
    _selectedBranch = exp?.branch ?? 'Main Branch';
    _selectedDate = exp?.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateExpenseNumber() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final random = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return 'EXP-$dateStr-$random';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );
      if (mounted) {
        setState(() {
          if (pickedTime != null) {
            _selectedDate = DateTime(picked.year, picked.month, picked.day, pickedTime.hour, pickedTime.minute);
          } else {
            _selectedDate = picked;
          }
        });
      }
    }
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid expense amount greater than 0')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = ref.read(databaseServiceProvider);
      final currentUser = ref.read(authProvider);

      final isEditing = widget.existingExpense != null;
      final expense = widget.existingExpense ?? Expense();

      expense.expenseNumber = isEditing ? expense.expenseNumber : _generateExpenseNumber();
      expense.category = _selectedCategory;
      expense.amount = amount;
      expense.paymentAccountName = _selectedPaymentAccount;
      expense.recordedBy = currentUser?.name ?? 'Admin';
      expense.branch = _selectedBranch;
      expense.referenceNumber = _referenceController.text.trim().isNotEmpty ? _referenceController.text.trim() : null;
      expense.notes = _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : _selectedCategory;
      expense.expenseDate = _selectedDate;
      expense.createdAt = isEditing ? expense.createdAt : DateTime.now();

      await db.saveExpense(expense);

      if (_printVoucherOnSave) {
        final export = ref.read(exportServiceProvider);
        final config = ref.read(storeConfigProvider).value;
        await export.exportExpenseVoucherToPdf(expense, config: config, printDirectly: true);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Expense updated successfully' : 'Expense recorded successfully'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save expense: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final config = ref.watch(storeConfigProvider).value;
    final currency = config?.currencySymbol ?? 'K';
    final branchesAsync = ref.watch(storeBranchesProvider);
    final isPhone = MediaQuery.of(context).size.width < 600;

    final cardBg = isDark ? const Color(0xFF151F32) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
    final inputBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: isPhone ? 12 : 24, vertical: isPhone ? 16 : 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderCol),
      ),
      child: Container(
        width: 640,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: EdgeInsets.all(isPhone ? 16 : 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(isPhone ? 8 : 10),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.receipt_long_rounded, color: primaryColor, size: isPhone ? 20 : 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.existingExpense != null ? 'EDIT EXPENSE VOUCHER' : 'RECORD NEW EXPENSE',
                                style: GoogleFonts.inter(fontSize: isPhone ? 15 : 17, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Track branch operating costs, petty cash, and bills',
                                style: GoogleFonts.inter(fontSize: isPhone ? 11 : 12, color: theme.colorScheme.onSurfaceVariant),
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              SizedBox(height: isPhone ? 12 : 18),
              const Divider(height: 1),
              SizedBox(height: isPhone ? 12 : 18),

              // Form Body
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Branch / Store Selector
                      Text('STORE / BRANCH', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      branchesAsync.when(
                        data: (branches) {
                          final branchNames = ['Main Branch', ...branches.map((b) => b.name).where((n) => n != 'Main Branch')];
                          if (!branchNames.contains(_selectedBranch)) {
                            branchNames.add(_selectedBranch);
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: inputBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderCol),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedBranch,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down_rounded),
                                items: branchNames.map((name) {
                                  return DropdownMenuItem(
                                    value: name,
                                    child: Row(
                                      children: [
                                        Icon(Icons.store_rounded, size: 16, color: primaryColor),
                                        const SizedBox(width: 8),
                                        Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedBranch = val);
                                },
                              ),
                            ),
                          );
                        },
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => TextFormField(
                          initialValue: _selectedBranch,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onChanged: (val) => _selectedBranch = val,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // What was the expense exactly? (Title / Description)
                      Text('WHAT WAS THE EXPENSE EXACTLY?', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _titleController,
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'e.g. Generator Fuel 20 Litres, ZESCO Units...',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          filled: true,
                          fillColor: inputBg,
                          prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please describe what the expense was for';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),

                      // Quick Suggestion Chips
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _quickSuggestions.take(6).map((s) {
                          return InkWell(
                            onTap: () {
                              _titleController.text = s;
                              // Auto-select likely category
                              if (s.contains('Fuel') || s.contains('Fare')) {
                                setState(() => _selectedCategory = 'Transport / Fuel');
                              } else if (s.contains('Electricity') || s.contains('Internet') || s.contains('Water')) {
                                setState(() => _selectedCategory = 'Utilities');
                              } else if (s.contains('Paper') || s.contains('Supplies')) {
                                setState(() => _selectedCategory = 'Supplies & Stationery');
                              } else if (s.contains('Lunch')) {
                                setState(() => _selectedCategory = 'Meals & Refreshments');
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderCol),
                              ),
                              child: Text(
                                '+ $s',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Amount & Category Fields
                      if (isPhone) ...[
                        // Amount
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AMOUNT ($currency)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444)),
                              decoration: InputDecoration(
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(currency, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: primaryColor)),
                                ),
                                hintText: '0.00',
                                filled: true,
                                fillColor: inputBg,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Enter amount';
                                final num = double.tryParse(val);
                                if (num == null || num <= 0) return 'Enter valid amount > 0';
                                return null;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Category
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CATEGORY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderCol),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedCategory,
                                  isExpanded: true,
                                  items: _categories.map((cat) {
                                    final name = cat['name'] as String;
                                    final icon = cat['icon'] as IconData;
                                    final color = cat['color'] as Color;
                                    return DropdownMenuItem(
                                      value: name,
                                      child: Row(
                                        children: [
                                          Icon(icon, size: 16, color: color),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedCategory = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Amount
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('AMOUNT ($currency)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _amountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444)),
                                    decoration: InputDecoration(
                                      prefixIcon: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(currency, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: primaryColor)),
                                      ),
                                      hintText: '0.00',
                                      filled: true,
                                      fillColor: inputBg,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                                    ),
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) return 'Enter amount';
                                      final num = double.tryParse(val);
                                      if (num == null || num <= 0) return 'Enter valid amount > 0';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Category
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('CATEGORY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: inputBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedCategory,
                                        isExpanded: true,
                                        items: _categories.map((cat) {
                                          final name = cat['name'] as String;
                                          final icon = cat['icon'] as IconData;
                                          final color = cat['color'] as Color;
                                          return DropdownMenuItem(
                                            value: name,
                                            child: Row(
                                              children: [
                                                Icon(icon, size: 16, color: color),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedCategory = val);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Payment Account & Date Fields
                      if (isPhone) ...[
                        // Payment Account
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PAID FROM (ACCOUNT)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderCol),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedPaymentAccount,
                                  isExpanded: true,
                                  items: _paymentAccounts.map((acc) {
                                    return DropdownMenuItem(
                                      value: acc,
                                      child: Row(
                                        children: [
                                          Icon(
                                            acc.contains('Cash') ? Icons.payments_rounded : (acc.contains('Bank') ? Icons.account_balance_rounded : Icons.phone_android_rounded),
                                            size: 16,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(acc, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedPaymentAccount = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Date Picker
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('EXPENSE DATE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: inputBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: borderCol),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('dd MMM yyyy, HH:mm').format(_selectedDate), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                    Icon(Icons.calendar_today_rounded, size: 16, color: primaryColor),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            // Payment Account
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('PAID FROM (ACCOUNT)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: inputBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedPaymentAccount,
                                        isExpanded: true,
                                        items: _paymentAccounts.map((acc) {
                                          return DropdownMenuItem(
                                            value: acc,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  acc.contains('Cash') ? Icons.payments_rounded : (acc.contains('Bank') ? Icons.account_balance_rounded : Icons.phone_android_rounded),
                                                  size: 16,
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(acc, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedPaymentAccount = val);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Date Picker
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('EXPENSE DATE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: _pickDate,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      height: 48,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: inputBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderCol),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(DateFormat('dd MMM yyyy, HH:mm').format(_selectedDate), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                          Icon(Icons.calendar_today_rounded, size: 16, color: primaryColor),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Reference / Receipt Number
                      Text('REFERENCE / INVOICE / RECEIPT # (OPTIONAL)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _referenceController,
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. REC-98421, INV-2026-004, ZESCO-TKN-8831',
                          filled: true,
                          fillColor: inputBg,
                          prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Print / Export Voucher Checkbox
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderCol),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _printVoucherOnSave,
                              activeColor: primaryColor,
                              onChanged: (val) => setState(() => _printVoucherOnSave = val ?? false),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Print or Export Expense Voucher PDF immediately on save',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveExpense,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      widget.existingExpense != null ? 'Update Expense' : 'Save Expense Voucher',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
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
}
