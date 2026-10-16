# Voice Intercom — Setup and Device Evidence

Decision: `docs/voice-intercom-decision-2026-10-16.md`.

Repository PASS (CI) does not count as any of these gates.

## Log

- 2026-10-16 — LiveKit Cloud project `CommRide Pilot` (Build plan, project
  `p_3wniesihmus`, data region United States) created by the product owner;
  `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` stored as Worker
  secrets (names verified, values not read).
- 2026-10-16 — Worker `commride-api` deployed from `feat/voice-intercom`
  `8a8850c` with owner approval (includes the unmerged stack #81–#85). Version
  `5e6283d4-4e08-4b33-a6e8-bfefe5d872ad`; previous version
  `8dd2d595-7b2d-4637-be5a-a684d449f7fe` (rollback target). Remote D1 had no
  pending migrations. `/health` ok; unauthenticated intercom token request
  answers `401 authentication_required` (endpoint live, secrets present).
  Provider PASS still open: no real join token minted yet.

## 1. Provider setup (operator, needs approval)

1. Sign in at <https://cloud.livekit.io> and create a project named
   `CommRide Pilot` on the free **Build** plan.
2. Project settings → note the **WebSocket URL** (`wss://<project>.livekit.cloud`).
3. Project settings → **API keys** → create a key named `commride-worker`.
   Copy the **API key** and the **API secret** (the secret is shown once).
   Never put them in the app, in `pilot-defines.local.json` or in git.
4. Keep recording/egress, SIP, agents and other add-ons off.
5. Store the three values as Worker secrets (each command asks for the value):

   ```bash
   cd services/api
   npx wrangler secret put LIVEKIT_URL
   npx wrangler secret put LIVEKIT_API_KEY
   npx wrangler secret put LIVEKIT_API_SECRET
   ```

6. Deploy the Worker (`npx wrangler deploy`), then check that an Active Ride
   participant gets `200` from `POST /v1/rides/{rideId}/intercom/token` and a
   non-member gets `403`. No D1 migration is needed for the intercom.

Provider PASS: record date, Worker version, one successful token response
(token redacted) and the room that appeared in the LiveKit Cloud dashboard.
Check the dashboard usage page after each test Ride against the 5,000 free
participant-minutes per month.

## 2. Device PASS (two phones, one Active Ride)

Build with `COMMRIDE_VOICE_INTERCOM_ENABLED=true`. Phone A = Redmi 8
(LineageOS, Android 16), phone B = any second Android phone. One is the Ride
Leader.

| # | Check | A | B |
|---|---|---|---|
| 1 | Starting navigation joins listening; row shows "Mendengar"; no mic indicator in the status bar | | |
| 2 | First mic tap asks for microphone permission once, then "Mic menyala" | | |
| 3 | B hears A and A hears B; speaker name shows on the other phone | | |
| 4 | Screen locked: voice still both ways; "Interkom Ride aktif" notification shown | | |
| 5 | Music app playing: music keeps playing, music row still works, voice audible | | |
| 6 | Bluetooth helmet headset: voice in/out via headset (note headset model, music quality, any Nearby devices prompt) | | |
| 7 | Tap untuk bicara: tap, speak, tap again; turn ends by itself after 30 s | | |
| 8 | Bisukan untuk saya: A silences B only for A; others still hear B | | |
| 9 | Leader mutes Rider: Rider sees "Mic dimatikan Ketua", nobody hears them; Rider's own tap turns it back on | | |
| 10 | Mobile data off 10 s then on: row shows weak signal, then recovers without re-tapping | | |
| 11 | End Ride / leave riding screen: room left, notification gone, mic indicator gone | | |
| 12 | Data used per hour (Android data usage for CommRide) | | |

Record for each run: date, build commit, phones and Android versions, headset
model, network operator, result per row, and any audio-quality notes.
