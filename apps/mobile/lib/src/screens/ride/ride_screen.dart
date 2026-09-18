import 'package:flutter/material.dart';

import '../../widgets/placeholder_page.dart';

class RideScreen extends StatelessWidget {
  const RideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Ride',
      description:
          'Plan, join, and review Rides here. Route planning, Add Stop, '
          'Search Along Route, and the Active Ride command center come next.',
      icon: Icons.route_outlined,
    );
  }
}
