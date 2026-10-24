local helpers = require("lib.helpers")
local CostSolver = require("lib.cost-solver")
require("defines")

local TargetMapper = {}

-- Helper to check if a flag exists in a table of flags
local function has_flag(flags_table, search_flag)
    if not flags_table or type(flags_table) ~= "table" then return false end
    for _, flag in ipairs(flags_table) do
        if flag == search_flag then
            return true
        end
    end
    return false
end

-- Items that are NOT meaningful to replicate. These are UI/utility items that
-- the player carries (wires, remotes, planners, blueprints) rather than
-- production materials. Replicating them adds no gameplay value and pollutes
-- the replication lists (user report: red-wire/green-wire and spidertron-remote
-- appeared replicable before ever unlocking them).
local TARGET_BLACKLIST = {
    -- Circuit network wiring (vanilla)
    "red-wire",
    "green-wire",
    "copper-wire",
    -- Remote controls (vanilla)
    "artillery-targeting-remote",
    "discharge-defense-remote",
    "spidertron-remote",
    -- Planners / blueprints (UI metadata items, not producible materials)
    "blueprint",
    "blueprint-book",
    "deconstruction-planner",
    "upgrade-planner",
    -- Selection / copy tools (UI)
    "copy-paste-tool",
    "cut-paste-tool",
    "selection-tool",
    -- Rail planner
    "rail-planner",
}

-- Fast lookup set (name -> true) built from the list above
local blacklist_set = {}
for _, name in ipairs(TARGET_BLACKLIST) do
    blacklist_set[name] = true
end

-- v4.2 refino (original-mod study): los replicadores son replicables — el
-- original los declara repltech_recipe(device3-5, upgrade=true). El mirror
-- forzará su tier 1..5 (REPLICATOR_TIER) para que cada uno quede en su
-- propia tech espejo.
local DMR_REPLICATOR_WHITELIST = {
    [gprefix .. "replicator-1"] = true,
    [gprefix .. "replicator-2"] = true,
    [gprefix .. "replicator-3"] = true,
    [gprefix .. "replicator-4"] = true,
    [gprefix .. "replicator-5"] = true,
}

-- Helper: check if a name matches the filled-barrel pattern.
-- Factorio generates filled barrels dynamically as "fill-<fluid>-barrel"
-- (and some mods use "<fluid>-barrel"). The empty barrel itself is "barrel".
-- Filled barrels are containers, not production materials — replicating them
-- would let players duplicate fluids without a replication recipe for the
-- fluid itself.
local function is_filled_barrel(name)
    if name == "barrel" then return false end
    if string.find(name, "%-barrel$") then return true end
    return false
end

