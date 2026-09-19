import '../models/club_ride.dart';

abstract interface class ClubRideApi {
  Future<List<ClubListItem>> listClubs();

  Future<Club> createClub(ClubInput input);

  Future<void> inviteClubMember({
    required String clubId,
    required String riderId,
    required ClubRole role,
  });

  Future<void> joinClub(String clubId);

  Future<List<RideListItem>> listRides(String clubId);

  Future<Ride> createRide(String clubId, RideInput input);

  Future<void> inviteRideMember({
    required String rideId,
    required String riderId,
    required RideRole role,
  });

  Future<void> joinRide(String rideId);

  Future<Ride> publishRide(String rideId);

  Future<Ride> startRide(String rideId);

  Future<Ride> endRide(String rideId);

  Future<Ride> cancelRide(String rideId);
}

class ClubRideApiException implements Exception {
  const ClubRideApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => 'ClubRideApiException($statusCode, $code, $message)';
}
