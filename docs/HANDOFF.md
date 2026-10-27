# Iron: handoff to the next lead agent

## Owner checkpoint: Watch app needs revision (2026-10-26)

The owner rejected the current Watch result and explicitly stopped development. They then
authorized committing and pushing the existing work to preserve it, primarily the iPhone app.
The Watch code is included as a **work-in-progress checkpoint**, not an accepted final design.
This decision supersedes the earlier Watch design approvals and completion language below.

The Watch app still needs a further design/usability pass across Home, the exercise list,
exercise details, set editing and deep menus. Automatic recording/recovery, fresh BPM/kcal,
Always On, Smart Stack opening the local Watch app and a complete on-wrist Health save also
need end-to-end verification. Build 43 reports a running session with matching identifiers,
but fresh sensor values were not verified after its recovery change. Prior test/build results
do not establish owner acceptance or complete physical-device validation.

Preserve the iPhone app's current design and all saved work. Do not resume Watch implementation
or install another build until the owner asks. No workout data was removed for this checkpoint.

## Active follow-up: Light rename and Live Activities (2026-10-26)

### Latest steering: exercise-first Watch navigation (2026-10-26)

Owner approved and installed the exercise-first redesign across the entire Watch app.
The authoritative flow is **Home → active exercise list → exercise sets → set editor**.
No global ellipsis; secondary set actions sit behind Settings at the bottom of the set.
Home orders New Workout → Saved Workouts → History. Larger rows show exercise/set totals,
primary muscles and history date/duration. Red BPM/orange active kcal are pinned above the
scrolling body on active pages and deep editors, explicitly unredacted for Always On.
The approved interactive proposal is `light-watch-exercise-first.html` in this thread's
visualization directory (88 browser checks); native layout evidence is in QA_2026-10-26.md.

Signed build **43** is installed: phone sequence **5756**, Watch **1224**. Normal launches
succeeded on both. Full iOS test-bundle compilation and Watch simulator compilation pass.
Regression harnesses pass: 14 actual Core Data synchronization, 13 automatic-start/recovery,
13 actual-manager/mock-HealthKit lifecycle, nine editing/persistence/cache and three exact
superset-membership scenarios.
Modern Watch events carry changed-field masks and explicit addition/deletion IDs, preserving
concurrent phone edits and preventing deleted objects from being resurrected by stale copies.

**Real sensor evidence:** build 41 showed 93 BPM in native diagnostics and then 85 BPM /
**4 active kcal** on the actual display. Reinstall exposed a recovered builder with missing
external-ID metadata. Build 43 reuses the durable projection ID locally while preserving any
actual HealthKit metadata; it does not restart collection or rewrite the live builder.
Thirteen actual-manager/mock-HealthKit scenarios pass, including recovery identity and inactive
session guards. The real build-43 diagnostic confirms the original session is running, IDs match
and the recording error is gone. Initial recovered metrics were still missing; the later
capture failed when the Bluetooth developer tunnel dropped. The final tunnel retry succeeded
and still confirms the same running session without a recording error, but no fresh metrics
were returned. A fresh on-wrist check is pending the owner; do not claim final-build sensor
values were captured yet. Calories
remain Apple's Traditional Strength Training estimate. Earlier D0… Watch projection and A276…
phone mismatch is historical; the latest Watch durable snapshot has converged to A276… with
empty outbox. No workout was finished/discarded or Health data fabricated for QA. Do not claim
that a real Smart Stack tap or a full completed on-wrist Health save was exercised.

The real library contains 5,798 exercise picks and 453 history sessions; zero saved routines
matches the phone's empty routine library. Current identifiers remain compatible; IPv6 stays
Off. Debug device builds write a read-only recording diagnostic to
`Library/Caches/LightRecordingState.json`; it never changes session state or exists in Release.

### Historical Focus implementation and live metrics (superseded navigation)

Owner approved **Focus** and implementation across the **entire Watch app**, including deep
menus and Watch-only training. The approved design is `light-watch-redesign.html`. That earlier
implementation used a single native navigation stack, focused logging, Crown editors,
rest controls, exercise/set management, visual superset selection, reorder, notes, effort and
finish, saved-workout creation/editing/deletion, and cached history/repeat. Phone UI stays on
its existing design. Build **39** is being delivered; final install evidence is below.

