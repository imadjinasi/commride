# CommRide Product Vision

Status: Draft v0.1  
Last updated: 18 September 2026

## 1. Positioning

CommRide is a communication and coordination app for people who ride together.

It is not merely a GPS tracker and not a generic social network. CommRide helps riders remain connected, visible to the group, and aware of one another's condition throughout a shared journey.

The core product question is:

> **How do we get there together?**

rather than only:

> How do I get there?

## 2. Brand foundation

**Name:** CommRide

Meaning:
- **COMM** -> Communication
- **RIDE** -> Riding
- Secondary association: **comrade** -> a companion on the journey

**Primary tagline:** Ride Connected.  
**Brand promise:** Nobody rides alone.  
**Secondary line:** Your Ride. Your Comrades.  
**Long-form line:** Stay connected. Know who's with you.

## 3. Brand character

CommRide should feel:

- **Rider-first** — designed from the perspective of people actually riding.
- **Connected** — communication is central, not an add-on.
- **Confident** — functional and clear, not childish.
- **Urban** — suitable for motorcycle and car communities.
- **Practical** — every major feature must have a reason during a real journey.

CommRide should avoid feeling:

- excessively adventure/outdoor;
- racing-oriented;
- military;
- corporate-startup;
- gamer-like.

## 4. Product philosophy

### 4.1 Group awareness, not surveillance

CommRide is not built to watch people.

Location sharing is contextual to a Ride and exists to help a group coordinate. Riders should understand when location sharing is active, who can see it, and when it ends.

### 4.2 Familiar route planning, group-specific intelligence

Route planning should use interaction patterns already familiar from mainstream mapping products:

- search origin and destination;
- route alternatives;
- add stop;
- reorder stops;
- search along route;
- search nearby;
- route modifiers;
- ETA recalculation;
- open external navigation.

The differentiation is not a novel map interaction. The differentiation is that CommRide applies those familiar patterns to a group.

### 4.3 The Ride is more important than the feed

The social layer exists because riders and clubs have activity before and after a Ride.

During an Active Ride, coordination has priority over social content.

> **The social layer grows from real rides. The ride experience must never become secondary to the feed.**

### 4.4 Cooperation, not speed competition

Badges, levels, achievements, and statistics must not incentivize speeding, unsafe distance chasing, or risky riding.

CommRide should reward participation, consistency, contribution, assistance, leadership, and shared experiences rather than speed.

## 5. Core product loop

**Discover -> Plan -> Ride -> Coordinate -> Review -> Share -> Connect -> Ride Again**

### Discover
Find Clubs, public activity, Ride recaps, upcoming public Rides, and interesting routes.

### Plan
Create a Ride, search routes, add stops, define checkpoints, invite Riders, assign roles, and publish the Ride Briefing.

### Ride
Share live location, follow the group route, see the next checkpoint, communicate, report stops/incidents, regroup, and request help.

### Review
Compare planned vs actual journey and generate a Ride recap.

### Share
Publish the recap, photos, milestones, and achievements to the social layer.

### Connect
Follow Clubs, discover communities, and maintain relationships between groups.

## 6. Core vocabulary

**Club -> Ride -> Riders -> Route -> Stops -> Checkpoints -> Segments**

Roles:
- Leader
- Sweeper
- Navigator
- Member

Social concepts:
- Club Profile
- Follow
- Post
- Ride Recap
- Badge
- Achievement
- Rider Level

## 7. Three Ride states

### PLAN
Search route, compare alternatives, add stops, set checkpoints, invite Riders, assign roles, and complete briefing.

### RIDE
Live Group, route progress, communication, next checkpoint, separation awareness, SOS, incident reports, and regrouping.

### REVIEW
Actual route, duration, stops, checkpoint timeline, incidents, group spread, photos, recap, and achievements.

## 8. Route planning principle

CommRide should preserve the mental model of a modern mapping application while adding group context.

The planner should eventually understand:

- number of Riders;
- motorcycle/car/mixed group;
- shortest safe fuel range in the group;
- departure time;
- target arrival time;
- rest preferences;
- fuel preferences;
- mandatory regroup points;
- planned meal or prayer stops;
- route constraints;
- planned stop duration.

The planner should be able to answer questions such as:

- Is there a reasonable fuel stop before the shortest-range vehicle reaches its safety margin?
- Where is a sensible regroup point?
- Which optional stop can be skipped if the Ride is behind schedule?
- What is the next operationally important checkpoint?

## 9. Social product principle

CommRide may feel socially alive even when no Ride is active, but it should not become a generic social network.

Initial emphasis:

- Rider follows Club;
- Club follows Club;
- Club timeline;
- Ride recap posts;
- upcoming public Ride posts;
- achievements and milestones.

Rider-to-Rider follow can be considered later if it supports real riding relationships.

## 10. Achievement principle

Achievements may include:

- First Ride
- 5 Rides Together
- 10 Completed Rides
- Leader
- Sweeper
- Helper
- Explorer
- Early Member
- Club Founder
- Interclub Ride
- Event Participant

Rider Level should remain understated and non-competitive.

XP should come from healthy participation and contribution, not speed.

## 11. Privacy principle

Location is sensitive.

The product must eventually make these states explicit:

- location sharing inactive;
- Ride location session active;
- background tracking active;
- last known location;
- live vs stale/offline location;
- who can see the Rider;
- when location history is retained or discarded.

A Ride ending should also end live Ride location visibility by default.

## 12. Visual direction

Primary brand colors:

- Comm Black — `#161616`
- Road White — `#F4F2EC`
- Signal Orange — `#FF6A1A`
- Road Grey — `#767676`

Orange is a **signal**, not the dominant surface color.

Use it for important attention states such as:

- incoming communication;
- checkpoint;
- separation;
- help;
- Ride actions.

Emergency/SOS states may require a dedicated critical-state color system distinct from ordinary Signal Orange.

Typography direction:
- Inter
- Manrope
- Plus Jakarta Sans

Use clear modern sans-serif typography. Avoid exaggerated futuristic/racing typography.

## 13. Non-goals for the initial product

The first release does not need to:

- replace Google Maps/Waze/Apple Maps turn-by-turn navigation;
- become a public influencer social network;
- provide competitive speed leaderboards;
- support fleet-management/employer surveillance;
- implement every possible Club administration feature;
- build advanced spatial analytics before real usage requires it.

## 14. Product north star

A successful CommRide should make this statement true:

> A Rider can join a group trip, understand the plan, see who is still with the group, know what comes next, communicate quickly, surface problems, regroup when needed, and finish with a useful shared record of the Ride.
