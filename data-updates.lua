require("defines")
local helpers = require("lib.helpers")

-- v3.7.0 (A6): Dynamic recipe generation MOVED to data-final-fixes.lua.
-- It must run AFTER overhaul mods (Bob's, Angel's, K2) finish defining their
-- recipes and unlock-recipe tech effects — in data-updates the recipe_tech_map
-- was incomplete, silently skipping original-tech prereqs (118 items with
-- Bob's) and under-tiering 367 items. See data-final-fixes.lua PASS 0.

-- 1. Configure planet autoplace spawning for Tenemut
-- v4.3: skipped entirely in "Synthesis only" mode — no autoplace spec, no
-- autoplace-control and no map-gen injection means nothing can spawn.
local spawning_planet_setting = settings.startup["tenemut-spawning-planet"]
if helpers.tenemut_worldgen_enabled() and spawning_planet_setting and spawning_planet_setting.value then
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
        helpers.warn("Unknown planet selected as starting planet: " .. default_planet)
    end
end

-- 2. Map autoplace for other Space Age planets if configured
-- v4.3: same worldgen gate as block 1 (synthesis-only places nothing).
if helpers.tenemut_worldgen_enabled() and mods["space-age"] then
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

-- 3. Surface conditions and gravity restrictions (No replication in zero-gravity space unless configured)
if mods["space-age"] then
    local space_repl_setting = settings.startup["replication-in-space"]
    if space_repl_setting and not space_repl_setting.value then
        -- Enforce gravity for the lab
        local lab = data.raw.lab[gprefix .. "replication-lab"]
        if lab then
            lab.surface_conditions = lab.surface_conditions or {}
            table.insert(lab.surface_conditions, { property = "gravity", min = 0.1 })
        end

        -- Enforce gravity for all Replicator entities (Tiers 1-3 always require gravity; Tiers 4-5 bypass if Dyson Sphere mod is active)
        local has_dyson = mods["slp-dyson-sphere-reworked"] ~= nil
        for i = 1, 5 do
            local assembler = data.raw["assembling-machine"][gprefix .. "replicator-" .. i]
            if assembler then
                if not (has_dyson and (i == 4 or i == 5)) then
                    assembler.surface_conditions = assembler.surface_conditions or {}
                    table.insert(assembler.surface_conditions, { property = "gravity", min = 0.1 })
                end
            end
        end

        -- Enforce gravity for the Dark Matter Synthesizer (v4.3) — same rule as
        -- the other DMR machinery when replication in space is disabled.
        local synthesizer = data.raw["assembling-machine"][gprefix .. "tenemut-synthesizer"]
        if synthesizer then
            synthesizer.surface_conditions = synthesizer.surface_conditions or {}
            table.insert(synthesizer.surface_conditions, { property = "gravity", min = 0.1 })
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