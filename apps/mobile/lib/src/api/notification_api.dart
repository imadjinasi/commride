import '../models/rider_notification.dart';

abstract interface class NotificationApi {
  Future<List<RiderNotification>> listNotifications({
    RiderNotificationScope? scope,
    String? clubId,
    int limit = 50,
  });

  Future<void> markRead(String notificationId);
}

class NotificationApiException implements Exception {
  const NotificationApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'NotificationApiException($code): $message';
}
