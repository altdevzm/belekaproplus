import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:isar/isar.dart';

/// Quick dialog to create a category and immediately return it
Future<Category?> showQuickCreateCategoryDialog(BuildContext context, WidgetRef ref) async {
  final nameCtrl = TextEditingController();
  CategorySector selectedSector = CategorySector.other;
  final accentColor = ref.read(accentColorProvider);

  return await showDialog<Category>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF16161C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.create_new_folder_rounded, color: accentColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'CREATE CATEGORY',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.3)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'CATEGORY NAME',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. Footwear, Beverages, Dairy, Snacks',
                        hintStyle: GoogleFonts.inter(color: Colors.white10),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'RETAIL SECTOR / TAG',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<CategorySector>(
                        value: selectedSector,
                        dropdownColor: const Color(0xFF141418),
                        isExpanded: true,
                        icon: const Icon(Icons.expand_more, color: Colors.white24),
                        items: CategorySector.values.map((sector) {
                          return DropdownMenuItem<CategorySector>(
                            value: sector,
                            child: Text(
                              sector.name.toUpperCase(),
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedSector = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        final db = ref.read(databaseServiceProvider);
                        final newCategory = Category(
                          name: name,
                          sector: selectedSector,
                        );
                        await db.isar.writeTxn(() async {
                          await db.isar.categorys.put(newCategory);
                        });
                        ref.invalidate(categoriesProvider);
                        if (context.mounted) {
                          Navigator.pop(context, newCategory);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        'CREATE CATEGORY',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class CategoryManagementModal extends ConsumerStatefulWidget {
  const CategoryManagementModal({super.key});

  @override
  ConsumerState<CategoryManagementModal> createState() => _CategoryManagementModalState();
}

class _CategoryManagementModalState extends ConsumerState<CategoryManagementModal> {
  final _nameController = TextEditingController();
  CategorySector _selectedSector = CategorySector.other;
  bool _isLoading = false;
  List<Category> _categories = [];
  Map<int, int> _productCounts = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadCategories());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    final db = ref.read(databaseServiceProvider);
    setState(() => _isLoading = true);
    try {
      final categories = await db.isar.categorys.where().findAll();
      final products = await db.isar.products.where().findAll();
      
      final Map<int, int> counts = {};
      for (final p in products) {
        counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _productCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCategory({Category? existing}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseServiceProvider);

    final category = existing ?? Category(name: name);
    category.name = name;
    category.sector = _selectedSector;

    await db.isar.writeTxn(() async {
      await db.isar.categorys.put(category);
    });

    ref.invalidate(categoriesProvider);

    _nameController.clear();
    if (mounted) setState(() => _selectedSector = CategorySector.other);
    _loadCategories();
  }

  Future<void> _deleteCategory(Id id) async {
    final count = _productCounts[id] ?? 0;
    if (count > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A20),
          title: Text('Delete Category?', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            'There are $count products allocated to this category. Deleting will unassign their category.',
            style: GoogleFonts.inter(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final db = ref.read(databaseServiceProvider);
    await db.isar.writeTxn(() async {
      await db.isar.categorys.delete(id);
    });

    ref.invalidate(categoriesProvider);
    _loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final accentColor = primaryColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 640,
        height: 700,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.category_rounded, color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CATEGORY MANAGEMENT',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'ORGANIZE AND ALLOCATE YOUR INVENTORY',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white24),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Add New Category Section
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CREATE NEW CATEGORY',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _nameController,
                          style: GoogleFonts.inter(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Category Name (e.g. Electronics, Bakery)',
                            hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                            filled: true,
                            fillColor: Colors.black26,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _saveCategory(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<CategorySector>(
                              value: _selectedSector,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1A1A20),
                              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white24),
                              items: CategorySector.values.map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.name.toUpperCase(),
                                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedSector = v!),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _saveCategory(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text('Add', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: accentColor))
                  : _categories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.category_outlined, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                              const SizedBox(height: 12),
                              Text(
                                'No categories yet. Create your first category above.',
                                style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _categories.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final productCount = _productCounts[category.id] ?? 0;
                            final color = _getSectorColor(category.sector);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: color.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      category.sector.name.toUpperCase(),
                                      style: GoogleFonts.ibmPlexMono(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: color,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          category.name.toUpperCase(),
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$productCount allocated products',
                                          style: GoogleFonts.inter(
                                            color: Colors.white30,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      _nameController.text = category.name;
                                      setState(() => _selectedSector = category.sector);
                                      _showEditDialog(category);
                                    },
                                    icon: const Icon(Icons.edit_outlined, color: Colors.white38, size: 18),
                                    tooltip: 'Edit Category',
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteCategory(category.id),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    tooltip: 'Delete Category',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSectorColor(CategorySector sector) {
    switch (sector) {
      case CategorySector.pharmacy: return const Color(0xFF00D1FF);
      case CategorySector.stationery: return const Color(0xFFB565FF);
      case CategorySector.grocery: return const Color(0xFF00FF85);
      case CategorySector.food: return const Color(0xFFFF5C00);
      case CategorySector.restaurant: return const Color(0xFFF39C12);
      case CategorySector.other: return const Color(0xFFC1F11D);
    }
  }

  void _showEditDialog(Category category) {
    final editNameCtrl = TextEditingController(text: category.name);
    CategorySector editSector = category.sector;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setEditState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A20),
            title: Text('Edit Category', style: GoogleFonts.manrope(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: editNameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButton<CategorySector>(
                  value: editSector,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF141418),
                  items: CategorySector.values.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(s.name.toUpperCase(), style: const TextStyle(color: Colors.white70)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setEditState(() => editSector = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final db = ref.read(databaseServiceProvider);
                  category.name = editNameCtrl.text.trim();
                  category.sector = editSector;
                  await db.isar.writeTxn(() async {
                    await db.isar.categorys.put(category);
                  });
                  ref.invalidate(categoriesProvider);
                  _loadCategories();
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ref.read(accentColorProvider), 
                  foregroundColor: Colors.black,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
