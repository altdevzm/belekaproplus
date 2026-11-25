import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/data/digitax_classifications.dart';

enum _ClsFilterTab { production, quickPicks, sandbox, vatAct }

/// Searchable modal dialog over DigiTax Zambia's official UNSPSC / VAT Act
/// item classification tables (1,011 Production codes, 11 Sandbox TEST codes,
/// 8 verified retail quick-picks, plus custom 8-digit code entry).
class DigitaxClassificationPickerDialog extends StatefulWidget {
  final String initialCode;
  final bool isSandboxEnvironment;
  final Color accentColor;

  const DigitaxClassificationPickerDialog({
    super.key,
    required this.initialCode,
    this.isSandboxEnvironment = false,
    this.accentColor = const Color(0xFF3B82F6),
  });

  static Future<String?> show(
    BuildContext context, {
    required String initialCode,
    bool isSandboxEnvironment = false,
    Color accentColor = const Color(0xFF3B82F6),
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => DigitaxClassificationPickerDialog(
        initialCode: initialCode,
        isSandboxEnvironment: isSandboxEnvironment,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<DigitaxClassificationPickerDialog> createState() =>
      _DigitaxClassificationPickerDialogState();
}

class _DigitaxClassificationPickerDialogState
    extends State<DigitaxClassificationPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customCodeController = TextEditingController();
  late _ClsFilterTab _activeTab;
  String _query = '';
  bool _showCustomInput = false;
  String? _customError;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.isSandboxEnvironment
        ? _ClsFilterTab.sandbox
        : _ClsFilterTab.production;
    _customCodeController.text = widget.initialCode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customCodeController.dispose();
    super.dispose();
  }

  List<DigitaxClassification> get _filteredItems {
    List<DigitaxClassification> source;
    switch (_activeTab) {
      case _ClsFilterTab.production:
        source = DigitaxClassifications.productionCodes;
        break;
      case _ClsFilterTab.quickPicks:
        source = DigitaxClassifications.quickPicks;
        break;
      case _ClsFilterTab.sandbox:
        source = DigitaxClassifications.sandboxCodes;
        break;
      case _ClsFilterTab.vatAct:
        source = DigitaxClassifications.productionCodes
            .where((c) => c.code.startsWith('99'))
            .toList(growable: false);
        break;
    }

    final trimmed = _query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return source;
    }

    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    bool matches(DigitaxClassification item) {
      final hay = '${item.code} ${item.name}'.toLowerCase();
      return tokens.every(hay.contains);
    }

    final results = source.where(matches).toList();

    // When searching All Production, also surface matching quick-pick presets
    // whose codes are not in the 1,011 appendix table (e.g. "groceries", "medicines").
    if (_activeTab == _ClsFilterTab.production) {
      final seen = results.map((e) => e.code).toSet();
      for (final qp in DigitaxClassifications.quickPicks) {
        if (!seen.contains(qp.code) && matches(qp)) {
          results.add(qp);
        }
      }
    }

    return results;
  }

