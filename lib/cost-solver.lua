local helpers = require("lib.helpers")

local CostSolver = {}

-- Machine efficiency multipliers (from original replvar system).
-- These adjust replication cost based on what type of machine the original
-- recipe uses. More efficient machines (electric furnaces) reduce replication
-- cost; more complex machines (refineries, centrifuges) increase it.
-- Format: recipe-category-name → efficiency multiplier
-- Enabled via startup setting "dmrsa-use-machine-efficiency" (default: true).
local MACHINE_EFFICIENCY = {
    ["crafting"] = 56/90,                       -- Assembling machine 3
    ["advanced-crafting"] = 56/90,              -- Assembling machine 3
    ["smelting"] = 1/3,                         -- Electric furnace (3x cheaper)
    ["chemistry"] = 56/90,                      -- Chemical plant
    ["oil-processing"] = 14/9,                  -- Oil refinery (more expensive)
    ["centrifuging"] = 140/81,                  -- Centrifuge (more expensive)
    ["rocket-building"] = 25/27,                -- Rocket silo
    ["crafting-with-fluid"] = 56/90,            -- Assembling machine 3 with fluid
    ["crafting-with-fluid-or-recycling"] = 56/90, -- Recycling or fluid crafting
    ["recycling"] = 1.0,                        -- Recycler (neutral baseline)
    ["hand-crafting"] = 1.0,                    -- Player hand crafting (neutral)
    -- Space Age specific categories — names MUST match the real SA internal
    -- names (verified against space-age/prototypes/recipe.lua). Earlier keys
    -- used wrong spellings (metallurgic, electromagnetic, cryogenic,
    -- organic-or-egg) so those machines fell through to the neutral 1.0
    -- fallback. Fixed in v3.5.20.
    ["farming"] = 1.0,                          -- Agricultural tower (if used)
    ["brewing"] = 1.0,                          -- Biochamber (if used)
    ["metallurgy"] = 1/3,                       -- Foundry (3x cheaper, like smelting)
    ["electromagnetics"] = 1.0,                 -- Electromagnetic plant
    ["cryogenics"] = 1.0,                       -- Cryogenic plant
    ["organic"] = 1.0,                          -- Biochamber / organic recipes
    ["crushing"] = 1.0,                         -- Crusher (Space Age)
    ["captive-spawner-process"] = 1.5,          -- Captive biter spawner (biochamber, more complex)
    -- v3.7.0 (A3): Bob's / Angel's / overhaul-mod crafting categories. Without
    -- these entries every mod category fell to the neutral 1.0 fallback,
    -- losing the machine-efficiency cost adjustment (and, for expensive mod
    -- machines like electrolysis, under-pricing replication).
    ["bob-assembling-1"] = 56/90,               -- Bob's assembler 1 (like AM1-ish)
    ["bob-assembling-2"] = 56/90,               -- Bob's assembler 2
    ["bob-assembling-3"] = 56/90,               -- Bob's assembler 3 (like AM3)
    ["bob-assembling-4"] = 56/90,               -- Bob's assembler 4
    ["bob-assembling-5"] = 56/90,               -- Bob's assembler 5
    ["bob-assembling-6"] = 56/90,               -- Bob's assembler 6
    ["bob-chemical-furnace"] = 1/3,             -- Bob's chemical furnace (smelting-tier cheap)
    ["bob-mixing-furnace"] = 1/3,               -- Bob's mixing furnace (alloy mixing)
    ["bob-electrolysis"] = 140/81,              -- Bob's electrolysis (expensive, like centrifuge)
    ["bob-distillery"] = 14/9,                  -- Bob's distillery (like oil refinery)
    ["bob-air-pump"] = 14/9,                    -- Bob's air pump (compression, complex)
    ["bob-water-pump"] = 1.0,                   -- Bob's water pump (neutral)
    ["bob-void"] = 1.0,                         -- Bob's void (destruction, neutral)
    ["bob-void-fluid"] = 1.0,                   -- Bob's void fluid (destruction, neutral)
    ["bob-petrochem"] = 14/9,                   -- Bob's petrochem (complex, refinery-like)
    ["electronics"] = 56/90,                    -- Bob's electronics assembly (like AM3)
    ["electronics-with-fluid"] = 56/90,         -- Bob's electronics with fluid
    ["barrelling"] = 1.0,                       -- Barrelling (neutral)
}

