-- lib/refiner-generator.lua
-- v4.1.0: Quality Refiner dynamic recipes.
--
-- Para cada item replicable (recipe dmrsa-repl-<item> generada por el árbol
-- espejo), genera 4 recipes de refinado — una por escalón de calidad:
--   normal → uncommon (5%), uncommon → rare (2.5%), rare → epic (1.25%),
--   epic → legendary (1%).   (v4.4.0 A5: the last step was 0.5% — 200 of the
--   340 expected cycles; 1% makes the ladder 240 cycles, -29%.)
--   v4.4.0 (B8): 5x the original 1 / 0.5 / 0.25 / 0.1% — at 1% per step the
--   expected 100 cycles per step (340 per item for the full ladder) made the
--   machine a museum piece instead of a quality tool (see the A2 receipt).
--
-- Cada ciclo consume 1 item del escalón actual y devuelve, con probabilidades
-- independientes:
--   - el MISMO item (reintento) con probabilidad 1 - LOSS_PROB - p
--   - el item +1 calidad con probabilidad p
--   - nada (LOSS_PROB: la pieza se destruye) — cuando ninguna probability acierta
--   v4.4.0 (B8): LOSS_PROB 5% → 1%, so the ladder is decided by the success
--   rolls again instead of by the destruction roll.
--
-- Energía por ciclo = 3x la energía de la recipe de replicación del item
-- (v4.2 B2: antes x10 — con la reescala del cost-model, x10 = 6000s en
-- endgame, inoperable; x3 mantiene el premium de calidad jugable).
--
-- Solo se generan para items REPLICABLES (filosofía fiel: el refiner solo
-- puede refinar estructuras cuya replicación dominas — armas, vehículos y
-- demás excluidos del árbol espejo no aparecen aquí).
--
-- GAP 3 (v4.4.0 fix): NO refining recipes for chemical fuels. Quality does not
-- change a fuel's `fuel_value` (plan §0 — quality only affects vehicle stats and
-- machine speed/consumption), so a refine recipe for a burnable is a DEAD entry
-- in the recipe picker: the probability ladder can only return the same item or
-- raise its quality, neither of which changes the MJ it burns for. Roughly 68
-- dead recipes in the reference modlist (17 burnables × 4 quality steps).
-- The exclusion is driven by REFINER_QUALITY_BLACKLIST below: it applies the
-- fuel rule (fuel_value <= 100 MJ) and lets explicit item names be added later.
-- The fluid exclusion (fluids have no quality) stays as before.
--
-- Gate: requiere un mod de calidad activo (data.raw["quality"]["uncommon"]);
-- sin él, generate() no hace nada.
local helpers = require("lib.helpers")
local TimingModel = require("lib.timing-model")
local RefinerLogic = require("lib.refiner-logic")
local gprefix = "dmrsa-"

local RefinerGenerator = {}

-- Quality name -> level (0 for normal). data.raw.quality is the source of truth;
-- the fallback table keeps the unit tests and older modlists working.
local FALLBACK_LEVEL = { normal = 0, uncommon = 1, rare = 2, epic = 3, legendary = 5 }
local function qlevel(name)
    local q = data.raw.quality and data.raw.quality[name]
    if q and type(q.level) == "number" then return q.level end
    return FALLBACK_LEVEL[name] or 0
end

-- Escalones de calidad: probabilidad de éxito DECRECIENTE por escalón
-- (el 1% del diseño original baja a la mitad en cada salto).
-- v4.4.0 (B8): every step is 5x the v4.1 value. INVARIANT (the ladder design,
-- not a tunable): one entry per step, `from` = the previous `to`, so a cycle
-- can only return the SAME quality (retry) or the NEXT one — the refiner never
-- skips a step.
-- v4.4.0 (A5, review r3 §4): epic -> legendary 0.5 % -> 1 %. The last step was
-- 59 % of the ladder's price (200 of the 340 expected cycles); at 1 % the full
-- ladder is 20 + 40 + 80 + 100 = 240 expected cycles, -29 % time and energy,
-- and it matches the rare -> epic step instead of being a fifth of it. The
-- ladder stays strictly decreasing (5 / 2.5 / 1.25 / 1 %) and never skips.
local QUALITY_STEPS = {
    { from = "normal",    to = "uncommon",  p = 0.05 },    -- 5%
    { from = "uncommon",  to = "rare",      p = 0.025 },   -- 2.5%
    { from = "rare",      to = "epic",      p = 0.0125 },  -- 1.25%
    { from = "epic",      to = "legendary", p = 0.01 },    -- 1%
}
-- Probabilidad de destrucción por ciclo (independiente del éxito).
-- v4.4.0 (B8): 0.05 → 0.01 (see the header).
local LOSS_PROB = 0.01
-- Multiplicador de energía frente a la recipe de replicación original.
-- v4.2 (B2): 10 → 3 (ver cabecera — la reescala de costos hace x10 inoperable).
-- v4.4.0 (B8): KEPT at 3. The 4x energy cut of this batch is applied on the
-- MACHINE side (`energy_usage` 4MW → 1MW in prototypes/entities/refiner.lua),
-- deliberately not here: ENERGY_MULT sets the recipe TIME, and the recipe time
-- is what the timing model prices — one number, one owner.
local ENERGY_MULT = 3
-- M6 (review r1) — CAP ON THE PER-CYCLE TIME.
-- ENERGY_MULT multiplies the POST-CLAMP replication time, and that time can be
-- the C5 arbitrage floor (or the fuel ladder), not the 200 s ladder ceiling:
-- `dmrsa-repl-fusion-reactor` sits at 14 900 s after the floor, so the refiner
-- inherited 44 702 s (12.4 h) per attempt — and 178 809 s (49.7 h) on the
-- shipped 4.4.0 build — which made the top quality steps unobtainable. The cap
-- is one hour: a cycle is meant to be a session-scale commitment, and every
-- quality step keeps a finite worst case (240 expected cycles x 1 h is the
-- absolute upper bound for one legendary megastructure; typical items are far
-- below it because their replication time is 6-200 s).
local REFINER_MAX_CYCLE = 3600

