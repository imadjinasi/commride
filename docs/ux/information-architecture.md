# CommRide Information Architecture v0.1

Status: Draft  
Date: 18 September 2026

## 1. Goal

The mobile information architecture should make CommRide feel useful both during a Ride and between Rides, without allowing the social layer to distract from active coordination.

The product has two operating modes:

1. **Ambient mode** — browsing Clubs, upcoming Rides, history, social activity.
2. **Active Ride mode** — a focused command center where coordination has priority.

## 2. Primary navigation

Recommended bottom navigation:

1. **Home**
2. **Ride**
3. **Explore**
4. **Clubs**
5. **Profile**

The navigation may be visually simplified while an Active Ride is in progress, but the underlying destinations remain available.

### Home

Purpose:
- social/activity timeline;
- active or upcoming Ride card;
- important invitations;
- recent Ride recap;
- followed Club activity.

Priority order:
1. Active Ride
2. upcoming Ride
3. alerts/invitations
4. timeline

### Ride

Purpose:
- create Ride;
- upcoming Rides;
- draft Rides;
- active Ride;
- Ride history.

Sections:
- Active
- Upcoming
- Drafts
- History

### Explore

Purpose:
- discover public Clubs;
- discover public Rides;
- search communities;
- later: discover shared routes or events.

Explore is intentionally not required for MVP.

### Clubs

Purpose:
- list joined Clubs;
- open Club profile;
- manage Club if authorized;
- Club members;
- Club Ride history;
- Club timeline.

### Profile

Purpose:
- Rider identity;
- callsign;
- vehicles;
- Ride history;
- badges;
- level;
- privacy/settings.

## 3. Active Ride command center

When a Ride becomes Active, the app should visually foreground the Ride.

Recommended Active Ride tabs:

1. **Overview**
2. **Map**
3. **Route**
4. **Convoy**
5. **Comms**

The active context should remain obvious at all times.

### Overview

Answers:
- What is happening now?
- What comes next?
- Is the group healthy?

Primary information:
- Ride name;
- current segment;
- next checkpoint;
- distance/ETA to checkpoint;
- Rider count;
- convoy spread;
- stale/offline Riders;
- delay vs plan;
- important alerts.

Primary actions:
- Navigate
- Broadcast
- I'm Stopping
- Need Help
- SOS

### Map

Answers:
- Where is the group?
- Where am I?
- Where is the next checkpoint?

Contains:
- selected Route;
- Rider markers;
- Leader/Sweeper distinction;
- checkpoints;
- stale-state marker treatment;
- map recenter;
- optional route overview.

Map should not become the only interface for Ride status.

### Route

Answers:
- What is the Ride plan?
- Which checkpoint is next?
- Who has arrived?

Contains:
- ordered Segments;
- Stops/Checkpoints;
- planned times;
- current ETA;
- arrival count;
- regroup state;
- optional stop actions where Leader has permission.

### Convoy

Answers:
- Is everyone still connected?
- Who is last?
- Where are large gaps?

Contains:
- Leader;
- Rider ordering when reliable enough;
- Sweeper;
- per-Rider freshness/state;
- large gap indicators;
- separated subgroup indicators.

No false precision: if ordering cannot be determined reliably, the UI should show a list or grouping rather than inventing a convoy order.

### Comms

Contains:
- Leader announcements;
- Ride chat;
- quick operational actions;
- incident updates;
- SOS/help event state.

Operational messages should remain distinguishable from casual chat.

## 4. Ride planning hierarchy

A Draft Ride contains:

1. Basics
2. Route
3. Stops & Checkpoints
4. Riders & Roles
5. Briefing
6. Publish

### Basics

- Ride name
- Club
- date/time
- visibility
- notes

### Route

- origin
- destination
- route alternatives
- route preferences

### Stops & Checkpoints

- Add Stop
- Search Along Route
- reorder
- checkpoint type
- planned duration
- mandatory regroup

### Riders & Roles

- invite Riders
- Leader
- Sweeper
- Navigator

### Briefing

- generated Ride summary
- important notes
- acknowledgement state

## 5. Club profile hierarchy

Recommended Club profile tabs:

- **Overview**
- **Rides**
- **Posts**
- **Members**
- **About**

### Overview
- logo/banner;
- name;
- city;
- follow state;
- member count;
- upcoming Ride;
- recent recap;
- achievements.

### Rides
- upcoming public Rides;
- completed public Ride recaps.

### Posts
- Club timeline.

### Members
Visibility depends on Club privacy settings.

### About
- description;
- links;
- location;
- founding information.

## 6. Rider profile hierarchy

- identity/callsign;
- Club memberships;
- vehicles;
- Ride history;
- badges;
- Rider Level;
- optional social stats.

Avoid prominent competitive stats such as top speed.

## 7. Global actions

Potential global floating or top-level actions:

- Create Ride
- Search
- Notifications

Avoid a permanent SOS button outside Active Ride context unless the product later supports emergency behavior independent of a Ride.

## 8. State-dependent navigation rules

### No Active Ride
Use normal 5-tab navigation.

### Active Ride
Home and Ride should both expose a persistent Active Ride entry point.

The app may:
- elevate Active Ride as a top banner;
- open directly to Active Ride on launch;
- persist a mini Ride status strip.

Do not fully lock the user inside Active Ride.

### SOS/critical incident
Temporarily elevate incident controls and acknowledgement status.

## 9. Language principles

Use short operational labels.

English product vocabulary may remain:
- Ride
- Rider
- Club
- Route
- Checkpoint
- Leader
- Sweeper

Indonesian action labels should stay natural:
- Mulai Ride
- Gabung Ride
- Tambah Stop
- Cari di Sepanjang Rute
- Titik Kumpul
- Saya Berhenti
- Saya Tertinggal
- Butuh Bantuan

Avoid overly technical route terminology in primary UI.

## 10. Accessibility

- Do not encode live/stale/SOS state only by color.
- Critical controls need clear text/icon labels.
- Tap targets must support gloved or one-handed use where practical.
- Avoid dense text during an Active Ride.
- Important actions should remain reachable with minimal interaction.
- Map markers require status alternatives in list/Convoy view.

## 11. Design tension to preserve

CommRide has two identities:

- a social Club platform when users are not riding;
- a focused operational tool while a Ride is active.

The UI should intentionally switch emphasis between those modes rather than forcing one interface to serve both equally.
