# Health data: how it works and what users need to set up

Internal reference for how Mytr.AI gets steps/heart-rate/HRV/sleep data onto a
user's device, and what has to be true on their phone/watch for each metric
to actually show up. Written to later be distilled into in-app setup copy
(onboarding wearables screen, Connect your device screen) — not itself
user-facing yet.

## 1. The core model: we don't measure anything ourselves

Mytr.AI never talks to a watch, a sensor, or a fitness-tracking service
directly. On both platforms we read from one on-device aggregator that some
*other* app has already written data into:

- **Android:** [Health Connect](https://developer.android.com/health-and-fitness/guides/health-connect)
  — a shared data store built into the OS (Android 14+) or installed as a
  separate app (Android <14).
- **iOS:** Apple's **Health** app (HealthKit).

All the read/request logic lives in one place:
[`frontend/lib/core/services/health_service.dart`](../frontend/lib/core/services/health_service.dart),
via the `health` Flutter package.

This means: **if no source app is writing a given metric into Health
Connect/Health, granting Mytr.AI every permission in the world still shows
"no data."** Permissions control whether we're *allowed* to read a record
type — they don't make the record type exist.

## 2. What each metric actually needs

| Metric | Phone alone (no watch)? | What's required |
|---|---|---|
| Steps | ✅ Works | Phone's own accelerometer; Health Connect/Health can source this directly. |
| Active calories | ✅ Works (estimate) | Derived from steps/motion on-phone. |
| Heart rate (current) | ❌ No | A device with a continuous PPG sensor — a watch or band. |
| Resting heart rate | ❌ No | Same as above, needs multi-hour/overnight wear. |
| HRV | ❌ No | PPG sensor at rest, almost always computed overnight during sleep. |
| Sleep stages (light/deep/REM) | ❌ No, or coarse at best | A watch/band worn overnight. Phone-only "sleep" trackers can guess *time asleep* from motion + screen-off, never real stages. |

So: steps work out of the box for every user. Everything else requires a
wearable whose companion app is configured to sync into Health
Connect/Health — the watch being *paired to the phone* is necessary but not
sufficient.

## 3. HRV vs. heart rate — not the same signal

- **Heart rate** = current pulse, beats per minute.
- **HRV** = variability in the *time gaps between* successive heartbeats — a
  distinct signal used as an autonomic-nervous-system/recovery proxy, not
  derivable from a plain BPM reading.

We request them as separate `HealthDataType`s
([`health_service.dart:59-61`](../frontend/lib/core/services/health_service.dart)).
The two platforms also measure HRV differently — HealthKit reports **SDNN**,
Health Connect reports **RMSSD** — these are different statistics over the
same underlying heartbeats, with no clean conversion. We ingest both under
one backend "hrv" metric; a user switching from iPhone to Android (or vice
versa) will see a discontinuity in their HRV trend that isn't a real
physiological change. Known simplification, not a bug.

## 4. Setup chain, per platform

### Android + Pixel Watch (Fitbit-based)

1. **Google account** — pair the watch to the phone via the **Pixel Watch**
   app. Any Google account; this only governs watch-level pairing
   (notifications, complications), not health data.
2. **Fitbit account** — Pixel Watch's on-wrist health tracking (heart rate,
   HRV, sleep) runs on Fitbit, not raw Health Connect. During watch setup
   you're prompted to sign into Fitbit (a Google account works as the
   Fitbit login, or use an existing Fitbit account).
3. **Fitbit app on the phone**, signed into the *same* Fitbit account as the
   watch.
4. **Fitbit app → Settings → Health Connect → enable syncing.** This is the
   step users will most often miss: Fitbit tracks everything internally but
   keeps it siloed inside its own app until this toggle is turned on. Skip
   it and Health Connect stays empty regardless of how well the watch is
   paired.
5. Wear the watch normally. HR updates quickly; HRV/sleep populate after a
   full night's sleep with the watch worn.

Other Android wearables follow the same shape, just with a different
companion app in step 2–4 (Galaxy Watch → Samsung Health, Mi/Amazfit →
Zepp, Oura, etc.) — any app that can write into Health Connect works, it
does not have to be a Pixel Watch or Fitbit specifically.

### Android 14+ note (platform requirement, not a user step)

On Android 14+, Health Connect is built into the OS rather than a separate
Play Store app, and it requires the app requesting permissions to declare a
specific `activity-alias` in its manifest
(`ViewPermissionUsageActivity`, see
[`AndroidManifest.xml`](../frontend/android/app/src/main/AndroidManifest.xml))
or it refuses to show the permission screen at all — surfaced to the user as
"Mytr.AI needs to be updated to sync with Health Connect." This is already
fixed in the app itself; noted here only because it explains why older
builds could fail this whole flow regardless of anything the user did.

### iOS + Apple Watch

1. Pair the Apple Watch via the **Watch** app, signed into the user's Apple
   ID (no separate fitness-account step — HealthKit is first-party).
2. Wear the watch; Apple Watch writes heart rate, HRV (SDNN), and sleep
   directly into Health with no extra sync toggle required.
3. First time Mytr.AI requests permissions, iOS shows its native Health
   access sheet — user must switch on the specific data types (steps, heart
   rate, HRV, sleep, etc.), not just tap "Allow" once for everything.

## 5. In-app permission flow (for context)

- `HealthService.instance.configure()` is called once at app startup
  ([`main.dart`](../frontend/lib/main.dart)) — required before any
  permission request on Android (registering the permission launcher after
  the Activity has started silently fails).
- Tapping "Connect" (onboarding wearables tile, or Profile → Manage
  Devices) calls `requestPermissions()`, which shows the OS-native
  permission screen (Health Connect's own UI on Android, Apple's Health
  sheet on iOS).
- `isAuthorized()` is used passively (e.g. on screen load) to reflect
  current status without prompting.
- On resume, `HealthSyncService.sync()` fires automatically
  ([`main.dart`](../frontend/lib/main.dart), `didChangeAppLifecycleState`)
  — no manual "sync now" action needed once connected.

## 6. Troubleshooting checklist (for support / future in-app copy)

1. **"Needs to be updated" message from Health Connect** → app-side manifest
   issue, already fixed; if it recurs, check for the `activity-alias` in
   the Android manifest.
2. **Permission screen never appears at all** → confirm Health Connect (or
   the separate Health Connect app, on older Android) is installed.
3. **Permission granted but a specific metric stays empty** → the source
   app (Fitbit/Samsung Health/etc.) most likely isn't syncing that record
   type into Health Connect yet. Check Health Connect's own **App
   permissions** screen: the source app should be listed as a data
   *writer* for that type, and Mytr.AI as a data *reader*.
4. **HRV/sleep specifically empty, steps/HR fine** → likely just needs a
   full night of watch wear; these are computed overnight, not instantly.
5. **Works on Android, same watch shows nothing after switching to
   iPhone (or vice versa)** → expected; wearable data doesn't migrate
   across ecosystems, and HRV in particular will show a trend
   discontinuity (see §3).
