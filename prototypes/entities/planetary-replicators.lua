local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Define custom planetary recipe categories
data:extend({
    { type = "recipe-category", name = gprefix .. "replication-vulcanus" },
    { type = "recipe-category", name = gprefix .. "replication-fulgora" },
    { type = "recipe-category", name = gprefix .. "replication-gleba" },
    { type = "recipe-category", name = gprefix .. "replication-aquilo" }
})

-- Common function to define a specialized planetary replicator
local function make_planetary_replicator(name_suffix, speed, power_mw, tint_color, surface_conds)
    local name = gprefix .. "replicator-" .. name_suffix
    
    local entity = {
        type = "assembling-machine",
        name = name,
        icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-3.png",
        icon_size = 64,
        icons = {
            {
                icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-3.png",
                tint = tint_color
            }
        },
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.5, result = name },
        fast_replaceable_group = gprefix .. "replicator",
        max_health = 350,
        resistances = {
            {
                type = "fire",
                percent = 80
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -0.8, -0.8 }, { 0.8, 0.8 } },
        selection_box = { { -1.0, -1.0 }, { 1.0, 1.0 } },
        
        -- Native C++ replication processing
        crafting_categories = { gprefix .. "replication-" .. name_suffix },
        crafting_speed = speed,
        
        -- High power consumption (GW/MW range)
        energy_usage = power_mw .. "MW",
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input",
            emissions_per_second = 0.05
        },

        -- Optimal fluid outputs (UPS Friendly, only connects when recipe outputs fluid)
        fluid_boxes_off_when_no_fluid_recipe = true,
        fluid_boxes = {
            {
                production_type = "output",
                pipe_picture = assembler2pipepictures(),
                pipe_covers = pipecoverspictures(),
                base_area = 10,
                base_level = 1,
                volume = 100,
                pipe_connections = {
                    {
                        flow_direction = "output",
                        position = { -0.5, 0.8 }, -- Properly aligned with grid and inside bounding box
                        direction = defines.direction.south,
                    }
                }
            }
        },

        -- Graphics with custom planetary tint overlays!
        graphics_set = {
            animation = {
                filename = "__dark-matter-replicators-space-age__/graphics/entity/replicator-3.png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                scale = 0.66,
                tint = tint_color -- BEAUTIFUL VIBRANT PLANETARY TINT OVERLAYS
            }
        },
        working_sound = {
            sound = {
                {
                    filename = "__base__/sound/lab.ogg",
                    volume = 0.7
                }
            },
            idle_sound = { filename = "__base__/sound/idle1.ogg", volume = 0.6 },
            apparent_volume = 1.5
        },
        
        module_slots = 3,
        allowed_effects = { "consumption", "speed", "productivity", "quality", "pollution" }
    }

    -- Apply planetary restrictions if Space Age expansion is loaded
    if mods["space-age"] and surface_conds then
        entity.surface_conditions = surface_conds
    end

    -- Add space-exploration space allowance if configured
    if helpers.get_startup_setting("replication-in-space", false) then
        entity.se_allow_in_space = true
    end

    data:extend({
        -- Item
        {
            type = "item",
            name = name,
            icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-3.png",
            icon_size = 64,
            icons = {
                {
                    icon = "__dark-matter-replicators-space-age__/graphics/icons/replicator-3.png",
                    tint = tint_color
                }
            },
            subgroup = gprefix .. "replicators",
            order = "c-" .. name_suffix,
            place_result = name,
            stack_size = 50
        },
        -- Recipe
        {
            type = "recipe",
            name = name,
            enabled = false,
            ingredients = {
                { type = "item", name = gprefix .. "replicator-3", amount = 1 },
                { type = "item", name = gprefix .. "matter-conduit", amount = 2 }
            },
            results = {
                { type = "item", name = name, amount = 1 }
            },
            subgroup = gprefix .. "replicators",
            order = "c-" .. name_suffix
        },
        -- Entity
        entity
    })
end

-- Define the 4 planetary machines
if mods["space-age"] then
    -- 1. Vulcanus (Geothermal): Orange/Red tint, metallurgy speedup
    make_planetary_replicator(
        "vulcanus", 
        3.0, 
        400, 
        { r = 1.0, g = 0.35, b = 0.15, a = 1.0 },
        { { property = "gravity", min = 0.5 } } -- restricts to solid surfaces
    )

    -- 2. Fulgora (Electromagnetic): Electric Cyan/Purple tint, electronics speedup
    make_planetary_replicator(
        "fulgora", 
        3.0, 
        400, 
        { r = 0.45, g = 0.15, b = 0.9, a = 1.0 },
        { { property = "gravity", min = 0.5 } }
    )

    -- 3. Gleba (Bio-Replicator): Moss Green tint, organic synthesis
    make_planetary_replicator(
        "gleba", 
        3.0, 
        400, 
        { r = 0.25, g = 0.85, b = 0.35, a = 1.0 },
        { { property = "gravity", min = 0.5 } }
    )

    -- 4. Aquilo (Cryogenic): Icy Blue tint, ultra superconductive speed
    make_planetary_replicator(
        "aquilo", 
        5.0, 
        800, 
        { r = 0.35, g = 0.75, b = 1.0, a = 1.0 },
        { { property = "gravity", min = 0.5 } }
    )
end
