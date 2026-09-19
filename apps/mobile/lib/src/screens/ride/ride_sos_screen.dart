import 'dart:async';

import 'package:flutter/material.dart';

import '../../active_ride/ride_sos_controller.dart';
import '../../models/club_ride.dart';
import '../../models/ride_sos.dart';

class RideSosScreen extends StatefulWidget {
  const RideSosScreen({
    required this.ride,
    required this.membership,
    required this.controller,
    super.key,
  });

  final Ride ride;
  final RideMembership membership;
  final RideSosController controller;

  @override
  State<RideSosScreen> createState() => _RideSosScreenState();
}

class _RideSosScreenState extends State<RideSosScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.start();
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RideSosViewState state = widget.controller.state;
    final bool readOnly =
        state.rideEnded || widget.ride.status == RideStatus.completed;
    final List<RideSos> active = state.activeItems;
    final bool hasOwnActive = active.any(
      (RideSos item) => item.riderId == widget.membership.riderId,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('SOS Ride')),
      body: RefreshIndicator(
        onRefresh: widget.controller.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _SafetyNotice(readOnly: readOnly),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(
                message: state.errorMessage!,
                retryAvailable: state.failedRaise != null,
                working: state.working,
                onRetry: _retryRaise,
                onDismiss: widget.controller.clearError,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'SOS aktif',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (state.loading && state.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (active.isEmpty)
              const _EmptyActiveCard()
            else
              ...active.map(
                (RideSos item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SosCard(
                    item: item,
                    currentRiderId: widget.membership.riderId,
                    currentRole: widget.membership.role,
                    working: state.working,
                    onCancel: () => _cancel(item),
                    onResolve: () => _resolve(item),
                  ),
                ),
              ),
            if (!readOnly && !hasOwnActive) ...<Widget>[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: state.working ? null : _confirmRaise,
                icon: const Icon(Icons.sos_outlined),
                label: Text(state.working ? 'Mengirim...' : 'Aktifkan SOS'),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Riwayat SOS',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (state.items.where((RideSos item) {
              return item.status != RideSosStatus.active;
            }).isEmpty)
              Text(
                'Belum ada SOS yang ditutup.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...state.items
                  .where(
                    (RideSos item) => item.status != RideSosStatus.active,
                  )
                  .map(
                    (RideSos item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SosHistoryTile(item: item),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRaise() async {
    final String? result = await showDialog<String?>(
      context: context,
      builder: (BuildContext context) => const _RaiseSosDialog(),
    );
    if (result == null || result == _cancelledDialogValue) {
      return;
    }

    try {
      await widget.controller.raise(result.isEmpty ? null : result);
    } catch (_) {
      // Controller keeps a visible retryable failure.
    }
  }

  Future<void> _retryRaise() async {
    try {
      await widget.controller.retryFailedRaise();
    } catch (_) {
      // Controller keeps the retry state visible.
    }
  }

  Future<void> _cancel(RideSos item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Batalkan SOS?'),
        content: const Text(
          'SOS akan ditandai dibatalkan. Riwayatnya tetap tersimpan di Ride.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.cancel(item.id);
    } catch (_) {
      // Controller exposes failure state.
    }
  }

  Future<void> _resolve(RideSos item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Tandai SOS selesai?'),
        content: Text(
          'Pastikan bantuan untuk ${item.riderDisplayName} sudah ditangani. '
          'Tindakan ini menyelesaikan status SOS di CommRide.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tandai selesai'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.resolve(item.id);
    } catch (_) {
      // Controller exposes failure state.
    }
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

const String _cancelledDialogValue = '__commride_cancelled_sos_dialog__';

class _RaiseSosDialog extends StatefulWidget {
  const _RaiseSosDialog();

  @override
  State<_RaiseSosDialog> createState() => _RaiseSosDialogState();
}

class _RaiseSosDialogState extends State<_RaiseSosDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.sos_outlined),
      title: const Text('Aktifkan SOS?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'SOS akan memberi perhatian tinggi kepada peserta Ride. '
              'Jika tersedia, CommRide menyertakan lokasi terakhir yang '
              'sudah diterima server.',
            ),
            const SizedBox(height: 12),
            Text(
              'CommRide tidak otomatis menghubungi ambulans, polisi, '
              'atau layanan darurat publik.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Keterangan (opsional)',
                hintText: 'Contoh: ban bocor, terjatuh, butuh bantuan medis',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_cancelledDialogValue),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          icon: const Icon(Icons.sos_outlined),
          label: const Text('Kirim SOS'),
        ),
      ],
    );
  }
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice({required this.readOnly});

  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                readOnly
                    ? 'Ride sudah selesai. Riwayat SOS tetap dapat dibaca.'
                    : 'Gunakan SOS untuk kondisi yang membutuhkan perhatian '
                          'tinggi dari rombongan. SOS berbeda dari tombol '
                          'Butuh Bantuan dan tetap tersimpan sampai dibatalkan '
                          'atau diselesaikan.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyActiveCard extends StatelessWidget {
  const _EmptyActiveCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tidak ada SOS aktif.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosCard extends StatelessWidget {
  const _SosCard({
    required this.item,
    required this.currentRiderId,
    required this.currentRole,
    required this.working,
    required this.onCancel,
    required this.onResolve,
  });

  final RideSos item;
  final String currentRiderId;
  final RideRole currentRole;
  final bool working;
  final VoidCallback onCancel;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final bool mine = item.riderId == currentRiderId;
    final bool leader = currentRole == RideRole.leader;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.sos_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.riderDisplayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Chip(label: Text('SOS aktif')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${item.riderRideRole.label} · '
              '${_formatDateTime(item.raisedAt.toLocal())}',
            ),
            if (item.reason != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(item.reason!),
            ],
            const SizedBox(height: 12),
            _PresenceSummary(presence: item.presence),
            if (mine || leader) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (mine)
                    OutlinedButton(
                      onPressed: working ? null : onCancel,
                      child: const Text('Batalkan SOS'),
                    ),
                  if (leader)
                    FilledButton(
                      onPressed: working ? null : onResolve,
                      child: const Text('Tandai selesai'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresenceSummary extends StatelessWidget {
  const _PresenceSummary({required this.presence});

  final RideSosPresence? presence;

  @override
  Widget build(BuildContext context) {
    final RideSosPresence? value = presence;
    if (value == null) {
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.location_off_outlined, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Lokasi terakhir tidak tersedia. SOS tetap aktif tanpa GPS.',
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.location_on_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Lokasi terakhir: '
            '${value.latitude.toStringAsFixed(5)}, '
            '${value.longitude.toStringAsFixed(5)}\n'
            '${value.freshness.label} · diamati '
            '${_formatDateTime(value.observedAt.toLocal())}',
          ),
        ),
      ],
    );
  }
}

class _SosHistoryTile extends StatelessWidget {
  const _SosHistoryTile({required this.item});

  final RideSos item;

  @override
  Widget build(BuildContext context) {
    final String closedAt = item.status == RideSosStatus.cancelled
        ? item.cancelledAt == null
              ? ''
              : ' · ${_formatDateTime(item.cancelledAt!.toLocal())}'
        : item.resolvedAt == null
        ? ''
        : ' · ${_formatDateTime(item.resolvedAt!.toLocal())}';

    return Card(
      child: ListTile(
        leading: Icon(
          item.status == RideSosStatus.resolved
              ? Icons.task_alt
              : Icons.cancel_outlined,
        ),
        title: Text(item.riderDisplayName),
        subtitle: Text('${item.status.label}$closedAt'),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.retryAvailable,
    required this.working,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final bool retryAvailable;
  final bool working;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            if (retryAvailable)
              TextButton(
                onPressed: working
                    ? null
                    : () {
                        unawaited(onRetry());
                      },
                child: const Text('Kirim ulang'),
              ),
            IconButton(
              tooltip: 'Tutup',
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} · '
      '${two(value.hour)}:${two(value.minute)}';
}
