# Iron Design System

Iron should feel like a private strength-training app designed by Apple: direct,
calm, data-rich, and native to iPhone and Apple Watch. Hevy remains a functional
reference for workout logging density, but Iron does not reproduce Hevy's visual
identity and does not use Material design vocabulary.

The primary references are Apple's Human Interface Guidelines for
[layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[color](https://developer.apple.com/design/human-interface-guidelines/color),
[typography](https://developer.apple.com/design/human-interface-guidelines/typography),
[materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[navigation](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search),
[buttons](https://developer.apple.com/design/human-interface-guidelines/buttons),
[motion](https://developer.apple.com/design/human-interface-guidelines/motion), and
[charts](https://developer.apple.com/design/human-interface-guidelines/charts).

## Product principles

1. Prefer the native SwiftUI control before creating an Iron-specific control.
2. Use Apple semantic colors and text styles; never recreate separate light and
   dark palettes in a screen.
3. Let the system own chrome. Never paint a toolbar, search field, sheet, or list
   background: an opaque fill flattens the bar at rest and suppresses scroll-edge
   and Liquid Glass behavior. Content sits on `List`/`Form` grouped surfaces.
4. Reserve Liquid Glass for layers that float above changing content — the active
   workout accessory, the Home weekly hero, and the logger summary pill. Glass is
   depth, not another stacked card.
5. Use tint sparingly and give it meaning. System blue means actions, workouts,
   selection, and completed sets. Metric roles distinguish sets, volume, time,
   effort, records, and body measurements. Warning and destructive colors retain
   their status meanings; muscle-group tags stay neutral.
6. Preserve data density during a workout. Native does not mean sparse.
7. Every animation must explain navigation, continuity, or a state change.
8. Respect Dynamic Type, VoiceOver, Reduce Motion, safe areas, and a 44-point
   minimum touch target.

## Semantic foundation

Production views consume `IronTheme`, whose roles map to adaptive UIKit colors.

| Iron role | Apple semantic role | Use |
| --- | --- | --- |
| `accent` / `accentSoft` | `systemBlue` / soft blue | Navigation, actions, workouts, selection, completed-set checks/badges/tints |
| `metricSets` / `metricSetsContainer` | `systemOrange` / soft orange | Set counts and warm-up sets |
| `metricVolume` / `metricVolumeContainer` | `systemGreen` / soft green | Weight moved (volume) |
| `metricTime` / `metricTimeContainer` | `systemCyan` / soft cyan | Duration, rest countdown, and rest connectors |
| `metricEffort` / `metricEffortContainer` | `systemPink` / soft pink | RPE and session effort |
| `metricRecord` / `metricRecordContainer` | `systemYellow` / soft yellow | Personal records and trophies |
| `metricBody` / `metricBodyContainer` | `systemPurple` / soft purple | Body measurements |
| `success` | `systemGreen` | Sync status dots and success messages only |
| `warning` | `systemOrange` | Attention and overtime |
| `danger` | `systemRed` | Destructive actions and errors |
| `background` | `systemGroupedBackground` | Full-screen editors that cannot use a `List` |
| `surface` | `secondarySystemGroupedBackground` | Only where a `Section` row is impossible |
| `raisedSurface` | `tertiarySystemGroupedBackground` | Nested low-emphasis surfaces |
| `field` | `secondarySystemFill` | Input and compact control backgrounds |
| `tertiaryFill` | `tertiarySystemFill` | Current-set capsule fields and rest ring tracks |
| `outline` | `separator` | Hairlines only, not card borders |
| text roles | `label`, `secondaryLabel`, `tertiaryLabel` | Text hierarchy |

`List`, `Form`, and sheets receive no explicit background. `IronTheme.surface` and
`raisedSurface` are for the few surfaces the platform cannot express — prefer a
`Section` row every time.

The six metric containers use their adaptive system hue at 0.18 opacity. Keep
metric colors on numbers, short labels, icons, and soft containers. Cyan and yellow
foreground text on light backgrounds must be semibold or bold and must never be
used for body copy. Units use smaller secondary text. Do not use green to paint a
completed set: completion is blue. Legacy `successContainer`, `successControl`,
and `onSuccessContainer` remain for source compatibility during migration and must
not be used by new set-row treatments.

Muscle-group tags use `secondarySystemFill` with `secondaryLabel` text, or plain
secondary text. Do not assign colors to individual muscle groups.

Do not hard-code black, white, gray, or RGB values for application chrome.
Exercise diagrams and user photos are the exceptions: they use fixed media roles
because their contrast must not change with appearance.

## Retired Iron components

The following Iron primitives were removed in favor of the platform control. Do not
reintroduce them or an equivalent under a new name.

| Removed | Use instead |
| --- | --- |
| `IronCard`, `IronScreenBackground`, `IronModalBackground` | `List`/`Form` with `Section` |
| `IronSectionTitle` | `Section` header, or `Text` in a footer |
| `IronHairline` | `Divider` |
| `IronDestinationHeader`, `ironDestinationScreen` | `.navigationTitle` plus `ToolbarItem` |
| `IronMetricTile` | `LabeledContent` rows or metric columns inside one aggregate section |
| `IronPrimaryButtonStyle`, `IronSecondaryButtonStyle`, `IronIconButtonStyle` | `.borderedProminent`, `.bordered`, `.borderless` |
| `IronCompactPillButtonStyle`, `IronChoicePillButtonStyle`, `IronUtilityPillButtonStyle` | `Picker`, or `.bordered` with `.buttonBorderShape(.capsule)` |
| `IronKeyboardAccessoryButtonStyle` | Plain `Button` in a `.keyboard` toolbar |
| `IronPopupMenu`, `IronPopupAction` | `Menu`, `swipeActions`, `contextMenu` |
| `IronEffortCarousel` | `Picker` for RPE; the completion editor uses the ten-segment effort control |
| `IronDateTimeButton` | `DatePicker` |
| `WatchCard`, `WatchActionButtonStyle` | watchOS `List`/`Section`, `.bordered` buttons |
| Custom `Canvas`/`Path` chart drawing | Swift Charts |
| `presentationBackground`, `toolbarBackground` | Nothing — let the system render it |

The shared foundation stays small: the semantic palette, `Font.ironMetric`, the
Liquid Glass modifiers, `IronMotion`, completion/entrance feedback helpers,
`IronRestRing`, and the few sheets that carry more
explanation than an `.alert` can (`IronUtilitySheet`, `IronConfirmationSheet`,
`IronStatusSheet`, `IronDateTimePickerSheet`, `IronDurationPickerSheet`).
`UI/Components/IronSessionStrip.swift` supplies the reusable full and compact
session timeline; it owns no workout persistence or timer logic.

## Geometry and spacing

| Role | Token | Value |
| --- | --- | ---: |
| Minimum control height | `IronTheme.controlHeight` | 44 pt |
| Icon button | `IronTheme.iconButtonSize` | 44 x 44 pt |
| Grouped section radius | `IronTheme.cornerRadius` | 12 pt |
| Field/control radius | `IronTheme.compactCornerRadius` | 10 pt |
| Hero/glass radius | `IronTheme.heroCornerRadius` | 22 pt |
| Screen gutter | `IronTheme.horizontalPadding` | 16 pt |
| Floating workout clearance | `IronTheme.floatingWorkoutBottomClearance` | 152 pt |

Capsules are reserved for compact status controls, prominent toolbar actions,
the floating active-workout accessory, the rest pill, and the workout logger's
current-set fields. Completed rows use a faint accent fill in a continuous rounded
rectangle at the existing inset. Other fields, cards, rows, and full-width buttons use continuous
rounded rectangles. Grouped sections do not get decorative outlines or shadows.

## Typography

- Use San Francisco through SwiftUI semantic styles.
- Root titles use `largeTitle` with bold weight.
- Navigation titles use `headline` in the native inline bar.
- Screen section titles use `title3` semibold; Settings/Form section labels can
  use `footnote` or `caption` with secondary color.
- Body copy uses `body` or `subheadline`; supporting metadata uses `caption`.
- Every metric number — weights, reps, volume, durations, timers, counts, and RPE —
  uses SF Pro bold with fixed-width digits. Dense rows may use semibold. Use
  `.font(.ironMetric(.title2))` or `.font(.ironMetric(.body, weight: .semibold))`;
  the helper keeps the semantic style and applies `.monospacedDigit()`. Do not use
  rounded font design.
- Units such as “lb” and “kg” use a smaller semantic style and secondary text.
- Changing metric values use `.contentTransition(.numericText())` with
  Reduce-Motion-aware `IronMotion` animation.
- Avoid custom point sizes unless a chart, timer, or compact workout grid has a
  measured requirement.
- At accessibility text sizes, exercise names wrap and muscle/equipment labels
  stack instead of competing for one truncated line. Keep the compact metadata
  row at standard text sizes.

## Navigation and tabs

The app has five stable top-level tabs, in this order, and preserves each tab's
navigation state:

- **Home:** glass weekly hero, inline activity calendar, body measurements, pinned
  exercise charts, and recent training. Body measurements live here, not in Settings.
- **History:** completed workouts, exercise history, trends, records, and muscle load.
- **Workout:** quick start, saved workouts, folders, and workout sharing.
- **Exercises:** searchable movement library, instructions, and two independent
  filter menus — one for muscle, one for equipment. Never combine them in one menu.
- **Settings:** appearance, training defaults, connected services, privacy, backups,
  imports, exports, licenses, and developer tools.

Use `NavigationStack`, `.navigationTitle`, standard back behavior, `ToolbarItem`,
and the native `TabView`. Navigation bars and `.searchable` fields keep the system
material so they read as glass at rest and adopt scroll-edge behavior on scroll —
they must never be given a `toolbarBackground` fill. Do not draw a fake circular
back button. A custom header
is allowed only when an interactive full-screen workout or editor cannot be
expressed by the platform bar; it must still use 44-point controls and standard
title geometry.

The active-workout compact surface uses the native tab-bar accessory on supported
systems. The compatibility fallback may use Liquid Glass because it floats above
content and performs navigation. On iOS 26.1 and newer the native tab bar minimizes on downward
scrolling: the accessory adopts its inline layout between the current destination and
Settings, then returns to the full-width layout when the bar expands. The expanded
accessory contains resume, expand, and discard actions.

## Home and History

Home keeps its sections and their order. The weekly hero has three metric columns:
Workouts in accent, Sets in `metricSets`, and Volume in `metricVolume`. Each uses a
32-point soft-filled icon chip and bold monospaced values. Daily bars are accent on
a neutral track; today's label is bold accent. The “Best day …” caption highlights
its value in `metricVolume`. Resume/Start stays unchanged. Add a trailing flame
streak chip in accent soft fill to “Last 4 Weeks” when a streak exists. Calendar
trained days remain accent-filled.

History rows show the workout title, date and neutral muscle metadata, followed by
a metric line such as “1h 02m · 14 sets · 9,860 lb” with duration, sets, and volume
in their metric roles. Trailing PR-count trophies use `metricRecordContainer`;
session effort, when rated, uses `metricEffortContainer` with an “RPE 8” label.
Reuse `IronSessionStrip` in compact size. Group by week with workout-count and
volume totals in accent and `metricVolume` when the existing fetches support it.

## Controls

- Use native `Toggle` with `.switch` and the app tint.
- Use native `Menu` and `Button(role:)` for pull-down actions.
- Use `Picker` or a system wheel for ordered choices such as effort/RPE and 1RM
  limits. The active rest timer is the deliberate exception: its compact radial
  dial supports direct 15-second adjustment with haptic and audio notches. Session
  effort in the completion editor is the other exception: ten directly adjustable
  segments with selection feedback and an accessibility adjustable action.
- Primary actions use `.borderedProminent`. Limit each surface to one visually
  dominant action.
- Secondary actions use `.bordered` or a plain text toolbar action.
- Destructive actions use the `.destructive` role and system red.
- Text fields use the correct numeric keyboard and may expose a trailing or keyboard-
  accessory utility such as the plate calculator.
- Use SF Symbols with familiar meanings. Do not put every symbol in a colored tile.

## Grouped content

- Prefer `List`, `Form`, `Section`, `LabeledContent`, and standard separators for
  settings and dense data.
- One rounded grouped surface may contain several related rows. Do not wrap each row
  in a card and do not nest cards.
- Personal summaries may use one aggregate surface, but their metrics remain columns
  or labeled rows inside that surface rather than separate nested tiles.
- Saved workouts appear as compact rows in one grouped surface. The row opens detail,
  the prominent trailing action starts or resumes, and the system menu owns edit,
  duplicate, and delete.
- A summary card is appropriate for one meaningful aggregate: the workout headline,
  a weekly overview, a Health connection state, or a personal record.
- Use separators as structure, not borders around every surface.

## Sheets, dialogs, and search

- Use native sheets with system detents and drag indicators.
- Put complex sheet content in a `NavigationStack` with Cancel/Done toolbar actions.
- Use `.confirmationDialog` or `.alert` for simple destructive decisions. A custom
  confirmation sheet is reserved for explanations that genuinely need more room.
- Use `.searchable` for searchable collections rather than drawing a custom search field.
- Date and time selection uses `DatePicker`. Durations use `IronDurationWheel`, the
  system dual-wheel minute/second picker.
- Never impose a custom modal corner radius or `presentationBackground`.

## Active workout behavior

- The expanded workout is an edge-to-edge content surface with a compact native-style
  top bar, collapsible session summary, and continuous exercise sections.
- Minimize slides the workout toward the native tab accessory. Reduce Motion replaces
  this with a brief fade.
- The session summary collapses as a separate fixed-size region; metric labels never
  squash or scale during collapse.
- Returning the exercise log to its true scroll top always restores the complete
  sync, duration, volume, set-count, and front/back muscle-map summary. Scrolling
  into the log replaces it with the full-width glass summary pill.
- A named saved workout remains named throughout the active and completed workout.
- Weight and repetition fields accept only valid numeric input. Focusing a weight field
  shows the plate-calculator control beside the keyboard-dismiss control.
- Keep the refined table columns (Set · Previous · lb · Reps · RPE · ✓) and
  `InlineWorkoutSetLayout` geometry. Row height, padding, width, and column positions
  never change between states:
  - **Done:** a leading accent sweep settles to a faint 0.10–0.14 accent tint in a
    continuous rounded rectangle. Weight/reps become plain bold numbers without
    field fills. The circular set badge has accent soft fill and an accent number;
    RPE uses `metricEffort`. The check is `checkmark.circle.fill` in accent with a
    white checkmark. Never use a green completed-set wash.
  - **Current:** the first incomplete set uses a raised `secondarySystemFill`-like
    row surface, capsule fields on `tertiarySystemFill`, an accent-ring badge and
    check, and an RPE field on `metricEffortContainer`.
  - **Upcoming:** secondary values, neutral filled badge, and neutral-ring check.
  - **Warm-up:** “W” in `metricSets` on `metricSetsContainer`.
  Completion always includes a check and badge change as well as color. Preserve
  numeric input sanitizing, plate calculator, RPE picker, duration sets, inline
  set timer, accessibility labels, and all existing actions.
- Set deletion is a trailing swipe reveal. The red action expands behind the full row
  as the row moves and appears only during the swipe.
- The active rest timer appears below the sets of the exercise that triggered it as a
  full-width rounded pill on `metricTimeContainer`. Its leading `IronRestRing`
  drains as time passes: a `tertiarySystemFill` track, `metricTime` progress,
  approximately 4-point stroke, and round caps. Remaining time is bold monospaced
  `metricTime`, with a secondary “Rest of 2:30” caption. Four separate 44-point
  circular controls use neutral fill: minus 15 seconds, pause/resume, plus 15
  seconds, and skip. Share `IronTheme.iconButtonSize` and distribute the controls
  evenly. Preserve the shared radial dial, timer store, and all actions.
  The radial editor scrubs locally and commits on
  release so notification, Watch, and Live Activity updates never block dragging.
- The logger summary retains Duration / Volume / Sets and its muscle map. Labels
  use time / volume / sets colors; values use bold monospaced primary text and
  `.contentTransition(.numericText())`.
- The session muscle map highlights only muscles represented by completed sets;
  primary and secondary muscles use distinct emphasis and update during the workout.
- Exercise actions are Replace, Superset, and Remove. Reordering is direct manipulation:
  touch and hold the exercise title, then drag it to another exercise position.
- Exercise removal and workout discard require confirmation.

## Saved workouts and sharing

- “Workout” is the user-facing term for a reusable saved workout; internal model names
  such as routine or plan must not leak into copy.
- Saved workouts may be grouped into user-created folders without changing their stable
  identifiers or history links.
- Import and export use a documented, versioned representation. Imported workouts are
  validated before persistence; sharing exports a portable file through the system share
  sheet and importing works from Files or another app's share sheet.
- Starting a named saved workout keeps that name on the active-workout accessory, in the
  logger, and in history.

## Workout completion

The completion editor contains every established field and action: workout name,
start/end or duration, session effort, notes, media, saved-workout update preference,
Health export state, exercise and set summary, save, and discard. The hierarchy uses
grouped Apple sections rather than nested cards or an overlay on the logger.

1. Header: workout name, date/time range, and a small accent circle icon.
2. One metrics grid, three columns by two rows: Duration (`metricTime`), Volume
   (`metricVolume`), Sets (`metricSets`), Exercises (`accent`), Avg RPE
   (`metricEffort`), and Records (`metricRecord`). Labels are primary text; values
   are bold monospaced in the metric role. Keep the grid legible at Dynamic Type sizes.
3. Session strip: completed sets ordered by `WorkoutSet.completedAt`, grouped into
   contiguous exercise runs with small gaps. Thin rounded bars scale by weight ×
   reps; duration/bodyweight sets use a constant fallback. Warm-ups use `metricSets`,
   `isPersonalRecord` sets use `metricRecord`, and other sets use accent. Thin soft
   `metricTime` connectors represent rests, without claiming precise rest duration.
   Short exercise labels sit below groups, followed by a legend. Supply an accessible
   summary label. `IronSessionStrip` accepts plain groups with relative volumes in
   0...1 and kinds `warmUp`, `normal`, or `record`; callers own ordering, volume
   normalization, fallback values, and record classification. Its compact size
   omits labels and legend. Long strips scroll horizontally.
4. Effort: “How hard was it?” uses ten rounded segments bound to `sessionEffort`
   (0 = not rated). Tap or drag to set, fill left to right in `metricEffort`, and
   show a trailing label such as “8 · Hard”: 1–3 Easy, 4–6 Moderate, 7–8 Hard,
   9–10 All Out. Use selection haptics per step and VoiceOver increment/decrement.
5. Records: trophy icons in `metricRecordContainer` circles and a list of this
   workout's PR sets. Hide the section when there are none.
6. Keep the saved-workout update toggle and Apple Health row, plus notes, media,
   exercise/set details, Save, and Discard.

Metrics rise with opacity and an 8-point offset, staggered about 40 ms. Session
bars grow from their baseline per exercise; effort segments fill left to right;
trophies bounce with `.symbolEffect(.bounce)`. Reduce Motion replaces these spatial
effects with a short fade. Decorative motion must never delay Save or dismissal.

## Data visualization

- All charts use Swift Charts. Hand-drawn `Canvas`, `Path`, or `GeometryReader`
  plotting and third-party chart libraries are not permitted.
- The session strip is a deliberate plain-stack exception: rounded shapes in
  `HStack`/`VStack` may render its ordered mini timeline, or use Swift Charts if
  readable. Do not use `GeometryReader` plotting for it.
- Selection uses `chartXSelection`; axes use `AxisMarks` with automatic tick counts.
- Data marks are the most prominent element; axes and framing are secondary.
- Tapping or horizontally scrubbing selects the nearest point and shows exact period,
  value, workout count, sets, repetitions, duration, volume, and recorded effort.
- Detail appears outside the plot or in reserved chart space and never obscures marks.
- Vertical gesture intent belongs to the containing scroll view.
- VoiceOver exposes chart summary, selected value, and adjustable previous/next navigation.
- Do not encode meaning with color alone.

## Live Activity and Apple Watch

- Live Activities stay within the system container. Use one compact identity row, one
  exercise/set row, a native progress indicator, and one result or timer/control row.
- State advances from active set to a ten-second completion confirmation, then to rest
  countdown and the next set. All states remain legible at the system's compact sizes.
- The Lock Screen and expanded Dynamic Island show elapsed workout time, workout name,
  exercise, next set number/count and prescription, completed/total sets, rest progress,
  a live countdown, and native App Intent controls for −15 seconds, +15 seconds, and Skip.
- Declare `supplementalActivityFamilies([.small])` so the activity reaches the Apple
  Watch Smart Stack, and give `.small` its own layout: one identity line, the live
  value or countdown, and Skip only when rest is actually running.
- The Watch app targets watchOS 10 and uses `NavigationStack` with `List`/`Section`
  throughout. Set logging is a grouped form of `Picker` rows plus a prominent
  Complete Set control; the rest timer rides in a `safeAreaInset` glass capsule.
- Watch controls use native watchOS components, Digital Crown interaction where useful,
  immediate persistence, and truthful reachable/queued/offline status. No tonal card
  containers or per-muscle rainbow tinting.

## Home Screen widget

- The Last Workout widget uses `containerBackground(.fill.tertiary, for: .widget)`
  and supports `.systemSmall` and `.systemMedium`. No solid accent slab behind the
  statistic, and no white-on-accent text.

## Motion and feedback

- Prefer platform navigation and presentation transitions.
- Use the `IronMotion` tokens rather than ad-hoc durations: `IronMotion.snappy` for
  selection and value changes, and the spring tokens for direct manipulation.
- Haptics reinforce set completion, deletion, and discrete picker changes.
- Never delay dismissal solely to play a decorative animation.
- Every custom animation reads `accessibilityReduceMotion` and uses
  `IronMotion.preferred(_:reduceMotion:)`. Reduce Motion swaps spatial motion for
  a short fade; haptics still play. This includes matched geometry, charts,
  entrances, session strips, rings, and workout collapse. Gate symbol bounces and
  spatial transitions as well.

| Moment | Behavior | Shared API / token |
| --- | --- | --- |
| Complete a set | Leading accent sweep, then faint settled tint; check pops and swaps; fields flatten | `.ironSetCompletion(isComplete:)`, `IronMotion.snappy` (spring 0.32 / 0.82), `.symbolEffect(.bounce)`, `.contentTransition(.symbolEffect(.replace))`, success sensory feedback |
| Counters | Volume, sets, duration, and rest numbers roll | `.contentTransition(.numericText())` with preferred `IronMotion.snappy` |
| Rest starts | Pill inserts below the triggering set | Move from top + opacity, preferred `IronMotion.collapse` (spring 0.42 / 0.86); fade for Reduce Motion |
| Rest ends | Ring pulses once, pill removes, next set raises its fields | Phase/keyframe animation; light-impact sensory feedback; fade for Reduce Motion |
| Next set becomes current | Field backgrounds fade in after about 0.12 seconds | Preferred `IronMotion.snappy.delay(0.12)` |
| Delete set | Existing swipe, then row collapse | Preferred `IronMotion.collapse`; opacity + scale 0.96 transition, opacity only for Reduce Motion |
| Open/minimize workout | Preserve existing matched/zoom continuity | Matched transition source / zoom where available; fade for Reduce Motion |
| Workout complete | Metrics fade/rise 8 points at 40 ms intervals; session bars grow per exercise; trophy bounces | `.ironStaggeredEntrance(index:)`, `IronSessionStrip`, preferred tokens; fade without stagger for Reduce Motion |
| Effort | Segments fill while dragging | Preferred `IronMotion.snappy`, selection sensory feedback per step |
| Charts | Bars grow from zero on first appearance | Swift Charts with preferred animation; fade for Reduce Motion |
| Tabs/scroll | Native large titles and tab minimization | Existing `.tabBarMinimizeBehavior(.onScrollDown)` where supported |

`IronMotion.fade` is ease-in-out over 0.18 seconds. `IronRestRing(progress:)` accepts
the remaining fraction (1 = full, 0 = elapsed); the caller owns timer logic and may
hide the ring from VoiceOver when the pill already announces the countdown.

## Exercise media and attribution

- Render movement art with aspect-fit and enough inset to keep the full pose visible.
- Scale the art just enough to fill its circular canvas without clipping the person,
  equipment, or any embedded attribution at any supported thumbnail size.
- Do not remove, paint over, or crop attribution embedded in third-party media.
- Do not repeat a separate watermark badge over every thumbnail. Surface source,
  provenance, and license information in Settings > Licenses & Attributions.
- Keep remotely loaded third-party media out of the git repository. After the first
  successful fetch, persist Gym Visual / ExerciseDB GIFs in the app’s on-device
  ExerciseMedia store and never evict them. Prefetch missing files on later launches
  over inexpensive networks so the library works offline.

## Review checklist

- Verify light and dark appearance with no hard-coded surface or text color leaks.
- Verify standard back behavior, swipe-back, tab state preservation, and sheet dismissal.
- Verify Dynamic Type at accessibility sizes, VoiceOver labels/order, Reduce Motion,
  contrast, and 44-point targets.
- Verify the final scroll item clears the tab bar and active-workout accessory.
- Verify numeric keyboards, plate calculator, timer controls, set swipe deletion,
  completion effort, Health sync, Watch continuity, import/export, and Live Activity.
- Compare every new control with the closest native iOS control before approving a
  custom implementation.
- Verify no screen sets `toolbarBackground`, `presentationBackground`, or
  `scrollContentBackground(.hidden)` with a custom fill.
- Verify no reintroduced equivalent of a component in “Retired Iron components”.