-- v4.2.2 (batch-3 audit): quality-capable prototype classes. The old guard
-- (data.raw.item[...]) skipped 142 quality-capable targets (66 ammo, 39
-- module, 35 capsule, 2 tool): their prototypes live in separate registries,
-- not in data.raw.item. MirrorGenerator attaches dmrsa-repl-* recipes for
-- ALL of them; the refiner must accept them too. Fluids and recipes never
-- qualify (no quality axis).
local REFINE_PROTO_TABLE = { "item", "ammo", "module", "capsule", "tool" }
local function resolve_refine_proto(name)
    for _, reg in ipairs(REFINE_PROTO_TABLE) do
        local reg_raw = data.raw[reg]
        if reg_raw then
            local proto = reg_raw[name]
            if proto then return proto end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- REFINER_QUALITY_BLACKLIST — items that must NOT get quality-refining
-- recipes, even when they pass the prototype-class guard above.
--   * (a) fuel rule — applied automatically below: quality never changes a
--     fuel's `fuel_value`, so every chemical fuel (fuel_value <= 100 MJ, the
--     same class lib/timing-model.lua prices by energy) is skipped. Covers
--     coal, wood, carbon, solid-fuel, rocket-fuel and the Gleba organics.
--     The >100 MJ class (nuclear-fuel, uranium-fuel-cell, fusion-power-cell)
--     keeps its recipes: it is outside the chemical-fuel scope.
--   * (b) explicit names — add an entry here to blacklist any other item by
--     name (value `true`), e.g. a modded item with no meaningful quality axis.
-- ══════════════════════════════════════════════════════════════════
local REFINER_QUALITY_BLACKLIST = {}

-- Returns (true, reason) when `name` must not be refined; (false, nil) otherwise.
local function is_quality_blacklisted(name)
    if REFINER_QUALITY_BLACKLIST[name] then
        return true, "explicit blacklist"
    end
    local proto = resolve_refine_proto(name)
    if proto and TimingModel.is_cheap_fuel(proto) then
        return true, "chemical fuel (fuel_value <= 100 MJ)"
    end
    return false, nil
end

-- Placeable items use entity-name locale, everything else item-name.
local function get_loc_prefix(name)
    local item_proto = resolve_refine_proto(name)
    if item_proto and item_proto.place_result then
        return "entity-name"
    end
    return "item-name"
end

