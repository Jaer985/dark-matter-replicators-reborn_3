local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Define custom planetary recipe categories
data:extend({
    { type = "recipe-category", name = gprefix .. "replication-vulcanus" },
    { type = "recipe-category", name = gprefix .. "replication-fulgora" },
    { type = "recipe-category", name = gprefix .. "replication-gleba" },
    { type = "recipe-category", name = gprefix .. "replication-aquilo" }
})

-- ── v4.4.0 (B3/C3): the tier and planetary machines share one module contract.
-- B3: with `dmrsa-replicator-quality = "Normal only"` the `quality` effect is
-- NOT offered (the machine is what the engine evaluates — the old
-- `recipe.quality = "normal"` gate in the mirror generator gated nothing).
-- C3: "consumption" is gone — an efficiency module/beacon would cut the draw
-- the replication balance is priced against.
local QUALITY_ALLOWED =
    helpers.get_startup_setting("dmrsa-replicator-quality", "Normal only") == "Allow quality"

local function planetary_allowed_effects()
    local effects = { "speed", "pollution" }
    if QUALITY_ALLOWED then
        table.insert(effects, "quality")
    end
    return effects
end

-- ── v4.4.0 (D1/G4): sprite geometry, art-calibrated ───────────────────────────
-- These machines are 2x2 (selection half 1.0) but drew replicator-3.png at
-- scale 0.66 with NO shift at all: the art sat 0.15 tiles left of its box.
-- Same rule as replicators.lua: scale = 1.0 * 2/3 = 0.6667 (95 px * 0.6667/32 =
-- 1.98 tiles in the 2x2 box) and shift = { 1.0*0.4/3 = 0.1333, 1.0*0.02 = 0.02 }.
local PLANET_SELECTION = 1.0
local PLANET_SPRITE_SCALE = PLANET_SELECTION * 2 / 3
local PLANET_SPRITE_SHIFT = { PLANET_SELECTION * 0.4 / 3, PLANET_SELECTION * 0.02 }

