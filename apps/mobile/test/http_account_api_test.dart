import 'dart:convert';

import 'package:commride_mobile/src/api/account_api.dart';
import 'package:commride_mobile/src/api/http_account_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuthGateway implements AuthGateway {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async => 'token-1';

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

Map<String, Object?> _deletion({bool blocked = false}) => <String, Object?>{
  'clubsRequiringTransfer': blocked
      ? <Object?>[
          <String, Object?>{'clubId': 'club-x', 'name': 'Club X'},
        ]
      : <Object?>[],
  'clubsToClose': <Object?>[
    <String, Object?>{'clubId': 'club-y', 'name': 'Club Y'},
  ],
  'activeRides': <Object?>[],
  'blocked': blocked,
};

HttpAccountApi _api(MockClient client) => HttpAccountApi(
  apiBaseUrl: Uri.parse('https://api.example.test'),
  authGateway: FakeAuthGateway(),
  client: client,
);

void main() {
  test('previews deletion for the authenticated Rider', () async {
    late http.Request captured;
    final AccountDeletionPreview preview = await _api(
      MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{'deletion': _deletion()}),
          200,
        );
      }),
    ).previewDeletion();

    expect(captured.method, 'GET');
    expect(captured.url.path, '/v1/me/deletion');
    expect(captured.headers['authorization'], 'Bearer token-1');
    expect(preview.blocked, isFalse);
    expect(preview.clubsToClose.single.name, 'Club Y');
  });

  test('blocked deletion carries the current blockers', () async {
    final HttpAccountApi api = _api(
      MockClient((http.Request request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/me');
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'account_deletion_blocked',
              'message': 'Blocked.',
              'requestId': 'req-1',
            },
            'deletion': _deletion(blocked: true),
          }),
          409,
        );
      }),
    );

    await expectLater(
      api.deleteAccount(),
      throwsA(
        isA<AccountApiException>()
            .having(
              (AccountApiException e) => e.code,
              'code',
              'account_deletion_blocked',
            )
            .having(
              (AccountApiException e) =>
                  e.preview?.clubsRequiringTransfer.single.clubId,
              'blocking club',
              'club-x',
            ),
      ),
    );
  });

  test('lists Club members and transfers ownership', () async {
    final List<http.Request> requests = <http.Request>[];
    final HttpAccountApi api = _api(
      MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'members': <Object?>[
              <String, Object?>{
                'riderId': 'rider-b',
                'displayName': 'Rider B',
                'callsign': null,
                'role': 'member',
              },
            ],
          }),
          200,
        );
      }),
    );

    final List<ClubMember> members = await api.listMembers('club-x');
    await api.transferOwnership(clubId: 'club-x', riderId: 'rider-b');

    expect(members.single.role, ClubRole.member);
    expect(requests[0].url.path, '/v1/clubs/club-x/members');
    expect(requests[1].method, 'POST');
    expect(requests[1].url.path, '/v1/clubs/club-x/owner');
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'riderId': 'rider-b',
    });
  });
}
