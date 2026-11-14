import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';

class ManagerAuthDialog extends ConsumerStatefulWidget {
  final String title;
  final String message;
  final String? branchCode;

  /// Holds the most recently verified approver (Owner at HQ or assigned Branch Manager at a branch)
  static User? lastAuthorizedUser;

  /// Verifies whether the current user is already authorized for [branchCode]
  /// (Owner at HQ; Assigned Branch Manager or Owner at a sub-branch), or prompts
  /// for the required PIN and returns the approving [User] (with their real name & ID).
  static Future<User?> ensureBranchAuthorized({
    required BuildContext context,
    required WidgetRef ref,
    String title = 'MANAGER AUTHORIZATION',
    String message = 'Please enter the required authorization PIN to proceed.',
    String? branchCode,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final currentUser = ref.read(authProvider);
    final config =
        ref.read(storeConfigProvider).value ??
        await db.isar.storeConfigs.where().findFirst();

    final rawBranch = (branchCode != null && branchCode.trim().isNotEmpty)
        ? branchCode.trim()
        : (currentUser?.branchCode != null &&
                  currentUser!.branchCode!.trim().isNotEmpty
              ? currentUser.branchCode!.trim()
              : (config?.bhfId.trim().isNotEmpty == true
                    ? config!.bhfId.trim()
                    : '00'));

    final allBranches = await db.isar.storeBranchs.where().findAll();
    final normTarget = _ManagerAuthDialogState._normBhf(rawBranch);

    StoreBranch? matchedBranch;
    for (final b in allBranches) {
      if (_ManagerAuthDialogState._normBhf(b.bhfId) == normTarget ||
          _ManagerAuthDialogState._normBhf(b.code) == normTarget ||
          b.bhfId.trim() == rawBranch ||
          b.code.trim() == rawBranch) {
        matchedBranch = b;
        break;
      }
    }

    final bool isHq = matchedBranch != null
        ? (matchedBranch.isHQ ||
              _ManagerAuthDialogState._isHqCode(matchedBranch.bhfId))
        : _ManagerAuthDialogState._isHqCode(rawBranch);

    if (currentUser != null) {
      final r = currentUser.role.trim().toLowerCase();
      final isOwnerRole =
          r == 'owner' || r == 'admin' || r == 'super_admin';
      final isBranchManagerRole = r == 'branch_manager' || r == 'manager';

      if (isHq) {
        if (isOwnerRole) {
          lastAuthorizedUser = currentUser;
          return currentUser;
        }
      } else {
        if (isOwnerRole) {
          lastAuthorizedUser = currentUser;
          return currentUser;
        }
        if (isBranchManagerRole) {
          final assignedId = matchedBranch?.managerId?.trim();
          final matchesAssignedId =
              assignedId != null &&
              assignedId.isNotEmpty &&
              currentUser.numericId.trim() == assignedId;
          final matchesBranchCode =
              currentUser.branchCode != null &&
              currentUser.branchCode!.trim().isNotEmpty &&
              _ManagerAuthDialogState._normBhf(currentUser.branchCode) ==
                  normTarget;
          final noSpecificBranchAssigned =
              (assignedId == null || assignedId.isEmpty) &&
              (currentUser.branchCode == null ||
                  currentUser.branchCode!.trim().isEmpty);

          if (matchesAssignedId ||
              matchesBranchCode ||
              noSpecificBranchAssigned) {
            lastAuthorizedUser = currentUser;
            return currentUser;
          }
        }
      }
    }

    if (!context.mounted) {
      return null;
    }

    lastAuthorizedUser = null;
    final ok =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => ManagerAuthDialog(
            title: title,
            message: message,
            branchCode: rawBranch,
          ),
        ) ??
        false;

    if (!ok) {
      return null;
    }
    return lastAuthorizedUser;
  }

  const ManagerAuthDialog({
    super.key,
    this.title = 'MANAGER AUTHORIZATION',
    this.message = 'Please enter the required authorization PIN to proceed.',
    this.branchCode,
  });

  @override
  ConsumerState<ManagerAuthDialog> createState() => _ManagerAuthDialogState();
}

