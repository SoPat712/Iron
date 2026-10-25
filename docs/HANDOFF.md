# Iron: handoff to the next lead agent

Written 2026-10-25 by the previous lead (Claude) for Codex or any agent taking over. It holds
the mission, the current state, what the owner wants and how they work, what's left (in priority
order), every UI idea discussed so far, and two ready-to-paste prompts.

Read with: [`AGENTS.md`](../AGENTS.md), [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md) (how everything
looks) and [`DESIGN_BACKLOG.md`](DESIGN_BACKLOG.md) (B1–B10 specs, lanes, build commands).

---

## Prompt 1: implement the remaining work (paste into `codex exec`)

```
You are working on Iron, a SwiftUI strength-training app (iPhone + Apple Watch) in this repo.
Read AGENTS.md, docs/DESIGN_SYSTEM.md (all of it), docs/DESIGN_BACKLOG.md §0, and
docs/HANDOFF.md ("Task list") first. They are the spec.

Implement the tasks in docs/HANDOFF.md "Task list" marked [CODEX], in order, starting with T1.
For each task: read the files named, make the change following DESIGN_SYSTEM.md exactly
(IronTheme roles, Font.ironMetric, IronMotion + Reduce Motion, 44 pt targets, VoiceOver labels),
and keep all existing persistence, Watch sync, Live Activity and Apple Health behavior.
Never export imported workouts to Health.

Do not commit, push, stash, reset or checkout. Don't touch reference-material/.
Build after each task with the simulator command in DESIGN_BACKLOG.md §0.3 (if the sandbox
blocks xcodebuild, say so once and continue with careful compile-correct code).
Finish with at most 25 lines: per task, the files changed, what you did, and what you could not verify.
```

## Prompt 2: carry on as the lead/orchestrator (paste into a fresh agent session)

```
You are the new lead for Iron (SwiftUI, iPhone + Watch), taking over from a previous lead.
Read docs/HANDOFF.md fully, then AGENTS.md, docs/DESIGN_SYSTEM.md and docs/DESIGN_BACKLOG.md.

Your job: (1) keep shipping the owner's goals: finish the app and keep its own Apple-native
design ("if Apple made a strength tracker", not Hevy); (2) work the Task list in HANDOFF.md;
(3) the owner approves visual design before it's built, so propose designs first (describe them
precisely, or mock them in SwiftUI previews and screenshots), and get a yes; (4) split
implementation into parallel lanes with exclusive file ownership (DESIGN_BACKLOG §0.1), run
workers, review every diff yourself, build, install on the owner's iPhone (§0.3 commands),
then commit per lane; (5) keep HANDOFF.md, DESIGN_SYSTEM.md and DESIGN_BACKLOG.md current: log
every owner decision and every new idea.

Owner rules: ask before booting a simulator (other apps use the CPU). Push only to the fork's
`origin` (SoPat712/Iron) main, never upstream, and only when asked. Never enter credentials;
the owner handles Apple ID and trust prompts. Never export imported workouts to Apple Health.
Be fast: the owner tests on their phone daily and wants builds on it quickly.
```

---

## 1. Mission

1. **Finish building Iron** into a daily-use strength tracker that replaces Hevy for the
   owner. They have already imported their Hevy history.
2. **Give it its own design identity**, Apple-native: "imagine if Apple made a workout
   tracker". It must stop looking like a Hevy copy. The full system is in `DESIGN_SYSTEM.md`.

## 2. Current state (as of commit `c3f401a` on `main`)

