-- Define mod namespace
require("defines")

-- Safe require wrapper with traceback on error
local function safe_require(module_path)
    local ok, result = pcall(require, module_path)
    if not ok then
        log("[DarkMatterReplicators] ERROR loading " .. module_path .. ": " .. tostring(result) .. "\n" .. debug.traceback())
    end
    return result
end

-- Load modular prototypes
safe_require("prototypes.items.dark-matter")
safe_require("prototypes.entities.replicators")
safe_require("prototypes.entities.refiner")
-- v4.3: Dark Matter Synthesizer (ore-free tenemut) — self-gating on the
-- `dmrsa-tenemut-source` startup setting (returns early in "Ore patches").
safe_require("prototypes.entities.synthesizer")
-- v4.4.0 (Part B): the dark-matter power loop — Accelerator Ring + Annihilation
-- Chamber. Loaded BEFORE the recipes that reference their categories/items, and
-- before the technologies that unlock them.
safe_require("prototypes.entities.collider")
safe_require("prototypes.entities.annihilator")
-- v4.5.0: the Annihilation Coil — the same dark matter burned straight into
-- electricity. Loaded right after its sibling chamber and BEFORE
-- recipes/dark-matter-power.lua, which defines its build recipe.
safe_require("prototypes.entities.annihilation-coil")
safe_require("prototypes.recipes.base-recipes")
safe_require("prototypes.recipes.dark-matter-power")
safe_require("prototypes.technologies.technologies")
-- v4.4.0 (Part B): dmrsa-collider-1 + dmrsa-annihilation. AFTER technologies.lua,
-- because they declare dmrsa-replication-materials-5 as a prerequisite (guard
-- reads data.raw.technology at load time, load order matters).
safe_require("prototypes.technologies.dark-matter-power")

-- Load Space Age specialized planetary prototypes
if mods["space-age"] then
    safe_require("prototypes.entities.planetary-replicators")
    safe_require("prototypes.technologies.planetary-tech")
end

-- Load baseline tenemut resource definition (maps resources on planets)
safe_require("prototypes.raw-resources")