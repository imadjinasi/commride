import 'package:commride_mobile/src/api/http_vehicle_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/vehicle_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TokenAuthGateway implements AuthGateway {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async => 'firebase-id-token';

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  test('listVehicles sends Bearer token and maps planning fields', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/me/vehicles');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      return http.Response(
        '{"vehicles":[{"id":"vehicle-1","riderId":"rider-1",'
        '"kind":"motorcycle","make":"Honda","model":"CB150R",'
        '"nickname":"Black","fuelType":"Pertamax","safeRangeKm":220,'
        '"createdAt":"2026-09-18T00:00:00Z",'
        '"updatedAt":"2026-09-18T00:00:00Z"}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpVehicleApi api = HttpVehicleApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final List<VehicleProfile> vehicles = await api.listVehicles();

    expect(vehicles, hasLength(1));
    expect(vehicles.single.kind, VehicleKind.motorcycle);
    expect(vehicles.single.safeRangeKm, 220);
    expect(vehicles.single.displayName, 'Black · Honda · CB150R');
  });

  test('createVehicle serializes optional safe range', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/me/vehicles');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');
      expect(request.body, contains('"safeRangeKm":180'));

      return http.Response(
        '{"vehicle":{"id":"vehicle-2","riderId":"rider-1",'
        '"kind":"motorcycle","make":"Yamaha","model":"XSR 155",'
        '"nickname":null,"fuelType":null,"safeRangeKm":180,'
        '"createdAt":"2026-09-18T00:00:00Z",'
        '"updatedAt":"2026-09-18T00:00:00Z"}}',
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpVehicleApi api = HttpVehicleApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final VehicleProfile vehicle = await api.createVehicle(
      const VehicleProfileInput(
        kind: VehicleKind.motorcycle,
        make: 'Yamaha',
        model: 'XSR 155',
        safeRangeKm: 180,
      ),
    );

    expect(vehicle.id, 'vehicle-2');
    expect(vehicle.safeRangeKm, 180);
  });
}
