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

data:extend({
    -- Pure Dark Matter (High-stack universal input item)
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
        order = "f[dark-matter]",
        stack_size = 1000
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
