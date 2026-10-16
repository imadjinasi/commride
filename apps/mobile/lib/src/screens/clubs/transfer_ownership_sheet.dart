import 'package:flutter/material.dart';

import '../../api/account_api.dart';

/// Lets the Club owner hand ownership to another active member.
/// Resolves `true` when ownership was transferred.
Future<bool> showTransferOwnershipSheet({
  required BuildContext context,
  required ClubOwnershipApi api,
  required String clubId,
  required String clubName,
  required String currentRiderId,
}) async {
  final bool? transferred = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _TransferOwnershipSheet(
      api: api,
      clubId: clubId,
      clubName: clubName,
      currentRiderId: currentRiderId,
    ),
  );
  return transferred ?? false;
}

class _TransferOwnershipSheet extends StatefulWidget {
  const _TransferOwnershipSheet({
    required this.api,
    required this.clubId,
    required this.clubName,
    required this.currentRiderId,
  });

  final ClubOwnershipApi api;
  final String clubId;
  final String clubName;
  final String currentRiderId;

  @override
  State<_TransferOwnershipSheet> createState() =>
      _TransferOwnershipSheetState();
}

class _TransferOwnershipSheetState extends State<_TransferOwnershipSheet> {
  late Future<List<ClubMember>> _membersFuture;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.api.listMembers(widget.clubId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FutureBuilder<List<ClubMember>>(
          future: _membersFuture,
          builder:
              (BuildContext context, AsyncSnapshot<List<ClubMember>> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Daftar anggota belum dapat dimuat.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final List<ClubMember> candidates =
                    (snapshot.data ?? const <ClubMember>[])
                        .where(
                          (ClubMember member) =>
                              member.riderId != widget.currentRiderId,
                        )
                        .toList(growable: false);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Serahkan kepemilikan ${widget.clubName}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pilih anggota yang akan menjadi pemilik baru. '
                      'Anda tetap di Club sebagai Admin.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (candidates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Belum ada anggota aktif lain.'),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: <Widget>[
                            for (final ClubMember member in candidates)
                              ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(member.displayName),
                                subtitle: Text(
                                  member.callsign == null
                                      ? member.role.label
                                      : '${member.callsign} · ${member.role.label}',
                                ),
                                enabled: !_working,
                                onTap: () => _confirm(member),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
        ),
      ),
    );
  }

  Future<void> _confirm(ClubMember member) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Serahkan kepemilikan?'),
        content: Text(
          '${member.displayName} akan menjadi pemilik ${widget.clubName}. '
          'Anda menjadi Admin.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Serahkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.api.transferOwnership(
        clubId: widget.clubId,
        riderId: member.riderId,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Kepemilikan belum dapat diserahkan. Coba lagi.';
        });
      }
    }
  }
}
