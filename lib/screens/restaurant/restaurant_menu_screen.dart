import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/restaurant_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/screens/restaurant/restaurant_modal_widgets.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/restaurant_service.dart';

class RestaurantMenuScreen extends ConsumerStatefulWidget {
  const RestaurantMenuScreen({super.key});

  @override
  ConsumerState<RestaurantMenuScreen> createState() =>
      _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  final _searchCtrl = TextEditingController();

  Future<String?> _pickAndSaveFoodImage(String prefix) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      final srcPath = res?.files.single.path;
      if (srcPath == null || srcPath.isEmpty) {
        return null;
      }
      final docsDir = await getApplicationDocumentsDirectory();
      final foodDir = Directory(path_pkg.join(docsDir.path, 'food_images'));
      if (!await foodDir.exists()) {
        await foodDir.create(recursive: true);
      }
      final ext = path_pkg.extension(srcPath).isEmpty
          ? '.png'
          : path_pkg.extension(srcPath);
      final fileName =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final destFile = await File(srcPath).copy(
        path_pkg.join(foodDir.path, fileName),
      );
      return destFile.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach image: $e')),
        );
      }
      return null;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandColor = theme.colorScheme.primary;
    final productsAsync = ref.watch(allInventoryProductsProvider);
    final stations = ref.watch(kitchenStationsProvider).valueOrNull ?? [];
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: brandColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          color: brandColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Restaurant Menu & Kitchen Routing',
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Configure dish availability, kitchen stations, paid extras/modifiers & recipes',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () =>
                        _showCreateMenuDishDialog(stations, currency),
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('New Menu Dish'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search menu items by name or SKU...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: productsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (products) {
                  final menuDishes = products
                      .where(
                        (p) =>
                            !p.isArchived &&
                            (p.restaurantProductType == 'menu_item' ||
                                p.restaurantProductType == 'both'),
                      )
                      .toList();
                  final q = _searchCtrl.text.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? menuDishes
                      : menuDishes
                          .where(
                            (p) =>
                                p.name.toLowerCase().contains(q) ||
                                p.sku.toLowerCase().contains(q),
                          )
                          .toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No products found in Inventory.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, idx) {
                      final p = filtered[idx];
                      final stnName = stations
                              .where((s) => s.id == p.kitchenStationId)
                              .firstOrNull
                              ?.name ??
                          'Main Kitchen';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 360,
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      final saved =
                                          await _pickAndSaveFoodImage(
                                        'dish_${p.id}',
                                      );
                                      if (saved == null) return;
                                      final db = ref.read(
                                        databaseServiceProvider,
                                      );
                                      await db.isar.writeTxn(() async {
                                        p.imagePath = saved;
                                        await db.isar.products.put(p);
                                      });
                                      if (mounted) setState(() {});
                                    },
                                    child: Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.25),
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: p.imagePath != null &&
                                              p.imagePath!.isNotEmpty &&
                                              File(p.imagePath!).existsSync()
                                          ? Image.file(
                                              File(p.imagePath!),
                                              fit: BoxFit.cover,
                                            )
                                          : Icon(
                                              Icons.add_photo_alternate_rounded,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              size: 24,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                p.name,
                                                style: GoogleFonts.manrope(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15.5,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '$currency ${p.price.toStringAsFixed(2)}',
                                              style: GoogleFonts.ibmPlexMono(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: brandColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Station: $stnName  •  Prep: ${p.prepTimeMinutes}m  •  Type: ${p.restaurantProductType}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Large Touch-Friendly Action Buttons
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final db = ref.read(databaseServiceProvider);
                                    await db.isar.writeTxn(() async {
                                      p.isAvailableNow = !p.isAvailableNow;
                                      await db.isar.products.put(p);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (p.isAvailableNow
                                              ? const Color(0xFF10B981)
                                              : Colors.redAccent)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: p.isAvailableNow
                                            ? const Color(0xFF10B981)
                                            : Colors.redAccent,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          p.isAvailableNow
                                              ? Icons.check_circle_rounded
                                              : Icons.block_rounded,
                                          size: 16,
                                          color: p.isAvailableNow
                                              ? const Color(0xFF10B981)
                                              : Colors.redAccent,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          p.isAvailableNow
                                              ? 'Available'
                                              : '86 / Out of Stock',
                                          style: GoogleFonts.manrope(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: p.isAvailableNow
                                                ? const Color(0xFF10B981)
                                                : Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final saved = await _pickAndSaveFoodImage(
                                      'dish_${p.id}',
                                    );
                                    if (saved == null) return;
                                    final db = ref.read(
                                      databaseServiceProvider,
                                    );
                                    await db.isar.writeTxn(() async {
                                      p.imagePath = saved;
                                      await db.isar.products.put(p);
                                    });
                                    if (mounted) setState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    size: 17,
                                  ),
                                  label: Text(
                                    p.imagePath != null &&
                                            p.imagePath!.isNotEmpty
                                        ? 'Change PNG'
                                        : 'Dish PNG',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _showProductRestaurantSettings(p, stations),
                                  icon: const Icon(Icons.tune_rounded, size: 17),
                                  label: const Text('Station & Prep'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () => _showModifiersDialog(p),
                                  icon: const Icon(
                                    Icons.playlist_add_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Extras / Modifiers'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () => _showRecipeDialog(p, products),
                                  icon: const Icon(
                                    Icons.blender_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('Recipe'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductRestaurantSettings(
    Product p,
    List<KitchenStation> stations,
  ) async {
    int? stationId = stations.any((s) => s.id == p.kitchenStationId)
        ? p.kitchenStationId
        : (stations.isNotEmpty ? stations.first.id : null);
    const validTypes = ['menu_item', 'ingredient', 'both'];
    String prodType = validTypes.contains(p.restaurantProductType)
        ? p.restaurantProductType
        : 'menu_item';
    bool useRecipe = p.useRecipeStockDeduction;
    final prepCtrl = TextEditingController(text: p.prepTimeMinutes.toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => RestaurantModalShell(
          icon: Icons.tune_rounded,
          title: p.name,
          subtitle: 'Kitchen station routing, prep time & recipe deduction',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Save Settings'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildModalFieldLabel(ctx, 'Kitchen Station'),
              DropdownButtonFormField<int>(
                initialValue: stationId,
                decoration: restaurantInputDecoration(ctx),
                items: stations
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setLocal(() => stationId = v);
                  }
                },
              ),
              const SizedBox(height: 16),
              buildModalFieldLabel(ctx, 'Menu Classification'),
              DropdownButtonFormField<String>(
                initialValue: prodType,
                decoration: restaurantInputDecoration(ctx),
                items: const [
                  DropdownMenuItem(
                    value: 'menu_item',
                    child: Text('Menu Item (Sold to Guests)'),
                  ),
                  DropdownMenuItem(
                    value: 'ingredient',
                    child: Text('Ingredient Only (Hidden from Menu)'),
                  ),
                  DropdownMenuItem(
                    value: 'both',
                    child: Text('Both Menu Item & Ingredient'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setLocal(() => prodType = v);
                  }
                },
              ),
              const SizedBox(height: 16),
              buildModalFieldLabel(ctx, 'Estimated Prep Time (Minutes)'),
              TextField(
                controller: prepCtrl,
                keyboardType: TextInputType.number,
                decoration: restaurantInputDecoration(
                  ctx,
                  hintText: 'e.g. 10',
                  prefixIcon: const Icon(Icons.timer_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(ctx)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: SwitchListTile(
                  title: Text(
                    'Deduct Recipe Ingredients on Sale',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: const Text(
                    'Automatically subtract linked raw ingredients when sold',
                  ),
                  value: useRecipe,
                  onChanged: (v) => setLocal(() => useRecipe = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      final db = ref.read(databaseServiceProvider);
      await db.isar.writeTxn(() async {
        p.kitchenStationId = stationId;
        p.restaurantProductType = prodType;
        p.prepTimeMinutes = int.tryParse(prepCtrl.text.trim()) ?? 10;
        p.useRecipeStockDeduction = useRecipe;
        await db.isar.products.put(p);
      });
    }
    prepCtrl.dispose();
  }

  Future<void> _showModifiersDialog(Product p) async {
    final svc = ref.read(restaurantServiceProvider);
    var groups = await svc.getModifiersForProduct(p.id);
    final allStock =
        ref.read(allInventoryProductsProvider).valueOrNull ?? const [];
    final recipe = await svc.getRecipeForProduct(p.id);
    if (!mounted) {
      return;
    }
    final groupNameCtrl = TextEditingController(text: 'Extras');
    final optNameCtrl = TextEditingController();
    final optPriceCtrl = TextEditingController(text: '0');
    String? newOptImagePath;
    String? formError;

    // Combine recipe ingredients + Stock ingredients for quick extra picking
    final extraSourceNames = <String, double>{};
    for (final r in recipe) {
      extraSourceNames[r.ingredientName] = r.unitPrice;
    }
    for (final item in allStock.where(
      (s) => s.id != p.id && s.restaurantProductType == 'ingredient',
    )) {
      extraSourceNames.putIfAbsent(item.name, () => item.price);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => RestaurantModalShell(
          icon: Icons.playlist_add_rounded,
          title: 'Extras & Modifiers',
          subtitle: p.name,
          width: 540,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (groups.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'No modifier groups yet. Add one below (e.g. Paid Extras: Extra Cheese, Extra Cream).',
                  ),
                )
              else
                ...groups.map(
                  (g) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.name,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Builder(
                                builder: (_) {
                                  List<Map<String, dynamic>> parsedOpts = [];
                                  try {
                                    final raw =
                                        jsonDecode(g.optionsJson) as List;
                                    parsedOpts = raw
                                        .whereType<Map>()
                                        .map(
                                          (m) => Map<String, dynamic>.from(m),
                                        )
                                        .toList();
                                  } catch (_) {}
                                  return Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: parsedOpts.asMap().entries.map((
                                      entry,
                                    ) {
                                      final i = entry.key;
                                      final opt = entry.value;
                                      final img = opt['imagePath']?.toString();
                                      final hasImg =
                                          img != null &&
                                          img.isNotEmpty &&
                                          File(img).existsSync();
                                      return ActionChip(
                                        avatar: hasImg
                                            ? CircleAvatar(
                                                backgroundImage: FileImage(
                                                  File(img),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.add_photo_alternate_outlined,
                                                size: 16,
                                              ),
                                        label: Text(
                                          '${opt['name']} (+${opt['price'] ?? 0})',
                                        ),
                                        tooltip:
                                            'Tap to attach/change layer PNG',
                                        onPressed: () async {
                                          final saved =
                                              await _pickAndSaveFoodImage(
                                            'extra_${p.id}_${g.id}_$i',
                                          );
                                          if (saved == null) return;
                                          parsedOpts[i]['imagePath'] = saved;
                                          g.optionsJson =
                                              jsonEncode(parsedOpts);
                                          await svc.saveModifierGroup(g);
                                          groups = await svc
                                              .getModifiersForProduct(p.id);
                                          setLocal(() {});
                                        },
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () async {
                            await svc.deleteModifierGroup(g.id);
                            groups = await svc.getModifiersForProduct(p.id);
                            setLocal(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 28),
              Text(
                'Add New Modifier Group',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              if (extraSourceNames.isNotEmpty) ...[
                buildModalFieldLabel(
                  ctx,
                  'Quick-Fill from Recipe / Mini-Stock (Optional)',
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: extraSourceNames.entries.map((entry) {
                    return ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 15),
                      label: Text('Extra ${entry.key}'),
                      onPressed: () {
                        setLocal(() {
                          optNameCtrl.text = 'Extra ${entry.key}';
                          if (entry.value > 0) {
                            optPriceCtrl.text = entry.value.toStringAsFixed(2);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              buildModalFieldLabel(ctx, 'Group Name'),
              TextField(
                controller: groupNameCtrl,
                decoration: restaurantInputDecoration(
                  ctx,
                  hintText: 'e.g. Paid Extras, Spice Level',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildModalFieldLabel(ctx, 'Options (Comma Separated)'),
                        TextField(
                          controller: optNameCtrl,
                          decoration: restaurantInputDecoration(
                            ctx,
                            hintText: 'Extra Cheese, Extra Cream',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildModalFieldLabel(ctx, 'Extra Price'),
                        TextField(
                          controller: optPriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: restaurantInputDecoration(ctx, hintText: '0'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await _pickAndSaveFoodImage(
                        'extra_${p.id}',
                      );
                      if (saved != null) {
                        setLocal(() => newOptImagePath = saved);
                      }
                    },
                    icon: const Icon(
                      Icons.add_photo_alternate_rounded,
                      size: 18,
                    ),
                    label: Text(
                      newOptImagePath != null
                          ? 'Layer PNG Attached'
                          : 'Attach Layer PNG (Optional)',
                    ),
                  ),
                  if (newOptImagePath != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(newOptImagePath!),
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove PNG',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setLocal(() => newOptImagePath = null),
                    ),
                  ],
                ],
              ),
              if (formError != null) ...[
                const SizedBox(height: 8),
                Text(
                  formError!,
                  style: GoogleFonts.inter(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Extra / Modifier'),
                  onPressed: () async {
                    final grpName = groupNameCtrl.text.trim().isEmpty
                        ? 'Extras'
                        : groupNameCtrl.text.trim();
                    final extra =
                        double.tryParse(optPriceCtrl.text.trim()) ?? 0.0;
                    final opts = optNameCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .map((s) {
                          final optMap = <String, dynamic>{
                            'name': s,
                            'price': extra,
                          };
                          if (newOptImagePath != null) {
                            optMap['imagePath'] = newOptImagePath;
                          }
                          return optMap;
                        })
                        .toList();
                    if (opts.isEmpty) {
                      setLocal(() {
                        formError =
                            'Please enter at least one Extra name (e.g. Chocolate Layer).';
                      });
                      return;
                    }
                    formError = null;
                    final existingGroup = groups
                        .where(
                          (g) => g.name.toLowerCase() == grpName.toLowerCase(),
                        )
                        .firstOrNull;
                    if (existingGroup != null) {
                      List<dynamic> currentOpts = [];
                      try {
                        currentOpts =
                            jsonDecode(existingGroup.optionsJson) as List;
                      } catch (_) {}
                      currentOpts.addAll(opts);
                      existingGroup.optionsJson = jsonEncode(currentOpts);
                      await svc.saveModifierGroup(existingGroup);
                    } else {
                      final g = ProductModifierGroup(
                        productId: p.id,
                        name: grpName,
                        allowMultiple: true,
                        optionsJson: jsonEncode(opts),
                      );
                      await svc.saveModifierGroup(g);
                    }
                    groups = await svc.getModifiersForProduct(p.id);
                    optNameCtrl.clear();
                    optPriceCtrl.text = '0';
                    newOptImagePath = null;
                    setLocal(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    groupNameCtrl.dispose();
    optNameCtrl.dispose();
    optPriceCtrl.dispose();
  }

  Future<void> _showCreateMenuDishDialog(
    List<KitchenStation> stations,
    String currency,
  ) async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    int? stationId = stations.firstOrNull?.id;
    String? dishImagePath;
    String? formError;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => RestaurantModalShell(
          icon: Icons.restaurant_menu_rounded,
          title: 'New Menu Dish',
          subtitle:
              'Create a saleable restaurant dish (e.g. Chicken Burger). Link Stock ingredients under Recipe next.',
          width: 520,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  setLocal(() => formError = 'Please enter a dish name.');
                  return;
                }
                if ((double.tryParse(priceCtrl.text.trim()) ?? -1) < 0) {
                  setLocal(
                    () => formError = 'Please enter a valid selling price.',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Create Dish'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildModalFieldLabel(ctx, 'Dish Name'),
              TextField(
                controller: nameCtrl,
                decoration: restaurantInputDecoration(
                  ctx,
                  hintText: 'e.g. Chicken Burger, Chips & Chicken',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildModalFieldLabel(ctx, 'Selling Price ($currency)'),
                        TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: restaurantInputDecoration(
                            ctx,
                            hintText: '95.00',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildModalFieldLabel(ctx, 'SKU / Code (Optional)'),
                        TextField(
                          controller: skuCtrl,
                          decoration: restaurantInputDecoration(
                            ctx,
                            hintText: 'Auto-generated',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (stations.isNotEmpty) ...[
                buildModalFieldLabel(ctx, 'Kitchen Station'),
                DropdownButtonFormField<int>(
                  initialValue: stationId,
                  decoration: restaurantInputDecoration(ctx),
                  items: stations
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => stationId = v),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await _pickAndSaveFoodImage('dish_new');
                      if (saved != null) {
                        setLocal(() => dishImagePath = saved);
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: Text(
                      dishImagePath != null
                          ? 'Dish PNG Attached'
                          : 'Attach Dish PNG (Optional)',
                    ),
                  ),
                  if (dishImagePath != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(dishImagePath!),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ],
              ),
              if (formError != null) ...[
                const SizedBox(height: 10),
                Text(
                  formError!,
                  style: GoogleFonts.inter(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (created == true && mounted) {
      final db = ref.read(databaseServiceProvider);
      final config = ref.read(storeConfigProvider).valueOrNull;
      final branch = ref.read(activeRestaurantBranchProvider);
      final sku = skuCtrl.text.trim().isNotEmpty
          ? skuCtrl.text.trim()
          : 'MENU-${DateTime.now().millisecondsSinceEpoch % 100000}';
      final prod = Product(
        name: nameCtrl.text.trim(),
        sku: sku,
        price: double.tryParse(priceCtrl.text.trim()) ?? 0.0,
        stockLevel: 0,
        categoryId: 0,
      )
        ..imagePath = dishImagePath
        ..branchCode = branch
        ..branchName = config?.branchName
        ..restaurantProductType = 'menu_item'
        ..isAvailableNow = true
        ..useRecipeStockDeduction = true
        ..kitchenStationId = stationId;
      await db.isar.writeTxn(() async {
        await db.isar.products.put(prod);
      });
    }

    nameCtrl.dispose();
    priceCtrl.dispose();
    skuCtrl.dispose();
  }

  Future<void> _showRecipeDialog(Product p, List<Product> allProducts) async {
    final svc = ref.read(restaurantServiceProvider);
    final config = ref.read(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';
    final existing = await svc.getRecipeForProduct(p.id);
    final ingredients = List<RecipeIngredient>.from(existing);
    if (!mounted) {
      return;
    }

    // Pull raw ingredients from Stock (prioritizing items marked 'ingredient')
    final stockCandidates = allProducts
        .where((x) => !x.isArchived && x.id != p.id)
        .toList()
      ..sort((a, b) {
        final aIsIng = a.restaurantProductType == 'ingredient' ? 0 : 1;
        final bIsIng = b.restaurantProductType == 'ingredient' ? 0 : 1;
        if (aIsIng != bIsIng) return aIsIng.compareTo(bIsIng);
        return a.name.compareTo(b.name);
      });

    Product? selectedIng = stockCandidates.firstOrNull;
    final qtyCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController(text: 'pcs');
    final lineCostCtrl = TextEditingController(
      text: (selectedIng?.unitCost ?? 0.0).toStringAsFixed(2),
    );
    bool applyPriceToDish = p.price == 0.0;

    double calcTotalCost() => ingredients.fold<double>(
      0.0,
      (sum, ing) => sum + (ing.quantityRequired * ing.unitCost),
    );

    final finalPriceCtrl = TextEditingController(
      text: (p.price > 0 ? p.price : calcTotalCost()).toStringAsFixed(2),
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final totalCost = calcTotalCost();
          return RestaurantModalShell(
            icon: Icons.blender_outlined,
            title: 'Recipe & Costing',
            subtitle:
                '${p.name} • Current Dish Price: $currency ${p.price.toStringAsFixed(2)}',
            width: 600,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final parsedFinalPrice = double.tryParse(
                    finalPriceCtrl.text.trim(),
                  );
                  await svc.saveRecipeIngredients(
                    p.id,
                    ingredients,
                    updateProductPricing: applyPriceToDish,
                    sellingPriceOverride: parsedFinalPrice,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save Recipe'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                const Color(0xFF3B82F6).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Select raw ingredients from Stock (e.g. Tomatoes, Potatoes, Cooking Oil, Chicken) and set the unit & quantity used to make "${p.name}". Total stock cost is calculated automatically.',
                          style: GoogleFonts.inter(fontSize: 12, height: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (ingredients.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('No recipe ingredients added yet.'),
                  )
                else
                  ...ingredients.map(
                    (ing) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ing.ingredientName,
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  'Qty: ${ing.quantityRequired} ${ing.unitOfMeasure}  •  Cost: $currency ${(ing.quantityRequired * ing.unitCost).toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () {
                              ingredients.remove(ing);
                              if (p.price == 0) {
                                finalPriceCtrl.text =
                                    calcTotalCost().toStringAsFixed(2);
                              }
                              setLocal(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 24),
                Text(
                  'Add Ingredient from Stock',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                buildModalFieldLabel(ctx, 'Stock Ingredient Product'),
                DropdownButtonFormField<Product>(
                  initialValue: stockCandidates.contains(selectedIng)
                      ? selectedIng
                      : null,
                  isExpanded: true,
                  decoration: restaurantInputDecoration(
                    ctx,
                    hintText: stockCandidates.isEmpty
                        ? 'Add raw ingredients under Stock first'
                        : 'Select stock ingredient',
                  ),
                  items: stockCandidates
                      .map(
                        (x) => DropdownMenuItem(
                          value: x,
                          child: Text(
                            '${x.name} (${x.restaurantProductType == 'ingredient' ? 'Ingredient' : 'Stock'} • Qty: ${x.stockLevel} • Cost: $currency ${x.unitCost.toStringAsFixed(2)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setLocal(() {
                      selectedIng = v;
                      if (v != null) {
                        lineCostCtrl.text = v.unitCost.toStringAsFixed(2);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildModalFieldLabel(ctx, 'Qty / Dish'),
                          TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                restaurantInputDecoration(ctx, hintText: '1'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildModalFieldLabel(ctx, 'Unit'),
                          TextField(
                            controller: unitCtrl,
                            decoration:
                                restaurantInputDecoration(ctx, hintText: 'pcs'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildModalFieldLabel(ctx, 'Cost ($currency)'),
                          TextField(
                            controller: lineCostCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                restaurantInputDecoration(ctx, hintText: '0'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Ingredient to Recipe'),
                    onPressed: selectedIng == null
                        ? null
                        : () {
                            ingredients.add(
                              RecipeIngredient(
                                productId: p.id,
                                ingredientProductId: selectedIng!.id,
                                ingredientName: selectedIng!.name,
                                quantityRequired:
                                    double.tryParse(qtyCtrl.text.trim()) ?? 1.0,
                                unitOfMeasure: unitCtrl.text.trim().isEmpty
                                    ? 'pcs'
                                    : unitCtrl.text.trim(),
                                unitCost:
                                    double.tryParse(lineCostCtrl.text.trim()) ??
                                        selectedIng!.unitCost,
                                unitPrice: selectedIng!.price,
                              ),
                            );
                            if (p.price == 0) {
                              finalPriceCtrl.text =
                                  calcTotalCost().toStringAsFixed(2);
                            }
                            setLocal(() {});
                          },
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Recipe Cost:',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$currency ${totalCost.toStringAsFixed(2)}',
                            style: GoogleFonts.ibmPlexMono(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      buildModalFieldLabel(
                        ctx,
                        'Final Dish Selling Price ($currency)',
                      ),
                      TextField(
                        controller: finalPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: restaurantInputDecoration(ctx),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: applyPriceToDish,
                        onChanged: (v) =>
                            setLocal(() => applyPriceToDish = v ?? true),
                        title: Text(
                          'Update "${p.name}" cost & selling price on save',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    qtyCtrl.dispose();
    unitCtrl.dispose();
    lineCostCtrl.dispose();
    finalPriceCtrl.dispose();
  }
}
