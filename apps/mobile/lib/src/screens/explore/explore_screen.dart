import 'package:flutter/material.dart';

import '../../widgets/placeholder_page.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Explore',
      description:
          'Explore is reserved for public Clubs, public Rides, and future '
          'route discovery. It is intentionally not required for the MVP.',
      icon: Icons.explore_outlined,
    );
  }
}
