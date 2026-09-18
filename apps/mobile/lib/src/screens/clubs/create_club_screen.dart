import 'package:flutter/material.dart';

import '../../api/club_ride_api.dart';
import '../../models/club_ride.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({
    required this.clubRideApi,
    required this.onCreated,
    super.key,
  });

  final ClubRideApi clubRideApi;
  final ValueChanged<Club> onCreated;

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _slugController = TextEditingController();
  final TextEditingController _homeAreaController = TextEditingController();

  ClubVisibility _visibility = ClubVisibility.private;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _homeAreaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Club')),
      body: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              onChanged: _syncSlugIfEmpty,
              decoration: const InputDecoration(
                labelText: 'Nama Club',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _slugController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Handle / slug',
                helperText: 'Huruf kecil, angka, dan tanda hubung.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _homeAreaController,
              decoration: const InputDecoration(
                labelText: 'Kota / area (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ClubVisibility>(
              initialValue: _visibility,
              decoration: const InputDecoration(
                labelText: 'Visibilitas',
                border: OutlineInputBorder(),
              ),
              items: ClubVisibility.values
                  .map(
                    (ClubVisibility visibility) =>
                        DropdownMenuItem<ClubVisibility>(
                          value: visibility,
                          child: Text(visibility.label),
                        ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (ClubVisibility? value) {
                      if (value != null) {
                        setState(() {
                          _visibility = value;
                        });
                      }
                    },
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Buat Club'),
            ),
          ],
        ),
      ),
    );
  }

  void _syncSlugIfEmpty(String name) {
    if (_slugController.text.isNotEmpty) {
      return;
    }

    _slugController.text = _slugify(name);
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    final String slug = _slugController.text.trim().toLowerCase();

    if (name.isEmpty || slug.length < 2) {
      setState(() {
        _errorMessage = 'Nama Club dan slug wajib diisi.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final Club club = await widget.clubRideApi.createClub(
        ClubInput(
          name: name,
          slug: slug,
          homeArea: _nullable(_homeAreaController.text),
          visibility: _visibility,
        ),
      );

      if (!mounted) {
        return;
      }

      widget.onCreated(club);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Club belum dapat dibuat. Periksa data dan coba lagi.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _slugify(String value) {
    final String normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized;
  }

  String? _nullable(String value) {
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
