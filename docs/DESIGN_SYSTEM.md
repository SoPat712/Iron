# Iron Design System

This is the single source of truth for how Iron looks, moves, sounds and reads.
It is written for engineers **and coding agents**. If you are handed a screenshot of
an unthemed or off-brand screen, follow [§16 Theming a screen from a
screenshot](#16-theming-a-screen-from-a-screenshot) and you should be able to bring
it on-system without asking anyone.

Pending, approved-but-unbuilt work lives in [`DESIGN_BACKLOG.md`](DESIGN_BACKLOG.md).
Visual references live on the design canvas
(<https://claude.ai/artifact/XwxfzWTFvH2PNZWqMRpihv>, pages "Round 3 · Iron blue",
"Round 4 · Live workout", "Round 5 · Exercises"). When this document and a canvas
board disagree, **this document wins**; when this document is silent, match the
board.

Contents

1. [Identity](#1-identity)
2. [Principles](#2-principles)
3. [Color](#3-color)
4. [Typography](#4-typography)
5. [Layout, spacing and shape](#5-layout-spacing-and-shape)
6. [Surfaces, materials and Liquid Glass](#6-surfaces-materials-and-liquid-glass)
7. [Iconography](#7-iconography)
8. [Shared components (code)](#8-shared-components-code)
9. [Recurring patterns](#9-recurring-patterns)
10. [Data visualization](#10-data-visualization)
11. [Motion](#11-motion)
12. [Haptics and sound](#12-haptics-and-sound)
13. [Copy and number formatting](#13-copy-and-number-formatting)
14. [Accessibility](#14-accessibility)
15. [Screen-by-screen reference](#15-screen-by-screen-reference)
16. [Theming a screen from a screenshot](#16-theming-a-screen-from-a-screenshot)
17. [Retired components and banned techniques](#17-retired-components-and-banned-techniques)
18. [Review checklist](#18-review-checklist)

---

## 1. Identity

**"If Apple made a strength-training app."** Iron should be indistinguishable in
quality from Fitness, Health or Activity, while being clearly its own app. It is
*not* Hevy with Liquid Glass on top. Hevy is only a reference for logging density.

What makes Iron recognisably Iron:

| Signature | What it means in practice |
| --- | --- |
| **Iron blue** | One accent, `systemBlue`. It means action, workouts, selection and *completed sets*. |
| **One color per metric** | Sets = orange, Volume = green, Time = cyan, Effort = pink, Records = yellow, Body = purple. A number's color tells you what it measures, on every screen. |
| **Bold fixed-width numerals** | Every number is SF Pro **bold** (or semibold in dense rows) with `.monospacedDigit()`. Never SF Rounded: the owner rejected it as cartoonish. |
| **Things fill** | Completing a set sweeps a fill across the row left to right. Rest drains a ring. Effort fills rising bars. Progress fills, it doesn't tick. |
| **Rest lives inside the exercise** | The rest timer appears under the set that started it, not in a modal. |
| **Native chrome** | System navigation bars, tab bar, sheets, lists, toggles and pickers. Iron never repaints system chrome. |

## 2. Principles

1. **Native first.** Reach for the SwiftUI control before an Iron-specific one. A custom control
   must beat the native one for a measurable reason. Today that means the set row, the rest
   strip and ruler, the effort graph, the session strip and the muscle-map tooltip.
2. **Semantic colors only.** Use `IronTheme` roles, which map to adaptive UIKit colors. Never
   hard-code a hex value, `Color.black`, `.white` or `.gray` for chrome.
3. **The system owns chrome.** Never set `toolbarBackground`, `presentationBackground`,
   `scrollContentBackground(.hidden)` with a custom fill, or a custom modal corner radius.
4. **Glass is depth, not decoration.** Liquid Glass is only for layers that float above
   changing content (see §6).
5. **Tint carries meaning.** If a color does not mean "action", "this metric" or "this status",
   it is not allowed.
6. **Dense, not cramped.** A workout screen shows a lot of data. Native does not mean sparse.
7. **Every animation explains something:** navigation, continuity or a state change.
   Decorative motion is banned.
8. **Accessible by construction:** Dynamic Type, VoiceOver, Reduce Motion, 44 pt targets
   and 4.5:1 text contrast.

## 3. Color

All roles live in `Shared/UI/SwiftUI/IronStyle.swift` (`IronPalette` → `IronTheme`).
Screens use **only** `IronTheme.*` and a few system colors named below.

### 3.1 Core roles

The hex values below are what the system color resolves to. They are listed so you can match
screenshots and canvas boards; never write them in code.

| `IronTheme` role | System color | Light | Dark | Means |
| --- | --- | --- | --- | --- |
| `accent` | `systemBlue` | `#007AFF` | `#0A84FF` | Actions, selection, workouts, **completed sets**, primary chart series |
| `accentSoft` | systemBlue @ 0.12 | — | — | Soft accent chips, icon wells, selected pills |
| `accentPressed` | systemBlue @ 0.72 | — | — | Pressed state of custom accent fills |
| `metricSets` | `systemOrange` | `#FF9500` | `#FF9F0A` | Set counts, warm-up sets |
| `metricVolume` | `systemGreen` | `#34C759` | `#30D158` | Volume (weight × reps), positive deltas |
| `metricTime` | `systemCyan` | `#32ADE6` | `#64D2FF` | Durations, elapsed time, rest |
| `metricEffort` | `systemPink` | `#FF2D55` | `#FF375F` | RPE, session effort |
| `metricRecord` | `systemYellow` | `#FFCC00` | `#FFD60A` | Personal records, trophies |
| `metricBody` | `systemPurple` | `#AF52DE` | `#BF5AF2` | Body measurements |
| `*Container` (one per metric) | hue @ 0.18 | — | — | Soft backgrounds for metric chips and badges |
| `success` | `systemGreen` | | | Sync status dots and success messages **only** |
| `warning` | `systemOrange` | | | Attention, overtime, paused rest |
| `danger` | `systemRed` | `#FF3B30` | `#FF453A` | Destructive actions, errors, the delete swipe |
| `primaryText` | `label` | `#000000` | `#FFFFFF` | Body text, titles, values |
| `secondaryText` | `secondaryLabel` | rgba(60,60,67,.60) | rgba(235,235,245,.60) | Captions, units, metadata |
| `tertiaryText` | `tertiaryLabel` | rgba(60,60,67,.30) | rgba(235,235,245,.30) | Placeholders, disabled text |
| `background` | `systemGroupedBackground` | `#F2F2F7` | `#000000` | Full-screen editors that cannot be a `List` |
| `surface` | `secondarySystemGroupedBackground` | `#FFFFFF` | `#1C1C1E` | Card surfaces where a `Section` is impossible |
| `raisedSurface` | `tertiarySystemGroupedBackground` | `#F2F2F7` | `#2C2C2E` | Nested low-emphasis surfaces |
| `field` | `secondarySystemFill` | rgba(120,120,128,.16) | rgba(120,120,128,.32) | Input and compact control backgrounds |
| `tertiaryFill` | `tertiarySystemFill` | rgba(118,118,128,.12) | rgba(118,118,128,.24) | Current-set fields, ring tracks, inactive pills |
| `outline` | `separator` | rgba(60,60,67,.29) | rgba(84,84,88,.60) | Hairlines only, never card borders |
| `onAccent` | white | | | Text and glyphs on solid accent |
| `diagramCanvas` | white (fixed) | | | Background behind exercise diagrams in both modes |

`Color(.quaternarySystemFill)` is allowed for inactive bars in graphs, as in the effort graph.

### 3.2 Rules for using metric colors

- Metric colors go on **numbers, short labels, icons and soft containers**. Never on body copy
  or long text.
- Cyan and yellow on a light background must be **semibold or bold** (contrast).
- Units ("lb", "kg", "sets") are smaller and `secondaryText`, even when the number is colored.
- One metric, one color, everywhere: Home, History, logger, finish, widgets, Watch and Live Activity.
- **Green never paints completed sets.** Completion is blue. Green only ever means volume or success.
- Muscle-group text tags are **neutral** (`secondarySystemFill` with `secondaryLabel`). Muscles are
  never color-coded by group. The anatomical muscle map uses accent only (§8.9).

### 3.3 Set-state colors (live logger)

| State | Row fill | Badge | Values | Check |
| --- | --- | --- | --- | --- |
| Upcoming | none | neutral filled circle (`tertiaryFill`), secondary number | `secondaryText` | neutral ring |
| Current (focused) | raised card (§15.6) | accent ring | primary, large | accent "Log Set" button |
| Completed, normal | accent sweep to **0.12** settled (peak 0.24) | `accentSoft` + accent number | primary bold, no field fill | `checkmark.circle.fill` accent |
| Completed, warm-up | **soft** orange sweep, settled 0.14 | "W" in `metricSets` on `metricSetsContainer` | primary | same check, accent |
| Completed, drop set | **soft** indigo (`systemIndigo`) sweep, settled 0.14 | "D" in indigo on indigo @ 0.18 | primary | accent |
| Completed, failure | **soft** red (`systemRed`) sweep, settled 0.12 | "F" in red on red @ 0.16 | primary | accent |

The owner likes the current blue fill on normal completed sets. **Do not change it.** Set-type
fills must be *softer* than the blue, never saturated slabs with white text. Use
`IronTheme.setFill(for:)` once it exists (backlog B4).

### 3.4 Muscle map colors

These are copied exactly from the live-workout map. Every `BodyView` in the app uses this
`BodyViewStyle`:

```swift
BodyViewStyle(
    defaultFillColor: Color(.tertiaryLabel).opacity(0.35),
    strokeColor: Color(.separator),
    strokeWidth: 0.5,
    selectionColor: IronTheme.accent,
    selectionStrokeColor: IronTheme.accent,
    selectionStrokeWidth: 1,
    headColor: Color(.tertiaryLabel).opacity(0.45),
    hairColor: Color(.quaternaryLabel)
)
// primary muscles:   .highlight(primary,   color: IronTheme.accent)
// secondary muscles: .highlight(secondary, color: IronTheme.accent, opacity: 0.42)
```

Always render front and back side by side (`gender: .male`, `side: .front` / `.back`). Map
catalog muscle names with `ironMapMuscle(_:)` (`Iron/UI/SwiftUISupport.swift`). Never write a
second mapping table.

## 4. Typography

San Francisco only, through SwiftUI text styles so Dynamic Type works. Sizes are at the
default "Large" content size.

| Style | pt / weight | Used for |
| --- | --- | --- |
| `.largeTitle.bold()` | 34 bold | Root tab titles (Home, History, Workout, Exercises, Settings) |
| `.title.bold()` | 28 bold | Hero headers (finish screen workout name, exercise detail title) |
| `.title2` | 22 | Big standalone numbers (`ironMetric(.title2)`) |
| `.title3.weight(.semibold)` | 20 semibold | Card titles inside screens ("Session", "How hard was it?", "Target") |
| `.headline` | 17 semibold | Row titles, inline navigation titles, exercise names in the logger |
| `.body` | 17 | Body copy, list rows |
| `.callout` | 16 | Secondary rows |
| `.subheadline` | 15 | Metadata lines, watch-sync banner |
| `.footnote` | 13 | Captions, section footers, chart axis labels |
| `.caption` | 12 | Legends, compact metadata, badges |
| `.caption2` | 11 | Tiny labels under charts and figures |

### 4.1 Numbers

Every metric number (weights, reps, volume, durations, timers, counts, RPE and percentages) uses:

```swift
Text("185").font(.ironMetric(.title2))                    // bold, fixed-width digits
Text("8").font(.ironMetric(.body, weight: .semibold))     // dense rows
```

`Font.ironMetric(_:weight:)` = `.system(style).weight(weight).monospacedDigit()`. Default weight
is `.bold`.

| Context | Style |
| --- | --- |
| Hero metric (exercise headline 1RM, finish grid values) | `ironMetric(.largeTitle)` or `.title` |
| Card metric values (Home week numbers, summary columns) | `ironMetric(.title2)` |
| Rest countdown in the rest strip | `ironMetric(.title3)` in `metricTime` |
| Focused-set weight and reps | `ironMetric(.largeTitle)` (≈34 pt) |
| Compact set row values | `ironMetric(.title3, weight: .bold)` |
| Inline metric lines ("1h 02m · 14 sets · 9,860 lb") | `ironMetric(.subheadline, weight: .semibold)` |
| Badges ("RPE 8", "2 PRs") | `ironMetric(.caption, weight: .bold)` |

- **Units** sit after the number in a smaller style (`.footnote`/`.caption`, semibold) in
  `secondaryText`, baseline-aligned: `HStack(alignment: .firstTextBaseline, spacing: 2)`.
- Values that change animate with `.contentTransition(.numericText())` (countdowns use
  `.numericText(countsDown: true)`), driven by `IronMotion.snappy`.
- Never use `design: .rounded` for anything.

### 4.2 Text color hierarchy

Primary for titles and values, secondary for metadata, units and captions, tertiary for
placeholders. Metric color is for the number only, never its label. The exception is labels that
*are* metric identifiers, such as the "Duration / Volume / Sets" labels in the logger summary,
which take their metric color.

## 5. Layout, spacing and shape

### 5.1 Tokens (`IronTheme`)

| Token | Value | Use |
| --- | ---: | --- |
| `horizontalPadding` | 16 | Screen gutter for custom layouts (List provides its own) |
| `controlHeight` | 44 | Minimum height for every interactive control |
| `iconButtonSize` | 44 | Icon-only buttons (44 × 44 hit area, glyph may be smaller) |
| `pillCornerRadius` | 22 | Capsule controls at 44 pt |
| `cornerRadius` | 12 | Generic rounded rectangles |
| `compactCornerRadius` | 10 | Set rows, completion fill, fields |
| `heroCornerRadius` | 22 | Hero/summary glass clusters, the rest strip |
| `floatingWorkoutBottomClearance` | 152 | Bottom inset so content clears the tab bar and workout accessory |
| `activeWorkoutPillHorizontalPadding` | 20 | Fallback floating workout pill |

### 5.2 Spacing scale

Use only **2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32**.

- Between a label and its value: 2–4.
- Inside a card: 12–16 padding, 10–14 between rows of content.
- Between cards or sections: 12–20 (List handles this itself).
- Icon to text in a chip or label: 5–6.

### 5.3 Shapes

- Always `RoundedRectangle(cornerRadius:, style: .continuous)`. Never non-continuous corners.
- **Capsule** is reserved for: compact status chips (RPE, PR, streak), segmented and range pills,
  prominent toolbar buttons, the floating workout accessory, the rest strip controls, the
  focused-set "Log Set" button, steppers, and tooltips.
- Grouped content uses `List`/`Form` `Section`s, whose corners come from the system. Custom
  cards (hero, progress card, target card) use `heroCornerRadius` (22). Canvas boards show 26;
  use 22 in code.
- No borders around cards. No drop shadows on cards. Shadows are only for floating glass
  (system-provided) and the tooltip.

### 5.4 Touch targets

Minimum 44 × 44 pt, always. A visually smaller glyph gets a padded `contentShape`.

## 6. Surfaces, materials and Liquid Glass

| Layer | Implementation |
| --- | --- |
| Screen background | System (`List`, `Form`, `NavigationStack`); never painted |
| Grouped content | `List` `.insetGrouped` sections. One section holds related rows; never wrap each row in its own card, never nest cards |
| Custom card | `IronTheme.surface` fill, `heroCornerRadius`, used only when the content cannot be rows (charts, the muscle map, the logger's exercise card) |
| Floating chrome | Liquid Glass: `.ironLiquidGlassPill(tint:)` (capsule) or `.ironLiquidGlassSurface(cornerRadius:tint:)`; on iOS 26 it is `glassEffect(.regular.tint().interactive())`, with an `.ultraThinMaterial` + hairline fallback |
| Buttons floating over content | `.ironGlassButtonStyle()` (secondary) and `.ironProminentGlassButtonStyle()` (the one primary action) |

**Glass is allowed only on:** the active-workout tab accessory, the logger's collapsed summary
pill, the Home weekly hero, floating action buttons (Add Exercises), and tooltips (material).
Glass never sits on glass. Glass never replaces a List section.

## 7. Iconography

SF Symbols only, using the semantic style and weight of the adjacent text. Never put every
symbol in a colored tile. Icon wells (32 pt soft circles) are only for metric chips and record
lists.

| Concept | Symbol |
| --- | --- |
| Workout / start | `dumbbell.fill` (filled when prominent), `figure.strengthtraining.traditional` |
| History | `clock.arrow.circlepath` |
| Exercises tab | `figure.strengthtraining.traditional` |
| Rest timer | `timer` (chips), `stopwatch` (duration sets) |
| Add | `plus` |
| Edit | `pencil` |
| Delete | `trash` (menus), `trash.fill` (swipe action) |
| More | `ellipsis.circle` (toolbar), `ellipsis` (inline) |
| Record / PR | `trophy.fill` in `metricRecord`; `medal.fill` for "best" lists |
| Warm-up / drop / failure | `flame`, `arrow.down.right`, `bolt.fill` |
| Effort | `gauge.with.dots.needle.50percent` |
| Progress chart | `chart.xyaxis.line` |
| Repeat workout | `arrow.clockwise` |
| Share / export / import | `square.and.arrow.up`, `square.and.arrow.down` |
| Sync | `arrow.triangle.2.circlepath`; device: `iphone`, `applewatch` |
| Collapse / expand | `chevron.up` / `chevron.down` |
| Streak | `flame.fill` |
| Plate calculator | `plusminus` |

Symbol effects: `.symbolEffect(.bounce)` for confirmations (check, trophy) and
`.contentTransition(.symbolEffect(.replace))` for state swaps (play ↔ pause, circle ↔
checkmark). Gate both on Reduce Motion.

## 8. Shared components (code)

Before building anything custom, check this list. File paths are relative to the repo root.

### 8.1 Tokens: `Shared/UI/SwiftUI/IronStyle.swift`
`IronPalette`, `IronTheme`, `Font.ironMetric`, `IronMotion`. This file is shared with the widget
extension, so keep it free of app-only imports.

### 8.2 Glass helpers: `Iron/UI/SwiftUISupport.swift`
`ironLiquidGlassPill(tint:)`, `ironLiquidGlassSurface(cornerRadius:tint:)`,
`ironGlassButtonStyle()`, `ironProminentGlassButtonStyle()`.

### 8.3 `ironSetCompletion(isComplete:feedbackEnabled:)`
Leading-anchored fill sweep behind a row: `scaleEffect(x:)` from 0 to 1 at opacity 0.24 using
`IronMotion.collapse`, then after 420 ms it fades to 0.12. It fires the `.success` haptic.
Existing completed rows appear already settled and do not replay. Reduce Motion uses a fade and
keeps the haptic. Apply it to the row content inside its inset; it adds no geometry. Backlog B4
adds a set-type tint parameter.

### 8.4 `ironStaggeredEntrance(index:)`
Opacity 0 → 1 and y +8 → 0 with `IronMotion.snappy`, delayed 40 ms × index. Plays **once**.
Never reset it in `onDisappear`, because List prefetching would then hide rows.

### 8.5 `IronRestRing(progress:)`
Countdown ring. `progress` is the fraction remaining (1 = full). Its track is `tertiaryFill`,
it draws a 4 pt `metricTime` stroke with round caps, and it starts at 12 o'clock. Callers own
the timer. Hide it from VoiceOver when the text already announces the time.

### 8.6 `EffortRatingGraph(rating:allowsUnrated:)`
Ten rising capsules from 18% to 100% height across a 108 pt graph, 5 pt apart. Active bars use
the `metricEffort` gradient and inactive bars `quaternarySystemFill`; the selected bar scales
to 1.06 with a soft glow. Set it by tap or drag, with a selection haptic per step and an
accessibility adjustable action. The title and subtitle above read tier and value, using
`EffortTier`: 1–2 Easy, 3–4 Light, 5–6 Moderate, 7–8 Hard, 9–10 All Out. This is **the**
pattern for any 1-to-N intensity input; the RPE picker redesign reuses it (backlog B5).

### 8.7 `IronSessionStrip`: `Iron/UI/Components/IronSessionStrip.swift`
Session timeline. Input is `[ExerciseGroup(label:, sets: [Set(relativeVolume: 0…1, kind:
.warmUp/.normal/.record, completedAt:, volume:, result:, rpe:)])]`.
- **`.full`:** two lanes, a volume-bars lane and a work/rest track, plus trimmed time axis
  labels, rest labels, exercise bands with a chip fallback, scrubbing, a legend and an
  accessibility summary.
- **`.compact`:** bars only, used in History rows.

Colors: warm-up `metricSets`, normal `accent`, record `metricRecord`, rest connectors soft
`metricTime`. Callers own ordering and normalization.

### 8.8 Sheets: `Iron/UI/SwiftUISupport.swift`
`IronUtilitySheet` (titled utility sheet with icon, subtitle and close button),
`IronConfirmationSheet`, `IronStatusSheet`, `IronDateTimePickerSheet`, `IronDurationPickerSheet`
/ `IronDurationWheel` (system dual wheel for minutes and seconds). Prefer `.alert` or
`.confirmationDialog` when a one-line explanation is enough.

### 8.8.1 `HevyImportProgressOverlay`: `Iron/Data/Model/HevyCSV.swift`
A blocking progress overlay for long imports. Its phases are reading (files) and saving
(workouts). Reuse the same pattern (glass card, `ProgressView`, phase text and counts) for any
operation over about 1 s.

### 8.9 Muscle map (MuscleMap package)
`import MuscleMap`, then `BodyView(gender: .male, side:, style:)` with the style from §3.4.
- **Live workout:** a 54 pt tall pair, not interactive (`allowsHitTesting(false)`).
- **Exercise detail:** a pair about 190 pt tall that is interactive (press-and-hold tooltip,
  §9.8).
- Map names with `ironMapMuscle(_:)`. Never hand-draw bodies.

### 8.10 Exercise art
`ExerciseDiagramThumbnail(exercise:size:)` (in `Iron/UI/Exercises/ExercisesView.swift`) draws
a circular white canvas with the PDF diagram or remote GIF fitted inside, a hairline ring and
a 2 pt shadow. Sizes: 42 (logger header), 58 (lists), 60 (detail header).
`ExerciseRemoteMediaView` plays the animated demo.

### 8.11 Sounds: `Shared/IronSoundPlayer.swift`
Covered in §12.

## 9. Recurring patterns

### 9.1 Metric chip (Home week card, finish grid)
```
[32pt circle, metric Container fill, SF Symbol 17pt in metric color]
<value>  ironMetric(.title2), primary (or metric color in the finish grid)
<label>  .footnote, secondaryText
```
Three per row in a `Grid` or a three-column `LazyVGrid`. Labels never truncate; at
accessibility sizes they wrap.

### 9.2 Metric line (History rows, accessory, exercise rows)
`"1h 02m · 14 sets · 9,860 lb"`: each value in its metric color, `ironMetric(.subheadline,
weight: .semibold)`, separated by `" · "` in `secondaryText`. Order is always
**time → sets → volume**, with effort or records as trailing badges.

### 9.3 Badges
A capsule 22–24 pt tall with 8 pt horizontal padding and `ironMetric(.caption, weight: .bold)`:
- PR: `trophy.fill` 11 pt + "2 PRs" in `metricRecord` on `metricRecordContainer`.
- RPE: "RPE 8" in `metricEffort` on `metricEffortContainer`.
- Streak: `flame.fill` + "33-week streak" in accent on `accentSoft`.
- Set chips (exercise history): "205×5" on `tertiaryFill`; warm-up in `metricSets` on its
  container; the record set gets a trophy and record colors.

### 9.4 Segmented control
Use the system `Picker(...).pickerStyle(.segmented)` where possible. If you need custom styling
(the exercise progress card), use a 32 pt capsule track on `tertiaryFill`, a selected segment on
`systemBackground`/`card3` with a subtle shadow, 13 pt text (semibold when selected), and
`IronMotion.snappy` with `matchedGeometryEffect` for the thumb. Use four segments at most.

### 9.5 Time-range pills
Five equal 30 pt capsules: **1M · 3M · 6M · 1Y · All**. The selected pill is `accentSoft` with
accent bold text; the rest are clear with `secondaryText` semibold. Default is **3M**.

### 9.6 Empty states
Use `ContentUnavailableView` with an SF Symbol, a title and one sentence that says what will
appear and how to make it appear. No illustrations. Example: "No sessions yet" / "Log this
exercise in a workout and your progress will chart here."

### 9.7 Destructive confirmation
`.confirmationDialog` with a `.destructive` button. The copy states what is lost and what is
kept: "Your completed workout history is not affected."

### 9.8 Tooltip (muscle map, chart callouts)
A small capsule (30 pt tall, 12 pt horizontal padding) with `.regularMaterial` or glass, a
hairline edge and the shadow `0 6 18 black @ 0.28`. Content is an 8 pt colored dot, the bold
name and the role in `secondaryText`, as in **"● Chest  Primary"**. A 14 × 7 pointer points at
the target, and the tooltip sits above the touch point, clamped inside the card.
- **Appears** with scale 0.92 → 1 plus fade (`IronMotion.snappy`) and a `.selection` haptic
  whenever the target changes.
- **Disappears** on finger lift, or about 2 s after a tap.
- **Triggers:** touch-and-hold (0.25 s), then drag to scrub between targets. A quick tap shows
  it too. A vertical drag that starts on the map must still scroll the page; use a long-press
  that then becomes a drag, never an always-on `DragGesture(minimumDistance: 0)`.
- **Never** a sheet or modal.

### 9.9 Swipe to delete (custom rows)
The row slides left and a **separate** red capsule appears in the space it leaves, with an
**8 pt gap** between the row's trailing edge and the action. The action never sits under the
row and never overlaps the row's own controls. While the row is open, a tap on the row closes it
and does not toggle anything. A full swipe past 60% deletes. Use `danger` with `trash.fill`
and "Delete" in white. In `List`s, use the system `.swipeActions`.

### 9.10 Loading and progress
For work under about 1 s, show nothing. For more than that, show inline `ProgressView` in
the row or button. For blocking work over about 3 s (imports), use the overlay pattern in
§8.8.1 with a phase and count.

## 10. Data visualization

- **Swift Charts only.** No hand-drawn `Canvas`, `Path` or `GeometryReader` plotting and no
  third-party chart libraries. The session strip and effort graph are deliberate stack-based
  exceptions.
- The marks are the most prominent thing. Axes are `secondaryText` `.caption2`; gridlines are
  dashed `separator` at reduced opacity, and there are at most 3 horizontal gridlines with
  trailing y labels.
- **Line charts** (1RM, top weight): a 2.5 pt accent line with round joins; points are 6 pt
  dots. An area fill under the line uses accent at about 0.15 (a flat color, never a gradient
  wash). The latest PR point is a 9 pt `metricRecord` dot with a soft halo and a 1.5 pt card
  stroke.
- **Bar charts** (volume, reps): rounded bars, 4 pt corner, in the metric color (volume green,
  reps orange).
- **Scrubbing:** `chartXSelection`. The selected mark is full color and the others drop to 0.45
  opacity. A 1 pt vertical rule marks the selection, and the headline above the chart switches
  to the selected value and date. Callouts never cover marks.
- **Axis:** about 3–4 x labels ("Aug", "Sep", "Oct", or day numbers for 1M). Use automatic
  `AxisMarks`.
- **Color series:** one metric per chart, colored by that metric. Never encode meaning with
  hue alone.
- **First appearance:** bars grow and lines draw in with `IronMotion.snappy`. Changing metric
  or range cross-fades the plot and rolls the headline digits.
- **VoiceOver:** a chart summary label, the selected value and an adjustable action for
  previous and next points.
- **Vertical drags belong to the scroll view.** Chart gestures must only react to horizontal
  intent.

## 11. Motion

Tokens (`IronMotion`, in `IronStyle.swift`):

| Token | Curve | Use |
| --- | --- | --- |
| `snappy` | spring response 0.32, damping 0.82 | Anything the finger caused: selection, toggles, value changes, tooltips |
| `collapse` | spring response 0.42, damping 0.86 | Large surfaces moving: header collapse, rest strip insert, focused-set expand |
| `fade` | easeInOut 0.18 s | Non-spatial changes, and the Reduce Motion substitute |

Always write `withAnimation(IronMotion.preferred(.snappy, reduceMotion: reduceMotion))`, reading
`@Environment(\.accessibilityReduceMotion)`. Reduce Motion swaps spatial motion for a fade; the
haptics still play.

| Moment | Motion |
| --- | --- |
| Complete a set | Fill sweep (§8.3), check bounce plus `.symbolEffect(.replace)`, success haptic and `setComplete` sound (`setRecord` for a PR) |
| Next set becomes current | The focused editor expands from the compact row (`collapse`). The previous card collapses into its completed row |
| Counters | `.contentTransition(.numericText())` plus `snappy` |
| Rest starts | The strip inserts under the triggering set with `.move(edge: .top).combined(with: .opacity)` and `collapse` |
| Rest ticks | The ring drains continuously and the digits roll down (`numericText(countsDown: true)`) |
| Rest ends | The ring pulses once (scale 1.12), the strip folds away, plus a light-impact haptic and the `restComplete` sound |
| Rest ruler opens | Expands under the strip (`collapse`), with ticks fading in |
| Delete set | The row slides out, then collapses (`collapse`) with an opacity plus scale 0.96 transition |
| Header collapse | The summary is swapped for the glass pill (`collapse`), and labels never squash |
| Open or minimize the workout | Zoom from the tab accessory (`matchedTransitionSource` plus `.navigationTransition(.zoom)`); fade under Reduce Motion |
| Finish screen | Metrics rise in staggered (`ironStaggeredEntrance`), session bars grow per exercise, trophies bounce |
| Effort and RPE | Bars fill while dragging, with a selection haptic per step |
| Charts | Grow on first appearance; cross-fade when the metric or range changes |
| Tooltip | Scale 0.92 → 1 plus fade (`snappy`) |
| Lists reordering (recency) | Default List animation; do not add extra motion |

Never delay a dismissal, save or navigation for an animation.

## 12. Haptics and sound

### 12.1 Haptics (`.sensoryFeedback`)

| Event | Feedback |
| --- | --- |
| Set completed | `.success` (inside `ironSetCompletion`) |
| Stepper tap, picker step, effort and RPE step, ruler notch, tooltip target change, segment change | `.selection` |
| Rest finished | `.impact(weight: .light)` |
| Delete committed | `.impact(weight: .medium)` |
| Error or validation failure | `.error` |

### 12.2 Sounds (`IronSoundPlayer.shared.play(.cue)`)

Original procedurally generated `.caf` files live in `Iron/Resources/Sounds/`; regenerate them
with `scripts/generate_sounds.py`. The audio session is `.ambient` (it mixes with music and
respects the silent switch). Players are preloaded at launch.

| Cue | When | Volume |
| --- | --- | --- |
| `setComplete` | Set marked complete | 0.6 |
| `setRecord` | Completed set is a PR (instead of `setComplete`) | 0.6 |
| `tick` | Keypad, steppers, dial and ruler notches, ±15 s | 0.35 |
| `restComplete` | Rest timer reaches zero (also the notification sound) | 0.8 |
| `workoutFinish` | Workout saved | 0.6 |

Never use system "beep" sounds. Never play a sound without its matching haptic, except
`tick`.

## 13. Copy and number formatting

- **Terminology:** "Workout" means a saved, reusable workout. Never say "routine", "plan" or
  "template" in UI copy, even though the model uses those names. "Set", "Rest", "Effort" or
  "RPE", "Record" or "PR", "Volume".
- **Case:** Title Case for buttons, navigation titles and section headers ("Start Workout",
  "Recent Workouts"). Sentence case for body text, footers, captions and tooltips ("Touch and
  hold a muscle").
- **Weights:** `205 lb`, `92.5 kg`. Use `settingsStore.weightUnit` and the
  `WeightUnit.convert` path; never hard-code the unit.
- **Sets:** `205 × 5` with a true multiplication sign (×) and spaces; chips may drop the
  spaces (`205×5`).
- **Volume:** `9,860 lb`, abbreviated as `19.0k lb` above 10,000 in compact places.
- **Durations:** elapsed `1h 02m` or `18:42`; rest `2:30`; adjustments `−15` and `+15` with a
  true minus sign (−).
- **Dates:** "Today", "Yesterday", "Wed, Oct 14" (same year), "Oct 14, 2025" (another year).
  Relative ages use `RelativeDateTimeFormatter` `.named` ("7 days ago").
- **Effort:** "RPE 8", "RPE 8.5"; session effort "8 · Hard".
- **Deltas:** an arrow glyph (↑/↓ symbol) plus the value, in `metricVolume` when good and
  `secondaryText` when flat or negative ("↑ 18 lb · in 3 months"). Never red for a dip; a dip
  is not an error.

## 14. Accessibility

- Dynamic Type through the accessibility sizes. Rows reflow from horizontal to vertical
  (`ViewThatFits` or an accessibility-size check). Exercise names wrap.
- Every icon-only button has an `accessibilityLabel`. Custom controls expose
  `accessibilityValue` and `accessibilityAdjustableAction`: steppers, effort, RPE, the ruler and
  charts.
- Combine composite rows with `.accessibilityElement(children: .combine)` or give them a written
  label ("Set 2, 205 pounds, 5 reps, completed").
- Decorative images and figures are `accessibilityHidden(true)`, with their meaning stated in a
  label on the container ("Target muscles. Primary: Chest. Secondary: Shoulders, Triceps.").
- Contrast is 4.5:1 for text. Metric-colored text on light backgrounds must be bold.
- Reduce Motion is covered in §11. Reduce Transparency is handled automatically because glass
  falls back to material.

## 15. Screen-by-screen reference

### 15.1 Tabs
There are five tabs, always in this order: **Home · History · Workout · Exercises · Settings**.
Each uses `NavigationStack` with a large title. The tab bar minimizes on scroll
(`.tabBarMinimizeBehavior(.onScrollDown)`). The active workout appears as the native tab-bar
accessory: name plus a metric line (time · volume · sets) on the left, and expand and discard
buttons on the right.

### 15.2 Home (`Iron/UI/Feed/FeedView.swift`)
Board: *Round 3 → Home*. Sections, in order:
1. A greeting caption ("Good afternoon") in `.headline`, `secondaryText`.
2. **Week card** (glass hero): three metric chips (Workouts in accent, Sets in `metricSets`,
   Volume in `metricVolume`), seven daily volume bars (accent on a `tertiaryFill` track, 22 pt
   wide capsules, today's weekday label bold accent), a "Best day Saturday at **11.4k lb**"
   caption with the value in `metricVolume`, and a full-width Resume or Start Workout button
   (prominent glass, 50 pt).
3. A one-line comparison caption ("Volume is up 12% on last week").
4. **Last 4 Weeks** calendar: 34 pt day circles, trained days solid accent with white numbers,
   others `tertiaryFill` with `secondaryText`. A streak chip sits in the section header.
5. Recent Training, Muscle Focus, Body, and Pinned Charts, as today.

### 15.3 History (`Iron/UI/History/HistoryView.swift`)
Board: *Round 3 → History*. A segmented control (Workouts · Exercises · Insights). Workouts are
grouped by week, with headers showing the count in accent and volume in green. Each row has the
title, PR and RPE badges, "date · muscles" metadata, the metric line and an `IronSessionStrip`
in `.compact`. The detail view has Repeat in its toolbar menu.

### 15.4 Workout tab (`Iron/UI/Workout/StartWorkoutView.swift`)
Being redesigned in backlog B8: Quick Start, Recent Workouts with one-tap Repeat, and Saved
Workouts. Until then: a Quick Start section plus a Saved Workouts list.

### 15.5 Exercises (`Iron/UI/Exercises/*`)
- **Library** (`ExerciseMuscleGroupsView`): `.searchable`, two independent filter menus (muscle
  and equipment), and a **recency-first** order. Every exercise you have done, imported Hevy
  history included, comes first, newest first; the rest keep their existing order. Search
  results follow the same rule. This is implemented by `ExerciseStore.orderedByRecency` and
  `lastPerformedDates`.
- **Detail** (`ExerciseDetailView`): see backlog B6 and boards *Round 5 → Exercise* and
  *History segment*.

### 15.6 Live workout (`Iron/UI/Workout/CurrentWorkoutView.swift`)
Boards: *Round 3 → Logger B · focused set*, *Round 4 → Live workout* (only the parts the backlog
adopts).

Top to bottom:
1. **Top bar:** `chevron.down` (minimize), "Log Workout" (`.headline`), the rest-timer button
   and the prominent **Finish** capsule.
2. **Session bar** (backlog B2): a thin progress bar segmented per exercise. It stays visible
   even when the header collapses.
3. **Session header** (expanded at scroll top): the watch-sync banner (dot, status text such as
   "Saved on iPhone · Install Iron on Watch", device glyph, collapse chevron), then a summary row
   with **Duration** (`metricTime`, tap to edit), **Volume** (`metricVolume` plus unit),
   **Sets** (`metricSets`) and the **live muscle map** (54 pt front and back, completed sets
   only).
4. **Collapsed state** (after about 64 pt of scroll): the header is replaced by a full-width
   glass pill reading "● 18:42 • 2,430 lb • 6 sets ⌄". The scroll content gets a 66 pt top
   inset so the pill never covers the first exercise.
5. **Exercise card:** a 42 pt diagram thumbnail, the name (`.headline`), equipment
   (`secondaryText`), the rest chip top right (backlog B3), and an ⋯ menu (Replace, Superset,
   Remove). Touch-and-hold the title to reorder.
6. **Set rows:**
   - **Completed:** a compact row with the fill sweep, badge, values and check.
   - **Current, non-duration:** the **focused editor**, a raised card containing:
     - a header with "Set N" (it opens the set-type menu) and "Last time 200 × 5";
     - two tiles for weight and reps, each with a huge `ironMetric` TextField and 40 pt −/+
       circular steppers (5 lb or 2.5 kg; 1 rep);
     - a plates-per-side hint (barbell only; it opens the plate calculator) and an Add RPE pill;
     - a full-width 52 pt **Log Set** capsule in accent with a checkmark.
   - **Upcoming:** a compact row in secondary colors.
   - **Duration sets:** the compact row with an inline timer.
   - Rows swipe left to delete (§9.9).
7. **Rest strip** under the set that started it: a `metricTimeContainer` rounded rectangle with
   `IronRestRing`, the countdown and "Rest of 2:30", then four 44 pt neutral circular buttons:
   **−15 · pause/play · +15 · skip**. Tapping the countdown opens the **inline rest-length
   ruler** (backlog B3); the old dial modal is retired.
8. **Add Exercises:** a prominent glass capsule button, then the bottom actions.

### 15.7 Workout complete (finish editor)
Board: *Round 3 → Workout complete*. Order: header (accent circle icon, name, date range); a
3 × 2 metrics grid (Duration, Volume, Sets, Exercises, Avg RPE, Records, each value in its metric
color); `IronSessionStrip(.full)`; **How hard was it?** (`EffortRatingGraph`); records list
(hidden when empty); the "Update saved workout" toggle; the Apple Health row (state: will save,
saved, waiting, imported, or not exported); notes and media; Save and Discard.

### 15.8 Settings
A plain `Form`/`List` with native rows. "Import & Export" holds the Hevy CSV import, backups and
exports. The Sounds & Haptics screen previews each cue.

### 15.9 Watch, widgets and Live Activity
- **Watch:** native watchOS `List`/`Section`, `Picker` rows, a prominent Complete Set button
  and a rest capsule in the `safeAreaInset`. Same metric colors.
- **Widget:** `containerBackground(.fill.tertiary, for: .widget)`, with no solid accent slabs.
- **Live Activity:** an identity row, an exercise and set row, a native progress view and a
  timer or controls row (−15 · +15 · Skip App Intents). A `.small` supplemental family is
  provided for the Watch Smart Stack.

### 15.10 Apple Health rule (behavior, not visual)
Only workouts **completed in Iron** (phone or Watch) are exported. Imported workouts (Hevy,
`importSource != nil`) are **never** exported. UI copy must say so where relevant.

## 16. Theming a screen from a screenshot

Use this procedure when you are given a screenshot of a screen that is not on-system (stock
SwiftUI, legacy Iron, or Hevy-like) and asked to "theme it".

**Step 1: inventory.** List every element in the screenshot and classify it: navigation chrome,
section or card, row, number, label, unit, icon, button (primary, secondary or destructive),
input, chart, badge, empty state, progress.

**Step 2: apply this mapping table** (left: what you see; right: what it becomes).

| You see | Make it |
| --- | --- |
| A custom-colored nav bar, tab bar or sheet background | Delete the custom background; let the system render it |
| Cards with borders or shadows stacked in a ScrollView | A `List(.insetGrouped)` with `Section`s, or one `surface` card (radius 22) when the content is a chart or graphic |
| Each row in its own card | Rows inside one `Section` |
| A plain number ("185", "1:30", "12") | `Text(...).font(.ironMetric(<style>))`, in its **metric color** if it measures sets, volume, time, effort, records or body; otherwise primary |
| A number with its unit in the same font | Split it: number in `ironMetric`, unit `.footnote` `secondaryText`, baseline-aligned |
| A row of 2–4 stats | Metric chips (§9.1) or metric columns, with values colored by metric |
| "1h 2m, 14 sets, 9860 lb" as plain text | The metric line pattern (§9.2) |
| Green on a "done" thing | Accent blue (completion) unless it is volume or success |
| Any gray, black or white `Color` literal | The semantic role from §3.1 |
| Rainbow muscle tags | Neutral tags (`secondarySystemFill` + `secondaryLabel`) |
| A primary button (filled) | `.ironProminentGlassButtonStyle()` floating over content, or `.borderedProminent` in a list; capsule shape; one per surface |
| A secondary button | `.bordered` or `.ironGlassButtonStyle()` |
| A delete button | `Button(role: .destructive)` plus a confirmation dialog |
| A custom segmented control or tabs | `Picker(.segmented)`, or §9.4 if it needs styling |
| A custom slider or dial for a discrete scale | `EffortRatingGraph`-style rising bars (intensity) or a ruler (time) |
| A wheel picker for RPE or effort | The rising bars (§8.6, backlog B5) |
| A chart drawn with shapes or a third-party library | Swift Charts following §10 |
| A "PR", "Best" or trophy marker | A record badge (§9.3) in `metricRecord` |
| An empty white screen with text | `ContentUnavailableView` (§9.6) |
| A spinner over the whole screen | Inline `ProgressView`, or the import overlay pattern for long work |
| Hand-drawn body or muscle graphics | MuscleMap `BodyView` with the §3.4 style |
| A modal popup with a single fact | A tooltip (§9.8) or `.popover` |
| Rounded font numbers | SF Pro via `ironMetric` |
| A corner radius that is not continuous, or random radii | `.continuous`, using 10, 12, 22 or capsule |
| Animations with ad-hoc durations | `IronMotion` tokens plus `preferred(_:reduceMotion:)` |
| Beeps | `IronSoundPlayer` cues |

**Step 3: hierarchy pass.** There is exactly one dominant action per screen. Titles are `.largeTitle`
at the root and `.headline` inline. Metadata is `secondaryText`. Max two type sizes per row.

**Step 4: color audit.** Every colored pixel must be accent, a metric role, a status role or
media. If you cannot say which role a color is, it is wrong.

**Step 5: states.** Design and verify empty, loading, error, light, dark, Dynamic Type XXXL and
Reduce Motion.

**Step 6: motion and feedback.** Add `numericText` to changing numbers, `snappy` to toggles and
selections, a `.selection` haptic to discrete steps, and sounds only for the §12 events.

**Step 7: check against §18.**

Worked example, a stock stats row:

```swift
// Before
HStack { Text("Volume: 9860 lb").foregroundColor(.green); Text("Sets: 14") }

// After
HStack(spacing: 0) {
    metric("Volume", value: "9,860", unit: "lb", tint: IronTheme.metricVolume)
    metric("Sets", value: "14", unit: nil, tint: IronTheme.metricSets)
}
func metric(_ label: String, value: String, unit: String?, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.ironMetric(.title2)).foregroundStyle(tint)
                .contentTransition(.numericText())
            if let unit { Text(unit).font(.footnote.weight(.semibold)).foregroundStyle(IronTheme.secondaryText) }
        }
        Text(label).font(.footnote).foregroundStyle(IronTheme.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
}
```

## 17. Retired components and banned techniques

Do not reintroduce any of these, or an equivalent under a new name.

| Removed | Use instead |
| --- | --- |
| `IronCard`, `IronScreenBackground`, `IronModalBackground` | `List`/`Form` with `Section` |
| `IronSectionTitle` | `Section` header |
| `IronHairline` | `Divider` |
| `IronDestinationHeader`, `ironDestinationScreen` | `.navigationTitle` + `ToolbarItem` |
| `IronMetricTile` | Metric chips inside one aggregate surface |
| `IronPrimary/Secondary/IconButtonStyle` | `.borderedProminent`, `.bordered`, glass styles |
| `IronCompact/Choice/UtilityPillButtonStyle` | `Picker`, or `.bordered` + `.capsule` |
| `IronPopupMenu`, `IronPopupAction` | `Menu`, `swipeActions`, `contextMenu` |
| `IronEffortCarousel` | `EffortRatingGraph` |
| `IronDateTimeButton` | `DatePicker` |
| `WatchCard`, `WatchActionButtonStyle` | watchOS `List`/`Section`, `.bordered` |
| The rest-timer radial dial modal | The inline rest-length ruler (backlog B3) |
| The RPE wheel sheet | Rising RPE bars (backlog B5) |

Banned techniques: `toolbarBackground`, `presentationBackground`, `design: .rounded`,
hard-coded colors for chrome, `GeometryReader` chart plotting, resetting entrance state in
`onDisappear`, `DragGesture(minimumDistance: 0)` on anything inside a scroll view, emoji in UI,
and gradients as decoration (gradients are allowed only inside effort bars).

## 18. Review checklist

- [ ] Light and dark: no hard-coded colors, and every color maps to a §3 role.
- [ ] Numbers use `ironMetric`; units are smaller and secondary; no rounded fonts.
- [ ] One primary action per surface; 44 pt targets everywhere.
- [ ] System chrome untouched (no toolbar or presentation backgrounds).
- [ ] Glass only on floating layers.
- [ ] Motion uses `IronMotion` plus `preferred`; Reduce Motion falls back to fades.
- [ ] Haptics and sounds match §12.
- [ ] Dynamic Type at AX sizes, VoiceOver labels and values, adjustable actions.
- [ ] Vertical scrolling works when a drag starts on any custom control.
- [ ] Final scroll content clears the tab bar and workout accessory
      (`floatingWorkoutBottomClearance`).
- [ ] Copy follows §13 (Workout, not routine; ×, −; Title Case buttons).
- [ ] Apple Health rule (§15.10) unaffected.
