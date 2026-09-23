import 'package:flutter/material.dart';

import '../../active_ride/live_group_models.dart';

typedef RideQuickActionSender =
    Future<void> Function(LiveQuickActionKind kind, {String? reason});

Future<void> showRideQuickActionsSheet(
  BuildContext context, {
  required RideQuickActionSender onSend,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return _RideQuickActionsSheet(
        onSend: (LiveQuickActionKind kind, {String? reason}) async {
          try {
            await onSend(kind, reason: reason);
            if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
              Navigator.of(sheetContext).pop();
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${kind.label} terkirim.')),
              );
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Quick action belum terkirim. Periksa koneksi realtime.',
                  ),
                ),
              );
            }
          }
        },
      );
    },
  );
}

class _RideQuickActionsSheet extends StatelessWidget {
  const _RideQuickActionsSheet({required this.onSend});

  final RideQuickActionSender onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Kirim kondisi penting ke rombongan tanpa membuka chat.',
            ),
            const SizedBox(height: 12),
            _QuickActionTile(
              kind: LiveQuickActionKind.stopping,
              subtitle:
                  'Berhenti sementara untuk BBM, istirahat, atau kendala.',
              onSend: onSend,
            ),
            _QuickActionTile(
              kind: LiveQuickActionKind.leftBehind,
              subtitle: 'Beri tahu rombongan bahwa kamu tertinggal.',
              onSend: onSend,
            ),
            _QuickActionTile(
              kind: LiveQuickActionKind.needHelp,
              subtitle: 'Minta bantuan rombongan. Ini bukan layanan SOS.',
              onSend: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.kind,
    required this.subtitle,
    required this.onSend,
  });

  final LiveQuickActionKind kind;
  final String subtitle;
  final RideQuickActionSender onSend;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon(kind)),
      title: Text(kind.label),
      subtitle: Text(subtitle),
      onTap: () => onSend(kind),
      trailing: IconButton(
        tooltip: 'Kirim ${kind.label} dengan alasan',
        icon: const Icon(Icons.note_add_outlined),
        onPressed: () => _sendWithReason(context),
      ),
    );
  }

  Future<void> _sendWithReason(BuildContext context) async {
    String draft = '';
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('${kind.label} — alasan'),
          content: TextField(
            maxLength: 240,
            minLines: 1,
            maxLines: 3,
            onChanged: (String value) {
              draft = value;
            },
            decoration: const InputDecoration(
              hintText: 'Opsional, mis. isi BBM atau kendala mesin',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(draft.trim()),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (reason == null) {
      return;
    }
    await onSend(kind, reason: reason);
  }

  IconData _icon(LiveQuickActionKind kind) {
    return switch (kind) {
      LiveQuickActionKind.stopping => Icons.pause_circle_outline,
      LiveQuickActionKind.leftBehind => Icons.route_outlined,
      LiveQuickActionKind.needHelp => Icons.health_and_safety_outlined,
    };
  }
}