local BASE_RESOURCE_COSTS = {
    ["iron-ore"] = { dark_matter = 1.0, time = 1.0, tier = 1 },
    ["copper-ore"] = { dark_matter = 1.0, time = 1.0, tier = 1 },
    ["coal"] = { dark_matter = 1.0, time = 1.0, tier = 1 },
    ["stone"] = { dark_matter = 0.8, time = 0.8, tier = 1 },
    ["wood"] = { dark_matter = 0.5, time = 0.5, tier = 1 },
    ["water"] = { dark_matter = 0.01, time = 0.01, tier = 1 },
    ["crude-oil"] = { dark_matter = 0.1, time = 0.1, tier = 1 },
    ["uranium-ore"] = { dark_matter = 5.0, time = 5.0, tier = 3 },
    
    -- Space Age Specific Ores/Plants
    ["calcite"] = { dark_matter = 1.2, time = 1.2, tier = 2 },
    ["scrap"] = { dark_matter = 0.6, time = 0.6, tier = 1 },
    ["holmium-ore"] = { dark_matter = 4.0, time = 4.0, tier = 3 },
    ["tungsten-ore"] = { dark_matter = 4.0, time = 4.0, tier = 3 },
    ["jellynut"] = { dark_matter = 2.0, time = 2.0, tier = 3 },
    ["yumako"] = { dark_matter = 2.0, time = 2.0, tier = 3 },
    ["spoiled-organic-substrate"] = { dark_matter = 0.5, time = 0.5, tier = 3 },
    ["metallic-asteroid-chunk"] = { dark_matter = 2.0, time = 2.0, tier = 4 },
    ["carbonic-asteroid-chunk"] = { dark_matter = 2.0, time = 2.0, tier = 4 },
    ["oxide-asteroid-chunk"] = { dark_matter = 2.0, time = 2.0, tier = 4 },
    ["promethium-asteroid-chunk"] = { dark_matter = 10.0, time = 10.0, tier = 5 },
    ["promethium-ore"] = { dark_matter = 20.0, time = 20.0, tier = 5 },
    ["promethium-science-pack"] = { dark_matter = 50.0, time = 50.0, tier = 5 },

    -- v4.2 (dump audit B3): Bob's individual gem ores are ITEMS whose only
    -- producing recipes are "-recycling" (excluded from build_recipe_map), so
    -- the solver found no path and they were never replicated. bobores on the
    -- 138-mod modlist generates bob-amethyst/diamond/emerald/ruby/sapphire/
    -- topaz-ore (not bob-gem-ore anymore). Classify them directly: endgame
    -- rare materials (tier 5).
    ["bob-amethyst-ore"] = { dark_matter = 45.0, time = 5.0, tier = 5 },
    ["bob-diamond-ore"] = { dark_matter = 45.0, time = 5.0, tier = 5 },
    ["bob-emerald-ore"] = { dark_matter = 45.0, time = 5.0, tier = 5 },
    ["bob-ruby-ore"] = { dark_matter = 45.0, time = 5.0, tier = 5 },
    ["bob-sapphire-ore"] = { dark_matter = 45.0, time = 5.0, tier = 5 },
    ["bob-topaz-ore"] = { dark_matter = 45.0, time = 5.0, tier = 5 },
}

-- Special fluids that have no crafting recipe (passive outputs of buildings
-- like the fusion reactor) and need explicit tier classification. Without
-- this, they would fall through to a tier-1 fallback in solve_cost because
-- no recipe exists to compute their cost from.
local FLUID_TIER_OVERRIDES = {
    ["fusion-plasma"] = { dark_matter = 25.0, time = 25.0, tier = 5 },
}

local recipe_map = {}
local recipe_tech_map = {}
-- Memoization cache: stores raw cost (pre-penalty) keyed by item name
-- Each entry: { dark_matter = <raw_dm>, time = <raw_time>, tier = <tier> }
local solved_cache = {}
-- Cache for cycle-detected fallback values to avoid repeated computation
local cycle_cache = {}

