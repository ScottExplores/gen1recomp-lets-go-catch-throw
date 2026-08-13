# Compatibility and implementation notes

## Tested host surface

- Gen1Recomp API 2
- Gen1Recomp 0.1.75 Android source/runtime surface
- Gen1Recomp 0.1.80 release source/runtime surface
- Pokémon Red, Blue, and Yellow manifest targets

The manifest floor is `>=0.1.75 <2.0.0`. Older builds may contain some of the
same hooks, but the complete feature set is not claimed or tested there.

## Renderer and cameras

The mod registers only a late `render.hud` contribution. It reads Dramaless
1.6.4's exported `VoxelState`, `FirstPerson`, and `Voxel3D.project` interfaces
without writing camera state. Kanto in First Person remains responsible for
its patched ceilings, canopy, horizons, and ambience.

Dramaless 1.6.4 does not export a supported companion 3D draw callback, depth
buffer attachment, geometry collision query, or raycast. Consequently:

- the arc, ball, target marker, and impact are projected overlays;
- terrain collision uses conservative map-cell checks near ground level;
- true behind-wall/ceiling/canopy occlusion is unavailable;
- camera-follow choices safely resolve to the current camera;
- no competing world render pipeline is installed.

This is a deliberate stability boundary rather than a hidden renderer patch.

## Controller adapter

Gen1Recomp 0.1.75 exposes Game Boy mod input but no registry for new native
controller actions. A reversible adapter handles both
`Game.gamepadpressed/released` and the `triggerright`/`triggerleft` analog axes
reported by the Thor. Trigger hysteresis converts each pull/release into one
logical edge. It claims configured input only for an eligible throw state and
delegates everything else. Select-held chords always delegate.

The user's Thor maps R1/L1 to emulation speed while R2/L2 do not change speed.
R2/L2 are therefore the default Aim/Cancel bindings. R1/L1 are not used by the
default throw or ball-wheel controls and continue to reach emulator speed.

## Inventory and capture transaction

- Native Bag selection has already removed one ball before the battle adapter
  sees it; cancel/teardown refunds exactly that reservation.
- Manual overworld aim reserves nothing. Launch calls the Bag adapter once.
- Safari Ball uses the battle's Safari counter.
- Successful impact calls the host battle's `catchAttempt` and
  `storeCaughtMon`; capture math, Pokédex, party/box, nickname, OT, hooks, and
  Master Ball behavior stay canonical.
- A committed overworld throw is never refunded merely because its subsequent
  Wilds transition fails.

## Wilds of Kanto

Wilds 1.11.1 exports entity tables but no supported `beginEncounter` or direct
capture method. The adapter is therefore exact-version and capability gated.
It revalidates entity identity, state, map, visibility, and battleability, then
uses that version's encounter start seam. The hit ball is handed into the
resulting matching battle; it never removes/captures an entity directly.

Unknown/mismatched versions are not patched and simply produce normal misses.
Aggro on miss is currently status-only because there is no safe aggro API.

## FULL mode scope

FULL is an experimental capture-only battle presentation built from this mod's
own state machine. It does not implement Dramatic Shape's wider half-price mart
economy, party catch/KO experience, persistent catch combo, or unrelated 3D
battle renderer. CATCH ONLY is the recommended first-release mode.

## Independent-authoring boundary

Dramatic Shape 1.8.0's behavior was inspected to identify its public-facing
OFF/FULL/CATCH ONLY ladder and capture expectations. Its repository/archive has
no general reuse license and includes a redistribution restriction, so this
package contains no source, constants, assets, meshes, or audio from it. The
procedural ball/HUD and all implementation code here were authored separately.