Watch independence: bundled 5,749-exercise text catalog; cached full phone library, routines
and history via immutable files. Current snapshot/edit packets stay separate. Oversize
snapshots/events use files; the outbox drains in sequence and removes edits only after the
phone acknowledges durable save. A different phone current workout is preserved; conflicting
unfinished Watch records stay in a separate deferred file until completion. Explicit deletion
IDs remove Watch-deleted sets/exercises without erasing unseen phone additions. Imported
records remain read-only to the Watch event adapter and never export to Health. Repeats use
fresh workout/graph IDs. No Core Data schema or dependency changes.

Native 40 mm/Ultra-size QA caught and fixed field truncation, hidden primaryAction toolbars,
wrapped linked metadata, crowded editor titles and main-action placement. Larger text stacks
the fields. Fixtures are DEBUG + simulator only. Nine persistence/editing, eight actual Core
Data sync, and ten mocked-HealthKit lifecycle cases pass. Actual Ultra launch/capture shows
the dark rest view. The last end-to-end sensor and system Smart Stack tap checks require the
owner wearing/unlocking the Watch and handling Health prompts; never claim these are verified
from unit tests. Owner confirmed the Watch is worn/unlocked and both apps are open; real library delivery is
verified (5,798 exercises and 453 history sessions; no saved routines on this phone). Sensor
recording and Smart Stack tap checks are in progress. Owner corrected the normal path: an active
workout must automatically start/recover Health recording. This is implemented; Record/Retry is
only for failures/denied access. Recovery and start guards prevent duplicate sessions. Owner also requested 0.5 weight steps
for both units: implemented for Crown display/commit and ±, preserving accumulated raw travel.

Build **38** small correctness update is installed (phone **5700**, Watch **1168**); normal
launches succeeded. It adds live Watch HR/estimated active calories to the phone status row,
transient UUID/time-scoped sensor transport, WKSupportsLiveActivityLaunchAttributeTypes, and
correct HealthKit stop/collect/save/end ordering. Start-time edits remain in Light while the
Health workout retains its original sensor window/sample associations. Seven telemetry tests
and ten actual-source/mock-HK lifecycle scenarios passed; iOS test-bundle and signed builds
passed. Physical metric values and native local tap still need in-use verification. Forced
restart was auto-review rejected for an active-workout risk; normal launch was used instead.
Owner is actively using devices; do not assume a later screenshot is still Light after launch.
IPv6 remains Off; never change it. No workout data was changed for QA.


- Owner approved **Set tile** after reviewing `light-live-activities.html`. Implemented cached
  exercise artwork plus per-exercise blue set cells in compact iPhone/Mac and minimal views;
  no compact stopwatch. Watch shows artwork/name, set position, tile and secondary rest/Skip.
  All ActivityConfiguration families inherit a dark foreground and black activity background.
  Expanded iPhone uses one full-width bottom region below the sensor, with safe content margins.
  Existing rest, pause/resume, Log Set and Undo intents remain available.
- Payload adds an optional completed-set count, preserving legacy decoding. Counts come from
  actual nondeleted sets, never the next set ordinal; legacy snapshots retain position text.
  Three native XCTest cases executed against the extracted production snapshot type passed.
  Simulator app/test-bundle, signed iPhone/embedded Watch, and generic Watch builds passed.
  Full iOS XCTest runtime remains limited by the earlier DTServiceHub stall.
- Owner chose **Light**; display names, permission copy, Siri phrases and visible branding are
  updated. README describes current features and credits Iron/Karim Abou Zeid; About links to
  this fork and original project. Icon remains the owner's next task. Internal names, bundle
  IDs, backup/UTI formats, app groups, preferences, media paths and companion IDs stay stable
  to preserve data. `com.sopat712.light` is only a proposed future distribution identity.
