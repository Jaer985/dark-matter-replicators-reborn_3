-- prototypes/entities/synthesizer.lua
-- v4.3 (mod portal request, evil_star): the Dark Matter Synthesizer — the
-- ore-free path to tenemut.
--
-- WHY THIS EXISTS
--   tenemut is not just an ore: it is the tier-1 material research pack AND
--   the input of the first Dark Matter Scoop recipe. Without tenemut ore the
--   whole replication chain is unreachable, so "no ore in the world" needs a
--   non-ore source. This machine pulls tenemut straight out of the vacuum
--   using electricity and nothing else.
--
-- BALANCE (user-approved 2026-10-16)
--   1 MW, 4 s per tenemut  →  4 MJ per unit. A vanilla electric mining drill
--   (90 kW) needs 2.5 s of mining_time per ore ≈ 225 kJ, so electricity
--   synthesis costs roughly 18x the energy of the ore it replaces — the grid
--   is the price of not exploring. One steam engine (900 kW) is not enough to
--   feed it: it needs its own power plant early on.
--
-- EXPLOIT GUARDS (this is the failure class the v4.2 rebalance already hit
-- once — "productivity on 0-ingredient recipes = free duplication"):
--   * recipe:  hide_from_player_crafting = true — an ingredient-less recipe
--              that is hand-craftable means INFINITE free items in the
--              player's crafting menu, so it must never be hand-craftable.
--   * recipe:  allow_productivity = false — no productivity module or beacon
--              may multiply a recipe that consumes nothing.
--   * machine: module_slots = 0 and allowed_effects = { "consumption" } —
--              allowed_effects also governs beacons, so speed beacons cannot
--              turn "the grid is the cost" into a rounding error.
--
-- The whole subsystem only exists when the startup setting
-- `dmrsa-tenemut-source` is "Ore patches + synthesis" or "Synthesis only".
-- With the historical default ("Ore patches") this file returns early and the
-- mod is byte-for-byte the mod it was before v4.3.
--
-- Placeholder graphics: DMR's own replication-lab sprite (113x91, 33 frames,
-- line_length 11 — the real geometry used by the lab, not memory) with the
-- dark-matter violet tint. Icons are tinted tenemut/lab icons.
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

if not helpers.tenemut_synthesis_enabled() then
    return
end

local DARK_MATTER_TINT = { r = 0.25, g = 0.05, b = 0.35, a = 1.0 }
local SYNTH_TINT = { r = 0.35, g = 0.25, b = 0.65, a = 1.0 }
local TENEMUT_ICON = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
local LAB_ICON = "__dark-matter-replicators-reborn__/graphics/icons/replication-lab.png"
local LAB_SPRITE = "__dark-matter-replicators-reborn__/graphics/entity/replication-lab.png"

-- Energy per tenemut (MJ) = energy_usage × energy_required = 1 MW × 4 s.
local SYNTHESIS_TIME = 4

data:extend({
    -- Recipe category — only the synthesizer can run the synthesis recipe.
    {
        type = "recipe-category",
        name = gprefix .. "synthesis"
    },

    -- Item (the building)
    {
        type = "item",
        name = gprefix .. "tenemut-synthesizer",
        icons = {
            {
                icon = LAB_ICON,
                tint = DARK_MATTER_TINT
            }
        },
        icon_size = 64,
        subgroup = gprefix .. "power",
        order = "a",
        place_result = gprefix .. "tenemut-synthesizer",
        stack_size = 50
    },

    -- Entity (placeholder: our own replication-lab sprite, violet tinted)
    {
        type = "assembling-machine",
        -- v4.8.0: circuit connectors, parity with vanilla assembling machines
        -- (field absent = distance 0 = wires cannot be attached: measured, see
        -- research/gate-circuit-wires.md).
        circuit_wire_max_distance = 9,
        name = gprefix .. "tenemut-synthesizer",
        icons = {
            {
                icon = LAB_ICON,
                tint = DARK_MATTER_TINT
            }
        },
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.2, result = gprefix .. "tenemut-synthesizer" },
        fast_replaceable_group = gprefix .. "replicator",
        max_health = 350,
        resistances = {
            {
                type = "fire",
                percent = 60
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -1.2, -1.2 }, { 1.2, 1.2 } },
        selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } },
        crafting_categories = { gprefix .. "synthesis" },
        crafting_speed = 1,
        -- 1 MW: the whole cost of going ore-free.
        energy_usage = "1MW",
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input",
            emissions_per_second = 0.04
        },
        graphics_set = {
            animation = {
                filename = LAB_SPRITE,
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                shift = { 0.2, 0.15 },
                tint = SYNTH_TINT
            },
            -- Factorio 2.x requires idle_animation.frame_count to match
            -- animation.frame_count, and animation_speed must be > 0.
            idle_animation = {
                filename = LAB_SPRITE,
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 0.01,
                shift = { 0.2, 0.15 },
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
        light = { intensity = 0.6, size = 6 },
        -- NO modules and no beacons: electricity IS the balance.
        module_slots = 0,
        allowed_effects = { "consumption" }
    },

    -- Build recipe (unlocked by the synthesis technology)
    {
        type = "recipe",
        name = gprefix .. "tenemut-synthesizer",
        enabled = false,
        ingredients = {
            { type = "item", name = "iron-plate", amount = 25 },
            { type = "item", name = "copper-plate", amount = 15 },
            { type = "item", name = "electronic-circuit", amount = 15 },
            { type = "item", name = "pipe", amount = 5 }
        },
        results = {
            { type = "item", name = gprefix .. "tenemut-synthesizer", amount = 1 }
        }
    },

    -- The synthesis recipe itself: NO ingredients at all. Factorio's
    -- `ingredients` field is optional — an empty list means the machine
    -- consumes nothing over `energy_required` and pays only electricity.
    {
        type = "recipe",
        name = gprefix .. "tenemut-synthesis",
        -- Factorio 2.1: `categories` (array). The singular `category` key was
        -- merged into it and now HARD-ERRORS at prototype load — caught by the
        -- headless load test, not by the unit suite.
        categories = { gprefix .. "synthesis" },
        subgroup = "raw-resource",
        icons = {
            {
                icon = TENEMUT_ICON,
                tint = DARK_MATTER_TINT
            }
        },
        icon_size = 64,
        enabled = false,
        ingredients = {},
        energy_required = SYNTHESIS_TIME,
        results = {
            { type = "item", name = gprefix .. "tenemut", amount = 1 }
        },
        main_product = gprefix .. "tenemut",
        -- Guards, see the header comment: never hand-craftable, never
        -- productivity-boostable, not decomposable (no raw cost exists).
        hide_from_player_crafting = true,
        allow_productivity = false,
        allow_decomposition = false,
        auto_recycle = false
    }
})
