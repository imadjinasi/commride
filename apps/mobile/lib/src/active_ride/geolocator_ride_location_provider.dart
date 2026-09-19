import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';

import 'location_provider.dart';

class GeolocatorRideLocationProvider implements RideLocationProvider {
  GeolocatorRideLocationProvider();

  final StreamController<RideLocationSample> _samples =
      StreamController<RideLocationSample>.broadcast();

  StreamSubscription<Position>? _positionSubscription;

  @override
  Stream<RideLocationSample> get samples => _samples.stream;

  @override
  Future<RideLocationPermission> checkPermission() async {
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<RideLocationPermission> requestPermission() async {
    return _mapPermission(await Geolocator.requestPermission());
  }

  @override
  Future<void> start() async {
    if (_positionSubscription != null) {
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Layanan lokasi perangkat belum aktif.');
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _settings(),
    ).listen(
      (Position position) {
        _samples.add(
          RideLocationSample(
            latitude: position.latitude,
            longitude: position.longitude,
            observedAt: position.timestamp.toUtc(),
            movement: _movement(position),
          ),
        );
      },
      onError: _samples.addError,
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _samples.close();
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'CommRide · Ride aktif',
          notificationText:
              'Lokasi dibagikan untuk koordinasi Ride yang sedang aktif.',
          enableWakeLock: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 25,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
    );
  }

  RideLocationPermission _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => RideLocationPermission.granted,
      LocationPermission.denied => RideLocationPermission.denied,
      LocationPermission.deniedForever =>
        RideLocationPermission.deniedPermanently,
      LocationPermission.unableToDetermine => RideLocationPermission.unknown,
    };
  }

  RideMovementState _movement(Position position) {
    final double speed = position.speed;
    if (!speed.isFinite || speed < 0) {
      return RideMovementState.unknown;
    }
    if (speed <= 0.8) {
      return RideMovementState.stopped;
    }
    if (speed >= 1.5) {
      return RideMovementState.moving;
    }
    return RideMovementState.unknown;
  }
}
