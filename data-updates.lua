require("defines")
local helpers = require("lib.helpers")
local DynamicGenerator = require("prototypes.recipes.dynamic-generator")

-- 1. Execute dynamic recipe generation and receive baseline and planetary unlocks
local baseline_unlocks, planetary_unlocks = DynamicGenerator.generate()

-- 2. Dynamically attach baseline unlocks to their corresponding technology nodes
for tier = 1, 5 do
    local tech_name = gprefix .. "replication-" .. tier
    local tech = data.raw.technology[tech_name]
    local unlocks = baseline_unlocks[tier]

    if tech and unlocks and #unlocks > 0 then
        tech.effects = tech.effects or {}
        for _, recipe_name in ipairs(unlocks) do
            table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
        end
    elseif tier == 3 and mods["space-age"] and unlocks and #unlocks > 0 then
        -- Attach baseline Tier 3 unlocks to the three planetary technologies
        local planetary_techs = {
            gprefix .. "replication-vulcanus-tech",
            gprefix .. "replication-fulgora-tech",
            gprefix .. "replication-gleba-tech"
        }
        for _, p_tech_name in ipairs(planetary_techs) do
            local p_tech = data.raw.technology[p_tech_name]
            if p_tech then
                p_tech.effects = p_tech.effects or {}
                for _, recipe_name in ipairs(unlocks) do
                    table.insert(p_tech.effects, { type = "unlock-recipe", recipe = recipe_name })
                end
            end
        end
    end
end

-- 3. Dynamically attach planetary unlocks to their corresponding planetary technology nodes
if mods["space-age"] and planetary_unlocks then
    for planet, unlocks in pairs(planetary_unlocks) do
        local tech_name = gprefix .. "replication-" .. planet .. "-tech"
        local tech = data.raw.technology[tech_name]
        if tech and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
            end
        end
    end
end

-- 4. Configure planet autoplace spawning for Tenemut
local spawning_planet_setting = settings.startup["tenemut-spawning-planet"]
if spawning_planet_setting and spawning_planet_setting.value then
    local default_planet = string.lower(spawning_planet_setting.value)
    if data.raw.planet and data.raw.planet[default_planet] then
        local planet_def = data.raw.planet[default_planet]
        if planet_def.map_gen_settings then
            planet_def.map_gen_settings.autoplace_controls = planet_def.map_gen_settings.autoplace_controls or {}
            planet_def.map_gen_settings.autoplace_settings = planet_def.map_gen_settings.autoplace_settings or {}
            planet_def.map_gen_settings.autoplace_settings.entity = planet_def.map_gen_settings.autoplace_settings.entity or {}
            planet_def.map_gen_settings.autoplace_settings.entity.settings = planet_def.map_gen_settings.autoplace_settings.entity.settings or {}

            planet_def.map_gen_settings.autoplace_controls[gprefix .. "tenemut"] = {}
            planet_def.map_gen_settings.autoplace_settings.entity.settings[gprefix .. "tenemut"] = {}
        end
    else
        helpers.log("Unknown planet selected as starting planet: " .. default_planet)
    end
end

-- 5. Map autoplace for other Space Age planets if configured
if mods["space-age"] then
    local other_planets_setting = settings.startup["tenemut-other-planets"]
    if other_planets_setting and other_planets_setting.value ~= "None" then
        local value = other_planets_setting.value
        if data.raw.planet then
            for planet, ptbl in pairs(data.raw.planet) do
                if planet ~= "nauvis" or value == "All" then
                    if ptbl.map_gen_settings then
                        ptbl.map_gen_settings.autoplace_controls = ptbl.map_gen_settings.autoplace_controls or {}
                        ptbl.map_gen_settings.autoplace_settings = ptbl.map_gen_settings.autoplace_settings or {}
                        ptbl.map_gen_settings.autoplace_settings.entity = ptbl.map_gen_settings.autoplace_settings.entity or {}
                        ptbl.map_gen_settings.autoplace_settings.entity.settings = ptbl.map_gen_settings.autoplace_settings.entity.settings or {}

                        ptbl.map_gen_settings.autoplace_controls[gprefix .. "tenemut"] = {}
                        ptbl.map_gen_settings.autoplace_settings.entity.settings[gprefix .. "tenemut"] = {}
                    end
                end
            end
        end
    end
end

-- 6. Surface conditions and gravity restrictions (No replication in zero-gravity space unless configured)
if mods["space-age"] then
    local space_repl_setting = settings.startup["replication-in-space"]
    if space_repl_setting and not space_repl_setting.value then
        -- Enforce gravity for the lab
        local lab = data.raw.lab[gprefix .. "replication-lab"]
        if lab then
            lab.surface_conditions = lab.surface_conditions or {}
            table.insert(lab.surface_conditions, { property = "gravity", min = 0.1 })
        end

        -- Enforce gravity for all Replicator entities
        for i = 1, 5 do
            local assembler = data.raw["assembling-machine"][gprefix .. "replicator-" .. i]
            if assembler then
                assembler.surface_conditions = assembler.surface_conditions or {}
                table.insert(assembler.surface_conditions, { property = "gravity", min = 0.1 })
            end
        end

        -- Enforce gravity for specialized planetary Replicator entities
        local planetary_suffixes = { "vulcanus", "fulgora", "gleba", "aquilo" }
        for _, suffix in ipairs(planetary_suffixes) do
            local assembler = data.raw["assembling-machine"][gprefix .. "replicator-" .. suffix]
            if assembler then
                assembler.surface_conditions = assembler.surface_conditions or {}
                table.insert(assembler.surface_conditions, { property = "gravity", min = 0.1 })
            end
        end
    end
end