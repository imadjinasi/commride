# CommRide Low-Fidelity Wireframe Specification v0.1

Status: Draft  
Date: 18 September 2026

This is a structural specification, not final visual design.

## 1. Home — no Active Ride

```
┌──────────────────────────────────┐
│ CommRide                 🔔   ◉  │
│ Ride Connected.                  │
├──────────────────────────────────┤
│ NEXT RIDE                        │
│ Sunday Morning Ride              │
│ Sun, 06:00                       │
│ Cirebon → Kuningan               │
│ 14 Riders                        │
│ [ View Ride ]                    │
├──────────────────────────────────┤
│ Timeline                         │
│                                  │
│ Cirebon Riders                   │
│ completed a Ride                 │
│ 18 Riders · 247 km               │
│ [ Ride recap card ]              │
│                                  │
│ Bandung Classic Riders           │
│ announced a Ride                 │
│ [ View ]                         │
├──────────────────────────────────┤
│ Home Ride Explore Clubs Profile  │
└──────────────────────────────────┘
```

If there is an Active Ride, it replaces the ordinary next-Ride card with a highly visible Active Ride card.

## 2. Create Ride — route search

```
┌──────────────────────────────────┐
│ ← New Ride                       │
├──────────────────────────────────┤
│ Ride name                        │
│ [ Sunday Morning Ride         ]  │
│                                  │
│ Start                            │
│ [ Cirebon                     ]  │
│                                  │
│ Destination                      │
│ [ Where are you riding?       ]  │
│                                  │
│ Date / Departure                 │
│ [ Sun 27 Sep ] [ 06:00 ]         │
│                                  │
│ [ Find Routes ]                  │
└──────────────────────────────────┘
```

## 3. Route alternatives

```
┌──────────────────────────────────┐
│ ← Route                          │
├──────────────────────────────────┤
│              MAP                 │
│       ╭──────────────╮           │
│       │ route lines  │           │
│       ╰──────────────╯           │
├──────────────────────────────────┤
│ Route A                          │
│ 122 km · 2h 48m                  │
│ via Majalengka                   │
│ [ Selected ]                     │
│                                  │
│ Route B                          │
│ 136 km · 3h 05m                  │
│ via alternative                 │
│ [ Select ]                       │
├──────────────────────────────────┤
│ [ Continue Planning ]            │
└──────────────────────────────────┘
```

Avoid subjective route labels unless backed by defined criteria.

## 4. Ride Planner

```
┌──────────────────────────────────┐
│ ← Sunday Morning Ride       ⋮    │
├──────────────────────────────────┤
│              MAP                 │
│   Start ●────●────●────◎ Finish  │
├──────────────────────────────────┤
│ 122 km · 2h 48m · ETA 08:48      │
│                                  │
│ Start                            │
│ Cirebon                          │
│   │                              │
│   ├─ 54 km                       │
│   │                              │
│ ⛽ Fuel Stop                      │
│ SPBU ... · 15 min                │
│   │                              │
│   ├─ 68 km                       │
│   │                              │
│ ◎ Kuningan Regroup               │
│                                  │
│ [ + Add Stop ]                   │
│ [ Search Along Route ]           │
├──────────────────────────────────┤
│ Riders  ·  Briefing  ·  Publish  │
└──────────────────────────────────┘
```

## 5. Add Stop bottom sheet

```
┌──────────────────────────────────┐
│ Add Stop                         │
│ ───────────────────────────────  │
│ 🔎 Search a place                │
│ ⛽ Fuel                           │
│ 🍴 Food                           │
│ ☕ Rest                           │
│ 🏨 Hotel                          │
│ 📍 Pick on map                   │
│                                  │
│ [ Search Along Route ]           │
└──────────────────────────────────┘
```

## 6. Search Along Route

```
┌──────────────────────────────────┐
│ ← Fuel Along Route               │
├──────────────────────────────────┤
│              MAP                 │
│       route + result pins        │
├──────────────────────────────────┤
│ SPBU A                           │
│ +1.2 km · +4 min                 │
│ 62 km from current origin        │
│ [ Add Stop ]                     │
│                                  │
│ SPBU B                           │
│ +0.6 km · +3 min                 │
│ 79 km from current origin        │
│ [ Add Stop ]                     │
└──────────────────────────────────┘
```

Do not display detour numbers unless supplied or reliably computed.

## 7. Ride Briefing

