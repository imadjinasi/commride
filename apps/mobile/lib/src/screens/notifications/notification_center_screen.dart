import 'package:flutter/material.dart';

import '../../api/notification_api.dart';
import '../../models/rider_notification.dart';

typedef NotificationOpenCallback =
    Future<void> Function(RiderNotification notification);

class NotificationCenterScreen extends StatelessWidget {
  const NotificationCenterScreen({
    required this.notificationApi,
    this.clubId,
    this.clubName,
    this.onOpen,
    super.key,
  });

  final NotificationApi notificationApi;
  final String? clubId;
  final String? clubName;

  /// Opens the Ride or Club a notification points to. Called after the
  /// item is marked read; only offered for items that carry a target.
  final NotificationOpenCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (clubId != null) {
      return _NotificationListScaffold(
        title: clubName == null
            ? 'Notifikasi Club'
            : 'Notifikasi · ${clubName!}',
        notificationApi: notificationApi,
        scope: RiderNotificationScope.club,
        clubId: clubId,
        onOpen: onOpen,
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifikasi'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Akun'),
              Tab(text: 'Club'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _NotificationList(
              notificationApi: notificationApi,
              scope: RiderNotificationScope.account,
              onOpen: onOpen,
            ),
            _NotificationList(
              notificationApi: notificationApi,
              scope: RiderNotificationScope.club,
              onOpen: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationListScaffold extends StatelessWidget {
  const _NotificationListScaffold({
    required this.title,
    required this.notificationApi,
    required this.scope,
    this.clubId,
    this.onOpen,
  });

  final String title;
  final NotificationApi notificationApi;
  final RiderNotificationScope scope;
  final String? clubId;
  final NotificationOpenCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _NotificationList(
        notificationApi: notificationApi,
        scope: scope,
        clubId: clubId,
        onOpen: onOpen,
      ),
    );
  }
}

class _NotificationList extends StatefulWidget {
  const _NotificationList({
    required this.notificationApi,
    required this.scope,
    this.clubId,
    this.onOpen,
  });

  final NotificationApi notificationApi;
  final RiderNotificationScope scope;
  final String? clubId;
  final NotificationOpenCallback? onOpen;

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList> {
  late Future<List<RiderNotification>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.notificationApi.listNotifications(
      scope: widget.scope,
      clubId: widget.clubId,
    );
  }

  void _refresh() {
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RiderNotification>>(
      future: _future,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<RiderNotification>> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _LoadError(onRetry: _refresh);
            }

            final List<RiderNotification> items =
                snapshot.data ?? const <RiderNotification>[];
            if (items.isEmpty) {
              return const _EmptyNotifications();
            }

            return RefreshIndicator(
              onRefresh: () async {
                _refresh();
                await _future;
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final RiderNotification item = items[index];
                  final bool actionable = _canOpen(item);
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        item.isUnread
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                      title: Text(
                        item.title,
                        style: item.isUnread
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null,
                      ),
                      subtitle: Text(
                        '${item.body}\n${_formatTime(item.createdAt)}',
                      ),
                      isThreeLine: true,
                      trailing: item.isUnread
                          ? const Icon(Icons.circle, size: 10)
                          : actionable
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: item.isUnread || actionable
                          ? () => _open(item)
                          : null,
                    ),
                  );
                },
              ),
            );
          },
    );
  }

  bool _canOpen(RiderNotification item) =>
      widget.onOpen != null && (item.rideId != null || item.clubId != null);

  Future<void> _open(RiderNotification item) async {
    if (item.isUnread) {
      await _markRead(item);
    }
    if (_canOpen(item) && mounted) {
      await widget.onOpen!(item);
    }
  }

  Future<void> _markRead(RiderNotification item) async {
    try {
      await widget.notificationApi.markRead(item.id);
      if (mounted) {
        _refresh();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifikasi belum dapat ditandai dibaca.'),
        ),
      );
    }
  }

  String _formatTime(DateTime value) {
    final DateTime local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Belum ada notifikasi.', textAlign: TextAlign.center),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Notifikasi belum dapat dimuat.'),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
