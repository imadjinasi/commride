import '../models/club_ride.dart';

class DeletionClub {
  const DeletionClub({required this.clubId, required this.name});

  final String clubId;
  final String name;

  factory DeletionClub.fromJson(Map<String, Object?> json) {
    return DeletionClub(
      clubId: json['clubId']! as String,
      name: json['name']! as String,
    );
  }
}

class DeletionRide {
  const DeletionRide({required this.rideId, required this.title});

  final String rideId;
  final String title;

  factory DeletionRide.fromJson(Map<String, Object?> json) {
    return DeletionRide(
      rideId: json['rideId']! as String,
      title: json['title']! as String,
    );
  }
}

/// What deleting the account would do right now, from `GET /v1/me/deletion`.
class AccountDeletionPreview {
  const AccountDeletionPreview({
    required this.clubsRequiringTransfer,
    required this.clubsToClose,
    required this.activeRides,
  });

  final List<DeletionClub> clubsRequiringTransfer;
  final List<DeletionClub> clubsToClose;
  final List<DeletionRide> activeRides;

  bool get blocked =>
      clubsRequiringTransfer.isNotEmpty || activeRides.isNotEmpty;

  factory AccountDeletionPreview.fromJson(Map<String, Object?> json) {
    List<T> list<T>(String key, T Function(Map<String, Object?>) parse) {
      final Object? raw = json[key];
      if (raw is! List<Object?>) {
        return <T>[];
      }
      return raw
          .whereType<Map<String, Object?>>()
          .map(parse)
          .toList(growable: false);
    }

    return AccountDeletionPreview(
      clubsRequiringTransfer: list(
        'clubsRequiringTransfer',
        DeletionClub.fromJson,
      ),
      clubsToClose: list('clubsToClose', DeletionClub.fromJson),
      activeRides: list('activeRides', DeletionRide.fromJson),
    );
  }
}

class ClubMember {
  const ClubMember({
    required this.riderId,
    required this.displayName,
    required this.callsign,
    required this.role,
  });

  final String riderId;
  final String displayName;
  final String? callsign;
  final ClubRole role;

  factory ClubMember.fromJson(Map<String, Object?> json) {
    return ClubMember(
      riderId: json['riderId']! as String,
      displayName: json['displayName']! as String,
      callsign: json['callsign'] as String?,
      role: ClubRole.fromWireValue(json['role']! as String),
    );
  }
}

abstract interface class AccountDeletionApi {
  Future<AccountDeletionPreview> previewDeletion();

  /// Throws [AccountApiException] with code `account_deletion_blocked` and a
  /// fresh [AccountApiException.preview] when something still blocks it.
  Future<void> deleteAccount();
}

abstract interface class ClubOwnershipApi {
  Future<List<ClubMember>> listMembers(String clubId);

  Future<void> transferOwnership({
    required String clubId,
    required String riderId,
  });
}

class AccountApiException implements Exception {
  const AccountApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.preview,
  });

  final int statusCode;
  final String code;
  final String message;
  final AccountDeletionPreview? preview;

  @override
  String toString() => 'AccountApiException($code): $message';
}