```
┌──────────────────────────────────┐
│ ← Ride Briefing                  │
├──────────────────────────────────┤
│ Sunday Morning Ride              │
│ Cirebon → Kuningan               │
│                                  │
│ 122 km                           │
│ Departure 06:00                  │
│ Expected finish 08:48            │
│                                  │
│ Leader   Imad                    │
│ Sweeper  Rudi                    │
│                                  │
│ CHECKPOINTS                      │
│ 1. Fuel Stop                     │
│ 2. Kuningan Regroup              │
│                                  │
│ IMPORTANT                        │
│ [ leader notes ]                 │
│                                  │
│ ☑ I've read the briefing         │
└──────────────────────────────────┘
```

## 8. Pre-start

```
┌──────────────────────────────────┐
│ Sunday Morning Ride              │
│ Ready to Ride?                   │
├──────────────────────────────────┤
│ 12 / 14 Riders ready             │
│                                  │
│ ✓ Location permission            │
│ ✓ Background location            │
│ ! 2 Riders not ready             │
│                                  │
│ Next: Fuel Stop · 54 km          │
│                                  │
│ [ START RIDE ]                   │
└──────────────────────────────────┘
```

## 9. Active Ride — navigation-first

The map is the primary foreground once the Rider explicitly starts navigation
and tracking. Convoy context stays on the same surface rather than requiring a
second tracking dashboard.

```
┌──────────────────────────────────┐
│ Leader · 14 Rider · 13 Live      │
├──────────────────────────────────┤
│ ↱ Belok kanan ke Jl. Kartini     │
│   450 m              🚦 2 · baru │
├──────────────────────────────────┤
│                                  │
│        NAVIGATION MAP            │
│                                  │
│   route ━━━━━━━━━━━━━━━           │
│           ▲ Saya                 │
│    L ●        ● Rider            │
│                    ◌ stale       │
│          ⚠ roadworks             │
│                                  │
├──────────────────────────────────┤
│ Group Intercom · Mic Off         │
│ [ Mic ] [ Riders ] [ Track ] SOS │
└──────────────────────────────────┘
```

The traffic indicator includes freshness when traffic data is configured.
Traffic/provider degradation must not remove the accepted RoutePlan.

## 10. Active Ride — off-route recovery

Leaving the accepted route does not silently replace it.

```
┌──────────────────────────────────┐
│ Leader · 14 Rider · 13 Live      │
├──────────────────────────────────┤
│ ↰ Belok kiri menuju rute utama   │
│ Anda keluar rute · rejoin 700 m  │
│                 [ Cari rute baru ]│
├──────────────────────────────────┤
│                                  │
│        NAVIGATION MAP            │
│                                  │
│ accepted route ━━━━━━━━━━━        │
│                   ◎ rejoin       │
│              ╱                   │
│ recovery ━━━╯                    │
│       ▲ Saya                     │
│                                  │
├──────────────────────────────────┤
│ Group Intercom · Mic Off         │
│ [ Mic ] [ Riders ] [ Track ] SOS │
└──────────────────────────────────┘
```

The recovery line is shown only when a provider-computed drivable recovery route
exists. Provider failure keeps the accepted RoutePlan and rejoin target; it must
not draw a straight line and imply that it is a road.

**Cari rute baru** previews candidates. It never changes the shared RoutePlan
without explicit confirmation and the required Leader/Navigator authority.

Legend/state must use text/icon/freshness semantics, not color alone.

## 11. Convoy view

```
┌──────────────────────────────────┐
│ Convoy                           │
├──────────────────────────────────┤
│ LEADER                           │
│ Imad              Live           │
│  ↓ 180 m                         │
│ Andi              Live           │
│  ↓ 120 m                         │
│ Budi              Live           │
│                                  │
│ ⚠ GAP 1.4 km                     │
│                                  │
│ Haris             Live           │
│  ↓ 220 m                         │
│ Rudi · SWEEPER     Live           │
└──────────────────────────────────┘
```

If ordering confidence is low, replace this with grouped/list state rather than showing inaccurate distances.

## 12. Route / checkpoint view

```
┌──────────────────────────────────┐
│ Route                            │
├──────────────────────────────────┤
│ CURRENT SEGMENT                  │
│ Cirebon → Fuel Stop              │
│ 34 km remaining                  │
│ ETA 07:12                        │
│                                  │
│ ○ Start                          │
│ │                                │
│ ● Fuel Stop                      │
│   0 / 14 arrived                 │
│ │                                │
│ ◎ Kuningan Regroup               │
│   expected 08:48                 │
└──────────────────────────────────┘
```

