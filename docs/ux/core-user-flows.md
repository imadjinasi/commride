# CommRide Core User Flows v0.1

Status: Draft  
Date: 18 September 2026

## 1. First-time Rider onboarding

Goal: get a Rider to a useful state without forcing Club creation.

Flow:

1. Open CommRide
2. Brand intro
3. Sign in / create account
4. Set display name or callsign
5. Optional profile photo
6. Add vehicle or Skip
7. Land on Home
8. Suggested next actions:
   - Join a Club
   - Create a Club
   - Join a Ride by invite

Do not request background location during onboarding.

Location permission should be requested in context when the Rider joins/starts a Ride that requires live tracking.

## 2. Create Club

1. Clubs
2. Create Club
3. Club name
4. handle/slug
5. city/area
6. visibility
7. logo optional
8. description optional
9. Create
10. Club Overview

Owner becomes Club admin.

## 3. Join Club

Primary methods:
- invitation link;
- invitation code;
- Club discovery + request, later.

Invite flow:

1. Open invite
2. See Club preview
3. Join Club
4. Confirm identity
5. Club Overview

## 4. Create Ride

1. Ride
2. Create Ride
3. Choose Club or personal/independent context if supported
4. Enter Ride name
5. Date/time
6. Origin
7. Destination
8. Compute route alternatives
9. Select route
10. Continue to Ride Planner

The route should become useful before asking for every advanced setting.

## 5. Add Stop

From Ride Planner:

1. Tap **Add Stop**
2. Choose:
   - Search place
   - Pick on map
   - Search Along Route
3. Select place
4. Preview detour / route impact
5. Add
6. Route recalculates
7. Stop appears in ordered itinerary
8. Optional:
   - convert to Checkpoint
   - set type
   - planned duration

## 6. Search Along Route

1. Ride Planner
2. Tap **Search Along Route**
3. Choose quick category:
   - Fuel
   - Food
   - Rest
   - Hotel
   - Custom search
4. Results appear along the planned Route
5. Each result should show useful route impact when available:
   - added distance;
   - added time;
   - position along route.
6. Select result
7. Preview
8. Add as Stop
9. Recalculate Ride plan

Important:
- search is deliberate/on-demand;
- avoid automatic repeated Places calls while panning.

## 7. Reorder Stops

1. Open itinerary
2. Long-press/reorder Stop
3. Show pending route recalculation
4. Recompute Route
5. Show changed total distance/time
6. Confirm implicitly by retaining order or explicitly if impact is large

If route computation fails, preserve the previous valid plan.

## 8. Convert Stop to Checkpoint

1. Open Stop
2. Mark as Checkpoint
3. Choose type:
   - Fuel
   - Rest
   - Meal
   - Regroup
   - Mandatory Regroup
   - Hotel
   - Custom
4. Set planned duration
5. Save

For Mandatory Regroup:
- show explanation that Leader controls release during Active Ride.

## 9. Invite Riders

1. Ride -> Riders
2. Invite
3. Select Club members or share invite link
4. Rider receives invitation
5. Rider opens Ride preview
6. Join
7. choose Vehicle if needed
8. confirm role if assigned
9. appear in Ride roster

## 10. Publish Ride Briefing

Leader flow:

1. Planner completed
2. Open Briefing
3. Review generated summary
4. Add notes
5. Publish
6. Riders notified

Rider flow:

1. Open Ride
2. Read Briefing
3. Confirm **Ready / I've read this**
4. readiness state updates

## 11. Start Ride

Leader:

1. Open published Ride near departure
2. Pre-start screen
3. Show:
   - joined Riders;
   - ready Riders;
   - missing permission warnings;
   - next checkpoint.
4. Tap Start Ride
5. Confirm location-sharing behavior
6. Ride -> Active

Rider:
- if joined, receives Active Ride prompt;
- sees a contextual explanation before any OS location prompt;
- explicitly enables Ride tracking;
- the app requests the minimum required location permission only at that point;
- joins the authenticated realtime room;
- sees a persistent in-app tracking state while the Ride session is active.

Starting a Ride does not silently start GPS publishing on another Rider's
device. Each Rider's local tracking session remains explicit.

Start Ride must be idempotent.

## 12. Active Ride normal flow

1. App foregrounds Overview
2. Rider sees next checkpoint
3. Rider enables tracking if it is not already active
4. CommRide requests location permission contextually if required
5. Rider can open Map or external navigation
6. the local Ride location session continues while the app is backgrounded where platform rules permit
7. latest observations publish to the authenticated Active Ride room
8. Leader sees group state
9. checkpoint approaches
10. Riders arrive/check in
11. if Regroup:
   - Leader sees arrival count
   - waits as needed
