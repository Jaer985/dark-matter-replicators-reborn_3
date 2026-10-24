-- prototypes/entities/annihilation-coil.lua
-- v4.5.0: the ANNIHILATION COIL — dark matter goes in, electricity comes out.
--
-- WHY A `burner-generator`
--   The Annihilation Chamber (annihilator.lua) is a `reactor`: it lets dark
--   matter decay into HEAT and hands that heat to the vanilla
--   exchanger -> turbine chain, which costs a 5x5 machine, a water line, ~4.2
--   heat exchangers and ~7 steam turbines per unit. The coil is the other half
--   of the same physics: it threads a phased lattice through the decay and
--   takes the charge DIRECTLY, so it needs no heat stage, no water, no
--   exchangers and no turbines — one 2x2 machine on the grid.
--   `burner-generator` is the engine's own prototype type for exactly that
--   (verified in the 2.1.23 binary and in the 2.1 API docs: an entity that
--   produces power from a burner source; `burner` is the fuel side,
--   `energy_source` is the ELECTRIC OUTPUT side, `max_power_output` is the cap).
--
-- THE LEDGER (identical to the chamber — do NOT "improve" it)
--   fuel_value(dmrsa-dark-matter) = 25 GJ = 25 000 MJ
--   max_power_output              = 41.6667 MW
--   burner.effectivity            = 1.0        (NEVER above 1: >1 is free energy)
--   25 GJ / 41.6667 MW = 600.0 s per unit      (ten minutes, same as the chamber)
--   41.6667 MW x 600 s = 25.00002 GJ — 20 kJ of rounding over 25 GJ (0.00008 %),
--   the same string the chamber burns at, so the two machines' ledgers agree
--   to the gram. The coil wins on FOOTPRINT AND PLUMBING, never on joules.
--
-- FUEL LOCK
--   `fuel_categories = { "dmrsa-dark-matter-fuel" }` ONLY — the private category
--   dmrsa-dark-matter carries since v4.4.0. No vanilla burner (coal, nuclear
--   fuel, uranium cell, fusion cell) fits this machine, and dark matter fits
--   nowhere else. Anything else in that list would be a second fuel path.
--
-- NO MODULES, EVER
--   A `burner-generator` is not a crafting machine: it has no `module_slots`,
--   no `allowed_effects` and no beacon interaction of any kind, so the two
--   fields the replicators/refiner have to declare are structurally absent
--   here. There is nothing to switch off — that is the point of choosing this
--   prototype type over a disguised assembling-machine.
--
-- PLACEHOLDER GRAPHICS — measured, not guessed
--   The mod's OWN sheet, never a vanilla one (overhaul mods replace those):
--     graphics/entity/replicator-3.png = 1243 x 273 px = 11 x 3 frames of
--                                       113 x 91 (frame_count 33, line_length 11)
--     graphics/icons/replicator-3.png  = 64 x 64 px
--   The SOLID art inside a frame (alpha >= 250) is x 2..96, y 2..86 = 95 x 85 px,
--   i.e. its centre sits 7 px LEFT and 1 px UP of the 113x91 frame centre.
--   v4.4.0's audit (G1) caught the chamber scaling the FRAME instead of the art;
--   this file scales the art:
--     art_tiles_x = 95 * scale / 32  ->  scale = 2.0 * 32 / 95 = 0.67368
--     art_tiles_y = 85 * 0.67368 / 32 = 1.79 (0.105 tiles of air top+bottom —
--                   the frame aspect, not a mistake)
--     shift = { 7 * 0.67368 / 32, 1 * 0.67368 / 32 } = { 0.1474, 0.0211 } tiles,
--             which cancels the art's own bias and centres it in the 2x2 box.
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local COIL_SPRITE = "__dark-matter-replicators-reborn__/graphics/entity/replicator-3.png"
local COIL_ICON = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png"

-- Real sheet geometry (measured on disk, see header).
local FRAME_W, FRAME_H, FRAME_COUNT, LINE_LENGTH = 113, 91, 33, 11
local ART_W, ART_H = 95, 85
local ART_OFFSET_X, ART_OFFSET_Y = 7, 1

-- 2x2 footprint: the same proportion the tier machines use (selection 1.0,
-- collision 0.8 — 0.2 tiles of margin so a 2x2 build does not look glued).
local BOARD = 1.0
local HITBOX = 0.8

