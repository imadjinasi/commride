import 'package:flutter/material.dart';

import '../../api/club_ride_api.dart';
import '../../models/club_ride.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({
    required this.clubId,
    required this.clubRideApi,
    required this.onCreated,
    super.key,
  });

  final String clubId;
  final ClubRideApi clubRideApi;
  final ValueChanged<Ride> onCreated;

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late DateTime _departure;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _departure = DateTime(now.year, now.month, now.day + 1, 6);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Ride')),
      body: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nama Ride',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Waktu berangkat'),
              subtitle: Text(_formatDeparture(_departure)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickDeparture,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                border: OutlineInputBorder(),
              ),
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
              child: Text(_saving ? 'Menyimpan…' : 'Buat Ride'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDeparture() async {
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _departure,
    );

    if (date == null || !mounted) {
      return;
    }

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
    );

    if (time == null) {
      return;
    }

    setState(() {
      _departure = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _errorMessage = 'Nama Ride wajib diisi.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final Ride ride = await widget.clubRideApi.createRide(
        widget.clubId,
        RideInput(
          title: title,
          scheduledStartAt: _departure,
          notes: _nullable(_notesController.text),
        ),
      );

      if (!mounted) {
        return;
      }

      widget.onCreated(ride);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Ride belum dapat dibuat. Coba lagi.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _nullable(String value) {
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

String _formatDeparture(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} · '
      '${two(value.hour)}:${two(value.minute)}';
}