| Area | State |
| --- | --- |
| Design system | Documented (`DESIGN_SYSTEM.md`), including §16, a recipe for restyling a screen from a screenshot |
| Iron blue refresh: metric colors, SF Pro bold numerals, motion, original sounds | Shipped |
| Apple Health | Exports **only Iron-completed** workouts (phone or Watch); imports are never exported; durable retry |
| Hevy CSV import | Fast, off the main thread, progress overlay, tagged `importSource = "hevy"` |
| Logger: focused current-set editor (Logger B), blue completed fill | Shipped |
| B1 swipe-overlap fix, B2 session bar, B3 rest chip + ruler (dial removed), B4 soft set-type fills, B5 RPE bars | Shipped in `d6cdeb5`, **visually unverified** |
| B6 exercise detail (inline progress, history, target map, tooltip) | Shipped in `1ad5e22`, **visually unverified**; hold-and-drag tooltip not done (T3) |
| Recency-first exercise ordering (all lists, search, pickers, Watch) | Shipped in `8387ef4` |
| B8 Workout tab (Recent Workouts + Repeat), B9 Home redesign | Shipped in `c3f401a`, **visually unverified**; empty-state button bug (T1) |
| On the owner's iPhone | Build of `c3f401a` installed 2026-10-22 |
| Pushed to fork | **No.** Commits `3ab7e2f..c3f401a` are local only (push when the owner asks) |
| Unit tests | Exist (`IronTests/`), but `xcodebuild test` hung in this environment, so none ran recently |

## 3. The owner: preferences and how they work

- Approves **visual design personally before it's built**. Show options; they choose.
- Liked: the rest timer inside the exercise; effort and RPE as their own color; the
  workout-complete recap; rows that **fill** blue on completion; today's **−15 / +15** rest
  strip; the session bar; Logger B's big steppers; the session chart with labels and visible
  rests.
- Rejected: stylized themes (Forge, Plate, Logbook); orange accent; **SF Rounded** ("cartoonish");
  the radial rest-timer modal ("disgustingly bad"); anything that reads as "Hevy merged with
  Liquid Glass"; beeps; graphs that look like random lines.
- Wants: Apple-quality animation everywhere; better sounds; speed (build to the phone fast);
  orchestration with parallel Codex workers. They are a capable engineer.
- Git: works on `main` of the fork `origin` (SoPat712/Iron). Commit per feature or lane. Push
  only when asked. Never push upstream. `reference-material/` is untracked on purpose; never add it.
- Phone: "Josh's iPhone", UDID `00008150-001914903E69401C`, bundle `com.joshpatra.IronDev`,
  personal-team signing (`-allowProvisioningUpdates`). The free-team profile expires after
  about 7 days; if launch fails with a profile error, rebuild and reinstall.
- Ask before booting a simulator.

## 4. How the previous lead orchestrated (copy this)

- Workers: `codex exec -m gpt-6-astra -c model_reasoning_effort='"xhigh"' -c
  service_tier='"priority"' -c approval_policy='"never"' -s workspace-write --add-dir /tmp
  --add-dir /private/tmp -C <repo> -o <result.md> - < <brief.md>`.
- **`workspace-write` cannot run xcodebuild** (`sandbox_apply: Operation not permitted`).
  Either the lead builds after workers finish, or the owner allows `-s danger-full-access`.
- Each brief: role, lane, exact items (point at backlog IDs), files owned exclusively, "do not
  commit", "other agents are editing other files", and a short final report format.
- After workers finish: read each report, review the diffs (look for hard-coded colors, rounded
  fonts, `DragGesture(minimumDistance: 0)` inside scroll views, `onDisappear` resets, Health
  changes), then build, install on the phone, and commit per lane.
- Packages are pre-cloned in `/tmp/iron-spm`. `/tmp` gets wiped on reboot; if it's gone,
  run one normal `xcodebuild -resolvePackageDependencies` with network access, then copy
  `<derivedData>/SourcePackages` to `/tmp/iron-spm`.

## 5. Task list (priority order)

`[CODEX]` means implementable from specs now. `[OWNER]` needs the owner. `[LEAD]` is
orchestration or verification.

