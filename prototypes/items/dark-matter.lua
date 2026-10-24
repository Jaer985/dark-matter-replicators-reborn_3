local gprefix = "dmrsa-"

-- 1. Define the dedicated custom Item Group (tab at the top of the crafting menu)
data:extend({
    {
        type = "item-group",
        name = "dmrsa-replication",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/category-replicators.png",
        icon_size = 128,
        order = "g-dmrsa"
    }
})

-- 2. Define all custom item subgroups, assigning them to our custom Replication group
data:extend({
    -- Subgroup for intermediate items (scoops, transducers, conduits)
    {
        type = "item-subgroup",
        name = gprefix .. "replication-resources",
        group = "dmrsa-replication",
        order = "a[dmrsa-resources]"
    },
    -- Subgroup for the machines themselves (replicators and lab)
    {
        type = "item-subgroup",
        name = gprefix .. "replicators",
        group = "dmrsa-replication",
        order = "b[dmrsa-replicators]"
    }
})

-- 3. Register item subgroups for the 5 tiers of dynamically generated recipes, assigning them to our custom group
for i = 1, 5 do
    data:extend({
        {
            type = "item-subgroup",
            name = gprefix .. "replication-tier-" .. i,
            group = "dmrsa-replication",
            order = "c[dmrsa-tier-" .. i .. "]"
        }
    })
end

-- 3b. Register item subgroups per replication category (v3.5.21).
-- This makes it easy to find items in the replicator crafting menu by
-- category (modules, weapons, chemicals...) instead of scanning each tier.
-- Mirrors the [replcategory-name] locale keys so names resolve automatically.
local category_subgroups = {
    "ore", "element", "shape", "alloy", "chemical", "organic",
    "module", "module-advanced", "science", "military", "military-advanced",
    "life", "exotic", "magic", "alien", "general"
}
for _, cat in ipairs(category_subgroups) do
    data:extend({
        {
            type = "item-subgroup",
            name = gprefix .. "replication-" .. cat,
            group = "dmrsa-replication",
            order = "d[dmrsa-cat-" .. cat .. "]"
        }
    })
end

data:extend({
    -- ── v4.4.0 (C2): the private fuel category ────────────────────────────────
    -- Dark matter shipped as `fuel_categories = { "nuclear" }`, so a VANILLA
    -- nuclear reactor could burn it — and a 2x2 block burned it with the
    -- reactor's 1.5-1.75x neighbour bonus, turning the collider's declared
    -- 0.50x floor (250 MW x 200 s = 50 GJ in, 25 GJ out) into a 0.75-0.875x
    -- return with no research at all. The item now carries a category that only
    -- the Annihilation Chamber accepts (`dmrsa-dark-matter-fuel`), so the floor
    -- is the floor. fuel_value stays 25 GJ: the energy ledger did not change,
    -- only WHO may burn it.
    {
        type = "fuel-category",
        name = gprefix .. "dark-matter-fuel"
    },
    -- Tenemut (raw material, tool). Defined HERE (items file, loaded FIRST by
    -- data.lua) — v4.2 fix (gate-test dump 2026-08-23): it previously lived in
    -- prototypes/raw-resources.lua which loads AFTER technologies.lua, so
    -- make_research_unit ran before data.raw.tool["dmrsa-tenemut"] existed →
    -- helpers.item_exists returned false → the hardened fallback silently
    -- substituted matter-conduit for the tier-1 materials pack (dump showed
    -- replication-materials-1 researching with 30× Nanophase Conduit).
    {
        type = "tool",
        name = gprefix .. "tenemut",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png",
        icon_size = 64,
        subgroup = "raw-resource",
        order = "f[tenemut]",
        stack_size = 200,
        durability = 1
    },

    -- Pure Dark Matter (High-stack universal input item)
    -- v4.4.0 (Part B): it is now the carrier of the power loop — a fuel.
    --   fuel_value / fuel_categories make it burnable through the mod's OWN
    --   category (v4.4.0 C2: `dmrsa-dark-matter-fuel`, declared right above —
    --   the vanilla reactor's `nuclear` category is deliberately NOT used, so
    --   the 1.5-1.75x neighbour bonus of a reactor block cannot be stacked on
    --   top of the collider ledger). The Annihilation Chamber
    --   (prototypes/entities/annihilator.lua) is tuned around the value:
    --   one unit = 25 GJ = 25 000 MJ -> 600 s of heat at 41.6667 MW.
    --   It stays hidden (hidden = true) so it never appears in the item browser.
    --   NOTE (engine, Factorio 2.1.20): the singular `fuel_category` was REMOVED —
    --   the field is `fuel_categories` (array). Proven by the load error
    --   "ItemPrototype::fuel_category was removed. Please use
    --   ItemPrototype::fuel_categories." and by base's nuclear-fuel
    --   (base/prototypes/item.lua: fuel_categories = {"nuclear"}).
    {
        type = "item",
        name = gprefix .. "dark-matter",
        localised_name = {"item-name.dmrsa-dark-matter"},
        localised_description = {"item-description.dmrsa-dark-matter"},
        hidden = true,
        icons = {
            {
                icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png",
                tint = {r = 0.25, g = 0.05, b = 0.35, a = 1.0} -- SLEEK PURPLE/DARK MATTE TINT
            }
        },
        icon_size = 64,
        subgroup = "raw-resource", -- Raw resource is placed under vanilla raw resources to keep it in the natural ore group
        order = "z",
        stack_size = 1000,
        fuel_value = "25GJ",
        -- v4.4.0 (C2): PRIVATE category — a vanilla reactor/boiler/generator
        -- accepts `nuclear`/`chemical`, never this one. Only the Annihilation
        -- Chamber (prototypes/entities/annihilator.lua) lists it.
        fuel_categories = { gprefix .. "dark-matter-fuel" },
        -- Purple glow while burning (shown on the Annihilation Chamber's light).
        fuel_glow_color = {r = 0.45, g = 0.15, b = 0.7, a = 1.0}
    },

    -- Dark Matter Scoop
    {
        type = "tool",
        name = gprefix .. "dark-matter-scoop",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/dark-matter-scoop.png",
        icon_size = 64,
        subgroup = gprefix .. "replication-resources",
        order = "a[matter-conduit]-a",
        stack_size = 200,
        durability = 1
    },

    -- Dark Matter Transducer
    {
        type = "tool",
        name = gprefix .. "dark-matter-transducer",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/dark-matter-transducer.png",
        icon_size = 64,
        subgroup = gprefix .. "replication-resources",
        order = "a[matter-conduit]-b",
        stack_size = 200,
        durability = 1
    },

    -- Matter Conduit
    {
        type = "tool",
        name = gprefix .. "matter-conduit",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/matter-conduit.png",
        icon_size = 64,
        subgroup = gprefix .. "replication-resources",
        order = "a[matter-conduit]-c",
        stack_size = 200,
        durability = 1
    }
})
