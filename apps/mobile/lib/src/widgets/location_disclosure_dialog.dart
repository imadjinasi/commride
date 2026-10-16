import 'package:flutter/material.dart';

import 'privacy_policy_link.dart';

/// Explains location use before Android/iOS asks for permission (Google Play
/// "prominent disclosure"). Resolves `true` when the Rider continues.
Future<bool> showLocationDisclosure(BuildContext context) async {
  final bool? accepted = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => const _LocationDisclosureDialog(),
  );
  return accepted ?? false;
}

class _LocationDisclosureDialog extends StatelessWidget {
  const _LocationDisclosureDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.my_location),
      title: const Text('CommRide memakai lokasi Anda'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Point(
              'Posisi Anda dibagikan ke peserta Ride ini selama Ride '
              'berjalan, untuk navigasi dan menjaga rombongan.',
            ),
            _Point(
              'Lokasi tetap dikirim saat layar terkunci atau aplikasi tidak '
              'dibuka. Selama itu ada notifikasi yang terus tampil.',
            ),
            _Point(
              'Berhenti otomatis saat Ride selesai. Untuk rekap, paling banyak '
              '1 titik per menit disimpan dan dihapus 30 hari setelah Ride.',
            ),
            PrivacyPolicyLink(),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Tidak sekarang'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Lanjutkan'),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
