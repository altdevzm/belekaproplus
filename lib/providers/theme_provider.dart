import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';

final accentColorProvider = Provider<Color>((ref) {
  final storeConfig = ref.watch(storeConfigProvider).value;
  
  if (storeConfig == null) return const Color(0xFFC1F11D); // Default Neon Green

  switch (storeConfig.primarySector) {
    case CategorySector.pharmacy:
      return const Color(0xFF00B4D8); // Healthcare Blue
    case CategorySector.stationery:
      return const Color(0xFFFFD60A); // Vibrant Yellow
    case CategorySector.grocery:
      return const Color(0xFF2ECC71); // Fresh Green
    case CategorySector.food:
      return const Color(0xFFFF6B6B); // Appetizing Red
    case CategorySector.restaurant:
      return const Color(0xFFF39C12); // Amber/Orange
    case CategorySector.other:
      return const Color(0xFFC1F11D); // Industrial Neon Green
  }
});