-- v3.7.0 (A1): Material-based tier mapping for mod-added ores. The dynamic
-- fallback in initialize_base_resources() used to map EVERY unlisted minable
-- resource to tier 1 / cost 1.5 — with Bob's/Angel's that made endgame ores
-- (gold, tungsten, gems, thorium) replicable from the tier-1 replicator before
-- the player could even mine them. This table maps common mod ore materials to
-- a progression tier so the fallback respects game progression.
-- Keys are substrings matched against the RESULT name (e.g. "bob-tin-ore"
-- contains "tin"). Order matters: more specific materials first.
local MOD_ORE_TIERS = {
    -- Tier 2 (early-mid metals — shape/element replicator)
    { pattern = "tin",     tier = 2 },
    { pattern = "lead",    tier = 2 },
    { pattern = "zinc",    tier = 2 },
    { pattern = "nickel",  tier = 2 },
    { pattern = "silver",  tier = 2 },
    { pattern = "quartz",  tier = 2 },
    { pattern = "sulfur",  tier = 2 },
    { pattern = "graphite", tier = 2 },
    -- Tier 3 (chemical-era metals — chemical replicator)
    { pattern = "bauxite", tier = 3 },  -- aluminium ore
    { pattern = "rutile",  tier = 3 },  -- titanium ore
    { pattern = "cobalt",  tier = 3 },
    { pattern = "chrome",  tier = 3 },  -- chromium
    { pattern = "manganese", tier = 3 },
    -- Tier 4 (late-game metals — conduit replicator)
    { pattern = "gold",    tier = 4 },
    { pattern = "thorium", tier = 4 },
    { pattern = "tungsten", tier = 4 },
    { pattern = "titanium", tier = 4 },
    { pattern = "platinum", tier = 4 },
    -- Tier 5 (endgame materials)
    { pattern = "gem",     tier = 5 },  -- bob-gem-ore
    { pattern = "iridium", tier = 5 },
    { pattern = "osmium",  tier = 5 },
    { pattern = "neodymium", tier = 5 },
    -- v3.7.0 (B5): individual gem ores (bobores generates bob-amethyst-ore /
    -- bob-diamond-ore / bob-emerald-ore / bob-ruby-ore / bob-sapphire-ore /
    -- bob-topaz-ore from bob-gem-ore). "gem" alone doesn't match them, so they
    -- fell to the tier-1 fallback (dump-verified: assigned 1, real 5). Same
    -- endgame tier as the unsorted gem ore.
    { pattern = "amethyst", tier = 5 },
    { pattern = "diamond",  tier = 5 },
    { pattern = "emerald",  tier = 5 },
    { pattern = "ruby",     tier = 5 },
    { pattern = "sapphire", tier = 5 },
    { pattern = "topaz",    tier = 5 },
    -- v4.2 (dump 4.1.0, Angel's full + planetaris): ores from overhaul mods
    -- that the recipe-chain solver resolves to tier 1 (Angel's gives ores
    -- crafting recipes — crushing/floatation — so they never hit the resource
    -- fallback where MOD_ORE_TIERS applied). Angel's ores: ore1..6 are the six
    -- base minerals (saphirite...jivolite), early-mid game. Specific metals
    -- first (more specific patterns before generic "ore").
    -- CRITICAL (Lua pitfall): `-` is a LAZY QUANTIFIER in Lua patterns, NOT a
    -- literal hyphen — every hyphen must be `%-`. Unescaped patterns silently
    -- fail to match (and let earlier simple patterns like "tin" win:
    -- "angels-platinum-ore" contains "tin"!).
    { pattern = "angels%-americium", tier = 5 },
    { pattern = "angels%-curium",    tier = 5 },
    { pattern = "angels%-neptunium", tier = 5 },
    { pattern = "angels%-platinum",  tier = 5 },
    { pattern = "angels%-chrome",    tier = 4 },
    { pattern = "angels%-fluorite",  tier = 3 },
    { pattern = "angels%-manganese", tier = 3 },
    { pattern = "angels%-thorium",   tier = 4 },
    { pattern = "angels%-ore",       tier = 2 },   -- angels-ore1..ore9 base minerals
    { pattern = "planetaris%-raw%-emerald", tier = 5 },
    { pattern = "planetaris%-raw%-ruby",    tier = 5 },
    { pattern = "planetaris%-raw%-sapphire", tier = 5 },
    { pattern = "planetaris%-raw",   tier = 4 },
    { pattern = "planetaris%-metallic", tier = 2 },
    { pattern = "sphalerite",       tier = 2 },   -- zinc sulfide ore
    { pattern = "tetrahedrite",     tier = 2 },   -- copper antimony ore
    { pattern = "vaterite",         tier = 3 },   -- calcium carbonate (planetaris)
    { pattern = "gold%-ore",        tier = 4 },   -- generic gold ore (SE/planetaris)
    -- v4.2 (dump 4.1.0): baseline NON-ore materials from overhaul mods that
    -- have NO unlocking tech (Bob's/Angel's redirect the vanilla unlocks to
    -- their own recipes — e.g. "plastics" descubre bob-plastic-pipe, not
    -- plastic-bar). Without this they all fell to materials-1. Tier reflects
    -- their progression in petrochem/biochem (3) or planet-level gating (4).
    { pattern = "plastic%-bar",     tier = 3 },
    { pattern = "resin",            tier = 3 },
    { pattern = "rubber",           tier = 3 },
    { pattern = "wax",              tier = 3 },
    { pattern = "polysaccharides",  tier = 3 },
    { pattern = "sulfuric%-acid",   tier = 3 },
    { pattern = "ammoniacal%-solution", tier = 4 },
    { pattern = "lava",             tier = 4 },
    { pattern = "nitrogen",         tier = 3 },
    { pattern = "blood",            tier = 4 },
    { pattern = "lymph",            tier = 4 },
    { pattern = "dirty%-lymph",     tier = 4 },
    { pattern = "royal%-jelly",     tier = 4 },
    { pattern = "%-sand$",          tier = 2 },   -- planetaris-sand / pure-sand
    { pattern = "thermal%-water",   tier = 3 },
    { pattern = "gas%-natural",     tier = 2 },
    { pattern = "multi%-phase%-oil", tier = 3 },
    { pattern = "condensates",      tier = 3 },
    { pattern = "rpg_",             tier = 3 },   -- RPG system potions (no tech)
    { pattern = "nitric%-acid",     tier = 3 },   -- mid-game acid (no same-mod tech)
    -- v4.2.x (2026-08-23, consumibles audit): items with NO producing recipe
    -- that fell to the tier-1/2 baseline. Tiers reflect their real
    -- progression position (see research/nosotros-fix-specs.md §3).
    { pattern = "depleted%-.*fuel%-cell$", tier = 3 },  -- spent nuclear fuel ×4 (reprocessing is t3)
    { pattern = "mushell%-seed",    tier = 4 },   -- Gleba-family seed (agriculture L4)
    { pattern = "fossil%-larvae",   tier = 4 },   -- apiculture byproduct (L4)
    { pattern = "fission%-construction%-robot", tier = 3 },  -- construction infra, no producing recipe in dump
    -- v4.2.2 (A2 commit-2, sim-a2-rescale.md §2.6 — 24 items dump-confirmed,
    -- families reach 73): material families degraded to t1 by chain collapse
    -- (zero-ingredient/cycle terminators). Floors only RAISE.
    { pattern = "angels%-ingot",    tier = 2 },   -- ingot-copper/iron t1→2; silver/tin 2; alu..zinc 3; chrome/gold/titanium 4; platinum 5
    { pattern = "angels%-powder",   tier = 2 },   -- powder-copper/iron t1→2 (mixers are machines, no-op)
    { pattern = "angels%-roll",     tier = 2 },   -- roll-copper/iron/steel t1→2; tin 2; alu/silver 3; gold/titanium 4
    { pattern = "angels%-wire%-coil", tier = 2 }, -- wire-coil-copper t1→2
    { pattern = "angels%-geode",    tier = 3 },   -- geode-* all t2→3 (mid-game refining byproducts)
    { pattern = "angels%-crystal%-dust", tier = 3 },
    { pattern = "angels%-catalyst%-metal", tier = 3 }, -- green t1/carrier t2/blue..yellow 3 → ≥3 (lottery unifier)
    { pattern = "angels%-liquid%-ferric%-chloride%-solution", tier = 3 },
    { pattern = "angels%-liquid%-cupric%-chloride%-solution", tier = 3 },
    { pattern = "angels%-liquid%-molten", tier = 4 }, -- 9 vulcanus fluids (unfloored)
    { pattern = "spaceship%-scrap", tier = 3 },   -- space material, zero-ing fallback t1→3
    { pattern = "planetaris%-magnesium%-dust", tier = 2 }, -- documents current state (no-op)
    { pattern = "auric%-asteroid%-chunk", tier = 5 },  -- solver-side floor (mirror SPACE_CHUNKS already t5)
    { pattern = "bismuth%-asteroid%-chunk", tier = 5 }, -- bismuth t5@39s — closes the chain-tier leak
    { pattern = "bob%-wooden%-board", tier = 2 },  -- t1-resolved degradation
    { pattern = "coal%-crushed",   tier = 2 },     -- t1-resolved degradation
}

-- v4.2: universal ore-tier override. MOD_ORE_TIERS used to apply ONLY in the
-- resource fallback of initialize_base_resources() — ores that gained crafting
-- recipes from overhaul mods (Angel's crushing/floatation, SE, planetaris)
-- resolved through the recipe chain to tier 1 (dump 4.1.0: bob-tin-ore=1,
-- bob-gold-ore=3, angels-ore1..6=1 with Angel's full). The material name is the
-- ground truth for progression, so the override applies to ANY solve_cost
-- result as a FLOOR. Returns nil when the name matches nothing.
-- IMPORTANT: returns the LONGEST matching pattern, not the first — simple
-- metal names are substrings of composite ones ("angels-platinum-ore"
-- contains "tin"!); the most specific material wins.
local function get_ore_tier_override(name)
    local best_tier, best_len = nil, -1
    for _, ore in ipairs(MOD_ORE_TIERS) do
        if string.find(name, ore.pattern) then
            local plen = #ore.pattern
            if plen > best_len then
                best_len = plen
                best_tier = ore.tier
            end
        end
    end
    return best_tier
end

-- Scans all resource entities to discover dynamic base resource products (e.g. from mods)
function CostSolver.initialize_base_resources()
    local resources = data.raw.resource
    if not resources then return end

    for _, res in pairs(resources) do
        if res.minable then
            local results = res.minable.results
            if not results and res.minable.result then
                results = { { name = res.minable.result, amount = 1 } }
            end

            if results and #results > 0 then
                for _, result in ipairs(results) do
                    local name = result.name or result[1]
                    if name and not BASE_RESOURCE_COSTS[name] then
                        -- Detect if it requires advanced fluid mining (e.g. uranium, holmium)
                        local requires_fluid = res.minable.required_fluid ~= nil
                        local base_tier = requires_fluid and 3 or 1
                        local base_cost = requires_fluid and 4.0 or 1.5

                        -- v3.7.0 (A1): infer tier from the material name so
                        -- mod ores respect progression instead of all landing
                        -- at tier 1. Cost scales with tier (roughly tier^1.5)
                        -- so deep-tier ores are never cheap to replicate.
                        for _, ore in ipairs(MOD_ORE_TIERS) do
                            if string.find(name, ore.pattern) then
                                if ore.tier > base_tier then
                                    base_tier = ore.tier
                                    base_cost = math.max(base_cost, 1.5 * (ore.tier ^ 1.5))
                                end
                                break
                            end
                        end

                        -- v4.2 refino (original-mod study): RAREZA de ore — modelo COMPLETO del
                        -- original: cost = var("ore")(2) × (mining_time /
                        -- base_density × 8). La densidad no está en los
                        -- resource protos (el original la pasaba a mano por
                        -- mod); inferimos density=4 (típica de ores normales)
                        -- → cost = 2 × (mining_time/4 × 8) = mining_time × 4.
                        -- Los ores raros (mining lento: thorium 2.5,
                        -- tungsten 5) pagan mucho más que los comunes.
                        base_cost = base_cost + (res.minable.mining_time or 0.75) * 4

                        BASE_RESOURCE_COSTS[name] = {
                            dark_matter = base_cost,
                            time = base_cost,
                            tier = base_tier
                        }
                        helpers.info("Dynamically mapped base resource: " .. name .. " (Tier " .. base_tier .. ", Cost " .. base_cost .. ")")
                    end
                end
            end
        end
    end
end

-- v3.7.0 (B1): expose whether a name is a KNOWN base resource / fluid override.
-- target-mapper uses this for fluid eligibility so fluid targets that are not
-- produced by any recipe AND are not minable AND are not known (e.g. phantom
-- fluid internals) get excluded.
function CostSolver.is_known_resource(name)
    if BASE_RESOURCE_COSTS[name] then return true end
    if FLUID_TIER_OVERRIDES[name] then return true end
    return false
end

-- Helper: check if a recipe belongs to a category (handles 2.0 single-string and 2.1 array)
local function recipe_has_category(recipe, cat)
    if recipe.categories then
        for _, c in ipairs(recipe.categories) do
            if c == cat then return true end
        end
    end
    if recipe.category == cat then
        return true
    end
    return false
end

-- Builds recipe mapping for quick product -> recipe lookups
function CostSolver.build_recipe_map()
    if not data or not data.raw or not data.raw.recipe then return end

    for name, recipe in pairs(data.raw.recipe) do
        -- EXCLUDE recycling, unbarreling, cyclic byproduct, and DMR's OWN
        -- recipes to prevent massive cost infinite loops.
        local is_valid_recipe = true
        if recipe_has_category(recipe, "recycling") or string.find(name, "%-recycling$") then
            is_valid_recipe = false
        end
        if recipe_has_category(recipe, "barreling") or string.find(name, "empty%-") or string.find(name, "%-unbarrel") then
            is_valid_recipe = false
        end
        -- v4.2.2 (A2 commit-2, sim §2.6): DMR's own dmrsa-repl-*/refine-*
        -- recipes are zero-ingredient (cost = energy_required), so letting
        -- them into the map makes branch 7 (zero-ingredient) treat them as
        -- legit chain terminators for mod items (angels-thermal-water read
        -- dm 1.5). Same exclusion class as -recycling$.
        if string.find(name, "^dmrsa%-") then
            is_valid_recipe = false
        end

        if is_valid_recipe then
            local results = {}
            if recipe.results then
                results = recipe.results
            elseif recipe.result then
                local count = recipe.result_count or 1
                results = { { name = recipe.result, amount = count, type = "item" } }
            elseif recipe.normal and recipe.normal.results then
                results = recipe.normal.results
            elseif recipe.normal and recipe.normal.result then
                local count = recipe.normal.result_count or 1
                results = { { name = recipe.normal.result, amount = count, type = "item" } }
            end

            if #results > 0 then
                for _, product in ipairs(results) do
                    local product_name = product.name or product[1]
                    if product_name then
                        -- Helper: count ingredients safely across 2.0/2.1 recipe formats.
                        -- Recipes in Factorio 2.0+ may define ingredients only in
                        -- recipe.normal.ingredients (or recipe.expensive.ingredients),
                        -- leaving recipe.ingredients as nil. Without this fallback,
                        -- such recipes get a count of 99 and never win the simplicity
                        -- comparison, causing tier misclassification in overhaul mods.
                        local function get_ing_count(r)
                            if r.ingredients then return #r.ingredients end
                            if r.normal and r.normal.ingredients then return #r.normal.ingredients end
                            if r.expensive and r.expensive.ingredients then return #r.expensive.ingredients end
                            return 99
                        end
                        -- Prefer simpler recipes if duplicates exist
                        if not recipe_map[product_name] then
                            recipe_map[product_name] = recipe
                        else
                            local current_recipe = recipe_map[product_name]
                            local current_ing_count = get_ing_count(current_recipe)
                            local new_ing_count = get_ing_count(recipe)
                            if new_ing_count > 0 and new_ing_count < current_ing_count then
                                recipe_map[product_name] = recipe
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Builds technology unlock mapping to determine item tiers
function CostSolver.build_tech_map()
    local techs = data.raw.technology
    if not techs then return end

    for tech_name, tech in pairs(techs) do
        local effects = tech.effects
        if effects then
            for _, effect in ipairs(effects) do
                if effect.type == "unlock-recipe" and effect.recipe then
                    recipe_tech_map[effect.recipe] = tech
                end
            end
        end
    end
end

-- Classifies technology science requirements into tier levels
function CostSolver.get_tier_from_tech(tech)
    if not tech or not tech.unit or not tech.unit.ingredients then return 1 end
    
    local max_tier = 1
    local pack_count = 0
    for _, ingredient in ipairs(tech.unit.ingredients) do
        local name = ingredient.name or ingredient[1]
        if not name then goto continue_ingredient end
        pack_count = pack_count + 1

        -- Tier 1 packs (early game).
        -- These are recognized explicitly to enable accurate count-based fallback.
        if name == "automation-science-pack" or name == "logistic-science-pack"
           or string.find(name, "automation") or string.find(name, "logistic") then
            -- max_tier stays at least 1
            goto continue_ingredient

        -- Tier 2: military science
        elseif name == "military-science-pack" or string.find(name, "military") then
            max_tier = math.max(max_tier, 2)

        -- Tier 3: chemical, production, utility (all BEFORE planets).
        -- Replication tier 3 = Chemical Replicator. Production/utility are
        -- late-chemical in vanilla progression but still pre-planet.
        elseif name == "chemical-science-pack"
               or string.find(name, "chemical")
               or name == "production-science-pack" or name == "utility-science-pack"
               or string.find(name, "production") or string.find(name, "utility")
               or string.find(name, "advanced%-logistic") then  -- Bob's: bob-advanced-logistic-science-pack
            max_tier = math.max(max_tier, 3)

        -- Tier 4: Space Age planetary packs (the planets ARE tier 4)
        elseif name == "metallurgic-science-pack" or name == "electromagnetic-science-pack" or name == "agricultural-science-pack"
               or string.find(name, "metallurgic") or string.find(name, "electromagnetic") or string.find(name, "agricultural") then
            max_tier = math.max(max_tier, 4)

        -- Tier 5: space, cryogenic, promethium, gold, alien
        elseif name == "space-science-pack" or name == "cryogenic-science-pack" or name == "promethium-science-pack"
               or string.find(name, "space") or string.find(name, "cryogenic") or string.find(name, "promethium")
               or string.find(name, "singularity") or string.find(name, "matter")
               or string.find(name, "gold") or name == "bob-science-pack-gold"
               or string.find(name, "alien") then
            max_tier = math.max(max_tier, 5)

        -- Generic numbered science pack detection:
        -- Many mod science packs follow "modname-science-pack-N" naming.
        -- The number in the name is a reasonable proxy for tier.
        else
            local num_match = string.match(name, "science%-pack%-(%d+)")
            if num_match then
                local num = tonumber(num_match)
                if num then
                    -- Map number to tier: 1→2, 2→2, 3→3, 4→4, 5→5
                    local num_tier = math.min(5, math.max(2, num))
                    max_tier = math.max(max_tier, num_tier)
                end
            end
        end
        ::continue_ingredient::
    end

    -- Fallback: if no vanilla/mod science packs matched, use pack count as heuristic
    -- More unique packs = higher tier in progression.
    if max_tier == 1 and pack_count >= 5 then
        max_tier = 3
    elseif max_tier == 1 and pack_count >= 3 then
        max_tier = 2
    end
    return max_tier
end

-- Safely calculates replication cost recursively with cycle detection
-- Uses memoization: raw costs are cached and penalty is applied at retrieval.
-- Cycle-detected fallbacks are cached in a separate table to prevent
-- repeated computation when the same dependency cycle is encountered.
function CostSolver.solve_cost(name, visited, is_root, depth)
    if is_root == nil then is_root = true end
    depth = depth or 0

    -- 1. Check cycle cache (previously detected cycles)
    if cycle_cache[name] then
        return cycle_cache[name]
    end

    -- 2. Check main memoization cache (stores raw, pre-penalty costs)
    if solved_cache[name] then
        local cached = solved_cache[name]
        local penalty = helpers.get_startup_setting("replication-penalty", 0.5)
        -- v4.2 refino (original-mod study): el penalty del ORIGINAL es +0.5
        -- FIJO por item (suma, no multiplicador). El multiplicador decayente
        -- inflaba los items de cadena larga y contradecía la descripción
        -- ("added to the cost"). Ahora: dark_matter += penalty, time +=
        -- penalty×0.5, en ambos métodos.
        return {
            dark_matter = cached.dark_matter + penalty,
            time = cached.time + penalty * 0.5,
            tier = cached.tier
        }
    end

    -- 3. Base resources check
    if BASE_RESOURCE_COSTS[name] then
        local base = BASE_RESOURCE_COSTS[name]
        -- v4.2: ore-tier override as floor (a statically-mapped ore that got a
        -- low tier before the table was extended must respect the material map).
        local ore_override = get_ore_tier_override(name)
        if ore_override and ore_override > (base.tier or 1) then
            return {
                dark_matter = math.max(base.dark_matter or 1, 1.5 * (ore_override ^ 1.5)),
                time = base.time,
                tier = ore_override
            }
        end
        return base
    end

    -- 3b. Fluid tier overrides (for fluids with no crafting recipe)
    if FLUID_TIER_OVERRIDES[name] then
        return FLUID_TIER_OVERRIDES[name]
    end

    -- 4. Cycle prevention
    visited = visited or {}
    if visited[name] then
        -- Cache the fallback so subsequent encounters don't recompute.
        -- Use the item's unlock-tech tier as the fallback tier instead of
        -- hardcoding tier 1. With overhaul mods (Bob's, Angel's, K2), many
        -- legitimately intermediate items have cyclic recipes (e.g. A needs B
        -- and B needs A) or are locked behind mid-game techs; giving them
        -- tier 1 polluted the "Tier 1" grouped tech with Space-Age-tier items.
        -- The tech tier heuristic is a better proxy than a blind 1.
        local cycle_tier = 1
        local cycle_tech = recipe_tech_map[name]
        if cycle_tech then
            cycle_tier = CostSolver.get_tier_from_tech(cycle_tech)
        end
        local fallback = { dark_matter = 5.0, time = 2.0, tier = cycle_tier }
        local ore_override = get_ore_tier_override(name)
        if ore_override and ore_override > fallback.tier then
            fallback.tier = ore_override
            fallback.dark_matter = math.max(fallback.dark_matter, 1.5 * (ore_override ^ 1.5))
        end
        cycle_cache[name] = fallback
        return fallback
    end
    visited[name] = true

    -- 5. Find recipe
    local recipe = recipe_map[name]
    if not recipe then
        -- Unknown item with no recipe, cache and return fallback.
        -- Same tech-tier heuristic: don't blindly assign tier 2, use the
        -- unlock tech if available (Space Age items without recipes like
        -- promethium asteroid chunks or planet-specific materials would
        -- otherwise pollute low-tier grouped techs).
        --
        -- v4.2.2 (A2 commit-2, sim §2.3): orphans no longer get a flat
        -- dm=10.0 — dm and time derive from their TIER (1.5×t^1.5, the
        -- ore-floor formula): an endgame orphan (tenemut, spaceship-scrap)
        -- stops costing the same as a t2 one. Tier from unlock tech → SCL
        -- fallback, floor by MOD_ORE_TIERS as before.
        visited[name] = nil
        local unknown_tier = 2
        local unknown_tech = recipe_tech_map[name]
        if unknown_tech then
            unknown_tier = CostSolver.get_tier_from_tech(unknown_tech)
        end
        local fallback = {
            dark_matter = 1.5 * (unknown_tier ^ 1.5),
            time = 3.0 * unknown_tier / 2,
            tier = unknown_tier,
        }
        local ore_override = get_ore_tier_override(name)
        if ore_override and ore_override > fallback.tier then
            fallback.tier = ore_override
            fallback.dark_matter = math.max(fallback.dark_matter, 1.5 * (ore_override ^ 1.5))
        end
        solved_cache[name] = fallback
        return fallback
    end

    -- Parse ingredients safely
    local ingredients = recipe.ingredients
    if recipe.normal and recipe.normal.ingredients then
        ingredients = recipe.normal.ingredients
    end

    if not ingredients or #ingredients == 0 then
        visited[name] = nil
        local fallback = { dark_matter = 1.0, time = 1.0, tier = 1 }
        local ore_override = get_ore_tier_override(name)
        if ore_override then
            fallback.tier = math.max(fallback.tier, ore_override)
            fallback.dark_matter = math.max(fallback.dark_matter, 1.5 * (ore_override ^ 1.5))
        end
        solved_cache[name] = fallback
        return fallback
    end

    local total_dm = 0
    local total_time = 0.5 -- Base crafting overhead
    local max_tier = 1

    -- Sum up ingredient costs recursively
    for _, ing in ipairs(ingredients) do
        local ing_name = ing.name or ing[1]
        local ing_amount = ing.amount or ing[2] or 1
        if ing_name then
            -- Re-use visited table using standard backtracking instead of deep copy
            local solved = CostSolver.solve_cost(ing_name, visited, false, depth + 1)
            total_dm = total_dm + (solved.dark_matter * ing_amount)
            total_time = total_time + (solved.time * ing_amount * 0.1)
            max_tier = math.max(max_tier, solved.tier)
        end
    end

    -- Extract result amount
    local result_amount = 1
    local results = recipe.results
    if recipe.normal and recipe.normal.results then
        results = recipe.normal.results
    end

    if results then
        for _, res in ipairs(results) do
            if (res.name or res[1]) == name then
                result_amount = res.amount or res[2] or 1
                break
            end
        end
    elseif recipe.result_count then
        result_amount = recipe.result_count
    elseif recipe.normal and recipe.normal.result_count then
        result_amount = recipe.normal.result_count
    end

    if result_amount <= 0 then result_amount = 1 end

    -- Normalize per single item (raw cost, before penalty)
    local final_dm = total_dm / result_amount
    local final_time = total_time / result_amount

    -- Apply machine efficiency multiplier if enabled (Phase 8: replvar system)
    -- This adjusts cost based on what machine type the recipe uses.
    -- e.g. smelting in an electric furnace (efficient) costs less to replicate
    --      than oil processing in a refinery (complex).
    if helpers.get_startup_setting("dmrsa-use-machine-efficiency", true) then
        -- Get the recipe's crafting category (handles 2.0 and 2.1 formats)
        local recipe_categories = recipe.categories
        if not recipe_categories and recipe.category then
            recipe_categories = { recipe.category }
        end
        if not recipe_categories and recipe.normal then
            recipe_categories = recipe.normal.categories
            if not recipe_categories and recipe.normal.category then
                recipe_categories = { recipe.normal.category }
            end
        end
        -- Use the most restrictive (lowest) efficiency multiplier when a recipe
        -- belongs to multiple categories (e.g. smelting + crafting).
        -- math.min() ensures the stricter category wins, which is conservative
        -- by design: a dual-purpose recipe shouldn't be cheaper to replicate
        -- than either of its categories alone.
        local efficiency = 1.0
        if recipe_categories then
            for _, cat in ipairs(recipe_categories) do
                local cat_eff = MACHINE_EFFICIENCY[cat]
                -- v3.7.0 (A3): substring fallback for overhaul-mod categories
                -- not covered by the explicit table. Bob's/Angel's/K2 invent
                -- many category names (bob-smelting-2, angel's petrochem
                -- variants, krastorio assemblers, etc.); matching the base
                -- machine word keeps the efficiency adjustment alive without
                -- needing an entry per mod.
                if not cat_eff then
                    if string.find(cat, "smelt") then
                        cat_eff = 1/3
                    elseif string.find(cat, "chem") then
                        cat_eff = 56/90
                    elseif string.find(cat, "electro") then
                        cat_eff = 140/81
                    elseif string.find(cat, "distill") or string.find(cat, "refin") or string.find(cat, "petro") then
                        cat_eff = 14/9
                    elseif string.find(cat, "centri") then
                        cat_eff = 140/81
                    elseif string.find(cat, "assembl") or string.find(cat, "craft") then
                        cat_eff = 56/90
                    elseif string.find(cat, "oil") then
                        cat_eff = 14/9
                    elseif string.find(cat, "crush") or string.find(cat, "void") then
                        cat_eff = 1.0
                    end
                end
                if cat_eff then
                    efficiency = math.min(efficiency, cat_eff)
                end
            end
        end
        if efficiency ~= 1.0 then
            final_dm = final_dm * efficiency
            final_time = final_time * efficiency
            helpers.debug("Machine efficiency '" .. (recipe.name or name) .. "': " .. string.format("%.3f", efficiency))
        end
    end

    -- Determine tier based on tech unlock (capped at ingredient_max + 1)
    -- This prevents mods (Bob's, Angel's, etc.) with very deep tech trees from
    -- inflating tiers of simple intermediate items. The ingredient chain's own
    -- complexity is a better proxy for replicator tier than the original tech's
    -- science-pack requirements.
    local unlock_tech = recipe_tech_map[recipe.name]
    if unlock_tech then
        local tech_tier = CostSolver.get_tier_from_tech(unlock_tech)
        local ingredient_tier = max_tier
        max_tier = math.max(max_tier, tech_tier)
        -- If the tech tier is more than 1 above the ingredient tier, cap the jump.
        -- This prevents "blue bottle" scenarios where mid-game items from mods
        -- get T5 because their unlocking-tech requires space science.
        -- BUT: if the ingredient tier was 1, it's ambiguous — could be a
        -- legitimately simple item OR a degraded cycle/unknown fallback. In the
        -- fallback case the tech tier is more trustworthy, so we skip the cap
        -- entirely when ingredients resolved to tier 1. This is the trade-off
        -- that fixes "Replication: Components (Tier 1) contains too much stuff"
        -- from the mod portal report (Bob's items pinned at tier 1 by cycles).
        --
        -- v4.2.2 (A2 commit-2, sim-a2-rescale.md §2.5): the bypass is EXACTLY
        -- the degradation mechanism — cycle/zero-ingredient collapses resolve
        -- ingredient_tier to 1, so the cap never applied and collapsed chains
        -- absorbed the unlock tech's full tier (861/1602 tier flips in the
        -- sim without the companion guard). With the dmrsa-* map guard below
        -- the collapse class shrinks; the cap now applies UNCONDITIONALLY
        -- (test run_tests "mid-item cap" asserts the new deliberate value).
        if max_tier > ingredient_tier + 1 then
            max_tier = ingredient_tier + 1
        end
    end

    -- Clean up cycle tracker
    visited[name] = nil

    -- v4.2: ore-tier override as a floor on the recipe-chain result. The
    -- recipe chain (crushing/floatation/processing with Angel's) can resolve
    -- an ore to tier 1 even when the material is mid/late game; the name map
    -- is the ground truth. Also scales cost so deep ores aren't cheap.
    local ore_override = get_ore_tier_override(name)
    if ore_override and ore_override > max_tier then
        max_tier = ore_override
        local min_cost = 1.5 * (ore_override ^ 1.5)
        if final_dm < min_cost then final_dm = min_cost end
    end

    -- Cache the RAW cost (before any penalty) for reuse across different call contexts
    local raw_result = {
        dark_matter = final_dm,
        time = final_time,
        tier = max_tier
    }
    solved_cache[name] = raw_result

    -- v4.2 refino (original-mod study): penalty FIJO +0.5 (suma) en todos
    -- los casos — el multiplicador decayente inflaba cadenas largas. El
    -- setting dmrsa-cost-calculation-method queda SIN EFECTO (igual en
    -- ambas ramas; descripción actualizada en el locale).
    local penalty = helpers.get_startup_setting("replication-penalty", 0.5)
    return {
        dark_matter = final_dm + penalty,
        time = final_time + penalty * 0.5,
        tier = max_tier
    }
end

CostSolver.recipe_map = recipe_map
CostSolver.recipe_tech_map = recipe_tech_map

return CostSolver
