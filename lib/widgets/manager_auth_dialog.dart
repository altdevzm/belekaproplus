import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/models/models.dart';

class ManagerAuthDialog extends ConsumerStatefulWidget {
  final String title;
  final String message;

  const ManagerAuthDialog({
    super.key,
    this.title = 'MANAGER AUTHORIZATION',
    this.message = 'Please enter Manager or Admin PIN to proceed.',
  });

  @override
  ConsumerState<ManagerAuthDialog> createState() => _ManagerAuthDialogState();
}

class _ManagerAuthDialogState extends ConsumerState<ManagerAuthDialog> {
  String _pin = '';
  String? _errorMessage;
  bool _isLoading = false;

  void _onKeypadTap(String value) {
    if (_isLoading) return;
    setState(() {
      _errorMessage = null;
      if (value == 'backspace') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (value == 'check') {
        _verifyPin();
      } else {
        if (_pin.length < 6) _pin += value;
      }
    });
  }

  Future<void> _verifyPin() async {
    if (_pin.length < 4) {
      setState(() => _errorMessage = 'Enter at least 4 digits');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final users = await db.getAllUsers();
      
      User? authorizedUser;
      
      // hashPin is available in database_service.dart
      final hashedPin = hashPin(_pin);
      for (final user in users) {
        if ((user.role == 'manager' || user.role == 'admin') && user.passwordHash == hashedPin) {
          authorizedUser = user;
          break;
        }
      }

      if (authorizedUser != null) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _errorMessage = 'Invalid Manager/Admin PIN';
          _pin = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verification error';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, color: Color(0xFFC1F11D), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            
            // PIN Display
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                _pin.isEmpty ? '••••••' : '• ' * _pin.length,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _pin.isEmpty ? Colors.white24 : const Color(0xFFC1F11D),
                  letterSpacing: 8,
                ),
              ),
            ),
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: GoogleFonts.manrope(
                  color: Colors.redAccent, 
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Keypad
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ...List.generate(9, (index) => _buildKeyItem((index + 1).toString())),
                _buildKeyItem('backspace', isIcon: true),
                _buildKeyItem('0'),
                _buildKeyItem('check', isIcon: true),
              ],
            ),
            
            const SizedBox(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'CANCEL',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white38,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyItem(String val, {bool isIcon = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeypadTap(val),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isIcon ? Colors.white.withValues(alpha: 0.03) : Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          alignment: Alignment.center,
          child: _isLoading && val == 'check'
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC1F11D)))
            : isIcon 
              ? Icon(val == 'backspace' ? Icons.backspace_outlined : Icons.check_circle_outline, 
                     color: val == 'check' ? const Color(0xFFC1F11D) : Colors.white70, size: 20)
              : Text(val, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      ),
    );
  }
}
