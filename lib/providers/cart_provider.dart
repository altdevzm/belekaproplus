import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'store_provider.dart';

class CartItem {
  final Product product;
  final int quantity;
  final double weight; // in kg or g
  final bool isWeighted;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.weight = 0.0,
    bool? isWeighted,
  }) : isWeighted = isWeighted ?? product.isWeighted;

  double get effectiveQuantity {
    if (isWeighted) {
      return weight > 0 ? weight : 1.0;
    }
    return quantity.toDouble();
  }

  double get unitPrice {
    final now = DateTime.now();
    if (product.discountPrice != null && 
        product.discountStartDate != null && 
        product.discountEndDate != null &&
        now.isAfter(product.discountStartDate!) && 
        now.isBefore(product.discountEndDate!)) {
      return product.discountPrice!;
    }
    return product.price;
  }

  double get baseUnitPrice {
    if (product.isTaxInclusive) {
      return unitPrice / (1 + (product.taxRate / 100));
    }
    return unitPrice;
  }

  double get taxAmountPerUnit {
    if (product.isTaxInclusive) {
      return unitPrice - baseUnitPrice;
    }
    return unitPrice * (product.taxRate / 100);
  }

  double get subtotal => baseUnitPrice * effectiveQuantity;
  double get totalTax => taxAmountPerUnit * effectiveQuantity;
  double get total => (baseUnitPrice + taxAmountPerUnit) * effectiveQuantity;

  CartItem copyWith({int? quantity, double? weight, bool? isWeighted}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      weight: weight ?? this.weight,
      isWeighted: isWeighted ?? this.isWeighted,
    );
  }
}

class CartState {
  final List<CartItem> items;
  final Customer? customer;
  final int appliedPoints;
  final double discountAmount;
  final double serviceChargeRate; // e.g. 10.0 for 10%
  final bool serviceChargeEnabled;
  final String? customerTpin;
  final String? customerBusinessName;
  final String? customerAddress;

  CartState({
    this.items = const [],
    this.customer,
    this.appliedPoints = 0,
    this.discountAmount = 0.0,
    this.serviceChargeRate = 0.0,
    this.serviceChargeEnabled = false,
    this.customerTpin,
    this.customerBusinessName,
    this.customerAddress,
  });

