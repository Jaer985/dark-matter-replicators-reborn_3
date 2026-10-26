-- prototypes/entities/collider.lua
-- v4.4.0 (Part B): the ACCELERATOR RING — the only machine that makes dark matter.
--
-- WHY THIS EXISTS
--   dmrsa-dark-matter shipped in v4.x as a hidden, unused placeholder item (a
--   reserved carrier). This is the machine that finally produces it: tenemut
--   clusters are hurled into each other at 250 MW until the debris collapses
--   into raw dark matter, which the Annihilation Chamber (annihilator.lua) then
--   burns back into heat.
--
-- THE ENERGY LEDGER (load-bearing — do NOT change one side without the other)
--   IN   = 250 MW x 200 s = 50 GJ per dark matter (crafting_speed = 1, so the
--          200 s recipe costs 200 s of wall clock on one ring)
--   OUT  = 25 GJ (fuel_value of dmrsa-dark-matter, see prototypes/items/dark-matter.lua)
--   ratio OUT/IN = 0.50x at duplication L0 / 1.00x at L1 / 1.50x at L2 / 2.00x at L3
--          (the duplication research adds change-recipe-productivity to the
--          recipe; at L3 the ring nets +50 GJ per 200 s cycle = +250 MW per ring)
--   A shorter recipe is a POWER PRINTER at L0: at the originally briefed 40 s the
--   ring would return 25 GJ for 10 GJ (2.45x positive with zero research). The
--   200 s lives in prototypes/recipes/dark-matter-power.lua and the 250MW lives
--   here: both numbers are part of the balance, not cosmetics.
--
-- MODULES
--   4 slots. Direct modules: vanilla SPEED modules (allowed_module_categories
--   includes "speed") plus the NEW `dmrsa-collider` category, which is reserved
--   for a future DMR focusing/beam module and currently has no members.
--   Productivity modules are impossible (the category is absent) and so are
--   efficiency modules — deliberately, see below.
--   allowed_effects = { "speed" } ONLY, and that is the whole module contract:
--     * speed beacons raise throughput and the machine draws power in the SAME
--       proportion (energy per craft unchanged = the ladder self-balances);
--     * productivity is FORBIDDEN (it would stack on top of the duplication
--       research and overdrive the ladder past 2.00x at L3);
--     * "consumption" is FORBIDDEN too — an efficiency beacon could cut the
--       250 MW draw and break the L0 0.50x floor (at the -80% floor the ring
--       would return 25 GJ for 10 GJ = 2.5x POSITIVE with zero research).
--   Do not widen allowed_effects without redoing the ledger at the top of this file.
--
-- PLACEHOLDER GRAPHICS
--   The mod's OWN sprite sheet, tinted — never a vanilla sheet (overhaul mods such
--   as Bob's replace those). Verified on disk before use:
--     graphics/entity/replicator-5.png  = 1243 x 273 px = 11 x 3 frames of 113x91
--                                         -> frame_count 33, line_length 11
--                                         (the exact geometry the tier-5 replicator
--                                         and the Quality Refiner already use)
--     graphics/icons/replicator-5.png   = 64 x 64 px
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local RING_SPRITE = "__dark-matter-replicators-reborn__/graphics/entity/replicator-5.png"
local RING_ICON = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png"
-- Real sheet geometry (see header) — do not invent these numbers.
local FRAME_W, FRAME_H, FRAME_COUNT, LINE_LENGTH = 113, 91, 33, 11

-- v4.4.0 (D7, audit I2): 0.25/0.30/0.85 multiplied the icon's pixels down to
-- 11.4 % luminance — a dark silhouette (the audit measured 12 %). 0.45/0.55/1.0
-- is the same violet at 18.1 %. ONE constant: item icon, entity icon and the in-world
-- animation/idle_animation all use it (RING_IDLE_TINT stays the dimmed grey).
local RING_TINT = { r = 0.45, g = 0.55, b = 1.0, a = 1.0 }
local RING_IDLE_TINT = { r = 0.55, g = 0.55, b = 0.55, a = 0.9 }

-- 7x7 footprint (plan §2 "big footprint"): selection 3.5, collision 3.2 — the same
-- 0.3-tile proportion the 2x2 replicators use (selection 1.0 / collision 0.8).
local BOARD = 3.5
local HITBOX = BOARD - 0.3
-- The mod's own placeholder scaling rule (entity_corner * 2 / 3, see replicators.lua)
-- so the ring reads as a scaled-up replicator instead of a differently-scaled sprite.
local SPRITE_SCALE = BOARD * 2 / 3
-- v4.4.0 (D1/G2): the Y term was `BOARD * 0.1` = 0.35 tiles — the art is
-- vertically centred in its frame within 1 px, so that just pushed the 6.20-tile
-- ring 0.12 tiles past the south edge of the 7x7 box and left 0.68 tiles of empty
-- ground at the north edge (and the error grows with machine size: it was 0.08
-- tiles on a 2x2). Art-calibrated: `BOARD * 0.02` = 0.07 → 0.40 tiles of air top
-- and bottom, symmetric. The X term (0.4667) cancels the art's 7 px left bias
-- and is unchanged: art lands at x -3.51 .. +3.42 against the +-3.5 selection box.
local SPRITE_SHIFT = { BOARD * 0.4 / 3, BOARD * 0.02 }