### T1 [CODEX] The empty Saved Workouts "New Workout" button renders far taller than it is wide (owner-reported bug)
`Iron/UI/Workout/StartWorkoutView.swift`, around line 398: `ContentUnavailableView { … } actions:
{ Button("New Workout", systemImage: "plus", action: newPlan).buttonStyle(.bordered)
.frame(minHeight: IronTheme.controlHeight) }`, inside a `List` `Section`. The `.frame` sits
outside the button style, and `ContentUnavailableView` in a list row lets the action stretch
vertically, giving a narrow, very tall "+" bezel.

Fix:
- `Button(action: newPlan) { Label("New Workout", systemImage: "plus") }`
  `.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)`
  `.labelStyle(.titleAndIcon).fixedSize()`, with no external `.frame`.
- Give the `ContentUnavailableView` `.frame(maxWidth: .infinity)` and
  `.listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))`.
- Then audit **every** `ContentUnavailableView` with `actions:` and every `.frame(minHeight:)` on
  a styled button in the app for the same bug.
- Verify at the default text size and at AX5.

### T2 [LEAD] Visual QA pass of everything shipped since 2026-10-21
Nothing in `d6cdeb5`, `1ad5e22` or `c3f401a` has been looked at on screen. With the owner's OK,
boot one simulator, seed data (Debug builds have developer seed buttons in Settings), and
screenshot, in light and dark, at the default size and AX3:
- the logger: session bar, header expanded and collapsed, focused editor, swipe open, rest strip
  plus ruler, the exercise rest chip idle and running, soft set-type rows, the RPE sheet;
- the exercise detail: every segment, the empty state, the tooltip;
- the Workout tab, with history and without;
- Home.

Compare each against `DESIGN_SYSTEM.md` and the backlog acceptance criteria, then file and fix
deviations. Check that vertical scrolling works when a drag starts on the ruler, chart, map,
rows and steppers.

### T3 [CODEX] Muscle tooltip: true touch-and-hold, then drag to scrub
Today a tap or long-press shows the tooltip for 2 s. The package reports long-press **on
release**, and its drag recognizer steals scrolling. MuscleMap is MIT-licensed and its hit-testing
is internal. Options, in order of preference:
1. Use a public API if a newer package version exposes hit-testing.
2. Build an overlay with
   `LongPressGesture(0.25).sequenced(before: DragGesture(minimumDistance: 0))` and do the
   hit-testing against path data copied **through the package's public types only**.
3. If neither is possible, propose vendoring the package as a local Swift package
   with a public `muscle(at:)`, and get the owner's OK first, because it changes dependencies.

Spec: `DESIGN_SYSTEM.md` §9.8, backlog B6.3.

### T4 [OWNER] Push `3ab7e2f..c3f401a` to the fork's `main` when the owner says so
`git fetch origin && git merge-base --is-ancestor origin/main main && git push origin main`

### T5 [CODEX] B7 recency captions and B10 motion gaps
These are optional and low priority (backlog B7 and B10). B10's accessory-to-logger zoom
transition is the most visible of them.

### T6 [CODEX] Known technical issues
- An `AVAudioSession` setup warning on the main thread at launch
  (`Shared/IronSoundPlayer.swift`): move the session configuration off the main thread, or make
  it lazy and idempotent.
- `xcodebuild test` hangs before connecting in this environment. Investigate: try a specific
  simulator destination, `-parallel-testing-enabled NO`, and check for a test host that waits on
  HealthKit or WatchConnectivity.
- Debug-only developer seed buttons must stay out of Release. Confirm they are behind
  `#if DEBUG`.
- `WorkoutSetEditor.swift:143`: "TODO: let the user configure this for barbell, dumbbell and
  others" (plate and bar weights). This is a candidate setting; design it first.

### T7 [LEAD + OWNER] Design rounds still owed
These are unapproved, so design first:
- **Exercise touch states:** chart scrub callout and muscle hold. A board was planned but never
  drawn.
