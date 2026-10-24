-- prototypes/recipes/dark-matter-power.lua
-- v4.4.0 (Part B): the dark-matter recipes.
--
-- 1. dmrsa-dark-matter  — the collision recipe. MACHINE-ONLY.
--    THE 200 SECONDS ARE THE BALANCE, NOT A PLACEHOLDER:
--      250 MW (dmrsa-collider) x 200 s = 50 GJ spent  vs  25 GJ of fuel_value out
--      -> 0.50x at L0, 1.00x at L1, 1.50x at L2, 2.00x at L3 (the duplication
--      research adds change-recipe-productivity to THIS recipe, hence
--      allow_productivity = true — the single deliberate exception to the mod's
--      "no productivity on replication" rule).
--    At the originally briefed 40 s the ring would return 25 GJ for 10 GJ = 2.45x
--    POSITIVE with zero research: an infinite power printer. Do not shorten it.
--
--    VISIBILITY (the v4.1 refiner bug, research/refiner-picker-hidden-bug.md):
--      hide_from_player_crafting = true  (never hand-craftable, but STILL listed in
--                                        the Accelerator Ring's recipe picker)
--      hidden is NOT set: `hidden = true` would also remove it from machine pickers,
--      which is exactly why the Quality Refiner shipped empty in 4.1.0-4.3.1.
--    The category `dmrsa-collision` already makes it impossible to hand-craft
--    (the character has no such crafting category); the flag is belt and braces.
--
-- 2. dmrsa-collider / dmrsa-annihilator / dmrsa-annihilation-coil — the three
--    build recipes (machine items). All enabled = false: the technologies
--    unlock them.
local gprefix = "dmrsa-"

local TENEMUT_ICON = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
local DARK_MATTER_TINT = { r = 0.25, g = 0.05, b = 0.35, a = 1.0 }

-- Must match prototypes/entities/collider.lua: 250 MW x this = 50 GJ.
local COLLISION_TIME = 200

data:extend({
    -- 1. Dark matter — the Accelerator Ring's only product.
    {
        type = "recipe",
        name = gprefix .. "dark-matter",
        -- Factorio 2.1: `categories` (array). The singular `category` key now
        -- HARD-ERRORS at prototype load (caught by the 4.3.0 engine gate).
        categories = { gprefix .. "collision" },
        subgroup = "raw-resource",
        icons = {
            {
                icon = TENEMUT_ICON,
                tint = DARK_MATTER_TINT
            }
        },
        icon_size = 64,
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "tenemut", amount = 25 },
            { type = "item", name = gprefix .. "matter-conduit", amount = 1 }
        },
        results = {
            { type = "item", name = gprefix .. "dark-matter", amount = 1 }
        },
        main_product = gprefix .. "dark-matter",
        -- 250 MW x 200 s = 50 GJ per unit (see header).
        energy_required = COLLISION_TIME,
        -- The deliberate exception: the duplication research needs productivity to
        -- work, and this recipe consumes its inputs (no free duplication).
        allow_productivity = true,
        -- Machine-only, but pickable inside the collider (refiner bug).
        hide_from_player_crafting = true,
        allow_decomposition = false,
        -- No recycler path back into tenemut: dark matter is only ever burned.
        auto_recycle = false
    },

    -- 2a. Build recipe: Accelerator Ring (unlocked by dmrsa-collider-1).
    {
        type = "recipe",
        name = gprefix .. "collider",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "matter-conduit", amount = 25 },
            { type = "item", name = "processing-unit", amount = 75 },
            { type = "item", name = "advanced-circuit", amount = 100 },
            { type = "item", name = "steel-plate", amount = 150 }
        },
        results = {
            { type = "item", name = gprefix .. "collider", amount = 1 }
        }
    },

    -- 2b. Build recipe: Annihilation Chamber (unlocked by dmrsa-annihilation).
    {
        type = "recipe",
        name = gprefix .. "annihilator",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "matter-conduit", amount = 30 },
            { type = "item", name = "processing-unit", amount = 100 },
            { type = "item", name = "advanced-circuit", amount = 150 },
            { type = "item", name = "steel-plate", amount = 300 }
        },
        results = {
            { type = "item", name = gprefix .. "annihilator", amount = 1 }
        }
    },

    -- 2c. Build recipe: Annihilation Coil (unlocked by dmrsa-annihilation-coil).
    -- CHEAPER THAN THE CHAMBER ON PURPOSE. The chamber is a 5x5 reactor whose
    -- 41.7 MW only reaches the grid through ~4.2 vanilla heat exchangers and
    -- ~7 steam turbines (plus the water line and the heat-pipe grid): that
    -- hardware is the real price of the chamber build, and the coil replaces
    -- all of it with one 2x2 machine. So the coil costs ~2/3 of the chamber:
    --   30 -> 20 matter conduits (less plumbing: no heat-pipe connections)
    --   8 dark-matter transducers (the phased lattice itself — the one part
    --     the chamber does not need; 8 transducers = 32 scoops + 8 circuits)
    --   100 -> 75 processing units, 150 -> 100 advanced circuits (fewer
    --     control loops than a reactor with a heat buffer)
    --   300 -> 200 steel (no pressure vessel, no exchanger housings)
    -- It is NOT cheaper in joules: fuel_value and effectivity are untouched.
    {
        type = "recipe",
        name = gprefix .. "annihilation-coil",
        enabled = false,
        -- Hand-craftable on purpose: the ingredients and the technology are the
        -- gate, exactly like the chamber's recipe (only the machine-only
        -- collision recipe above hides itself from the crafting menu).
        hide_from_player_crafting = false,
        ingredients = {
            { type = "item", name = gprefix .. "matter-conduit", amount = 20 },
            { type = "item", name = gprefix .. "dark-matter-transducer", amount = 8 },
            { type = "item", name = "processing-unit", amount = 75 },
            { type = "item", name = "advanced-circuit", amount = 100 },
            { type = "item", name = "steel-plate", amount = 200 }
        },
        results = {
            { type = "item", name = gprefix .. "annihilation-coil", amount = 1 }
        }
    }
})
