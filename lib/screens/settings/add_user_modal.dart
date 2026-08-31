import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/users_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class AddUserModal extends ConsumerStatefulWidget {
  final User? userToEdit;
  const AddUserModal({super.key, this.userToEdit});

  @override
  ConsumerState<AddUserModal> createState() => _AddUserModalState();
}

class _AddUserModalState extends ConsumerState<AddUserModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _numericIdController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  late TextEditingController _nameController;
  late String _role;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _numericIdController = TextEditingController(text: widget.userToEdit?.numericId ?? '');
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _nameController = TextEditingController(text: widget.userToEdit?.name ?? '');
    final rawRole = (widget.userToEdit?.role ?? 'cashier').toLowerCase().trim();
    _role = (rawRole == 'admin' || rawRole == 'manager') ? 'manager' : (rawRole == 'owner' ? 'owner' : 'cashier');

    _passwordController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _numericIdController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.userToEdit == null ? 'ADD NEW STAFF ACCOUNT' : 'EDIT STAFF ACCOUNT',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.onSurface,
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
              _buildTextField(
                context: context,
                controller: _nameController,
                label: 'Full Name',
                hint: 'e.g. Sarah Vance',
                icon: Icons.person_outline,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                context: context,
                controller: _numericIdController,
                label: 'Staff Numeric ID',
                hint: 'e.g. 1001 (max 4 digits)',
                icon: Icons.badge_outlined,
                isNumeric: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length > 4) return 'Staff ID cannot exceed 4 digits';
                  return null;
                },
              ),
              const SizedBox(height: 16),
               _buildTextField(
                 context: context,
                 controller: _passwordController,
                 label: widget.userToEdit == null ? 'Password / PIN' : 'New Password / PIN',
                 hint: '4-6 digits',
                 icon: Icons.lock_outline_rounded,
                 obscure: _obscurePassword,
                 isPin: true,
                 suffixIcon: IconButton(
                   icon: Icon(
                     _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                     color: theme.colorScheme.onSurfaceVariant,
                     size: 18,
                   ),
                   onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                 ),
                 validator: (v) {
                   if (widget.userToEdit == null && (v == null || v.isEmpty)) {
                     return 'Required';
                   }
                   if (v != null && v.isNotEmpty && (v.length < 4 || v.length > 6)) {
                     return 'Must be 4-6 digits';
                   }
                   return null;
                 },
               ),
               if (widget.userToEdit != null || _passwordController.text.isNotEmpty) ...[
                 const SizedBox(height: 16),
                 _buildTextField(
                   context: context,
                   controller: _confirmPasswordController,
                   label: 'Confirm PIN',
                   hint: 'Repeat new PIN',
                   icon: Icons.lock_reset_rounded,
                   obscure: _obscurePassword,
                   isPin: true,
                   validator: (v) {
                     if (_passwordController.text.isNotEmpty && v != _passwordController.text) {
                       return 'PINs do not match';
                     }
                     return null;
                   },
                 ),
               ],
              const SizedBox(height: 16),
              _buildRoleDropdown(context),
              const SizedBox(height: 24),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.userToEdit == null ? 'CREATE ACCOUNT' : 'SAVE CHANGES',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isPin = false,
    bool isNumeric = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final int? maxDigits = isNumeric ? 4 : (isPin ? 6 : null);
    final String errorLabel = isNumeric ? "Staff ID cannot exceed 4 digits" : "PIN cannot exceed 6 digits";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            if (maxDigits != null)
              Text(
                'MAX $maxDigits DIGITS',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          maxLength: maxDigits,
          keyboardType: (isPin || isNumeric) ? TextInputType.number : TextInputType.text,
          inputFormatters: [
            if (isPin || isNumeric) FilteringTextInputFormatter.digitsOnly,
            if (maxDigits != null)
              _MaxLengthFormatter(maxDigits, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorLabel),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }),
          ],
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 13),
            prefixIcon: Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 18),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: primaryColor),
            ),
            errorStyle: const TextStyle(color: Color(0xFFDC2626), fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROLE',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: primaryColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: ['owner', 'manager', 'cashier'].contains(_role) ? _role : 'cashier',
              dropdownColor: isDark ? const Color(0xFF151F32) : Colors.white,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.onSurfaceVariant),
              isExpanded: true,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
              borderRadius: BorderRadius.circular(8),
              items: ['owner', 'manager', 'cashier'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value == 'owner' ? 'OWNER / CORPORATE ADMIN' : value.toUpperCase()),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _role = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  void _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      final db = ref.read(databaseServiceProvider);
      final id = _numericIdController.text.trim();
      
      // Check for uniqueness if creating new or changing ID
      if (widget.userToEdit == null || widget.userToEdit!.numericId != id) {
        final existing = await db.getUserByNumericId(id);
        if (existing != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: This Numeric ID is already assigned to another staff member.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      final storeConfig = ref.read(storeConfigProvider).value;
      final currentUser = ref.read(authProvider);

      final user = widget.userToEdit ?? User();
      user.name = _nameController.text;
      user.numericId = _numericIdController.text;
      user.role = _role;
      user.branchCode ??= (storeConfig?.bhfId.isNotEmpty == true) ? storeConfig!.bhfId : (currentUser?.branchCode ?? '00');
      user.branchName ??= (storeConfig?.branchName?.isNotEmpty == true) ? storeConfig!.branchName : (currentUser?.branchName ?? 'Main Branch');

      final rawPassword = _passwordController.text.trim();
      if (rawPassword.isNotEmpty) {
        user.passwordHash = hashPin(rawPassword);
      }
      // If editing and password field is blank, keep the existing hash unchanged.

      await ref.read(usersProvider.notifier).saveUser(user);
      try {
        ref.read(postgresSyncServiceProvider).syncUser(
          user,
          plainPin: rawPassword.isNotEmpty ? rawPassword : null,
        );
      } catch (_) {}
      if (mounted) Navigator.pop(context);
    }
  }
}

class _MaxLengthFormatter extends TextInputFormatter {
  final int maxLength;
  final VoidCallback onLimitReached;

  _MaxLengthFormatter(this.maxLength, this.onLimitReached);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > maxLength) {
      onLimitReached();
      return oldValue;
    }
    return newValue;
  }
}
