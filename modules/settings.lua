-- LETS_GO_CATCH_THROW settings registry and live option store.
--
-- Gen1Recomp 0.1.75 exposes mod.options:define/get, but not a public setter.
-- This module therefore mirrors ManagerState:setOption when its own in-game
-- menu changes a value: the save bucket and live loader bucket are updated,
-- options are written once, and both the engine and a namespaced mod event are
-- emitted when those channels are available.  Other modules should read
-- through Settings:get so preset overrides are applied consistently.

return function(mod, shared)
  shared = shared or {}

  local Settings = {}
  Settings.MOD_ID = (mod and mod.id) or "LETS_GO_CATCH_THROW"

  local function choice(label, value, compact)
    return { label, value, compact or label }
  end

  local function add(rows, group, page, key, kind, label, default, extra)
    local row = extra or {}
    row.group = group
    row.page = page
    row.key = key
    row.type = kind
    row.label = label
    row.menu_label = row.menu_label or label
    row.default = default
    rows[#rows + 1] = row
    return row
  end

  local ON_OFF = {
    choice("OFF", false),
    choice("ON", true),
  }
  local SPEED_3 = {
    choice("SLOW", "slow"),
    choice("NORMAL", "normal"),
    choice("FAST", "fast"),
  }
  local ASSIST_4 = {
    choice("OFF", "off"),
    choice("LOW", "low"),
    choice("NORMAL", "normal"),
    choice("HIGH", "high"),
  }

  local rows = {}

  -- Battle Catch Only / Let's Go throwing.
  add(rows, "battle", "battle", "lets_go_mode", "choice", "LET'S GO MODE", "catch_only", {
    choices = {
      choice("OFF", "off"),
      choice("CATCH ONLY", "catch_only", "CATCH"),
      choice("FULL", "full"),
    },
  })
  add(rows, "battle", "battle", "battle_catch_throw", "toggle", "BATTLE CATCH THROW", true,
      { menu_label = "BATTLE THROW" })
  add(rows, "battle", "battle", "throw_input", "choice", "THROW INPUT", "both", {
    choices = {
      choice("STICK", "stick"), choice("TOUCH", "touch"),
      choice("BOTH", "both"), choice("AUTO", "auto"),
    },
  })
  add(rows, "battle", "battle", "throw_sensitivity", "choice", "THROW SENSITIVITY", "normal", {
    menu_label = "SENSITIVITY", choices = {
      choice("LOW", "low"), choice("NORMAL", "normal"), choice("HIGH", "high"),
    },
  })
  add(rows, "battle", "battle", "battle_throw_speed", "choice", "BATTLE THROW SPEED", "normal",
      { menu_label = "THROW SPEED", choices = SPEED_3 })
  add(rows, "battle", "battle", "battle_aim_assist", "choice", "BATTLE AIM ASSIST", "normal",
      { menu_label = "AIM ASSIST", choices = ASSIST_4 })
  add(rows, "battle", "battle", "battle_throw_arc", "toggle", "THROW ARC", true,
      { menu_label = "THROW ARC" })
  add(rows, "battle", "battle", "battle_ball_trail", "toggle", "BATTLE BALL TRAIL", true,
      { menu_label = "BALL TRAIL" })
  add(rows, "battle", "battle", "catch_ring", "choice", "CATCH RING", "full", {
    choices = {
      choice("OFF", "off"), choice("SIMPLE", "simple"), choice("FULL", "full"),
    },
  })
  add(rows, "battle", "battle", "catch_ring_speed", "choice", "CATCH RING SPEED", "normal",
      { menu_label = "RING SPEED", choices = SPEED_3 })
  add(rows, "battle", "battle", "camera_shake", "choice", "CAMERA SHAKE", "low", {
    choices = {
      choice("OFF", "off"), choice("LOW", "low"), choice("NORMAL", "normal"),
    },
  })
  add(rows, "battle", "battle", "battle_throw_sound", "toggle", "BATTLE THROW SOUND", true,
      { menu_label = "THROW SOUND" })
  add(rows, "battle", "battle", "battle_impact_effect", "toggle", "BATTLE IMPACT EFFECT", true,
      { menu_label = "IMPACT FX" })
  add(rows, "battle", "battle", "capture_animation", "choice", "CAPTURE ANIMATION", "lets_go", {
    menu_label = "CAPTURE ANIM", choices = {
      choice("CLASSIC", "classic"),
      choice("LET'S GO", "lets_go", "LETS GO"),
      choice("FAST", "fast"),
    },
  })
  add(rows, "battle", "debug", "debug_battle_throw", "toggle", "DEBUG BATTLE THROW", false,
      { menu_label = "DEBUG BATTLE" })

  -- Manual overworld throw and trajectory.
  -- The AYN Thor build maps the intended defaults cleanly: hold/release R2,
  -- cancel with L2.  Other builds/mod combinations still receive a visible
  -- conflict status and can rebind without changing this out-of-box path.
  add(rows, "overworld", "overworld", "manual_throw", "toggle", "MANUAL THROW", true)
  add(rows, "overworld", "overworld", "throw_mode", "choice", "THROW MODE", "hold_release", {
    choices = {
      choice("HOLD & RELEASE", "hold_release", "HOLD"),
      choice("PRESS TO AIM / PRESS TO THROW", "press_press", "2-PRESS"),
      choice("QUICK THROW", "quick", "QUICK"),
    },
  })
  add(rows, "overworld", "overworld", "max_range", "number", "MAX RANGE", 5,
      { min = 1, max = 5, step = 1 })
  add(rows, "overworld", "overworld", "min_range", "number", "MIN RANGE", 1,
      { min = 1, max = 3, step = 1 })
  add(rows, "overworld", "overworld", "charge_speed", "choice", "CHARGE SPEED", "normal", {
    choices = {
      choice("SLOW", "slow"), choice("NORMAL", "normal"),
      choice("FAST", "fast"), choice("VERY FAST", "very_fast", "V.FAST"),
    },
  })
  add(rows, "overworld", "overworld", "range_loop", "toggle", "RANGE LOOP", true)
  add(rows, "overworld", "overworld", "trajectory_line", "choice", "TRAJECTORY LINE", "dots", {
    menu_label = "TRAJECTORY", choices = {
      choice("OFF", "off"), choice("DOTS", "dots"),
      choice("SEGMENTS", "segments", "SEGMENTS"), choice("SOLID", "solid"),
    },
  })
  add(rows, "overworld", "overworld", "trajectory_thickness", "choice",
      "TRAJECTORY THICKNESS", "normal", {
        menu_label = "LINE WIDTH", choices = {
          choice("THIN", "thin"), choice("NORMAL", "normal"), choice("THICK", "thick"),
        },
      })
  add(rows, "overworld", "overworld", "trajectory_length", "choice", "TRAJECTORY LENGTH",
      "current_range", {
        menu_label = "ARC LENGTH", choices = {
          choice("CURRENT RANGE", "current_range", "CURRENT"),
          choice("FULL ARC", "full_arc", "FULL ARC"),
        },
      })
  add(rows, "overworld", "overworld", "arc_height", "choice", "ARC HEIGHT", "normal", {
    choices = {
      choice("LOW", "low"), choice("NORMAL", "normal"), choice("HIGH", "high"),
    },
  })
  add(rows, "overworld", "overworld", "overworld_throw_speed", "choice",
      "OVERWORLD THROW SPEED", "normal", { menu_label = "THROW SPEED", choices = SPEED_3 })
  add(rows, "overworld", "overworld", "ball_scale", "choice", "BALL SCALE", "normal", {
    choices = {
      choice("SMALL", "small"), choice("NORMAL", "normal"), choice("LARGE", "large"),
    },
  })
  add(rows, "overworld", "overworld", "overworld_ball_trail", "choice", "OVERWORLD BALL TRAIL",
      "normal", {
        menu_label = "BALL TRAIL", choices = {
          choice("OFF", "off"), choice("SHORT", "short"),
          choice("NORMAL", "normal"), choice("LONG", "long"),
        },
      })
  add(rows, "overworld", "overworld", "throw_camera", "choice", "THROW CAMERA", "current", {
    choices = {
      choice("CURRENT", "current"),
      choice("SLIGHT FOLLOW", "slight_follow", "SLIGHT"),
      choice("BALL FOLLOW", "ball_follow", "BALL"),
    },
  })

  -- Targeting, inventory presentation, feedback and HUD.
  add(rows, "overworld", "target_hud", "overworld_aim_assist", "choice", "OVERWORLD AIM ASSIST",
      "normal", { menu_label = "AIM ASSIST", choices = ASSIST_4 })
  add(rows, "overworld", "target_hud", "target_snap", "choice", "TARGET SNAP", "normal", {
    choices = {
      choice("OFF", "off"), choice("NEAR", "near"),
      choice("NORMAL", "normal"), choice("STRONG", "strong"),
    },
  })
  add(rows, "overworld", "target_hud", "target_highlight", "choice", "TARGET HIGHLIGHT", "both", {
    menu_label = "TARGET MARK", choices = {
      choice("OFF", "off"), choice("OUTLINE", "outline"),
      choice("ICON", "icon"), choice("BOTH", "both"),
    },
  })
  add(rows, "overworld", "target_hud", "target_range", "number", "TARGET RANGE", 5,
      { min = 1, max = 5, step = 1 })
  add(rows, "overworld", "target_hud", "auto_face_target", "toggle", "AUTO FACE TARGET", true,
      { menu_label = "AUTO FACE" })
  add(rows, "overworld", "target_hud", "default_ball", "choice", "DEFAULT BALL", "auto", {
    choices = {
      choice("AUTO", "auto"), choice("POKE BALL", "poke_ball", "POKE"),
      choice("GREAT BALL", "great_ball", "GREAT"),
      choice("ULTRA BALL", "ultra_ball", "ULTRA"),
      choice("MASTER BALL", "master_ball", "MASTER"),
      choice("SAFARI BALL", "safari_ball", "SAFARI"),
      choice("LAST USED", "last_used", "LAST"),
    },
  })
  add(rows, "overworld", "target_hud", "ball_select_mode", "choice", "BALL SELECT MODE",
      "last_used", {
        menu_label = "BALL SELECT", choices = {
          choice("LAST USED", "last_used", "LAST"),
          choice("PREFERRED", "preferred"),
          choice("BEST AVAILABLE", "best_available", "BEST"),
          choice("MANUAL", "manual"),
        },
      })
  add(rows, "overworld", "target_hud", "show_ball_count", "toggle", "SHOW BALL COUNT", true,
      { menu_label = "BALL COUNT" })
  add(rows, "overworld", "target_hud", "show_range_number", "toggle", "SHOW RANGE NUMBER", true,
      { menu_label = "RANGE NUMBER" })
  add(rows, "overworld", "target_hud", "show_target_name", "toggle", "SHOW TARGET NAME", true,
      { menu_label = "TARGET NAME" })
  add(rows, "overworld", "target_hud", "show_target_level", "toggle", "SHOW TARGET LEVEL", true,
      { menu_label = "TARGET LEVEL" })
  add(rows, "overworld", "target_hud", "show_catch_chance", "choice", "SHOW CATCH CHANCE",
      "simple", {
        menu_label = "CATCH CHANCE", choices = {
          choice("OFF", "off"), choice("SIMPLE", "simple"), choice("PERCENT", "percent"),
        },
      })
  add(rows, "overworld", "target_hud", "overworld_throw_sound", "toggle", "OVERWORLD THROW SOUND",
      true, { menu_label = "THROW SOUND" })
  add(rows, "overworld", "target_hud", "overworld_impact_sound", "toggle", "OVERWORLD IMPACT SOUND",
      true, { menu_label = "IMPACT SOUND" })
  add(rows, "overworld", "target_hud", "overworld_impact_effect", "toggle", "OVERWORLD IMPACT EFFECT",
      true, { menu_label = "IMPACT FX" })
  add(rows, "overworld", "target_hud", "miss_effect", "toggle", "MISS EFFECT", true)
  add(rows, "overworld", "target_hud", "rumble", "choice", "RUMBLE", "low", {
    choices = ASSIST_4,
  })
  add(rows, "overworld", "debug", "debug_throw", "toggle", "DEBUG THROW", false)

  -- Optional quick-select wheel.
  add(rows, "wheel", "wheel", "ball_wheel", "toggle", "BALL WHEEL", true)
  add(rows, "wheel", "wheel", "ball_wheel_button", "choice", "BALL WHEEL BUTTON", "select", {
    menu_label = "WHEEL BUTTON", choices = {
      choice("SELECT", "select"), choice("X", "x"), choice("Y", "y"),
      choice("L3", "leftstick"), choice("R3", "rightstick"), choice("OFF", "off"),
    },
  })
  add(rows, "wheel", "wheel", "ball_wheel_style", "choice", "BALL WHEEL STYLE", "horizontal", {
    menu_label = "WHEEL STYLE", choices = {
      choice("HORIZONTAL", "horizontal", "HORIZ"),
      choice("RADIAL", "radial"), choice("LIST", "list"),
    },
  })
  add(rows, "wheel", "wheel", "remember_last_ball", "toggle", "REMEMBER LAST BALL", true,
      { menu_label = "REMEMBER BALL" })

  -- Optional Wilds of Kanto adapter.
  add(rows, "wilds", "wilds", "wilds_integration", "choice", "WILDS INTEGRATION", "auto", {
    menu_label = "WILDS LINK", choices = {
      choice("AUTO", "auto"), choice("ON", "on"), choice("OFF", "off"),
    },
  })
  add(rows, "wilds", "wilds", "overworld_capture", "toggle", "OVERWORLD CAPTURE", true,
      { menu_label = "WORLD CAPTURE" })
  add(rows, "wilds", "wilds", "miss_starts_battle", "toggle", "MISS STARTS BATTLE", false,
      { menu_label = "MISS BATTLE" })
  add(rows, "wilds", "wilds", "hit_starts_capture", "toggle", "HIT STARTS CAPTURE", true,
      { menu_label = "HIT CAPTURE" })
  add(rows, "wilds", "wilds", "failed_catch_starts_battle", "toggle",
      "FAILED CATCH STARTS BATTLE", true, { menu_label = "FAIL BATTLE" })
  add(rows, "wilds", "wilds", "aggro_on_miss", "toggle", "AGGRO ON MISS", false)

  -- Dramaless/Kanto First Person camera tuning.  These are adapter choices;
  -- the mod never takes ownership of either camera.
  add(rows, "camera", "camera", "first_person_throw_origin", "choice", "1ST THROW ORIGIN",
      "right_hand", {
        menu_label = "1ST ORIGIN", choices = {
          choice("CENTER", "center"), choice("RIGHT HAND", "right_hand", "R.HAND"),
          choice("LOW RIGHT", "low_right", "LOW RIGHT"),
        },
      })
  add(rows, "camera", "camera", "third_person_throw_origin", "choice", "3RD THROW ORIGIN",
      "shoulder", {
        menu_label = "3RD ORIGIN", choices = {
          choice("PLAYER", "player"), choice("SHOULDER", "shoulder"),
          choice("CAMERA BIAS", "camera_bias", "CAM BIAS"),
        },
      })
  add(rows, "camera", "camera", "diorama_throw_origin", "choice", "DIORAMA THROW ORIGIN",
      "player", {
        menu_label = "DIO ORIGIN", choices = {
          choice("PLAYER", "player"), choice("TILE CENTER", "tile_center", "TILE"),
        },
      })
  add(rows, "camera", "camera", "camera_aim_mode", "choice", "CAMERA AIM MODE", "smart", {
    menu_label = "AIM MODE", choices = {
      choice("PLAYER FACING", "player_facing", "PLAYER"),
      choice("CAMERA FACING", "camera_facing", "CAMERA"),
      choice("SMART", "smart"),
    },
  })
  add(rows, "camera", "camera", "camera_pitch_affects_throw", "toggle",
      "CAMERA PITCH AFFECTS THROW", true, { menu_label = "PITCH THROW" })
  add(rows, "camera", "camera", "camera_yaw_affects_throw", "toggle",
      "CAMERA YAW AFFECTS THROW", true, { menu_label = "YAW THROW" })
  add(rows, "camera", "camera", "first_person_fov_compensation", "choice",
      "FIRST PERSON FOV COMPENSATION", "auto", {
        menu_label = "FOV COMP", choices = {
          choice("OFF", "off"), choice("AUTO", "auto"),
        },
      })

  -- Raw controller actions.  Gen1Recomp has no native mod action registry in
  -- 0.1.75, so these values are interpreted by this mod's scoped gamepad
  -- adapter.  They are deliberately explicit and rebindable.
  add(rows, "controls", "controls", "aim_button", "choice", "AIM BUTTON", "r2", {
    choices = {
      choice("R", "r"), choice("R2", "r2"), choice("X", "x"),
      choice("Y", "y"), choice("CUSTOM", "custom"),
    },
  })
  add(rows, "controls", "controls", "custom_aim_button", "choice", "CUSTOM AIM BUTTON",
      "rightshoulder", {
        menu_label = "CUSTOM AIM", choices = {
          choice("R", "rightshoulder"), choice("L", "leftshoulder"),
          choice("R2", "righttrigger"), choice("L2", "lefttrigger"),
          choice("X", "x"), choice("Y", "y"), choice("A", "a"), choice("B", "b"),
          choice("SELECT", "back"), choice("START", "start"),
          choice("L3", "leftstick"), choice("R3", "rightstick"),
        },
      })
  add(rows, "controls", "controls", "cancel_button", "choice", "CANCEL BUTTON", "l2", {
    choices = {
      choice("L", "l"), choice("L2", "l2"), choice("X", "x"),
      choice("Y", "y"), choice("CUSTOM", "custom"),
    },
  })
  add(rows, "controls", "controls", "custom_cancel_button", "choice", "CUSTOM CANCEL BUTTON",
      "leftshoulder", {
        menu_label = "CUSTOM CANCEL", choices = {
          choice("L", "leftshoulder"), choice("R", "rightshoulder"),
          choice("L2", "lefttrigger"), choice("R2", "righttrigger"),
          choice("X", "x"), choice("Y", "y"), choice("A", "a"), choice("B", "b"),
          choice("SELECT", "back"), choice("START", "start"),
          choice("L3", "leftstick"), choice("R3", "rightstick"),
        },
      })
  add(rows, "controls", "controls", "ball_select_button", "choice", "BALL SELECT ACTION",
      "select", {
        menu_label = "BALL SELECT", choices = {
          choice("SELECT", "select"), choice("X", "x"), choice("Y", "y"),
          choice("L3", "leftstick"), choice("R3", "rightstick"), choice("OFF", "off"),
        },
      })
  add(rows, "controls", "controls", "quick_throw_button", "choice", "QUICK THROW ACTION", "off", {
    menu_label = "QUICK THROW", choices = {
      choice("R", "rightshoulder"), choice("R2", "righttrigger"),
      choice("X", "x"), choice("Y", "y"), choice("OFF", "off"),
    },
  })
  add(rows, "controls", "controls", "range_up_button", "choice", "RANGE UP ACTION", "dpright", {
    menu_label = "RANGE UP", choices = {
      choice("DPAD RIGHT", "dpright", "D-RIGHT"), choice("R2", "righttrigger"),
      choice("X", "x"), choice("Y", "y"), choice("OFF", "off"),
    },
  })
  add(rows, "controls", "controls", "range_down_button", "choice", "RANGE DOWN ACTION", "dpleft", {
    menu_label = "RANGE DOWN", choices = {
      choice("DPAD LEFT", "dpleft", "D-LEFT"), choice("L2", "lefttrigger"),
      choice("X", "x"), choice("Y", "y"), choice("OFF", "off"),
    },
  })
  add(rows, "controls", "controls", "toggle_aim_assist_button", "choice",
      "TOGGLE AIM ASSIST ACTION", "rightstick", {
        menu_label = "TOGGLE ASSIST", choices = {
          choice("R3", "rightstick"), choice("L3", "leftstick"),
          choice("SELECT", "select"), choice("Y", "y"), choice("OFF", "off"),
        },
      })

  -- Preset selector.  Presets are resolved at read time, not destructively
  -- copied over manual values, so choosing CUSTOM restores the player's knobs.
  add(rows, "preset", "preset", "throw_preset", "choice", "THROW PRESET", "lets_go", {
    choices = {
      choice("CLASSIC", "classic"), choice("LET'S GO", "lets_go", "LETS GO"),
      choice("IMMERSIVE", "immersive"), choice("ARCADE", "arcade"),
      choice("CUSTOM", "custom"),
    },
  })

  Settings.schema = rows
  Settings.byKey = {}
  Settings.pages = {}
  Settings.groups = {}
  for _, row in ipairs(rows) do
    Settings.byKey[row.key] = row
    Settings.pages[row.page] = Settings.pages[row.page] or {}
    Settings.pages[row.page][#Settings.pages[row.page] + 1] = row
    Settings.groups[row.group] = Settings.groups[row.group] or {}
    Settings.groups[row.group][#Settings.groups[row.group] + 1] = row
  end

  Settings.PRESETS = {
    classic = {
      throw_input = "auto", battle_throw_speed = "normal",
      battle_aim_assist = "off", battle_throw_arc = false,
      battle_ball_trail = false, catch_ring = "off",
      camera_shake = "off", battle_impact_effect = false,
      capture_animation = "classic", trajectory_line = "off",
      arc_height = "low", overworld_throw_speed = "normal",
      overworld_ball_trail = "off", throw_camera = "current",
      overworld_aim_assist = "off", target_snap = "off",
      target_highlight = "off", show_target_name = false,
      show_target_level = false, show_catch_chance = "off",
      overworld_impact_effect = false, miss_effect = false, rumble = "off",
    },
    lets_go = {
      throw_input = "both", battle_throw_speed = "normal",
      battle_aim_assist = "normal", battle_throw_arc = true,
      battle_ball_trail = true, catch_ring = "full",
      catch_ring_speed = "normal", camera_shake = "low",
      battle_impact_effect = true, capture_animation = "lets_go",
      charge_speed = "normal", trajectory_line = "dots",
      arc_height = "normal", overworld_throw_speed = "normal",
      ball_scale = "normal", overworld_ball_trail = "normal",
      throw_camera = "current", overworld_aim_assist = "normal",
      target_snap = "normal", target_highlight = "both",
      show_target_name = true, show_target_level = true,
      show_catch_chance = "simple", overworld_impact_effect = true,
      miss_effect = true, rumble = "low",
    },
    immersive = {
      throw_input = "both", battle_throw_speed = "normal",
      battle_aim_assist = "low", battle_throw_arc = true,
      battle_ball_trail = false, catch_ring = "simple",
      camera_shake = "low", capture_animation = "lets_go",
      charge_speed = "normal", trajectory_line = "segments",
      trajectory_thickness = "thin", arc_height = "normal",
      overworld_throw_speed = "normal", ball_scale = "normal",
      overworld_ball_trail = "short", throw_camera = "current",
      overworld_aim_assist = "low", target_snap = "near",
      target_highlight = "outline", show_range_number = false,
      show_target_name = false, show_target_level = false,
      show_catch_chance = "off", rumble = "normal",
    },
    arcade = {
      throw_input = "auto", battle_throw_speed = "fast",
      battle_aim_assist = "high", battle_throw_arc = true,
      battle_ball_trail = true, catch_ring = "full",
      catch_ring_speed = "slow", camera_shake = "normal",
      capture_animation = "fast", charge_speed = "very_fast",
      trajectory_line = "solid", trajectory_thickness = "thick",
      arc_height = "low", overworld_throw_speed = "fast",
      ball_scale = "large", overworld_ball_trail = "long",
      overworld_aim_assist = "high", target_snap = "strong",
      target_highlight = "both", show_catch_chance = "percent",
      rumble = "high",
    },
  }

  Settings.presetControlled = {}
  for _, values in pairs(Settings.PRESETS) do
    for key in pairs(values) do Settings.presetControlled[key] = true end
  end

  Settings._memory = {}
  Settings._game = shared.game
  local CATCH_ONLY_MIGRATION = "catch_only_default_v020"

  local function resolveGame(game)
    if game then return game end
    if Settings._game then return Settings._game end
    if shared.game then return shared.game end
    local ok, world = pcall(function() return mod and mod.world end)
    if ok and world then return world.game end
    return nil
  end

  function Settings:bindGame(game)
    if game then
      self._game = game
      shared.game = shared.game or game
    end
    return game
  end

  function Settings:raw(key)
    if self._memory[key] ~= nil then return self._memory[key] end
    if mod and mod.options and type(mod.options.get) == "function" then
      local ok, value = pcall(mod.options.get, mod.options, key)
      if ok and value ~= nil then return value end
    end
    local row = self.byKey[key]
    return row and row.default or nil
  end

  function Settings:get(key)
    if key ~= "throw_preset" then
      local preset = self:raw("throw_preset") or "custom"
      local values = self.PRESETS[preset]
      if values and values[key] ~= nil then return values[key] end
    end
    return self:raw(key)
  end

  function Settings:valueLabel(key, value, compact)
    local row = type(key) == "table" and key or self.byKey[key]
    if not row then return tostring(value == nil and "" or value) end
    if value == nil then value = self:get(row.key) end
    if row.type == "toggle" then return value and "ON" or "OFF" end
    if row.type == "choice" then
      for _, item in ipairs(row.choices or {}) do
        if item[2] == value then return tostring(compact and item[3] or item[1]) end
      end
    end
    return tostring(value == nil and "" or value)
  end

  local function normalize(row, value)
    if row.type == "toggle" then
      if value == true or value == false then return value end
      if value == "on" or value == "ON" or value == 1 then return true end
      if value == "off" or value == "OFF" or value == 0 then return false end
      return nil, "expected ON/OFF"
    elseif row.type == "choice" then
      for _, item in ipairs(row.choices or {}) do
        if item[2] == value then return value end
      end
      return nil, "unsupported choice"
    elseif row.type == "number" then
      local n = tonumber(value)
      if not n then return nil, "expected number" end
      if row.min then n = math.max(row.min, n) end
      if row.max then n = math.min(row.max, n) end
      if row.step and row.step >= 1 then n = math.floor(n + 0.5) end
      return n
    elseif row.type == "text" then
      return tostring(value or "")
    end
    return nil, "unsupported option type"
  end

  local function writeBucket(bucket, modId, key, value)
    if type(bucket) ~= "table" then return false end
    bucket[modId] = bucket[modId] or {}
    bucket[modId][key] = value
    return true
  end

  function Settings:_persist(game)
    game = resolveGame(game)
    if game and type(game.writeOptions) == "function" then
      pcall(game.writeOptions, game)
    end
  end

  function Settings:_emit(key, value, game, source)
    game = resolveGame(game)
    local payload = {
      mod = self.MOD_ID, key = key, value = value,
      source = source or "settings", game = game, writer = self.MOD_ID,
    }
    local engineEvents = game and game.mods and game.mods.events
    if engineEvents and type(engineEvents.emit) == "function" then
      pcall(engineEvents.emit, engineEvents, "mod.options_changed", payload)
    end
    if mod and mod.events and type(mod.events.emit) == "function" then
      pcall(mod.events.emit, mod.events,
        "mod." .. self.MOD_ID .. ".options_changed", payload)
    end
    return payload
  end

  function Settings:_setRaw(key, value, game, source, deferWrite)
    local row = self.byKey[key]
    if not row then return false, "unknown option: " .. tostring(key) end
    local normalized, err = normalize(row, value)
    if normalized == nil and err then return false, err end
    game = resolveGame(game)
    self._memory[key] = normalized
    local wrote = true -- in-memory live value is immediately valid
    if game and game.save then
      game.save.options = game.save.options or {}
      game.save.options.modOptions = game.save.options.modOptions or {}
      writeBucket(game.save.options.modOptions, self.MOD_ID, key, normalized)
    end
    if game and game.mods then
      game.mods.modOptions = game.mods.modOptions or {}
      writeBucket(game.mods.modOptions, self.MOD_ID, key, normalized)
      if game.mods.loader then
        game.mods.loader.modOptions = game.mods.loader.modOptions or {}
        writeBucket(game.mods.loader.modOptions, self.MOD_ID, key, normalized)
      end
    end
    if mod and mod.options and type(mod.options.set) == "function" then
      pcall(mod.options.set, mod.options, key, normalized)
    end
    self:_emit(key, normalized, game, source)
    if not deferWrite then self:_persist(game) end
    return wrote, normalized
  end

  function Settings:set(key, value, game, source)
    if key ~= "throw_preset" and self.presetControlled[key]
        and self:raw("throw_preset") ~= "custom"
        and not tostring(source or ""):match("^reset")
        and not tostring(source or ""):match("^preset") then
      self:_setRaw("throw_preset", "custom", game, "manual_override", true)
    end
    local ok, result = self:_setRaw(key, value, game, source, false)
    return ok, result
  end

  function Settings:applyPreset(name, game, source)
    if name ~= "custom" and not self.PRESETS[name] then
      return false, "unknown preset: " .. tostring(name)
    end
    return self:_setRaw("throw_preset", name, game, source or "preset", false)
  end

  function Settings:_resetRows(resetRows, game, source, customAfter)
    game = resolveGame(game)
    local changed = 0
    for _, row in ipairs(resetRows or {}) do
      local ok = self:_setRaw(row.key, row.default, game, source or "reset", true)
      if ok then changed = changed + 1 end
    end
    if customAfter and self.byKey.throw_preset then
      self:_setRaw("throw_preset", "custom", game, source or "reset", true)
    end
    self:_persist(game)
    return changed
  end

  function Settings:resetGroup(group, game)
    local list = self.groups[group] or {}
    local custom = false
    for _, row in ipairs(list) do
      if self.presetControlled[row.key] then custom = true break end
    end
    return self:_resetRows(list, game, "reset_group:" .. tostring(group), custom)
  end

  function Settings:resetPage(page, game)
    local list = self.pages[page] or {}
    local custom = false
    for _, row in ipairs(list) do
      if self.presetControlled[row.key] then custom = true break end
    end
    return self:_resetRows(list, game, "reset_page:" .. tostring(page), custom)
  end

  function Settings:resetBattle(game)
    return self:_resetRows(self.groups.battle, game, "reset_battle", true)
  end

  function Settings:resetOverworld(game)
    local list = {}
    for _, group in ipairs({ "overworld", "wheel", "wilds", "camera" }) do
      for _, row in ipairs(self.groups[group] or {}) do list[#list + 1] = row end
    end
    return self:_resetRows(list, game, "reset_overworld", true)
  end

  function Settings:resetControls(game)
    return self:_resetRows(self.groups.controls, game, "reset_controls", false)
  end

  function Settings:resetAll(game)
    -- The preset row appears last, so the schema default is the final resolved
    -- behavior after every raw knob has returned to its own default.
    return self:_resetRows(self.schema, game, "reset_all", false)
  end

  local BUTTON_ALIAS = {
    r = "rightshoulder", r2 = "righttrigger",
    l = "leftshoulder", l2 = "lefttrigger",
  }

  function Settings:actionBinding(action)
    if action == "aim" then
      local value = self:get("aim_button")
      if value == "custom" then return self:get("custom_aim_button") end
      return BUTTON_ALIAS[value] or value
    elseif action == "cancel" then
      local value = self:get("cancel_button")
      if value == "custom" then return self:get("custom_cancel_button") end
      return BUTTON_ALIAS[value] or value
    elseif action == "ball_select" then
      return self:get("ball_select_button")
    elseif action == "quick_throw" then
      return self:get("quick_throw_button")
    elseif action == "range_up" then
      return self:get("range_up_button")
    elseif action == "range_down" then
      return self:get("range_down_button")
    elseif action == "toggle_aim_assist" then
      return self:get("toggle_aim_assist_button")
    end
    return nil
  end

  local function findMod(id)
    if not (mod and type(mod.find) == "function") then return nil end
    local ok, handle = pcall(mod.find, id)
    if not ok then ok, handle = pcall(mod.find, mod, id) end
    return ok and handle or nil
  end

  function Settings:integrationStatus()
    return {
      dramaless = findMod("DRAMALESS_SHAPE") ~= nil,
      kanto_first_person = findMod("ds_fp_ceiling") ~= nil,
      wilds = findMod("overworld_wild_spawns") ~= nil,
      sky_ride = findMod("DRAMATIC_SKY_RIDE") ~= nil,
    }
  end

  function Settings:inputConflicts(game)
    local conflicts = {}
    local seen = {}
    local function warn(code, label, message)
      if seen[code] then return end
      seen[code] = true
      conflicts[#conflicts + 1] = { code = code, label = label, message = message }
    end
    local actions = {
      aim = self:actionBinding("aim"),
      cancel = self:actionBinding("cancel"),
      ball_select = self:actionBinding("ball_select"),
      quick_throw = self:actionBinding("quick_throw"),
      range_up = self:actionBinding("range_up"),
      range_down = self:actionBinding("range_down"),
      toggle_aim_assist = self:actionBinding("toggle_aim_assist"),
    }
    -- Scott's AYN Thor reports R1/L1 as the physical emulation-speed
    -- controls.  Its analog R2/L2 inputs arrive through the trigger-axis
    -- adapter and are the intentional throw defaults.
    local coreSpeed = {
      rightshoulder = true,
      leftshoulder = true,
    }
    for action, button in pairs(actions) do
      if coreSpeed[button] then
        warn("core:" .. action, "CORE SPEED",
          (action:gsub("_", " "):upper()) .. " uses " .. tostring(button):upper()
          .. ". R1/L1 are reserved for emulator speed on the tested AYN "
          .. "Thor. Use the default R2/L2 trigger-axis bindings for throws.")
      end
    end
    local owners = {}
    for action, button in pairs(actions) do
      if button and button ~= "off" then
        if owners[button] then
          warn("duplicate:" .. button, "DUPLICATE BIND",
            owners[button]:upper() .. " and " .. action:gsub("_", " "):upper()
            .. " are both bound to " .. tostring(button):upper() .. ".")
        else
          owners[button] = action:gsub("_", " ")
        end
      end
    end
    local status = self:integrationStatus()
    if status.sky_ride then
      local skyButtons = {
        x = true, y = true, righttrigger = true, lefttrigger = true,
      }
      for action, button in pairs(actions) do
        if skyButtons[button] then
          warn("sky:" .. action, "SKY RIDE",
            (action:gsub("_", " "):upper()) .. " shares "
            .. tostring(button):upper() .. " with Dramatic Sky Ride. Rebind it "
            .. "or keep throwing disabled while riding/flying.")
        end
      end
    end
    if status.kanto_first_person then
      for action, button in pairs(actions) do
        if button == "x" or button == "y" then
          warn("kfp:" .. action, "KANTO 1ST",
            (action:gsub("_", " "):upper()) .. " may share "
            .. tostring(button):upper() .. " with Kanto First Person jump controls.")
        end
      end
    end
    if status.dramaless then
      for action, button in pairs(actions) do
        if button == "leftstick" or button == "rightstick" then
          warn("dramaless:" .. action, "DRAMALESS",
            (action:gsub("_", " "):upper()) .. " may share a stick-click with "
            .. "Dramaless camera or zoom controls.")
        end
      end
    end
    return conflicts
  end

  function Settings:hasInputConflicts(game)
    return #self:inputConflicts(game) > 0
  end

  if mod and mod.options and type(mod.options.define) == "function" then
    mod.options:define(rows)
  end
  if mod and mod.events and type(mod.events.on) == "function" then
    mod.events:on("game.ready", function(payload)
      local game = payload and payload.game
      if game then Settings:bindGame(game) end

      -- v0.1.0 shipped LET'S GO MODE = OFF. Gen1Recomp preserves explicit
      -- option buckets across an update, so changing the schema default alone
      -- would leave an existing Thor install in vanilla mode. Migrate that old
      -- value once; after this marker is written, an intentional OFF selection
      -- remains respected.
      if game and mod.save and type(mod.save.get) == "function"
          and type(mod.save.set) == "function" then
        local okDone, done = pcall(mod.save.get, mod.save,
                                   CATCH_ONLY_MIGRATION, false)
        if okDone and done ~= true then
          if Settings:raw("lets_go_mode") == "off" then
            Settings:_setRaw("lets_go_mode", "catch_only", game,
                             "migration:0.2.0", false)
          end
          pcall(mod.save.set, mod.save, CATCH_ONLY_MIGRATION, true)
        end
      end
    end)
    -- A Mod Manager edit writes the live loader bucket itself. Drop a stale
    -- in-memory menu override so subsequent reads observe that external edit.
    mod.events:on("mod.options_changed", function(payload)
      if payload and payload.mod == Settings.MOD_ID
          and payload.writer ~= Settings.MOD_ID then
        Settings._memory[payload.key] = nil
      end
    end)
  end

  shared.settings = Settings
  return Settings
end
