-- prototypes/technologies/dark-matter-power.lua
-- v4.4.0 (Part B): the dark-matter power technologies; v4.5.0 adds the coil.
--
--   dmrsa-collider-1     prereq dmrsa-replication-materials-5 + production-science-pack
--                        -> unlocks the Accelerator Ring and the collision recipe
--   dmrsa-annihilation   prereq dmrsa-collider-1 + utility-science-pack + space-science-pack
--                        -> unlocks the Annihilation Chamber (and closes the loop)
--   dmrsa-annihilation-coil  prereq dmrsa-annihilation
--                        -> unlocks the Annihilation Coil (same joules, no heat stage)
--
-- ICONS ARE MANDATORY: Factorio 2.1 hard-errors on a technology without icon/icons.
-- Both icons are the mod's OWN files, tinted (verified on disk, 64x64):
--   graphics/icons/replicator-5.png / graphics/icons/tenemut.png
--
-- NO NUMERIC PARAMETERS IN THE LOCALISED STRINGS (the 4.2.0 load crash): both
-- localised_name/description tables below hold exactly ONE string element, and any
-- number a description needs lives inside the string itself, never as a parameter.
--
-- THE DELIBERATE TENSION
--   dmrsa-annihilation researches WITH dark matter (1 per repetition): the substance
--   you would rather burn for power is spent on progress instead. That works because
--   the Accelerator Ring already exists by then.
--   dmrsa-collider-1 must NOT require dark matter: the only producer of dark matter
--   in the game is the Accelerator Ring, which THIS technology unlocks — a dark-matter
--   research pack here would be an unbreakable lock (exactly the failure mode the
--   v4.3.0 tenemut-synthesis technology was designed to avoid: "you would need tenemut
--   to unlock the machine that produces tenemut"). Its DMR pack is therefore the tier-5
--   material pack, Nanophase Conduit, like its prerequisite dmrsa-replication-materials-5.
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local RING_ICON = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png"
local DARK_MATTER_ICON = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
-- v4.5.0: the coil's icon and tint, byte-for-byte the constants
-- prototypes/entities/annihilation-coil.lua uses for the item and the entity,
-- so the technology, the item and the machine read as one thing.
local COIL_ICON = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png"
local RING_TINT = { r = 0.25, g = 0.30, b = 0.85, a = 1.0 }
local DARK_MATTER_TINT = { r = 0.25, g = 0.05, b = 0.35, a = 1.0 }
local COIL_TINT = { r = 0.55, g = 1.0, b = 1.0, a = 1.0 }

-- Same contract as make_research_unit in technologies.lua:
--   * packs that do not exist are skipped (a pack id from another modlist can never
--     crash the unit);
--   * with `dmrsa-tenemut-research-required = false` every "dmrsa-" pack is dropped
--     and the vanilla packs carry the cost;
--   * an EMPTY ingredient list is never allowed (it renders as "no cost" — the v4.2
--     failure mode), so the fallback fills in tier-1 vanilla packs;
--   * research difficulty scales count (repetitions) and time.
local function make_research_unit(count, packs, time)
    local ingredients = {}
    local dmr_pack_required = helpers.dmr_research_pack_required()
    for _, pack in ipairs(packs) do
        local is_dmr_pack = type(pack) == "string"
            and string.sub(pack, 1, string.len(gprefix)) == gprefix
        if helpers.item_exists(pack) and (dmr_pack_required or not is_dmr_pack) then
            table.insert(ingredients, { pack, 1 })
        end
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
        time = math.max(1, math.ceil((time or 30) * diff_mult.time_mult))
    }
end

-- Prerequisites are the ones the plan names; each is guarded so a modlist that
-- removes a vanilla tech cannot produce a dangling prerequisite (the final-fixes
-- PASS 1 would strip it anyway, this just keeps the intent readable in the dump).
-- CAVEAT (bug found by the v4.4.0 engine gate): both techs go out in the SAME
-- data:extend() call below, so data.raw.technology does NOT yet contain them when
-- these tables are built — an existence-only guard silently dropped
-- dmrsa-annihilation's dmrsa-collider-1 prerequisite. OWN_TECHS covers the names
-- this file defines itself; everything else still needs to exist for real.
local OWN_TECHS = {}
for _, suffix in ipairs({ "collider-1", "annihilation", "annihilation-coil" }) do
    OWN_TECHS[gprefix .. suffix] = true
end

local function prereqs(list)
    local out = {}
    for _, name in ipairs(list) do
        if data.raw.technology[name] or OWN_TECHS[name] then
            table.insert(out, name)
        end
    end
    return out
end

