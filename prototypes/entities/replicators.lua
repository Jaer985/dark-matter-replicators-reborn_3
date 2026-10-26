local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Retrieve stats from settings with robust short-circuit evaluation
local speed_base = helpers.get_startup_setting("replstats-speed-base", 1.0)
-- v4.2 (B2): speed_factor 2.0 → 1.6 — the old 1/2/4/8/16x ramp crushed
-- real replication times to 1.6-12s across ALL tiers (t5 at 16x = 0.2s for
-- cheap items). 1.6 → 1/1.6/2.56/4.1/6.55x keeps the progressive feel but
-- leaves ~2-3x more real time per recipe (user: "cada replicator aumenta la
-- velocidad, es muy rápido").
local speed_factor = helpers.get_startup_setting("replstats-speed-factor", 1.6)
local energy_base = helpers.get_startup_setting("replstats-energy-base", 256.0) -- in kW (legacy since v4.2 B2)
local energy_factor = helpers.get_startup_setting("replstats-energy-factor", 2.5) -- legacy
local pollution_base = helpers.get_startup_setting("replstats-pollution-base", 1.0)
local pollution_factor = helpers.get_startup_setting("replstats-pollution-factor", 1.75)
local size_base = helpers.get_startup_setting("replstats-size-base", 2.0)
local size_addend = helpers.get_startup_setting("replstats-size-addend", 0.0)
local module_slots_base = helpers.get_startup_setting("replstats-modules-base", 1.0)
local module_slots_addend = helpers.get_startup_setting("replstats-modules-addend", 0.5)

-- v4.2 (B2, user-approved): PER-TIER POWER TABLE (MW) — the cost shift from
-- time to POWER needs a strong monotonic ramp: 1 / 3 / 8 / 15 / 30 MW.
-- v4.2 refinement (user: "si es más lento debe ser más económico"): the 1/4/
-- 16/40/100 MW ramp was tuned for speed 1/2/4/8/16x — with speed_factor 1.6
-- (1/1.6/2.56/4.1/6.55x) the same energy per recipe lands at LOWER power:
-- slower replication, same ~MJ per recipe, more accessible grid (30MW t5).
-- replstats-energy-base / replstats-energy-factor settings are legacy.
local PER_TIER_MW = { [1] = 1, [2] = 3, [3] = 8, [4] = 15, [5] = 30 }

-- ── v4.4.0 (B3): the 'Normal only' quality gate ───────────────────────────────
-- The gate used to be applied by writing `recipe.quality = "normal"` on every
-- generated replication recipe (lib/mirror-generator.lua), a recipe property
-- that does not gate anything: what the engine really evaluates is the
-- MACHINE's `allowed_effects`. With the setting on 'Normal only' the machines
-- therefore must not offer the `quality` effect (no quality module fits the
-- slots, and an effects beacon can't grant it either); 'Allow quality' offers it.
local QUALITY_ALLOWED =
    helpers.get_startup_setting("dmrsa-replicator-quality", "Normal only") == "Allow quality"

local function replicator_allowed_effects()
    -- v4.4.0 (C3): "consumption" REMOVED. An efficiency module/beacon cuts the
    -- machine's draw without changing the ledger the balance is defined on
    -- (replication MJ per recipe at 1/3/8/15/30 MW), so a build can cross the
    -- deliberate 0.50x floor of the dark-matter loop into positive territory.
    -- "speed" stays (it draws proportionally more, energy per craft unchanged),
    -- "pollution" stays (cosmetic), "quality" is the B3 gate above.
    local effects = { "speed", "pollution" }
    if QUALITY_ALLOWED then
        table.insert(effects, "quality")
    end
    return effects
end

-- ── v4.4.0 (D1/G3): the vertical sprite shift ─────────────────────────────────
-- The 95x85 solid art sits in a 113x91 frame, centred within 1 px vertically and
-- 7 px biased to the left. `entity_corner * 0.1` therefore pushed every
-- replicator 0.08 tiles SOUTH of its grid box (leaving the visible gap at the
-- north edge); the art-calibrated value is `entity_corner * 0.02`. The X term
-- (0.4/3) cancels the 7 px bias and is unchanged.
local SHIFT_Y_FACTOR = 0.02

-- We will generate 5 tiers of Replicators
for tier = 1, 5 do
    -- Calculations for stats
    local speed = speed_base * (speed_factor ^ (tier - 1))
    -- v4.2 (B2): per-tier power table (1/4/16/40/100 MW), see PER_TIER_MW above.
    local energy_usage_str = PER_TIER_MW[tier] .. "MW"
    local pollution = pollution_base * (pollution_factor ^ (tier - 1))
    
    -- Hitbox calculations
    local size = math.max(1, math.floor(size_base + (size_addend * (tier - 1))))
    local entity_corner = size / 2
    local hitbox_corner = entity_corner - 0.2
    
    -- Pipe offset calculation (nudges pipe connection half a tile if even-sized to align with grid)
    local pipe_connector_offset = 0
    if math.floor(entity_corner) == entity_corner then
        pipe_connector_offset = -0.5
    end
    
    -- Module slots calculation
    local module_slots = math.max(0, math.floor(module_slots_base + (module_slots_addend * (tier - 1))))
    
    -- Category support
    local categories = {}
    for lower_tier = 1, tier do
        table.insert(categories, gprefix .. "replication-" .. lower_tier)
    end
    
    -- Next upgrade link
    local next_upgrade = nil
    if tier < 5 then
        local next_size = math.max(1, math.floor(size_base + (size_addend * tier)))
        if size == next_size then
            next_upgrade = gprefix .. "replicator-" .. (tier + 1)
        end
    end

    local replicator = {
        type = "assembling-machine",
        name = gprefix .. "replicator-" .. tier,
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-" .. tier .. ".png",
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.2, result = gprefix .. "replicator-" .. tier },
        fast_replaceable_group = gprefix .. "replicator",
        next_upgrade = next_upgrade,
        max_health = 150 + (tier * 50),
        resistances = {
            {
                type = "fire",
                percent = 40 + (tier * 10)
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -hitbox_corner, -hitbox_corner }, { hitbox_corner, hitbox_corner } },
        selection_box = { { -entity_corner, -entity_corner }, { entity_corner, entity_corner } },
        
        -- Native C++ replication processing
        crafting_categories = categories,
        crafting_speed = speed,
        
        -- High power consumption (GW/MW range)
        energy_usage = energy_usage_str,
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input",
            emissions_per_second = pollution / 60
        },

        -- Optimal fluid outputs (UPS Friendly, only connects when recipe outputs fluid)
        fluid_boxes_off_when_no_fluid_recipe = true,
        fluid_boxes = {
            {
                production_type = "output",
                -- v4.0 (2.1 fix): assembler2pipepictures is no longer a global
                -- function — it's a data table in the base assembler-pictures
                -- module. Referenced via __base__/ require without parens
                -- (same pattern Bob's 3.0.1 uses on 2.1).
                pipe_picture = require("__base__/prototypes/entity/assembler-pictures").assembler2pipepictures,
                pipe_covers = pipecoverspictures(),
                base_area = 10,
                base_level = 1,
                volume = 100,
                pipe_connections = {
                    {
                        flow_direction = "output",
                        position = { pipe_connector_offset, hitbox_corner }, -- STRICTLY INSIDE THE BOUNDING BOX
                        direction = defines.direction.south,
                    }
                }
            }
        },

        -- Graphics and sounds
        graphics_set = {
            animation = {
                filename = "__dark-matter-replicators-reborn__/graphics/entity/replicator-" .. tier .. ".png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                scale = entity_corner * 2 / 3,
                shift = { entity_corner * 0.4 / 3, entity_corner * SHIFT_Y_FACTOR }
            },
            -- v3.6.0: idle animation shows the replicator DIMMED when it has no
            -- recipe/input, so it visibly "turns off" instead of looking like
            -- it's always running. Uses the same sprite sheet with a dark tint;
            -- Factorio only displays it while the machine is idle.
            -- NOTE: Factorio 2.x REQUIRES idle_animation.frame_count to equal
            -- animation.frame_count (same sprite sheet) — otherwise the game
            -- refuses to load the entity. frame_count = 33 matches animation.
            idle_animation = {
                filename = "__dark-matter-replicators-reborn__/graphics/entity/replicator-" .. tier .. ".png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                -- animation_speed MUST be > 0 (Factorio rejects 0). A tiny
                -- value (0.01) makes the 33-frame cycle take ~55s, so the
                -- idle state is visually a static dimmed frame while still
                -- satisfying the > 0 constraint.
                animation_speed = 0.01,
                scale = entity_corner * 2 / 3,
                shift = { entity_corner * 0.4 / 3, entity_corner * SHIFT_Y_FACTOR },
                tint = { r = 0.55, g = 0.55, b = 0.55, a = 0.9 }
            }
        },
        working_sound = {
            sound = {
                {
                    filename = "__base__/sound/lab.ogg",
                    volume = 0.7
                }
            },
            idle_sound = { filename = "__base__/sound/idle1.ogg", volume = 0.6 },
            apparent_volume = 1.5
        },
        
        module_slots = module_slots,
        -- v4.2 refino (original-mod study): allowed_effects sin "productivity" —
                -- con recipes de 0 ingredientes la productividad es duplicación
                -- GRATIS (el exploit existe en el original; lo corregimos).
                -- v4.4.0 (B3/C3): the quality gate and the removed "consumption"
                -- effect live in replicator_allowed_effects() at the top of this
                -- file — one place, both tiers of machine.
                allowed_effects = replicator_allowed_effects(),
    }

    -- Space platform and Space Exploration compatibility
    if helpers.get_startup_setting("replication-in-space", false) then
        replicator.se_allow_in_space = true
    end

    data:extend({
        -- Item Prototype
        {
            type = "item",
            name = gprefix .. "replicator-" .. tier,
            icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-" .. tier .. ".png",
            icon_size = 64,
            subgroup = gprefix .. "replicators",
            order = "b" .. tier,
            place_result = gprefix .. "replicator-" .. tier,
            stack_size = 50
        },
        -- Recipe Category
        {
            type = "recipe-category",
            name = gprefix .. "replication-" .. tier
        },
        -- Replicator Entity
        replicator
    })
end

-- 6. Replication Lab Entity
-- v4.4.0 (D1/G4): the lab's sprite geometry, stated instead of implied — the
-- selection box is 3x3 (half 1.5), so the art-calibrated rule gives
-- scale 1.0 and shift {0.2, 0.03} (see the SHIFT_Y_FACTOR note above).
local LAB_SELECTION = 1.5
local LAB_SCALE = LAB_SELECTION * 2 / 3
local LAB_SHIFT = { LAB_SELECTION * 0.4 / 3, LAB_SELECTION * SHIFT_Y_FACTOR }

data:extend({
    {
        type = "item",
        name = gprefix .. "replication-lab",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replication-lab.png",
        icon_size = 64,
        subgroup = gprefix .. "replicators",
        order = "a",
        place_result = gprefix .. "replication-lab",
        stack_size = 50
    },
    {
        type = "lab",
        name = gprefix .. "replication-lab",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replication-lab.png",
        icon_size = 64,
        flags = { "placeable-player", "player-creation" },
        minable = { mining_time = 1, result = gprefix .. "replication-lab" },
        max_health = 150,
        corpse = "big-remnants",
        dying_explosion = "big-explosion",
        collision_box = { { -1.2, -1.2 }, { 1.2, 1.2 } },
        selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } },
        light = { intensity = 0.75, size = 8 },
        -- v4.4.0 (D1/G4): the lab is a 3x3 building: the mod's art-calibrated
        -- rule is scale = selection_half * 2/3 = 1.5 * 2/3 = 1.0 (what the
        -- missing `scale` key defaulted to — the 3.53-tile figure in the audit
        -- is the FRAME width, the solid art is 95 px = 2.97 tiles) and
        -- shift = { 1.5*0.4/3 = 0.2, 1.5*0.02 = 0.03 } instead of {0.2, 0.15}.
        on_animation = {
            filename = "__dark-matter-replicators-reborn__/graphics/entity/replication-lab.png",
            width = 113,
            height = 91,
            frame_count = 33,
            line_length = 11,
            animation_speed = 1 / 3,
            scale = LAB_SCALE,
            shift = LAB_SHIFT
        },
        off_animation = {
            filename = "__dark-matter-replicators-reborn__/graphics/entity/replication-lab.png",
            width = 113,
            height = 91,
            frame_count = 1,
            scale = LAB_SCALE,
            shift = LAB_SHIFT
        },
        working_sound = {
            sound = {
                filename = "__base__/sound/lab.ogg",
                volume = 0.7
            },
            apparent_volume = 1.5
        },
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input"
        },
        energy_usage = "60kW",
        -- v4.5.1 (gate test, author): the replication lab carries the whole
        -- mirror tree (~1,500 techs with a real modlist) and had no research
        -- speed at all. It is the tier-5 lab of the mod, so it researches at
        -- double the vanilla rate; the speed modules it accepts (2 slots) stack
        -- on top of this.
        researching_speed = 2.0,
        inputs = {
            gprefix .. "tenemut",
            gprefix .. "dark-matter-scoop",
            gprefix .. "dark-matter-transducer",
            gprefix .. "matter-conduit"
        },
        research_category = nil,
        module_slots = 2,
        allowed_module_categories = { "efficiency", "speed", "productivity" }
    }
})
