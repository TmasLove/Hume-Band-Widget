# Hume Band 2.0 — macOS widget + dashboard

A WidgetKit widget and companion SwiftUI app showing heart rate, stress, skin
temperature and activity from a Hume Band 2.0. Band data is currently
simulated; the transport is behind a protocol so swapping in the real API is a
one-line change.

Built against the **macOS 27 SDK (Xcode 27)**, deployment target **macOS 27.0**,
and run on a macOS 27 host.

## About the 10-second refresh

**A widget cannot fetch new data every 10 seconds, and no code can make it.**
macOS gives each widget a background budget of roughly a few dozen refreshes a
day. Requesting one every 10s would be ~8,600/day; the system would simply
refuse and the widget would sit stale.

What this project does instead:

| Where | Cadence | How |
|---|---|---|
| App dashboard | Genuinely every 10s | Real polling, torn down when the app backgrounds |
| Widget display | Steps every 10s | One fetch produces a 180-entry timeline spaced 10s apart; WidgetKit swaps pre-rendered entries in without waking the extension |
| Widget data | On real change | App calls `WidgetCenter.reloadTimelines`, which does not spend the background budget |

So the widget *moves* every 10 seconds at no energy cost, and gets *new* data
whenever the app has some. One timeline covers 30 minutes (~48 refreshes/day),
which sits inside the budget with headroom.

The 180-entry timeline was verified to be accepted by WidgetKit (`timeline
returning 180 entries`, no reload error) during the iOS bring-up of this same
provider code. Whether the OS renders every single 10-second step or coalesces
some was **not** verified on macOS — that needs a long observation with the
widget actually placed in Notification Center.

## Battery and performance

- The extension holds no state between renders: read cache, draw, exit.
- One network call per timeline, not one per entry.
- Polling stops on `scenePhase == .background` and on `onDisappear`. On macOS
  `.inactive` only means "window not frontmost", which happens constantly, so
  stopping there would thrash the timer rather than save power.
- Timeline entries are pre-reduced to display-ready `MetricReading` values, so
  view bodies do no arithmetic, date maths or formatting during render.
- Cache writes are atomic, so a render mid-write never sees a partial file.
- A failed fetch falls back to the last good reading rather than an error card.

## Layout

```
Shared/         # compiled into BOTH targets
  HumeMetrics.swift      model
  MetricZone.swift       green/yellow/red banding + per-metric thresholds
  HumeBandService.swift  protocol, mock transport, live transport
  MetricsStore.swift     App Group cache (app writes, widget reads)
  RefreshPolicy.swift    the cadence/budget constants
  HumeIntents.swift      configuration, refresh and collapse intents
  BandScanner.swift      diagnostic CoreBluetooth scan
  Palette.swift          Codenotch-derived palette, Design scale, Motion
  ZoneBar.swift          ring, bar, row and card components
  Assets.xcassets        app icon + accent
HumeApp/        # dashboard, deep-link handling
HumeWidget/     # provider, family views, widget bundle
```

## Visual language

