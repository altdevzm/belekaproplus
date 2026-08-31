import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';

final accentColorProvider = Provider<Color>((ref) {
  final storeConfig = ref.watch(storeConfigProvider).value;
  
  if (storeConfig == null) return const Color(0xFF1D4ED8); // Brand Primary #1D4ED8

  switch (storeConfig.primarySector) {
    case CategorySector.pharmacy:
      return const Color(0xFF0284C7); // Info #0284C7
    case CategorySector.stationery:
      return const Color(0xFFD97706); // Warning #D97706
    case CategorySector.grocery:
      return const Color(0xFF059669); // Success #059669
    case CategorySector.food:
      return const Color(0xFFDC2626); // Error #DC2626
    case CategorySector.restaurant:
      return const Color(0xFFEA580C); // Warm Orange
    case CategorySector.other:
      return const Color(0xFF1D4ED8); // Brand Primary #1D4ED8
  }
});

