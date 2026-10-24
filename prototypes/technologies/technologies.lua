local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Setup science pack ingredients helper
local function make_research_unit(count, packs, time)
    local ingredients = {}
    -- v4.3: with `dmrsa-tenemut-research-required = false` every DMR pack
    -- ("dmrsa-" prefix) is dropped from the unit — the vanilla packs the caller
    -- supplied carry the tech instead. Default (true) keeps the old behaviour.
    local dmr_pack_required = helpers.dmr_research_pack_required()
    for _, pack in ipairs(packs) do
        local is_dmr_pack = type(pack) == "string" and string.sub(pack, 1, string.len(gprefix)) == gprefix
        if helpers.item_exists(pack) and (dmr_pack_required or not is_dmr_pack) then
            table.insert(ingredients, { pack, 1 })
        end
    end
    -- Fallback: if all specified packs are missing, use tenemut as a fallback to avoid startup errors
    if #ingredients == 0 then
        if not dmr_pack_required then
            -- v4.3: no DMR pack may be used at all, so the tier-1 vanilla packs
            -- take over. A tech with an EMPTY ingredient list renders as "no
            -- cost" (the v4.2 failure mode) — never leave it empty.
            for _, vanilla in ipairs({ "automation-science-pack", "logistic-science-pack" }) do
                if helpers.item_exists(vanilla) then
                    table.insert(ingredients, { vanilla, 1 })
                end
            end
        elseif helpers.item_exists(gprefix .. "tenemut") then
            table.insert(ingredients, { gprefix .. "tenemut", 1 })
        else
            -- v4.2 (dump 4.1.0): the tier-1 material pack (tenemut) is a TOOL
            -- prototype — if item_exists misses it for ANY reason, don't leave
            -- the tech with an EMPTY ingredient list (it rendered "no cost").
            -- Fall back to any existing DMR material.
            for _, mat in ipairs({ "matter-conduit", "dark-matter-transducer", "dark-matter-scoop" }) do
                if helpers.item_exists(gprefix .. mat) then
                    table.insert(ingredients, { gprefix .. mat, 1 })
                    break
                end
            end
        end
    end
    -- Apply research difficulty multipliers (Medium/High) to ALL static techs
    local diff_mult = helpers.get_research_difficulty_multipliers()
    return {
        count = math.max(1, math.ceil(count * diff_mult.reps_mult)),
        ingredients = ingredients,
        time = math.max(1, math.ceil((time or 30) * diff_mult.time_mult))
    }
end

-- 1. Baseline Science Packs List
local t1_packs = { "automation-science-pack", "logistic-science-pack" }
-- Tier 2: automation + logistic ONLY (no chemical). Progression: chemical is
-- tier 3. t2_packs previously included chemical-science-pack, which made
-- replication-2 (transducer, replicator-2) require chemical before it should.
local t2_packs = { "automation-science-pack", "logistic-science-pack" }

-- Tier 3: chemical is the endpoint of tier 3 (before planets). With SA,
-- production/utility don't exist; the tier 3 tech uses chemical only.
local t3_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }

-- Tier 4: planetary packs (SA) — the planets ARE tier 4.
local t4_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    table.insert(t4_packs, "metallurgic-science-pack")
    table.insert(t4_packs, "electromagnetic-science-pack")
    table.insert(t4_packs, "agricultural-science-pack")
else
    table.insert(t4_packs, "production-science-pack")
end

-- Tier 5: space, cryogenic (SA) or utility/space (non-SA)
local t5_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    table.insert(t5_packs, "space-science-pack")
    table.insert(t5_packs, "cryogenic-science-pack")
else
    table.insert(t5_packs, "utility-science-pack")
    table.insert(t5_packs, "space-science-pack")
end

-- Inject space-science-pack into research requirements for space-locked tiers
local function add_science_pack_if_missing(pack_list, pack_name)
    for _, name in ipairs(pack_list) do
        if name == pack_name then return end
    end
    table.insert(pack_list, pack_name)
end

local space_lock = helpers.get_startup_setting("replresearch-space-lock", 6)
if space_lock <= 1 then add_science_pack_if_missing(t1_packs, "space-science-pack") end
if space_lock <= 2 then add_science_pack_if_missing(t2_packs, "space-science-pack") end
if space_lock <= 3 then add_science_pack_if_missing(t3_packs, "space-science-pack") end
if space_lock <= 4 then add_science_pack_if_missing(t4_packs, "space-science-pack") end
if space_lock <= 5 then add_science_pack_if_missing(t5_packs, "space-science-pack") end