-- v3.6.3: Hybrid "step item" filter. With overhaul mods (Bob's, Angel's, K2),
-- many intermediate "step" items are NOT worth replicating: bearing balls,
-- internal projectiles/warheads, roboport parts, grinding/polishing wheels,
-- and similar. They pollute the replication lists and tech trees.
--
-- LEVEL 1 — name patterns (cheap, general, covers the classes nihil excluded):
-- returns true when the name matches a known step-item pattern.
local STEP_NAME_PATTERNS = {
    "%-bearing%-ball$",        -- bob-steel-bearing-ball (input to bearing)
    "%-projectile$",           -- internal ammo projectiles
    "%-warhead$",              -- internal rocket warheads
    "roboport%-antenna%-",     -- roboport internal parts
    "roboport%-chargepad%-",
    "roboport%-door%-",
    "%-grinding%-wheel$",      -- gem-processing consumables
    "%-polishing%-wheel$",
    -- v3.7.1: "-instantiated" items (factorissimo factory-1-instantiated,
    -- space-factory-1-instantiated...). These are INTERNAL packed-state items
    -- (the entity's mined form, item-with-tags with indirect localised_name).
    -- They leak past the eligibility rule because Space Age auto-generates
    -- <name>-recycling recipes that PRODUCE them → is_produced_by_recipe=true.
    -- Their locale key (entity-name.<name>) does not exist → "unknown key"
    -- runtime warnings. Same internal-item class as parameter-N.
    "%-instantiated$",
}
local function is_step_by_name(name)
    for _, pat in ipairs(STEP_NAME_PATTERNS) do
        if string.find(name, pat) then
            return true
        end
    end
    return false
end

-- LEVEL 2 — explicit exclusion list (ground truth from nihil's replvar calls):
-- these are the "step" items the upstream mod explicitly marks as not worth
-- replicating. Keeping them out of the dynamic generator avoids polluting the
-- replication lists with intermediates that only feed one more recipe.
local STEP_EXPLICIT = {
    -- Bearing balls (feed the bearing recipe only)
    "bob-steel-bearing-ball", "bob-titanium-bearing-ball", "bob-nitinol-bearing-ball",
    "bob-ceramic-bearing-ball", "bob-cobalt-steel-bearing-ball", "brass-bearing-ball",
    "titanium-bearing-ball", "nitinol-bearing-ball", "ceramic-bearing-ball",
    "cobalt-steel-bearing-ball",
    -- Gem-processing consumables
    "bob-grinding-wheel", "bob-polishing-wheel", "grinding-wheel", "polishing-wheel",
    "bob-polishing-compound", "polishing-compound",
    -- Upstream-excluded misc (nihil replvar): silicon carbide + long-handed inserter
    "silicon-carbide", "long-handed-inserter",
    -- Bob's base bullets (nihil excludes both X-bullet and X-bullet-projectile)
    "bob-bullet", "bob-ap-bullet", "bob-he-bullet", "bob-flame-bullet",
    "bob-acid-bullet", "bob-poison-bullet", "bob-electric-bullet", "bob-uranium-bullet",
    "bob-plasma-bullet",
    -- Internal projectile/warhead entities (not magazines) — bob-ammo-parts
    "bob-bullet-projectile", "bob-ap-bullet-projectile", "bob-he-bullet-projectile",
    "bob-flame-bullet-projectile", "bob-acid-bullet-projectile",
    "bob-poison-bullet-projectile", "bob-electric-bullet-projectile",
    "bob-uranium-bullet-projectile", "bob-plasma-bullet-projectile",
    "bob-rocket-warhead", "bob-piercing-rocket-warhead", "bob-electric-rocket-warhead",
    "bob-explosive-rocket-warhead", "bob-acid-rocket-warhead", "bob-flame-rocket-warhead",
    "bob-poison-rocket-warhead", "bob-plasma-rocket-warhead",
    -- Roboport internal parts (Bob's logistics)
    "bob-roboport-antenna-1", "bob-roboport-antenna-2", "bob-roboport-antenna-3", "bob-roboport-antenna-4",
    "bob-roboport-chargepad-1", "bob-roboport-chargepad-2", "bob-roboport-chargepad-3", "bob-roboport-chargepad-4",
    "bob-roboport-door-1", "bob-roboport-door-2", "bob-roboport-door-3", "bob-roboport-door-4",
    -- Robot sub-parts (Bob's) — verified against 805-recipe graph (2026-08-11)
    "bob-robot-brain", "bob-robot-brain-2", "bob-robot-brain-3", "bob-robot-brain-4",
    "bob-robot-tool-construction", "bob-robot-tool-construction-2",
    "bob-robot-tool-construction-3", "bob-robot-tool-construction-4",
    "bob-robot-tool-logistic", "bob-robot-tool-logistic-2",
    "bob-robot-tool-logistic-3", "bob-robot-tool-logistic-4",
    "bob-flying-robot-frame-2", "bob-flying-robot-frame-3", "bob-flying-robot-frame-4",
    -- v3.7.0 (B4): combat robot brains/tools (Bob's warfare) — the user
    -- reported bob-robot-brain-combat 1/2, distractor/destroyer/devastator/
    -- defender robot weapons still appearing as replication targets. These are
    -- internal sub-parts of combat robots (defender/distractor/destroyer), the
    -- same step-item class as the construction/logistic brains above.
    "bob-robot-brain-combat", "bob-robot-brain-combat-2", "bob-robot-brain-combat-3", "bob-robot-brain-combat-4",
    "bob-robot-tool-combat", "bob-robot-tool-combat-2", "bob-robot-tool-combat-3", "bob-robot-tool-combat-4",
    -- v3.7.0 (B4): mech sub-parts (Bob's warfare) — mech brain / leg segment /
    -- frame / hip / knee / foot / armor-plate are internal parts that only feed
    -- the mech assembly; replicating them individually is pointless pollution.
    "bob-mech-brain", "bob-mech-leg", "bob-mech-leg-segment",
    "bob-mech-frame", "bob-mech-hip", "bob-mech-knee", "bob-mech-foot",
    "bob-mech-armor-plate",
    -- Small alien artifacts (dropped by enemies, not producible by recipe)
    "bob-small-alien-artifact", "bob-small-alien-artifact-blue", "bob-small-alien-artifact-green",
    "bob-small-alien-artifact-orange", "bob-small-alien-artifact-purple",
    "bob-small-alien-artifact-red", "bob-small-alien-artifact-yellow",
    -- Bob's module processor components (intermediate for processors)
    "bob-basic-electronic-components", "bob-electronic-components",
    -- Angel's petrochem intermediates (nihil replvar exclusions) — gaseous /
    -- liquid / solid chemical steps of the petrochem chains. Verified against
    -- nihil's angel.lua: these are pure processing steps, never worth
    -- replicating directly.
    "rocket-oxidizer-capsule", "gas-dimethylhydrazine", "gas-hydrazine",
    "liquid-nitric-acid", "gas-dinitrogen-tetroxide", "gas-dimethylamine",
    "gas-monochloramine", "gas-ammonia", "gas-nitrogen-dioxide",
    "gas-nitrogen-monoxide", "gas-methylamine", "solid-sodium-hypochlorite",
    "liquid-aqueous-sodium-hydroxide", "solid-sodium-hydroxide",
}
local STEP_EXPLICIT_SET = {}
for _, n in ipairs(STEP_EXPLICIT) do STEP_EXPLICIT_SET[n] = true end

-- Combined hybrid check: name pattern OR explicit list.
local function is_step_item(name)
    if is_step_by_name(name) then return true end
    if STEP_EXPLICIT_SET[name] then return true end
    return false
end

-- v3.6.4: Eligibility rule — an item is only worth replicating if it can be
-- OBTAINED legitimately by the player:
--   1) produced by some recipe (craftable), OR
--   2) is a minable resource (has an autoplace / is in data.raw.resource), OR
--   3) is whitelisted explicitly (asteroid chunks, alien artifacts, special
--      drops that the game intends as obtainable).
-- Items that are neither produced nor minable nor whitelisted are "phantom"
-- items (spawn/drop-only internals, hidden mod internals) — replicating them
-- is a shortcut the game never intended, so they must not generate research.
local ELIGIBILITY_WHITELIST = {
    -- Space Age asteroid chunks (mined from space, no recipe).
    -- v4.2.2 (D17): all 6 real chunks — auric/bismuth added (they were
    -- escaping eligibility and only reachable via steam-recycler swallow).
    -- Same source list as SPACE_CHUNK_TARGETS below (sync both).
    "metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk",
    "auric-asteroid-chunk", "bismuth-asteroid-chunk", "promethium-asteroid-chunk",
    -- Bob's alien artifacts (enemy drops, game-intended collectible)
    "bob-alien-artifact", "bob-alien-artifact-blue", "bob-alien-artifact-green",
    "bob-alien-artifact-orange", "bob-alien-artifact-purple", "bob-alien-artifact-red",
    "bob-alien-artifact-yellow",
    -- SA plants (grown, not crafted)
    "jellynut", "yumako",
}
local ELIGIBILITY_WHITELIST_SET = {}
for _, n in ipairs(ELIGIBILITY_WHITELIST) do ELIGIBILITY_WHITELIST_SET[n] = true end

-- Cache of items produced by any recipe (built lazily from data.raw.recipe).
local produced_set = nil
local function is_produced_by_recipe(name)
    if not produced_set then
        produced_set = {}
        local recipes = data.raw.recipe
        if recipes then
            for _, recipe in pairs(recipes) do
                local results = recipe.results
                if not results and recipe.normal and recipe.normal.results then
                    results = recipe.normal.results
                end
                if results then
                    for _, res in ipairs(results) do
                        local res_name = res.name or res[1]
                        if res_name then produced_set[res_name] = true end
                    end
                end
            end
        end
    end
    return produced_set[name] or false
end

-- Cache of minable resources (data.raw.resource autoplace entries).
local resource_set = nil
local function is_minable_resource(name)
    if not resource_set then
        resource_set = {}
        local resources = data.raw.resource
        if resources then
            for rname in pairs(resources) do resource_set[rname] = true end
        end
    end
    return resource_set[name] or false
end

local function is_eligible(name)
    if ELIGIBILITY_WHITELIST_SET[name] then return true end
    if is_produced_by_recipe(name) then return true end
    if is_minable_resource(name) then return true end
    return false
end

-- v4.0: "1-solo-uso / no producción masiva" exclusions (user-approved 2026-08-12).
-- Weapons, armor, combat capsules, vehicles, vehicle equipment, and personal
-- equipment are produced once and carried/equipped — replicating them adds no
-- production value. KEPT (mass-use): ammo (aliens), fuel cells (reactors),
-- seeds (Gleba agriculture), raw-fish (healing), solar panels + batteries.
local VEHICLE_REGISTRIES = {
    "car", "tank", "spider-vehicle", "locomotive",
    "cargo-wagon", "fluid-wagon", "artillery-wagon"
}
-- v4.2 (audit B3): Bob's individual gem ores are ITEMS whose only producing
-- recipe is "-recycling" (excluded from the recipe map) — they fail the
-- phantom-item eligibility rule but are legit endgame rare materials.
local BOB_GEM_ORES = {}
for _, n in ipairs({
    "bob-amethyst-ore", "bob-diamond-ore", "bob-emerald-ore",
    "bob-ruby-ore", "bob-sapphire-ore", "bob-topaz-ore",
}) do
    BOB_GEM_ORES[n] = true
end
-- v4.2.2 (D17, decisión del usuario 2026-09-04): the 6 real asteroid chunks.
-- They are flag-hidden in Space Age but ARE legit replication targets (the
-- only source of chunk material without asteroid reprocessing chains). Their
-- GATE (tier 5 + gravity<=0) lives in mirror-generator's SPACE_CHUNKS — this
-- set only keeps them past the hidden-item filter here. Mirrors the
-- mirror-generator list: keep both in sync.
local SPACE_CHUNK_TARGETS = {}
for _, n in ipairs({
    "metallic-asteroid-chunk", "carbonic-asteroid-chunk",
    "oxide-asteroid-chunk", "auric-asteroid-chunk",
    "bismuth-asteroid-chunk", "promethium-asteroid-chunk",
}) do
    SPACE_CHUNK_TARGETS[n] = true
end
-- v4.2.2 (batch-3 audit): hoisted out of is_v4_excluded — these tables were
-- rebuilt on every call (per-item re-allocation). Pure lookup tables.
local YUOKI_SIGNS = {
    "y_greensign", "y_rwtechsign", "ypfw_trader_sign", "ye_science_blue"
}
local YUOKI_EXCLUDED = {
    -- Inserters
    "y-inserter-s4", "y-inserter-smart-long", "y-inserter-smart",
    "y_inserter_diagonal", "y_inserter_evade_shortL", "y_inserter_evade_shortR",
    "y_inserter_smart_LL", "y_inserter_smart_RR",
    "y_inserter_smart_leftR2", "y_inserter_smart_rightR2",
    -- Storage
    "y-rare-m1bunker-log",
    -- Basements
    "y_basement_4x4a", "y_basement_5x5a", "y_basement_5x5b", "y_basement_5x5c",
    "y_basement_5x5d", "y_basement_5x5e", "y_basement_5x5f", "y_basement_5x5f2",
}
local YUOKI_EXCLUDED_SET = {}
for _, s in ipairs(YUOKI_EXCLUDED) do YUOKI_EXCLUDED_SET[s] = true end
local V42_EXCLUDED = {
    -- (las minas/cápsulas/robots de combate se REVIERTEN: el usuario decide
    -- que se replican en su tier; se quitan de esta lista en 2026-08-22)
    "factory-circuit-connector",
    "bob-spidertron-cannon",
}
local V42_EXCLUDED_SET = {}
for _, s in ipairs(V42_EXCLUDED) do V42_EXCLUDED_SET[s] = true end
local function is_v4_excluded(name, type_name)
    -- 1. Weapons (gun) and armor
    if type_name == "gun" or type_name == "armor" then
        return true
    end
    -- v4.2 (2026-08-22, decisión del usuario en B5): las cápsulas de combate
    -- (granadas, poison, slowdown, cliff-explosives, defender/distractor/
    -- destroyer-capsule, flamethrower) SÍ se replican, en su tier como
    -- vanilla (el mirror las pone en su tech original, tipicamente military)
    -- y no antes. Antes de v4.2 se excluían como "1-solo-uso".
    -- (El bloque COMBAT_CAPSULE_PATTERNS se elimina; las minas siguen
    -- replicandose igual.)

    -- 3. Vehicles / rolling stock (their item form is item-with-entity-data)
    for _, reg_name in ipairs(VEHICLE_REGISTRIES) do
        if data.raw[reg_name] and data.raw[reg_name][name] then
            return true
        end
    end
    -- 4. Vehicle equipment (Bob's bob-vehicle-*)
    if string.sub(name, 1, 12) == "bob-vehicle-" then
        return true
    end
    -- 5. Personal equipment EXCEPT solar panels and batteries (mass-use kept).
    -- v4.2 (dump audit): Bob's equipment tiers end in "-N" (bob-exoskeleton-
    -- equipment-2...), so the plain "%-equipment$" pattern never matched them
    -- and 13 personal equipment items were replicating. Match versioned too.
    if string.find(name, "%-equipment$") or string.find(name, "%-equipment%-%d+$") then
        if string.find(name, "solar") or string.find(name, "battery") then
            return false
        end
        return true
    end
    -- NOTE (v4.0): a universal place_result exclusion was considered for Yuoki
    -- but REJECTED — it would kill mass-use items (chests, inserters, pipes,
    -- lamps, poles, belts) that must stay replicable. Yuoki machines are
    -- handled per-item via YUOKI_EXCLUDED below.
    -- 7. Yuoki Industries faction signs (v4.0): signs represent what other
    -- factions are willing to do for you — faction currency, not production.
    -- Upstream DMR explicitly set their replication cost to 0.
    for _, s in ipairs(YUOKI_SIGNS) do
        if name == s then return true end
    end
    -- 8. Yuoki Industries — per-item exclusions decided by Jaer985 (2026-08-14):
    --   - Inserters: Bob's inserters already cover inserters; Yuoki's add no value
    --   - Bunker storage: storage buildings, not production
    --   - Basements: factorio-style buildings (one per base placement)
    --   (Pendiente: procesado/refinado/mastercrafted/ultimate decidir poco a poco)
    if YUOKI_EXCLUDED_SET[name] then return true end
    -- v4.2 (dump audit 2026-08-22): Bob's combat robots are type "item"
    -- (vanilla uses capsules, which the capsule rule catches), so they slipped
    -- past the combat-capsule exclusion. Also the factorissimo network
    -- connector (red-wire utility, not a production item) and the spidertron
    -- cannon (a weapon).
    if V42_EXCLUDED_SET[name] then return true end
    -- 9. v4.2.x: Angel's vehicle equipment uses the "-vequip" suffix, which
    -- escapes both the bob-vehicle-* prefix rule and the %-equipment$ rule,
    -- and its items are type "item" with place_as_equipment_result (no
    -- entity in data.raw.car/... so the vehicle-registry rule misses too).
    -- Vehicle equipment is excluded like every other vehicle/personal gear
    -- (user decision 2026-08-23; dump: exactly 5 items + 1 hidden variant).
    if string.find(name, "%-vequip$") then
        return true
    end
    -- 10. v4.2.x: RPG-system potions are drop-only progression items with no
    -- production chain — replication would bypass their intended scarcity
    -- (user decision 2026-08-23; not mass-use ammo/capsules).
    if string.find(name, "^rpg_.*_potion$") then
        return true
    end
    -- 11. v4.2.2 (batch-3 audit): structural equipment guard. Gear whose item
    -- name escapes ALL name patterns was still replicating: aircraft-
    -- afterburner (movement), aircraft-energy-shield, angels-cab-energy-
    -- interface-mk1, manual-color-module — none contains "-equipment", so
    -- rules 4/5 miss them even though Factorio marks them as worn equipment
    -- via place_as_equipment_result. Inspect the prototype instead of the
    -- name. Solar/battery stays KEPT (mass-use, same exception as rule 5).
    local proto = data.raw[type_name] and data.raw[type_name][name]
    if proto and proto.place_as_equipment_result then
        if string.find(name, "solar") or string.find(name, "battery") then
            return false
        end
        return true
    end
    return false
end

-- Safely maps out all potential replication targets
function TargetMapper.get_potential_replication_targets()
    local targets = {}
    local item_categories = {
        "item", "ammo", "armor", "gun", "capsule", "tool", "module",
        "item-with-entity-data", "item-with-tags", "spidertron-remote",
        -- v4.4.0 (B13): the real Space Age registry is
        -- `space-platform-starter-pack`; the old `space-platform-starter`
        -- literal matches no prototype type, so the starter pack was never a
        -- replication target.
        "space-platform-starter-pack"
    }

    -- 1. Safely iterate over each item category in data.raw
    for _, category in ipairs(item_categories) do
        local registry = data.raw[category]
        if registry then
            for name, item in pairs(registry) do
                local is_valid = true

                -- Prevent self-replication/looping of mod items
                -- EXCEPTION (v4.0): dmrsa-tenemut IS replicable — but only at
                -- tier 5 ("Mastery of Dark Matter"). The mirror generator
                -- forces its tier to 5, so it lands in the tier-5 baseline.
                -- EXCEPTION (v4.2 refino, original-mod study): los
                -- dmrsa-replicator-1..5 también se replican (el original los
                -- hace repltech_recipe(device3-5, upgrade=true)) — el jugador
                -- duplica sus replicadores en vez de fabricarlos a mano.
                if string.sub(name, 1, string.len(gprefix)) == gprefix
                   and name ~= gprefix .. "tenemut"
                   and not DMR_REPLICATOR_WHITELIST[name] then
                    is_valid = false
                end

                -- Blacklist UI/utility items (wires, remotes, planners, blueprints)
                if is_valid and blacklist_set[name] then
                    is_valid = false
                end

                -- Blacklist filled barrels (fill-<fluid>-barrel / <fluid>-barrel)
                if is_valid and is_filled_barrel(name) then
                    is_valid = false
                end

                -- v3.6.3: Hybrid step-item filter (Bob's/Angel's/K2 intermediates)
                -- bearing balls, internal projectiles/warheads, roboport parts,
                -- grinding/polishing wheels, and graph-detected step items.
                if is_valid and is_step_item(name) then
                    is_valid = false
                end

                -- v3.6.4: Eligibility rule — phantom/spawn-only items (no
                -- producing recipe, not minable, not whitelisted) are not
                -- legitimate replication targets. This catches mod internals
                -- (factorissimo factory-*, hidden robots), drop-only items,
                -- and any future mod's phantom items without per-mod lists.
                -- v4.2 (audit B3): Bob's individual gem ores are items whose
                -- only producing recipe is "-recycling" (excluded from the
                -- recipe map) — they fail this rule but ARE legit rare
                -- materials, so they force through.
                if is_valid and not is_eligible(name)
                   and not BOB_GEM_ORES[name] then
                    is_valid = false
                end

                -- v3.7.0 (B4): parametrized-recipe placeholder items — Factorio
                -- 2.0 parametrized recipes (used by mods like KS_Power) create
                -- synthetic items named "parameter-N" in subgroup "parameters".
                -- They are NOT real items (no crafting recipe, no gameplay
                -- value) and must never be replication targets. The dump-based
                -- audit (2026-08-11) found dmrsa-repl-parameter-0..9 recipes
                -- generated from these.
                if is_valid and string.find(name, "^parameter%-%d+$") then
                    is_valid = false
                end

                -- v4.0: 1-solo-uso / no producción masiva exclusions
                -- (weapons, armor, combat capsules, vehicles, vehicle +
                -- personal equipment; ammo/fuel-cells/seeds/raw-fish/solar/
                -- batteries stay).
                if is_valid and is_v4_excluded(name, category) then
                    is_valid = false
                end

                -- Filter out hidden items (whitelist: orbital chunks — they
                -- are flag-hidden in SA but ARE legit replication targets;
                -- v4.2.2 D17: single source of truth with mirror-generator's
                -- SPACE_CHUNKS set: the 6 real chunks stay target-eligible).
                if is_valid and (item.hidden or (item.flags and has_flag(item.flags, "hidden"))) then
                    if not SPACE_CHUNK_TARGETS[name] then
                        is_valid = false
                    end
                end

                -- Ensure item actually exists in registry and has valid properties
                if is_valid then
                    targets[name] = {
                        name = name,
                        type = category,
                        subgroup = item.subgroup or "other",
                        stack_size = item.stack_size or 1,
                        icon = item.icon,
                        icons = item.icons,
                        icon_size = item.icon_size,
                        icon_mipmaps = item.icon_mipmaps
                    }
                end
            end
        end
    end

    -- 2. Include fluids if fluid replication is allowed
    local fluids = data.raw.fluid
    if fluids then
        for name, fluid in pairs(fluids) do
            local is_valid_fluid = true

            -- Prevent self-replication/looping of mod fluids
            if string.sub(name, 1, string.len(gprefix)) == gprefix then
                is_valid_fluid = false
            end

            -- v3.7.0 (B1): apply the SAME step-item filter to fluids as to
            -- items. With Angel's petrochem, hundreds of gaseous/liquid
            -- intermediates (gas-*, liquid-* — already in STEP_EXPLICIT) are
            -- pure processing steps, not replication targets.
            if is_valid_fluid and is_step_item(name) then
                is_valid_fluid = false
            end

            -- v3.7.0 (B1): fluid eligibility — a fluid is replicable only if it
            -- is produced by some recipe, is a minable resource (e.g.
            -- bob-lithia-water), or is a known base resource / fluid override
            -- (water, crude-oil, fusion-plasma...). Phantom/spawn-only fluids
            -- (mod internals with no producing recipe) are excluded — same
            -- rule as items, previously missing for fluids.
            if is_valid_fluid and not (is_produced_by_recipe(name) or is_minable_resource(name) or CostSolver.is_known_resource(name)) then
                is_valid_fluid = false
            end

            -- Filter out hidden fluids (same as items)
            if is_valid_fluid and fluid.hidden then
                is_valid_fluid = false
            end

            if is_valid_fluid then
                targets[name] = {
                    name = name,
                    type = "fluid",
                    subgroup = fluid.subgroup or "fluid",
                    icon = fluid.icon,
                    icons = fluid.icons,
                    icon_size = fluid.icon_size,
                    icon_mipmaps = fluid.icon_mipmaps
                }
            end
        end
    end

    return targets
end

return TargetMapper