- **Add-exercise sheet with recency:** grouping and captions; a board was planned but never drawn.
- **Finish screen and History** re-check against the new fills (soft set-type colors in the
  session strip? Today the strip only knows warm-up, normal and record).
- **Watch app parity** with the new phone visuals (set fills, rest chip, RPE bars), on watchOS
  native controls.
- **Live Activity and widgets** using the session bar and metric colors.

## 6. UI ideas log

Everything discussed or proposed so far, with its status.

### Approved and shipped
Iron blue + one color per metric · SF Pro bold fixed-width numerals · fill sweep on set
completion · rest strip inside the exercise with −15 / pause / +15 / skip · rest drains an
`IronRestRing` · inline rest-length ruler replacing the dial · rest chip at the top right of each
exercise card (countdown while resting) · focused current-set editor (Logger B: big fields, −/+
steppers, "Last time", plates hint, Add RPE, Log Set) · soft set-type fills (warm-up orange,
drop indigo, failure red) · RPE rising-bar picker · session effort rising bars ("How hard was
it?") · workout-complete recap (metrics grid, session strip with labelled rests, records,
saved-workout toggle, Health row) · History week grouping with totals, PR and RPE badges, compact
session strips, and an exercise breakdown capsule · Home weekly hero, day bars, best day, streak
chip, 4-week calendar, greeting, week-over-week caption · recency-first exercise ordering ·
exercise detail with inline progress (1RM, Weight, Volume, History; 1M–All), headline delta, PR
point, inline session history with set chips, target on the live-workout muscle map, tooltip
(not modal) · Recent Workouts with one-tap Repeat · session bar under the logger top bar ·
original procedurally generated sounds · import progress overlay · "Import & Export" label.

### Approved, not yet done
True hold-and-drag muscle tooltip (T3) · recency captions (B7) · accessory-to-logger zoom (B10).

### Shown on the canvas but not adopted (keep for reference)
Round 4 "everything fills":
- tall set bars that fill blue, with no table header or Previous column;
- the rest bar filling cyan under the set, dragged left or right to add or remove 15 s and
  tapped to pause;
- a "Ready / Go" state;
- a pulsing glow ring on the next set when rest ends;
- an elapsed / volume / sets header above a big session bar (replaced by keeping today's
  summary plus a thin bar).

The owner kept today's timer and summary instead. **The glow on the next set when rest ends is
still a good, unrejected idea; propose it.**

### Proposed by the previous lead, never shown to the owner (design and ask before building)
1. **Progressive overload hint** in the focused editor: under "Last time 200 × 5", a quiet chip
   "Try 205 × 5" (+1 increment when all sets hit their target reps last time). Tap to fill.
2. **Next-set glow** when rest ends: an accent ring pulse on the focused editor, plus the
   `restComplete` sound.
3. **Muscle Focus as a heatmap.** MuscleMap supports `.heatmap(_:colorScale:)`. Replace Home's
   muscle bars with a front and back heat map of the last 4 weeks' sets, in accent intensity
   only (not rainbow).
4. **Exercise "Bests" card** on the detail page: heaviest weight, best e1RM, most reps, best
   session volume, each with a date and a record badge.
5. **Plate visual** in the plate calculator and focused editor: a tiny barbell drawing with
   plates per side as colored rounded rectangles (neutral, sized by weight), instead of text
   only.
6. **Warm-up generator:** from the first working set, propose 2–3 warm-up sets (e.g. 40%, 60%,
   80%) using plate math, added as W sets.
7. **Superset rail:** linked exercises share a 3 pt accent rail along their cards' leading edge,
   labelled "Superset".
