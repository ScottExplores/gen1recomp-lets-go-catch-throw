# Test suites

The tests are ROM-free and can run from the mod root with a Lua 5.1-compatible
runtime:

```text
lua tests/settings_test.lua
lua tests/support_test.lua
lua tests/battle_test.lua
lua tests/overworld_test.lua
lua tests/renderer_test.lua
```

`engine_bag_battle_integration.lua` additionally drives the production
Gen1Recomp `BagMenu`, `Bag`, and `BattleState` against the ROM-free fixture
dataset. It verifies the real pre-debit/refund/catch/store/failure flow on both
tested engine versions.

`full_load.lua` additionally loads the actual API-2 engine loader. Set:

- `LETSGO_MOD_PARENT` to the folder containing `lets_go_catch_throw`;
- `LETSGO_ENGINE_ROOT` to a Gen1Recomp checkout/extracted game source;
- `LETSGO_FIXTURE_ROOT` to a checkout containing the ROM-free loader fixtures.

It verifies manifest/schema loading, module installation, controller patches,
exports, cleanup, and ownership-safe restoration.

The pre-package verification run covers:

- settings schema/persistence/presets/resets;
- camera/inventory/trajectory/Wilds support adapters;
- Bag/Safari/pending-overworld battle transactions and native queue ordering;
- R2/L2 button fallback plus Thor analog-trigger axes, quick/two-press modes,
  scoped ownership, Select wheel access, and cleanup;
- trajectory/target/HUD/selector/impact rendering and graphics restoration;
- complete API-2 loading on Gen1Recomp 0.1.75 and 0.1.80.

The final focused run passes **556 checks** under both standard Lua and
LuaJIT, plus 35 real-engine Bag/Battle checks and 15 production-loader checks
on each tested Gen1Recomp version.
