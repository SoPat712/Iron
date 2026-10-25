# Agent guide for Iron

Iron is a SwiftUI strength-training app for iPhone and Apple Watch (Core Data model in `WorkoutDataKit`).

## Read before any UI work

1. [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md): colors, type, spacing, components, motion, haptics, sounds and copy. To restyle a screen from a screenshot, follow §16.
2. [`docs/DESIGN_BACKLOG.md`](docs/DESIGN_BACKLOG.md): approved build specs (B1–B10), lane and file ownership, and build and install commands.
3. [`docs/HANDOFF.md`](docs/HANDOFF.md): mission, current state, owner preferences, the prioritized task list, and the UI ideas log.

## Hard rules

- Never commit, push, stash, reset or checkout unless the person running you explicitly says to. Never touch `reference-material/`.
- Apple Health: only workouts completed in Iron are exported. Imported workouts (`Workout.importSource != nil`) are never exported.
- No new package dependencies. Register new Swift files in `Iron.xcodeproj/project.pbxproj`.
- Use `IronTheme` roles, `Font.ironMetric` and `IronMotion` tokens. No hard-coded colors and no rounded font design.
- Preserve existing persistence, Watch sync, Live Activity, and accessibility behavior when changing visuals.

## Build

See `docs/DESIGN_BACKLOG.md` §0.3. Packages are pre-cloned in `/tmp/iron-spm`. Pass `-disableAutomaticPackageResolution`.
