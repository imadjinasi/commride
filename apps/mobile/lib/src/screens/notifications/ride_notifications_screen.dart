import 'dart:async';

import 'package:flutter/material.dart';

import '../../push/ride_push_controller.dart';
import '../../theme/commride_theme.dart';

class RideNotificationsScreen extends StatelessWidget {
  const RideNotificationsScreen({
    required this.controller,
    required this.onOpen,
    super.key,
  });

  final RidePushController controller;
  final Future<void> Function(RideNotificationEntry notification) onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? child) {
              return TextButton(
                onPressed: controller.state.unreadCount == 0
                    ? null
                    : controller.markAllNotificationsRead,
                child: const Text('Tandai dibaca'),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, Widget? child) {
            final List<RideNotificationEntry> items =
                controller.state.notifications;

            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(CommRideSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.notifications_none, size: 42),
                      SizedBox(height: CommRideSpacing.sm),
                      Text(
                        'Belum ada notifikasi.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                CommRideSpacing.md,
                CommRideSpacing.sm,
                CommRideSpacing.md,
                CommRideSpacing.xl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: CommRideSpacing.xs),
              itemBuilder: (BuildContext context, int index) {
                final RideNotificationEntry item = items[index];
                return Card(
                  child: ListTile(
                    minVerticalPadding: CommRideSpacing.sm,
                    leading: Icon(
                      item.read
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                      color: item.read
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      item.message.title?.trim().isNotEmpty == true
                          ? item.message.title!.trim()
                          : 'Notifikasi CommRide',
                      style: TextStyle(
                        fontWeight:
                            item.read ? FontWeight.w600 : FontWeight.w800,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (item.message.body?.trim().isNotEmpty == true) ...<
                          Widget
                        >[
                          const SizedBox(height: CommRideSpacing.xxs),
                          Text(item.message.body!.trim()),
                        ],
                        const SizedBox(height: CommRideSpacing.xxs),
                        Text(
                          item.read ? 'Sudah dibaca' : 'Belum dibaca',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      controller.markNotificationRead(item.id);
                      unawaited(onOpen(item));
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
