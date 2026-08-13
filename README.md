# Let's Go Catch & Throw

Standalone, independently authored Gen1Recomp mod for interactive wild-battle
catching and manual overworld Poké Ball throws. It is designed to coexist with
Dramaless Shape and Kanto in First Person; it does not depend on, replace, or
impersonate Dramatic Shape.

Version 0.2.1 is an early public beta for Pokémon Red, Blue, and Yellow. It has
been loader-tested against Gen1Recomp 0.1.75 and 0.1.80. The first physical AYN
Thor playtest is still recommended before treating the controller/rendering
tuning as final.

## Install

1. Copy `LETS_GO_CATCH_THROW-0.2.1.zip` to the Android device.
2. Open the Gen1Recomp launcher and select **MODS**.
3. Select **Import mod .zip**, choose the ZIP, and enable **Let's Go Catch &
   Throw**.
4. Restart/relaunch the game if Gen1Recomp asks.
5. In game, open **START → OPTIONS → CATCH & THROW**.

The ZIP is ready to import as-is. Do not unzip it into another wrapper folder.
Version 0.2.1 also enables Gen1Recomp's GitHub release update checks for future
releases from `ScottExplores/gen1recomp-lets-go-catch-throw`.

## AYN Thor quick start

The default preset is **LET'S GO**. Catch Only and manual overworld throwing
start enabled with the user's tested Thor bindings:

- Hold **R2** to ready a ball and cycle the 1–5 block range.
- Release **R2** to commit and throw one ball.
- Press **L2** before release to cancel without spending a ball.
- Press **Select** while aiming to open the ball selector.
- D-pad left/right changes the range or moves through the selector.

**R1/L1 are never claimed by the default throw controls.** They remain the
Thor's emulator-speed buttons. R2/L2 are read from the Thor's analog trigger
axes and are claimed only during an eligible overworld throw.

The adapter claims those controls only during eligible free-roam throwing. It
does nothing in menus, cutscenes, battles, links, or while Dramatic Sky Ride is
riding/flying. The Controls page reports known overlaps and allows rebinding.

See [docs/AYN_THOR_SETUP.md](docs/AYN_THOR_SETUP.md) for the complete setup and
playtest checklist.

## Battle catching

**LET'S GO MODE** defaults to **CATCH ONLY**. In a catchable wild battle, use a
Poké Ball from the ordinary Bag and the interactive throw begins automatically.
Updating from 0.1.0 migrates its old OFF default once; you can still select OFF
afterward whenever you want vanilla throws.

- **CATCH ONLY** intercepts a supported ball selected from the real Bag in a
  catchable wild battle. Aim with the right stick/touch, flick upward or press
  A for the accessible throw, and press B before launch to cancel/refund.
- **FULL (experimental)** turns ordinary wild battles into a capture-only
  loop, automatically offering the next available real Bag ball. B leaves the
  encounter. It intentionally does not recreate Dramatic Shape's unrelated
  shop-price, catch-combo, or party-EXP rules.
- Safari Balls use the Safari counter rather than Bag inventory.
- The ball is spent exactly once on launch. Aim/cancel is free.
- Capture resolution calls Gen1Recomp's own `catchAttempt`, including HP,
  status, ball definitions, mod hooks, and guaranteed Master Ball behavior.
- Scripted demos, trainer/link battles, ghosts, and no-catch battles delegate
  unchanged to the game.

## Overworld throwing

Manual throws use the real Bag and a deterministic five-stage parabolic arc.
Without a supported visible target, the ball simply animates and misses. With
Wilds of Kanto 1.11.1, a hit is tied to that exact visible entity and can start
its matching wild battle. Optional hit-to-capture hands the already-spent ball
into that battle, where the normal Gen1Recomp capture calculation resolves it.

The quick selector supports horizontal, radial, and list layouts. Presets,
target assistance, ball selection, range/arc/trail styling, camera origins,
feedback, controls, status, debug HUD, per-page restore, group reset, and
restore-all are available in the organized menu. The ordinary Mod Manager
option list remains a complete fallback if the organized screen cannot load.

## Compatibility

| Component | Behavior |
| --- | --- |
| Gen1Recomp | API 2; tested on 0.1.75 and 0.1.80 |
| Red / Blue / Yellow | Supported |
| Dramaless Shape 1.6.4 | Optional read-only camera/projection adapter |
| Kanto in First Person 1.60.0 | Compatible; remains owner of ceilings, canopy, and camera |
| Wilds of Kanto 1.11.1 | Optional, exact-version guarded target/encounter adapter |
| Dramatic Sky Ride 0.1.6 | Optional state guard pauses throwing while riding/flying |
| Dramatic Shape | Neither required nor modified |

## Important clean-integration limits

These boundaries prevent the mod from destabilizing Dramaless/Kanto First
Person:

- Dramaless 1.6.4 exposes camera projection but no supported companion
  depth-draw or raycast API. Balls, arcs, and highlights are therefore a
  projected HUD overlay and may draw in front of walls, cave ceilings, forest
  canopy, or buildings. The mod deliberately does not replace/patch the world
  renderer to fake occlusion.
- **SLIGHT FOLLOW** and **BALL FOLLOW** safely behave as **CURRENT** until a
  companion camera-control API exists. All origin, facing, pitch, and yaw
  options work without taking camera ownership.
- Wilds 1.11.1 has no public direct-capture/removal or aggro API. A hit starts
  the exact target's real battle; **AGGRO ON MISS** records an unavailable
  status instead of mutating Wilds internals. Unsupported Wilds versions
  degrade to harmless misses.
- Gen1Recomp 0.1.75 has no native custom mod-action registry. The rebindable
  controller adapter is narrowly scoped, translates the Thor's analog R2/L2
  axes, and always preserves Select-held engine chords. R1/L1 remain available
  for emulator speed; optional custom binding conflicts are shown in status.

More detail is in
[docs/COMPATIBILITY_AND_LIMITS.md](docs/COMPATIBILITY_AND_LIMITS.md).

## Testing

The package includes ROM-free unit suites for settings, support adapters,
battle transactions, controller/world state, rendering, and a production API-2
loader smoke test. The current automated total is reported in
[tests/README.md](tests/README.md).

## Independent implementation and license

Dramatic Shape 1.8.0 was studied only as a behavioral reference. Its source and
assets are not redistributed, copied, required, or bundled. This mod uses new
Lua code and procedural HUD graphics and is released under the MIT License; see
[LICENSE](LICENSE).

Pokémon names and game content belong to their respective owners. This is an
unofficial fan-made interoperability mod.
