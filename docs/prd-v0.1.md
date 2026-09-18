# CommRide PRD v0.1

Status: Draft  
Date: 18 September 2026

## 1. Purpose

This document defines the first product baseline for CommRide.

CommRide is a riding coordination platform with three connected surfaces:

1. **Ride Planning**
2. **Live Ride Coordination**
3. **Club & Social Layer**

The MVP should prove that a group can plan and complete a Ride with materially better coordination than a combination of generic navigation + chat + location sharing tools.

## 2. Primary users

### Ride Leader
Creates the Ride, plans the route, invites Riders, assigns roles, publishes briefing, starts/ends the Ride, manages checkpoints, and broadcasts important information.

### Sweeper
Maintains awareness of the rear of the group and receives enhanced attention when Riders fall behind.

### Rider
Joins a Ride, views the plan, shares location during an Active Ride, communicates, checks in, reports status, and receives alerts.

### Club Admin
Maintains the Club profile, membership, and public/social presence.

## 3. Core objects

- Rider
- Vehicle
- Club
- Club Membership
- Ride
- Ride Membership
- Route Plan
- Route Alternative
- Stop
- Checkpoint
- Segment
- Live Location Session
- Incident
- Message
- Announcement
- Post
- Follow
- Badge
- Achievement

See `docs/domain-model.md`.

## 4. MVP scope

The initial product flow is:

**Sign in -> Club -> Create Ride -> Plan Route -> Add Stops -> Invite/Join -> Briefing -> Start Ride -> Live Map -> Communication -> Checkpoint -> SOS/Help -> End Ride -> Ride Recap**

### MVP capabilities

#### Identity
- Email/social sign-in without mandatory SMS OTP.
- Rider profile.
- One or more vehicles per Rider.

#### Club
- Create Club.
- Join Club by invitation.
- Basic Club profile.
- Club roles: admin/member.

#### Ride
- Create draft Ride.
- Title, date/time, origin, destination.
- Select participating Riders.
- Assign Leader and Sweeper.
- Ride status: Draft, Published, Active, Completed, Cancelled.
- Leader may cancel a Ride only before it becomes Active (Draft or Published).
- Cancellation is idempotent; an already Cancelled Ride remains Cancelled.
- An Active Ride must be ended to become Completed rather than cancelled, preserving the operational record of a Ride that actually started.

#### Route planning
- Origin/destination search.
- Route alternatives.
- Add Stop.
- Reorder Stops.
- Remove Stop.
- Route recalculation after changes.
- Search Nearby.
- Search Along Route.
- Search categories such as fuel, food, rest area, hotel, meeting point.
- Convert a Stop into a Checkpoint.
- Checkpoint types.
- Route summary and estimated timing.
- External navigation deep link for the next destination/checkpoint.

#### Ride briefing
- Route summary.
- departure time;
- expected finish;
- stops/checkpoints;
- Leader/Sweeper;
- important notes;
- acknowledgement/readiness state.

#### Live Ride
- background location sharing while Ride is active;
- Rider markers;
- moving/stopped/offline/stale state;
- last known position;
- Live Group list;
- distance/spread summary;
- next checkpoint;
- basic off-route/separation awareness.

#### Communication
- Ride text chat.
- Leader announcement/broadcast.
- Quick actions:
  - I'm Stopping
  - I'm Left Behind
  - Need Help
- SOS action with location and timestamp.

#### Checkpoint
- Rider arrival/check-in state.
- Leader sees arrived/expected count.
- Mandatory Regroup checkpoint.
- Leader releases group after regroup.

#### End Ride
- stop live location session;
- mark Ride Completed;
- generate basic recap:
  - participants;
  - planned route;
  - actual journey summary where available;
  - duration;
  - checkpoints;
  - incidents.

## 5. Route planner requirements

The route planner should intentionally feel familiar.

### Search
The user can search for:
- cities;
- addresses;
- landmarks;
- hotels;
- restaurants;
- fuel stations;
- custom map points.

### Add Stop
A Leader can insert stops into the route and reorder them.

Every change recalculates:
- route geometry;
- total distance;
- estimated drive time;
- expected checkpoint arrival times.

Persistence rule:
- only a successful recomputation may become the new current RoutePlan;
- the previous valid plan remains current if provider recomputation fails;
- each saved plan is a new revision so reorder/add/remove history is recoverable;
- Draft and Published Rides may replace the current plan in the initial MVP;
- Active Ride replanning is deferred to an explicit operational flow.

### Search Along Route
The Leader can search categories along the planned route without manually panning the map.

Examples:
- Fuel along route
- Food along route
- Hotel along route
- Rest area along route

Results should ideally communicate detour impact where the map provider supports it.

### Checkpoint types
- Stop
- Fuel
- Rest
- Meal
- Regroup
- Mandatory Regroup
- Hotel
- Custom
- Finish

### Group-aware route metadata
The first MVP may use simple rules rather than an optimization engine.

Inputs may include:
- group size;
- vehicle type;
- shortest safe fuel range;
- planned departure;
- target arrival;
- maximum desired continuous riding period.

Outputs can initially be warnings/suggestions rather than automatic decisions.

