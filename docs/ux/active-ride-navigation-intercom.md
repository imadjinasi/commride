# Active Ride Navigation + Group Intercom

Date: 21 September 2026  
Status: Accepted product direction; provider activation pending

## Product statement

Active Ride is not a tracking dashboard with a map button. Its primary
foreground is a **navigation command center** that combines:

1. embedded turn-by-turn navigation;
2. live convoy awareness on the same map;
3. always-connected Ride voice intercom;
4. low-interaction operational alerts and SOS.

The target feeling is familiar navigation, with CommRide differentiation layered
around the group rather than inventing a novel navigation interaction.

## Screen hierarchy

### Top — navigation context
Show the next maneuver, distance, road/segment context, and compact group state.
Role/attention information must stay glanceable.

### Center — primary navigation map
Rider guidance owns the map camera while guidance is active. Overlay authorized
Ride participants with callsign/name, operational role and freshness. A stale or
offline observation stays visibly stale/offline and is never animated as live.

Routine use must not require switching to a separate map solely to see the
convoy.

### Bottom — communication dock
Primary controls:
- **Mic On / Mic Off**;
- group listening/output state;
- Riders/participants sheet;
- deliberate **SOS**.

PTT can be selected as an alternate voice mode. It is not the default.

## Voice modes

### Group Intercom — default
The Rider participates like a group call. Mic On is persistent until the Rider
turns it off. Voice activity/noise suppression should avoid transmitting
constant non-speech noise where the media provider supports it.

### Push to Talk — optional
The Rider holds or uses a dedicated mapped control only while speaking. This is
useful for large/noisy Rides but is never silently imposed.

### Listen Only
The Rider receives Ride voice but does not transmit.

## Moderation and privacy

Local mute affects only what that Rider hears.

Leader moderator-mute can stop a participant from transmitting to the group.
Leader cannot remotely unmute or enable another Rider's microphone.

Mic state must remain visible. Joining an Active Ride does not authorize hidden
microphone activation.

## Hardware control

Do not repurpose standard media Play/Pause, Next or Previous controls for
CommRide Mic Toggle/PTT by default.

A dedicated headset/intercom/handlebar/BLE input may be mapped only when the
platform/accessory exposes it as a distinct controllable input. On-screen
controls always remain available.

## Audio priority

Target priority:

**SOS > Leader Broadcast > Navigation Prompt > Group Voice > Music**

Where platform/audio-route behavior allows, routine navigation and Ride voice
should duck/mix media rather than unexpectedly pause or seize playback. Bluetooth
headsets may change audio profile while their microphone is used; this requires
real-device acceptance and cannot be guaranteed uniformly in repository tests.

## SOS voice behavior

SOS is a deliberate Ride-internal alert, not public-emergency dispatch.

After deliberate activation:
- persist the existing SOS incident;
- highlight the Rider and last trusted position/freshness;
- send a high-priority Ride audio alert, for example
  “SOS — <callsign> — <vehicle>”;
- repeat according to a bounded alert policy until acknowledged;
- allow the SOS Rider to speak immediately on a priority channel;
- Leader/Sweeper can acknowledge/respond/resolve through existing incident rules.

Do not claim ambulance, police or other public emergency services were called.

## Roles

Current persisted operational roles remain:
- Leader;
- Navigator;
- Sweeper;
- Member/Rider.

The UI may later add Marshal as an explicit operational role after its authority
and persistence contract are defined. Mechanic/First Aid and similar attributes
fit better as Rider capability tags than hierarchy roles.

## Navigation provider transition

The working MapLibre + Geoapify pilot remains a fallback.

When Google is enabled:
- Places handles place discovery;
- Routes computes the shared plan;
- a fresh compatible route token bridges that selected plan into Navigation SDK;
- Navigation SDK provides embedded guidance;
- CommRide overlays RiderPresence and group state.

Because route tokens are short-lived, persist the provider-independent RoutePlan
and recompute/refresh before guidance rather than storing the token in D1.

## Active Ride route revision

Pre-Ride planning remains Leader-owned.

While a Ride is Active, Leader or Navigator may deliberately open RoutePlan,
review/recompute the candidate, and save a new revision. The previous revision
is retained; CommRide does not rewrite it in place.

The saved D1 revision is authoritative. The Active Ride room broadcasts
`ride.route_plan_updated` as coordination metadata. Connected navigation
clients then fetch the persisted RoutePlan and obtain a fresh compatible route
token before changing embedded guidance.

A client must not silently switch to a materially different provider route when
refreshing an expiring route token. If the newly computed provider geometry no
longer matches the selected persisted route closely enough, guidance keeps the
existing plan and asks for explicit route review.

If persistence succeeds but realtime delivery is degraded, the saving Rider is
warned that other Riders may still be following the previous revision. This
state is not reported as synchronized.

## Voice architecture boundary

Durable Objects continue to own Ride presence/control events and can participate
in signalling/control metadata. They must not become the realtime audio relay.

Actual group media should use WebRTC with an appropriate SFU/media service. The
provider choice, costs, codec policy, noise/echo cancellation, background audio,
Bluetooth routing, moderation enforcement and failure recovery require a separate
technical decision and field acceptance.

## Gating

Repository code may be prepared before provider billing is available.

Google navigation remains **OFF by default** until:
1. billing is active;
2. required Google Maps Platform APIs are enabled;
3. backend and mobile API keys are created separately and restricted;
4. Android package/signing restrictions are verified;
5. real-device route-token navigation passes;
6. actual map, reroute, voice coexistence and background behavior are tested.

Repository PASS is not Provider PASS or Device PASS.


## Route changes while moving

Leader and Navigator should not have to abandon the Active Ride context just to
perform a routine route change.

The navigation surface exposes a compact Route action sheet with:
- **Tambah Stop**;
- **Cari sepanjang rute**;
- **Kelola RoutePlan lengkap**.

The quick actions open the existing Route Planner with the requested action
already selected. Guidance remains the operational context, but a changed route
is never applied merely because a place was selected. The user must save the
new RoutePlan revision; only then can connected Riders fetch and apply the new
authoritative plan.

This keeps the interaction close to familiar navigation products while
preserving CommRide's explicit shared-route revision model.
