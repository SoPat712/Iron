# Iron Cupertino Design System

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
5. Use tint sparingly. Blue means action or selection, green means completion,
   orange means warning or attention, and red means destructive or failed.
6. Preserve data density during a workout. Native does not mean sparse.
7. Every animation must explain navigation, continuity, or a state change.
8. Respect Dynamic Type, VoiceOver, Reduce Motion, safe areas, and a 44-point
   minimum touch target.

## Semantic foundation

Production views consume `IronTheme`, whose roles map to adaptive UIKit colors.

| Iron role | Apple semantic role | Use |
| --- | --- | --- |
| `accent` | `systemBlue` | Navigation, selected controls, primary actions |
| `success` | `systemGreen` | Completed sets and successful operations |
| `warning` | `systemOrange` | Attention and overtime |
| `danger` | `systemRed` | Destructive actions and errors |
| `background` | `systemGroupedBackground` | Full-screen editors that cannot use a `List` |
| `surface` | `secondarySystemGroupedBackground` | Only where a `Section` row is impossible |
| `raisedSurface` | `tertiarySystemGroupedBackground` | Nested low-emphasis surfaces |
| `field` | `secondarySystemFill` | Input and compact control backgrounds |
| `outline` | `separator` | Hairlines only, not card borders |
| text roles | `label`, `secondaryLabel`, `tertiaryLabel` | Text hierarchy |

`List`, `Form`, and sheets receive no explicit background. `IronTheme.surface` and
`raisedSurface` are for the few surfaces the platform cannot express — prefer a
`Section` row every time.

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
| `IronMetricTile` | `LabeledContent` rows |
| `IronPrimaryButtonStyle`, `IronSecondaryButtonStyle`, `IronIconButtonStyle` | `.borderedProminent`, `.bordered`, `.borderless` |
| `IronCompactPillButtonStyle`, `IronChoicePillButtonStyle`, `IronUtilityPillButtonStyle` | `Picker`, or `.bordered` with `.buttonBorderShape(.capsule)` |
| `IronKeyboardAccessoryButtonStyle` | Plain `Button` in a `.keyboard` toolbar |
| `IronPopupMenu`, `IronPopupAction` | `Menu`, `swipeActions`, `contextMenu` |
| `IronEffortCarousel` | `Picker` |
| `IronDateTimeButton` | `DatePicker` |
| `WatchCard`, `WatchActionButtonStyle` | watchOS `List`/`Section`, `.bordered` buttons |
| Custom `Canvas`/`Path` chart drawing | Swift Charts |
| `presentationBackground`, `toolbarBackground` | Nothing — let the system render it |

What remains in `SwiftUISupport.swift` is deliberately small: the semantic palette,
the two Liquid Glass modifiers, `IronMotion`, and the few sheets that carry more
explanation than an `.alert` can (`IronUtilitySheet`, `IronConfirmationSheet`,
`IronStatusSheet`, `IronDateTimePickerSheet`, `IronDurationPickerSheet`).

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

Capsules are reserved for inherently compact status controls, prominent toolbar
actions, and the floating active-workout accessory. Fields, cards, rows, and
full-width buttons use continuous rounded rectangles. Grouped sections do not get
decorative outlines or shadows.

## Typography

- Use San Francisco through SwiftUI semantic styles.
- Root titles use `largeTitle` with bold weight.
- Navigation titles use `headline` in the native inline bar.
- Screen section titles use `title3` semibold; Settings/Form section labels can
  use `footnote` or `caption` with secondary color.
- Body copy uses `body` or `subheadline`; supporting metadata uses `caption`.
- Numeric workout values may use `monospacedDigit()` but keep the surrounding
  semantic text style.
- Avoid custom point sizes unless a chart, timer, or compact workout grid has a
  measured requirement.

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

## Controls

- Use native `Toggle` with `.switch` and the app tint.
- Use native `Menu` and `Button(role:)` for pull-down actions.
- Use `Picker` or a system wheel for ordered choices such as effort/RPE and 1RM
  limits. The active rest timer is the deliberate exception: its compact radial
  dial supports direct 15-second adjustment with haptic and audio notches.
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
- Completing a set paints one rounded semantic-green wash from edge to edge inside
  its exercise surface and highlights every editable/control value without changing
  row padding, width, or column geometry; completion is never communicated by color alone.
- Set deletion is a trailing swipe reveal. The red action expands behind the full row
  as the row moves and appears only during the swipe.
- The active rest timer appears above the exercise that triggered it as a
  full-width Liquid Glass status pill. Its four separate compact controls share
  one geometry token and are distributed evenly: minus 15 seconds, pause/resume,
  plus 15 seconds, and stop. The radial editor scrubs locally and commits on
  release so notification, Watch, and Live Activity updates never block dragging.
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

## Data visualization

- All charts use Swift Charts. Hand-drawn `Canvas`, `Path`, or `GeometryReader`
  plotting and third-party chart libraries are not permitted.
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
- Read `accessibilityReduceMotion` for custom matched-geometry, chart, carousel, and
  workout-collapse animation.

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
