local gprefix = "dmrsa-"

data:extend({
    -- 1. Dark Matter scoop (Tier 1 Component)
    {
        type = "recipe",
        name = gprefix .. "dark-matter-scoop",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "tenemut", amount = 4 },
            { type = "item", name = "iron-plate", amount = 1 }
        },
        results = {
            { type = "item", name = gprefix .. "dark-matter-scoop", amount = 1 }
        }
    },

    -- 2. Dark Matter Transducer (Tier 2 Component)
    {
        type = "recipe",
        name = gprefix .. "dark-matter-transducer",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "dark-matter-scoop", amount = 4 },
            { type = "item", name = "steel-plate", amount = 1 }
        },
        results = {
            { type = "item", name = gprefix .. "dark-matter-transducer", amount = 1 }
        }
    },

    -- 3. Matter Conduit (Tier 4 Component)
    {
        type = "recipe",
        name = gprefix .. "matter-conduit",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "dark-matter-transducer", amount = 4 },
            { type = "item", name = gprefix .. "dark-matter-scoop", amount = 1 }
        },
        results = {
            { type = "item", name = gprefix .. "matter-conduit", amount = 1 }
        }
    },

    -- 4. Pure Dark Matter Condensation (Refining Tenemut to Dark Matter)
    {
        type = "recipe",
        name = gprefix .. "dark-matter",
        enabled = false,
        category = "crafting",
        energy_required = 10,
        ingredients = {
            { type = "item", name = gprefix .. "tenemut", amount = 1 },
            { type = "item", name = "coal", amount = 1 }
        },
        results = {
            { type = "item", name = gprefix .. "dark-matter", amount = 50 }
        }
    },

    -- 5. Replication Lab
    {
        type = "recipe",
        name = gprefix .. "replication-lab",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "dark-matter-scoop", amount = 5 },
            { type = "item", name = "electronic-circuit", amount = 10 },
            { type = "item", name = "copper-plate", amount = 10 }
        },
        results = {
            { type = "item", name = gprefix .. "replication-lab", amount = 1 }
        }
    },

    -- 6. Replicator Tier 1 Recipe
    {
        type = "recipe",
        name = gprefix .. "replicator-1",
        enabled = false,
        ingredients = {
            { type = "item", name = "iron-plate", amount = 10 },
            { type = "item", name = "electronic-circuit", amount = 5 },
            { type = "item", name = gprefix .. "dark-matter-scoop", amount = 4 }
        },
        results = {
            { type = "item", name = gprefix .. "replicator-1", amount = 1 }
        }
    },

    -- 7. Replicator Tier 2 Recipe
    {
        type = "recipe",
        name = gprefix .. "replicator-2",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "replicator-1", amount = 1 },
            { type = "item", name = "electronic-circuit", amount = 10 },
            { type = "item", name = gprefix .. "dark-matter-transducer", amount = 2 }
        },
        results = {
            { type = "item", name = gprefix .. "replicator-2", amount = 1 }
        }
    },

    -- 8. Replicator Tier 3 Recipe
    {
        type = "recipe",
        name = gprefix .. "replicator-3",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "replicator-2", amount = 1 },
            { type = "item", name = "advanced-circuit", amount = 5 },
            { type = "item", name = gprefix .. "dark-matter-transducer", amount = 4 }
        },
        results = {
            { type = "item", name = gprefix .. "replicator-3", amount = 1 }
        }
    },

    -- 9. Replicator Tier 4 Recipe
    {
        type = "recipe",
        name = gprefix .. "replicator-4",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "replicator-3", amount = 1 },
            { type = "item", name = "advanced-circuit", amount = 10 },
            { type = "item", name = gprefix .. "matter-conduit", amount = 2 }
        },
        results = {
            { type = "item", name = gprefix .. "replicator-4", amount = 1 }
        }
    },

    -- 10. Replicator Tier 5 Recipe
    {
        type = "recipe",
        name = gprefix .. "replicator-5",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "replicator-4", amount = 1 },
            { type = "item", name = "processing-unit", amount = 5 },
            { type = "item", name = gprefix .. "matter-conduit", amount = 4 }
        },
        results = {
            { type = "item", name = gprefix .. "replicator-5", amount = 1 }
        }
    }
})
