# CommRide Domain Model v0.1

Status: Draft  
Date: 18 September 2026

## 1. Purpose

This document defines the initial domain language and entity boundaries. It is conceptual and intentionally not a database schema yet.

## 2. Rider

Represents a person using CommRide.

Key concepts:
- identity;
- profile;
- callsign/display name;
- home area;
- vehicles;
- Club memberships;
- Ride history;
- achievements;
- privacy preferences.

A Rider can belong to multiple Clubs and join multiple Rides.

## 3. Vehicle

Represents a motorcycle or car associated with a Rider.

Candidate attributes:
- type;
- make/model;
- nickname;
- fuel type;
- approximate safe fuel range;
- optional plate visibility setting.

A Ride may select which Vehicle a Rider is using.

## 4. Club

Represents a community or riding group.

Candidate attributes:
- name;
- handle/slug;
- logo;
- banner;
- description;
- home city/area;
- public/private visibility;
- social links;
- membership policy.

A Club owns or organizes zero or more Rides.

## 5. ClubMembership

Connects Rider and Club.

Candidate roles:
- owner;
- admin;
- member.

Future roles may be added independently of Ride roles.

## 6. Follow

Represents a social relationship.

Initial supported directions:
- Rider follows Club;
- Club follows Club.

Potential later direction:
- Rider follows Rider.

Follow must not imply access to private Ride location.

## 7. Ride

Represents one shared journey.

Lifecycle:
- Draft
- Published
- Active
- Completed
- Cancelled

Lifecycle semantics:
- Draft -> Published -> Active -> Completed is the normal execution path.
- Draft or Published -> Cancelled is allowed before a Ride starts.
- Cancelled is terminal and idempotent.
- Active -> Cancelled is not allowed; once a Ride starts it must be ended as Completed so the product does not erase the fact that live Ride operations began.

Key concepts:
- organizer/Club;
- title;
- planned date/time;
- route plan;
- participating Riders;
- Ride roles;
- briefing;
- location session;
- communication;
- checkpoints;
- incidents;
- recap.

## 8. RideMembership

Connects Rider and Ride.

Candidate roles:
- Leader
- Sweeper
- Navigator
- Member

Candidate states:
- Invited
- Joined
- Ready
- Active
- Finished
- Left

Role and state are separate.

## 9. RoutePlan

Represents the planned journey for a Ride.

Contains:
- origin;
- destination;
- ordered Stops;
- selected route alternative;
- route geometry/polyline;
- estimated distance;
- estimated driving time;
- timing assumptions.

A Ride can evolve through multiple route-plan revisions.

RoutePlan revision semantics:
- each successful saved plan creates a new immutable revision;
- exactly one revision is current for a Ride;
- replacing the current plan never mutates the previous revision in place;
- a failed provider recomputation must not replace the last valid current plan;
- the initial MVP allows route-plan replacement only while the Ride is Draft or Published;
- Active Ride replanning requires a future explicit operational command rather than silently changing the pre-Ride plan.

The system retains provenance so the current plan can be distinguished from superseded revisions.

## 10. RouteAlternative

A candidate route returned by the route provider.

Potential attributes:
- provider reference;
- geometry;
- distance;
- duration;
- labels;
- toll/ferry/highway characteristics where available.

A RouteAlternative is not necessarily retained permanently after selection.

## 11. Stop

A planned point in a RoutePlan.

Types may include:
- generic;
- fuel;
- rest;
- meal;
- hotel;
- custom.

A Stop becomes operationally significant when converted to a Checkpoint.

Within one RoutePlan revision, Stops have stable IDs and a unique zero-based
sequence. Reordering changes the next revision's sequence; it does not rewrite
the prior revision.

## 12. Checkpoint

A Stop with Ride coordination semantics.

Types:
- Rest
- Fuel
- Meal
- Regroup
- Mandatory Regroup
- Hotel
- Finish
- Custom

Possible attributes:
- expected arrival;
- planned duration;
- mandatory flag;
- check-in policy;
- release state.

## 13. Segment

Represents the section between two operational route points.

Derived attributes:
- distance;
- estimated duration;
- start;
- end;
- sequence.

Segments may later carry:
- assigned Navigator;
- warnings;
- fuel margin;
- route notes.

## 14. LiveLocationSession

Represents the period when Ride location sharing is active.

It begins when the Ride starts and normally ends when the Ride ends.

Initial lifecycle semantics:
- only an Active Ride may accept realtime room connections;
- joining the room does not itself start device location tracking;
- Ride completion terminates the live room;
- reconnect after completion is rejected;
- live-room authorization is derived from authenticated RideMembership, never social follow state.

It owns/controls:
- who may publish location;
- who may view location;
- freshness semantics;
- session start/end;
- retention behavior.

This boundary is important for privacy.