-- Common function to define a specialized planetary replicator
local function make_planetary_replicator(name_suffix, speed, power_mw, tint_color, surface_conds)
    local name = gprefix .. "replicator-" .. name_suffix
    
    local entity = {
        type = "assembling-machine",
        -- v4.8.0: circuit connectors, parity with vanilla assembling machines
        -- (field absent = distance 0 = wires cannot be attached: measured, see
        -- research/gate-circuit-wires.md).
        circuit_wire_max_distance = 9,
        name = name,
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
        icon_size = 64,
        icons = {
            {
                icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
                tint = tint_color
            }
        },
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.5, result = name },
        fast_replaceable_group = gprefix .. "replicator",
        max_health = 350,
        resistances = {
            {
                type = "fire",
                percent = 80
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -0.8, -0.8 }, { 0.8, 0.8 } },
        selection_box = { { -1.0, -1.0 }, { 1.0, 1.0 } },
        
        -- Native C++ replication processing
        crafting_categories = { gprefix .. "replication-" .. name_suffix },
        crafting_speed = speed,
        
        -- High power consumption (GW/MW range)
        energy_usage = power_mw .. "MW",
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input",
            emissions_per_second = 0.05
        },

        -- Optimal fluid outputs (UPS Friendly, only connects when recipe outputs fluid)
        fluid_boxes_off_when_no_fluid_recipe = true,
        fluid_boxes = {
            {
                production_type = "output",
                -- v4.0 (2.1 fix): assembler2pipepictures is now a data table
                -- in the base assembler-pictures module, not a global function.
                -- __base__/ prefix required when requiring from another mod.
                pipe_picture = require("__base__/prototypes/entity/assembler-pictures").assembler2pipepictures,
                pipe_covers = pipecoverspictures(),
                base_area = 10,
                base_level = 1,
                volume = 100,
                pipe_connections = {
                    {
                        flow_direction = "output",
                        position = { -0.5, 0.8 }, -- Properly aligned with grid and inside bounding box
                        direction = defines.direction.south,
                    }
                }
            }
        },

        -- Graphics with custom planetary tint overlays!
        graphics_set = {
            animation = {
                filename = "__dark-matter-replicators-reborn__/graphics/entity/replicator-3.png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                -- v4.4.0 (D1/G4): 0.66 → the art-calibrated 2/3, plus the
                -- shift that centres the 1.98 tiles of art in the 2x2 box.
                scale = PLANET_SPRITE_SCALE,
                shift = PLANET_SPRITE_SHIFT,
                tint = tint_color -- BEAUTIFUL VIBRANT PLANETARY TINT OVERLAYS
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
        
        module_slots = 3,
        -- v4.2 refino (original-mod study): sin "productivity" (0-ingredient
        -- recipes = duplicación gratis).
        -- v4.4.0 (B3/C3): quality gate + no "consumption" — see
        -- planetary_allowed_effects() above.
        allowed_effects = planetary_allowed_effects()
    }

    -- Apply planetary restrictions if Space Age expansion is loaded
    if mods["space-age"] and surface_conds then
        entity.surface_conditions = surface_conds
    end

    -- Add space-exploration space allowance if configured
    if helpers.get_startup_setting("replication-in-space", false) then
        entity.se_allow_in_space = true
    end

    data:extend({
        -- Item
        {
            type = "item",
            name = name,
            icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
            icon_size = 64,
            icons = {
                {
                    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
                    tint = tint_color
                }
            },
            subgroup = gprefix .. "replicators",
            order = "c-" .. name_suffix,
            place_result = name,
            stack_size = 50
        },
        -- Recipe
        {
            type = "recipe",
            name = name,
            enabled = false,
            ingredients = {
                { type = "item", name = gprefix .. "replicator-3", amount = 1 },
                { type = "item", name = gprefix .. "matter-conduit", amount = 2 }
            },
            results = {
                { type = "item", name = name, amount = 1 }
            },
            subgroup = gprefix .. "replicators",
            order = "c-" .. name_suffix
        },
        -- Entity
        entity
    })
end

-- Define the 4 planetary machines
if mods["space-age"] then
    -- 1. Vulcanus (Geothermal): Orange/Red tint, metallurgy speedup
    -- v4.2 (B2): 400MW → 40MW — the old 400-800MW was tuned for 600s
    -- replication times (200s×400MW = 80GJ/recipe, unplayable). With the
    -- rebalanced band model (8-48s nominal) the planets stay the most
    -- expensive machines in the game at ~0.1-0.6 GJ/recipe.
    make_planetary_replicator(
        "vulcanus", 
        3.0, 
        40, 
        { r = 1.0, g = 0.35, b = 0.15, a = 1.0 },
        { { property = "gravity", min = 0.5 } } -- restricts to solid surfaces
    )

    -- 2. Fulgora (Electromagnetic): Electric Cyan/Purple tint, electronics speedup
    make_planetary_replicator(
        "fulgora", 
        3.0, 
        40, 
        { r = 0.45, g = 0.15, b = 0.9, a = 1.0 },
        { { property = "gravity", min = 0.5 } }
    )

    -- 3. Gleba (Bio-Replicator): Moss Green tint, organic synthesis
    make_planetary_replicator(
        "gleba", 
        3.0, 
        40, 
        { r = 0.25, g = 0.85, b = 0.35, a = 1.0 },
        { { property = "gravity", min = 0.5 } }
    )

    -- 4. Aquilo (Cryogenic): Icy Blue tint, ultra superconductive speed
    -- (v4.2 B2: 800MW → 80MW, see above)
    make_planetary_replicator(
        "aquilo", 
        5.0, 
        80, 
        { r = 0.35, g = 0.75, b = 1.0, a = 1.0 },
        { { property = "gravity", min = 0.5 } }
    )
end
