import 'package:flutter/widgets.dart';

/// Keeps client map configuration above the Navigator, including pushed routes.
class MapStyleScope extends InheritedWidget {
  const MapStyleScope({
    required this.styleUrl,
    required super.child,
    super.key,
  });

  final String? styleUrl;

  static String? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MapStyleScope>()?.styleUrl;
  }

  @override
  bool updateShouldNotify(MapStyleScope oldWidget) {
    return styleUrl != oldWidget.styleUrl;
  }
}
