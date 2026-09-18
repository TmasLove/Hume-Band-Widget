# Hume Relay — iPhone companion

Reads your Hume Band data out of **Apple Health** on the phone and sends it
to HumeWidgets on your Mac over your own Wi-Fi.

## Why this route

HealthKit does not exist on macOS, so the Mac cannot read your Health data
itself. And the band's Bluetooth profile is proprietary — it advertises
`FFF0` and `190E` with vendor characteristics and no standard Heart Rate
service, so there is nothing documented to ask it for.

HealthKit is Apple's API, not Hume's. Your band writes into it, so reading
your own readings back needs no vendor account, key or permission. It also
carries **sleep stages and HRV**, which direct Bluetooth never would —
those are computed in Hume's app, not streamed from the wrist.

## Installing it on your phone

This cannot be installed for you; it needs Xcode deploying to your device.

1. `open HumeCompanion.xcodeproj`
2. Plug the iPhone in and pick it as the run destination
3. Press Run. Xcode registers the device against your Apple Developer team and
   creates the profile automatically
4. On the phone, if prompted: **Settings › General › VPN & Device
   Management** → trust the developer

## Using it

1. On the Mac: **HumeWidgets › Settings › iPhone › Start receiving**. Note
   the six-digit pairing code.
2. On the phone: **Allow Health access**, **Find my Mac**, type the code,
   then **Send my latest readings**.

## What it sends, and what it does not

| Metric | Source |
|---|---|
| Heart rate, resting heart rate | HealthKit, measured |
| HRV (SDNN) | HealthKit, measured |
| Wrist temperature | HealthKit `appleSleepingWristTemperature`, measured |
| Sleep stages, bedtime, wake | HealthKit `sleepAnalysis`, measured |
| Activity | Derived from today's step count against a 10,000-step day |
| Sleep quality score, sleep debt | **Derived here.** Hume computes their own score in their app and does not publish it to Health, so this is an approximation from duration, deep share and continuity — not their number. |
| **Stress** | **Not sent.** No HealthKit type carries it. The Mac keeps showing a simulated value for stress until we find a real source. |

Sleep stages map onto Apple's `HKCategoryValueSleepAnalysis`:
`asleepDeep → Deep`, `asleepREM → REM`, `asleepCore` and
`asleepUnspecified → Light`, `awake → Awake`. `inBed` is deliberately
ignored — it brackets the whole night and would double-count against the
stage samples inside it.

## Wire format

One JSON object per line over TCP, found via Bonjour `_humeband._tcp`. The
Mac accepts **private network addresses only** (loopback, 10/8, 192.168/16,
172.16–31, link-local) and checks the pairing code before reading the
payload.

`RelayProtocol.swift` and the model types are shared with the Mac app **by
reference**, not copied, so the two ends cannot drift apart.

## Verified

- Mac relay tested over real sockets: valid accepted, wrong code rejected,
  malformed rejected, payloads split across TCP packets reassembled, two
  readings in one write both handled
- 27 unit tests on merge semantics and the private-address guard
- Bonjour advertisement confirmed discoverable with `dns-sd -B _humeband._tcp`
- Sleep-stage mapping checked against Apple's enum in the iOS SDK

**Not yet verified:** the HealthKit read itself and a real phone-to-Mac
send. Both need the app on a physical iPhone with Hume data in Health.
