-- Define mod namespace
require("defines")

-- Load modular prototypes
require("prototypes.items.dark-matter")
require("prototypes.entities.replicators")
require("prototypes.recipes.base-recipes")
require("prototypes.technologies.technologies")

-- Load Space Age specialized planetary prototypes
if mods["space-age"] then
    require("prototypes.entities.planetary-replicators")
    require("prototypes.technologies.planetary-tech")
end

-- Load baseline tenemut resource definition (maps resources on planets)
require("prototypes.raw-resources")