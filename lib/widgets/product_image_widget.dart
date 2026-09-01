import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// Universal Product Image Widget for Beleka POS
/// Supports local files, HTTP/HTTPS URLs, base64 data URLs, and clean fallbacks.
class ProductImageWidget extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;
  final double? fallbackIconSize;
  final Color? backgroundColor;

  const ProductImageWidget({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.inventory_2_outlined,
    this.fallbackIconSize,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final defaultBg = backgroundColor ?? primaryColor.withValues(alpha: 0.08);
    final iconSize = fallbackIconSize ?? ((height != null && height! > 50) ? 32.0 : 18.0);

    Widget fallback = Container(
      width: width,
      height: height,
      color: defaultBg,
      child: Center(
        child: Icon(
          fallbackIcon,
          color: primaryColor.withValues(alpha: 0.5),
          size: iconSize,
        ),
      ),
    );

    if (imagePath == null || imagePath!.trim().isEmpty) {
      return borderRadius != null
          ? ClipRRect(borderRadius: borderRadius!, child: fallback)
          : fallback;
    }

    final path = imagePath!.trim();
    Widget imageContent;

    if (path.startsWith('http://') || path.startsWith('https://')) {
      imageContent = Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else if (path.startsWith('data:image')) {
      try {
        final base64Str = path.split(',').last;
        final bytes = base64Decode(base64Str);
        imageContent = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => fallback,
        );
      } catch (_) {
        imageContent = fallback;
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        imageContent = Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => fallback,
        );
      } else {
        imageContent = fallback;
      }
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageContent);
    }
    return imageContent;
  }
}