## 13. Mandatory Regroup

```
┌──────────────────────────────────┐
│ REGROUPING                       │
│ Kuningan                         │
├──────────────────────────────────┤
│ 11 / 14 arrived                  │
│                                  │
│ ✓ Rider A                        │
│ ✓ Rider B                        │
│ …                                │
│ → Rider M · 3 min away           │
│ ◌ Rider N · stale 6 min          │
│                                  │
│ Leader only                      │
│ [ Release Group ]                │
└──────────────────────────────────┘
```

## 14. Quick Actions

```
┌──────────────────────────────────┐
│ Quick Action                     │
├──────────────────────────────────┤
│ 🛑 Saya Berhenti                 │
│ ↙ Saya Tertinggal                │
│ 🆘 Butuh Bantuan                 │
│                                  │
│ 🚨 SOS                           │
└──────────────────────────────────┘
```

SOS must be visually and interactionally distinct from ordinary actions.

## 15. Ride completed

```
┌──────────────────────────────────┐
│ Ride Completed                   │
├──────────────────────────────────┤
│ Sunday Morning Ride              │
│ 14 Riders                        │
│ 126 km actual                    │
│ 3h 08m                           │
│                                  │
│ [ route recap map ]              │
│                                  │
│ 2 Checkpoints                    │
│ 1 reported stop                  │
│                                  │
│ [ View Recap ]                   │
│ [ Share to Club ]                │
└──────────────────────────────────┘
```

## 16. Club profile

```
┌──────────────────────────────────┐
│ [ Banner ]                       │
│  ◉ Cirebon Riders                │
│  Cirebon                         │
│  84 Riders                       │
│  [ Follow ]                      │
├──────────────────────────────────┤
│ Overview Rides Posts Members     │
├──────────────────────────────────┤
│ UPCOMING                         │
│ Sunday Morning Ride              │
│                                  │
│ RECENT                           │
│ Pangandaran Ride recap           │
│                                  │
│ ACHIEVEMENTS                     │
│ [ badge ] [ badge ]              │
└──────────────────────────────────┘
```

## 17. Rider profile

```
┌──────────────────────────────────┐
│ Rider Profile                    │
├──────────────────────────────────┤
│ ◉ Imad                           │
│ @callsign                        │
│ Level 4                          │
│                                  │
│ Clubs                            │
│ Cirebon Riders                   │
│                                  │
│ Vehicles                         │
│ Honda ...                        │
│                                  │
│ Badges                           │
│ [First Ride] [Sweeper] [...]     │
│                                  │
│ Ride History                     │
└──────────────────────────────────┘
```

Level should not dominate the profile.

## 18. Visual hierarchy notes

- Signal Orange is for attention and interaction, not full-screen dominance.
- Active Ride should feel operational and calm.
- Critical SOS state must be more explicit than ordinary Signal Orange.
- Map should be visually subordinate to actionable Ride information when necessary.
- Cards should be simple, with limited shadow and clear separation.
- Avoid racing dashboards, speedometer metaphors, military terminology, or game HUD styling.


## 19. Active Ride Navigation Command Center — superseding direction

This section supersedes the earlier split Overview/Map-first Active Ride layout
when embedded navigation is enabled.

```
┌──────────────────────────────────┐
│  800 m   ↱ Jl. Siliwangi        │
│  Leader · 9 Rider · 1 attention  │
├──────────────────────────────────┤
│                                  │
│       TURN-BY-TURN MAP           │
│                                  │
│      L●   ●     ●N               │
│              ◌ stale             │
│                         S●       │
│                                  │
│   42 km · ETA 09:18   [recenter] │
├──────────────────────────────────┤
│ 🎙 MIC ON   🔊 GROUP   👥 RIDERS │
│                                  │
│ [  Leader broadcast / alert  ]   │
│                         [ SOS ]   │
└──────────────────────────────────┘
```

The map is the main operational surface, not a decorative preview. CommRide
presence overlays must never obscure the current maneuver. Detailed roster,
Route, Checkpoints, text Comms and settings open as secondary sheets/screens.

Default voice state is Group Intercom. PTT is optional. SOS requires deliberate
activation and remains visually distinct.
