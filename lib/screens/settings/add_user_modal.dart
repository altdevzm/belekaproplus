import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/users_provider.dart';
import 'package:beleka_pos/services/database_service.dart';

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
    _role = widget.userToEdit?.role ?? 'cashier';

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
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(40),
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
                    widget.userToEdit == null ? 'ADD NEW STAFF' : 'EDIT STAFF',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: const Color(0xFFC1F11D),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white24, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'e.g. Sarah Vance',
                icon: Icons.person_outline,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
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
              const SizedBox(height: 20),
               _buildTextField(
                 controller: _passwordController,
                 label: widget.userToEdit == null ? 'Password / PIN' : 'New Password / PIN',
                 hint: '4-6 digits',
                 icon: Icons.lock_outline_rounded,
                 obscure: _obscurePassword,
                 isPin: true,
                 suffixIcon: IconButton(
                   icon: Icon(
                     _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                     color: Colors.white24,
                     size: 18,
                   ),
                   onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                 ),
                 validator: (v) {
                   // When editing, password is optional (skip blank means no change)
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
                 const SizedBox(height: 20),
                 _buildTextField(
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
              const SizedBox(height: 20),
              _buildRoleDropdown(),
              const SizedBox(height: 48),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.userToEdit == null ? 'CREATE ACCOUNT' : 'SAVE CHANGES',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      fontSize: 14,
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
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 1,
              ),
            ),
            if (maxDigits != null)
              Text(
                'MAX $maxDigits DIGITS',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.25),
                  letterSpacing: 1,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
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
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white10),
            prefixIcon: Icon(icon, color: Colors.white24, size: 18),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.02),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFFC1F11D).withValues(alpha: 0.3)),
            ),
            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROLE',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.4),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _role,
              dropdownColor: const Color(0xFF1A1A1F),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white24),
              isExpanded: true,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              borderRadius: BorderRadius.circular(12),
              items: ['manager', 'cashier'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value.toUpperCase()),
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

      final user = widget.userToEdit ?? User();
      user.name = _nameController.text;
      user.numericId = _numericIdController.text;
      user.role = _role;

      final rawPassword = _passwordController.text;
      if (rawPassword.isNotEmpty) {
        user.passwordHash = hashPin(rawPassword);
      }
      // If editing and password field is blank, keep the existing hash unchanged.

      await ref.read(usersProvider.notifier).saveUser(user);
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