## 15. RiderPresence

Ephemeral state for a Rider within an active Ride.

Potential states:
- Moving
- Stopped
- Weak Signal
- Stale
- Offline
- GPS Unavailable

Contains latest-known:
- coordinates;
- observation timestamp;
- server receipt timestamp;
- movement state;
- connection/freshness state;
- battery/network metadata only if explicitly justified and permission-safe.

Initial semantics:
- one latest RiderPresence is operationally retained per Rider in the Active Ride room;
- an older observation cannot replace a newer observation;
- disconnect changes connection state to Offline without pretending the last coordinate disappeared;
- Stale/Offline positions retain timestamps;
- RiderPresence is overwritten operational state, not an append-only GPS log.

RiderPresence should be treated differently from long-term route history.

## 16. LocationSample

A historical position sample retained for Ride history/recap.

The system should not assume every realtime location update must become a permanent LocationSample.

Sampling/retention should control cost and privacy exposure.

## 17. Message

A communication event in a Ride.

Initial types:
- text message;
- Leader announcement;
- quick-action status.

Future:
- voice note;
- image/attachment.

## 18. QuickAction

Operational communication with predefined semantics.

Initial:
- I'm Stopping
- I'm Left Behind
- Need Help

QuickAction should create a visible event and may trigger notifications.

## 19. Incident

Represents a noteworthy event during a Ride.

Types may include:
- flat tire;
- mechanical issue;
- accident;
- out of fuel;
- stopping;
- rest;
- other.

SOS is treated as a special high-priority incident/event.

## 20. SOS

A high-priority request for attention associated with:
- Rider;
- Ride;
- location;
- timestamp;
- optional emergency contact action.

SOS is not equivalent to contacting public emergency services unless such an integration is explicitly implemented.

## 21. CheckIn

Connects Rider and Checkpoint with arrival data.

Candidate fields:
- arrived_at;
- method;
- optional location confirmation.

The Leader can see arrival counts without needing to infer solely from GPS.

## 22. RideBriefing

Snapshot of operational information published before a Ride.

Includes:
- route summary;
- stops/checkpoints;
- Leader/Sweeper;
- timing;
- notes.

RideBriefing revision semantics:
- each publish creates a new immutable briefing revision;
- exactly one briefing revision is current for a Ride;
- the briefing references the exact immutable RoutePlan revision that was reviewed;
- if the current RoutePlan later changes, the latest briefing remains readable but is stale until the Leader publishes a new briefing revision;
- only Draft or Published Rides may publish or replace the current briefing in the initial MVP.

Briefing acknowledgement/readiness is scoped to one Rider and one exact
RideBriefing revision. Acknowledgement of an older briefing remains historical
but does not count toward readiness for a newer revision.

Readiness is advisory in the MVP. It is visible to the Leader before Start Ride
but does not automatically block the Leader from starting the Ride.

## 23. RideRecap

Post-Ride aggregate generated after completion.

Possible contents:
- participants;
- duration;
- distance;
- checkpoint timeline;
- planned vs actual;
- incidents;
- photos;
- achievements.

A RideRecap may produce a social Post.

## 24. Post

A social timeline item.

Initial sources:
- manually created Club post;
- Ride announcement;
- Ride recap;
- Club milestone;
- achievement.

Post visibility must be independent of private Ride location visibility.

## 25. BadgeDefinition

Defines an achievement that can be earned.

Examples:
- First Ride;
- Leader;
- Sweeper;
- Helper;
- Explorer;
- Event Participant.

Badge rules must not incentivize unsafe behavior.

## 26. Achievement

Connects a BadgeDefinition to a Rider or Club.

Includes:
- awarded_at;
- source Ride/event where applicable;
- metadata/provenance.

## 27. RiderLevel

Optional progression aggregate.

Potential input:
- Ride participation;
- healthy contribution;
- leadership;
- assistance;
- achievements.

It is not a speed/race score.

## 28. Important domain boundaries

### Club membership != Ride participation
A Rider may join a Ride without all Club privileges, depending on future invitation rules.

### Social follow != location access
Following a Club does not allow seeing private live Rider locations.

### Realtime presence != permanent history
The latest live coordinates are an operational state; retained history is a separate policy decision.

### Route provider data != CommRide domain
Provider-specific IDs and map data should be wrapped behind provider adapters where practical.

### Ride role != Club role
Club admin and Ride Leader are separate concepts.

## 29. Open questions

To resolve before implementation of each area:

- Can a Ride have multiple organizing Clubs?
- Can public Rides allow non-members to request to join?
- What exact location history retention is appropriate?
- Does a Rider choose one active Vehicle per Ride?
- How long should Completed Ride route history remain?
- Which social visibility defaults are safest?
- Should checkpoint check-in be automatic, manual, or hybrid?
