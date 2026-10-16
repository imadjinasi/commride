#!/usr/bin/env node
// Operator tool for web account-deletion requests (docs/account-deletion.md).
//
//   node scripts/account-deletion-sql.mjs preview <firebase-uid>
//     Prints a read-only query that shows the Rider ID, Clubs needing an
//     ownership transfer, Clubs that will close and Active Rides.
//
//   node scripts/account-deletion-sql.mjs delete <rider-id> [club-to-close ...]
//     Prints the deletion SQL. Only run it when the preview shows no blocker.
//
// Run the printed SQL with:
//   npx wrangler d1 execute commride-pilot --remote --file <file>
//
// Uses the same statements as DELETE /v1/me, so both paths follow the same
// rules. Requires Node 23.6+ (TypeScript type stripping).

import { accountDeletionStatements } from '../src/account-deletion/statements.ts';

const [mode, id, ...clubsToClose] = process.argv.slice(2);

function literal(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function inline(sql, params) {
  return sql.replace(/\?(\d+)/g, (_, index) => literal(params[Number(index) - 1]));
}

if (mode === 'preview' && id) {
  const subject = literal(id);
  console.log(`-- Read-only preview for Firebase uid ${id}
SELECT 'rider' AS kind, id, display_name AS name FROM riders
WHERE auth_subject = ${subject};

SELECT
  CASE WHEN (
    SELECT COUNT(*) FROM club_memberships other
    WHERE other.club_id = c.id AND other.status = 'active'
      AND other.rider_id <> m.rider_id
  ) > 0 THEN 'club_requires_transfer' ELSE 'club_will_close' END AS kind,
  c.id, c.name
FROM club_memberships m
JOIN clubs c ON c.id = m.club_id
JOIN riders r ON r.id = m.rider_id
WHERE r.auth_subject = ${subject} AND m.status = 'active' AND m.role = 'owner';

SELECT 'active_ride_blocks' AS kind, rd.id, rd.title AS name
FROM ride_memberships rm
JOIN rides rd ON rd.id = rm.ride_id
JOIN riders r ON r.id = rm.rider_id
WHERE r.auth_subject = ${subject} AND rd.status = 'active'
  AND rm.status NOT IN ('invited', 'left');`);
} else if (mode === 'delete' && id) {
  const statements = accountDeletionStatements(
    id,
    clubsToClose,
    new Date().toISOString(),
  );
  console.log(`-- Account deletion for Rider ${id}`);
  for (const { sql, params } of statements) {
    console.log(`${inline(sql, params)};`);
  }
} else {
  console.error(
    'Usage:\n' +
      '  node scripts/account-deletion-sql.mjs preview <firebase-uid>\n' +
      '  node scripts/account-deletion-sql.mjs delete <rider-id> [club-to-close ...]',
  );
  process.exit(1);
}