- Latest installed/launch-verified iPhone update: build **37**, install sequence **5692**.
  This includes the compact tile correction: a 20 pt tile in a 24 pt slot with 6 pt trailing
  clearance, replacing the 24 pt tile that clipped at the curve. Simulator and signed device
  builds passed. Native island visual clearance remains unverified: AXe input returned success
  without changing simulator state. Earlier files named compact/expanded-three-sets are logger
  captures, not evidence of island correctness. Do not claim native clipping QA passed.
- **Watch integrity/install issue resolved.** Owner completed pairing and enabled Developer
  Mode. The actual Ultra 4 is **00008320-001F472A2160000A**, **Watch8,1**, watchOS **27.0.1
  (24R365)**. Do not target the stale original Ultra record 00008301-408D14941E08202E.
  Destination-specific Watch build with `-allowProvisioningDeviceRegistration` succeeded.
  Renewed profile **392ffe10-71b2-4fe1-9641-a13458364910** includes the actual Watch and
  expires **2026-11-02 21:38 UTC**. Signature verification passed; direct Watch install
  sequence **1160** and launch succeeded. CLI screenshot shows **Light / iPhone connected**.
  The iPhone was reinstalled with the same renewed embedded Watch profile and launched.
  Actual Watch Smart Stack/full-screen Live Activity still needs a running workout to verify.
- Mac Wi-Fi IPv6 is **Off**, verified after successful pairing. The agent never changed it;
  owner explicitly prefers it remain off. The connection now works with the owner's Wi-Fi
  reconnection/pairing and the iPhone on USB. No unpairing, resets, app deletion, credentials
  or trust/passcode entry by the agent. Binary has arm64 and arm64_32; target resolves watchOS.
- Owner prefers CLI. `idb` is absent; CoreDevice handles device build/install/launch/capture,
  AXe handles simulator input when responsive. `pymobiledevice3 companion list` found the
  correct Watch ID through USB before Xcode discovered it. `devicectl device pairings list`
  is a simulator capability and fails on the physical phone. Device Hub was used for initial
  pairing only. CACE is shut down; compiler and simulator slots returned to Overland.


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
workers within AGENTS.md's concurrency limits, review every diff yourself, build, and install
on the owner's iPhone (§0.3 commands). Leave changes uncommitted unless explicitly asked;
(5) keep HANDOFF.md, DESIGN_SYSTEM.md and DESIGN_BACKLOG.md current: log
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

### 2026-10-25 continuation (uncommitted working tree)

- T1: Saved Workouts uses an explicitly labelled, intrinsic-size prominent capsule; all eight
  empty-state action sites and styled minimum-height wrappers were audited. The five other
  styled empty-state actions also use intrinsic sizing. The first simulator build passed.
  AX5 exposed horizontal clipping with fully fixed labels; actions now keep intrinsic height
  while allowing horizontal wrapping inside the List row.
- T3: owner approved vendoring MIT MuscleMap 1.6.4 in `Packages/MuscleMap`; the renderer now
  exposes `MuscleHitTester`. The target card uses a 0.25 s UIKit long press, hold/scrub/lift
  callbacks and a 2 s tap tooltip. Gesture cancellation clears the selection.
- T4b: owner approved the native Imported Data section. Removal and replacement target exactly
  `importSource == "hevy"`, run on a sibling private context, and merge object IDs into the UI.
  Replacement deletes and inserts in one save, reusing custom-exercise rollback. Measurements
  are kept. Invalid or partially malformed replacement files fail before deletion.
- Re-import deduplication also checks start second + exercise/set fingerprint for Hevy sessions,
  so title-only edits do not duplicate them. Editing the start time still changes identity;
  matching by content across dates would incorrectly merge repeated workouts. Replacement is
  the supported way to reconcile those edits without a new model attribute.
- B7 captions and B10 native accessory/logger zoom are implemented; Reduce Motion and iOS 17
  retain the existing overlay/fade. DEBUG-only launch routes support deterministic screen QA.
- T6: audio-session category setup runs on a serial queue; concurrent preload requests coalesce.
  Seed controls and launch seeding are confirmed behind `#if DEBUG`. Fixed a pre-existing test
  compile error by importing `WorkoutDataKit` with `@testable` in its test file.