Adapted from **[Codenotch](https://github.com/vinzdg/codenotch)** (MIT), a macOS
app by vinzdg, so the two read as siblings on the same desktop. Extracted from
its `Sources/DesignSystem` rather than eyeballed:

- **The three-state ramp**, reused directly as the zone colours:
  `ample #00FF88/#00A356`, `watch #F2FF00/#B08800`, `critical #FF3F00`.
- **The ring**: a *wide dim track* with a *thinner bright arc* riding inside it
  (`trackStroke` 15.5px vs `progressStroke` 8px in frame units). The stroke
  difference is the whole character of the mark — equal widths read as an
  ordinary progress ring.
- **Translucent tracks**, white/black at low alpha rather than a fixed grey, so
  a track darkens what is behind it instead of looking painted on.
- **Proportional layout.** Every number is a ratio measured off Codenotch's
  design frame, and one anchor picks the scale. Codenotch has a single global
  `Design.scale`; this app draws the same object at two very different sizes,
  so `Design` is a struct — `Design.dashboard` (112pt ring) and `Design.widget`
  (58pt ring). Change the anchor and type, strokes, padding and corners all
  move together.
- **Motion**: `Motion.reading` is Codenotch's `spring(response: 0.9,
  dampingFraction: 0.9)` — slow and heavily damped, so a number changing every
  ten seconds settles instead of bouncing.

### The one deliberate deviation

Codenotch's `card` is pure black unconditionally, because its notch *is* a
bezel and its solid style pins the panel to `darkAqua` so white ink stays
white. A window and a widget cannot pin the appearance. A black card in Light
Appearance draws black `textPrimary` and a black-translucent track onto black —
the numbers and the ring tracks disappear completely. (This was not theoretical:
the first light-mode render came back with every value missing.) So `card`
adapts, and stays pure black in dark mode, which is where the identity lives.
Codenotch makes the same concession for its glass style, for the same reason.

## Collapsing, and pinning to the desktop

The widget has a chevron in its corner. Tapping it folds the whole thing down
to four icon rings — glyph plus zone colour plus a progress arc, no numbers,
no labels. Tapping again unfolds it. The state lives in the App Group, so it
survives relaunch and every placed instance agrees.

The layout adapts with `ViewThatFits` rather than branching on
`widgetFamily`: it offers the four rings in a row and falls back to a 2×2
block when the tile is too narrow. A small tile therefore folds to a square of
icons instead of clipping them, and any future tile size is handled without a
code change.

**One real constraint.** A WidgetKit widget cannot resize itself. The family
is chosen by the person placing it and the extension has no say — so
"collapsed" changes what is *drawn inside* the tile, not the tile's footprint.
There is no API that would change this.

**Pinning to the desktop already works** and needs no code: open Notification
Center, click Edit Widgets, then drag the Hume Band widget onto the desktop.
macOS keeps it there. Collapse it once it is placed and it sits as a quiet row
of icons.

If you want something that genuinely shrinks its footprint — a floating panel
that pins to a screen edge and folds to a pill, the way Codenotch itself
behaves — that is an `NSPanel` in the app rather than a WidgetKit widget. Not
built here; see the note at the end.

## The floating desktop panel

A second surface, separate from the WidgetKit widget, for the case a widget
cannot serve: something that genuinely shrinks. **Settings › Desktop panel**
turns it on and picks an edge; right-clicking the panel does the same.

It rests as a small pill welded to a screen edge showing four zone rings, and
unfolds into a full readout when you point at it. Click opens the dashboard.

The `NSPanel` configuration is lifted from Codenotch's `NotchPanel`, because
it is the combination that actually works:

```swift
styleMask         = [.borderless, .nonactivatingPanel]
level             = .statusBar          // above the menu bar
collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
isOpaque = false; backgroundColor = .clear; hasShadow = false
hidesOnDeactivate = false
canBecomeKey = false; canBecomeMain = false
```

`.nonactivatingPanel` is the important one: glancing at your heart rate must
never pull focus from what you were doing, and an ordinary window would.
Clicks and the context menu are handled in `sendEvent`/`mouseDown` on the
panel rather than on the content view, because the hosting view's hit test
resolves to a SwiftUI subview that may swallow the event first.

The panel keeps a **fixed frame** sized for its expanded form, with the
content aligned to the bezel and nothing drawn elsewhere — SwiftUI hit
testing returns nil over the empty region, so clicks fall through to whatever
is behind. Folding is therefore an animation inside a stable window rather
than a window-server resize, which would be visibly steppy.

It is on the first launch only. A window that floats above everything should
never reappear uninvited once you have turned it off.

## Sleep

**Vitals** and **Sleep** are real tabs in the app window. In the widget they
are *pages*: a widget has no tab bar, only `AppIntent` buttons, so the header
carries a control that steps between them. The choice persists in the App
Group.

### Following Hume's own vocabulary

The metrics and their definitions come from Hume Health's published
[Sleep Architecture Metrics](https://humehealth.com/blogs/hume-blogs/comprehensive-hume-band-metrics-catalog),
not from Apple's Health app. Three differences that actually matter:

- Hume says **Light**, where Apple says "Core".
- Hume leads with stage **percentages**, not bare durations.
- **Deep, REM and Light are shares of total sleep, while Awake is a share of
  the whole sleep period.** Different denominators, so they do not sum to
  100. `SleepSummary.percentage(_:)` encodes that rather than flattening it.

Also carried over: **Sleep Quality Score** (the composite Hume leads with,
and what the zone bands on), **Sleep Debt**, and their definition of
**resting heart rate and HRV as measured during deep sleep** specifically.

Each stage carries the recovery function Hume attaches to it — Deep is
physical recovery, REM cognitive, Light transitional, Awake fragmentation —
so the breakdown says what the number is *for*.

### Expanding the timeline

The **Expand** control above the hypnogram is not just a bigger version of
the same chart — expanded it gains hour gridlines, a real time-of-night axis,
and each stage's total in the lane label, in that stage's colour. Collapsed
it stays a glance; expanded it is something you can actually read a night
off.

Tapping the widget's **sleep** page lands on the sleep tab with the timeline
already expanded (`humeband://dashboard?tab=sleep&graph=expanded`). Tapping a
chart too small to read should hand you the big one, not the dashboard's
front page.

