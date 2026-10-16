import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/commride_links.dart';

/// Opens the public privacy policy in the browser. Google Play requires the
/// policy to be reachable inside the app as well as on the store listing.
class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => unawaited(openPrivacyPolicy(context)),
      icon: const Icon(Icons.privacy_tip_outlined, size: 18),
      label: const Text('Kebijakan Privasi'),
    );
  }
}

Future<void> openPrivacyPolicy(BuildContext context) async {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  bool opened = false;
  try {
    opened = await launchUrl(
      CommRideLinks.privacyPolicy,
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'Buka ${CommRideLinks.privacyPolicy} di browser untuk membaca '
          'Kebijakan Privasi.',
        ),
      ),
    );
  }
}