- Final simulator `build-for-testing` and signed iPhone/Watch Debug builds passed. MuscleMap's
  220 package tests and all 19 isolated import service smoke checks passed. The iPhone install
  succeeded; iOS refused launch because the phone was locked. Runtime XCTest on
  the explicit simulator with `-parallel-testing-enabled NO` stalled before execution at
  `DTServiceHubClient failed to bless service hub` / `com.apple.instruments.deviceservice.lockdown`.
  No test success is claimed. The stalled runner was interrupted and terminated.
- T2: the light/dark default/AX3 screen matrix and AX5 empty-action check exposed and fixed
  invisible volume bars, clipped empty buttons, and unstable header collapse. Accessibility
  logger summaries now stack their values; set rows reflow into labelled fields instead of
  narrow table columns. Header and stepper touch targets meet 44 pt. See
  [`QA_2026-10-25.md`](QA_2026-10-25.md) for evidence and verification limits.
- Owner authorized direct coordination with Overland's **Fix Live Activity display** chat
  (`01a170c9-8baf-7263-a0df-6fe990715e1d`). Iron's simulator is
  `CACE2E28-29B0-46A4-96F5-B66ACB4631A1`; Overland's is
  `E2C9ADC2-9481-4009-867F-7F00C53DC704`. Trade simulator/build windows directly; never reset
  the other app's data. AXe is available at `/tmp/overland-axe/axe` for simulator QA.
  The completed run restored Iron's simulator to light/default sizing, shut it down, and
  returned all shared slots. The final signed build is installed; phone launch awaits unlock.
- No commits, pushes, stashes, resets or checkouts were performed. No contents of
  `reference-material/` were read or changed. T7 and equipment-setting designs remain proposals.

### 2026-10-25 morning visual follow-up

The owner rejected Home's blue glass haze, requested library theming, full-width exercise
detail cards, one exercise title, and clearance below the collapsed summary at the scroll top. These
now use the existing Iron surface/type roles. The owner also approved Previous-result
capsules and 10 pt compact input outlines, and requested the remaining numeric font pass.
Live Activity rest now takes priority over the 10 s confirmation; ±15 intents await their
ActivityKit publication and countdowns suppress replacement/placeholder effects. Validation
for this follow-up is recorded in `QA_2026-10-25_FOLLOWUP.md`: all targets and the signed phone
build passed; the new phase resolver passed eight isolated checks. XCTest's host service is
still blocked. Default-light and AX3-dark screenshots confirm the visual changes. Phone install
succeeded; iOS denied launch because the phone was locked.

### 2026-10-25 afternoon cohesion, media and navigation follow-up

The owner rejected the partial font pass. A full-page comparison corrected Home's lower
data rows, measurement spacing and accessibility layout; shared `IronMetricValue` and
`IronWorkoutMetricLine` now keep numeric weights, units and metric colors consistent across
Home, History, Workout and logger. Library, picker, saved-workout tags and Custom Exercises
share row/tag treatments. Logger uses bold focused values, title3 compact values and theme
corner tokens. See `QA_2026-10-25_COHESION.md` for screenshots and validation.

The owner then reported missing exercise pictures and Show All Sessions filling the back
stack. A read-only phone exercise-definition audit found 49 empty custom definitions from
unmatched import names. Curated aliases/read-time enrichment recover 24 without changing
UUIDs, names, custom-file bytes or historical relationships; 25 need specific variants or
new catalog coverage. Unknown imagery uses a dumbbell instead of O. See
`EXERCISE_CATALOG_AUDIT.md` for the remaining names and verified free-media options.

The inline history card contained multiple NavigationLinks in one List row. It now sends
plain-button actions to one destination route owned outside the List by ExerciseDetailView.
Three Show All/back cycles and one individual-session/back cycle passed on the reported
History → exercise route. No historical records were merged or re-imported for these fixes.

### 2026-10-25 OpenGym catalog and Hevy matching

The owner stopped V2 comparisons and chose to keep Iron, update its main dataset from
OpenGym and match imported Hevy names. This means imported-history matching, not automatic
Hevy account sync. Canonical OpenGym text at revision
`042c9ee42282756ab0e6e86a1cd5c710efaecee6` contributes 5,632 definitions. The library combines
these with 117 legacy-only records for 5,749 built-ins; all 1,441 original UUIDs/IDs and media
references survive. The converter and bundled AGPL/MIT notices preserve provenance.

