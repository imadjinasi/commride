import 'package:flutter/material.dart';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.title,
    required this.description,
    this.icon = Icons.two_wheeler_outlined,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar.large(
          title: Text(title),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              container: true,
              label: '$title. $description',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 40),
                  const SizedBox(height: 20),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
