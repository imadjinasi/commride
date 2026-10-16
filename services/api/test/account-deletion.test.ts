import { beforeEach, describe, expect, it } from 'vitest';

import {
  D1AccountDeletionRepository,
  DELETED_RIDER_NAME,
} from '../src/account-deletion/repository';
import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import { D1ClubOwnershipRepository } from '../src/club-ownership/repository';
import { D1RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';
import { createSqliteD1, type SqliteD1 } from './support/sqlite-d1';

const NOW = '2026-10-16T08:00:00.000Z';

class TokenIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    return { subject: `firebase-${token}` };
  }
}

// Rider A is the account being deleted.
// - Club X: A owns it, B is an active member  -> needs transfer
// - Club Y: A owns it alone, C only invited   -> closes
// - Club Z: B owns it, A is a member
// - R1 (X, completed): A and B rode it; A wrote a message and raised SOS
// - R2 (Z, published): created by B, A joined -> A leaves
// - R3 (Z, published): created and led by A    -> cancelled
// - R4 (Y, draft): created by A                -> cancelled with the Club
function seed(db: SqliteD1): void {
  db.exec(`
    INSERT INTO riders(id, auth_subject, display_name, callsign, home_area) VALUES
      ('rider-a', 'firebase-a', 'Rider A', 'Alpha', 'Cirebon'),
      ('rider-b', 'firebase-b', 'Rider B', NULL, NULL),
      ('rider-c', 'firebase-c', 'Rider C', NULL, NULL);

    INSERT INTO clubs(id, created_by_rider_id, name, slug) VALUES
      ('club-x', 'rider-a', 'Club X', 'club-x'),
      ('club-y', 'rider-a', 'Club Y', 'club-y'),
      ('club-z', 'rider-b', 'Club Z', 'club-z');

    INSERT INTO club_memberships(club_id, rider_id, role, status, joined_at) VALUES
      ('club-x', 'rider-a', 'owner', 'active', '${NOW}'),
      ('club-x', 'rider-b', 'member', 'active', '${NOW}'),
      ('club-y', 'rider-a', 'owner', 'active', '${NOW}'),
      ('club-z', 'rider-b', 'owner', 'active', '${NOW}'),
      ('club-z', 'rider-a', 'member', 'active', '${NOW}');
    INSERT INTO club_memberships(club_id, rider_id, role, status) VALUES
      ('club-y', 'rider-c', 'member', 'invited');

    INSERT INTO rides(id, club_id, created_by_rider_id, title, status,
                      actual_start_at, ended_at) VALUES
      ('ride-1', 'club-x', 'rider-a', 'R1', 'completed', '${NOW}', '${NOW}'),
      ('ride-2', 'club-z', 'rider-b', 'R2', 'published', NULL, NULL),
      ('ride-3', 'club-z', 'rider-a', 'R3', 'published', NULL, NULL),
      ('ride-4', 'club-y', 'rider-a', 'R4', 'draft', NULL, NULL);

    INSERT INTO vehicles(id, rider_id, kind, make) VALUES
      ('vehicle-a', 'rider-a', 'motorcycle', 'Honda');

    INSERT INTO ride_memberships(ride_id, rider_id, vehicle_id, role, status, joined_at) VALUES
      ('ride-1', 'rider-a', 'vehicle-a', 'leader', 'finished', '${NOW}'),
      ('ride-1', 'rider-b', NULL, 'member', 'finished', '${NOW}'),
      ('ride-2', 'rider-b', NULL, 'leader', 'joined', '${NOW}'),
      ('ride-2', 'rider-a', 'vehicle-a', 'member', 'joined', '${NOW}'),
      ('ride-3', 'rider-a', NULL, 'leader', 'joined', '${NOW}'),
      ('ride-3', 'rider-b', NULL, 'member', 'joined', '${NOW}'),
      ('ride-4', 'rider-a', NULL, 'leader', 'joined', '${NOW}');

    INSERT INTO ride_messages(id, ride_id, sender_rider_id, sender_display_name,
                              sender_ride_role, kind, body, client_message_id,
                              created_at) VALUES
      ('message-1', 'ride-1', 'rider-a', 'Rider A', 'leader', 'chat',
       'Regroup di depan.', 'client-message-1', '${NOW}');

    INSERT INTO ride_sos(id, ride_id, rider_id, rider_display_name,
                         rider_ride_role, state, client_command_id, raised_at) VALUES
      ('sos-1', 'ride-1', 'rider-a', 'Rider A', 'leader', 'active',
       'client-sos-1', '${NOW}');

    INSERT INTO ride_location_samples(id, ride_id, rider_id, latitude, longitude,
                                      observed_at, received_at, movement) VALUES
      ('sample-1', 'ride-1', 'rider-a', -6.73, 108.55, '${NOW}', '${NOW}', 'moving');

    INSERT INTO rider_push_tokens(id, rider_id, token, platform, created_at, updated_at) VALUES
      ('push-a', 'rider-a', 'token-a', 'android', '${NOW}', '${NOW}');

    INSERT INTO rider_notifications(id, rider_id, scope, event_key, kind, title,
                                    body, created_at) VALUES
      ('notification-a', 'rider-a', 'account', 'club-invite:club-z:rider-a',
       'club_invite', 'Undangan Club', 'Anda diundang.', '${NOW}');
  `);
}