local SPRITE_SCALE = BOARD * 2 * 32 / ART_W
local SPRITE_SHIFT = {
    ART_OFFSET_X * SPRITE_SCALE / 32,
    ART_OFFSET_Y * SPRITE_SCALE / 32
}

-- v4.5.0: a cold cyan lattice, deliberately far from the chamber's red
-- (0.9/0.35/0.30) and from the ring's violet (0.45/0.55/1.0). Measured the way
-- the 4.4.0 audit measures it (mean RGB of the opaque pixels x tint, Rec.601):
--   icon  = 27.1 % luminance, in-world sheet = 27.7 % — both clears the 25 %
--   legibility floor the near-black tints failed.
local COIL_TINT = { r = 0.55, g = 1.0, b = 1.0, a = 1.0 }
local COIL_IDLE_TINT = { r = 0.55, g = 0.65, b = 0.68, a = 1.0 }

-- ---- the ledger, in one place ----------------------------------------------
local FUEL_GJ = 25                -- dmrsa-dark-matter fuel_value (items/dark-matter.lua)
local BURN_SECONDS = 600          -- one unit == ten minutes, exactly like the chamber
local OUTPUT_MW = FUEL_GJ * 1000 / BURN_SECONDS   -- 41.6667 MW
local MAX_POWER_OUTPUT = string.format("%.4fMW", OUTPUT_MW)

data:extend({
    -- Item (the building)
    {
        type = "item",
        name = gprefix .. "annihilation-coil",
        icons = {
            {
                icon = COIL_ICON,
                tint = COIL_TINT
            }
        },
        icon_size = 64,
        -- Same subgroup as every other DMR machine; order "g" sorts it right
        -- after the Annihilation Chamber ("f") and the Accelerator Ring ("e").
        subgroup = gprefix .. "replicators",
        order = "g",
        place_result = gprefix .. "annihilation-coil",
        stack_size = 20
    },

    -- Entity: dark matter in, grid power out, no heat stage at all.
    {
        type = "burner-generator",
        name = gprefix .. "annihilation-coil",
        icons = {
            {
                icon = COIL_ICON,
                tint = COIL_TINT
            }
        },
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.5, result = gprefix .. "annihilation-coil" },
        fast_replaceable_group = gprefix .. "annihilation-coil",
        max_health = 350,
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

        -- OUTPUT side: the electricity the coil puts on the grid. A generator
        -- uses an output priority so it is dispatched after accumulators.
        energy_source = {
            type = "electric",
            usage_priority = "secondary-output"
        },

        -- INPUT side: the private dark-matter category, effectivity exactly 1
        -- (any value above 1 would mint energy out of the fuel value).
        burner = {
            type = "burner",
            fuel_categories = { gprefix .. "dark-matter-fuel" },
            effectivity = 1.0,
            fuel_inventory_size = 1,
            burnt_inventory_size = 1,
            emissions_per_minute = { pollution = 20 }
        },

        -- 25 GJ / 600 s. The burner draws fuel only as the grid demands, so a
        -- unit always yields its full 25 GJ of electricity, spread over 600 s
        -- at full load (and longer at partial load — energy, not a timer).
        max_power_output = MAX_POWER_OUTPUT,

        animation = {
            filename = COIL_SPRITE,
            priority = "high",
            width = FRAME_W,
            height = FRAME_H,
            frame_count = FRAME_COUNT,
            line_length = LINE_LENGTH,
            animation_speed = 1 / 3,
            scale = SPRITE_SCALE,
            shift = SPRITE_SHIFT,
            tint = COIL_TINT
        },
        -- idle_animation frame_count/line_length must match the animation (the
        -- 2.1 rule the replicators/refiner/collider already follow) and
        -- animation_speed must stay > 0 (0.01 freezes it).
        idle_animation = {
            filename = COIL_SPRITE,
            priority = "high",
            width = FRAME_W,
            height = FRAME_H,
            frame_count = FRAME_COUNT,
            line_length = LINE_LENGTH,
            animation_speed = 0.01,
            scale = SPRITE_SCALE,
            shift = SPRITE_SHIFT,
            tint = COIL_IDLE_TINT
        }
    }
})
