local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local TargetMapper = {}

-- Helper to check if a flag exists in a table of flags
local function has_flag(flags_table, search_flag)
    if not flags_table or type(flags_table) ~= "table" then return false end
    for _, flag in ipairs(flags_table) do
        if flag == search_flag then
            return true
        end
    end
    return false
end

-- Safely maps out all potential replication targets
function TargetMapper.get_potential_replication_targets()
    local targets = {}
    local item_categories = {
        "item", "ammo", "armor", "gun", "capsule", "tool", "module",
        "item-with-entity-data", "item-with-tags", "spidertron-remote",
        "space-platform-starter"
    }

    -- 1. Safely iterate over each item category in data.raw
    for _, category in ipairs(item_categories) do
        local registry = data.raw[category]
        if registry then
            for name, item in pairs(registry) do
                local is_valid = true

                -- Prevent self-replication/looping of mod items
                if string.sub(name, 1, string.len(gprefix)) == gprefix then
                    is_valid = false
                end

                -- Filter out hidden items (whitelist specific asteroid chunks)
                if is_valid and (item.hidden or (item.flags and has_flag(item.flags, "hidden"))) then
                    if name ~= "metallic-asteroid-chunk" and name ~= "carbonaceous-asteroid-chunk" and name ~= "oxide-asteroid-chunk" then
                        is_valid = false
                    end
                end

                -- Ensure item actually exists in registry and has valid properties
                if is_valid then
                    targets[name] = {
                        name = name,
                        type = category,
                        subgroup = item.subgroup or "other",
                        stack_size = item.stack_size or 1,
                        icon = item.icon,
                        icons = item.icons,
                        icon_size = item.icon_size,
                        icon_mipmaps = item.icon_mipmaps
                    }
                end
            end
        end
    end

    -- 2. Include fluids if fluid replication is allowed
    local fluids = data.raw.fluid
    if fluids then
        for name, fluid in pairs(fluids) do
            if string.sub(name, 1, string.len(gprefix)) ~= gprefix and not fluid.hidden then
                targets[name] = {
                    name = name,
                    type = "fluid",
                    subgroup = fluid.subgroup or "fluid",
                    icon = fluid.icon,
                    icons = fluid.icons,
                    icon_size = fluid.icon_size,
                    icon_mipmaps = fluid.icon_mipmaps
                }
            end
        end
    end

    return targets
end

return TargetMapper
