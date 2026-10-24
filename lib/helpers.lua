local helpers = {}

-- Log level definitions (higher number = more verbose)
helpers.LOG_LEVELS = {
    none = 0,
    error = 1,
    warn = 2,
    info = 3,
    debug = 4
}

-- Internal: check if a message at the given level should be emitted
function helpers._should_log(level)
    local current_level_name = helpers.get_startup_setting("dmrsa-log-level", "warn")
    local current_priority = helpers.LOG_LEVELS[current_level_name] or helpers.LOG_LEVELS.warn
    local msg_priority = helpers.LOG_LEVELS[level] or helpers.LOG_LEVELS.info
    return msg_priority <= current_priority
end

-- Level-aware logging (replaces the old unconditional log)
function helpers.log(message, level)
    level = level or "info"
    if helpers._should_log(level) then
        log("[DarkMatterReplicators] " .. tostring(message))
    end
end

-- Convenience aliases for each log level
function helpers.error(message)
    helpers.log(message, "error")
end

function helpers.warn(message)
    helpers.log(message, "warn")
end

function helpers.info(message)
    helpers.log(message, "info")
end

function helpers.debug(message)
    helpers.log(message, "debug")
end

-- 1. Settings parsing with short-circuit evaluation
function helpers.get_startup_setting(name, default_value)
    if settings and settings.startup and settings.startup[name] and settings.startup[name].value ~= nil then
        return settings.startup[name].value
    end
    return default_value
end

-- 1b. Tenemut source (v4.3) — single source of truth for the three modes of
-- the `dmrsa-tenemut-source` startup setting:
--   "Ore patches"            → worldgen ore, no synthesizer
--   "Ore patches + synthesis"→ worldgen ore AND synthesizer
--   "Synthesis only"         → no worldgen ore, synthesizer only
-- Both queries are additive and default-safe: an unknown/absent value behaves
-- exactly like the historical default ("Ore patches").
local TENEMUT_SOURCE_VALUES = {
    ["Ore patches"] = true,
    ["Ore patches + synthesis"] = true,
    ["Synthesis only"] = true,
}

function helpers.get_tenemut_source()
    local value = helpers.get_startup_setting("dmrsa-tenemut-source", "Ore patches")
    if type(value) ~= "string" or not TENEMUT_SOURCE_VALUES[value] then
        return "Ore patches"
    end
    return value
end

-- True when tenemut ore may be placed by the map generator (autoplace spec,
-- autoplace-control and the planet map-gen injection all depend on this).
function helpers.tenemut_worldgen_enabled()
    return helpers.get_tenemut_source() ~= "Synthesis only"
end

-- True when the Dark Matter Synthesizer (machine + tech + recipes) exists.
function helpers.tenemut_synthesis_enabled()
    return helpers.get_tenemut_source() ~= "Ore patches"
end

-- True when replication techs require the DMR material pack of their tier.
-- v4.3: `dmrsa-tenemut-research-required` (default true).
function helpers.dmr_research_pack_required()
    return helpers.get_startup_setting("dmrsa-tenemut-research-required", true) ~= false
end

-- 2. Research difficulty — single source of truth (v3.7.0).
-- One table defines ALL THREE axes per difficulty so they always match:
--   cost       = research repetition multiplier (replaces replresearch-item-multiplier)
--   time       = research time per tech in seconds (replaces replresearch-item-time)
--   cap        = max replication recipe crafting time (the old hard 600s cap)
--   replic_mult= replication recipe time multiplier (v4.2: difficulty also
--                scales the actual replication times: Easy 1.0 / Medium 1.5 /
--                High 2.0 / Very Hard 3.0)
-- Easy (Fast) reads the player's replresearch-* settings (historical default
-- 25 cost / 5s time / 600s cap). Harder levels use fixed values from the table.
function helpers.get_research_difficulty_values()
    local difficulty = helpers.get_startup_setting("dmrsa-research-difficulty", "Easy (Fast)")
    if difficulty == "Medium" then
        return { cost = 50, time = 15, cap = 1000, replic_mult = 1.5 }
    elseif difficulty == "High" then
        return { cost = 100, time = 30, cap = 1800, replic_mult = 2.0 }
    elseif difficulty == "Very Hard" then
        return { cost = 200, time = 45, cap = 3200, replic_mult = 3.0 }
    end
    -- Easy (Fast): historical behavior preserved, player settings respected
    return {
        cost = helpers.get_startup_setting("replresearch-item-multiplier", 25),
        time = helpers.get_startup_setting("replresearch-item-time", 5),
        cap = 600,
        replic_mult = 1.0
    }
end

-- Backward-compat alias: returns {reps_mult, time_mult} derived from the table
-- (relative to the Easy baseline 25/5) for code that still multiplies.
function helpers.get_research_difficulty_multipliers()
    local v = helpers.get_research_difficulty_values()
    return { reps_mult = v.cost / 25, time_mult = v.time / 5 }
end

-- v3.7.0: Max replication recipe time cap per research difficulty.
-- The historical hard cap was 600s for every difficulty. Now the cap scales:
-- Easy (Fast) keeps the historical 600, then 1000 / 1800 / 3200 as the
-- difficulty rises — deep recipe chains cost more real time on harder modes,
-- while Easy stays the compactation-helper the mod is known for.
function helpers.get_replication_time_cap()
    return helpers.get_research_difficulty_values().cap
end

-- 2. Registry validation before creating recipe/tech
function helpers.item_exists(name)
    if not name or type(name) ~= "string" then return false end
    if data and data.raw then
        -- Check standard item tables
        local item_classes = {
            "item", "ammo", "armor", "gun", "capsule", "tool", "module",
            "item-with-entity-data", "item-with-tags", "spidertron-remote",
            -- v4.4.0 (B13): `space-platform-starter` is NOT a prototype
            -- registry — the Space Age starter-pack registry is
            -- `space-platform-starter-pack`, so the old literal made the
            -- starter pack invisible to item_exists() forever.
            "space-platform-starter-pack"
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

-- 6. Level-aware logging (defined at top of file)
--    Use helpers.info(), helpers.warn(), helpers.error(), helpers.debug()

return helpers