## 6. Advanced route planning backlog

Post-MVP candidates:

- Touring Intelligence itinerary generation.
- Fuel-aware stop suggestions.
- Rest/fatigue planning.
- ETA per Rider.
- predicted separation;
- convoy split detection;
- group topology instead of only Leader radius;
- Rider recovery/rejoin routing;
- Plan A / Plan B;
- dynamic replanning when delayed;
- optional checkpoint skipping;
- split convoy groups;
- offline route package;
- route quality based on prior Ride data.

## 7. Social layer

The social layer is part of product direction but should not block Ride MVP.

### Initial social scope
- Club public profile.
- Club timeline.
- Rider follows Club.
- Club follows Club.
- Ride recap post.
- upcoming/public Ride post.
- reactions/comments can follow after the base feed is proven.

### Feed principle
Most valuable content should be generated by real Ride activity.

Examples:
- Club completed a Ride.
- Club announced an upcoming public Ride.
- Ride recap.
- Club milestone.
- Event badge earned.

### Post-MVP social candidates
- Rider-to-Rider follow;
- explore/discovery;
- hashtags/tags;
- photos/albums;
- interclub Ride discovery;
- public route sharing.

## 8. Badges and levels

### Safety rule
No badge or XP should reward:
- top speed;
- speeding;
- shortest travel time;
- longest continuous riding without rest;
- unsafe distance accumulation.

### Example Rider badges
- First Ride
- 5 Rides Together
- 10 Completed Rides
- Leader
- Sweeper
- Helper
- Explorer
- Early Member
- Club Founder
- Event Participant

### Example Club achievements
- 10 Completed Rides
- 100 Rider Participations
- Interclub Ride
- 1 Year Together
- Club Milestone

### Rider Level
A lightweight level/XP system may aggregate:
- completed Ride participation;
- leadership/sweeper participation;
- helpful contributions;
- Club contribution;
- achievements.

No public competitive leaderboard is required for MVP.

## 9. Information architecture

Proposed top-level mobile navigation:

### Home
Timeline, upcoming Ride, active Ride entry point.

### Ride
Planning, upcoming Rides, Active Ride command center, Ride history.

### Explore
Future: Clubs, public Rides, routes, discovery.

### Clubs
Memberships and Club profiles.

### Profile
Rider identity, vehicles, Ride history, badges.

When a Ride is Active, the application should foreground the Ride command center.

Suggested Active Ride tabs:
- Overview
- Map
- Route
- Convoy
- Comms

## 10. Key Active Ride views

### Overview
- active Rider count;
- next checkpoint;
- ETA;
- convoy spread;
- last Rider;
- Ride timing state;
- important alerts.

### Map
- route;
- Rider locations;
- checkpoint markers;
- live/stale status.

### Route
- segments;
- checkpoints;
- ETA;
- arrival counts.

### Convoy
- group order where derivable;
- Leader;
- Sweeper;
- large gaps;
- disconnected subgroup warning.

### Comms
- chat;
- announcements;
- quick actions;
- incidents.

## 11. Notifications

High priority:
- SOS;
- Need Help;
- group separation;
- Leader broadcast;
- mandatory regroup release/change.

Normal:
- Ride invite;
- briefing published;
- upcoming Ride reminder;
- checkpoint arrival;
- Ride recap.

Notification fatigue must be avoided.

## 12. Offline and poor connectivity

MVP requirements:
- display last known location with timestamp;
- clearly distinguish live from stale;
- queue important Rider actions when practical;
- cache essential Ride briefing and checkpoint data;
- reconnect without creating duplicate Ride state.

Future:
- downloadable offline Ride package;
- more complete offline map behavior.

## 13. Privacy and safety requirements

- Background location requires explicit permission.
- The app must clearly indicate when active Ride tracking is running.
- Live location visibility should be limited to appropriate Ride participants.
- Ending a Ride ends live tracking by default.
- Stale positions must never be visually presented as live.
- SOS should not silently contact emergency services unless a dedicated supported integration exists.
- Club/public social visibility and Ride location visibility are separate concepts.

## 14. Monetization direction

The product should not require every Rider to subscribe merely to participate in a Ride.

Candidate models:
- generous Rider free tier;
- paid Club/Organizer capabilities;
- annual Club plan;
- one-off Ride Pass;
- advanced planning/history/analytics as paid value.

The initial infrastructure should target very low or zero fixed recurring cost while usage is small.

## 15. MVP success criteria

The MVP is validated when a small real Club can:

1. create a Ride;
2. build a multi-stop route;
3. invite Riders;
4. brief the group;
5. start background location sharing;
6. see active Riders and their status;
7. communicate operationally;
8. regroup at checkpoints;
9. handle a stop/help event;
10. complete the Ride and receive a recap;

without requiring the group to manually recreate the same coordination through multiple unrelated apps.

## 16. Explicit non-goals for MVP

- embedded full turn-by-turn navigation;
- social influencer features;
- speed ranking;
- complex gamification economy;
- employer/fleet tracking;
- complex PostGIS-style analytics;
- microservice architecture;
- fully automatic AI route planner;
- large-scale public discovery before Club/Ride fundamentals are validated.
