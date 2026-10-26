-- Replication type definitions (v4.5.1 — author-approved taxonomy)
--
-- The category of an item is decided STRUCTURALLY by lib/item-class.lua (entity
-- type, item type, fuel value, smelting recipe, minability), not by its name.
-- This table only carries the display/tech metadata for each category:
--   * tier  = FIXED minimum replication tier for items of this category (nil =
--             dynamic, from the cost solver);
--   * order = sort key of the picker subgroup (a, b, c … in the order below).
--
-- Order approved by the author (2026-10-24): machines · power · science ·
-- modules · ores · plates · intermediates · chemicals · logistics · military ·
-- fuels · organic · darkmatter.
-- Display names live in the locale files ([replcategory-name] and
-- [item-subgroup-name]) keyed by the category name, never hardcoded here.

local repltypes = {
    machines = { name = "machines", tier = 2, order = "aa" },
    power = { name = "power", tier = 3, order = "ab" },
    science = { name = "science", tier = nil, order = "ac" },
    modules = { name = "modules", tier = 3, order = "ad" },
    ores = { name = "ores", tier = 1, order = "ba" },
    plates = { name = "plates", tier = 2, order = "bb" },
    intermediates = { name = "intermediates", tier = 2, order = "bc" },
    chemicals = { name = "chemicals", tier = 3, order = "bd" },
    logistics = { name = "logistics", tier = 1, order = "ca" },
    military = { name = "military", tier = 3, order = "cb" },
    fuels = { name = "fuels", tier = 1, order = "cc" },
    organic = { name = "organic", tier = 3, order = "cd" },
    darkmatter = { name = "darkmatter", tier = 1, order = "da" },
    -- Fallback used by the legacy name-pattern helper only.
    general = { name = "general", tier = nil, order = "zz" },
}

-- Known element names (kept for the legacy classifier and the tech-icon border
-- helper; the structural classifier does not need them).
repltypes.element_names = {
    "hydrogen", "helium", "lithium", "beryllium", "boron",
    "carbon", "nitrogen", "oxygen", "fluorine", "neon",
    "sodium", "magnesium", "alumin", "aluminium", "aluminum",
    "silicon", "phosphorus", "sulfur", "sulphur", "chlorine",
    "titanium", "chromium", "manganese", "iron", "cobalt",
    "nickel", "copper", "zinc", "gallium", "germanium",
    "arsenic", "selenium", "bromine", "krypton",
    "silver", "cadmium", "indium", "tin", "antimony",
    "tellurium", "iodine", "xenon",
    "barium", "lanthanum", "cerium",
    "neodymium", "promethium", "samarium", "europium",
    "gadolinium", "terbium", "dysprosium", "holmium", "erbium",
    "thulium", "ytterbium", "lutetium",
    "tantalum", "tungsten", "wolfram", "rhenium", "osmium",
    "iridium", "platinum", "gold", "mercury", "thallium",
    "lead", "bismuth", "polonium", "astatine", "radon",
    "francium", "radium", "actinium", "thorium",
    "protactinium", "uranium", "neptunium", "plutonium",
    "americium", "curium",
}


return repltypes
