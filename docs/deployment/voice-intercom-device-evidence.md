# Voice Intercom — Setup and Device Evidence

Decision: `docs/voice-intercom-decision-2026-10-16.md`.

Nothing below is recorded yet. Repository PASS (CI) does not count as any of
these gates.

## 1. Provider setup (operator, needs approval)

1. Cloudflare dashboard → Realtime → RealtimeKit → create app
   `CommRide Pilot`. Note the App ID.
2. In that app create two presets, audio only (video and screen share off,
   recording off, chat off):
   - `commride_rider` — may publish audio;
   - `commride_leader` — same, plus host permission "disable participant
     audio".
3. Create an API token with **Realtime Admin** for this account only.
4. Apply migration `0012_ride_intercom.sql` to the pilot D1 database.
5. Worker configuration:
   - `REALTIMEKIT_ACCOUNT_ID`, `REALTIMEKIT_APP_ID` as vars;
   - `wrangler secret put REALTIMEKIT_API_TOKEN`.
6. Deploy the Worker. Check that an Active Ride participant gets `200` from
   `POST /v1/rides/{rideId}/intercom/token` and a non-member gets `403`.

Provider PASS: record date, Worker version, one successful token response
(token redacted) and the RealtimeKit dashboard session that appeared.

## 2. Device PASS (two phones, one Active Ride)

Build with `COMMRIDE_VOICE_INTERCOM_ENABLED=true`. Phone A = Redmi 8
(LineageOS, Android 16), phone B = any second Android phone. One is the Ride
Leader.

| # | Check | A | B |
|---|---|---|---|
| 1 | Starting navigation joins listening; row shows "Mendengar"; no mic icon in the status bar | | |
| 2 | First mic tap asks for microphone permission once, then "Mic menyala" | | |
| 3 | B hears A and A hears B; speaker name shows on the other phone | | |
| 4 | Screen locked: voice still both ways; "Interkom Ride aktif" notification shown | | |
| 5 | Music app playing: music keeps playing, music row still works, voice audible | | |
| 6 | Bluetooth helmet headset: voice in/out via headset (note headset model and music quality) | | |
| 7 | Tap untuk bicara: tap, speak, tap again; turn ends by itself after 30 s | | |
| 8 | Leader mutes Rider: Rider sees "Mic dimatikan Ketua", nobody hears them; Rider's own tap turns it back on | | |
| 9 | Mobile data off 10 s then on: row shows weak signal, then recovers without re-tapping | | |
| 10 | End Ride / leave riding screen: room left, notification gone, mic indicator gone | | |
| 11 | Data used per hour (Android data usage for CommRide) | | |

Record for each run: date, build commit, phones and Android versions, headset
model, network operator, result per row, and any audio-quality notes.