Nine more reviewed Hevy aliases bring recovery to 33/49 observed custom definitions with
metadata, 25/49 with existing-source media. Original custom UUIDs, names and on-disk bytes are
kept; custom exact titles win over canonical titles during import. Sixteen unresolved names
remain available without guessed variant assignments. No workout records are merged.

Lists now persist a first-frame PNG from Iron's existing provider; demos retain the original
GIF and its resolution. OpenGym's licensed media was not copied: its non-commercial exception
specifically permits OpenGym forks, not an independent app. Support for separately licensed
bundled `catalogue/still/` files is ready. See `EXERCISE_CATALOG_AUDIT.md` for checks and limits.

Catalog merge/matcher and still-cache fixture checks passed. Simulator app/test-bundle and
signed phone/Watch builds passed; the new build installed and launched on Josh's iPhone.
The test bundle compiled, but XCTest runtime still has the documented host-service limit.
Simulator screenshots verified alias search and custom metadata; shared slots were released.
Automatic approval review blocked the optional phone-file copy for a byte comparison, so
that post-install comparison is not claimed. No transfer was retried.

### 2026-10-26 native polish, daily recap and performance

The owner stopped the OpenGym-fork discussion and requested more native polish and faster
Home/History. Exercise toolbar label frames were removed to restore native spacing. Recent
rows now give titles/metadata/metrics full width, with a quiet chevron and bold text Repeat
below; the ellipsis menu offers Save as Workout. This opens a new transactional editor from
completed session data, preserving the source and Health provenance on Cancel, success or
failed-save rollback. Saved-workout targets support only their existing model fields/tags.

`TrainingHistoryStore` shares a debounced private-context snapshot of finished sessions,
day buckets, exercise totals, trained weeks and PR IDs. Home, History and calendars no longer
traverse every workout relationship from their view bodies. Exercise metadata uses a UUID
lookup refreshed with custom definitions. History's main selector is Workouts/Insights;
Exercise Progress remains in its options menu and reads cached totals.

Chart/selector rows are unified in History Insights, Body Measurements and saved workouts.
Daily calendar taps now open `TrainingDayRecapView`, with totals, all sessions, muscle focus
and measurements recorded that day. Month-grid buttons share one destination; large dates
scroll horizontally. Chart axes adapt at accessibility sizes and share the horizontal scrubber.
Settings uses native symbols/disclosures; deeper saved
workout fields and numeric keyboards use the metric type hierarchy, large-text reflow and
VoiceOver adjustment actions. App-only theme types are not linked into shared Siri controls.

Simulator app/test bundle and signed iPhone/Watch builds passed. The phone update installed;
launch was denied because the phone is locked. XCTest still stalls at DTServiceHub before
execution and the bounded attempt was stopped. Actual macOS Core Data service harnesses
passed snapshot totals/PR parity/streak/source preservation (600 sessions in ~24 ms), plus
saved-workout Cancel/Create/failure rollback/retry. See `QA_2026-10-26.md` for interaction and
visual checks and remaining limitations. No Git mutations or reference-material access.

### 2026-10-26 logger correction follow-up

The owner clarified that the collapsed summary must retain translucent glass, with content
starting lower rather than permanently excluded from behind it. It now floats over the scroll
viewport with measured top content margins (8 pt top plus 12 pt bottom gap), including AX sizes.

`WorkoutSetFocus` owns one next set across the active workout. Supersets alternate by round,
skipping empty/completed members; undo, reorder and pending deletion re-resolve from Core Data.
The editor, session progress marker, optional automatic superset scroll and Live Activity
superset snapshot use that same target. Ordinary ActivityKit anchor reconciliation is retained.

The iPhone high-refresh flag is enabled. Ruler position follows the finger continuously with
no per-event spring, while the selected duration and feedback snap to 15 s. Only release
commits changes. Duration timelines no longer rebuild static muscle paths/summary aggregates;
main-context child changes still invalidate them, including Watch events. No forced display
link or refresh loop was added. Actual iPhone frame pacing remains unprofiled.