### Widget chrome

The three widget controls — refresh, switch page, collapse — are glyphs on
filled circles. They were bare grey glyphs, which on a black card read as
decoration rather than as something pressable; the collapse chevron in
particular was effectively invisible. Collapse is drawn **prominent** (filled
with the primary colour, inverted glyph) because it is the one control that
should always be findable, and it keeps the same corner in both the expanded
and collapsed states so it never moves under the pointer.

### Layout

The breakdown is a **row per stage**, not a grid of cells. The first attempt
used a four-column grid at the dashboard's own type scale, and in a 460pt
window it truncated every figure to an ellipsis and broke "AWAKE" across
three lines one letter at a time. Two fixes, both worth keeping:

- The sleep section has **its own `Design` anchor** (62pt ring ≈ 13pt body).
  Inheriting the dashboard's 112pt-ring anchor put body text at 24pt and the
  headline near 53pt.
- The widget picks its layout with `ViewThatFits` across four rungs — full,
  no-details, four-column-no-times, and a two-column compact — so a wide-but-
  short tile still gets four columns instead of dropping straight to two.

### Two forms of the same night

**`SleepTimelineTrack`** — one rounded rail, each stage a coloured band at its
**real time position**. Stage is carried by colour, time by position, no
lanes. This is the compact form: the widget and the collapsed app card use
it, because the lane hypnogram needs height they do not have, and the stacked
proportional bar it used to fall back to threw away the one thing worth
knowing — *when*. A 3am waking and a waking at the very end of the night are
the same stacked bar and obviously different here.

Bands carry a hairline gap. Butted together, a night with twenty-odd
transitions reads as a barcode; the gap turns it into distinct blocks. The
form is the conventional one for sleep tracking, and the specific layout —
rail, four clock ticks beneath, then a row of figures with the value above a
dotted label — follows widget designs on Dribbble that Tomas collected as
reference.

**`SleepHypnogram`** — the four-lane version, for the expanded app view where
there is height to spend. Expanding swaps one for the other.

### The hypnogram, and stage colour

The chart is a **hypnogram** — four lanes, shallowest at the top, one rounded
bar per continuous stretch of a stage. A stacked proportional bar can say
*how much* deep sleep you got; only this shows that all of it happened before
2am. `intervals` is the single source of truth and every total, percentage
and clock time is derived from it, so the chart and the figures cannot drift
apart. The mock night is built as real architecture rather than noise:
~90-minute cycles, deep concentrated early and fading, REM lengthening toward
morning, brief awakenings between cycles.

Stages have **their own night-time colour family** — violet, blue, teal,
amber — deliberately not the green/amber/red zone ramp, which means *health
state*. Reusing it for "REM" would be a false signal.

Those four values were not chosen by eye, twice over. A constrained search
across hue bands maximised worst-case CIELAB ΔE under normal, protan, deutan
and tritan vision subject to 3:1 contrast:

| Stage palette | worst-case ΔE |
|---|---|
| Apple-Health-style indigo / blue / cyan / orange | **7.5** |
| Hand-tuned "prettier" violet / blue / mint / amber | **6.0** |
| Search result (shipped) | **45.9 dark, 41.6 light** |

The first two look fine to me and are near-useless to a dichromat, because
their three cool hues sit at almost the same lightness. Hue alone does not
separate; hue plus lightness does. Classic and High separation share the
shipped values, since they already are the maximum-separation result.
Monochrome drops to a lightness ramp, where hue cannot exist, and the lane
labels carry the rest.

**This sleep data is invented**, like everything else here — see below. It is
generated from the calendar day so "last night" stays put instead of drifting
under you every ten seconds.

## Liquid Glass

macOS 27's glass material, verified against the SDK before use — the full API
(`GlassEffectContainer`, `.glassEffect(.regular.tint().interactive(), in:)`,
`.glassEffectID`, `.buttonStyle(.glass)`) compiles at our deployment target.

**Where it is, and where it deliberately is not:**

