local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Setup science pack ingredients helper
local function make_research_unit(count, packs, time)
    local ingredients = {}
    for _, pack in ipairs(packs) do
        table.insert(ingredients, { pack, 1 })
    end
    return {
        count = count,
        ingredients = ingredients,
        time = time or 30
    }
end

-- 1. Baseline Science Packs List
local t1_packs = { "automation-science-pack", "logistic-science-pack" }
local t2_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }

-- Check for Space Age expansion packs
local t3_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    -- Require planetary science to progress to high tiers
    table.insert(t3_packs, "metallurgic-science-pack")
end

local t4_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    table.insert(t4_packs, "production-science-pack")
    table.insert(t4_packs, "utility-science-pack")
else
    table.insert(t4_packs, "production-science-pack")
end

local t5_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    table.insert(t5_packs, "space-science-pack")
    table.insert(t5_packs, "cryogenic-science-pack")
else
    table.insert(t5_packs, "utility-science-pack")
    table.insert(t5_packs, "space-science-pack")
end

data:extend({
    -- Technology Tier 1
    {
        type = "technology",
        name = gprefix .. "replication-1",
        icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-1.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter" },
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
        icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-2.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter-transducer" },
            { type = "unlock-recipe", recipe = gprefix .. "replicator-2" }
        },
        prerequisites = { gprefix .. "replication-1", "advanced-circuits" }, -- FIXED FOR FACTORIO 2.0 (formerly advanced-electronics)
        unit = make_research_unit(100, t2_packs, 30),
        order = "a-r-2"
    },

    -- Technology Tier 3
    {
        type = "technology",
        name = gprefix .. "replication-3",
        icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-3.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
        },
        prerequisites = mods["space-age"] and { gprefix .. "replication-2", "metallurgic-science-pack" } or { gprefix .. "replication-2" },
        unit = make_research_unit(150, t3_packs, 30),
        order = "a-r-3"
    },

    -- Technology Tier 4
    {
        type = "technology",
        name = gprefix .. "replication-4",
        icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-4.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "matter-conduit" },
            { type = "unlock-recipe", recipe = gprefix .. "replicator-4" }
        },
        prerequisites = { gprefix .. "replication-3", "processing-unit" }, -- FIXED FOR FACTORIO 2.0 (formerly advanced-electronics-2)
        unit = make_research_unit(250, t4_packs, 30),
        order = "a-r-4"
    },

    -- Technology Tier 5
    {
        type = "technology",
        name = gprefix .. "replication-5",
        icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-5.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "replicator-5" }
        },
        prerequisites = mods["space-age"] and { gprefix .. "replication-4", "cryogenic-science-pack" } or { gprefix .. "replication-4" },
        unit = make_research_unit(500, t5_packs, 45),
        order = "a-r-5"
    }
})