  void _applyCustomCode() {
    final raw = _customCodeController.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(raw)) {
      setState(() {
        _customError = 'Enter an exact 8-digit numeric UNSPSC code.';
      });
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final trimmedQuery = _query.trim();
    final queryIsExact8Digit = RegExp(r'^\d{8}$').hasMatch(trimmedQuery);
    final queryInResults =
        queryIsExact8Digit && items.any((i) => i.code == trimmedQuery);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.category_rounded,
                      size: 20,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZRA Item Classification (DigiTax)',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isSandboxEnvironment
                              ? 'Sandbox Mode · ${DigitaxClassifications.sandboxCodes.length} Test codes (${DigitaxClassifications.productionCodes.length} Live available)'
                              : 'Live (Production) · ${DigitaxClassifications.productionCodes.length} official ZRA codes',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: widget.isSandboxEnvironment
                                ? Colors.amber.shade200
                                : const Color(0xFF34D399),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  ),
                ],
              ),
              if (widget.isSandboxEnvironment) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.science_rounded,
                        size: 16,
                        color: Colors.amberAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Store is in Sandbox mode — DigiTax Sandbox accepts 11 specific test codes.',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: Colors.amber.shade100,
                          ),
                        ),
                      ),
                      if (_activeTab != _ClsFilterTab.sandbox)
                        TextButton(
                          onPressed: () =>
                              setState(() => _activeTab = _ClsFilterTab.sandbox),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'View 11 Test Codes',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Search field
              TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white),
                decoration: InputDecoration(
                  hintText:
                      'Search by item name or 8-digit code (e.g. flour, cement, shoes, 9901...)',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white38,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.accentColor, width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() => _query = val),
              ),
              const SizedBox(height: 10),
              // Filter tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.isSandboxEnvironment) ...[
                      _buildFilterChip(
                        label:
                            'Sandbox TEST (${DigitaxClassifications.sandboxCodes.length})',
                        tab: _ClsFilterTab.sandbox,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildFilterChip(
                      label: widget.isSandboxEnvironment
                          ? 'All Production (${DigitaxClassifications.productionCodes.length})'
                          : 'All Live (${DigitaxClassifications.productionCodes.length})',
                      tab: _ClsFilterTab.production,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label:
                          'Quick Picks (${DigitaxClassifications.quickPicks.length})',
                      tab: _ClsFilterTab.quickPicks,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'VAT Act (99*)',
                      tab: _ClsFilterTab.vatAct,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // List of classifications
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.search_off_rounded,
                                  size: 34,
                                  color: Colors.white30,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No classification matched "$_query".',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.white60,
                                  ),
                                ),
                                if (queryIsExact8Digit) ...[
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        Navigator.of(context).pop(trimmedQuery),
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: Text('Use custom code $trimmedQuery'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: widget.accentColor,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount:
                              items.length +
                              (queryIsExact8Digit && !queryInResults ? 1 : 0),
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          itemBuilder: (context, index) {
                            if (queryIsExact8Digit &&
                                !queryInResults &&
                                index == 0) {
                              return ListTile(
                                onTap: () =>
                                    Navigator.of(context).pop(trimmedQuery),
                                leading: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Colors.amberAccent,
                                ),
                                title: Text(
                                  'Use custom 8-digit code: $trimmedQuery',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              );
                            }
                            final item =
                                items[index -
                                    (queryIsExact8Digit && !queryInResults
                                        ? 1
                                        : 0)];
                            final isSelected = item.code == widget.initialCode;
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(item.code),
                              child: Container(
                                color: isSelected
                                    ? widget.accentColor.withValues(alpha: 0.14)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? widget.accentColor.withValues(
                                                alpha: 0.25,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.07,
                                              ),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: isSelected
                                              ? widget.accentColor.withValues(
                                                  alpha: 0.6,
                                                )
                                              : Colors.white.withValues(
                                                  alpha: 0.1,
                                                ),
                                        ),
                                      ),
                                      child: Text(
                                        item.code,
                                        style: GoogleFonts.robotoMono(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              _buildTag(
                                                item.levelLabel,
                                                item.level <= 2
                                                    ? Colors.orangeAccent
                                                    : Colors.white54,
                                              ),
                                              if (widget.isSandboxEnvironment &&
                                                  item.isSandbox)
                                                _buildTag(
                                                  'SANDBOX OK',
                                                  const Color(0xFF10B981),
                                                ),
                                              if (item.isQuickPick)
                                                _buildTag(
                                                  'QUICK PICK',
                                                  Colors.lightBlueAccent,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: widget.accentColor,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Custom code panel + footer count
              if (_showCustomInput) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customCodeController,
                              keyboardType: TextInputType.number,
                              maxLength: 8,
                              style: GoogleFonts.robotoMono(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Custom 8-digit ZRA UNSPSC code',
                                labelStyle: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                                counterText: '',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onSubmitted: (_) => _applyCustomCode(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _applyCustomCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                      if (_customError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _customError!,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Text(
                    'Showing ${items.length} code${items.length == 1 ? '' : 's'}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white54,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showCustomInput = !_showCustomInput;
                        _customError = null;
                      });
                    },
                    icon: Icon(
                      _showCustomInput
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.edit_rounded,
                      size: 16,
                      color: Colors.amberAccent,
                    ),
                    label: Text(
                      _showCustomInput
                          ? 'Hide custom code'
                          : 'Custom 8-digit Code...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amberAccent,
                      ),
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

  Widget _buildFilterChip({required String label, required _ClsFilterTab tab}) {
    final selected = _activeTab == tab;
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : Colors.white70,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _activeTab = tab),
      selectedColor: widget.accentColor.withValues(alpha: 0.35),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      side: BorderSide(
        color: selected
            ? widget.accentColor
            : Colors.white.withValues(alpha: 0.12),
      ),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
