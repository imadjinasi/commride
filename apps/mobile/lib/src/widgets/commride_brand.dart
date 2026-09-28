import 'package:flutter/material.dart';

abstract final class CommRideBrandAssets {
  static const String appIcon = 'assets/branding/commride-app-icon.png';
  static const String primaryLogo = 'assets/branding/commride-primary-logo.png';
  static const String monochrome = 'assets/branding/commride-monochrome.png';
}

enum CommRideBrandVariant { appIcon, primary, monochrome }

class CommRideBrandImage extends StatelessWidget {
  const CommRideBrandImage({required this.variant, this.size = 96, super.key});

  final CommRideBrandVariant variant;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assetPath,
      key: ValueKey<String>('commride-brand-${variant.name}'),
      width: size,
      height: size,
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

class CommRideHeaderBrand extends StatelessWidget {
  const CommRideHeaderBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CommRide · Ride Connected.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CommRideBrandImage(
            variant: CommRideBrandVariant.appIcon,
            size: 36,
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CommRide',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ride Connected.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
