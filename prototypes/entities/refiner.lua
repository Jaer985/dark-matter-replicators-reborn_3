-- prototypes/entities/refiner.lua
-- v4.1.0: Quality Refiner — a separate machine that refines replicable items
-- one quality step higher (never skips). Balance: every cycle costs 3x the
-- replication TIME of the item, CAPPED at 1 h per cycle (lib/refiner-generator.lua
-- ENERGY_MULT / REFINER_MAX_CYCLE); the per-step success chances are
-- 5 / 2.5 / 1.25 / 1 % and the destruction risk is 1% — v4.4.0 (B8) raised the
-- chances 5x and cut the loss 5x, and cut the machine draw 4MW → 1MW; A5 raised
-- the last step 0.5 % → 1 % (expected 340 → 240 cycles, -29 %). Energy per cycle
-- is 20x lower than 4.3.1; see research/apply-a2-prototypes.md for the
-- arithmetic. The machine accepts NO modules — the probabilities ARE the mechanic.
--
-- Placeholder graphics: vanilla assembling-machine-1 sprites with a violet /
-- black-obsidian tint (parameters taken from the real 2.x prototype, not
-- memory: 214x226, frame_count 32, line_length 8, scale 0.58).
--
-- The whole subsystem only exists when a quality mod is active
-- (data.raw["quality"]["uncommon"]).
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local QUALITY_ON = (data.raw["quality"] and data.raw["quality"]["uncommon"] ~= nil)
if not QUALITY_ON then
    return
end

-- v4.4.0: the refiner is a QUALITY tool, so it unlocks with the quality
-- discovery, not at the end of the replication tree (it used to require
-- `dmrsa-replication-materials-5`, i.e. tier 5 — a tool you could only build
-- after owning everything it upgrades).
-- The names are declared PLAINLY on purpose. This file is loaded from data.lua
-- BEFORE technologies.lua, before other mods' data-updates and before the
-- `quality` technology exists, so an existence check here produces an EMPTY
-- prerequisite list — and prototypes/fixes/pass-orphans.lua then treats the tech
-- as orphaned and DISABLES it (verified the hard way: the refiner disappeared
-- from the v4.4.0 build with an empty list). PASS 1
-- (prototypes/fixes/pass-prereqs.lua) strips the invalid entry at
-- data-final-fixes instead, which is the mod's own idiom.
-- The quality anchor is `quality-module` — there is NO technology named
-- "quality" in the game data (checked in the 2.1.20 dump: the quality techs are
-- quality-module / quality-module-2 / quality-module-3 / epic-quality /
-- legendary-quality, and `quality-module` is the one carrying
-- {type="unlock-quality", quality="uncommon"}).
local tech_prereqs = { gprefix .. "replication-2", "quality-module" }

-- ── v4.4.0 (D7): the machine's icon ───────────────────────────────────────────
-- It used to be graphics/icons/replicator-5.png with NO tint — byte-identical to
-- the tier-5 replicator's icon, so the two machines were indistinguishable in
-- the crafting menu (audit I1). It now carries the machine's own violet,
-- brightened: a 0.35/0.25/0.65 tint renders the icon at 10.7 % luminance (the
-- audit's "12 % dark silhouette"), 0.55/0.40/1.0 lands at 16.5 % — the same
-- legibility class as the new collider (18.1 %) and annihilator (17.0 %) tints.
-- (Measured on graphics/icons/replicator-5.png, mean RGB of the opaque pixels x
-- the tint, Rec.601 luma; see research/apply-a2-prototypes.md.)
local ICON = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png"
local ICON_TINT = { r = 0.55, g = 0.40, b = 1.0, a = 1.0 }
local SPRITE_TINT = ICON_TINT

-- ── v4.4.0 (D1/D4): sprite geometry, art-calibrated ───────────────────────────
-- The mod's own rule (replicators.lua) is scale = selection_half * 2/3 with the
-- shift cancelling the art's bias inside its 113x91 frame (the solid art is
-- 95x85, centred within 1 px vertically and 7 px biased to the left):
--   scale = 1.5 * 2/3 = 1.0       -> 95 px * 1.0 / 32 = 2.97 tiles in a 3x3 box
--   shift = { 1.5*0.4/3 = 0.2, 1.5*0.02 = 0.03 }
-- Shipped before this batch: shift {0.4, 0.1} — 0.20 tiles left of centre, a
-- 0.17-tile overhang on the right and 0.08 tiles south of the box (audit G4/G3).
local SELECTION = 1.5
local SPRITE_SCALE = SELECTION * 2 / 3
local SPRITE_SHIFT = { SELECTION * 0.4 / 3, SELECTION * 0.02 }

-- ── v4.4.0 (B10): the research unit ───────────────────────────────────────────
-- The unit was hardcoded to { { "dmrsa-dark-matter-scoop", 1 } }, ignoring the
-- `dmrsa-tenemut-research-required` setting — with it OFF (the ore-free mode of
-- v4.3) the tech still demanded a DMR intermediate, exactly what the setting
-- exists to remove, and unlike every other tech of this mod. This is the local
-- form of make_research_unit (prototypes/technologies/technologies.lua:5-50):
-- drop every dmrsa-* pack when the setting is off, fall back to the vanilla
-- packs of the refiner's own tier, and NEVER leave the list empty (an empty
-- ingredient list is the v4.2 "no cost" bug). Easy: 25 reps x 10 s (the values
-- the hardcoded unit produced there), scaled by the difficulty multipliers.
local function refiner_research_unit(count, time)
    local ingredients = {}
    local dmr_pack_required = helpers.dmr_research_pack_required()
    if dmr_pack_required and helpers.item_exists(gprefix .. "dark-matter-scoop") then
        table.insert(ingredients, { gprefix .. "dark-matter-scoop", 1 })
    end
    if #ingredients == 0 then
        for _, vanilla in ipairs({ "automation-science-pack", "logistic-science-pack" }) do
            if helpers.item_exists(vanilla) then
                table.insert(ingredients, { vanilla, 1 })
            end
        end
    end
    local diff_mult = helpers.get_research_difficulty_multipliers()
    return {
        count = math.max(1, math.ceil(count * diff_mult.reps_mult)),
        ingredients = ingredients,
        time = math.max(1, math.ceil(time * diff_mult.time_mult))
    }
