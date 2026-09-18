enum ClubRole {
  owner,
  admin,
  member;

  String get label {
    return switch (this) {
      ClubRole.owner => 'Owner',
      ClubRole.admin => 'Admin',
      ClubRole.member => 'Member',
    };
  }

  static ClubRole fromWireValue(String value) {
    return ClubRole.values.firstWhere(
      (ClubRole role) => role.name == value,
      orElse: () => throw FormatException('Unknown Club role: $value'),
    );
  }
}

enum ClubMembershipStatus {
  invited,
  active,
  left;

  static ClubMembershipStatus fromWireValue(String value) {
    return ClubMembershipStatus.values.firstWhere(
      (ClubMembershipStatus status) => status.name == value,
      orElse: () =>
          throw FormatException('Unknown Club membership status: $value'),
    );
  }
}

enum ClubVisibility {
  private,
  unlisted,
  public;

  String get label {
    return switch (this) {
      ClubVisibility.private => 'Privat',
      ClubVisibility.unlisted => 'Tidak terdaftar',
      ClubVisibility.public => 'Publik',
    };
  }

  static ClubVisibility fromWireValue(String value) {
    return ClubVisibility.values.firstWhere(
      (ClubVisibility visibility) => visibility.name == value,
      orElse: () => throw FormatException('Unknown Club visibility: $value'),
    );
  }
}

class Club {
  const Club({
    required this.id,
    required this.name,
    required this.slug,
    required this.homeArea,
    required this.description,
    required this.visibility,
  });

  final String id;
  final String name;
  final String slug;
  final String? homeArea;
  final String? description;
  final ClubVisibility visibility;

  factory Club.fromJson(Map<String, Object?> json) {
    return Club(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      homeArea: json['homeArea'] as String?,
      description: json['description'] as String?,
      visibility: ClubVisibility.fromWireValue(json['visibility'] as String),
    );
  }
}

class ClubMembership {
  const ClubMembership({
    required this.clubId,
    required this.riderId,
    required this.role,
    required this.status,
  });

  final String clubId;
  final String riderId;
  final ClubRole role;
  final ClubMembershipStatus status;

  factory ClubMembership.fromJson(Map<String, Object?> json) {
    return ClubMembership(
      clubId: json['clubId'] as String,
      riderId: json['riderId'] as String,
      role: ClubRole.fromWireValue(json['role'] as String),
      status: ClubMembershipStatus.fromWireValue(json['status'] as String),
    );
  }
}

class ClubListItem {
  const ClubListItem({required this.club, required this.membership});

  final Club club;
  final ClubMembership membership;

  factory ClubListItem.fromJson(Map<String, Object?> json) {
    final Object? rawClub = json['club'];
    final Object? rawMembership = json['membership'];

    if (rawClub is! Map<String, Object?> ||
        rawMembership is! Map<String, Object?>) {
      throw const FormatException('Invalid Club list item.');
    }

    return ClubListItem(
      club: Club.fromJson(rawClub),
      membership: ClubMembership.fromJson(rawMembership),
    );
  }
}

class ClubInput {
  const ClubInput({
    required this.name,
    required this.slug,
    required this.visibility,
    this.homeArea,
  });

  final String name;
  final String slug;
  final ClubVisibility visibility;
  final String? homeArea;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'slug': slug,
      'homeArea': homeArea,
      'visibility': visibility.name,
    };
  }
}

enum RideRole {
  leader,
  sweeper,
  navigator,
  member;

  String get label {
    return switch (this) {
      RideRole.leader => 'Leader',
      RideRole.sweeper => 'Sweeper',
      RideRole.navigator => 'Navigator',
      RideRole.member => 'Member',
    };
  }

  static RideRole fromWireValue(String value) {
    return RideRole.values.firstWhere(
      (RideRole role) => role.name == value,
      orElse: () => throw FormatException('Unknown Ride role: $value'),
    );
  }
}

enum RideMembershipStatus {
  invited,
  joined,
  ready,
  active,
  finished,
  left;

  static RideMembershipStatus fromWireValue(String value) {
    return RideMembershipStatus.values.firstWhere(
      (RideMembershipStatus status) => status.name == value,
      orElse: () =>
          throw FormatException('Unknown Ride membership status: $value'),
    );
  }
}

enum RideStatus {
  draft,
  published,
  active,
  completed,
  cancelled;

  String get label {
    return switch (this) {
      RideStatus.draft => 'Draft',
      RideStatus.published => 'Published',
      RideStatus.active => 'Active',
      RideStatus.completed => 'Completed',
      RideStatus.cancelled => 'Cancelled',
    };
  }

  static RideStatus fromWireValue(String value) {
    return RideStatus.values.firstWhere(
      (RideStatus status) => status.name == value,
      orElse: () => throw FormatException('Unknown Ride status: $value'),
    );
  }
}

class Ride {
  const Ride({
    required this.id,
    required this.clubId,
    required this.title,
    required this.status,
    required this.scheduledStartAt,
    required this.actualStartAt,
    required this.endedAt,
    required this.notes,
  });

  final String id;
  final String clubId;
  final String title;
  final RideStatus status;
  final DateTime? scheduledStartAt;
  final DateTime? actualStartAt;
  final DateTime? endedAt;
  final String? notes;

  factory Ride.fromJson(Map<String, Object?> json) {
    return Ride(
      id: json['id'] as String,
      clubId: json['clubId'] as String,
      title: json['title'] as String,
      status: RideStatus.fromWireValue(json['status'] as String),
      scheduledStartAt: _date(json['scheduledStartAt']),
      actualStartAt: _date(json['actualStartAt']),
      endedAt: _date(json['endedAt']),
      notes: json['notes'] as String?,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String) {
      return null;
    }

    return DateTime.tryParse(value);
  }
}

class RideMembership {
  const RideMembership({
    required this.rideId,
    required this.riderId,
    required this.role,
    required this.status,
  });

  final String rideId;
  final String riderId;
  final RideRole role;
  final RideMembershipStatus status;

  factory RideMembership.fromJson(Map<String, Object?> json) {
    return RideMembership(
      rideId: json['rideId'] as String,
      riderId: json['riderId'] as String,
      role: RideRole.fromWireValue(json['role'] as String),
      status: RideMembershipStatus.fromWireValue(json['status'] as String),
    );
  }
}

class RideListItem {
  const RideListItem({required this.ride, required this.membership});

  final Ride ride;
  final RideMembership? membership;

  factory RideListItem.fromJson(Map<String, Object?> json) {
    final Object? rawRide = json['ride'];
    if (rawRide is! Map<String, Object?>) {
      throw const FormatException('Invalid Ride list item.');
    }

    final Object? rawMembership = json['membership'];

    return RideListItem(
      ride: Ride.fromJson(rawRide),
      membership: rawMembership is Map<String, Object?>
          ? RideMembership.fromJson(rawMembership)
          : null,
    );
  }
}

class RideInput {
  const RideInput({required this.title, this.scheduledStartAt, this.notes});

  final String title;
  final DateTime? scheduledStartAt;
  final String? notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'scheduledStartAt': scheduledStartAt?.toUtc().toIso8601String(),
      'notes': notes,
    };
  }
}
