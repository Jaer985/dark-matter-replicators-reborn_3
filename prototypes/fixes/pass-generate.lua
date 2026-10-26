-- prototypes/fixes/pass-generate.lua
-- PASS 0: Dynamic recipe generation (v3.7.0 A6 — moved from data-updates).
--
-- The generator MUST run here, AFTER overhaul mods (Bob's, Angel's, K2) have
-- defined their recipes AND their unlock-recipe tech effects in their own
-- data-updates/data-final-fixes. Running it in data-updates meant:
--   1. recipe_tech_map was incomplete → 118 items (with Bob's) lost their
--      original-tech prereq (silently replicable from tier 1).
--   2. recipe_map resolved partial recipes → 367 items were under-tiered
--      (dump-verified: bob-destroyer-robot assigned 1, real 5; solar-panel
--      assigned 1, real 4; ...).
-- Optional dependencies in info.json (? bobplates, ? bobwarfare, ...) force
-- THIS data-final-fixes to run after the overhaul mods' own.
-- v4.0: choose the generator by tech-distribution setting.
--   "Mirror" (default) → MirrorGenerator (árbol espejo: 1 tech por tech
--     original, materials techs, tier = science level de la tech original)
--   "Individual" (legacy) → DynamicGenerator (1 tech por item, como v3.7.x)
-- The grouped-categories mode was REMOVED in v4.0.
require("defines")
local helpers = require("lib.helpers")

local tech_dist = helpers.get_startup_setting("dmrsa-tech-distribution", "Mirror")
local planetary_unlocks
if tech_dist == "Individual" then
    local DynamicGenerator = require("prototypes.recipes.dynamic-generator")
    local baseline_unlocks = DynamicGenerator.generate()
    -- Attach baseline unlocks to their corresponding technology nodes
    for tier = 1, 5 do
        local tech_name = gprefix .. "replication-" .. tier
        local tech = data.raw.technology[tech_name]
        local unlocks = baseline_unlocks[tier]

        if tech and (not (tier == 3 and mods["space-age"])) and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
            end
        elseif tier == 3 and mods["space-age"] and unlocks and #unlocks > 0 then
            -- Attach baseline Tier 3 unlocks to the three planetary technologies
            local planetary_techs = {
                gprefix .. "replication-vulcanus-tech",
                gprefix .. "replication-fulgora-tech",
                gprefix .. "replication-gleba-tech"
            }
            for _, p_tech_name in ipairs(planetary_techs) do
                local p_tech = data.raw.technology[p_tech_name]
                if p_tech then
                    p_tech.effects = p_tech.effects or {}
                    for _, recipe_name in ipairs(unlocks) do
                        table.insert(p_tech.effects, { type = "unlock-recipe", recipe = recipe_name })
                    end
                end
            end
        end
    end
else
    -- v4.0 MIRROR mode: MirrorGenerator handles recipes, mirror techs, AND the
    -- materials-tech baseline attachment internally. Returns planetary unlocks.
    local MirrorGenerator = require("lib.mirror-generator")
    planetary_unlocks = MirrorGenerator.generate()
end

-- v4.1.0 (Quality Refiner): dynamic refining recipes, one per replicable item
-- per quality step. Runs AFTER the mirror generator so it can read the real
-- dmrsa-repl-* recipes (energy costs). No-op when no quality mod is active.
-- v4.7.1: the refiner is a CRAFTING MACHINE again (author's call): one recipe per
-- item per quality step, real power draw and progress bar, and control.lua keeps
-- the machine's recipe in sync with the item's current quality so the chain walks
-- itself. The recipes now lock the input quality with `quality_min`/`quality_max`
-- (in 2.1 `ingredients[].quality` is NOT a gate — that was the exploit).

-- Attach planetary unlocks to their corresponding planetary technology nodes
if mods["space-age"] and planetary_unlocks then
    for planet, unlocks in pairs(planetary_unlocks) do
        local tech_name = gprefix .. "replication-" .. planet .. "-tech"
        local tech = data.raw.technology[tech_name]
        if tech and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
            end
        end
    end
end

local RefinerGenerator = require("lib.refiner-generator")
RefinerGenerator.generate()
