import 'dart:async';

import 'package:flutter/material.dart';

import '../active_ride/live_group_controller.dart';
import '../active_ride/live_group_models.dart';
import '../theme/commride_theme.dart';

typedef QuickActionSender =
    Future<void> Function(LiveQuickActionKind kind, {String? reason});

class ActiveRideQuickActionsSheet extends StatelessWidget {
  const ActiveRideQuickActionsSheet({required this.onSend, super.key});

  final QuickActionSender onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        CommRideSpacing.md,
        0,
        CommRideSpacing.md,
        CommRideSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Status cepat', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: CommRideSpacing.xxs),
            const Text(
              'Pilih kondisi. Keterangan tambahan bersifat opsional.',
            ),
            const SizedBox(height: CommRideSpacing.sm),
            _QuickActionTile(
              kind: LiveQuickActionKind.stopping,
              icon: Icons.stop_circle_outlined,
              subtitle: 'Berhenti sementara.',
              onSend: onSend,
            ),
            _QuickActionTile(
              kind: LiveQuickActionKind.leftBehind,
              icon: Icons.person_pin_circle_outlined,
              subtitle: 'Tertinggal dari rombongan.',
              onSend: onSend,
            ),
            _QuickActionTile(
              kind: LiveQuickActionKind.needHelp,
              icon: Icons.help_outline,
              subtitle: 'Memerlukan bantuan rombongan.',
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
    required this.icon,
    required this.subtitle,
    required this.onSend,
  });

  final LiveQuickActionKind kind;
  final IconData icon;
  final String subtitle;
  final QuickActionSender onSend;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CommRideTargets.minimum),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 28),
        title: Text(
          kind.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
        onTap: () => unawaited(onSend(kind)),
        trailing: IconButton(
          tooltip: 'Tambahkan keterangan',
          onPressed: () => unawaited(_sendWithReason(context)),
          icon: const Icon(Icons.note_add_outlined),
        ),
      ),
    );
  }

  Future<void> _sendWithReason(BuildContext context) async {
    String draft = '';
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('${kind.label} · keterangan'),
        content: TextField(
          maxLength: 240,
          minLines: 1,
          maxLines: 3,
          onChanged: (String value) => draft = value,
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
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );

    if (reason != null) {
      await onSend(kind, reason: reason);
    }
  }
}

Future<void> showActiveRideQuickActions({
  required BuildContext context,
  required ActiveRideGroupController controller,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => ActiveRideQuickActionsSheet(
      onSend: (LiveQuickActionKind kind, {String? reason}) async {
        try {
          await controller.raiseQuickAction(kind, reason: reason);
          if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
            Navigator.of(sheetContext).pop();
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('${kind.label} terkirim.'),
              ),
            );
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  'Status belum terkirim. Periksa koneksi lalu coba lagi.',
                ),
              ),
            );
          }
        }
      },
    ),
  );
}
