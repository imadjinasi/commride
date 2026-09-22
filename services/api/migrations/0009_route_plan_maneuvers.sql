-- Persist provider-neutral turn-by-turn maneuvers with each immutable
-- RoutePlan revision. Existing revisions remain valid with an empty maneuver
-- list; clients must never fabricate guidance from an empty list.

ALTER TABLE route_plans
ADD COLUMN maneuvers_json TEXT NOT NULL DEFAULT '[]';