12. Leader releases group
13. next Segment becomes active

## 13. I'm Stopping

Rider:

1. Tap Quick Actions
2. Tap **Saya Berhenti**
3. Optional reason:
   - fuel
   - rest
   - mechanical
   - other
4. Event immediately appears in Ride
5. location attached
6. Leader/Sweeper notified appropriately

The flow should be possible with very few taps.

## 14. I'm Left Behind

1. Quick Actions
2. **Saya Tertinggal**
3. send current location
4. Leader/Sweeper receives high-priority Ride event
5. Ride UI marks Rider attention state
6. event can be resolved

Do not shame or score the Rider negatively.

## 15. Need Help

1. Quick Actions
2. **Butuh Bantuan**
3. choose reason if practical
4. current location attached
5. notify Leader/Sweeper
6. allow call/message action
7. resolve state when help is no longer needed

## 16. Ride Comms

Active Ride participant:

1. Open **Comms**
2. App loads private Ride message history from the authenticated API
3. Read the latest Leader announcement separately from ordinary chat
4. Send a chat message while the Ride is Active
5. If the send fails:
   - show the failure explicitly;
   - keep the same clientMessageId for retry;
   - do not fabricate a delivered state.
6. When a persisted `ride.message_created` realtime event arrives, insert it
   into the visible conversation without duplicating an HTTP-created message.

Leader additionally:

1. Open **Pengumuman Leader**
2. Enter concise operational text
3. Publish through the Leader-only announcement endpoint
4. Announcement is visually distinct from ordinary chat

Completed Ride:

- private history remains readable to eligible Ride participants;
- composing chat and Leader announcements is disabled;
- the screen is explicitly read-only.

Quick Actions, Checkpoints, convoy separation, Ride End, and future SOS remain
typed operational state. They are not flattened into ordinary chat messages.

## 16. SOS

1. Rider presses SOS
2. deliberate confirmation designed to avoid accidental activation
3. event sent with:
   - Rider;
   - timestamp;
   - location;
   - Ride.
4. high-priority notification to relevant Ride roles
5. show emergency contact/call options where configured
6. SOS remains visibly active until resolved/cancelled

Do not claim emergency services were contacted unless they actually were.

## 17. Mandatory Regroup

1. Riders approach checkpoint
2. arrival states update
3. Leader sees:
   - arrived;
   - en route;
   - stale/offline.
4. Ride status shows **Regrouping**
5. when appropriate, Leader taps **Release Group**
6. next Segment becomes active
7. Riders notified

## 18. Rider goes offline

1. realtime connection drops
2. last valid position remains visible
3. timestamp ages
4. state changes:
   - Live -> Stale -> Offline
5. reconnect attempts occur
6. new valid position replaces stale state

Never animate stale position as though it is live.

## 19. Rider deviates from Route

MVP:
1. server/client detects basic deviation threshold
2. Rider sees off-route warning
3. Leader may see attention state
4. Rider can open external navigation to next checkpoint

Future:
- recommended rejoin/intercept point.

## 20. End Ride

Leader:

1. Tap End Ride
2. confirmation
3. Active Ride closes
4. realtime location session ends
5. Riders receive completion state
6. recap processing begins

Rider:
- local location provider stops;
- realtime publishing stops;
- clearly sees tracking stopped.

A server `ride.ended` realtime event has the same local stop effect as the
Leader completing the Ride through the normal lifecycle command.

## 21. Ride Recap

1. Completed Ride
2. show:
   - Riders;
   - duration;
   - route summary;
   - checkpoints;
   - incidents;
   - photos later.
3. Leader/Club may publish recap to timeline
4. eligible achievements awarded

## 22. Follow Club

1. Open Club profile
2. Follow
3. Club activity may enter Home feed
4. Follow does not grant membership or location access

## 23. Badge award

1. trusted Ride/Club event occurs
2. achievement rules evaluate
3. badge awarded
4. Rider/Club sees a lightweight celebration
5. optional social post/event

No badge should depend on unsafe speed behavior.

## 24. Failure-state principles

Every core flow must define behavior for:
- no signal;
- provider timeout;
- denied location permission;
- stale route result;
- Ride already started/ended;
- duplicate command;
- user removed from Ride;
- expired invite.

The app should preserve the last known valid plan/state rather than replacing it with partial failed state.