describe('account deletion', () => {
  let db: SqliteD1;
  let repository: D1AccountDeletionRepository;

  beforeEach(async () => {
    db = await createSqliteD1();
    seed(db);
    repository = new D1AccountDeletionRepository(db.d1);
  });

  it('previews Clubs needing transfer and Clubs that will close', async () => {
    const preview = await repository.preview('rider-a');

    expect(preview.clubsRequiringTransfer).toEqual([
      { clubId: 'club-x', name: 'Club X' },
    ]);
    expect(preview.clubsToClose).toEqual([
      { clubId: 'club-y', name: 'Club Y' },
    ]);
    expect(preview.activeRides).toEqual([]);
  });

  it('blocks deletion while the Rider is in an Active Ride', async () => {
    db.exec(`
      UPDATE rides SET status = 'active', actual_start_at = '${NOW}'
      WHERE id = 'ride-2'
    `);

    const preview = await repository.preview('rider-a');

    expect(preview.activeRides).toEqual([{ rideId: 'ride-2', title: 'R2' }]);
  });

  it('transfers ownership so only one active owner remains', async () => {
    const ownership = new D1ClubOwnershipRepository(db.d1);

    await ownership.transferOwnership('club-x', 'rider-a', 'rider-b', NOW);

    expect(await ownership.listActiveMembers('club-x')).toEqual([
      {
        riderId: 'rider-b',
        displayName: 'Rider B',
        callsign: null,
        role: 'owner',
      },
      {
        riderId: 'rider-a',
        displayName: 'Rider A',
        callsign: 'Alpha',
        role: 'admin',
      },
    ]);
  });

  it('deletes personal data and keeps shared history anonymous', async () => {
    await new D1ClubOwnershipRepository(db.d1).transferOwnership(
      'club-x',
      'rider-a',
      'rider-b',
      NOW,
    );

    await repository.deleteAccount('rider-a', ['club-y'], NOW);

    expect(
      db.query('SELECT display_name, callsign, home_area, auth_subject, deleted_at FROM riders WHERE id = ?', 'rider-a'),
    ).toEqual([
      {
        display_name: DELETED_RIDER_NAME,
        callsign: null,
        home_area: null,
        auth_subject: 'deleted:rider-a',
        deleted_at: NOW,
      },
    ]);

    for (const table of [
      'vehicles',
      'ride_location_samples',
      'rider_push_tokens',
      'rider_notifications',
    ]) {
      expect(
        db.query(`SELECT * FROM ${table} WHERE rider_id = ?`, 'rider-a'),
      ).toEqual([]);
    }

    // Shared history stays for Rider B, without A's name.
    expect(
      db.query('SELECT sender_display_name FROM ride_messages'),
    ).toEqual([{ sender_display_name: DELETED_RIDER_NAME }]);
    expect(db.query('SELECT rider_display_name FROM ride_sos')).toEqual([
      { rider_display_name: DELETED_RIDER_NAME },
    ]);
    expect(
      db.query(
        "SELECT rider_id, status FROM ride_memberships WHERE ride_id = 'ride-1' ORDER BY rider_id",
      ),
    ).toEqual([
      { rider_id: 'rider-a', status: 'finished' },
      { rider_id: 'rider-b', status: 'finished' },
    ]);

    // Upcoming Rides: A left R2, R3 (A led it) and R4 (closed Club) cancelled.
    expect(
      db.query("SELECT id, status FROM rides ORDER BY id"),
    ).toEqual([
      { id: 'ride-1', status: 'completed' },
      { id: 'ride-2', status: 'published' },
      { id: 'ride-3', status: 'cancelled' },
      { id: 'ride-4', status: 'cancelled' },
    ]);
    expect(
      db.query(
        "SELECT status FROM ride_memberships WHERE ride_id = 'ride-2' AND rider_id = 'rider-a'",
      ),
    ).toEqual([{ status: 'left' }]);

    // Club Y closed for everyone; A left every Club; B still owns X.
    expect(
      db.query("SELECT closed_at FROM clubs WHERE id = 'club-y'"),
    ).toEqual([{ closed_at: NOW }]);
    expect(
      db.query(
        "SELECT club_id, rider_id, status FROM club_memberships WHERE status <> 'left' ORDER BY club_id, rider_id",
      ),
    ).toEqual([
      { club_id: 'club-x', rider_id: 'rider-b', status: 'active' },
      { club_id: 'club-z', rider_id: 'rider-b', status: 'active' },
    ]);
  });

  it('API refuses deletion while blocked and detaches the login after', async () => {
    const overrides = {
      identityVerifier: new TokenIdentityVerifier(),
      riderRepository: new D1RiderRepository(db.d1),
      accountDeletionRepository: repository,
      clubOwnershipRepository: new D1ClubOwnershipRepository(db.d1),
      now: () => new Date(NOW),
    };
    const call = (method: string, path: string, body?: unknown) =>
      handleRequest(
        new Request(`https://api.example.test${path}`, {
          method,
          headers: {
            authorization: 'Bearer a',
            'content-type': 'application/json',
          },
          body: body == null ? undefined : JSON.stringify(body),
        }),
        {} as never,
        overrides,
      );

    const blocked = await call('DELETE', '/v1/me');
    expect(blocked.status).toBe(409);
    expect(await blocked.json()).toMatchObject({
      error: { code: 'account_deletion_blocked' },
      deletion: { clubsRequiringTransfer: [{ clubId: 'club-x' }] },
    });

    const members = await call('GET', '/v1/clubs/club-x/members');
    expect(members.status).toBe(200);

    const transfer = await call('POST', '/v1/clubs/club-x/owner', {
      riderId: 'rider-b',
    });
    expect(transfer.status).toBe(200);

    const deleted = await call('DELETE', '/v1/me');
    expect(deleted.status).toBe(200);
    expect(await deleted.json()).toMatchObject({
      deleted: true,
      closedClubs: [{ clubId: 'club-y' }],
    });

    // The same Firebase login no longer resolves to the old Rider.
    const profile = await call('GET', '/v1/me');
    expect(profile.status).toBe(404);
  });

  it('only the active owner can transfer, and only to an active member', async () => {
    const overrides = {
      identityVerifier: new TokenIdentityVerifier(),
      riderRepository: new D1RiderRepository(db.d1),
      clubOwnershipRepository: new D1ClubOwnershipRepository(db.d1),
    };
    const transfer = (token: string, clubId: string, riderId: string) =>
      handleRequest(
        new Request(`https://api.example.test/v1/clubs/${clubId}/owner`, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${token}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({ riderId }),
        }),
        {} as never,
        overrides,
      );

    expect((await transfer('b', 'club-x', 'rider-b')).status).toBe(403);
    expect((await transfer('a', 'club-y', 'rider-c')).status).toBe(404);
    expect((await transfer('a', 'club-x', 'rider-a')).status).toBe(400);
  });
});
