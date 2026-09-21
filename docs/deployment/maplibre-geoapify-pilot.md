# MapLibre + Geoapify pilot migration

Date: 21 September 2026
Scope: PR #68, based on post-#67 main `6a19647653b64420e28a9de3475c77436814f571`.
Status: implementation and repository validation in progress; no provider/device acceptance.

This decision supersedes Google-specific setup instructions in older component
READMEs. Google Maps SDK/web-service billing is not required for this pilot.
External navigation links to Google Maps remain independent of the embedded map.

## Preserved product contracts

Keep Club -> Ride -> Riders -> Route -> Checkpoint, RoutePlan revisions, Briefing,
readiness, realtime ownership, explicit location permission, Quick Actions,
private Comms, SOS, End Ride and Recap unchanged. Do not silently substitute
car routing for motorcycle routing. Do not change the accepted Android identity
`io.github.imadjinasi.commride`. iOS registration and bundle identity remain pending.

The four authenticated `/v1/maps/*` endpoints continue returning CommRide DTOs.
Provider response shapes belong only inside the Geoapify adapter. Persisted routes
keep coordinates and precision-5 encoded geometry, not provider place identifiers
as geographic truth. No database migration is required for this provider change.

## Backend behavior and limits

- `GEOAPIFY_API_KEY` is the server secret; no Google key fallback.
- Autocomplete uses Geoapify geocoding; place resolution uses Place Details.
- `two_wheeler` maps to `motorcycle`, `drive` remains `drive`.
- Route requests use ordered waypoints and metric GeoJSON responses.
- `balanced` is the recommended route. Request `short` only for alternatives
  without intermediate Stops. Suppress duplicate/nearly identical choices.
- Mixed via/stopover waypoints fail explicitly because Geoapify exposes one
  intermediate-waypoint mode per request. Normal mobile Stops are stopovers.
- Geoapify documents toll/highway avoids for selected car/truck/bus modes, not
  motorcycle. Reject unsupported motorcycle modifiers rather than ignore them.
  Avoid preferences are never a guarantee that a road is legal or excluded.
- Search Along Route is an approximate sampled-area search, not exhaustive
  road-access or detour validation: at most six distance-spaced search centers,
  each with a 5 km radius and bounded results. Deduplicate by place reference,
  reject coordinates outside the route corridor, and rank by proximity to the
  route geometry. Long routes can have gaps between sampled areas.
- Fuel/Food/Hotel categories use Places; custom text uses bounded geocoding.
  Rest search is text-based and is not a guaranteed inventory of rest facilities.
- Do not invent detour distance/time: `viaPlaceDistanceMeters` and
  `viaPlaceDurationSeconds` remain null. Adding a Stop recomputes the real route.
- Keep malformed coordinates, invalid polylines, malformed provider JSON,
  authentication/quota failures and transport timeouts explicit. Never forward
  raw upstream error text, URLs containing keys, or credentials to clients/logs.
- Provider calls are on-demand, bounded, and have finite timeouts. No automatic
  paid retries or calls triggered by Rider GPS updates.

## Mobile map behavior

Use `maplibre_gl` with a separately supplied Geoapify style URL. Configuration:

- `COMMRIDE_MAPS_ENABLED=true` requests a map;
- `COMMRIDE_MAP_STYLE_URL` is an HTTPS Geoapify style URL containing only the
  dedicated client map key, never the server key;
- missing/invalid style configuration keeps the Rider list available;
- the SDK must not start its own location stream or request location permission;
- update one marker per accepted Rider observation, with name and explicit
  Live/Stale/Offline or last-known information; color alone is insufficient;
- serialize map updates so delayed work cannot restore an older snapshot;
- Fit Group is explicit; GPS updates must not recenter the camera;
- style/map failure shows an honest degraded state and a usable list;
- keep visible Geoapify/OpenStreetMap attribution and attribution links;
- remove native Google Maps imports/keys without removing Firebase/FCM or
  location declarations. Verify Android release INTERNET permission explicitly.

A mobile map key is recoverable from an installed app. Separate keys reduce blast
radius but do not by themselves enforce API-level or Android certificate
restrictions. Verify the restrictions actually offered by Geoapify; do not copy
Google-specific restriction claims. Do not commit either key or a real style URL.

## Operator sequence after repository approval

1. Provision real D1 and Worker resources using the pilot operator runbook.
2. Set `FIREBASE_PROJECT_ID=commride-pilot` and store server/FCM credentials only
   in Cloudflare secrets. Never generate service-account credentials into Git.
3. Deploy the reviewed exact SHA and record Worker version/URL and real D1 ID.
4. Verify health/version, Firebase-authenticated API and Active Ride WebSocket.
5. Verify actual Geoapify autocomplete, place lookup, motorcycle routes, Stops,
   alternatives and sampled-area search, including quota/invalid-key behavior.
6. Configure local Android Firebase, signing and the separate client map style.
   Use an ignored local `--dart-define-from-file` file rather than posting keys.
7. Build against the actual Worker URL; complete two-Rider smoke, Android device
   tests and then three-vehicle convoy acceptance while safely stopped for UI use.

Do not use a fabricated Worker URL, database ID, signing identity or credential.
Do not close #33, #52, #55, #58 or #59 on repository CI alone.

## Repository acceptance

API: npm ci, typecheck, existing regressions, provider/geometry/error tests,
migrations and Wrangler dry-run must pass on the exact PR head.
Mobile: real Flutter dependency resolution, formatting, analyzer, widget/unit
tests, native declarations, debug APK and release AAB build must pass. Do not
hand-author a Flutter lockfile. CI binaries use no real credentials and are not
proof of installed-device Firebase, map rendering, GPS or notification delivery.

Repository PASS != Provider/runtime PASS != Device PASS != Field convoy PASS.
This PR stays open until explicit merge authorization.

## Primary references checked for this migration

- https://apidocs.geoapify.com/docs/routing/
- https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/
- https://apidocs.geoapify.com/docs/place-details/
- https://apidocs.geoapify.com/docs/places/
- https://apidocs.geoapify.com/docs/maps/map-tiles/
- https://pub.dev/packages/maplibre_gl/versions/0.27.1

Live account quotas, credential restrictions, road coverage, real SDK rendering
and device behavior still require operator evidence; documentation is not runtime proof.
