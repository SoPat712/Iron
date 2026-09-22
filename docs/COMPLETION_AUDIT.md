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
| LIVE-01 | High | `startOrUpdate` republishes existing confirmation/rest content unchanged. Editing, removing, or reordering sets during rest can leave stale set IDs and counts in the Live Activity. | Reconcile the payload against current model values while preserving valid phase deadlines. Deleted objects are excluded before relationship cleanup. | Fixed; 9 reconciliation regressions pass |
| SAVE-01 | High | `WorkoutLiveActivityIntentHandler.completeSet` starts the timer before Core Data save. On failure it returns without restoring completion fields or timer state. | Save completion before side effects; restore changed fields on failure without discarding other edits. Reject deleted or already-completed sets. | Fixed; failed-save regression passes |
| SAVE-02 | High | Phone finish/discard stops timers before saving, and finish can delete incomplete sets before a failed save. The editor uses crash-on-save helpers. | Scoped rollback for start, finish, discard, deletion, and set completion. Save before timer/Health/Watch effects; retain editor and show an error on failure. | Fixed; 4 lifecycle regressions pass |
| SAVE-03 | High | Other active-workout mutations still call a void save helper, allowing follow-up state changes after a failed save. Some history/start routes still use crash-on-error wrappers. | Audit each user action, use recoverable scoped mutations, and stop effects on failure. | Planned |
| HEALTH-01 | High | `syncWorkoutIfNeeded` deletes old HealthKit samples before saving replacements; a failed replacement can leave no Health sample. `deleteWorkout` queries only one match. | Save replacements before removing exact captured old samples. Preserve metadata, energy, and distance; strip old sync-version identity; compare duration; reject invalid intervals. Delete all matching owned samples. | Fixed; 8 regressions pass; device HealthKit check open |
| HEALTH-02 | High | Concurrent reconciliation can query the same old samples and race saves/deletes. A process interruption after saving a replacement can leave duplicates. | Serialize Health mutations, test overlapping save/delete operations, and define retry recovery. | Planned |
| BACKUP-01 | High | `applicationWillTerminate` blocks main on a dispatch group while the backup closure calls `viewContext.performAndWait` from a background queue. The closure waits for the blocked main queue. | Capture backup data before asynchronous file work and start during backgrounding. Coalesce writes even after background time expires so an older snapshot cannot race a newer one. | Fixed; 4 coordinator regressions pass; real iCloud check open |
| WATCH-01 | High | `handleWorkoutEvent` applies timer and Live Activity side effects before the database save. A failed save leaves unsaved model mutations and external state changed. | Scoped undo restores only event mutations. Timer/activity/selection/acknowledgement effects run after save; discard uses captured values, not a deleted object. | Fixed; 7 regressions pass; physical reconnection open |
| IMPORT-01 | High | CSV `Double` parsing accepts nonfinite values; unchecked `Int` conversion traps for nonfinite or oversized counts. Unit conversion can also overflow and make measurement JSON encoding fail. | Reject invalid numbers per row; use checked integer conversion and validate converted values. Mixed valid/invalid imports and persisted measurement reload are covered. | Fixed; both regressions pass |
| MEASURE-01 | High | Direct measurement entry also allowed nonfinite/overflow values, and the store published entries before attempting JSON encoding. A failed encode left visible but unsaved data. | Validate display-to-canonical conversion; encode before publishing/exporting. Keep the editor open if save fails. | Fixed; invalid input and persistence regressions pass |
| UI-01 | Medium | Saved-workout rest selectors still use `IronDurationPickerSheet`, while active-workout rest selectors use `RestTimerConfigurationSheet`. | Saved-workout rest selection now uses the shared dial; timed-set duration entry keeps its duration wheel. | Fixed; simulator build passes |
| LIVE-02 | Medium | Live Activity content has no paused-rest value. Pausing clears the deadline, so the widget treats it as the next set instead of paused rest. | Backwards-compatible paused duration; static remaining time, Resume/Skip actions, and paused compact presentation. Reconciliation clears pause after the final set. | Fixed; 4 regressions pass; device interaction check open |

## Verification queue

- Run the full iOS unit-test target, recording failures rather than treating build success as test success.
- Use idb to test timer selector press-and-hold, dial drag, pause/resume, completed-row geometry, and timer position in the simulator.
- Verify Live Activity current set, completion, rest, adjustment, skip, and stale intents.
- Audit workout persistence, imports/exports, measurement persistence, backup/restore, and Watch offline reconciliation.
- Inspect all five tabs in light/dark mode and large Dynamic Type; check keyboard and safe-area behavior.
- Verify iOS, widget/intents extensions, and watchOS targets build from the same source state; test CSV document opening separately (there is no share-extension target).

## Platform references

- Apple's [HealthKit sync identifier](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier) supports replacement using a higher sync version. The installed SDK's `HKMetadata.h` confirms this; reconciliation must account for legacy samples without these keys.
- Apple's [background preparation guidance](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background) places data saving at background entry. Automatic backup must not depend on a blocking termination callback.

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
- The second run failed to compile a Live Activity test because an XCTest autoclosure crossed actor isolation. The test now calls the main-actor helper explicitly. The third full run passed: 74 tests, 0 failures (`/private/tmp/IronAudit-20260922-Third.xcresult`).
- Live Activity root review caught lost completion anchors across repeated refreshes and stale numbering for pending-deletion objects. Both received corrections and passing regressions before acceptance.
- Fourth full run: 83 tests, 0 failures (`/private/tmp/IronAudit-20260922-Fourth.xcresult`). Watch tests cover save failure, inserted/deleted objects, cascading workout discard, retry, duplicate set addition, and mutations that throw before saving. Root corrected undo registration for that last case.
- Fifth run found missing escaping closure annotations in the Health replacement coordinator. Sixth found the shared persistence helper was unavailable to the intents target. Both compile errors were corrected; the helper now lives in WorkoutDataKit.
- Seventh full run: 105 tests, 0 failures (`/private/tmp/IronAudit-20260922-Seventh.xcresult`). This includes Health replacement ordering/failure tests, paused Live Activity states, workout lifecycle rollback, and backup parent-save rollback.
- Root Health review caught reused HealthKit sync metadata that could make a replacement save a no-op before deleting the old sample. Replacement metadata now strips that identity, with a regression. Bulk reconciliation retains samples linked to the current workout and samples without an Iron external identifier.
- Build validated the iPhone app, widget/intents extensions, and embedded Watch app for simulator. This does not validate device provisioning.
- Root review required follow-up corrections for timer restoration, foreground-only audio, generic cancellation invalidation, and stale notification actions before accepting the timer patch.
- idb hold test: selector frame stayed at x=98.259, y=437.111, width=height=205.483 points before/during hold. Screenshots: `/private/tmp/iron-selector-before.png`, `/private/tmp/iron-selector-held.png`.
- Existing completed/incomplete row control widths match in the simulator. Green chrome extends outside controls; screenshot: `/private/tmp/iron-audit-initial.png`.
- Migration fixtures log a missing legacy exercise ID and the test host logs an app-group entitlement warning. The migration tests pass; real signed app-group access remains a device check.
