import 'package:flutter/material.dart';

import '../../widgets/placeholder_page.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Profile',
      description:
          'Rider identity, vehicles, Ride history, badges, level, privacy, '
          'and settings will be managed here.',
      icon: Icons.person_outline,
    );
  }
}