local tech_list = {
    -- Technology Tier 1
    {
        type = "technology",
        name = gprefix .. "replication-1",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-1.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter-scoop" },
            { type = "unlock-recipe", recipe = gprefix .. "replication-lab" },
            { type = "unlock-recipe", recipe = gprefix .. "replicator-1" }
        },
        prerequisites = { "electronics" },
        unit = make_research_unit(50, t1_packs, 30),
        order = "a-r-1"
    },

    -- Technology Tier 2
    {
        type = "technology",
        name = gprefix .. "replication-2",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-2.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter-transducer" },
            { type = "unlock-recipe", recipe = gprefix .. "replicator-2" }
        },
        prerequisites = { gprefix .. "replication-1", "advanced-circuits" }, -- FIXED FOR FACTORIO 2.0 (formerly advanced-electronics)
        unit = make_research_unit(100, t2_packs, 30),
        order = "a-r-2"
    }
}

-- v4.3: Dark Matter Synthesis — the ore-free bootstrap.
-- Prerequisites and packs are deliberately VANILLA (electronics + automation
-- science): with `dmrsa-tenemut-source = "Synthesis only"` there is no tenemut
-- ore anywhere, so a tech that required a DMR pack to be researched would be an
-- unbreakable lock (you would need tenemut to unlock the machine that produces
-- tenemut). It is NOT a prerequisite of replication-1 — it is a side branch, so
-- players on "Ore patches + synthesis" can ignore it entirely.
if helpers.tenemut_synthesis_enabled() then
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "tenemut-synthesis",
        localised_name = { "technology-name.dmrsa-tenemut-synthesis" },
        localised_description = { "technology-description.dmrsa-tenemut-synthesis" },
        icons = {
            {
                icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png",
                tint = { r = 0.25, g = 0.05, b = 0.35, a = 1.0 }
            }
        },
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "tenemut-synthesizer" },
            { type = "unlock-recipe", recipe = gprefix .. "tenemut-synthesis" }
        },
        prerequisites = { "electronics" },
        unit = make_research_unit(30, { "automation-science-pack" }, 30),
        order = "a-r-0"
    })
end

if not mods["space-age"] then
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "replication-3",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
        },
        prerequisites = { gprefix .. "replication-2" },
        unit = make_research_unit(150, t3_packs, 30),
        order = "a-r-3"
    })
else
    -- With Space Age, replication-3 is VISIBLE and unlocks the Chemical
    -- Replicator (tier 3), which comes BEFORE the planets (tier 4). It also
    -- serves as the sink for orphaned tier-3 unlocks (data-final-fixes PASS 3).
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "replication-3",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
        },
        prerequisites = { gprefix .. "replication-2" },
        unit = make_research_unit(150, t3_packs, 30),
        order = "a-r-3"
    })
end

local rep_4_prereqs
if mods["space-age"] then
    rep_4_prereqs = {
        gprefix .. "replication-3",
        gprefix .. "replication-vulcanus-tech",
        gprefix .. "replication-fulgora-tech",
        gprefix .. "replication-gleba-tech",
        "processing-unit"
    }
else
    rep_4_prereqs = { gprefix .. "replication-3", "processing-unit" }
end

table.insert(tech_list, {
    type = "technology",
    name = gprefix .. "replication-4",
    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-4.png",
    icon_size = 64,
    effects = {
        { type = "unlock-recipe", recipe = gprefix .. "matter-conduit" },
        { type = "unlock-recipe", recipe = gprefix .. "replicator-4" }
    },
    prerequisites = rep_4_prereqs,
    unit = make_research_unit(250, t4_packs, 30),
    order = "a-r-4"
})

table.insert(tech_list, {
    type = "technology",
    name = gprefix .. "replication-5",
    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png",
    icon_size = 64,
    effects = {
        { type = "unlock-recipe", recipe = gprefix .. "replicator-5" }
    },
    prerequisites = mods["space-age"] and { gprefix .. "replication-4", "cryogenic-science-pack" } or { gprefix .. "replication-4" },
    unit = make_research_unit(500, t5_packs, 45),
    order = "a-r-5"
})

