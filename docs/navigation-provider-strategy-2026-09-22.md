# Navigation Provider Strategy — 22 September 2026

Status: Accepted direction; runtime migration pending

## Decision

CommRide will optimize for a free/low-cost pilot and low launch cost without
giving up the navigation-first Active Ride experience.

Primary target:
- MapLibre — embedded map/navigation rendering;
- CommRide Navigation Engine — local progress, maneuvers, deviation/recovery UX;
- Valhalla — target self-hosted motorcycle RoutePlan engine;
- TomTom REST — realtime traffic/incidents and optional place search;
- Geoapify — proven transition/fallback until replacements pass runtime gates;
- Google adapters — optional future capability, not the pilot default.

## Product rule: rejoin before reroute

An off-route GPS condition never authorizes an automatic shared RoutePlan
replacement.

Default:
1. detect sustained deviation;
2. keep the accepted RoutePlan authoritative;
3. guide toward a sensible future rejoin point;
4. offer **Cari rute baru** deliberately;
5. preview the replacement;
6. only Leader/Navigator may persist a shared Active Ride replacement revision.

Member/Sweeper deviation must not reroute the convoy.

## Cost and commercial rationale

The pilot must be operable without a mandatory provider subscription or large
billing deposit. Self-hosted Valhalla removes per-route vendor pricing from the
long-term core. TomTom REST is used only behind server adapters and bounded
quotas. Geoapify is retained because it already has real pilot runtime evidence.

Commercial/free allowances and provider terms can change. Before public launch,
record current terms and quotas in operational evidence; do not turn a dated
pricing observation into a permanent product assumption.

## Migration rule

Do not replace a working provider merely because repository code exists.

Order:
**repository adapter -> provider/runtime proof -> installed-device proof -> field convoy proof -> default switch**.

Each provider must fail honestly. The previous valid RoutePlan remains
authoritative when a planning/replacement call fails.
