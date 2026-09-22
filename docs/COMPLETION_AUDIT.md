# Iron completion audit

Last reviewed: 2026-09-22. This is a working defect log, not a release sign-off.

## Scope and acceptance

The current design target is Cupertino, with Home, History, Workout, Exercises,
and Settings tabs. Preserve the completed-set glass pills, stable row geometry,
exercise-local rest timers, and shared timer dial. Do not introduce social features.

Each fix needs a reproducible failure or code evidence, regression checks, a root
review of delegated changes, and a separate commit. Existing uncommitted changes
belong to the ongoing overhaul and must not be swept into unrelated commits.

## Confirmed defects

| ID | Priority | Evidence and impact | Fix and acceptance | Status |
| --- | --- | --- | --- | --- |
| TIMER-01 | High | `RestTimerStore.pause()` cleared the start through a setter that scheduled an alert from the paused remaining value. | Atomic transitions cancel local and notification deadlines on pause. Regression covers pause and invalidated expiry callback. | Fixed; tests pass |
| TIMER-02 | High | `resume()` restarted the original duration, losing elapsed time. | Resume deadline uses captured remaining time. Regression pauses a 120-second timer after 45 seconds and resumes 30 seconds later with 75 seconds left. | Fixed; tests pass |
| TIMER-03 | High | A stale notification settings callback could add an alert after cancellation; app sound preference was ignored. | Serialized generation checks, absolute deadlines, app/system sound policy, foreground-only local chime. Scheduling order reviewed; sound policy and expiry invalidation tested. | Fixed; physical delivery check open |
| TIMER-04 | Medium | Notification actions changed total duration off-main and could fail to extend an expired timer. | Actions validate category/existing timer, run on main, restart an expired timer from now, refresh Live Activity. | Fixed; expired-timer regression passes |
| LIVE-01 | High | `startOrUpdate` republishes existing confirmation/rest content unchanged. Editing, removing, or reordering sets during rest can leave stale set IDs and counts in the Live Activity. | Reconcile the payload against current model values while preserving valid phase deadlines. Test deletion, replacement, edits, and reorder during rest. | Assigned to Sol medium |
| SAVE-01 | High | `WorkoutLiveActivityIntentHandler.completeSet` starts the timer before Core Data save. On failure it returns without restoring completion fields or timer state. | Save completion before side effects; restore changed fields on failure. Test failed save and stale intent. | Assigned to Sol medium |
| HEALTH-01 | High | `syncWorkoutIfNeeded` deletes old HealthKit samples before saving replacements; a failed replacement can leave no Health sample. `deleteWorkout` queries only one match. | Audit reconciliation and recovery before changing HealthKit writes; test duplicate and failure cases. | Investigation required |
| BACKUP-01 | High | `applicationWillTerminate` blocks main on a dispatch group while the backup closure calls `viewContext.performAndWait` from a background queue. The closure waits for the blocked main queue. | Capture backup data before asynchronous file work, remove the main-thread wait, and schedule automatic backups during backgrounding. | Planned |
| WATCH-01 | High | `handleWorkoutEvent` applies timer and Live Activity side effects before the database save. A failed save leaves unsaved model mutations and external state changed. | Separate durable mutation from post-save effects and retry without acknowledging failed events. | Planned |

## Verification queue

- Run the full iOS unit-test target, recording failures rather than treating build success as test success.
- Use idb to test timer selector press-and-hold, dial drag, pause/resume, completed-row geometry, and timer position in the simulator.
- Verify Live Activity current set, completion, rest, adjustment, skip, and stale intents.
- Audit workout persistence, imports/exports, measurement persistence, backup/restore, and Watch offline reconciliation.
- Inspect all five tabs in light/dark mode and large Dynamic Type; check keyboard and safe-area behavior.
- Verify iOS, widget, share extension, and watchOS targets build from the same source state.

## Device-only checks

Simulator results do not certify physical haptics, locked-device alert delivery,
HealthKit permission behavior on a real account, Apple Watch offline workouts,
WatchConnectivity reconnection, or production signing. These remain open until
tested on suitable authorized devices. Do not mark the app complete while these
checks or confirmed defects remain unresolved.

## Results

Simulator boot and idb accessibility inspection succeeded. idb screenshot capture
failed; simulator-native capture succeeded.

- Full `Iron` scheme simulator test run: 58 tests, 0 failures, including 9 new timer regressions. Result bundle: `/private/tmp/IronAudit-20260922-Tests.xcresult`; log: `/private/tmp/iron-audit-tests.log`.
- Build validated the iPhone app, widget/intents extensions, and embedded Watch app for simulator. This does not validate device provisioning.
- Root review required follow-up corrections for timer restoration, foreground-only audio, generic cancellation invalidation, and stale notification actions before accepting the timer patch.
- idb hold test: selector frame stayed at x=98.259, y=437.111, width=height=205.483 points before/during hold. Screenshots: `/private/tmp/iron-selector-before.png`, `/private/tmp/iron-selector-held.png`.
- Existing completed/incomplete row control widths match in the simulator. Green chrome extends outside controls; screenshot: `/private/tmp/iron-audit-initial.png`.
- Migration fixtures log a missing legacy exercise ID and the test host logs an app-group entitlement warning. The migration tests pass; real signed app-group access remains a device check.