| Surface | Treatment | Why |
|---|---|---|
| Floating panel | `GlassEffectContainer`, interactive glass, pill morphs into the card via `glassEffectID` | It floats over the desktop, so there is real content behind it to refract. This is the surface glass was made for. |
| App cards & buttons | `GlassCard`, `.buttonStyle(.glass)` / `.glassProminent` | Glass over the window background — subtler, but it is where the controls live. |
| **Widget** | **No glass** — keeps the pure-black Codenotch card | A widget is a rendered snapshot the system composites. There is nothing live behind it to refract, so `glassEffect` costs the blur and returns a flat grey. |

Every glass surface falls back to the solid card under **Reduce
Transparency**. That is an accessibility setting, not a style preference,
which is why `Palette.card` still exists.

`ImageRenderer` cannot draw the material — in a cold process it paints
`glassEffect` as nothing at all — so the static renders in this repo show the
fallback surface. Glass has to be judged in the running app. (Codenotch
documents the same limitation in its own pixel tests.)

## The night backdrop

The sleep page sits on a slow aurora — three heavily blurred ellipses in the
deep / light / REM stage hues, drifting over 26 seconds. Two reasons, neither
decorative:

- It gives the Liquid Glass something worth refracting. Glass over near-flat
  black is a blur of nothing, which was most of why it looked underwhelming.
- It is tinted by the page's own data colours, so it belongs to the system
  rather than being a gradient bolted on.

Kept very low contrast deliberately — it sits under numbers people read. It
is off entirely under Reduce Transparency, and still under Reduce Motion. The
vitals page does not get it: that page is a readout and does not want a mood.

## Motion

Two animations, both behind `accessibilityReduceMotion`:

- **The quality badge** draws its ring in over 0.9s, and breathes slowly
  (2.6s, ±2.5%) *only* when the score is in the concerning band. A badge that
  pulses fast next to a health figure reads as an alarm, which is a claim
  this data cannot support.
- **The live dot** emits a slow expanding ring while polling is actually
  running, and stops when it is not.

The badge's ring state is `Double?`, falling back to the real value — a
context where `onAppear` never fires (a static render, a preview, a snapshot)
shows the correct ring rather than an empty one.

## Suggestions

The **How to improve this** button on the sleep tab expands a ranked short
list — at most three, because a list of eight things to fix is a list nobody
acts on.

Each suggestion names the number that triggered it and then quotes **Hume
Health's own published "Improvement" guidance** for that metric. Nothing here
is invented clinical advice and nothing diagnoses anything; these are
sleep-hygiene prompts tied to a figure, which is the most an app looking at
wrist data can honestly offer. The thresholds that decide *which* prompt
appears (deep 13–23% of total sleep, REM 20–25%, efficiency above 85%) are
ordinary population reference ranges, not a Hume API, and they are stated as
such in `SleepAdvisor`.

The panel under the list says plainly that the advice is reacting to
simulated data.

## Zones and colour vision

Colour is never the only signal — every zone also has a label and its own SF
Symbol, so a reading survives any colour vision. Zone colour is used on rings,
bars and glyphs (non-text UI, 3:1) but never on small body text.

Three ramps, switchable from the **View menu** in the menu bar — the standard
macOS home for appearance, and one click from anywhere rather than buried in
Settings — or from **Settings › View**. Both drive the same
`ZoneSettings.palette`.

The choice reaches every surface: the app window and the floating panel
observe it directly, and the widget extension reads it out of the App Group
on its next timeline. Changing it calls `reloadAllTimelines`, because a
separate process will not notice a defaults write on its own. Each was checked by simulating protanopia,
deuteranopia and tritanopia (Viénot et al. 1999) and measuring the worst-case
CIELAB ΔE between the three zones as each dichromat sees them. Below ~20 is
easily confused; above ~40 is comfortably distinct.

| Palette | dark ΔE | light ΔE | Notes |
|---|---|---|---|
| Classic | 38.0 | **5.7** | Codenotch's ramp. Strong in dark mode because its colours differ steeply in luminance, which dichromats retain. |
| High separation | 48.6 | 45.9 | Teal → amber → rose. |
| Monochrome | 26.7 | 24.7 | Lightness only; the only option that also works for achromatopsia. |

That **5.7** is the finding worth knowing: in *light* mode the classic ramp's
mid-green `#00A356` and dark amber `#B08800` genuinely are confusable with
red–green colour blindness. It is not a hypothetical — it is visible in
`Settings` when you compare the two swatch rows. The default is left as
Classic because it is correct in dark mode and is the shared visual identity,
but anyone with red–green CVD who uses Light Appearance should switch.

