import 'package:flutter/material.dart';

abstract final class CommRideBrandAssets {
  static const String appIcon = 'assets/branding/commride-app-icon.png';
  static const String primaryLogo = 'assets/branding/commride-primary-logo.png';
  static const String monochrome = 'assets/branding/commride-monochrome.png';
}

enum CommRideBrandVariant { appIcon, primary, monochrome }

class CommRideBrandImage extends StatelessWidget {
  const CommRideBrandImage({
    required this.variant,
    this.size = 96,
    this.width,
    this.height,
    super.key,
  });

  final CommRideBrandVariant variant;
  final double size;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assetPath,
      key: ValueKey<String>('commride-brand-${variant.name}'),
      width: width ?? size,
      height: height ?? size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      cacheWidth: 512,
      semanticLabel: 'CommRide',
    );
  }

  String get _assetPath => switch (variant) {
    CommRideBrandVariant.appIcon => CommRideBrandAssets.appIcon,
    CommRideBrandVariant.primary => CommRideBrandAssets.primaryLogo,
    CommRideBrandVariant.monochrome => CommRideBrandAssets.monochrome,
  };
}
