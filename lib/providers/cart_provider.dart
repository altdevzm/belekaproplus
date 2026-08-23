import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';

class CartItem {
  final Product product;
  final int quantity;

  CartItem({required this.product, required this.quantity});

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

  double get subtotal => baseUnitPrice * quantity;
  double get totalTax => taxAmountPerUnit * quantity;
  double get total => (baseUnitPrice + taxAmountPerUnit) * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartState {
  final List<CartItem> items;
  final Customer? customer;
  final int appliedPoints;
  final double discountAmount;
  final String? customerTpin;
  final String? customerBusinessName;
  final String? customerAddress;

  CartState({
    this.items = const [],
    this.customer,
    this.appliedPoints = 0,
    this.discountAmount = 0.0,
    this.customerTpin,
    this.customerBusinessName,
    this.customerAddress,
  });

  CartState copyWith({
    List<CartItem>? items,
    Customer? customer,
    int? appliedPoints,
    double? discountAmount,
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
      customerTpin: clearTpin ? null : (customerTpin ?? this.customerTpin),
      customerBusinessName: clearTpin ? null : (customerBusinessName ?? this.customerBusinessName),
      customerAddress: clearTpin ? null : (customerAddress ?? this.customerAddress),
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {

  CartNotifier() : super(CartState());

  double get taxRate => 0.0; // Global tax rate is no longer used

  bool addProduct(Product product, {int quantity = 1}) {
    final existingIndex = state.items.indexWhere((item) => item.product.id == product.id);
    
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
      state = state.copyWith(items: [...state.items, CartItem(product: product, quantity: quantity)]);
    }
    return true;
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
        if (item.product.id == productId) {
          final finalQty = quantity.clamp(1, 999);
          // Only sync with stock if needed, or assume caller handled it.
          // The current updateQuantity checks stockLevel, so we should too.
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

  void setCustomerTpin(String? tpin, {String? businessName, String? address}) {
    state = state.copyWith(
      customerTpin: tpin,
      customerBusinessName: businessName,
      customerAddress: address,
      clearTpin: tpin == null || tpin.isEmpty,
    );
  }

  void clear() {
    state = CartState();
  }

  double get subtotal => state.items.fold(0, (sum, item) => sum + item.subtotal);
  double get tax => state.items.fold(0, (sum, item) => sum + item.totalTax);
  double get totalBeforeDiscount => subtotal + tax;
  double get total => totalBeforeDiscount - state.discountAmount;
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  final notifier = CartNotifier();
  
  // Store config tax rate is no longer applied globally
  return notifier;
});