function RefinerGenerator.generate()
    if not (data.raw["quality"] and data.raw["quality"]["uncommon"]) then
        helpers.info("Refiner: quality not enabled, skipping refining recipes.")
        return 0
    end

    local count = 0
    local n_blacklisted = 0
    local prefix = gprefix .. "repl-"

    for recipe_name, recipe in pairs(data.raw.recipe) do
        if string.sub(recipe_name, 1, #prefix) == prefix then
            local res = recipe.results and recipe.results[1]
            if not (res and res.type == "item" and res.name) then
                goto continue_item
            end
            -- v4.2.2 (batch-3 audit): accept quality-capable prototype
            -- classes (ammo/module/capsule/tool), not just data.raw.item —
            -- the narrow guard left 142 targets without refining recipes.
            if not resolve_refine_proto(res.name) then
                goto continue_item
            end
            -- Only non-secret replicable items: mirror generator attaches
            -- every target here; skip dmrsa-* own items defensively.
            if string.sub(res.name, 1, #gprefix) == gprefix then
                goto continue_item
            end
            -- GAP 3 (v4.4.0 fix): no refining recipes for chemical fuels /
            -- explicitly blacklisted items (see REFINER_QUALITY_BLACKLIST).
            local blocked, why = is_quality_blacklisted(res.name)
            if blocked then
                n_blacklisted = n_blacklisted + 1
                helpers.debug("Refiner: skipping '" .. res.name .. "' (" .. why .. ")")
                goto continue_item
            end

            local base_energy = recipe.energy_required or 1
            -- v4.7.1: one attempt per tier, 1-5 s (the author's call for the
            -- automatic refiner). Same numbers as lib/refiner-logic.lua so the
            -- two paths can never drift.
            local cycle_time = RefinerLogic.cycle_seconds(base_energy)
            local loc_pref = get_loc_prefix(res.name)

            for _, step in ipairs(QUALITY_STEPS) do
                local retry_p = 1 - LOSS_PROB - step.p
                if retry_p < 0 then retry_p = 0 end

                -- Factorio 2.1 REQUIRES an icon on recipes whose results carry
                -- a `quality` field (the quality-refining recipe picker can't
                -- auto-detect the icon from a quality result). Reuse the source
                -- item's icon so the entry shows the item being refined.
                local item_proto = resolve_refine_proto(res.name)
                local r_icon, r_icon_size, r_icons
                if item_proto.icons and #item_proto.icons > 0 then
                    local layers = {}
                    for _, spec in ipairs(item_proto.icons) do
                        local cp = helpers.deep_copy(spec)
                        cp.icon_mipmaps = nil
                        table.insert(layers, cp)
                    end
                    r_icons = layers
                    r_icon_size = item_proto.icon_size or 64
                elseif item_proto.icon then
                    r_icon = item_proto.icon
                    r_icon_size = item_proto.icon_size or 64
                else
                    r_icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
                    r_icon_size = 64
                end

                local refine_recipe = {
                    type = "recipe",
                    name = gprefix .. "refine-" .. res.name .. "-" .. step.to,
                    localised_name = {
                        "recipe-name.dmrsa-refining-recipe",
                        { loc_pref .. "." .. res.name },
                        { "quality-name." .. step.to }
                    },
                    energy_required = cycle_time,
                    -- v4.7.1: `quality_min`/`quality_max` are the REAL gate in
                    -- 2.1 (`ingredients[].quality` is decorative — a normal item
                    -- could be pushed through the legendary step, the exploit the
                    -- author reproduced). Both take a quality NAME (a number is
                    -- rejected by the engine: "Value must be a string ...
                    -- quality_min"), and setting min = max locks the input
                    -- quality and disables the "Ingredient quality" selector.
                    ingredients = {
                        { type = "item", name = res.name, amount = 1,
                          quality_min = step.from, quality_max = step.from }
                    },
                    results = {
                        -- Factorio 2.1: retry/success probabilities are
                        -- INDEPENDENT per result (pumpjack-style). The property
                        -- is `independent_probability` (2.1 renamed the old
                        -- `probability` — loading with `probability` errors:
                        -- "'probability' property ... renamed into
                        -- 'independent_probability'").
                        { type = "item", name = res.name, amount = 1, quality = step.from, independent_probability = retry_p },
                        { type = "item", name = res.name, amount = 1, quality = step.to, independent_probability = step.p }
                    },
                    -- v4.4.0 (B8, THE 4.1.0 BLOCKER): `hide_from_player_crafting`,
                    -- NOT `hidden`. `hidden = true` removes a recipe from EVERY
                    -- list — machine recipe pickers included — which is why the
                    -- Quality Refiner shipped with an EMPTY picker in
                    -- 4.1.0-4.3.1 (research/refiner-picker-hidden-bug.md). The
                    -- `dmrsa-refining` category already makes hand-crafting
                    -- impossible (the character has no such crafting category);
                    -- the flag is the belt-and-braces half of the same idiom used
                    -- by dmrsa-dark-matter (prototypes/recipes/dark-matter-power.lua).
                    enabled = true,
                    hide_from_player_crafting = true,
                    subgroup = gprefix .. "refining",
                    categories = { gprefix .. "refining" },
                    order = "z[" .. res.name .. "][" .. step.to .. "]",
                    icon = r_icon,
                    icon_size = r_icon_size,
                    icons = r_icons,
                }
                -- icon and icons are mutually exclusive in a prototype; strip
                -- the simple icon when the layered icons array is present.
                if r_icons then
                    refine_recipe.icon = nil
                    refine_recipe.icon_size = r_icon_size
                end
                data:extend({ refine_recipe })
                count = count + 1
            end
        end
        ::continue_item::
    end

    helpers.info("Refiner: generated " .. count .. " refining recipes (" ..
        n_blacklisted .. " fuel/blacklisted targets skipped).")
    return count
end

return RefinerGenerator