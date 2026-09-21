import 'package:flutter/material.dart';

import '../../api/vehicle_api.dart';
import '../../models/vehicle_profile.dart';

class VehicleEditorScreen extends StatefulWidget {
  const VehicleEditorScreen({
    required this.vehicleApi,
    required this.onSaved,
    this.vehicle,
    super.key,
  });

  final VehicleApi vehicleApi;
  final VehicleProfile? vehicle;
  final ValueChanged<VehicleProfile> onSaved;

  @override
  State<VehicleEditorScreen> createState() => _VehicleEditorScreenState();
}

class _VehicleEditorScreenState extends State<VehicleEditorScreen> {
  late VehicleKind _kind;
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _fuelTypeController;
  late final TextEditingController _safeRangeController;

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final VehicleProfile? vehicle = widget.vehicle;
    _kind = vehicle?.kind ?? VehicleKind.motorcycle;
    _makeController = TextEditingController(text: vehicle?.make ?? '');
    _modelController = TextEditingController(text: vehicle?.model ?? '');
    _nicknameController = TextEditingController(text: vehicle?.nickname ?? '');
    _fuelTypeController = TextEditingController(text: vehicle?.fuelType ?? '');
    _safeRangeController = TextEditingController(
      text: vehicle?.safeRangeKm?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _nicknameController.dispose();
    _fuelTypeController.dispose();
    _safeRangeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.vehicle != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit kendaraan' : 'Tambah kendaraan'),
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            DropdownButtonFormField<VehicleKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Jenis kendaraan',
                border: OutlineInputBorder(),
              ),
              items: VehicleKind.values
                  .map((VehicleKind kind) {
                    return DropdownMenuItem<VehicleKind>(
                      value: kind,
                      child: Text(kind.label),
                    );
                  })
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (VehicleKind? value) {
                      if (value != null) {
                        setState(() {
                          _kind = value;
                        });
                      }
                    },
            ),
            const SizedBox(height: 16),
            _textField(_makeController, 'Merek (opsional)'),
            const SizedBox(height: 16),
            _textField(_modelController, 'Model (opsional)'),
            const SizedBox(height: 16),
            _textField(_nicknameController, 'Nama panggilan (opsional)'),
            const SizedBox(height: 16),
            _textField(_fuelTypeController, 'Jenis BBM (opsional)'),
            const SizedBox(height: 16),
            TextField(
              controller: _safeRangeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Safe range BBM (km, opsional)',
                helperText:
                    'Perkiraan jarak aman sebelum perlu mengisi BBM. '
                    'Bukan target untuk menghabiskan tangki.',
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
              child: Text(_saving ? 'Menyimpan…' : 'Simpan kendaraan'),
            ),
          ],
        ),
      ),
    );
  }

  TextField _textField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _save() async {
    final String rawSafeRange = _safeRangeController.text.trim();
    final int? safeRangeKm = rawSafeRange.isEmpty
        ? null
        : int.tryParse(rawSafeRange);

    if (rawSafeRange.isNotEmpty &&
        (safeRangeKm == null || safeRangeKm <= 0 || safeRangeKm > 2000)) {
      setState(() {
        _errorMessage = 'Safe range harus 1–2000 km atau dikosongkan.';
      });
      return;
    }

    final VehicleProfileInput input = VehicleProfileInput(
      kind: _kind,
      make: _nullable(_makeController.text),
      model: _nullable(_modelController.text),
      nickname: _nullable(_nicknameController.text),
      fuelType: _nullable(_fuelTypeController.text),
      safeRangeKm: safeRangeKm,
    );

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final VehicleProfile saved = widget.vehicle == null
          ? await widget.vehicleApi.createVehicle(input)
          : await widget.vehicleApi.updateVehicle(widget.vehicle!.id, input);

      if (!mounted) {
        return;
      }

      widget.onSaved(saved);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Kendaraan belum dapat disimpan. Coba lagi.';
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
