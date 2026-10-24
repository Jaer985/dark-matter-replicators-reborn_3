-- lib/mirror-generator.lua
-- v4.0 (Factorio 2.1): Árbol espejo de replicación.
--
-- Cada tech ORIGINAL del juego genera UNA tech de replicación
-- ("Replication: <tech original>") que desbloquea la replicación de TODOS los
-- items que esa tech desbloquea. El grouped-por-categoría desaparece; las
-- categorías (shape/alloy/chemical/...) quedan SOLO como subgroups visuales.
--
-- Cadena de progresión (filosofía: no replicas sin conocer los materiales):
--   replication-N (máquina)
--     → replication-materials-N (materiales base del tier, 5 techs nuevas)
--       → Replication: <tech original> (techs espejo, una por tech del juego)
--
-- Dump-verificado (3.7.1, Bob's+SA): 945 items → 144 excluidos → 801
-- replicables → ~417 techs espejo + 5 materials + 4 planetary = ~426 techs.

local helpers = require("lib.helpers")
local CostSolver = require("lib.cost-solver")
local TargetMapper = require("lib.target-mapper")
local repltypes = require("lib.repltypes")
local TimingModel = require("lib.timing-model")
local gprefix = "dmrsa-"

local MirrorGenerator = {}

-- ══════════════════════════════════════════════════════════════════
-- Replication recipe CATEGORY (the machine gate that decides R).
-- v4.4.0 (F-5b): the FUEL CLASS is always `dmrsa-replication-1`, because its
-- burn-value price is written for R = 1.0 (the tier-1 replicator: 1 MW /
-- speed 1). Before this, a fuel inherited its item tier's machine
-- (R = 1.875 … 16.0) and the price of every fuel in a real build was 2-13x
-- the model's — 15 of 19 fuel recipes could never break even even at L3.
-- Everything else keeps its planet / tier category. Exported so
-- dmr-tests/test_economy_invariants.lua can assert the rule directly.
function MirrorGenerator.category_for(opts)
    opts = opts or {}
    local prefix = opts.prefix or gprefix
    if opts.fuel then return prefix .. "replication-1" end
    if opts.planet_suffix then return prefix .. "replication-" .. opts.planet_suffix end
    return prefix .. "replication-" .. (opts.tier or 1)
end

-- ══════════════════════════════════════════════════════════════════
-- A7 (v4.4.0): the REPLICATION CEILING and the OWN-MACHINE rule
--
-- ONE predicate decides whether an item may be a replication target:
--   * the mod's OWN machines are never targets — a machine that replicates
--     itself is a loop (and its parts bill is its own cost: the C5 floor then
--     lifts it to hours, dump-measured 3694-15612 s);
--   * anything whose FINAL fair time is above TimingModel.REPLICATION_CEILING
--     (3600 s) is not a target either. Strictly above: 3600 s stays.
-- Returns the human-readable reason (for the ONE log line) or nil.
-- Exported so dmr-tests/test_economy_invariants.lua can assert the rule.
function MirrorGenerator.is_own_machine(name, prefix)
    if type(name) ~= "string" then return false end
    prefix = prefix or gprefix
    local head = prefix .. "replicator"      -- replicator, -1..-5, -<planet>
    if name:sub(1, #head) == head then return true end
    for _, suffix in ipairs({ "refiner", "synthesizer", "collider", "annihilator" }) do
        if name == prefix .. suffix then return true end
    end
    return false
end

function MirrorGenerator.replication_exclusion(name, t, prefix)
    if MirrorGenerator.is_own_machine(name, prefix) then
        return "the mod's own machine (self-replication is a loop)"
    end
    if TimingModel.over_replication_ceiling(t) then
        return string.format("fair time above the %d s replication ceiling",
            TimingModel.REPLICATION_CEILING)
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- Science pack → progression level (1-5)
-- ══════════════════════════════════════════════════════════════════

local PACK_LEVELS = {
    ["automation-science-pack"] = 1,
    ["logistic-science-pack"] = 1,
    ["military-science-pack"] = 2,
    ["chemical-science-pack"] = 3,
    ["production-science-pack"] = 3,
    ["utility-science-pack"] = 3,
    ["metallurgic-science-pack"] = 4,
    ["electromagnetic-science-pack"] = 4,
    ["agricultural-science-pack"] = 4,
    ["space-science-pack"] = 5,
    ["cryogenic-science-pack"] = 5,
    ["promethium-science-pack"] = 5,
}

-- Mod science packs → level (endgame equivalences). Extend here as new
-- overhaul mods appear; unknown packs fall back to the item-tier heuristic.
local MOD_PACK_LEVELS = {
    ["bob-science-pack-gold"] = 5,
    ["bob-alien-science-pack"] = 5,
    ["bob-alien-science-pack-blue"] = 5,
    ["bob-alien-science-pack-green"] = 5,
    ["bob-alien-science-pack-orange"] = 5,
    ["bob-alien-science-pack-purple"] = 5,
    ["bob-alien-science-pack-red"] = 5,
    ["bob-alien-science-pack-yellow"] = 5,
    -- v4.2.2 (batch-3 audit): FORCE-table gaps found in the dump. Levels are
    -- dump-proven: bob-advanced-logistic = SCL 3 of its own tech (Bob's
    -- primary mid-game pack — was being inferred to 5 by endgame
    -- co-consumption); galvanization 3 / golden 4 = their replication
    -- category in the dump; planetaris-refraction/pathological 5 = SCL 5 of
    -- their own techs.
    ["bob-advanced-logistic-science-pack"] = 3,
    ["galvanization-science-pack"] = 3,
    ["golden-science-pack"] = 4,
    ["planetaris-refraction-science-pack"] = 5,
    ["planetaris-pathological-science-pack"] = 5,
}

-- v4.2.2 (batch-3 audit): cap for INFERRED (unknown) pack levels. The dump
-- shows the max-anchor rule systematically over-rates mid-game packs — any
-- endgame tech (≤8 ingredients) co-consuming pack P alongside
-- space/promethium anchors P=5 (62 mirrors inflated; all of Angel's bio +
-- Bob's robot midgame landed at replication-5 with tier-2/3 items). Tier 5
-- is reserved for table/family-declared space-class progressions; dynamic
-- inference may never reach it. Declared BEFORE ensure_inferred_pack_levels
-- so the upvalue resolves.
local INFERENCE_CAP = 4

-- v4.2.2 (D17, decisión del usuario 2026-09-04): real asteroid chunks are
-- orbital-only materials — replication gate = tier 5 + gravity<=0 (the
-- promethium model), regardless of what the cost-solver's chain ranking
-- says. parameter-N / asteroid-chunk-unknown are engine pseudo-chunks, not
-- replication targets, and are deliberately absent.
local SPACE_CHUNKS = {}
for _, n in ipairs({
    "metallic-asteroid-chunk", "carbonic-asteroid-chunk",
    "oxide-asteroid-chunk", "auric-asteroid-chunk",
    "bismuth-asteroid-chunk", "promethium-asteroid-chunk",
}) do
    SPACE_CHUNKS[n] = true
end

-- v4.2.2 (PR-2, decisión del usuario): structural planetary routing.
-- SIGNALS (dump-validated, sim-pr2-structural-routing.md — 24 route changes,
-- 0 regressions):
--   * SPACE_FAMILY: chunks + promethium pack → tier 5 + gravity<=0, never a
--     planet (single source for both gravity<=0 sites below).
--   * Producer surface_conditions (RECIPES, not entities — entity SC proved
--     generic): a recipe's condition set satisfied by exactly ONE DMR
--     planet's surface_properties classifies that producer as planet-
--     exclusive. Guards dump-proven: crafted item result only, recipe must
--     also have a fluid ingredient, ALL SC producers must agree (steam's 13
--     unconditioned producers disagree → dropped), ceiling conditions are
--     factorissimo floors (skip), single-producer fluid OK (ammoniacal).
--   * default_import_location (DIL): item protos carry a home-planet
--     declaration; only EXACT DMR planet names route (73% of holders point
--     at planetaris planets with no replicators — never route those).
-- Precedence: space family → spoil → producer-SC → DIL → legacy keywords
-- (holmium*/electrolyte extension) → manual tables.
local SPACE_FAMILY = {}
for n in pairs(SPACE_CHUNKS) do SPACE_FAMILY[n] = true end
SPACE_FAMILY["promethium-science-pack"] = true
local DMR_PLANET_DIL = {
    vulcanus = true, fulgora = true, gleba = true, aquilo = true,
}
local function build_planet_props()
    local props = {}
    for _, pn in ipairs({ "vulcanus", "fulgora", "gleba", "aquilo" }) do
        local p = data.raw.planet and data.raw.planet[pn]
        if p and p.surface_properties then
            props[pn] = p.surface_properties
        end
    end
    return props
end
-- Satisfied-by set for a recipe's surface_conditions over DMR planets.
local function sc_satisfied_planets(conditions, planet_props)
    local satisfied = {}
    for _, cond in ipairs(conditions or {}) do
        local prop = cond.property
        if prop == "ceiling" then return {} end -- factorissimo floors
        for pn, props in pairs(planet_props) do
            local v = props[prop]
            if v then
                local lo_ok = not cond.min or v >= cond.min
                local hi_ok = not cond.max or v <= cond.max
                if lo_ok and hi_ok then
                    satisfied[pn] = (satisfied[pn] or 0) + 1
                end
            end
        end
    end
    -- every condition must be satisfiable by the SAME planet (unique)
    if next(satisfied) == nil then return nil end
    local n_conds = #conditions
    local hit, total = nil, nil
    for pn, cnt in pairs(satisfied) do
        if not total or cnt > total then total, hit = cnt, pn end
    end
    if total == n_conds and hit then return { hit } end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- v4.2 ADAPTABILITY: dynamic progression levels for UNKNOWN mod packs.
-- Design decision (user, 2026-08-23): the mod must adapt to ANY modlist,
-- not just ours. PACK_LEVELS/MOD_PACK_LEVELS only cover vanilla/SA/Bob's;
-- everything else is inferred from how the loaded modlist itself uses the
-- pack:
--   level(P) = max TABLE-BASED science level among the visible non-DMR
--              technologies that consume P as a research ingredient.
-- Kitchen-sink techs (>8 distinct ingredients, e.g. promethium-style
-- "consume everything" techs) are EXCLUDED from anchoring so endgame
-- mega-techs don't drag early packs to level 5. One pass, no recursion,
-- derived ONLY from table-known levels — no cycles possible.
-- (Declared BEFORE pack_level so the upvalues resolve correctly.)
-- ══════════════════════════════════════════════════════════════════
local inferred_pack_levels = {}
local inferred_built = false
local function ensure_inferred_pack_levels()
    if inferred_built then return end
    inferred_built = true
    for tech_name, tech in pairs(data.raw.technology) do
        if not string.find(tech_name, "dmrsa%-") and not tech.hidden and tech.unit then
            local packs_used, n_packs = {}, 0
            local known_max = nil
            for _, ing in ipairs(tech.unit.ingredients or {}) do
                local p = ing
                if type(ing) == "table" then p = ing[1] or ing.name end
                if type(p) == "string" then
                    n_packs = n_packs + 1
                    packs_used[p] = true
                    local lvl = PACK_LEVELS[p] or MOD_PACK_LEVELS[p]
                    if lvl and (not known_max or lvl > known_max) then known_max = lvl end
                end
            end
            -- anchor only from reasonably-shaped techs
            if known_max and n_packs <= 8 then
                for p in pairs(packs_used) do
                    local cur = inferred_pack_levels[p]
                    -- v4.2.2: cap the ANCHOR itself — inference never yields 5
                    local anchor = known_max > INFERENCE_CAP and INFERENCE_CAP or known_max
                    if not cur or anchor > cur then inferred_pack_levels[p] = anchor end
                end
            end
        end
    end
end

-- Testable accessor (dmr-tests): inferred level for an unknown pack, or nil.
function MirrorGenerator.get_inferred_pack_level(pack_name)
    ensure_inferred_pack_levels()
    return inferred_pack_levels[pack_name]
end

local function pack_level(pack_name)
    if not pack_name or type(pack_name) ~= "string" then return nil end
    if PACK_LEVELS[pack_name] then return PACK_LEVELS[pack_name] end
    if MOD_PACK_LEVELS[pack_name] then return MOD_PACK_LEVELS[pack_name] end
    -- Name heuristics for known Space Age families
    if string.find(pack_name, "promethium") or string.find(pack_name, "cryogenic")
       or string.find(pack_name, "%-space%-") then
        return 5
    end
    if string.find(pack_name, "metallurgic") or string.find(pack_name, "electromagnetic")
       or string.find(pack_name, "agricultural") then
        return 4
    end
    -- v4.2 (adaptability): ANY modlist — unknown packs are anchored dynamically
    -- (see ensure_inferred_pack_levels above); v4.2.2: anchors are capped at
    -- INFERENCE_CAP inside the inference pass itself.
    ensure_inferred_pack_levels()
    return inferred_pack_levels[pack_name]
end

-- Science level (1-5) of a technology, from the max level of its unit packs.
-- Returns nil when the tech has no detectable standard/mod packs.
function MirrorGenerator.get_tech_science_level(tech_name)
    local tech = data.raw.technology[tech_name]
    if not tech or not tech.unit then return nil end
    local max_level = nil
    for _, ing in ipairs(tech.unit.ingredients or {}) do
        local pack = ing
        if type(ing) == "table" then
            pack = ing[1] or ing.name
        end
        local lvl = pack_level(pack)
        if lvl and (not max_level or lvl > max_level) then
            max_level = lvl
        end
    end
    return max_level
end

-- v4.0: REAL depth of a technology in the research tree (1 = no prereqs).
-- When dmrsa-require-original-tech is ON, the mirror tech takes the original
-- tech as a DIRECT prerequisite, so the mirror's tier must be >= the original's
-- tree depth — otherwise Factorio rejects it with
-- "Non-contiguous levels: N, followed by M" (e.g. angel's chlorine-processing
-- sits at depth 4 while its science-pack level maps to 2). Memoized + cycle-safe.
local depth_cache = {}
local depth_in_progress = {}
function MirrorGenerator.get_tech_tree_depth(tech_name)
    if depth_cache[tech_name] then return depth_cache[tech_name] end
    if depth_in_progress[tech_name] then return 1 end  -- cycle guard
    local tech = data.raw.technology[tech_name]
    if not tech or not tech.prerequisites or #tech.prerequisites == 0 then
        depth_cache[tech_name] = 1
        return 1
    end
    depth_in_progress[tech_name] = true
    local max_depth = 0
    for _, prereq in ipairs(tech.prerequisites) do
        local d = MirrorGenerator.get_tech_tree_depth(prereq)
        if d > max_depth then max_depth = d end
    end
    depth_in_progress[tech_name] = nil
    depth_cache[tech_name] = max_depth + 1
    return depth_cache[tech_name]
end

-- ══════════════════════════════════════════════════════════════════
-- Item classification helpers (moved from dynamic-generator)
-- ══════════════════════════════════════════════════════════════════

-- v4.2: mod prefix = everything before the first hyphen ("" for base items).
-- Used to guard process-output tech inheritance (an angels-* item only
-- inherits techs from angels-* producing recipes, never from foreign mods).
-- v4.2.2 (batch-3 audit): "" is returned for the FIRST dash segment; but for
-- a compound name like "biosulfur" there IS no dash — both vanilla "sulfur"
-- and Bio Ind's "biosulfur" got prefix "" and crossed the same-mod guard,
-- so vanilla items inherited foreign (gleba T5) techs. Require a REAL shared
-- prefix: either both names share the same first dash-segment AND it is not
-- empty, or one is a name-compound of the other (recipe "X" produces "X-..."?
-- no — item X-... from recipe X-process: prefix compare stays the honest
-- rule). Compound-less vanilla names now never match foreign producers.
local function mod_prefix(name)
    local dash = string.find(name, "-", 1, true)
    if dash then return string.sub(name, 1, dash - 1) end
    return nil
end

local function same_mod_prefix(a, b)
    local pa, pb = mod_prefix(a), mod_prefix(b)
    if pa and pb then return pa == pb end
    return false
end

-- v4.2: minable resources never inherit a producing recipe's tech — they are
-- mined, not crafted; their tier comes from the cost-solver/base-resource map.
local function is_minable_resource(name)
    local res = data.raw.resource and data.raw.resource[name]
    return res ~= nil
end

-- Determine item category for VISUAL subgroup only (no tier gating in v4.0).
local function get_item_category(name, target)
    local subgroup = target.subgroup or ""
    local type_name = target.type or ""
    local item_proto = data.raw[target.type] and data.raw[target.type][name]

    if mods["space-age"] and item_proto then
        local is_organic = false
        if item_proto.spoil_ticks or item_proto.spoil_to or item_proto.spoil_result then
            is_organic = true
        end
        if is_organic or string.find(name, "yumako") or string.find(name, "jellynut")
           or name == "spoiled-organic-substrate" or name == "nutrients" then
            return "organic"
        end
    end

    if type_name == "resource" or subgroup == "ore" or subgroup == "raw-resource"
       or string.find(name, "ore$") or string.find(name, "%-ore") or string.find(name, "ore%-") then
        return "ore"
    end
    if string.find(name, "science%-pack") then return "science" end
    if type_name == "fluid" then return "chemical" end
    if string.find(name, "module") or subgroup == "module" then
        if string.find(name, "module%-3") then return "module-advanced" end
        return "module"
    end
    local is_military = false
    if type_name == "gun" or type_name == "ammo" or type_name == "armor" or type_name == "capsule" then
        is_military = true
    end
    if string.find(name, "weapon") or string.find(name, "bullet") or string.find(name, "magazine")
       or string.find(name, "rocket") or string.find(name, "grenade") or string.find(name, "shotgun")
       or string.find(name, "rifle") or string.find(name, "cannon") or string.find(name, "missile")
       or string.find(name, "mine%-") or string.find(name, "%-mine") or string.find(name, "capsule")
       or subgroup == "gun" or subgroup == "ammo" then
        is_military = true
    end
    if is_military then
        if string.find(name, "uranium") or string.find(name, "artillery")
           or string.find(name, "explosive%-rocket") or string.find(name, "cluster")
           or string.find(name, "spidertron") or string.find(name, "nuke")
           or string.find(name, "nuclear") or string.find(name, "explosive%-cannon")
           or string.find(name, "sniper") or string.find(name, "laser%-rifle")
           or string.find(name, "gatling") or string.find(name, "plasma")
           or string.find(name, "turret%-[3-9]") or string.find(name, "armor%-mk[3-9]")
           or string.find(name, "mech%-") or string.find(name, "tank%-[2-9]") then
            return "military-advanced"
        end
        return "military"
    end
    if string.find(name, "plate") or string.find(name, "alloy") or string.find(name, "foil")
       or string.find(name, "sheet") or subgroup == "plate" or subgroup == "alloy" then
        return "alloy"
    end
    if string.find(name, "gear") or string.find(name, "pipe") or string.find(name, "stick")
       or string.find(name, "cable") or string.find(name, "wire") or string.find(name, "brick")
       or string.find(name, "frame") or string.find(name, "bearing") or string.find(name, "spring")
       or string.find(name, "ring") or string.find(name, "rod") or string.find(name, "tube")
       or string.find(name, "barrel") or string.find(name, "coil") or string.find(name, "%-ball")
       or string.find(name, "ball%-") or subgroup == "component" or subgroup == "part"
       or subgroup == "intermediate" then
        return "shape"
    end
    if item_proto then
        local name_lower = string.lower(name)
        for _, elem in ipairs(repltypes.element_names) do
            if string.find(name_lower, elem) then return "element" end
        end
    end
    if string.find(name, "exotic") or string.find(name, "artifact") or subgroup == "artifact" then
        return "exotic"
    end
    if string.find(name, "magic") or string.find(name, "mana") or string.find(name, "arcane") then
        return "magic"
    end
    if string.find(name, "alien") or subgroup == "alien" then return "alien" end
    if string.find(name, "spawner") or string.find(name, "worm")
       or (type_name == "capsule" and string.find(name, "spawn")) or subgroup == "living" then
        return "life"
    end
    return "general"
end

-- Correct locale prefix for a target (placeable items use entity-name).
local function get_loc_prefix(name, target)
    if target.type == "fluid" then return "fluid-name" end
    if target.type == "item" or target.type == "ammo" or target.type == "armor"
       or target.type == "gun" or target.type == "capsule" or target.type == "tool"
       or target.type == "module" or target.type == "item-with-entity-data"
       or target.type == "item-with-tags" or target.type == "spidertron-remote"
       -- v4.4.0 (B13): the real registry is `space-platform-starter-pack`
       or target.type == "space-platform-starter-pack" then
        local item_proto = data.raw[target.type] and data.raw[target.type][name]
        if item_proto and item_proto.place_result then
            return "entity-name"
        end
        return "item-name"
    end
    return "entity-name"
end

-- v3.5.24: composite tech icon — bordered 128x128 with the item icon centered.
local function get_tech_icons(name, target, tier)
    local border = "tech-device" .. tier
    if tier < 2 then border = "tech-device2" end
    local subgroup = target.subgroup or ""
    local type_name = target.type or ""
    if type_name == "fluid" then
        border = "tech-chemical"
    elseif string.find(name, "ore") or string.find(subgroup, "ore") or subgroup == "raw-resource" then
        border = "tech-ore"
    elseif string.find(name, "science%-pack") then
        border = "tech-science"
    elseif string.find(name, "module") or subgroup == "module" then
        border = "tech-module"
    elseif string.find(name, "plate") or string.find(name, "alloy") then
        border = "tech-alloy"
    end
    local border_path = "__dark-matter-replicators-reborn__/graphics/icons/borders/" .. border .. ".png"
    local icons = {}
    table.insert(icons, { icon = border_path, icon_size = 128, scale = 1 })
    if target.icons and #target.icons > 0 then
        for _, icon_spec in ipairs(target.icons) do
            local spec = helpers.deep_copy(icon_spec)
            spec.icon_mipmaps = nil
            local isize = spec.icon_size or target.icon_size or 64
            if type(isize) ~= "number" or isize <= 0 then isize = 64 end
            local current_scale = spec.scale or 1
            spec.scale = current_scale * (64 / isize)
            if spec.shift then
                spec.shift = { spec.shift[1] * (64 / isize), spec.shift[2] * (64 / isize) }
            end
            table.insert(icons, spec)
        end
    else
        local icon_path = target.icon or "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
        local isize = target.icon_size or 64
        if type(isize) ~= "number" or isize <= 0 then isize = 64 end
        table.insert(icons, { icon = icon_path, icon_size = isize, scale = 64 / isize })
    end
    return icons
end

-- ══════════════════════════════════════════════════════════════════
-- Main generation
-- ══════════════════════════════════════════════════════════════════

-- v3.6.0: research pack order helper (cosmetic).
-- v4.3: `dmrsa-tenemut-research-required = false` skips the DMR material pack;
-- the caller's fallback below then adds the tier's vanilla packs so a research
-- unit can never end up with an empty ingredient list (v4.2 "no cost" bug).
local function add_research_pack(research_packs, pack, is_dmr_item)
    if is_dmr_item and not helpers.dmr_research_pack_required() then
        return
    end
    local order = helpers.get_startup_setting("dmrsa-research-pack-order", "DMR Item First")
    if order == "Science Pack First" and is_dmr_item then
        table.insert(research_packs, 1, pack)
    else
        table.insert(research_packs, pack)
    end
end

local function tier_material_pack(tier)
    if tier <= 1 then return gprefix .. "tenemut" end
    if tier == 2 then return gprefix .. "dark-matter-scoop" end
    if tier == 3 then return gprefix .. "dark-matter-transducer" end
    return gprefix .. "matter-conduit"
end

function MirrorGenerator.generate()
    helpers.info("Starting MIRROR (v4.0) dynamic generation...")

    -- 1. Init solver state
    CostSolver.initialize_base_resources()
    CostSolver.build_recipe_map()
    CostSolver.build_tech_map()

    -- 2. Targets (already filtered by v4.0 exclusions in target-mapper)
    local targets = TargetMapper.get_potential_replication_targets()
    local fluid_qty = helpers.get_startup_setting("replication-fluid-quantity", 25)
    local require_orig = helpers.get_startup_setting("dmrsa-require-original-tech", true)

    -- v4.2.2 (PR-2): item → producing-recipes index. Built ONCE before the
    -- target loop (the H1 chain-attribution below reuses it).
    -- v4.4.0 (A5, review r1 H2): DMR's OWN machine recipes are candidates now.
    -- The old predicate excluded every `dmrsa-*` recipe, so the mod's five
    -- machines had no producing recipe at all (bill = nil) and the C5 floor
    -- never touched them: a tier-1 replicator recycled for ~6.4x its cost, i.e.
    -- a recycler plus one replicator was a parts printer. Only the GENERATED
    -- recipes are still excluded — `dmrsa-repl-*` (the mirror output, which
    -- would bill an item against itself) and `dmrsa-refine-*` (the refiner's
    -- quality ladder, also generated; it does not exist yet at this point but
    -- the guard stays for the Individual-mode data path).
    local producers_of = {}  -- item -> { recipe names }
    do
        for rname, recipe in pairs(data.raw.recipe) do
            local skip = string.find(rname, "^dmrsa%-repl%-")
                or string.find(rname, "^dmrsa%-refine%-")
                or rname == "recycling"
                or string.find(rname, "%-recycling$")
                or string.find(rname, "^empty%-")
                or string.find(rname, "%-unbarrel$")
            if not skip then
                local results = recipe.results
                if recipe.normal and recipe.normal.results then
                    results = recipe.normal.results
                end
                if results then
                    for _, res in ipairs(results) do
                        local rn = res.name or res[1]
                        if rn then
                            producers_of[rn] = producers_of[rn] or {}
                            table.insert(producers_of[rn], rname)
                        end
                    end
                end
            end
        end
    end
    local planet_props = mods["space-age"] and build_planet_props() or {}
    local producer_sc = {}
    if mods["space-age"] and next(planet_props) then
        for rname, recipe in pairs(data.raw.recipe) do
            local sc = recipe.surface_conditions
            if sc and #sc > 0 and not string.find(rname, "dmrsa%-") then
                -- fluid ingredient required (byproduct co-production guard:
                -- sulfur/iron-ore/plastic-bar misfires died here)
                local ings = recipe.ingredients or (recipe.normal and recipe.normal.ingredients)
                local has_fluid_ing = false
                if ings then
                    for _, ing in ipairs(ings) do
                        if type(ing) == "table" and (ing.type == "fluid" or ing[1] == "fluid") then
                            has_fluid_ing = true
                            break
                        end
                    end
                end
                -- crafted item result required (fluid results never route)
                local results = recipe.results
                if not results and recipe.normal and recipe.normal.results then
                    results = recipe.normal.results
                end
                local crafted = nil
                if results then
                    for _, res in ipairs(results) do
                        if (res.type or "item") == "item" and res.name then
                            crafted = res.name
                            break
                        end
                    end
                end
                if has_fluid_ing and crafted then
                    local planets_hit = sc_satisfied_planets(sc, planet_props)
                    if planets_hit and #planets_hit == 1 then
                        producer_sc[rname] = planets_hit[1]
                    end
                end
            end
        end
    end

    -- v4.4.0 (Part A, timing model v3): recipe → science-pack set of the
    -- (lowest-tier) tech that unlocks it. Feeds the timing model's pack_tier
    -- ("the pack set of the tech that first unlocks the item"). Built ONCE,
    -- before the target loop. The old CT_MULT / BAND_LO / BAND_HI / MACHINE_MULT
    -- ladder + machine-layer detection is GONE — the closed-form model in
    -- lib/timing-model.lua replaces the whole cost/band machinery.
    local recipe_pack_set = {}
    do
        for tname, tech in pairs(data.raw.technology) do
            if (not tech.hidden) and (not string.find(tname, "dmrsa%-"))
               and tech.unit and tech.unit.ingredients then
                local set = {}
                local any = false
                for _, ing in ipairs(tech.unit.ingredients) do
                    local pk = ing.name or ing[1]
                    if pk then set[pk] = true; any = true end
                end
                if any then
                    local pt = TimingModel.pack_tier_from_set(set)
                    for _, eff in ipairs(tech.effects or {}) do
                        if eff.type == "unlock-recipe" and eff.recipe then
                            local cur = recipe_pack_set[eff.recipe]
                            if not cur or pt < cur then
                                recipe_pack_set[eff.recipe] = pt
                            end
                        end
                    end
                end
            end
        end
    end
    -- item → its "first unlock" pack tier (min over its producing recipes;
    -- 1.0 when nothing unlocks it → baseline materials).
    local function item_pack_tier(name)
        local best
        for _, rname in ipairs(producers_of[name] or {}) do
            local pt = recipe_pack_set[rname]
            if pt and (not best or pt < best) then best = pt end
        end
        return best or 1.0
    end

    -- item -> entry: { recipe_name, tier, target, planet_suffix, item_category }
    local items = {}
    local planetary_unlocks = { vulcanus = {}, fulgora = {}, gleba = {}, aquilo = {} }

    -- 3. Generate replication recipes for every target
    local recipe_count = 0
    -- v4.4.0 (Part A + F-2a): replication recipes of the FUEL CLASS (every
    -- burnable solid, priced by burn value) that receive allow_productivity +
    -- the duplication research effects.
    local fuel_recipe_names = {}
    -- v4.4.0 (A7 + F-2a): the ONE escape hatch. Every item that must NOT be a
    -- replication target — a burnable priced above FUEL_MAX_TIME (F-2a), an
    -- item whose final fair time is above the 3600 s ceiling (A7), or one of
    -- the mod's own machines (A7) — lands here and is logged with ONE format.
    -- { name, time, reason }
    local excluded_targets = {}
    local function record_exclusion(name, time, reason)
        excluded_targets[#excluded_targets + 1] = { name = name, time = time, reason = reason }
        -- WARN, not info: the data stage runs at log level "warn" by default,
        -- so an info line would be invisible exactly when a target vanishes
        -- from the tree. One line per skipped target, one format.
        helpers.warn(string.format(
            "Mirror: '%s' is NOT a replication target: %s (fair time %.2f s); recipe, unlock and tech skipped.",
            name, reason, time))
    end
    -- name -> { recipe_name, model_time, r } for every NON-fuel replication
    -- recipe: input of the C5 arbitrage clamp post-pass below.
    local repl_entries = {}
    -- name -> { t, r } for EVERY generated replication recipe (raws, fluids and
    -- fuels included): the parts bill of a recipe is the sum of these.
    local repl_cost = {}
    for name, target in pairs(targets) do
        local solved = CostSolver.solve_cost(name)
        if not solved then
            helpers.debug("Mirror: no cost solution for '" .. name .. "', skipping")
            goto continue_item
        end

        local tier = solved.tier or 1
        -- v4.2 refino (original-mod study): los replicadores DMR son
        -- replicables — cada uno cae en su PROPIO tier (replicator-1 → t1...
        -- replicator-5 → t5), como el original (device3-5 upgrade=true).
        local REPLICATOR_TIER = {
            ["dmrsa-replicator-1"] = 1, ["dmrsa-replicator-2"] = 2,
            ["dmrsa-replicator-3"] = 3, ["dmrsa-replicator-4"] = 4,
            ["dmrsa-replicator-5"] = 5,
        }
        if REPLICATOR_TIER[name] then tier = REPLICATOR_TIER[name] end
        -- v4.4.0 (Part A, timing model v3): dmrsa-tenemut's ACCESS tier follows
        -- where the ore appears (plan §1) — Nauvis/day-one or synthesis → 1, a
        -- planet → that planet's tier, a list → the LOWEST planet that has it.
        -- Its TIME always comes from the ore ladder (R4 = 10 s), never the
        -- tier ladder. (Was: hardcoded tier 5.)
        if name == gprefix .. "tenemut" then
            local tt = TimingModel.tenemut_tier()
            tier = math.max(1, math.min(5, math.floor(tt)))
        end
        -- v4.2.2 (batch-3 audit, PR-1): space-family materials replicate ONLY
        -- in orbit at tier 5 (promethium model: endgame gate + gravity<=0).
        -- The cost-solver ranks auric-asteroid-chunk at tier 1 by chain
        -- difficulty, which is meaningless for an orbital-only endgame
        -- material (dump: its only real unlock path is steam-recycler,
        -- Secretas-gated).
        -- v4.2.2 (D17, decisión del usuario): ALL real asteroid chunks follow
        -- the same rule — they spawn in orbit (never mineable on planets), so
        -- their replication gate is the space tier, not the solver's chain
        -- ranking (metallic/carbonic/oxide sat at t4 via chain difficulty,
        -- letting mid-game replicators farm the space progression).
        -- parameter-N / asteroid-chunk-unknown are engine pseudo-chunks and
        -- are not replication targets.
        if SPACE_CHUNKS[name] then
            tier = 5
        end
        -- v4.2 fix (gate-test dump 2026-08-23): science packs FORCED to their
        -- progression tier (same rule as Individual mode) — the cost-solver
        -- follows their ingredient chains (chemical needs advanced circuits...)
        -- and silently inflates them to tier 4-5.
        local sci_forced = PACK_LEVELS[name] or MOD_PACK_LEVELS[name]
        if sci_forced then tier = sci_forced end
        if tier > 5 then tier = 5 end
        if tier < 1 then tier = 1 end

        -- Planet routing. v4.2.2 (PR-2): structural signals FIRST
        -- (spoil → producer-SC → DIL), legacy keywords remain as fallback
        -- (batch-3 arms stay for one release — defense in depth), manual
        -- tables (SPACE_FAMILY gravity≤0) sit above everything.
        local item_proto = data.raw[target.type] and data.raw[target.type][name]
        local is_organic = false
        if mods["space-age"] and item_proto then
            if item_proto.spoil_ticks or item_proto.spoil_to or item_proto.spoil_result then
                is_organic = true
            end
        end

        -- ══ v4.4.0 (F-2a/F-3b/F-5b): the FUEL CLASS ══
        -- Every burnable SOLID is priced by the energy it returns (the 100 MJ
        -- cap is gone), measured against the BEST burner (heating tower,
        -- effectivity 2.5) and written for R = 1.0 — so its recipe is forced
        -- onto dmrsa-replication-1 (F-5b, see category_for) and carries
        -- allow_productivity so the duplication research can walk the
        -- 1x/2x/3x/4x ladder. Fluids are NOT fuels (C4).
        -- ESCAPE HATCH: a burnable whose fair price is above FUEL_MAX_TIME
        -- cannot be replicated at all — any shorter craft would return more
        -- burn value than it costs (the C1 printer: uranium fuel cells at
        -- 88 MJ for 8 GJ) and an 11-55 hour craft is dead content. It stays
        -- manufacturable and is reported in the log + the receipt.
        local fuel_class = TimingModel.is_burnable(item_proto)
        if fuel_class and TimingModel.fuel_price_over_max(item_proto) then
            record_exclusion(name,
                TimingModel.fuel_time(TimingModel.fuel_joules(item_proto.fuel_value)),
                string.format("burnable price above FUEL_MAX_TIME %d s (F-2a)",
                    TimingModel.FUEL_MAX_TIME))
            goto continue_item
        end

        local planet_suffix = nil
        if mods["space-age"] then
            -- v4.2.2 (PR-2 rule 3): producer surface_conditions (guarded).
            -- ALL producers with SC must agree on ONE planet, AND the SC
            -- producers must BE all of them (pod 2/2 → accept) or ≥3 agree
            -- (steam: 1 of 14 disagrees-by-absence → reject).
            local sc_planet = nil
            do
                local prods = producers_of and producers_of[name]
                if prods then
                    local agreed, n_sc = nil, 0
                    for _, rname in ipairs(prods) do
                        local p = producer_sc[rname]
                        if p then
                            n_sc = n_sc + 1
                            if agreed == nil then
                                agreed = p
                            elseif agreed ~= p then
                                agreed = nil
                                break
                            end
                        end
                    end
                    local n_total = #prods
                    if agreed and n_sc >= 1 and (n_sc == n_total or n_sc >= 3) then
                        sc_planet = agreed
                    end
                end
            end
            -- v4.2.2 (PR-2 rule 4): default_import_location (DMR planets only)
            local dil = item_proto
                and item_proto.default_import_location
                and DMR_PLANET_DIL[item_proto.default_import_location]
                and item_proto.default_import_location or nil
            -- v4.2.2 (PR-2): keyword chain extended with holmium*/electrolyte
            if is_organic or string.find(name, "yumako") or string.find(name, "jellynut")
               or name == "spoiled-organic-substrate" or name == "agricultural-science-pack"
               or name == "nutrients" then
                planet_suffix = "gleba"
            elseif string.find(name, "tungsten") or name == "calcite"
                   or name == "metallurgic-science-pack" or string.find(name, "molten%-")
                   or name == "foundry" or name == "lava"
                   -- v4.2.2: vulcanus-exclusive producers/home items (A5 PR-5)
                   or name == "big-mining-drill" or name == "cliff-explosives" then
                planet_suffix = "vulcanus"
            elseif name == "superconducting-cable" or name == "electromagnetic-science-pack"
                   or (string.find(name, "scrap") and not string.find(name, "spaceship"))
                   or string.find(name, "^holmium") or string.find(name, "%-holmium%-")
                   or name == "electrolyte" then
                planet_suffix = "fulgora"
            elseif name == "ice" or string.find(name, "lithium")
                   or string.find(name, "fluoroketone") or name == "fluorine"
                   or name == "cryogenic-science-pack"
                   -- v4.2.2: aquilo-exclusive fluid (A5 PR-3)
                   or name == "ammoniacal-solution" then
                planet_suffix = "aquilo"
            elseif name == "biochamber" or name == "agricultural-tower"
                   or name == "condensing-agricultural-tower" or name == "heating-tower" then
                -- v4.2.2: Gleba machines escaped the spoil-only rule (A5 PR-4)
                planet_suffix = "gleba"
            end
            -- structural signals apply BEFORE keyword decisions take effect
            -- (they win when both agree; keyword already-set value only
            -- stands when no structural signal exists)
            if not planet_suffix then
                if sc_planet then planet_suffix = sc_planet end
                if not planet_suffix and dil then planet_suffix = dil end
            end
        end

        -- Category: VISUAL ONLY in v4.0 (no tier gating)
        local item_category = get_item_category(name, target)
        local recipe_name = gprefix .. "repl-" .. name
        local loc_prefix = get_loc_prefix(name, target)

        local recipe_subgroup
        if planet_suffix then
            recipe_subgroup = gprefix .. "replication-resources"
        elseif item_category and repltypes[item_category] then
            recipe_subgroup = gprefix .. "replication-" .. item_category
        else
            recipe_subgroup = gprefix .. "replication-tier-" .. tier
        end

        local result_amount = 1
        if target.type == "fluid" then
            result_amount = fluid_qty
        end

        -- v4.4.0 (Part A, timing model v3): closed-form replication TIME.
        --   time(item) = B * g^(tier-1) * C(steps)
        --       B = 6.32 s, g = 2, C = 1 + 0.02*steps (cap 1.50), ceiling 200 s
        --       tier = max(pack_tier, chain_tier)   (decimals allowed)
        --   pack_tier : declared rung for the 12 packs / the pack set of the
        --               tech that first unlocks the item
        --   chain_tier: the item's replication gate (integer `tier` above);
        --               planets replace it with their own band
        -- Fuel / raw / non-craftable targets are priced by their own rules
        -- (energy, ore ladder) — see lib/timing-model.lua. This replaces the
        -- recursive solver cost + per-tier BAND_LO/HI soft clamp; the
        -- dark-matter / cost side of the solver is untouched.
        local steps = TimingModel.steps_of(name)
        -- v4.2 (mejora 6, user) + v4.4.0 (F-7a): the difficulty MULTIPLIER
        -- (Easy 1.0 / Medium 1.5 / High 2.0 / Very Hard 3.0) is passed INTO the
        -- model, which applies it BEFORE the 200 s ceiling — before this fix
        -- the caller multiplied after the clamp, so the "200 s ceiling" was
        -- really 300/400/600 s on Medium/High/Very Hard.
        local replic_mult = helpers.get_research_difficulty_values().replic_mult or 1
        local resolved = TimingModel.resolve({
            name = name,
            chain_tier = tier,
            planet = planet_suffix,
            pack_tier = item_pack_tier(name),
            steps = steps,
            item_proto = item_proto,
            replic_mult = replic_mult,
            result_amount = result_amount,
        })
        local repl_time = resolved.time
        -- Per-difficulty safety cap (600/1000/1800/3200 s). It sits far above
        -- the 200 s ceiling, so it never touches normal content; the FUEL CLASS
        -- is exempt (its burn-value ladder needs 200-3000 s crops and clamping
        -- it would re-open the printer).
        if not resolved.exempt_caps then
            local time_cap = helpers.get_replication_time_cap()
            if repl_time > time_cap then repl_time = time_cap end
        end

        -- ══ v4.4.0 (A7): THE REPLICATION CEILING ══
        -- BEFORE anything is emitted: an item is not a replication target when
        -- its fair time is above 3600 s, or when it IS one of the mod's own
        -- machines (a machine that replicates itself is a loop). Skipping HERE
        -- means no recipe, no unlock effect and — because the item never enters
        -- `items` — no mirror tech either: the tech ends up with an empty effect
        -- list and the M1 guard below drops it with its own log line.
        -- The C5 clamps LIFT prices afterwards, so the same predicate is applied
        -- again to the POST-CLAMP final time (section 3b): one rule, one log.
        do
            local ceiling_reason = MirrorGenerator.replication_exclusion(name, repl_time)
            if ceiling_reason then
                record_exclusion(name, repl_time, ceiling_reason)
                goto continue_item
            end
        end

        -- ══ v4.4.0 (C5/F-4a): replicate-and-recycle arbitrage ══
        -- The clamp itself runs in the POST-PASS after this loop (it needs the
        -- replication time of every INGREDIENT, which may be generated later
        -- in the same pass). Every recipe the mirror priced from the
        -- PROGRESSION ladder is recorded with its model time + machine R; see
        -- "5. C5 arbitrage clamp" below. Items priced by their OWN raw rule
        -- (ore ladder, fluid rule, non-minables) are NOT part of the clamp:
        -- their price is a mining/pumping price, not a craft the recycler can
        -- turn back into materials (and their "producing recipe" in the index
        -- is often a byproduct recipe — lava -> stone — which would invent a
        -- parts bill out of nothing).
        local LADDER_SOURCES = { ["ladder"] = true, ["planet"] = true, ["pack-rung"] = true, ["replicator"] = true }
        -- Every generated recipe contributes to OTHER recipes' parts bills with
        -- its model time + machine R (raws and fuels included: 1 iron ore = 3 s
        -- at R = 1 is exactly what a parts bill must count). FLUIDS are marked
        -- and contribute NOTHING: a vanilla recycler returns items only, never
        -- a fluid, and pricing 100 water at 8 MJ would put a 800 MJ "parts
        -- bill" on concrete (it did, before this guard).
        -- R must come from the recipe's ACTUAL category: a fuel-class recipe
        -- is category dmrsa-replication-1 even when the item itself is tagged
        -- Gleba (yumako/jellynut), so its R is 1.0 and not the planet's 13.33.
        repl_cost[name] = {
            t = repl_time,
            r = fuel_class and TimingModel.FUEL_CLASS_R or TimingModel.machine_r(tier, planet_suffix),
            fluid = (target.type == "fluid") or nil,
            fuel = fuel_class or nil,
            amount = result_amount,
        }
        if not fuel_class and LADDER_SOURCES[resolved.source] then
            repl_entries[name] = {
                recipe_name = recipe_name,
                model_time = repl_time,
                r = TimingModel.machine_r(tier, planet_suffix),
            }
        end
        repl_time = math.max(TimingModel.MIN_TIME, tonumber(string.format("%.2f", repl_time)))

        local repl_recipe = {
            type = "recipe",
            name = recipe_name,
            localised_name = {
                "recipe-name.dmrsa-replication-recipe",
                { loc_prefix .. "." .. name }
            },
            energy_required = repl_time,
            ingredients = {},
            results = {
                { type = target.type == "fluid" and "fluid" or "item", name = name, amount = result_amount }
            },
            enabled = false,
            hidden = false,
            subgroup = recipe_subgroup,
            order = "z[" .. name .. "]"
        }
        -- Factorio 2.1: categories array (no dual-compat in v4.0)
        -- v4.4.0 (F-5b): the fuel class is FORCED onto dmrsa-replication-1.
        local category = MirrorGenerator.category_for({
            fuel = fuel_class,
            planet_suffix = planet_suffix,
            tier = tier,
        })
        repl_recipe.categories = { category }

        -- v4.4.0 (F-2a/F-5b): burnable solids are the ONE deliberate exception
        -- to the mod's "no productivity on replication" rule. They carry
        -- allow_productivity so the duplication research
        -- (change-recipe-productivity, tiers 3/4/5) can apply: the burn-value
        -- rule prices them at a 5x loss at L0 and the research walks them to
        -- 2.5x/1.25x/0.25x loss (1x/2x/3x/4x output).
        if fuel_class then
            repl_recipe.allow_productivity = true
            fuel_recipe_names[#fuel_recipe_names + 1] = recipe_name
        end

        -- v4.1.0 (Quality Refiner): by default the replicator is faithful — it
        -- replicates matter AS IT KNOWS IT (normal quality). Quality output on
        -- the replicator itself is opt-in via dmrsa-replicator-quality
        -- (permissive mode); the dedicated Quality Refiner is the DMR path to
        -- quality. Fluids have no quality, so the field never applies to them.
        -- L1 (review r1): `recipe.quality` is IGNORED by the engine when the
        -- result has no quality axis in an item registry — the space-platform
        -- starter pack is one of those (its prototype lives in its own
        -- registry), and the flag produced a data-stage warning. Skip the stamp
        -- for it instead of shipping a no-op field.
        local q_allow = helpers.get_startup_setting("dmrsa-replicator-quality", "Normal only")
        if q_allow ~= "Allow quality" and target.type ~= "fluid"
           and target.type ~= "space-platform-starter-pack" then
            repl_recipe.quality = "normal"
        end

        -- v4.2.2 (PR-1 + D17): space-family materials replicate in orbit only.
        -- v4.2.2 (PR-1 + D17 + PR-2): space family replicates in orbit only
        -- (single source: SPACE_FAMILY = chunks + promethium pack).
        if SPACE_FAMILY[name] then
            repl_recipe.surface_conditions = { { property = "gravity", max = 0 } }
        end

        local category_key = category
        if not data.raw["recipe-category"][category_key] then
            helpers.warn("Mirror: skipping '" .. name .. "': crafting category '" .. category_key .. "' not found.")
            goto continue_item
        end

        data:extend({ repl_recipe })
        recipe_count = recipe_count + 1

        -- Register for mirror/baseline/planetary
        if planet_suffix then
            table.insert(planetary_unlocks[planet_suffix], recipe_name)
        else
            items[name] = {
                recipe_name = recipe_name,
                tier = tier,
                target = target,
                item_category = item_category,
            }
        end

        ::continue_item::
    end
    -- v4.4.0 (F-2a): the fuel class, in one line. The SHIPPED count and the
    -- exclusion report are printed AFTER the C5 clamp + the A7 second pass
    -- (section 3b), because the clamp can still change what ships.
    helpers.info("Mirror: fuel class = " .. #fuel_recipe_names ..
        " burnable replication recipes (category " .. MirrorGenerator.category_for({ fuel = true }) .. ").")

    -- ══ 5. C5 (F-4a) — replicate-and-recycle arbitrage clamp (post-pass) ══
    -- Recycling returns 25 % of a recipe's parts, so replicating the item
    -- itself must cost at least what the recycler would give back — a quarter
    -- of its own parts bill (t >= parts/(4R)); at that price the loop returns
    -- 1.00x and the recycler is not a materials printer (nuclear-reactor
    -- printed 148x its own cost at 36.9 s).  The CEILING is 4x the bill
    -- (41 items sat at 0.086x = dead content).  The bill is measured in the
    -- mirror's OWN terms:
    --   parts_mj = MIN over the item's producing recipes of
    --              SUM over that recipe's ingredients of
    --              amount * (ingredient replication time * ingredient R)
    -- — the same numbers the audit measured (nuclear-reactor = 68 572 MJ).
    -- MIN and not "the simplest recipe": several recipes can produce the same
    -- item (concrete vs. concrete-from-molten-iron) and the arbitrage
    -- question is literally "is there a cheaper way to make this from
    -- replicated parts?". It also keeps the choice deterministic (the recipe
    -- index used to depend on pairs() order) and keeps metal-casting/lava
    -- byproduct recipes from inventing a parts bill.
    -- An ingredient that is not a replication target contributes the cost
    -- solver's dark-matter cost instead (no stored time to use).
    -- A6 addition: the bill is the MAX of (a) the MIN producing-recipe bill
    -- above and (b) 4x the observed `<item>-recycling` yield, because the
    -- engine's recycling recipe is what the recycler actually returns — the
    -- cheapest producing recipe need not be the one it mirrors (LDS: metal
    -- casting bills ~0, the recycler hands back steel/copper/plastic). Items
    -- whose only production is raw/pump pricing enter this pass when their
    -- recycling recipe returns PARTS (scrap), because the loop is real even
    -- when the price is a mining price; self-recycling raws do not.
    -- The FUEL CLASS is exempt: fuels are consumed, not recycled, and its
    -- burn-value ladder must not be re-priced by a parts bill.
    -- ORDER (v4.4.0 A6): the bill MUST be priced with the FINAL (post-floor)
    -- cost of every part, so the clamp is solved as a FIXED POINT in
    -- dependency order (TimingModel.arbitrage_fixpoint). One pass over the
    -- pre-clamp list was NOT a fixed point: an ingredient that was itself
    -- floored still entered the bill at its MODEL time, so the recycler kept
    -- the difference — dump-measured residuals rail-support 5.26x,
    -- space-platform-starter-pack 1.29x, assembling-machine-3 1.15x,
    -- cargo-bay 1.09x (any factor > 1.0 is an infinite-materials loop).
    -- A dependency-ordered pass is exact in ONE pass: every ingredient that is
    -- itself a target is already final when its dependent is priced. There is
    -- no iteration and therefore no compounding feedback — the 1e7 s
    -- fusion-reactor blow-up came from iterating a CYCLIC graph, not from
    -- ordering. Cycles are cut at the nominal price and REPORTED: the current
    -- modlist has 11 (asteroid-chunk reprocessing, uranium-235/238 Kovarex,
    -- iron/copper bacteria), all self- or mutually-referential recipes.
    -- NOTE: this clamp runs AFTER the per-difficulty safety cap and outranks
    -- it — capping the parts bill back down would re-open the arbitrage.
    local arbitrage_floor, arbitrage_ceil, arbitrage_total = 0, 0, 0

    -- Price of ONE unit of an ingredient, in MJ, for the parts bill.
    -- (a) a replication target: its own replication cost (time * R / amount);
    -- (b) a DMR intermediate that is NOT a replication target (the scoop /
    --     transducer / conduit line): the mod's own crafting recipe, priced
    --     recursively with the same rule. Without this branch those
    --     ingredients fell to `CostSolver.solve_cost().dark_matter` — a count of
    --     DARK MATTER UNITS, not MJ (review r1 L5) — so a replicator's bill
    --     ignored the one ingredient that makes it expensive, and the H2 floor
    --     could not bite. Depth-capped so a malformed cycle cannot recurse.
    -- (c) anything else: the solver's dark-matter cost (unchanged behaviour).
    local BILL_DEPTH = 3
    -- `price` is the fixpoint's reader: it returns the FINAL per-unit MJ of a
    -- target that has already been processed, and nil for anything else.
    local function ingredient_mj(iname, depth, price)
        local known = repl_cost[iname]
        if known then
            if known.fluid then return 0 end           -- recyclers return items only
            local final = price and price(iname)
            if final then return final end             -- the post-floor price (A6)
            return (known.t * known.r) / (known.amount or 1)   -- raws/fuels: never clamped
        end
        depth = depth or 0
        if depth < BILL_DEPTH and string.find(iname, "^dmrsa%-") then
            local lists = {}
            for _, rname in ipairs(producers_of[iname] or {}) do
                local recipe = data.raw.recipe[rname]
                local ings = recipe
                    and (recipe.ingredients or (recipe.normal and recipe.normal.ingredients))
                if ings and #ings > 0 then
                    local list = {}
                    for _, ing in ipairs(ings) do
                        local n = ing.name or ing[1]
                        if n then list[#list + 1] = { n, ing.amount or 1 } end
                    end
                    lists[#lists + 1] = list
                end
            end
            local sub = TimingModel.parts_bill_mj(lists, function(n)
                return ingredient_mj(n, depth + 1, price)
            end)
            if sub then return sub end
        end
        local solved = CostSolver.solve_cost(iname)
        return solved and solved.dark_matter or nil
    end

    -- Candidate producing recipes of an item, as ingredient lists for
    -- parts_bill_mj (same class as the recipe index: -recycling/-unbarrel and
    -- DMR's own generated recipes never enter producers_of).
    local function recipe_ingredient_lists(item_name)
        local lists = {}
        for _, rname in ipairs(producers_of[item_name] or {}) do
            local recipe = data.raw.recipe[rname]
            local ings = recipe
                and (recipe.ingredients or (recipe.normal and recipe.normal.ingredients))
            if ings and #ings > 0 then
                local list = {}
                for _, ing in ipairs(ings) do
                    local iname = ing.name or ing[1]
                    if iname then list[#list + 1] = { iname, ing.amount or 1 } end
                end
                lists[#lists + 1] = list
            end
        end
        return lists
    end

    -- Fixpoint inputs: every non-fuel ladder-priced target, with the FINAL
    -- price its dependents must use.
    local fix_entries = {}
    local fix_deps = {}
    for name, entry in pairs(repl_entries) do
        fix_entries[name] = {
            model_time = entry.model_time,
            r = entry.r,
            amount = (repl_cost[name] and repl_cost[name].amount) or 1,
        }
        fix_deps[name] = {}
    end
    -- Edge: target -> target, through a recipe's ingredients. DMR
    -- intermediates that are NOT targets (scoop / transducer / conduit) are
    -- transparent: ingredient_mj() prices them from their own crafting recipe,
    -- so their target ingredients are dependencies too (same depth cap).
    local function collect_deps(item_name, depth, seen, out)
        for _, list in ipairs(recipe_ingredient_lists(item_name)) do
            for _, ing in ipairs(list) do
                local iname = ing[1]
                if fix_entries[iname] then
                    out[iname] = true
                elseif depth < BILL_DEPTH and string.find(iname, "^dmrsa%-")
                       and not seen[iname] then
                    seen[iname] = true
                    collect_deps(iname, depth + 1, seen, out)
                end
            end
        end
        -- the recycler's own results are ingredients of the bill too (scrap,
        -- and any item whose price comes from what its recycler hands back)
        local rec = data.raw.recipe[item_name .. "-recycling"]
        local rres = rec and (rec.results or (rec.normal and rec.normal.results))
        if rres then
            for _, r in ipairs(rres) do
                local rn = r.name or r[1]
                if rn and rn ~= item_name and fix_entries[rn] then out[rn] = true end
            end
        end
    end
    for name in pairs(fix_entries) do
        collect_deps(name, 0, { [name] = true }, fix_deps[name])
    end

    -- Raw and pump-priced targets are normally OUTSIDE this clamp (their price
    -- is a mining price, not a craft). One exception is honest: when the item
    -- has a hand-authored recycling recipe that returns PARTS rather than
    -- itself, the recycler loop exists regardless of how the item was priced.
    -- scrap is the archetype — 3 s of replication, then a random Fulgora
    -- component worth ~2x the craft. Self-recycling raws (every ore, stone,
    -- coal, jelly) are excluded: their yield is 0.25 of themselves = no loop.
    -- Fuels stay excluded (F-2a: a parts bill must never re-price a burnable).
    for name, known in pairs(repl_cost) do
        if not fix_entries[name] and not known.fluid and not known.fuel then
            local rec = data.raw.recipe[name .. "-recycling"]
            local res = rec and (rec.results or (rec.normal and rec.normal.results))
            if res then
                local non_self = false
                for _, r in ipairs(res) do
                    local rn = r.name or r[1]
                    if rn and rn ~= name then non_self = true end
                end
                if non_self then
                    fix_entries[name] = {
                        model_time = known.t, r = known.r, amount = known.amount or 1,
                    }
                    fix_deps[name] = {}
                    collect_deps(name, 0, { [name] = true }, fix_deps[name])
                end
            end
        end
    end

    local fix_results, fix_report = TimingModel.arbitrage_fixpoint(
        fix_entries, fix_deps,
        function(name, price)
            -- The bill must cover what the recycler actually returns. When the
            -- engine's auto-generated `<item>-recycling` recipe is already in
            -- data.raw (it is: base generates them before data-final-fixes),
            -- its results ARE the 25 % yield, so price them directly. This is
            -- what fixes low-density-structure (1.33x): its cheapest producing
            -- recipe is a fluid casting recipe (molten metal bills ~0), while
            -- the recycler mirrors the steel/copper/plastic recipe. The
            -- min-over-producers bill stays as the lower bound (it also keeps
            -- self-recycle items priced, where the yield is 0.25 of itself).
            local producing = TimingModel.parts_bill_mj(recipe_ingredient_lists(name),
                function(iname) return ingredient_mj(iname, 0, price) end)
            local rec = data.raw.recipe[name .. "-recycling"]
            local recycled
            if rec then
                local res = rec.results or (rec.normal and rec.normal.results)
                if res and #res > 0 then
                    local sum = 0
                    for _, r in ipairs(res) do
                        local rn = r.name or r[1]
                        local amt = r.amount or 1
                        -- Probability semantics (same as the engine):
                        --   shared_probability      mutually exclusive slots
                        --                           (scrap: one component per
                        --                           recycle, NOT twelve)
                        --   independent_probability each result rolls alone
                        --   extra_count_fraction    fractional extra amount
                        local sp = r.shared_probability
                        if sp then
                            amt = amt * ((sp.max or 0) - (sp.min or 0))
                        elseif r.independent_probability then
                            amt = amt * r.independent_probability
                        end
                        if r.extra_count_fraction then amt = amt + r.extra_count_fraction end
                        local c = rn and ingredient_mj(rn, 0, price)
                        if c then sum = sum + amt * c end
                    end
                    if sum > 0 then recycled = sum end
                end
            end
            if recycled and (not producing or 4 * recycled > producing) then
                -- `recycled` is the 25 % yield; the clamp wants the bill those
                -- parts came from, i.e. 4x the observed yield.
                return 4 * recycled
            end
            return producing
        end)

    local worst_ratio, worst_name = 0, nil
    for _, name in ipairs(fix_report.order) do
        local entry = repl_entries[name]
        local res = fix_results[name]
        if res.action then
            -- raw-priced entries added for a recycler loop are not in
            -- repl_entries; their recipe name is still the mirror's pattern.
            local recipe = data.raw.recipe[(entry and entry.recipe_name) or (gprefix .. "repl-" .. name)]
            if recipe then recipe.energy_required = res.time end
            if res.action == "floor" then arbitrage_floor = arbitrage_floor + 1
            else arbitrage_ceil = arbitrage_ceil + 1 end
            helpers.debug(string.format(
                "Mirror: C5 %s '%s': %.2f s -> %.2f s (parts bill %.1f MJ, R %.4f, parts/repl %.3f)",
                res.action, name, res.model_time, res.time, res.bill or 0, res.r, res.ratio or 0))
        end
        -- dependents read repl_cost; keep it in sync with what shipped
        if repl_cost[name] then repl_cost[name].t = res.time end
        if res.bill and res.time > 0 and res.r > 0 then
            local rr = res.bill / (4 * res.time * res.r)   -- recycler's return / craft cost
            if rr > worst_ratio then worst_ratio, worst_name = rr, name end
        end
    end
    arbitrage_total = fix_report.total

    helpers.info("Mirror: C5 arbitrage fixpoint (dependency order) — " .. arbitrage_floor ..
        " recipe(s) raised to the recycle break-even (parts/4R), " .. arbitrage_ceil ..
        " reduced to the 4x-parts ceiling (" .. (arbitrage_floor + arbitrage_ceil) ..
        " of " .. arbitrage_total .. " non-fuel recipes touched; " ..
        #fix_report.cycles .. " cycle(s) cut at nominal price).")
    helpers.info(string.format(
        "Mirror: C5 max recycle ratio after the fixpoint = %.4fx (%s)",
        worst_ratio, tostring(worst_name)))
    if #fix_report.cycles > 0 then
        local list = {}
        for _, c in ipairs(fix_report.cycles) do
            list[#list + 1] = tostring(c.from) .. "->" .. tostring(c.to)
        end
        helpers.info("Mirror: C5 dependency cycle(s) (approximated at the nominal price): " ..
            table.concat(list, ", "))
    end

    -- 3b. v4.4.0 (A7) — the ceiling, SECOND pass, on the POST-CLAMP time.
    -- The C5 fixpoint is what actually ships a recipe's final time, and its
    -- FLOOR can LIFT a cheap item far above 3600 s: a replicator's parts bill
    -- is its own cost, so the floor lifted dmrsa-replicator-1..5 to
    -- 3695..15612 s and nuclear-reactor / rocket-silo / railgun-turret /
    -- fusion-reactor / fusion-generator to 4797..14902 s (dump-measured).
    -- Those are NOT replication targets under A7, so their recipes are removed
    -- here (the techs that unlocked them are built AFTER this point, from
    -- `items` / `planetary_unlocks`, so a tech whose only effect was one of
    -- these comes out empty and the M1 guard below drops it — no orphan techs).
    -- Same predicate, same log line: nothing here is a second mechanism.
    do
        local removed = 0
        local function drop(name, time, reason)
            local rn = gprefix .. "repl-" .. name
            record_exclusion(name, time, reason)
            data.raw.recipe[rn] = nil
            items[name] = nil
            repl_cost[name] = nil
            repl_entries[name] = nil
            for _, list in pairs(planetary_unlocks) do
                for i = #list, 1, -1 do
                    if list[i] == rn then table.remove(list, i) end
                end
            end
            recipe_count = recipe_count - 1
            removed = removed + 1
        end
        -- non-planetary targets (keyed by item name in `items`)
        local names = {}
        for name in pairs(items) do names[#names + 1] = name end
        for _, name in ipairs(names) do
            local recipe = data.raw.recipe[gprefix .. "repl-" .. name]
            if recipe then
                local reason = MirrorGenerator.replication_exclusion(name, recipe.energy_required)
                if reason then drop(name, recipe.energy_required, reason) end
            end
        end
        -- planetary targets live ONLY in their planet's unlock list
        local repl_prefix_len = #(gprefix .. "repl-")
        for _, list in pairs(planetary_unlocks) do
            for i = #list, 1, -1 do
                local rn = list[i]
                local recipe = data.raw.recipe[rn]
                if recipe then
                    local name = rn:sub(repl_prefix_len + 1)
                    local reason = MirrorGenerator.replication_exclusion(name, recipe.energy_required)
                    if reason then drop(name, recipe.energy_required, reason) end
                end
            end
        end
        if removed > 0 then
            helpers.info("Mirror: A7 ceiling removed " .. removed ..
                " recipe(s) the C5 floor had pushed above " ..
                TimingModel.REPLICATION_CEILING .. " s (second pass).")
        end
    end

    -- ══ A7/F-2a report: the SHIPPED count + every exclusion, one line each ══
    helpers.warn("Mirror: generated " .. recipe_count .. " replication recipes after the A7 ceiling.")
    if #excluded_targets > 0 then
        local names = {}
        for _, e in ipairs(excluded_targets) do
            names[#names + 1] = string.format("%s (%.0f s)", e.name, e.time)
        end
        table.sort(names)
        helpers.warn("Mirror: " .. #excluded_targets ..
            " target(s) left NOT replicable (A7 ceiling / F-2a fuel / own machine): " ..
            table.concat(names, ", "))
    else
        helpers.info("Mirror: no target excluded by the A7 ceiling.")
    end

    -- 4. Build reverse map: original tech -> [replicable items]
    -- Walk every technology's unlock-recipe effects. An item is keyed by its
    -- original recipe name (== item name for item/fluid results).
    local tech_items = {}  -- tech_name -> { [item] = entry }
    for tech_name, tech in pairs(data.raw.technology) do
        -- v4.2.2 (batch-3 audit): exclude DMR's own techs. dmrsa-replication-N
        -- (the replicator machines' own techs) held the replicator items, and
        -- normalize_tech_base() collapsed replication-1/2/4/5 into ONE
        -- "dmrsa-replication" mirror at tier 5, while the planet techs (which
        -- also unlock dmrsa-replicator-3) hijacked it behind Vulcanus. With
        -- the filter the replicators fall to the baseline materials techs at
        -- their OWN tier (REPLICATOR_TIER: 1→1 ... 5→5) — the faithful
        -- progression the v4.2 balance doc describes.
        if (not tech.hidden) and (not string.find(tech_name, "dmrsa%-")) then
            for _, eff in ipairs(tech.effects or {}) do
                if eff.type == "unlock-recipe" and eff.recipe then
                    local entry = items[eff.recipe]
                    if entry then
                        tech_items[tech_name] = tech_items[tech_name] or {}
                        tech_items[tech_name][eff.recipe] = entry
                    end
                end
            end
        end
    end

    -- 4b. v4.2: process-output tech mapping — items that are OUTPUTS of a
    -- same-mod processing recipe inherit that recipe's unlocking tech.
    -- Root cause fix (dump 4.1.0, Angel's full + planetaris): overhaul mods
    -- do NOT unlock a recipe named after every output (angels-gas-hydrogen is
    -- a co-output of angels-water-separation, unlocked by
    -- angels-basic-chemistry). The old 1:1 item↔recipe-name assumption made
    -- all such outputs fall to the baseline (materials-N), flooding
    -- replication-materials-1 with 108 items (dump-verified).
    -- Guards: (a) producing recipe must share the item's mod prefix —
    -- cross-mod byproducts can't attach foreign techs; (b) minable resources
    -- never inherit (they are mined, not crafted); (c) recycling/barreling
    -- recipes excluded (same class as build_recipe_map).
    local recipe_unlocks = {}   -- recipe name -> visible tech names
    for tech_name, tech in pairs(data.raw.technology) do
        if (not tech.hidden) and (not string.find(tech_name, "dmrsa%-")) then
            for _, eff in ipairs(tech.effects or {}) do
                if eff.type == "unlock-recipe" and eff.recipe then
                    recipe_unlocks[eff.recipe] = recipe_unlocks[eff.recipe] or {}
                    table.insert(recipe_unlocks[eff.recipe], tech_name)
                end
            end
        end
    end

    local item_process_techs = {}  -- item -> visible tech names
    for recipe_name, recipe in pairs(data.raw.recipe) do
        if string.find(recipe_name, "dmrsa%-") then goto continue_recipe end
        if recipe_name == "recycling" or string.find(recipe_name, "%-recycling$") then
            goto continue_recipe
        end
        if string.find(recipe_name, "empty%-") or string.find(recipe_name, "%-unbarrel") then
            goto continue_recipe
        end

        local results = recipe.results
        if recipe.normal and recipe.normal.results then
            results = recipe.normal.results
        end
        if not results then goto continue_recipe end

        local unlocks = recipe_unlocks[recipe_name]
        if not unlocks or #unlocks == 0 then goto continue_recipe end

        for _, res in ipairs(results) do
            local res_name = res.name or res[1]
            if res_name and items[res_name] and not is_minable_resource(res_name) then
                if same_mod_prefix(res_name, recipe_name) then
                    local tlist = item_process_techs[res_name]
                    if not tlist then
                        tlist = {}
                        item_process_techs[res_name] = tlist
                    end
                    for _, tn in ipairs(unlocks) do
                        local already = false
                        for _, e in ipairs(tlist) do if e == tn then already = true break end end
                        if not already then table.insert(tlist, tn) end
                    end
                end
            end
        end
        ::continue_recipe::
    end

    -- 5. Assign every item to its BEST original tech (highest science level)
    -- Items with no original tech fall to the baseline (materials techs).
    --
    -- v4.0: techs ending in "-N" (e.g. angels-chlorine-processing-1..4) are
    -- treated by Factorio as LEVELS of a single base technology. Generating
    -- one mirror per level makes Factorio group them as one composite tech
    -- whose levels must be CONTIGUOUS — if a middle level (say -3) unlocks no
    -- replicable items, its mirror is skipped and the chain breaks with
    -- "Non-contiguous levels: 2, followed by 4". Fix: normalize every
    -- "-<digits>" suffix to its base name, so the whole chain maps to ONE
    -- mirror tech (prereq = deepest existing level).
    local function normalize_tech_base(name)
        return string.gsub(name, "%-%d+$", "")
    end

    -- v4.2 (dump audit 2026-08-22): manual tech routing for items whose
    -- unlock graph is warped by mod re-gates in this modlist:
    --   * TECH_REDIRECT[item] = original tech whose MIRROR gates this item
    --     (an item may be homonym-unlocked by a wrong tech after Angel's/
    --     planetaris re-gate them; forcing the mirror keeps progression sane).
    --   * BASELINE_FORCE[item] = skip mirror entirely; the item falls to the
    --     materials baseline at its cost-solver tier.
    -- Dump evidence:
    --   carbon      → homonym unlock re-gated under tungsten-carbide (vulcanus);
    --                 carbon is a space/asteroid/planetaris material.
    --   spaceship-scrap → was caught by the fulgora "scrap" matcher; space item.
    --   burner-pumpjack → only unlockable via cryovolcanic-power (aquilo L5) in
    --                 this modlist; an early oil pumpjack gated to the endgame.
    local TECH_REDIRECT = {
        ["carbon"] = "space-platform",
        ["spaceship-scrap"] = "space-platform",
        -- v4.2.2 (batch-3 audit): same-pattern siblings found by the A1/A5
        -- agents. Each entry is dump-proven (see CONSOLIDADO-BATCH3.md):
        --  * solid-fuel: 8 producers (flammables SCL1, aquilo re-gate...) —
        --    max-SCL winner picked planet-discovery-aquilo (T5 gate for a
        --    T1 fuel). Its own vanilla tech `flammables` exists (SCL 1).
        --  * lubricant / sulfur: vanilla recipes are HIDDEN with no visible
        --    unlock; the process-output fallback crossed mod_prefix("")=="" 
        --    with Bio Ind's biosulfur/biolubricant (gleba T5). Real vanilla
        --    techs exist (SCL 1): sulfur-processing / lubricant.
        --  * auric-asteroid-chunk: endgame material swallowed by steam-
        --    recycler (Secretas, unit=nil) — belongs to the space family
        --    (promethium model).
        --  (gold-plate stays with steam-recycler: it is its ONLY visible
        --  unlock in this modlist, and it already sits coherently at T4.)
        ["solid-fuel"] = "flammables",
        ["lubricant"] = "lubricant",
        ["sulfur"] = "sulfur-processing",
        ["auric-asteroid-chunk"] = "space-platform",
    }
    local BASELINE_FORCE = {
        ["burner-pumpjack"] = true,
    }

    -- v4.2 (B1, opción C del usuario): split LEVELED tech chains into one
    -- mirror PER LEVEL instead of collapsing them to the base. Dump-verified:
    -- every level of these chains has ≥1 replicable item (no hollow levels),
    -- so the mirror chain stays contiguous (base=1, -N=N ... automation (1),
    -- automation-2 (2), ...). 7 chains total (bob-oil-processing does not
    -- exist in this modlist; angels-oil-processing/bob-electronics have no
    -- levels — nothing to split there).
    local SPREAD_TECHS = {
        automation = true,
        logistics = true,
        ["logistic-system"] = true,
        ["bob-robo-modular"] = true,
        ["angels-metallurgy"] = true,
        ["angels-advanced-chemistry"] = true,
        ["angels-nitrogen-processing"] = true,
    }

    -- v4.2.2 (H1, decisión del usuario 2026-09-04): SPREAD REDUCIDO por nivel.
    -- 125 chains collapse to ONE mirror at the deepest level's tier — 278
    -- items gated ABOVE their own tier (dump: Angel's early bio at replication-5,
    -- Bob's poles/robots/modules at t5). Full per-level spread (~345 mirrors)
    -- would also split chains whose items already sit at the deepest tier's
    -- tier (zero gameplay change, tree noise). Reduced rule (dump-validated,
    -- 33 chains / 224 items / +117 mirrors):
    --   1. chain has a PLAIN level-1 tech (contiguity: "Non-contiguous levels"
    --      crash if level-1 mirror is missing — pitfall #4);
    --   2. every level owns >=1 replicable item (attributed via the chain's own
    --      level techs unlocking the item's producing recipes; unattributed
    --      items go to the deepest level);
    --   3. deepest level >= 3 (levels 1-2 chains carry no real tier gap);
    --   4. item-tier span >= 2 (no real damage, no split).
    local chain_levels = {}   -- base -> { [level_num] = tech_name }
    do
        for tname, tech in pairs(data.raw.technology) do
            if (not tech.hidden) and (not string.find(tname, "dmrsa%-")) then
                local base_name, lvl = string.match(tname, "^(.+)%-(%d+)$")
                if base_name and lvl then
                    chain_levels[base_name] = chain_levels[base_name] or {}
                    chain_levels[base_name][tonumber(lvl)] = tname
                end
            end
        end
        -- plain base tech = level 1 when no "-1" exists (vanilla/Bob's style)
        for base_name, levels in pairs(chain_levels) do
            if not levels[1] and data.raw.technology[base_name]
               and (not data.raw.technology[base_name].hidden) then
                levels[1] = base_name
            end
        end
    end

    -- item -> chain level (min level of the chain's techs that unlock one of
    -- the item's producing recipes; nil if the chain doesn't unlock it)
    -- Built from the recipe_unlocks map (visible techs) + the producers_of
    -- index (built above, before the target loop).
    -- NOTE: this includes tier-gated/production recipes the item_process_techs
    -- fallback filters out — attribution only feeds the eligibility decision;
    -- the mirror grouping itself stays keyed by each level's tech name.
    local function item_chain_level(base_name, item)
        local best
        local prods = producers_of[item] or {}
        for _, rname in ipairs(prods) do
            local unlockers = recipe_unlocks[rname]
            if unlockers then
                for _, tn in ipairs(unlockers) do
                    if tn == base_name then
                        if not best or 1 < best then best = 1 end
                    else
                        local lvl = string.match(tn, "^" .. base_name .. "%-(%d+)$")
                        if lvl then
                            lvl = tonumber(lvl)
                            if not best or lvl < best then best = lvl end
                        end
                    end
                end
            end
        end
        return best
    end

    -- v4.2.2 (H1): reduced dynamic spread — pre-compute per-level mirror
    -- assignment for ELIGIBLE chains only. Members come from tech_items
    -- (the reverse map built above): an item reaches base B exactly when one
    -- of B's level techs unlocks it, so the union over level techs is the
    -- chain's full item set. Eligibility (all dump-validated — 33 chains):
    --   plain level-1 tech exists, levels contiguous (Factorio rejects
    --   "Non-contiguous levels" — pitfall #4), deepest >= 3, every level
    --   owns >=1 item, and the chain's item tiers span >= 2.
    local spread_assign = {}  -- spread_assign[base][item] = level tech name
    -- v4.2.2 (H1): level techs that got a per-level mirror.
    -- DECLARED HERE ON PURPOSE (v4.3.0): it used to be declared AFTER the
    -- do-block below, so the writer inside resolved to a NIL GLOBAL and the
    -- whole mod failed to load ("attempt to index global 'h1_spread_techs'")
    -- on any modlist where a chain qualifies for the reduced spread. Found by
    -- the headless load test with base + Space Age only — the unit suite never
    -- hit it because it does not run the real data stage.
    local h1_spread_techs = {}
    do
        local chain_members = {}  -- base -> { [item] = true }
        for tech_name, its in pairs(tech_items) do
            local b, lvl = string.match(tech_name, "^(.+)%-(%d+)$")
            lvl = lvl and tonumber(lvl) or nil
            local is_level = b and chain_levels[b] and chain_levels[b][lvl] == tech_name
            if not is_level and chain_levels[tech_name] and chain_levels[tech_name][1] == tech_name then
                b, lvl = tech_name, 1  -- plain base tech acting as level 1
                is_level = true
            end
            if is_level and lvl then
                local m = chain_members[b]
                if not m then m = {}; chain_members[b] = m end
                for item in pairs(its) do m[item] = true end
            end
        end
        for base, members in pairs(chain_members) do
            local levels = chain_levels[base]
            if levels and not SPREAD_TECHS[base] then
                local deepest, n_levels = 0, 0
                for n in pairs(levels) do
                    n_levels = n_levels + 1
                    if n > deepest then deepest = n end
                end
                if deepest >= 3 and levels[1] and n_levels == deepest then
                    local by_level = {}
                    local min_t, max_t
                    local ok = true
                    for item in pairs(members) do
                        local entry = items[item]
                        local lvl = item_chain_level(base, item) or deepest
                        local bucket = by_level[lvl]
                        if not bucket then bucket = {}; by_level[lvl] = bucket end
                        table.insert(bucket, item)
                        local t = entry and entry.tier or nil
                        if t then
                            if not min_t or t < min_t then min_t = t end
                            if not max_t or t > max_t then max_t = t end
                        end
                    end
                    for n in pairs(levels) do
                        local bucket = by_level[n]
                        if not bucket or #bucket == 0 then ok = false end
                    end
                    if ok and min_t and max_t and (max_t - min_t) >= 2 then
                        local map = {}
                        for lvl, bucket in pairs(by_level) do
                            local tech = levels[lvl]
                            h1_spread_techs[tech] = true
                            for _, item in ipairs(bucket) do
                                map[item] = tech
                            end
                        end
                        spread_assign[base] = map
                    end
                end
            end
        end
        local n_spread = 0
        for _ in pairs(spread_assign) do n_spread = n_spread + 1 end
        helpers.info("Mirror: H1 reduced spread assigned " .. n_spread .. " chains to per-level mirrors.")
    end

    local item_tech = {}       -- item -> best original tech name (normalized)
    local baseline_by_tier = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
    local mirror_groups = {}   -- tech_base -> { [item] = entry }
    local mirror_deepest = {}  -- tech_base -> deepest original tech name (prereq)
    -- (h1_spread_techs is declared above, before the H1 do-block that writes it)

    for item, entry in pairs(items) do
        local techs_for_item = {}
        -- v4.2: dump-audit overrides (see TECH_REDIRECT / BASELINE_FORCE above)
        if BASELINE_FORCE[item] then
            -- forced baseline: leave techs_for_item empty
        elseif TECH_REDIRECT[item] then
            table.insert(techs_for_item, TECH_REDIRECT[item])
        else
            for tech_name in pairs(tech_items) do
                if tech_items[tech_name][item] then
                    table.insert(techs_for_item, tech_name)
                end
            end
            -- v4.2: process-output fallback — items without a recipe named after
            -- them (overhaul-mod gas/liquid/ore outputs) inherit the tech of their
            -- same-mod producing recipe (e.g. angels-gas-hydrogen →
            -- angels-basic-chemistry). This keeps them behind THEIR tech instead
            -- of flooding the baseline materials.
            if #techs_for_item == 0 then
                for _, tn in ipairs(item_process_techs[item] or {}) do
                    table.insert(techs_for_item, tn)
                end
            end
        end
        if #techs_for_item == 0 then
            local t = math.max(1, math.min(5, entry.tier))
            table.insert(baseline_by_tier[t], entry.recipe_name)
        else
            -- v4.2.2 (H1): reduced per-level spread takes precedence — items
            -- of eligible chains go to THEIR level's tech (its own mirror),
            -- instead of collapsing into the base mirror at the deepest
            -- level's tier (278 items gated above their own tier in the dump).
            -- Membership routing: if the item is in an eligible chain's map,
            -- it ALWAYS routes to map[item] — matching by per-tech iteration
            -- could divert an item to the best-tech fallback and leave its
            -- level mirror EMPTY → "Non-contiguous levels" crash (pitfall #4).
            -- The map was built with every level owning >=1 item, so routing
            -- all members keeps base + every level mirror non-empty.
            local spread_tech = nil
            for _, tech_name in ipairs(techs_for_item) do
                local b = string.match(tech_name, "^(.+)%-(%d+)$")
                local map = b and spread_assign[b] or nil
                if not map then
                    map = spread_assign[tech_name]
                end
                if map and map[item] then
                    spread_tech = map[item]
                    break
                end
            end
            if spread_tech then
                item_tech[item] = spread_tech
                mirror_groups[spread_tech] = mirror_groups[spread_tech] or {}
                mirror_groups[spread_tech][item] = entry
                if not mirror_deepest[spread_tech] then
                    mirror_deepest[spread_tech] = spread_tech
                end
                goto item_assigned -- skip the best-tech selection
            end
            -- Best = highest science level; among equal, prefer the DEEPEST
            -- chain level (so the prereq gate is the last one researched).
            local best, best_lvl, best_ord = nil, -1, -1
            for _, tname in ipairs(techs_for_item) do
                local lvl = MirrorGenerator.get_tech_science_level(tname) or 0
                local _, _, num = string.find(tname, "%-(" .. "%d+" .. ")$")
                local ord = num and tonumber(num) or 0
                if lvl > best_lvl or (lvl == best_lvl and ord > best_ord) then
                    best, best_lvl, best_ord = tname, lvl, ord
                end
            end
            if not best then best = techs_for_item[1] end
            local base = normalize_tech_base(best)
            -- v4.2 (B1): spread chains keep their LEVELED mirror (automation-2
            -- gets its own mirror instead of joining "automation").
            if SPREAD_TECHS[base] then base = best end
            item_tech[item] = base
            mirror_groups[base] = mirror_groups[base] or {}
            mirror_groups[base][item] = entry
            -- Track the deepest level as the original-tech prereq
            local cur = mirror_deepest[base]
            if not cur then
                mirror_deepest[base] = best
            else
                local _, _, cur_num = string.find(cur, "%-(" .. "%d+" .. ")$")
                local _, _, new_num = string.find(best, "%-(" .. "%d+" .. ")$")
                local cn = cur_num and tonumber(cur_num) or 0
                local nn = new_num and tonumber(new_num) or 0
                if nn > cn then mirror_deepest[base] = best end
            end
        end
        ::item_assigned::
    end

    -- 6. Generate one mirror tech per original tech (threshold=1)
    local tech_count = 0
    local diff_vals = helpers.get_research_difficulty_values()

    for tech_name, group in pairs(mirror_groups) do
        local item_count = 0
        for _ in pairs(group) do item_count = item_count + 1 end
        if item_count == 0 then goto continue_tech end

        -- v4.0: for "-N" chains (angels-chlorine-processing-1..4) the group key
        -- is the NORMALIZED base name; the real prototype that exists in
        -- data.raw is the deepest level (mirror_deepest). Use it for science
        -- level, tree depth, and the original-tech prerequisite.
        local orig_tech = mirror_deepest[tech_name] or tech_name

        -- v4.2 fix (gate-test dump 2026-08-23): science-pack mirrors are
        -- FORCED to their progression tier (auto/logistic=1, military=2,
        -- chemical/production/utility=3, planetary=4, space/cryo/prom=5).
        -- Exact-table lookup only — no name heuristics on arbitrary items.
        local forced_science_tier
        for item in pairs(group) do
            local lvl = PACK_LEVELS[item] or MOD_PACK_LEVELS[item]
            if lvl and (not forced_science_tier or lvl > forced_science_tier) then
                forced_science_tier = lvl
            end
        end
        -- v4.2 fix (gate-test dump 2026-08-23): science packs FORCED to their
        -- progression tier (auto/logistic=1, military=2, chem/prod/util=3,
        -- planetary=4, space/cryo/prom=5) — the SCL of the tech that unlocks a
        -- pack is NOT the pack's own progression tier (chemical-pack tech
        -- researches with tier-1 packs but the PACK is tier-3 progression).
        if forced_science_tier then
            tier = forced_science_tier
        elseif h1_spread_techs[tech_name] then
            -- v4.2.2 (H1): per-level mirror — same rule as B1 SPREAD chains:
            -- the tier is the ITEMS' cost tier (the replication-N machine
            -- gate), NOT the original tech's science level. Level-N techs
            -- commonly research with deep packs while their items are
            -- mid-game (the whole point of H1).
            local max_t = 1
            for _, entry in pairs(group) do
                if entry.tier and entry.tier > max_t then max_t = entry.tier end
            end
            tier = max_t
        elseif SPREAD_TECHS[normalize_tech_base(tech_name)] then
            -- v4.2 (B1): leveled mirror — tier is governed by the ITEMS' cost
            -- tiers (the replication-N machine gate), NOT the original tech's
            -- science level. Otherwise assembly-machine-6 would unlock behind
            -- replication-1 (free endgame machine).
            local max_t = 1
            for _, entry in pairs(group) do
                if entry.tier and entry.tier > max_t then max_t = entry.tier end
            end
            tier = max_t
        else
            tier = MirrorGenerator.get_tech_science_level(orig_tech)
            if not tier then
                -- fallback: max item tier in the group
                local max_t = 1
                for _, entry in pairs(group) do
                    if entry.tier and entry.tier > max_t then max_t = entry.tier end
                end
                tier = max_t
            end
        end
        -- v4.0: when dmrsa-require-original-tech is ON, the original tech is a
        -- DIRECT prerequisite of this mirror tech. The mirror's tier must be
        -- at least the original tech's REAL depth in the research tree, or
        -- Factorio rejects the tech with "Non-contiguous levels: N, followed
        -- by M" (science-pack level can be shallower than tree depth — e.g.
        -- angel's chlorine-processing maps to tier 2 by packs but sits at
        -- depth 4). Clamp to the tree depth when the original is required.
        -- v4.2 fix (gate-test dump 2026-08-23): tree-depth clamp REMOVED.
        -- It was added in the 4.0 gate test as a belt-and-suspenders against
        -- "Non-contiguous levels", but with real modlists it inflates nearly
        -- every mirror to tier 5 (dump: chemical-science-pack sits at depth
        -- 22, promethium at depth 80 → 458/474 mirrors ended in replication-5,
        -- incl. logistic/chemical/production/utility). The REAL contiguity
        -- hazard was leveled `-N` chains, which normalize_tech_base() already
        -- handles by grouping them into ONE mirror. If Factorio ever rejects
        -- a specific mirror for contiguity, fix THAT chain — not the whole
        -- tree via depth.
        tier = math.max(1, math.min(5, tier))

        local mirror_name = gprefix .. "mirror-" .. tech_name
        local tech_effects = {}
        local rep_item, rep_target = nil, nil
        for item, entry in pairs(group) do
            table.insert(tech_effects, { type = "unlock-recipe", recipe = entry.recipe_name })
            if not rep_item then rep_item, rep_target = item, entry.target end
        end

        -- M1 (review r1): NEVER emit a technology with an empty effect list.
        -- 4.4.0 shipped `dmrsa-mirror-kovarex-enrichment-process` as a tech
        -- whose only effect was `dmrsa-repl-nuclear-fuel`; the fuel escape
        -- hatch (F-2a) removed that recipe, so the tech either vanished from
        -- the tree (silently dropping a researched node) or came back with
        -- `effects = {}` (a research target that unlocks nothing). Skip it here
        -- and say so at data stage; the items of the group — if any survived —
        -- already fell to the baseline tier in the routing pass above.
        if #tech_effects == 0 then
            helpers.info("Mirror: not emitting tech '" .. mirror_name ..
                "': every unlock it had was dropped (empty effect list).")
            goto continue_tech
        end

        -- Prereqs: machine + materials + original tech (if setting ON)
        local prerequisites = {}
        local function add_prereq(tbl, p)
            for _, v in ipairs(tbl) do if v == p then return end end
            table.insert(tbl, p)
        end
        add_prereq(prerequisites, gprefix .. "replication-" .. tier)
        add_prereq(prerequisites, gprefix .. "replication-materials-" .. tier)
        if require_orig then
            if data.raw.technology[orig_tech] then
                add_prereq(prerequisites, orig_tech)
            end
        end

        -- Research packs: DMR material of the tier (+ planetary pack for aquilo T5)
        local research_packs = {}
        add_research_pack(research_packs, { tier_material_pack(tier), 1 }, true)
        if tier == 5 and string.find(orig_tech, "cryogenic") then
            add_research_pack(research_packs, { "cryogenic-science-pack", 1 }, false)
        end
        -- v4.3: with `dmrsa-tenemut-research-required` disabled the material
        -- pack is skipped — fall back to vanilla packs so the mirror tech never
        -- ends up with an empty ingredient list (v4.2 "no cost" bug).
        if #research_packs == 0 then
            add_research_pack(research_packs, { "automation-science-pack", 1 }, false)
            add_research_pack(research_packs, { "logistic-science-pack", 1 }, false)
        end

        local repetitions = 10 * tier
        -- v4.2 refino (original-mod study): SIN ×item_count — el original
        -- cobra research por TECH (tier×25), no por item del grupo. Nuestros
        -- grupos grandes (materials-1 25 items) pagaban 10×tier×25 = 250 reps;
        -- ahora 10×tier fijo (la dificultad sigue en diff_vals.cost/25).
        local reps_count = math.max(1, math.ceil(repetitions * (diff_vals.cost / 25)))
        local tech_time = math.max(1, math.ceil(diff_vals.time * 5))

        local tech_proto = {
            type = "technology",
            name = mirror_name,
            localised_name = {
                "technology-name.dmrsa-mirror-tech",
                { "technology-name." .. orig_tech }
            },
            localised_description = {
                "technology-description.dmrsa-mirror-tech",
                { "technology-name." .. orig_tech }
            },
            effects = tech_effects,
            prerequisites = prerequisites,
            unit = {
                count = reps_count,
                ingredients = research_packs,
                time = tech_time
            },
            order = "a-r-m-" .. tier .. "[" .. tech_name .. "]"
        }

        -- Icon from the representative item
        if rep_item and rep_target then
            tech_proto.icons = get_tech_icons(rep_item, rep_target, tier)
            tech_proto.icon_size = 128
        end

        -- Fail-safe validation
        local tech_valid = true
        for _, pack in ipairs(research_packs) do
            if not helpers.item_exists(pack[1]) then
                helpers.warn("Mirror: skipping tech '" .. mirror_name .. "': pack '" .. pack[1] .. "' not found.")
                tech_valid = false
                break
            end
        end
        if tech_valid then
            for _, prereq in ipairs(prerequisites) do
                if not data.raw.technology[prereq] then
                    helpers.warn("Mirror: skipping tech '" .. mirror_name .. "': prereq '" .. prereq .. "' not found.")
                    tech_valid = false
                    break
                end
            end
        end

        if tech_valid then
            local ok, err = pcall(data.extend, data, { tech_proto })
            if ok then
                tech_count = tech_count + 1
            else
                helpers.error("Mirror: could not create tech '" .. mirror_name .. "': " .. tostring(err))
                -- fallback: baseline unlock
                for item, entry in pairs(group) do
                    local t = math.max(1, math.min(5, tier))
                    table.insert(baseline_by_tier[t], entry.recipe_name)
                end
            end
        else
            -- fallback: baseline unlock
            for item, entry in pairs(group) do
                local t = math.max(1, math.min(5, tier))
                table.insert(baseline_by_tier[t], entry.recipe_name)
            end
        end

        ::continue_tech::
    end

    helpers.info("Mirror: generated " .. tech_count .. " mirror technologies.")

    -- 7. Attach baseline recipes to the materials techs (one per tier)
    -- The materials techs are defined in technologies.lua with empty effects;
    -- here we fill them with the baseline unlocks.
    local baseline_count = 0
    for tier = 1, 5 do
        local tech = data.raw.technology[gprefix .. "replication-materials-" .. tier]
        local unlocks = baseline_by_tier[tier]
        if tech and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                local already = false
                for _, eff in ipairs(tech.effects) do
                    if eff.recipe == recipe_name then already = true; break end
                end
                if not already then
                    table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
                    baseline_count = baseline_count + 1
                end
            end
        elseif not tech then
            helpers.warn("Mirror: materials tech '" .. gprefix .. "replication-materials-" .. tier .. "' not found!")
        end
    end
    helpers.info("Mirror: attached " .. baseline_count .. " baseline recipes to materials techs.")

    -- 8. v4.4.0 (Part A): duplication research effects.
    -- The three techs (dmrsa-duplication-3/4/5, declared in technologies.lua
    -- with empty effects) receive change-recipe-productivity for every
    -- chemical-fuel replication recipe generated above, plus the collider's
    -- dmrsa-dark-matter recipe when it exists.
    --
    -- v4.4.0 FIX (balance bug): change-recipe-productivity ACCUMULATES across
    -- technologies, so emitting the per-tech deltas (change = tier-2 -> 1/2/3)
    -- summed to +600 % = 7 items per cycle — a 1.75x free printer at L0.
    -- Every tech must add change = 1.0 instead, so the CUMULATIVE bonus is
    -- +100 % (t3) / +200 % (t4) / +300 % (t5) = 2 / 3 / 4 items per cycle
    -- (the intended 3.5x printer at the top tier). Sum = 1.0+1.0+1.0 = 3.0.
    local DUP_CHANGE_PER_TECH = 1.0
    do
        local dm_recipe = data.raw.recipe["dmrsa-dark-matter"]
        local n_fuel = #fuel_recipe_names
        local cumulative = 0
        for _, tier in ipairs({ 3, 4, 5 }) do
            local tech = data.raw.technology[gprefix .. "duplication-" .. tier]
            if tech and (n_fuel > 0 or dm_recipe) then
                tech.effects = tech.effects or {}
                cumulative = cumulative + DUP_CHANGE_PER_TECH
                for _, rname in ipairs(fuel_recipe_names) do
                    table.insert(tech.effects, {
                        type = "change-recipe-productivity",
                        recipe = rname,
                        change = DUP_CHANGE_PER_TECH,
                    })
                end
                if dm_recipe then
                    table.insert(tech.effects, {
                        type = "change-recipe-productivity",
                        recipe = "dmrsa-dark-matter",
                        change = DUP_CHANGE_PER_TECH,
                    })
                end
                helpers.info("Mirror: duplication-" .. tier ..
                    " adds +" .. math.floor(DUP_CHANGE_PER_TECH * 100) .. "% productivity (" ..
                    "cumulative +" .. math.floor(cumulative * 100) .. "% = " ..
                    math.floor(cumulative + 1) .. " items/cycle).")
            end
        end
        helpers.info("Mirror: duplication research scopes " .. n_fuel ..
            " fuel replication recipes" .. (dm_recipe and " + dmrsa-dark-matter" or "") ..
            "; cumulative productivity +" .. math.floor(cumulative * 100) .. "%.")
    end

    -- 8b. v4.4.0 (A7): a materials tech must never ship EMPTY.
    -- `dmrsa-replication-materials-N` is declared empty in technologies.lua and
    -- filled here with the tier's baseline unlocks. The A7 ceiling can empty
    -- one of them: `dmrsa-replicator-4` (an own machine) was the ONLY baseline
    -- item of tier 4, and the vanilla+SA gate has no tech-less tier-4 material.
    -- The tech CANNOT be deleted — Factorio validates name suffixes
    -- ("Technology dmrsa-replication-materials: Non-contiguous levels: 3,
    -- followed by 5") — so it keeps its gate role and unlocks the tier's own
    -- machine recipe (already unlocked by replication-N, and duplicate
    -- unlock-recipe effects are legal), instead of shipping `effects = {}`.
    do
        for tier = 1, 5 do
            local tname = gprefix .. "replication-materials-" .. tier
            local tech = data.raw.technology[tname]
            if tech and #(tech.effects or {}) == 0 then
                local machine_recipe = gprefix .. "replicator-" .. tier
                if data.raw.recipe[machine_recipe] then
                    tech.effects = { { type = "unlock-recipe", recipe = machine_recipe } }
                    helpers.info("Mirror: A7 left '" .. tname ..
                        "' with no baseline item; it now unlocks the tier's machine recipe '" ..
                        machine_recipe .. "' so the research node is never empty.")
                else
                    helpers.warn("Mirror: A7 left '" .. tname ..
                        "' with an EMPTY effect list and has no machine recipe to fall back to.")
                end
            end
        end
    end

    -- 9. M1 (review r1) — final data-stage audit: no DMR technology may ship
    -- with an empty effect list. The mirror guard above prevents the one case
    -- that produced it (a tech whose only unlock was dropped); this catches any
    -- OTHER path (a fix pass emptying a list, a placeholder left unfilled, a
    -- setting that removes every effect). Warn only: deleting a node here would
    -- strand its prerequisites, so the report is loud and the dump is checked.
    do
        local empty = {}
        for tname, tech in pairs(data.raw.technology) do
            if string.find(tname, "^dmrsa%-") and #(tech.effects or {}) == 0 then
                empty[#empty + 1] = tname
            end
        end
        if #empty > 0 then
            table.sort(empty)
            helpers.warn("Mirror: " .. #empty .. " dmrsa technology(ies) have an EMPTY effect list: " ..
                table.concat(empty, ", "))
        else
            helpers.info("Mirror: no dmrsa technology has an empty effect list.")
        end
    end

    return planetary_unlocks
end

return MirrorGenerator
