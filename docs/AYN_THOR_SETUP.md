# AYN Thor setup

## Install the ZIP

1. Transfer `LETS_GO_CATCH_THROW-0.2.2.zip` to the Thor's Downloads folder.
2. Launch Gen1Recomp.
3. Open the launcher **MODS** tab.
4. Tap **Import mod .zip** and choose the downloaded ZIP with Android's file
   picker.
5. Confirm **Let's Go Catch & Throw 0.2.2** appears and is enabled.
6. Keep Dramaless Shape 1.6.4 and Kanto in First Person 1.60.0 enabled.
7. Relaunch if Gen1Recomp requests it.

Gen1Recomp 0.1.75 is the minimum tested Android build; 0.1.80 is also tested
and is recommended when convenient.

## Recommended first setup

Open **START → OPTIONS → CATCH & THROW**.

1. Under **PRESETS**, leave **THROW PRESET = LET'S GO**.
2. Under **CONTROLS**, confirm **AIM = R2** and **CANCEL = L2**.
3. Under **BATTLE CATCH**, confirm **LET'S GO MODE = CATCH ONLY**. It is now
   the default, so using a Bag ball in a catchable wild battle immediately
   opens the interactive throw.
4. Under **OVERWORLD**, leave **MANUAL THROW = ON**, **THROW MODE = HOLD &
   RELEASE**, and **THROW CAMERA = CURRENT**.
5. Under **DEBUG/STATUS**, open **INPUT STATUS**. R1/L1 remain the tested
   emulator-speed controls; R2/L2 are the throw controls.

## Overworld controls

- **Hold R2:** enter aim and cycle the configured range.
- **Release R2:** launch; exactly one selected Bag ball is consumed.
- **Tap L2 before launch:** cancel once; no ball is consumed.
- **Select while aiming:** open/close the ball selector.
- **D-pad left/right:** move the selector or adjust range.
- **R3:** toggle aim assist for the current throw.

Throwing is intentionally inactive while a menu/script/battle is running and
while supported Sky Ride state says the player is riding or flying.
R1/L1 continue to change emulator speed and are not ball-wheel shortcuts.

## Battle controls

After selecting a ball from the Bag in a catchable wild battle:

- Move the right stick or drag on the touchscreen to aim.
- Flick the right stick upward or release the touch to throw.
- Press A for an assisted/accessibility throw.
- Press B before launch to return to the Bag/menu and refund the ball.

## Five-minute device checklist

1. Save the game before testing.
2. Confirm R2 starts aim only in normal free-roam play.
3. Hold R2 through all five distance numbers, then release at 3.
4. Confirm the Bag count drops by exactly one.
5. Aim again, press L2, and confirm the count does not change.
6. Open the selector and try each desired layout.
7. Enter a wild battle, select a Poké Ball, cancel once, then throw once.
8. Test Dramaless diorama, 1ST, and 3RD camera modes.
9. Enter a cave/forest with Kanto First Person and confirm the camera/world
   remain unchanged. The throw overlay is not depth-occluded; this is expected.
10. If using Wilds 1.11.1, hit one visible Pokémon and confirm its matching
    species/level starts rather than an unrelated encounter.

## Troubleshooting

- **R2 does nothing:** confirm Manual Throw is ON, the player is in idle
  overworld play, and there is at least one supported ball. Keep Aim on R2;
  this release listens to the Thor's analog trigger axis as well as button
  events.
- **R1/L1 change speed:** expected. Those remain the emulator-speed controls.
- **L2 overlaps another mod action:** the warning page lists optional mod
  overlaps; rebind only if that other feature is more important while aiming.
- **No target appears:** manual throwing still works without Wilds. Exact
  target integration currently requires Wilds of Kanto 1.11.1.
- **A hit opens a normal battle:** Overworld Capture and Hit Starts Capture
  must both be ON; unsupported Wilds versions deliberately fall back.
- **Ball/arc appears over a ceiling:** expected compatibility fallback. There
  is no safe depth-attachment API in Dramaless 1.6.4.
- **Organized menu missing:** use MODS → Let's Go Catch & Throw → OPTIONS; the
  complete native schema remains available there.
- **A mod error appears:** disable this mod, relaunch, and keep the error text
  for the bug report. Its cleanup restores the controller and battle wrappers.
