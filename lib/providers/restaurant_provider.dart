import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/restaurant_service.dart';

final isRestaurantModeProvider = Provider<bool>((ref) {
  final config = ref.watch(storeConfigProvider).valueOrNull;
  return config?.businessMode == 'restaurant';
});

final activeRestaurantBranchProvider = Provider<String>((ref) {
  final config = ref.watch(storeConfigProvider).valueOrNull;
  final code = config?.bhfId.trim() ?? '';
  return code.isEmpty ? '00' : code;
});

final kitchenStationsProvider = StreamProvider<List<KitchenStation>>((ref) {
  final branch = ref.watch(activeRestaurantBranchProvider);
  return ref.watch(restaurantServiceProvider).watchStations(branch);
});

final restaurantTablesProvider = StreamProvider<List<RestaurantTable>>((ref) {
  final branch = ref.watch(activeRestaurantBranchProvider);
  return ref.watch(restaurantServiceProvider).watchTables(branch);
});

final activeRestaurantOrdersProvider =
    StreamProvider<List<RestaurantOrder>>((ref) {
  final branch = ref.watch(activeRestaurantBranchProvider);
  return ref.watch(restaurantServiceProvider).watchActiveOrders(branch);
});

final allRestaurantOrdersProvider =
    StreamProvider<List<RestaurantOrder>>((ref) {
  final branch = ref.watch(activeRestaurantBranchProvider);
  return ref.watch(restaurantServiceProvider).watchAllOrders(branch);
});

final allInventoryProductsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(databaseServiceProvider).watchAllProducts();
});

final restaurantProductsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(databaseServiceProvider).watchAllProducts().map(
        (products) => products
            .where((p) => !p.isArchived && p.restaurantProductType != 'ingredient')
            .toList(),
      );
});

final selectedRestaurantOrderIdProvider = StateProvider<int?>((ref) => null);

final kitchenIngredientsProvider = StreamProvider<List<KitchenIngredient>>((
  ref,
) {
  return ref.watch(restaurantServiceProvider).watchKitchenIngredients();
});
