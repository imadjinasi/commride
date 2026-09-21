import 'package:flutter/material.dart';

import '../../widgets/placeholder_page.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'CommRide',
      description:
          'Home will prioritize an Active Ride, upcoming Ride, invitations, '
          'then Club activity. Social content stays secondary while riding.',
      icon: Icons.home_outlined,
    );
  }
}
