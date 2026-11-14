import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';

class CustomerDisplayState {
  const CustomerDisplayState({
    this.activeOrder,
    this.activeProduct,
    this.activeExtras = const [],
    this.availableExtras = const [],
    this.lastAddedExtraName,
    this.animationTrigger = 0,
  });

  final RestaurantOrder? activeOrder;
  final Product? activeProduct;
  final List<Map<String, dynamic>> activeExtras;
  final List<Map<String, dynamic>> availableExtras;
  final String? lastAddedExtraName;
  final int animationTrigger;

  CustomerDisplayState copyWith({
    RestaurantOrder? activeOrder,
    Product? activeProduct,
    List<Map<String, dynamic>>? activeExtras,
    List<Map<String, dynamic>>? availableExtras,
    String? lastAddedExtraName,
    int? animationTrigger,
    bool clearProduct = false,
  }) {
    return CustomerDisplayState(
      activeOrder: activeOrder ?? this.activeOrder,
      activeProduct: clearProduct ? null : (activeProduct ?? this.activeProduct),
      activeExtras: activeExtras ?? this.activeExtras,
      availableExtras: availableExtras ?? this.availableExtras,
      lastAddedExtraName: lastAddedExtraName ?? this.lastAddedExtraName,
      animationTrigger: animationTrigger ?? this.animationTrigger,
    );
  }
}

class CustomerDisplayNotifier extends StateNotifier<CustomerDisplayState> {
  CustomerDisplayNotifier() : super(const CustomerDisplayState());

  void setOrder(RestaurantOrder? order) {
    state = state.copyWith(activeOrder: order);
  }

  void previewProduct(
    Product product, {
    List<Map<String, dynamic>> extras = const [],
    List<Map<String, dynamic>>? availableExtras,
    String? addedExtraName,
  }) {
    state = state.copyWith(
      activeProduct: product,
      activeExtras: List<Map<String, dynamic>>.from(extras),
      availableExtras: availableExtras != null
          ? List<Map<String, dynamic>>.from(availableExtras)
          : state.availableExtras,
      lastAddedExtraName: addedExtraName,
      animationTrigger: state.animationTrigger + 1,
    );
  }

  void clearPreview() {
    state = state.copyWith(
      clearProduct: true,
      activeExtras: const [],
      availableExtras: const [],
      lastAddedExtraName: null,
    );
  }
}

final customerDisplayProvider =
    StateNotifierProvider<CustomerDisplayNotifier, CustomerDisplayState>(
  (ref) => CustomerDisplayNotifier(),
);

