# Changelog

## 0.2.1 — 2026-08-13

- Added the public GitHub repository metadata used by Gen1Recomp's built-in
  release update checker.
- No gameplay behavior changed from 0.2.0.

## 0.2.0 — 2026-08-12

- Enabled Catch Only by default so choosing a supported Bag ball in a
  catchable wild battle immediately starts the interactive throw.
- Added a one-time 0.1.0 options migration so existing installs also move from
  the old OFF default to Catch Only; later intentional OFF choices are kept.
- Added real AYN Thor analog-axis handling for R2 aim/release and L2 cancel.
- Kept R1/L1 exclusively available for emulator speed under the default
  controls and removed their hidden ball-wheel shortcuts.
- Tightened controller ownership so unrelated buttons and ineligible trigger
  input continue through the game unchanged.
- Expanded controller regression and production-loader coverage.

## 0.1.0 — 2026-08-12

- Added standalone Catch Only and experimental Full capture modes.
- Added real Gen1Recomp Bag/Safari transactions and native catch resolution.
- Added five-stage manual overworld throwing with R2 aim/release and L2 cancel
  defaults for the AYN Thor.
- Added parabolic trajectory, procedural ball, trails, timing ring, impact
  feedback, target HUD, debug HUD, and three ball-selector layouts.
- Added optional read-only Dramaless/Kanto First Person camera integration.
- Added exact-target Wilds of Kanto 1.11.1 encounter handoff.
- Added Dramatic Sky Ride input guard.
- Added complete schema options, organized nine-page menu, presets, warnings,
  per-page restore, and battle/world/control/all resets.
- Added ROM-free unit and API-2 loader test suites for Gen1Recomp 0.1.75/0.1.80.