-- The ledger's other half (see header).
local ENERGY_USAGE = "250MW"

data:extend({
    -- Recipe category: only the Accelerator Ring can run collision recipes.
    {
        type = "recipe-category",
        name = gprefix .. "collision"
    },

    -- Module category: reserved for future dark-matter collider modules. It MUST
    -- exist for allowed_module_categories below to reference it (an unknown module
    -- category is a data-stage error).
    {
        type = "module-category",
        name = gprefix .. "collider"
    },

    -- Item (the building)
    {
        type = "item",
        name = gprefix .. "collider",
        icons = {
            {
                icon = RING_ICON,
                tint = RING_TINT
            }
        },
        icon_size = 64,
        subgroup = gprefix .. "power",
        order = "b",
        place_result = gprefix .. "collider",
        stack_size = 20
    },

    -- Entity (placeholder: the mod's own tier-5 replicator sheet, violet tinted)
    {
        type = "assembling-machine",
        -- v4.8.0: circuit connectors, parity with vanilla assembling machines
        -- (field absent = distance 0 = wires cannot be attached: measured, see
        -- research/gate-circuit-wires.md).
        circuit_wire_max_distance = 9,
        name = gprefix .. "collider",
        icons = {
            {
                icon = RING_ICON,
                tint = RING_TINT
            }
        },
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.5, result = gprefix .. "collider" },
        fast_replaceable_group = gprefix .. "collider",
        max_health = 600,
        resistances = {
            {
                type = "fire",
                percent = 80
            },
            {
                type = "explosion",
                percent = 30
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -HITBOX, -HITBOX }, { HITBOX, HITBOX } },
        selection_box = { { -BOARD, -BOARD }, { BOARD, BOARD } },

        crafting_categories = { gprefix .. "collision" },
        crafting_speed = 1,
        energy_usage = ENERGY_USAGE,
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input"
            -- L1 (review r1): `emissions_per_second` removed — burner-only
            -- field, ignored on an electric source (and reported unused by
            -- --check-unused-prototype-data). The ring is a 250 MW machine
            -- whose cost is already the balance; it does not pollute.
        },

        graphics_set = {
            animation = {
                filename = RING_SPRITE,
                priority = "high",
                width = FRAME_W,
                height = FRAME_H,
                frame_count = FRAME_COUNT,
                line_length = LINE_LENGTH,
                animation_speed = 1 / 3,
                scale = SPRITE_SCALE,
                shift = SPRITE_SHIFT,
                tint = RING_TINT
            },
            -- Factorio 2.x requires idle_animation.frame_count to equal
            -- animation.frame_count on the same sheet, and animation_speed > 0
            -- (the replicators/refiner/synthesizer use the same values).
            idle_animation = {
                filename = RING_SPRITE,
                priority = "high",
                width = FRAME_W,
                height = FRAME_H,
                frame_count = FRAME_COUNT,
                line_length = LINE_LENGTH,
                animation_speed = 0.01,
                scale = SPRITE_SCALE,
                shift = SPRITE_SHIFT,
                tint = RING_IDLE_TINT
            }
            -- L1 (review r1): `light` REMOVED (it used to sit on the entity).
            -- The review suggested moving it to `graphics_set.light`, but in
            -- 2.1.20 neither the entity nor CraftingMachineGraphicsSet has a
            -- `light` property: the engine accepted the field and then reported
            -- it as unused data (ROOT.assembling-machine.dmrsa-collider
            -- .graphics_set.light was not used), and NO vanilla assembling
            -- machine carries one (vanilla lamps are `working_visualisations`
            -- with draw_as_glow). Shipping a field the engine ignores is worse
            -- than no light at all: the glow has to be a working visualisation,
            -- which is an art change, not a warning cleanup.
        },

        working_sound = {
            sound = {
                {
                    filename = "__base__/sound/lab.ogg",
                    volume = 0.7
                }
            },
            idle_sound = { filename = "__base__/sound/idle1.ogg", volume = 0.6 }
            -- L1 (review r1): `apparent_volume` removed — not a 2.1
            -- working_sound field (reported as unused data).
        },

        -- See the MODULES note in the header: the slots are reserved for the
        -- dmrsa-collider module category, and no productivity may ever amplify
        -- the 0.50x -> 2.00x ladder.
        module_slots = 4,
        allowed_effects = { "speed" },
        allowed_module_categories = { "speed", gprefix .. "collider" }
    }
})
