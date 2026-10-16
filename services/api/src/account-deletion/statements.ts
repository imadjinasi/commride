// Plain TypeScript (erasable syntax only) so the operator tool can run it
// directly with Node; see scripts/account-deletion-sql.mjs.

export const DELETED_RIDER_NAME = 'Rider terhapus';

export interface DeletionStatement {
  readonly sql: string;
  readonly params: readonly string[];
}

/**
 * Ordered SQL for one account deletion. Shared by the API and the operator
 * tool that handles web deletion requests, so both follow the same rules.
 */
export function accountDeletionStatements(
  riderId: string,
  clubsToClose: readonly string[],
  deletedAt: string,
): DeletionStatement[] {
  const statements: DeletionStatement[] = [];
  const add = (sql: string, ...params: string[]) =>
    statements.push({ sql: sql.trim(), params });

  // Close Clubs the Rider owns alone: cancel their open Rides and end every
  // membership so the Club disappears for everyone.
  for (const clubId of clubsToClose) {
    add(
      `UPDATE rides SET status = 'cancelled', updated_at = ?2
       WHERE club_id = ?1 AND status IN ('draft', 'published')`,
      clubId,
      deletedAt,
    );
    add(
      `UPDATE club_memberships SET status = 'left', left_at = ?2
       WHERE club_id = ?1 AND status <> 'left'`,
      clubId,
      deletedAt,
    );
    add(
      `UPDATE clubs SET closed_at = ?2, updated_at = ?2 WHERE id = ?1`,
      clubId,
      deletedAt,
    );
  }

  // Upcoming Rides the Rider organises or leads are cancelled rather than
  // left without an organiser.
  add(
    `UPDATE rides SET status = 'cancelled', updated_at = ?2
     WHERE status IN ('draft', 'published')
       AND (
         created_by_rider_id = ?1
         OR id IN (
           SELECT ride_id FROM ride_memberships
           WHERE rider_id = ?1 AND role = 'leader' AND status <> 'left'
         )
       )`,
    riderId,
    deletedAt,
  );

  // Leave upcoming Rides; pending invitations are not history.
  add(
    `DELETE FROM ride_memberships
     WHERE rider_id = ?1 AND status = 'invited'
       AND ride_id IN (
         SELECT id FROM rides WHERE status IN ('draft', 'published', 'cancelled')
       )`,
    riderId,
  );
  add(
    `UPDATE ride_memberships SET status = 'left'
     WHERE rider_id = ?1 AND status NOT IN ('invited', 'left')
       AND ride_id IN (
         SELECT id FROM rides WHERE status IN ('draft', 'published', 'cancelled')
       )`,
    riderId,
  );

  add(
    `UPDATE club_memberships SET status = 'left', left_at = ?2
     WHERE rider_id = ?1 AND status <> 'left'`,
    riderId,
    deletedAt,
  );

  // Personal data.
  for (const table of [
    'vehicles',
    'ride_location_samples',
    'rider_push_tokens',
    'rider_notifications',
    'ride_briefing_acknowledgements',
  ]) {
    add(`DELETE FROM ${table} WHERE rider_id = ?1`, riderId);
  }

  // Shared records keep the Rider reference but lose the stored name.
  add(
    `UPDATE ride_messages SET sender_display_name = ?2 WHERE sender_rider_id = ?1`,
    riderId,
    DELETED_RIDER_NAME,
  );
  add(
    `UPDATE ride_sos SET rider_display_name = ?2 WHERE rider_id = ?1`,
    riderId,
    DELETED_RIDER_NAME,
  );
  add(
    `UPDATE ride_briefings SET leader_display_name = ?2 WHERE leader_rider_id = ?1`,
    riderId,
    DELETED_RIDER_NAME,
  );
  add(
    `UPDATE ride_briefings SET sweeper_display_name = ?2 WHERE sweeper_rider_id = ?1`,
    riderId,
    DELETED_RIDER_NAME,
  );

  // Tombstone: the login can never resolve to this Rider again.
  add(
    `UPDATE riders
     SET display_name = ?2,
         callsign = NULL,
         home_area = NULL,
         auth_subject = 'deleted:' || id,
         deleted_at = ?3,
         updated_at = ?3
     WHERE id = ?1`,
    riderId,
    DELETED_RIDER_NAME,
    deletedAt,
  );

  return statements;
}
