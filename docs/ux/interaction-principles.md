# CommRide Interaction Principles v0.1

Status: Draft  
Date: 18 September 2026

## 1. Familiar first

Route planning should use patterns users already understand from mainstream maps.

Do not invent a new interaction for:
- search destination;
- choose route;
- Add Stop;
- reorder Stop;
- Search Along Route;
- recenter map;
- Navigate.

Innovation belongs in group coordination, not unnecessary novelty.

## 2. One primary task per screen

Especially during planning:
- choose destination;
- choose route;
- add a stop;
- assign Riders;
- read briefing.

Avoid forms containing every advanced Ride option at once.

## 3. Active Ride = low cognitive load

A Rider may glance at the phone briefly.

Prioritize:
- next checkpoint;
- group state;
- important alerts;
- large tap targets;
- obvious status.

Move secondary analytics out of the primary Active Ride screen.

## 4. Show freshness everywhere location matters

A coordinate without time context is dangerous.

Always distinguish:
- Live;
- Stale;
- Offline;
- GPS unavailable.

Last-known location should include age/timestamp semantics.

## 5. Do not create false precision

Avoid presenting:
- exact convoy order when uncertain;
- exact gap if GPS quality is poor;
- precise ETA if routing data is stale;
- “safe” claims without defined criteria.

Communicate uncertainty in the UI.

## 6. Operational events beat chat

For common Ride situations, structured actions are preferred over typing.

Examples:
- I'm Stopping;
- I'm Left Behind;
- Need Help;
- SOS;
- Arrived;
- Regroup released.

Chat remains useful but should not be required for everything.

## 7. Leader controls should be powerful but explicit

Leader-only actions:
- Start Ride;
- End Ride;
- change active route;
- release Mandatory Regroup;
- Leader broadcast.

Actions that affect the whole Ride should be clearly labeled and, where appropriate, confirmed.

## 8. Social is ambient, not intrusive

Feed activity should not interrupt Active Ride coordination.

While Active Ride is foregrounded:
- suppress low-priority social notifications;
- prioritize Ride operational notifications;
- avoid feed entry animations/badges that compete for attention.

## 9. Safety over engagement

CommRide should never encourage unsafe phone interaction while moving.

Design direction:
- minimize taps;
- support quick glance;
- consider voice/audio cues later;
- avoid long-form interaction while Ride is active;
- do not reward speed or aggressive riding.

## 10. Orange means signal

Signal Orange `#FF6A1A` should indicate:
- selected/high-priority actions;
- checkpoint;
- incoming operational attention;
- Ride state accents.

If everything is orange, nothing is a signal.

## 11. SOS is not just another orange button

SOS needs a distinct critical treatment and deliberate activation.

It should:
- resist accidental taps;
- send immediately after confirmation;
- show sent/received state;
- remain visible until resolved;
- not falsely imply public emergency services were contacted.

## 12. Permission requests must be contextual

Do not ask for background location on first app launch.

Request permissions when:
- joining an Active Ride;
- starting a Ride;
- enabling tracking.

Explain:
- why needed;
- when used;
- when tracking stops.

## 13. Preserve user trust during failure

If routing fails:
- keep previous valid route.

If realtime fails:
- keep last known positions and mark stale.

If external Places search fails:
- do not corrupt the Ride plan.

Failure should degrade functionality, not silently fabricate state.

## 14. Group-first, not Leader-centric

Leader is operationally important, but the product should not treat Leader location as the only truth.

Future convoy logic should consider:
- Sweeper;
- subgroup gaps;
- Riders between Leader and Sweeper;
- checkpoint progress.

## 15. Default simple, advanced available

Most users should be able to create a Ride with:
- start;
- destination;
- date/time;
- Riders.

Advanced controls:
- shortest fuel range;
- rest intervals;
- route constraints;
- optional Stops;
- Plan B;

should be available progressively.

## 16. Explain consequences before expensive or disruptive actions

Examples:
- adding a Stop changes ETA;
- changing route during Active Ride affects all Riders;
- ending Ride stops live tracking;
- publishing a public Ride changes visibility.

## 17. Accessibility is operational reliability

Accessible UI is not cosmetic.

Use:
- readable type;
- large controls;
- text + icon state;
- adequate contrast;
- non-color-only alerts;
- consistent placement.

## 18. Product tone

CommRide language should be:
- concise;
- calm;
- confident;
- rider-aware;
- non-militaristic;
- non-gamified during critical operations.

Examples:
- “Rudi location stale for 6 min”
- “3 Riders not yet at checkpoint”
- “Group released”
- “Need Help sent to Leader and Sweeper”

Avoid:
- “Target lost”
- “Mission”
- “Enemy”
- exaggerated danger language.