end

data:extend({
    -- Recipe category for refining (only visible inside the refiner)
    {
        type = "recipe-category",
        name = gprefix .. "refining"
    },
    -- Visual subgroup while picking recipes in the refiner
    {
        type = "item-subgroup",
        name = gprefix .. "refining",
        group = "production",
        order = "z"
    },
    -- Item
    {
        type = "item",
        name = gprefix .. "refiner",
        icons = { { icon = ICON, tint = ICON_TINT } },
        icon_size = 64,
        subgroup = gprefix .. "replicators",
        order = "c",
        place_result = gprefix .. "refiner",
        stack_size = 50
    },
    -- Entity (placeholder: assembler-1 tinted obsidian-violet)
    {
        type = "assembling-machine",
        -- v4.8.0: circuit connectors, parity with vanilla assembling machines
        -- (field absent = distance 0 = wires cannot be attached: measured, see
        -- research/gate-circuit-wires.md).
        circuit_wire_max_distance = 9,
        name = gprefix .. "refiner",
        icons = { { icon = ICON, tint = ICON_TINT } },
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.2, result = gprefix .. "refiner" },
        fast_replaceable_group = gprefix .. "replicator",
        max_health = 400,
        resistances = {
            {
                type = "fire",
                percent = 80
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -1.2, -1.2 }, { 1.2, 1.2 } },
        selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } },
        crafting_categories = { gprefix .. "refining" },
        crafting_speed = 1,
        -- v4.2 (B2): 6MW → 4MW. v4.4.0 (B8): 4MW → 1MW — with the 5x success
        -- chances the ladder takes 240 cycles per normal→legendary item
        -- (A5: 340 → 240 at the 1 % last step) instead of 1700, and at 1 MW
        -- instead of 4 MW the energy per item falls 20x. The recipe time
        -- (3x replication, capped at 1 h) is deliberately NOT touched here:
        -- the energy knob lives here, the time knob in ENERGY_MULT.
        energy_usage = "1MW",
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input"
            -- L1 (review r1): no `emissions_per_second` here. It is a BURNER
            -- field; on type = "electric" the engine ignores it and
            -- --check-unused-prototype-data reports it as unused data.
        },
        graphics_set = {
            animation = {
                -- Placeholder: DMR's own replicator-5 sprite (robust — the
                -- vanilla assembler-1 sheet path doesn't exist once an
                -- overhaul mod (Bob's) replaces it, so we use our own proven
                -- sprite with an obsidian-violet tint as the placeholder).
                filename = "__dark-matter-replicators-reborn__/graphics/entity/replicator-5.png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                -- v4.4.0 (D1/D4): art-calibrated scale + centring (see the
                -- constants above). 2.97 tiles of art in the 3x3 box.
                scale = SPRITE_SCALE,
                shift = SPRITE_SHIFT,
                tint = SPRITE_TINT
            }
        },
        working_sound = {
            sound = {
                {
                    filename = "__base__/sound/lab.ogg",
                    volume = 0.7
                }
            },
            idle_sound = { filename = "__base__/sound/idle1.ogg", volume = 0.6 }
            -- L1 (review r1): `apparent_volume` removed. It is not a 2.1
            -- working_sound field (the engine reports it as unused); the sound
            -- lives at `volume` on each filename entry above.
        },
        -- NO module slots: quality/probability balance is the mechanic itself.
        module_slots = 0,
        -- v4.4.0: NO module or beacon effects. "consumption" used to be here, which let an
        -- efficiency BEACON cut the refiner's 1 MW draw by up to 80% — and since the refiner's
        -- whole cost model is "3x the replication energy", that made refining cheaper than
        -- replicating (0.6x). Beacons key off allowed_effects, not module_slots, so an empty
        -- list is the only thing that closes it. The probabilities ARE the mechanic.
        allowed_effects = {},
    },
    -- Recipe (unlocked by the refining technology)
    {
        type = "recipe",
        name = gprefix .. "refiner",
        enabled = false,
        -- v4.4.0: tier-2 build cost, matching the new unlock gate (it used to
        -- cost a replicator-4 and 10 matter conduits = tier-5 materials).
        ingredients = {
            { type = "item", name = gprefix .. "replicator-2", amount = 1 },
            { type = "item", name = "electronic-circuit", amount = 10 },
            { type = "item", name = gprefix .. "dark-matter-scoop", amount = 5 }
        },
        results = {
            { type = "item", name = gprefix .. "refiner", amount = 1 }
        }
    },
    -- Technology (only when quality exists)
    {
        type = "technology",
        name = gprefix .. "replication-refining",
        localised_name = { "technology-name.dmrsa-replication-refining" },
        localised_description = { "technology-description.dmrsa-replication-refining" },
        -- Factorio 2.1 REQUIRES icon/icons on technologies (the other DMR
        -- techs define icons via get_tech_icons; this standalone tech uses
        -- the refiner's placeholder icon).
        icons = { { icon = ICON, tint = ICON_TINT } },
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "refiner" }
        },
        prerequisites = tech_prereqs,
        -- v4.4.0 (B10): was a hardcoded scoop pack — see refiner_research_unit.
        unit = refiner_research_unit(25, 10),
        order = "a-r-f"
    }
})