Focused Core Data/ruler XCTest methods run natively on macOS (15 passed); simulator UI verified
one editor through A1 → B1 → A2 → B2, plus default/AX3 floating-glass clearance. See the
follow-up section in `QA_2026-10-26.md` for final build, delivery and test-host status.
Final signed build installed on Josh's iPhone (sequence 5548); launch is pending phone unlock.
The bounded simulator XCTest attempt still stalls at DTServiceHub before execution.

### 2026-10-26 owner correction: manual header and matching set shapes

The owner rejected automatic scroll-based summary collapse. Only explicit chevron/glass taps
now toggle it. Each workout starts expanded and remembers its mode in `SceneState`, including
minimize/reopen; expanding retains the current scroll position. Both scroll-offset observer
paths and the forced scroll-to-top workaround were removed. Glass/clearance behavior remains.

Previous results in regular/AX logger rows and historical set-result chips now use the same
continuous 10 pt rounded rectangle as compact weight/reps/duration fields. Regular Previous
boxes also match the 46 pt field height. Status/action shapes retain their existing theme roles. This supersedes the earlier Previous-capsule choice.

Simulator scrolling, explicit toggles and minimize/reopen checks passed. Signed iPhone/Watch
build passed; installed and launched successfully on Josh's phone (sequence 5556).

### 2026-10-26 header separation and organization design review

**Signing follow-up, 15:47 Eastern:** The owner reported "no longer available." The installed
Debug profiles (app, extensions and Watch) expired today around 14:23 Eastern; the earlier
successful installation/launch preceded that expiry. The app signature verifies on disk,
but the phone rejects launch with a signing/security error. An automatic renewal build stops
with `No Accounts` / no matching profiles: Xcode currently has no Apple Account signed in.
Xcode Settings → Apple Accounts is open at Sign In for the owner. Do not enter credentials or
delete the app. After the owner signs in, rebuild with `-allowProvisioningUpdates`, verify fresh
embedded profile dates, install over the existing app and verify launch. Compiler slot released
to Overland; Iron simulator remains shut down. Renewal log: `/tmp/iron-profile-renewal-build.log`.

**Resolved after owner sign-in:** The signed renewal build passed. All five embedded profiles
are fresh through 2026-11-02 (the app expires 14:52:45 EST), with the same team/bundle IDs and
valid signatures. Reinstalled over the existing app as sequence 5628; launch succeeded after
iOS verification settled. No app deletion or workout-data changes. Logs:
`/tmp/iron-profile-renewal-{build,install,launch}.log`.

The owner rejected the progress/summary gray panel and bottom rules, and reported duration
colliding with volume. Toolbar, strip and expanded metrics now share one header material;
header/metadata rules and the segment outline are removed. Explicit columns, 12 pt gutters,
compact elapsed formatting and top-aligned captions keep long values separated.

The owner approved the visual Superset sheet and compact Arrange Exercises sheet. The sheets
are implemented in `WorkoutOrganizationSheets.swift`, with transactional model changes in
`WorkoutOrganization.swift`. Superset has source/partner thumbnails, a two-round preview above
the choices and explicit Save/Cancel. Selecting a different group includes its members;
unselected former partners remain linked if two or more are left. Arrangement uses native
handles with staged order and Done/Cancel, preserving sets and superset identities.

Holding a header name or thumbnail opens Arrange; Reorder is also in its menu and accessibility
actions. The name uses an exclusive tap/hold gesture and value navigation so a hold cannot
navigate underneath the sheet. Ordinary tap/Back and hold/Cancel were exercised successfully.
Both sheets keep failed saves open and use the isolated persist/save rollback boundary. Nine
native Core Data regression tests passed, including stale selection/order rejection and failed
save rollback with unrelated pending edits preserved. Simulator drag, Cancel/Done and superset
Save/Cancel persistence checks passed. Default/dark AX3 inspection caught and fixed preview
overlap during a live text-size change by using a separate accessibility stack. Final builds
passed and iPhone installation/launch succeeded (sequence 5596). See `QA_2026-10-26.md` for
details. The interactive interaction reference remains in the thread's
`iron-workout-arrangement.html` visualization.

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