-- v4.0: Materials techs (one per tier) — the bridge between the machine and
-- the mirror techs. Each unlocks the BASE MATERIALS of its tier (ores, fluids,
-- plates, vanilla basics that have no original unlock tech) and is a prereq of
-- every mirror tech of that tier. Philosophy: you cannot replicate items until
-- you know their base materials. Research pack = the tier's DMR intermediate.
-- Effects are filled dynamically by MirrorGenerator.generate() (data-final-fixes
-- PASS 0) with the baseline recipes.
local materials_defs = {
    { tier = 1, pack = gprefix .. "tenemut", count = 30 },
    { tier = 2, pack = gprefix .. "dark-matter-scoop", count = 40 },
    { tier = 3, pack = gprefix .. "dark-matter-transducer", count = 50 },
    { tier = 4, pack = gprefix .. "matter-conduit", count = 60 },
    { tier = 5, pack = gprefix .. "matter-conduit", count = 70 },
}
-- v4.3: when the DMR material pack is not required for research, a materials
-- tech uses the vanilla science packs of its OWN tier instead. Handing the
-- single DMR pack to make_research_unit with the toggle off would leave the
-- unit empty and silently fall back to tier-1 packs for every tier.
local materials_fallback_packs = { t1_packs, t2_packs, t3_packs, t4_packs, t5_packs }

for _, def in ipairs(materials_defs) do
    local packs = helpers.dmr_research_pack_required() and { def.pack } or materials_fallback_packs[def.tier]
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "replication-materials-" .. def.tier,
        -- v4.2: explicit localised_name from the shared template
        -- ("technology-name.dmrsa-materials-tech" = "Replication: Raw Materials
        -- (Tier __1__)"). Previously the techs relied on per-tier locale keys
        -- (technology-name.dmrsa-replication-materials-N) — a missing key in
        -- any language rendered the raw key in the research tree.
        -- v4.2 FIX (gate test): prototype localised strings in Factorio 2.x
        -- REJECT numeric parameters at load ("Value must be a string at
        -- ...localised_name[1]") — numbers are runtime-only. tostring() the
        -- tier so the parameter slot is a string.
        localised_name = { "technology-name.dmrsa-materials-tech", tostring(def.tier) },
        icon = "__dark-matter-replicators-reborn__/graphics/icons/matter-conduit.png",
        icon_size = 64,
        effects = {},  -- filled in data-final-fixes with baseline recipes
        prerequisites = { gprefix .. "replication-" .. def.tier },
        unit = make_research_unit(def.count, packs, 30),
        order = "a-r-m-" .. def.tier
    })
end

-- v4.4.0 (Part A): Dark-matter duplication research (tiers 3/4/5).
-- Each tier grants `change-recipe-productivity` to the chemical-fuel
-- replication recipes (every target whose fuel_value <= 100 MJ) and to the
-- collider's `dmrsa-dark-matter` recipe. The fuel replication recipes also
-- carry `allow_productivity = true` — the mod's SINGLE deliberate exception
-- to the "no productivity on replication" rule.
--
-- The effects live in data-final-fixes (lib/mirror-generator.lua §8): only
-- there are the exact generated recipe names known, and only there is
-- `dmrsa-dark-matter` guaranteed to exist. Declared here as empty nodes so the
-- mirror generator can fill them.
--
-- Levels (plan §1): t3 +100 % / t4 +200 % / t5 +300 % output.
-- v4.4.0 FIX: `change-recipe-productivity` ACCUMULATES across techs, so every
-- tech emits change = 1.0 (NOT tier-2 = 1/2/3, which summed to +600 % = 7
-- items/cycle). The cumulative totals are therefore +100 % (2 items/cycle),
-- +200 % (3) and +300 % (4) — the intended 3.5x printer at tier 5.
local duplication_packs = { t3_packs, t4_packs, t5_packs }
local duplication_counts = { 300, 400, 500 }
for i, dup_tier in ipairs({ 3, 4, 5 }) do
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "duplication-" .. dup_tier,
        -- v4.2 FIX (pitfall): numeric parameters in prototype localised strings
        -- crash the data stage — the tier goes in as a string.
        localised_name = { "technology-name.dmrsa-duplication-tech", tostring(dup_tier) },
        localised_description = { "technology-description.dmrsa-duplication-tech", tostring(dup_tier) },
        icons = {
            {
                icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png",
                tint = { r = 0.35, g = 0.10, b = 0.55, a = 1.0 }
            }
        },
        icon_size = 64,
        effects = {},  -- filled in data-final-fixes with change-recipe-productivity
        prerequisites = { gprefix .. "replication-" .. dup_tier },
        unit = make_research_unit(duplication_counts[i], duplication_packs[i], 45),
        order = "a-r-d-" .. dup_tier
    })
end

data:extend(tech_list)
