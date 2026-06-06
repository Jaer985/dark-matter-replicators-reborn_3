local helpers = {}

-- 1. Settings parsing with short-circuit evaluation
function helpers.get_startup_setting(name, default_value)
    if settings and settings.startup and settings.startup[name] and settings.startup[name].value ~= nil then
        return settings.startup[name].value
    end
    return default_value
end

-- 2. Registry validation before creating recipe/tech
function helpers.item_exists(name)
    if not name or type(name) ~= "string" then return false end
    if data and data.raw then
        -- Check standard item tables
        local item_classes = {
            "item", "ammo", "armor", "gun", "capsule", "tool", "module",
            "item-with-entity-data", "item-with-tags", "spidertron-remote",
            "space-platform-starter"
        }
        for _, class in ipairs(item_classes) do
            if data.raw[class] and data.raw[class][name] then
                return true
            end
        end
    end
    return false
end

function helpers.fluid_exists(name)
    if not name or type(name) ~= "string" then return false end
    if data and data.raw and data.raw.fluid and data.raw.fluid[name] then
        return true
    end
    return false
end

function helpers.resource_exists(name)
    if helpers.item_exists(name) or helpers.fluid_exists(name) then
        return true
    end
    return false
end

-- 3. Table safety validations
function helpers.is_non_empty_table(t)
    return type(t) == "table" and #t > 0
end

-- 4. Deep copy helper (for clean duplication)
function helpers.deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do
        res[helpers.deep_copy(k)] = helpers.deep_copy(v)
    end
    return res
end

-- 5. Helper to check if a flag exists in a flags list
function helpers.has_flag(flags_table, search_flag)
    if not flags_table or type(flags_table) ~= "table" then return false end
    for _, flag in ipairs(flags_table) do
        if flag == search_flag then
            return true
        end
    end
    return false
end

-- 6. Safe logging utility
function helpers.log(message)
    log("[DarkMatterReplicators] " .. tostring(message))
end

return helpers