Current delegation policy is in the owner's AGENTS.md instructions: root-session work by
default, at most one bounded independent child, no grandchildren, and isolated task briefs
with `fork_turns="none"`. The historical command below is reference, not permission to exceed
those limits or to commit.

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

Continuation status: T1, T3, T4b and T5 are implemented in the working tree. T2's simulator
pass and T6's audio/debug/test investigation are recorded in the QA report; XCTest execution
remains blocked by the host service. The original task specifications below remain for reference.
T4 still requires an explicit push request. T7 and equipment configuration remain owner proposals.

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

### T4b [CODEX, design the screen first] "Remove imported workouts" and re-import tools (owner request, 2026-10-25)
**What exists:** Hevy re-import already deduplicates. `HevyCSV.importData` builds a key
(start time rounded to the second, plus the normalized workout title) for every existing
workout and skips CSV sessions that match, reporting "N duplicate workouts skipped". Importing a
fresh full Hevy export therefore adds only the new sessions.

**Gaps to fix:**
1. A Hevy workout that the owner **renamed in Iron**, or whose start time they edited,
   no longer matches and would be re-imported as a duplicate. Match imported workouts
   (`importSource == "hevy"`) by start second plus exercise and set fingerprint as well, so a
   title change alone doesn't defeat deduplication.
2. Sessions **edited in Hevy** after the first import are skipped, not updated.
3. There is no way to undo an import.

**Build**, in Settings → Import & Export, as a new "Imported Data" section:
- A summary row: "Hevy · 412 workouts · Oct 2019 – Oct 2026" (count and date range of
  `importSource == "hevy"`).
- **"Remove Imported Workouts"**, a destructive action:
  - It deletes only workouts with `importSource == "hevy"` (never Iron-completed ones).
  - A `.confirmationDialog` states the count and says "Workouts you logged in Iron are kept."
  - It runs on a background context with the import progress overlay pattern.
  - It refreshes exercise recency afterwards (it observes saves, so this is automatic).
  - Imported workouts were never exported, so there is no Apple Health effect; assert that in
    code.
- **"Replace with New Export…"**: pick a CSV, remove the imported workouts, then import, as one
  operation that rolls back if the import fails. This is the clean way to pick up workouts
  edited in Hevy.
- Optional: "Remove imported body measurements". Measurements merge by date today; check
  whether they're tagged before offering this.

Never touch workouts without `importSource`. Add unit tests for the deduplication key and the
removal predicate.

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

Prepared directions for the next owner review (proposals, not approval to build):
- Touch states: keep the chart value/date in its existing headline while scrubbing, with one
  thin selection rule and no callout over marks. Show the muscle capsule directly above the
  held point, clamped to Target; the implemented gesture can be reviewed on the phone.
- Add Exercise: retain existing Recent-first ordering and muscle/equipment filters. The built
  relative-date captions disappear at accessibility sizes; any additional grouping needs a
  separate board before changing the current sections.
- Finish and History: extend the existing session-strip legend with soft drop/failure colors
  while preserving blue normal sets and yellow records. Review a mixed-set session first.
- Watch: use native List rows, blue completion, a compact cyan rest readout, and the existing
  effort bars adapted to the available width. Review the logger and RPE view together.
- Live Activity/widgets: retain native layouts, use the same time/sets/volume roles, and add
  a small session-progress bar only where it leaves the countdown and next set readable.
- Equipment setting (T6): a native Barbell Setup section under workout preferences, with bar
  weight and available plates in the chosen weight unit. Keep current defaults until approved;
  avoid introducing per-equipment increments without an explicit owner decision.

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

### Approved, implemented in the current uncommitted working tree
True hold-and-drag muscle tooltip (T3) · recency captions (B7) · accessory-to-logger zoom (B10).
Owner review on the installed phone is still useful; see the QA report for runtime evidence.

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
| Tokens | `Shared/UI/SwiftUI/IronStyle.swift`; shared numeric font in `IronMetricFont.swift` |
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