8. **Exercise thumbnails** in History rows and the Recent Workouts list (the first 3
   exercises' diagrams, overlapped).
9. **App icon:** a blue weight plate seen face-on (systemBlue rim, darker blue inner ring,
   black hub). Sketched on the canvas "System · Iron blue" board. It needs light, dark and
   tinted variants.
10. **Lock Screen widget:** the rest countdown and next set, with Smart Stack relevance during
    workouts.
11. **Weekly streak widget:** the week's day bars plus the streak.
12. **First-run flow:** a welcome screen and "Import from Hevy" as the first-class second step;
    Health permission explained (exports only Iron-completed workouts).
13. **Inline exercise notes** in the logger, shown as a secondary line under the exercise name
    and editable in place.
14. **Body tab charts** restyled to the §10 chart rules (`metricBody` purple).
15. **Session strip set-type colors:** add drop and failure kinds to `IronSessionStrip`, so the
    recap and History match the new soft fills.

## 7. Lessons and pitfalls (the "intellect")

- **List prefetch versus entrance animations:** never reset appear state in `onDisappear`, or
  prefetched rows stay invisible. This caused an "invisible effort graph" bug.
- **Horizontal gestures inside a scroll view:** use `HorizontalSwipeRecognizer`
  (`UIGestureRecognizerRepresentable`, begins only when |vx| > |vy|) on iOS 18 and later. A
  SwiftUI `DragGesture` swallows vertical scrolls. This caused "can't scroll when starting on a
  set row".
- **Floating glass over a scroll view:** inset the content with `.contentMargins(.top, h, for:
  .scrollContent)` so it never covers the first item.
- **Heavy work:** imports and history scans run off the main actor (`Task.detached` or a
  private-queue context), with progress UI. Exercise recency is one dictionary-result fetch
  with a debounced refresh on save.
- **Health:** eligibility is decided at finish time and stored (`healthExportState`); retries
  happen on scene activation; the Watch owns its own `HKWorkoutBuilder` sample and the phone
  never duplicates it.
- **Core Data:** model v6 (`importSource`, `healthExportState`) with a staged v5 → v6 migration.
  Any new attribute needs v7 plus a migration stage.
- **Codex** follows long, exact specs well, but will take a "permitted fallback" quickly. Say
  explicitly when a fallback is unacceptable.
- **Signing:** the IronIntentsUI target uses personal-team entitlements in Debug
  (`IronIntentsUI/IronIntentsUIPersonalTeam.entitlements`); don't reintroduce upstream app
  groups there.
- **Canvas:** the design canvas is a claude.ai artifact
  (<https://claude.ai/artifact/XwxfzWTFvH2PNZWqMRpihv>; pages Round 1–5). Agents without the
  Artifact tool can't edit it. Use SwiftUI previews and screenshots for design proposals
  instead, and record approved decisions in `DESIGN_BACKLOG.md`'s decisions log.

## 8. File map (where things live)

| Concern | Files |
| --- | --- |
| Tokens | `Shared/UI/SwiftUI/IronStyle.swift` |
| Shared UI helpers | `Iron/UI/SwiftUISupport.swift`, `Iron/UI/Components/*` |
| Live logger | `Iron/UI/Workout/CurrentWorkoutView.swift` (big), `RestTimerView.swift`, `WorkoutSetEditor.swift` |
| Workout tab | `Iron/UI/Workout/StartWorkoutView.swift` (includes `WorkoutRepeater`) |
| Home | `Iron/UI/Feed/FeedView.swift` |
| History | `Iron/UI/History/HistoryView.swift`, `WorkoutDetailView.swift` |
| Exercises | `Iron/UI/Exercises/*` (detail, statistics, history, library) |
| Model | `WorkoutDataKit/` (`ExerciseStore` holds recency) |
| Health | `Iron/HealthKit/HealthManager.swift`, `Workout+Logic.swift` |
| Watch | `WatchIron Extension/`, `Iron/WatchConnectivity/` |
| Import | `Iron/Data/Model/HevyCSV.swift` |
| Sounds | `Shared/IronSoundPlayer.swift`, `Iron/Resources/Sounds/`, `scripts/generate_sounds.py` |