class _ManagerAuthDialogState extends ConsumerState<ManagerAuthDialog> {
  String _pin = '';
  String? _errorMessage;
  bool _isLoading = false;
  bool _isHqBranch = true;
  String _branchLabel = 'Headquarters (HQ)';
  String? _assignedManagerId;
  String? _assignedManagerName;
  String _normalizedTargetBranch = '00';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveBranchApprovalContext();
    });
  }

  static String _normBhf(String? code) {
    final c = (code ?? '').trim();
    if (c.isEmpty || c == '0' || c == '00' || c == '000') {
      return '00';
    }
    final parsed = int.tryParse(c);
    if (parsed != null) {
      return parsed.toString().padLeft(3, '0');
    }
    return c.toUpperCase();
  }

  static bool _isHqCode(String? code) {
    final c = (code ?? '').trim();
    return c.isEmpty || c == '0' || c == '00' || c == '000' || c == '001';
  }

  Future<void> _resolveBranchApprovalContext() async {
    try {
      final db = ref.read(databaseServiceProvider);
      final currentUser = ref.read(authProvider);
      final config =
          ref.read(storeConfigProvider).value ??
          await db.isar.storeConfigs.where().findFirst();

      final rawBranch =
          (widget.branchCode != null && widget.branchCode!.trim().isNotEmpty)
          ? widget.branchCode!.trim()
          : (currentUser?.branchCode != null &&
                    currentUser!.branchCode!.trim().isNotEmpty
                ? currentUser.branchCode!.trim()
                : (config?.bhfId.trim().isNotEmpty == true
                      ? config!.bhfId.trim()
                      : '00'));

      final allBranches = await db.isar.storeBranchs.where().findAll();
      final normTarget = _normBhf(rawBranch);

      StoreBranch? matchedBranch;
      for (final b in allBranches) {
        if (_normBhf(b.bhfId) == normTarget ||
            _normBhf(b.code) == normTarget ||
            b.bhfId.trim() == rawBranch ||
            b.code.trim() == rawBranch) {
          matchedBranch = b;
          break;
        }
      }

      final bool isHq = matchedBranch != null
          ? (matchedBranch.isHQ || _isHqCode(matchedBranch.bhfId))
          : _isHqCode(rawBranch);

      if (mounted) {
        setState(() {
          _isHqBranch = isHq;
          _normalizedTargetBranch = normTarget;
          _branchLabel = matchedBranch?.name.trim().isNotEmpty == true
              ? matchedBranch!.name.trim()
              : (isHq ? 'Headquarters (HQ)' : 'Branch $rawBranch');
          _assignedManagerId = matchedBranch?.managerId?.trim();
          _assignedManagerName = matchedBranch?.managerName?.trim();
        });
      }
    } catch (_) {}
  }

  void _onKeypadTap(String value) {
    if (_isLoading) {
      return;
    }
    setState(() {
      _errorMessage = null;
      if (value == 'backspace') {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else if (value == 'check') {
        _verifyPin();
      } else {
        if (_pin.length < 6) {
          _pin += value;
        }
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
      final hashedPin = hashPin(_pin);

      User? matchedPinUser;
      User? authorizedUser;

      for (final user in users) {
        if (!user.isActive || user.passwordHash != hashedPin) {
          continue;
        }
        matchedPinUser = user;
        final r = user.role.trim().toLowerCase();
        final isOwnerRole =
            r == 'owner' || r == 'admin' || r == 'super_admin';
        final isBranchManagerRole = r == 'branch_manager' || r == 'manager';

        if (_isHqBranch) {
          // Rule 1: At Headquarters, ONLY the Owner can approve refunds/credit notes & exchanges
          if (isOwnerRole) {
            authorizedUser = user;
            break;
          }
        } else {
          // Rule 2: At a Sub-Branch, the Manager assigned to THIS branch (or Owner) approves
          if (isBranchManagerRole) {
            final matchesAssignedId =
                _assignedManagerId != null &&
                _assignedManagerId!.isNotEmpty &&
                user.numericId.trim() == _assignedManagerId;
            final matchesBranchCode =
                user.branchCode != null &&
                user.branchCode!.trim().isNotEmpty &&
                _normBhf(user.branchCode) == _normalizedTargetBranch;
            final noSpecificBranchAssigned =
                (_assignedManagerId == null || _assignedManagerId!.isEmpty) &&
                (user.branchCode == null || user.branchCode!.trim().isEmpty);

            if (matchesAssignedId ||
                matchesBranchCode ||
                noSpecificBranchAssigned) {
              authorizedUser = user;
              break;
            }
          } else if (isOwnerRole) {
            authorizedUser = user;
            break;
          }
        }
      }

      if (authorizedUser != null) {
        ManagerAuthDialog.lastAuthorizedUser = authorizedUser;
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        String specificError;
        if (matchedPinUser != null) {
          if (_isHqBranch) {
            specificError =
                'Headquarters requires Owner PIN approval (${matchedPinUser.name} is not Owner).';
          } else if (_assignedManagerName != null &&
              _assignedManagerName!.isNotEmpty) {
            specificError =
                'Only $_assignedManagerName (assigned manager for $_branchLabel) or Owner can approve.';
          } else {
            specificError =
                'Only the Manager assigned to $_branchLabel (or Owner) can approve.';
          }
        } else {
          specificError = _isHqBranch
              ? 'Invalid Owner PIN for Headquarters'
              : 'Invalid Branch Manager PIN for $_branchLabel';
        }

        setState(() {
          _errorMessage = specificError;
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
    final requiredApproverText = _isHqBranch
        ? 'HQ APPROVAL: OWNER PIN REQUIRED'
        : (_assignedManagerName != null && _assignedManagerName!.isNotEmpty
              ? '$_branchLabel: MANAGER (${_assignedManagerName!.toUpperCase()}) PIN REQUIRED'
              : '$_branchLabel: ASSIGNED BRANCH MANAGER PIN REQUIRED');

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340,
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
              child: const Icon(
                Icons.shield_outlined,
                color: Color(0xFFC1F11D),
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFC1F11D).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFC1F11D).withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                requiredApproverText,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFC1F11D),
                  letterSpacing: 0.5,
                ),
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
            const SizedBox(height: 20),

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
                  color: _pin.isEmpty
                      ? Colors.white24
                      : const Color(0xFFC1F11D),
                  letterSpacing: 8,
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Keypad
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ...List.generate(
                  9,
                  (index) => _buildKeyItem((index + 1).toString()),
                ),
                _buildKeyItem('backspace', isIcon: true),
                _buildKeyItem('0'),
                _buildKeyItem('check', isIcon: true),
              ],
            ),

            const SizedBox(height: 20),

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
            color: isIcon
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          alignment: Alignment.center,
          child: _isLoading && val == 'check'
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFC1F11D),
                  ),
                )
              : isIcon
              ? Icon(
                  val == 'backspace'
                      ? Icons.backspace_outlined
                      : Icons.check_circle_outline,
                  color: val == 'check'
                      ? const Color(0xFFC1F11D)
                      : Colors.white70,
                  size: 20,
                )
              : Text(
                  val,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