The "high separation" values were not picked by eye. A constrained search over
hue/saturation/value maximised the worst-case ΔE across normal, protan, deutan
and tritan vision, subject to ≥3:1 contrast on the surface and an ordinal
calm→alarm hue order. The first hand-picked attempt — the standard Okabe–Ito
"colourblind-safe" set — measured **5.1** for protanopia, worse than the
default, which is exactly why the search exists.

- **Heart rate** — banded against the wearer's own resting rate, not a
  population constant.
- **Stress** — 0–39 optimal, 40–69 elevated, 70+ high.
- **Skin temperature** — absolute deviation from the wearer's baseline; matters
  in both directions.
- **Activity** — always drawn optimal, because "high" is not a warning here.

## Swapping in the real API

`Shared/HumeBandService.swift`:

```swift
enum HumeBandClient {
    static let live: any HumeBandService = MockHumeBandService()
    //                                     ^ LiveHumeBandService(apiKey: …)
}
```

### Getting real data in

`../HumeCompanion` is an iPhone app that reads your band's data out of Apple
Health and sends it to this Mac over your Wi-Fi. See its README. The Mac
half — `RelayServer`, `RelayProtocol` — is built and tested; the phone half
needs deploying to a device from Xcode.

Direct Bluetooth was tried first and ruled out by evidence: the band
advertises no services, and on connection exposes only `FFF0` and `190E`
with vendor characteristics — no standard Heart Rate service, so nothing
documented to read. **Settings › Band** still holds that diagnostic, plus a
read-only listener that dumps whatever the vendor characteristics emit.

### What is actually connected: nothing

There is **no Bluetooth link to a Hume Band 2.0**, and every number the app
shows is synthetic — three sine waves driven by the clock, in
`MockHumeBandService.synthesise`. This was the brief (mock until real
credentials exist), but it bears repeating because the numbers look plausible
and they are health figures.

**Settings › Band** runs a CoreBluetooth scan and lists what is actually
advertising nearby, flagging anything that offers the standard Heart Rate
service (`0x180D`). That is the diagnostic that decides whether a Mac can read
the band directly at all — as of writing, no Hume Band is paired with this Mac,
and HealthKit does not exist on macOS, so the usual "read it from Apple Health"
route is unavailable here.

`LiveHumeBandService` fails loudly when no key is set rather than silently
falling back to mock numbers — showing invented health data to a user reading
their own vitals is worse than showing nothing. Its endpoint shape is a guess:
there is no verified public Hume Band 2.0 API reference behind it, so check the
JSON shape and the `projection` behaviour against the real docs before
shipping. Put the key in the Keychain, not in the repo.

## macOS-specific notes

- **No accessory families.** There is no lock screen, so the widget supports
  `systemSmall` / `Medium` / `Large` / `ExtraLarge` only.
- **AppKit colours.** `systemGroupedBackground` does not exist on macOS; the
  dashboard uses `windowBackgroundColor` for the page and
  `controlBackgroundColor` for cards, both of which track appearance.
- **Toolbar placement** is `.primaryAction`, not `.topBarTrailing`.
- **Both targets are sandboxed**, as macOS widget extensions must be, and the
  app holds `com.apple.security.network.client` for the real band API.

## Build and signing

```bash
xcodebuild -project HumeWidgets.xcodeproj -scheme HumeWidgets \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  -allowProvisioningUpdates build
```

`DEVELOPMENT_TEAM` is deliberately **not** set in the project — pick your own.

The **App Group** `group.com.tomasroldan.humewidgets` is what lets the app hand
fresh readings to the widget. macOS is stricter than iOS here:

1. An app-group entitlement requires a real Apple Development certificate —
   ad-hoc signing is rejected at build time with *"has entitlements that
   require signing with a development certificate"*.
2. This Mac must be registered in the developer account, and Mac App
   Development profiles must exist for both bundle IDs.
3. For distribution the group needs the team prefix:
   `<TEAMID>.group.com.tomasroldan.humewidgets` — change it in
   `Shared/MetricsStore.swift` and both `.entitlements` files together.

Until that is set up the app and widget still run and show correct values,
because the mock transport is deterministic on the clock and needs no shared
container. What you lose is the app-to-widget handoff: `MetricsStore.save`
silently no-ops when the container is unavailable, so the widget falls back to
synthesising its own reading instead of receiving the app's.
