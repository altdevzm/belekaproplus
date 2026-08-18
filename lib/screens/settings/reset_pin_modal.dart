import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/users_provider.dart';
import 'package:beleka_pos/services/database_service.dart';

class ResetPinModal extends ConsumerStatefulWidget {
  final User user;
  final String title;

  const ResetPinModal({
    super.key, 
    required this.user, 
    this.title = 'RESET SECURITY PIN',
  });

  @override
  ConsumerState<ResetPinModal> createState() => _ResetPinModalState();
}

class _ResetPinModalState extends ConsumerState<ResetPinModal> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _handleReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = widget.user;
      user.passwordHash = hashPin(_pinController.text.trim());
      
      await ref.read(usersProvider.notifier).saveUser(user);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PIN updated successfully for ${user.name}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
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
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: const Color(0xFFC1F11D),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white24, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Staff: ${widget.user.name} (${widget.user.numericId})',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 32),
              _buildPinField(
                controller: _pinController,
                label: 'NEW SECURITY PIN',
                hint: '4-6 digits',
              ),
              const SizedBox(height: 20),
              _buildPinField(
                controller: _confirmPinController,
                label: 'CONFIRM NEW PIN',
                hint: 'Repeat PIN',
                validator: (v) {
                  if (v != _pinController.text) return 'PINs do not match';
                  return null;
                },
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text(
                        'UPDATE SECURITY PIN',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
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

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.4),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          obscureText: _obscure,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _MaxLengthFormatter(6, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("PIN cannot exceed 6 digits"),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }),
          ],
          style: GoogleFonts.ibmPlexMono(
            color: Colors.white, 
            fontSize: 18, 
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.ibmPlexMono(color: Colors.white10, fontSize: 14, letterSpacing: 2),
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.white24, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white10),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.02),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (v.length < 4) return 'Min 4 digits';
            if (validator != null) return validator(v);
            return null;
          },
        ),
      ],
    );
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