  CartState copyWith({
    List<CartItem>? items,
    Customer? customer,
    int? appliedPoints,
    double? discountAmount,
    double? serviceChargeRate,
    bool? serviceChargeEnabled,
    String? customerTpin,
    String? customerBusinessName,
    String? customerAddress,
    bool clearCustomer = false,
    bool clearTpin = false,
  }) {
    return CartState(
      items: items ?? this.items,
      customer: clearCustomer ? null : (customer ?? this.customer),
      appliedPoints: appliedPoints ?? this.appliedPoints,
      discountAmount: discountAmount ?? this.discountAmount,
      serviceChargeRate: serviceChargeRate ?? this.serviceChargeRate,
      serviceChargeEnabled: serviceChargeEnabled ?? this.serviceChargeEnabled,
      customerTpin: clearTpin ? null : (customerTpin ?? this.customerTpin),
      customerBusinessName: clearTpin ? null : (customerBusinessName ?? this.customerBusinessName),
      customerAddress: clearTpin ? null : (customerAddress ?? this.customerAddress),
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final bool defaultServiceChargeEnabled;
  final double defaultServiceChargeRate;

  CartNotifier({
    this.defaultServiceChargeEnabled = false,
    this.defaultServiceChargeRate = 0.0,
  }) : super(CartState(
          serviceChargeEnabled: defaultServiceChargeEnabled && defaultServiceChargeRate > 0,
          serviceChargeRate: defaultServiceChargeEnabled && defaultServiceChargeRate > 0 ? defaultServiceChargeRate : 0.0,
        ));

  double get taxRate => 0.0; // Global tax rate is no longer used

  bool addProduct(Product product, {int quantity = 1}) {
    final existingIndex = state.items.indexWhere((item) => item.product.id == product.id && !item.isWeighted);
    
    if (existingIndex != -1) {
      final currentQty = state.items[existingIndex].quantity;
      if (currentQty + quantity > product.stockLevel) {
        return false; // Cannot add more than stock
      }
      
      final newItems = List<CartItem>.from(state.items);
      newItems[existingIndex] = newItems[existingIndex].copyWith(
        quantity: currentQty + quantity,
      );
      state = state.copyWith(items: newItems);
    } else {
      if (product.stockLevel < quantity) return false;
      state = state.copyWith(items: [
        ...state.items,
        CartItem(product: product, quantity: quantity, isWeighted: false),
      ]);
    }
    return true;
  }

  bool addWeightedProduct(Product product, {required double weight, double tareWeight = 0.0}) {
    final netWeight = weight - tareWeight > 0 ? (weight - tareWeight) : weight;
    if (netWeight <= 0) return false;

    final existingIndex = state.items.indexWhere((item) => item.product.id == product.id && item.isWeighted);
    
    if (existingIndex != -1) {
      final newItems = List<CartItem>.from(state.items);
      final currentWeight = newItems[existingIndex].weight;
      newItems[existingIndex] = newItems[existingIndex].copyWith(
        weight: currentWeight + netWeight,
      );
      state = state.copyWith(items: newItems);
    } else {
      state = state.copyWith(items: [
        ...state.items,
        CartItem(product: product, quantity: 1, weight: netWeight, isWeighted: true),
      ]);
    }
    return true;
  }

  void setWeight(int productId, double weight) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.product.id == productId && item.isWeighted) {
          return item.copyWith(weight: weight > 0 ? weight : 0.001);
        }
        return item;
      }).toList(),
    );
  }

  void removeProduct(int productId) {
    state = state.copyWith(
      items: state.items.where((item) => item.product.id != productId).toList(),
    );
  }

  bool updateQuantity(int productId, int delta) {
    bool success = true;
    final newItems = state.items.map((item) {
      if (item.product.id == productId) {
        if (item.isWeighted) {
          // Adjust by 0.1 kg or 0.25 kg for weighted items
          final newWeight = (item.weight + (delta * 0.25)).clamp(0.01, 999.0);
          return item.copyWith(weight: newWeight);
        }
        final newQty = item.quantity + delta;
        if (newQty > item.product.stockLevel) {
          success = false;
          return item;
        }
        return item.copyWith(quantity: newQty.clamp(1, 999));
      }
      return item;
    }).toList();
    
    if (success) {
      state = state.copyWith(items: newItems);
    }
    return success;
  }

  void setQuantity(int productId, int quantity) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.product.id == productId && !item.isWeighted) {
          final finalQty = quantity.clamp(1, 999);
          final stockAdjustedQty = finalQty.clamp(1, item.product.stockLevel);
          return item.copyWith(quantity: stockAdjustedQty);
        }
        return item;
      }).toList(),
    );
  }

  void setCustomer(Customer? customer) {
    state = state.copyWith(
      customer: customer,
      clearCustomer: customer == null,
      appliedPoints: 0,
      discountAmount: 0.0,
    );
  }
  
  void applyLoyaltyDiscount(int points, double value) {
    state = state.copyWith(
      appliedPoints: points,
      discountAmount: value,
    );
  }

  void setServiceChargeRate(double rate) {
    state = state.copyWith(
      serviceChargeRate: rate,
      serviceChargeEnabled: rate > 0,
    );
  }

  void toggleServiceCharge(bool enabled, {double? defaultRate}) {
    state = state.copyWith(
      serviceChargeEnabled: enabled,
      serviceChargeRate: enabled ? (defaultRate ?? (state.serviceChargeRate > 0 ? state.serviceChargeRate : 10.0)) : 0.0,
    );
  }

  void setCustomerTpin(String? tpin, {String? businessName, String? address}) {
    state = state.copyWith(
      customerTpin: tpin,
      customerBusinessName: businessName,
      customerAddress: address,
      clearTpin: tpin == null || tpin.isEmpty,
    );
  }

  bool addItem(Product product, {int quantity = 1}) => addProduct(product, quantity: quantity);

  void clearCart() => clear();

  void clear() {
    state = CartState(
      serviceChargeEnabled: defaultServiceChargeEnabled && defaultServiceChargeRate > 0,
      serviceChargeRate: defaultServiceChargeEnabled && defaultServiceChargeRate > 0 ? defaultServiceChargeRate : 0.0,
    );
  }

  double get subtotal => state.items.fold(0, (sum, item) => sum + item.subtotal);
  double get tax => state.items.fold(0, (sum, item) => sum + item.totalTax);
  
  // Non-taxable restaurant service charge calculated on subtotal
  double get serviceChargeAmount => state.serviceChargeEnabled
      ? (subtotal * (state.serviceChargeRate / 100))
      : 0.0;

  double get totalBeforeDiscount => subtotal + tax + serviceChargeAmount;
  double get total => (totalBeforeDiscount - state.discountAmount).clamp(0.0, double.infinity);
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  final config = ref.watch(storeConfigProvider).value;
  final notifier = CartNotifier(
    defaultServiceChargeEnabled: config?.serviceChargeEnabled ?? false,
    defaultServiceChargeRate: config?.defaultServiceChargeRate ?? 0.0,
  );
  return notifier;
});
