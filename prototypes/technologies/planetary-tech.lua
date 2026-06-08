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

if mods["space-age"] then
    data:extend({
        -- 1. Vulcanus Geothermal Metallurgy Replication
        {
            type = "technology",
            name = gprefix .. "replication-vulcanus-tech",
            localised_name = {"technology-name.dmrsa-replication-vulcanus"},
            localised_description = {"technology-description.dmrsa-replication-vulcanus"},
            icons = {
                {
                    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
                    tint = { r = 1.0, g = 0.35, b = 0.15, a = 1.0 } -- Geothermal orange-red
                }
            },
            icon_size = 64,
            effects = {
                { type = "unlock-recipe", recipe = gprefix .. "replicator-vulcanus" },
                { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
            },
            prerequisites = { gprefix .. "replication-2", "metallurgic-science-pack" },
            unit = make_research_unit(200, { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "metallurgic-science-pack" }, 30),
            order = "a-r-vulcanus"
        },
        
        -- 2. Fulgora Electromagnetic Replication
        {
            type = "technology",
            name = gprefix .. "replication-fulgora-tech",
            localised_name = {"technology-name.dmrsa-replication-fulgora"},
            localised_description = {"technology-description.dmrsa-replication-fulgora"},
            icons = {
                {
                    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
                    tint = { r = 0.45, g = 0.15, b = 0.9, a = 1.0 } -- Electromagnetic purple-blue
                }
            },
            icon_size = 64,
            effects = {
                { type = "unlock-recipe", recipe = gprefix .. "replicator-fulgora" },
                { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
            },
            prerequisites = { gprefix .. "replication-2", "electromagnetic-science-pack" },
            unit = make_research_unit(200, { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "electromagnetic-science-pack" }, 30),
            order = "a-r-fulgora"
        },

        -- 3. Gleba Biological Replication
        {
            type = "technology",
            name = gprefix .. "replication-gleba-tech",
            localised_name = {"technology-name.dmrsa-replication-gleba"},
            localised_description = {"technology-description.dmrsa-replication-gleba"},
            icons = {
                {
                    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
                    tint = { r = 0.25, g = 0.85, b = 0.35, a = 1.0 } -- Biological green
                }
            },
            icon_size = 64,
            effects = {
                { type = "unlock-recipe", recipe = gprefix .. "replicator-gleba" },
                { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
            },
            prerequisites = { gprefix .. "replication-2", "agricultural-science-pack" },
            unit = make_research_unit(200, { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "agricultural-science-pack" }, 30),
            order = "a-r-gleba"
        },

        -- 4. Aquilo Cryogenic Superconductivity
        {
            type = "technology",
            name = gprefix .. "replication-aquilo-tech",
            localised_name = {"technology-name.dmrsa-replication-aquilo"},
            localised_description = {"technology-description.dmrsa-replication-aquilo"},
            icons = {
                {
                    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
                    tint = { r = 0.35, g = 0.75, b = 1.0, a = 1.0 } -- Subzero icy cyan
                }
            },
            icon_size = 64,
            effects = {
                { type = "unlock-recipe", recipe = gprefix .. "replicator-aquilo" }
            },
            prerequisites = { gprefix .. "replication-4", "cryogenic-science-pack" },
            unit = make_research_unit(500, { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "production-science-pack", "cryogenic-science-pack" }, 45),
            order = "a-r-aquilo"
        }
    })
end