-- ENGINE CONSTRAINT (verified on the real 2.1.20 data stage, not assumed):
-- a technology's packs must ALL be accepted by ONE lab. prototypes/entities/
-- replicators.lua defines the DMR replication lab with inputs = the four DMR
-- materials, and prototypes/fixes/pass-lab-inputs.lua only adds the planetary
-- packs in data-final-fixes; no vanilla lab ever accepts a DMR pack. Since
-- dmrsa-annihilation researches WITH dark matter, dark matter has to be a valid
-- lab input. Without this registration the engine refuses to load the mod with:
--   "Technology dmrsa-annihilation: there is no lab that will accept all of the
--    science packs this technology requires."
-- Additive and guarded (idempotent — if the pass or a future refactor already
-- listed it, nothing happens). The same fix could live in pass-lab-inputs.lua,
-- which is not one of the Part B owned files.
local dmr_lab = data.raw.lab and data.raw.lab[gprefix .. "replication-lab"]
local dark_matter_pack = gprefix .. "dark-matter"
if dmr_lab and dmr_lab.inputs and helpers.item_exists(dark_matter_pack) then
    local present = false
    for _, input in ipairs(dmr_lab.inputs) do
        if input == dark_matter_pack then
            present = true
            break
        end
    end
    if not present then
        table.insert(dmr_lab.inputs, dark_matter_pack)
        helpers.log("data: added '" .. dark_matter_pack .. "' to replication-lab inputs (dark matter research pack)")
    end
else
    helpers.warn("data: replication-lab not found — '" .. dark_matter_pack
        .. "' cannot be a research pack and dmrsa-annihilation would be unresearchable")
end

data:extend({
    -- 1. Dark matter collision: the Accelerator Ring + the collision recipe.
    {
        type = "technology",
        name = gprefix .. "collider-1",
        localised_name = { "technology-name.dmrsa-collider-1" },
        localised_description = { "technology-description.dmrsa-collider-1" },
        icons = {
            {
                icon = RING_ICON,
                tint = RING_TINT
            }
        },
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "collider" },
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter" }
        },
        prerequisites = prereqs({
            gprefix .. "replication-materials-5",
            "production-science-pack"
        }),
        -- RESEARCH PACKS: the DMR pack ONLY. ENGINE CONSTRAINT (verified on the
        -- real 2.1.20 data stage): the DMR replication lab accepts the DMR packs
        -- plus (in Space Age) the planetary packs, while the vanilla lab accepts
        -- the vanilla packs and never the DMR ones — so a unit mixing e.g.
        -- production-science-pack with dmrsa-matter-conduit makes Factorio fail
        -- with "there is no lab that will accept all of the science packs this
        -- technology requires". The vanilla gate is therefore a PREREQUISITE
        -- (production-science-pack above), and the pack is the tier-5 DMR
        -- material, exactly like dmrsa-replication-materials-5 and every mirror
        -- tech the generator creates.
        unit = make_research_unit(100, {
            gprefix .. "matter-conduit"
        }, 45),
        order = "a-r-c1"
    },

    -- 2. Annihilation power: the reactor side of the loop.
    {
        type = "technology",
        name = gprefix .. "annihilation",
        localised_name = { "technology-name.dmrsa-annihilation" },
        localised_description = { "technology-description.dmrsa-annihilation" },
        icons = {
            {
                icon = DARK_MATTER_ICON,
                tint = DARK_MATTER_TINT
            }
        },
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "annihilator" }
        },
        prerequisites = prereqs({
            gprefix .. "collider-1",
            "utility-science-pack",
            "space-science-pack"
        }),
        -- THE TENSION: one dark matter per repetition (100 by default = 100 x 25 GJ
        -- of fuel turned into progress instead of power). It is the ONLY pack, for
        -- the lab reason documented on dmrsa-collider-1 above (the DMR lab takes
        -- dark matter, no vanilla lab does). Dropped automatically when
        -- `dmrsa-tenemut-research-required` is off.
        unit = make_research_unit(100, {
            gprefix .. "dark-matter"
        }, 60),
        order = "a-r-c2"
    },

    -- 3. Annihilation coil: the same decay, harvested as charge instead of heat.
    -- It is a REFINEMENT of dmrsa-annihilation (better plumbing, same joules),
    -- so it is gated behind it and costs less research than the chamber did:
    -- 75 repetitions instead of 100, 45 s instead of 60 s. Same DMR pack for
    -- the lab reason documented at the top of this file — the replication lab
    -- already accepts `dmrsa-dark-matter` (registered above for
    -- dmrsa-annihilation), and no vanilla lab does, so mixing in a vanilla pack
    -- here would make the tech unresearchable. With
    -- `dmrsa-tenemut-research-required` off, make_research_unit swaps in the
    -- vanilla packs, which is why the list is built by that helper.
    -- `dmrsa-annihilation` is in OWN_TECHS above: both techs ship in this same
    -- data:extend() call, so the guard cannot see it in data.raw yet (the
    -- v4.4.0 bug this table exists for).
    {
        type = "technology",
        name = gprefix .. "annihilation-coil",
        localised_name = { "technology-name.dmrsa-annihilation-coil" },
        localised_description = { "technology-description.dmrsa-annihilation-coil" },
        icons = {
            {
                icon = COIL_ICON,
                tint = COIL_TINT
            }
        },
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "annihilation-coil" }
        },
        prerequisites = prereqs({
            gprefix .. "annihilation"
        }),
        unit = make_research_unit(75, {
            gprefix .. "dark-matter"
        }, 45),
        order = "a-r-c3"
    }
})
