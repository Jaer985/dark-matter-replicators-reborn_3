local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Retrieve stats from settings with robust short-circuit evaluation
local speed_base = helpers.get_startup_setting("replstats-speed-base", 1.0)
local speed_factor = helpers.get_startup_setting("replstats-speed-factor", 2.0)
local energy_base = helpers.get_startup_setting("replstats-energy-base", 256.0) -- in kW
local energy_factor = helpers.get_startup_setting("replstats-energy-factor", 2.5)
local pollution_base = helpers.get_startup_setting("replstats-pollution-base", 1.0)
local pollution_factor = helpers.get_startup_setting("replstats-pollution-factor", 1.75)
local size_base = helpers.get_startup_setting("replstats-size-base", 2.0)
local size_addend = helpers.get_startup_setting("replstats-size-addend", 0.0)
local module_slots_base = helpers.get_startup_setting("replstats-modules-base", 1.0)
local module_slots_addend = helpers.get_startup_setting("replstats-modules-addend", 0.5)

-- We will generate 5 tiers of Replicators
for tier = 1, 5 do
    -- Calculations for stats
    local speed = speed_base * (speed_factor ^ (tier - 1))
    local energy_kw = energy_base * (energy_factor ^ (tier - 1))
    local energy_usage_str = energy_kw .. "kW"
    local pollution = pollution_base * (pollution_factor ^ (tier - 1))
    
    -- Hitbox calculations
    local size = math.max(1, math.floor(size_base + (size_addend * (tier - 1))))
    local entity_corner = size / 2
    local hitbox_corner = entity_corner - 0.2
    
    -- Pipe offset calculation (nudges pipe connection half a tile if even-sized to align with grid)
    local pipe_connector_offset = 0
    if math.floor(entity_corner) == entity_corner then
        pipe_connector_offset = -0.5
    end
    
    -- Module slots calculation
    local module_slots = math.max(0, math.floor(module_slots_base + (module_slots_addend * (tier - 1))))
    
    -- Category support
    local categories = {}
    for lower_tier = 1, tier do
        table.insert(categories, gprefix .. "replication-" .. lower_tier)
    end
    
    -- Next upgrade link
    local next_upgrade = nil
    if tier < 5 then
        local next_size = math.max(1, math.floor(size_base + (size_addend * tier)))
        if size == next_size then
            next_upgrade = gprefix .. "replicator-" .. (tier + 1)
        end
    end

    local replicator = {
        type = "assembling-machine",
        name = gprefix .. "replicator-" .. tier,
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-" .. tier .. ".png",
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.2, result = gprefix .. "replicator-" .. tier },
        fast_replaceable_group = gprefix .. "replicator",
        next_upgrade = next_upgrade,
        max_health = 150 + (tier * 50),
        resistances = {
            {
                type = "fire",
                percent = 40 + (tier * 10)
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -hitbox_corner, -hitbox_corner }, { hitbox_corner, hitbox_corner } },
        selection_box = { { -entity_corner, -entity_corner }, { entity_corner, entity_corner } },
        
        -- Native C++ replication processing
        crafting_categories = categories,
        crafting_speed = speed,
        
        -- High power consumption (GW/MW range)
        energy_usage = energy_usage_str,
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input",
            emissions_per_second = pollution / 60
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
                        position = { pipe_connector_offset, hitbox_corner }, -- STRICTLY INSIDE THE BOUNDING BOX
                        direction = defines.direction.south,
                    }
                }
            }
        },

        -- Graphics and sounds
        graphics_set = {
            animation = {
                filename = "__dark-matter-replicators-reborn__/graphics/entity/replicator-" .. tier .. ".png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                scale = entity_corner * 2 / 3,
                shift = { entity_corner * 0.4 / 3, entity_corner * 0.1 }
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
        
        module_slots = module_slots,
        allowed_effects = { "consumption", "speed", "productivity", "quality", "pollution" }
    }

    -- Space platform and Space Exploration compatibility
    if helpers.get_startup_setting("replication-in-space", false) then
        replicator.se_allow_in_space = true
    end

    data:extend({
        -- Item Prototype
        {
            type = "item",
            name = gprefix .. "replicator-" .. tier,
            icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-" .. tier .. ".png",
            icon_size = 64,
            subgroup = "production-machine",
            order = "b" .. tier,
            place_result = gprefix .. "replicator-" .. tier,
            stack_size = 50
        },
        -- Recipe Category
        {
            type = "recipe-category",
            name = gprefix .. "replication-" .. tier
        },
        -- Replicator Entity
        replicator
    })
end

-- 6. Replication Lab Entity
data:extend({
    {
        type = "item",
        name = gprefix .. "replication-lab",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replication-lab.png",
        icon_size = 64,
        subgroup = gprefix .. "replicators",
        order = "a",
        place_result = gprefix .. "replication-lab",
        stack_size = 50
    },
    {
        type = "lab",
        name = gprefix .. "replication-lab",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replication-lab.png",
        icon_size = 64,
        flags = { "placeable-player", "player-creation" },
        minable = { mining_time = 1, result = gprefix .. "replication-lab" },
        max_health = 150,
        corpse = "big-remnants",
        dying_explosion = "big-explosion",
        collision_box = { { -1.2, -1.2 }, { 1.2, 1.2 } },
        selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } },
        light = { intensity = 0.75, size = 8 },
        on_animation = {
            filename = "__dark-matter-replicators-reborn__/graphics/entity/replication-lab.png",
            width = 113,
            height = 91,
            frame_count = 33,
            line_length = 11,
            animation_speed = 1 / 3,
            shift = { 0.2, 0.15 }
        },
        off_animation = {
            filename = "__dark-matter-replicators-reborn__/graphics/entity/replication-lab.png",
            width = 113,
            height = 91,
            frame_count = 1,
            shift = { 0.2, 0.15 }
        },
        working_sound = {
            sound = {
                filename = "__base__/sound/lab.ogg",
                volume = 0.7
            },
            apparent_volume = 1.5
        },
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input"
        },
        energy_usage = "60kW",
        inputs = {
            gprefix .. "tenemut",
            gprefix .. "dark-matter-scoop",
            gprefix .. "dark-matter-transducer",
            gprefix .. "matter-conduit"
        },
        module_slots = 2,
        allowed_module_categories = { "efficiency", "speed", "productivity" }
    }
})
