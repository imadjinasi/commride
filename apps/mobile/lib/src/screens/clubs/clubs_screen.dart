import 'package:flutter/material.dart';

import '../../widgets/placeholder_page.dart';

class ClubsScreen extends StatelessWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Clubs',
      description:
          'Your riding communities live here, including Club profiles, '
          'membership, Ride history, and later the Club timeline.',
      icon: Icons.groups_outlined,
    );
  }
}
