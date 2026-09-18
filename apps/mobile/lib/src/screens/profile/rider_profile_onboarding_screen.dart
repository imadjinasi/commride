import 'package:flutter/material.dart';

import '../../api/rider_profile_api.dart';
import '../../models/rider_profile.dart';

class RiderProfileOnboardingScreen extends StatefulWidget {
  const RiderProfileOnboardingScreen({
    required this.riderProfileApi,
    required this.onSaved,
    super.key,
  });

  final RiderProfileApi riderProfileApi;
  final ValueChanged<RiderProfile> onSaved;

  @override
  State<RiderProfileOnboardingScreen> createState() =>
      _RiderProfileOnboardingScreenState();
}

class _RiderProfileOnboardingScreenState
    extends State<RiderProfileOnboardingScreen> {
  final TextEditingController _displayNameController =
      TextEditingController();
  final TextEditingController _callsignController = TextEditingController();
  final TextEditingController _homeAreaController = TextEditingController();

  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _displayNameController.dispose();
    _callsignController.dispose();
    _homeAreaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil Rider')),
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Kenalkan diri Anda',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nama ini akan terlihat oleh Rider lain di Club dan Ride '
                    'yang Anda ikuti.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _displayNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nama tampilan',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _callsignController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Callsign (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _homeAreaController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      labelText: 'Kota / area (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Menyimpan…' : 'Simpan profil'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CommRide tidak meminta izin lokasi di langkah ini.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final String displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      setState(() {
        _errorMessage = 'Nama tampilan wajib diisi.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final RiderProfile profile = await widget.riderProfileApi.saveProfile(
        RiderProfileInput(
          displayName: displayName,
          callsign: _nullableTrimmed(_callsignController.text),
          homeArea: _nullableTrimmed(_homeAreaController.text),
        ),
      );

      if (mounted) {
        widget.onSaved(profile);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Profil belum dapat disimpan. Coba lagi.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _nullableTrimmed(String value) {
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
