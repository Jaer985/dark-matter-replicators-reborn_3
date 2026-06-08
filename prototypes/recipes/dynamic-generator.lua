local helpers = require("lib.helpers")
local CostSolver = require("lib.cost-solver")
local TargetMapper = require("lib.target-mapper")
local gprefix = "dmrsa-"

-- Helper to layer appropriate border graphic on dynamic replication technology icons
local function get_tech_icons(name, target, tier)
    local border = "tech-device" .. tier
    if tier < 2 or tier > 5 then
        border = "tech-device2"
    end

    local subgroup = target.subgroup or ""
    local type_name = target.type or ""

    if type_name == "fluid" then
        border = "tech-chemical"
    elseif string.find(name, "ore") or string.find(subgroup, "ore") or subgroup == "raw-resource" then
        border = "tech-ore"
    elseif string.find(name, "science%-pack") then
        border = "tech-science"
    elseif string.find(name, "module") or subgroup == "module" then
        border = "tech-module"
    elseif string.find(name, "plate") or string.find(name, "alloy") then
        border = "tech-alloy"
    end

    local border_path = "__dark-matter-replicators-reborn__/graphics/icons/borders/" .. border .. ".png"

    local icons = {}
    -- Base layer: Border (128x128)
    table.insert(icons, {
        icon = border_path,
        icon_size = 128,
        scale = 1
    })

    -- Overlay layer: Item icon(s) scaled to fit in 64x64 inside 128x128 border
    if target.icons and #target.icons > 0 then
        for _, icon_spec in ipairs(target.icons) do
            local spec = helpers.deep_copy(icon_spec)
            local isize = spec.icon_size or target.icon_size or 64
            
            local current_scale = spec.scale or 1
            spec.scale = current_scale * (64 / isize)
            
            if spec.shift then
                spec.shift = { spec.shift[1] * (64 / isize), spec.shift[2] * (64 / isize) }
            end
            
            table.insert(icons, spec)
        end
    else
        local icon_path = target.icon or "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
        local isize = target.icon_size or 64
        table.insert(icons, {
            icon = icon_path,
            icon_size = isize,
            scale = 64 / isize
        })
    end

    return icons
end

local DynamicGenerator = {}

-- Main entry point to run the dynamic generation
function DynamicGenerator.generate()
    helpers.log("Starting dynamic recipe generation...")

    -- 1. Initialize solver states
    CostSolver.initialize_base_resources()
    CostSolver.build_recipe_map()
    CostSolver.build_tech_map()

    -- 2. Map potential replication targets via target-mapper
    local targets = TargetMapper.get_potential_replication_targets()
    local recipe_count = 0
    local derepl_count = 0
    local tech_count = 0

    -- Retrieve settings safely
    local fluid_qty = helpers.get_startup_setting("replication-fluid-quantity", 25)
    local return_ratio = 0 -- Disabled since replication requires no dark-matter input
    local use_individual_techs = helpers.get_startup_setting("dmrsa-individual-techs", true)

    -- Track recipes to unlock via baseline replication technologies (fallback when individual techs is disabled)
    local baseline_unlocks = {
        [1] = {},
        [2] = {},
        [3] = {},
        [4] = {},
        [5] = {}
    }

    -- Track recipes to unlock via planetary technologies (fallback when individual techs is disabled)
    local planetary_unlocks = {
        ["vulcanus"] = {},
        ["fulgora"] = {},
        ["gleba"] = {},
        ["aquilo"] = {}
    }

    for name, target in pairs(targets) do
        -- 3. Solve replication cost and tier recursively
        local solved = CostSolver.solve_cost(name)
        if solved then
            local dark_matter_cost = solved.dark_matter
            local time_cost = solved.time
            local tier = solved.tier or 1

            -- Limit tier to max 5
            if tier > 5 then tier = 5 end
            if tier < 1 then tier = 1 end

            -- Base category
            local category = gprefix .. "replication-" .. tier
            local planet_suffix = nil

            -- 4. Apply advanced Space Age planetary classification
            if mods["space-age"] then
                local item_proto = data.raw[target.type] and data.raw[target.type][name]
                local is_organic = false
                if item_proto then
                    if item_proto.spoil_ticks or item_proto.spoil_to or item_proto.spoil_result then
                        is_organic = true
                    end
                end

                if is_organic or string.find(name, "yumako") or string.find(name, "jellynut") or name == "spoiled-organic-substrate" or name == "agricultural-science-pack" or name == "nutrients" then
                    category = gprefix .. "replication-gleba"
                    planet_suffix = "gleba"
                elseif string.find(name, "tungsten") or name == "calcite" or name == "metallurgic-science-pack" or string.find(name, "molten%-") then
                    category = gprefix .. "replication-vulcanus"
                    planet_suffix = "vulcanus"
                elseif string.find(name, "holmium") or name == "superconducting-cable" or name == "electromagnetic-science-pack" then
                    category = gprefix .. "replication-fulgora"
                    planet_suffix = "fulgora"
                elseif name == "ice" or string.find(name, "lithium") or name == "fluoroketone" or name == "cryogenic-science-pack" then
                    category = gprefix .. "replication-aquilo"
                    planet_suffix = "aquilo"
                end
            end

            -- Adjust for fluid scale
            local result_amount = 1
            if target.type == "fluid" then
                result_amount = fluid_qty
                dark_matter_cost = dark_matter_cost * fluid_qty
                time_cost = time_cost * math.sqrt(fluid_qty)
            end

            -- Ensure minimum and maximum safety bounds
            dark_matter_cost = math.max(1, math.ceil(dark_matter_cost))
            if dark_matter_cost > 60000 then
                dark_matter_cost = 60000
            end
            time_cost = math.max(0.1, tonumber(string.format("%.2f", time_cost)))

            -- 5. Construct unique replication recipe
            local recipe_name = gprefix .. "repl-" .. name
            local repl_recipe = {
                type = "recipe",
                name = recipe_name,
                localised_name = {
                    "recipe-name.dmrsa-replication-recipe",
                    {
                        "?",
                        { "item-name." .. name },
                        { "entity-name." .. name },
                        { "fluid-name." .. name },
                        name
                    }
                },
                category = category,
                energy_required = dark_matter_cost,
                ingredients = {},
                results = {
                    { type = target.type == "fluid" and "fluid" or "item", name = name, amount = result_amount }
                },
                enabled = false,
                hidden = false,
                subgroup = planet_suffix and (gprefix .. "replication-resources") or (gprefix .. "replication-tier-" .. tier),
                order = "z[" .. name .. "]"
            }

            if name == "promethium-science-pack" then
                repl_recipe.surface_conditions = {
                    { property = "gravity", max = 0 }
                }
            end

            -- Safely extend recipe
            data:extend({ repl_recipe })
            recipe_count = recipe_count + 1

            -- 6. Construct corresponding de-replication recipe
            local derepl_recipe_name = gprefix .. "derepl-" .. name
            local input_qty = 1
            local output_qty = 0
            if return_ratio > 0 then
                -- raw dark matter return per single item/fluid unit
                local r_dm = (dark_matter_cost / result_amount) * return_ratio
                local found = false
                for m = 1, 10 do
                    local val = r_dm * m
                    if math.abs(val - math.floor(val + 0.5)) < 0.01 then
                        input_qty = m
                        output_qty = math.floor(val + 0.5)
                        if output_qty >= 1 then
                            found = true
                            break
                        end
                    end
                end
                if not found then
                    -- Fallback: scale input until output is at least 1
                    input_qty = math.ceil(1 / r_dm)
                    output_qty = math.floor(r_dm * input_qty)
                    if output_qty < 1 then output_qty = 1 end
                end

                local derepl_recipe = {
                    type = "recipe",
                    name = derepl_recipe_name,
                    localised_name = {
                        "recipe-name.dmrsa-derepl-recipe",
                        {
                            "?",
                            { "item-name." .. name },
                            { "entity-name." .. name },
                            { "fluid-name." .. name },
                            name
                        }
                    },
                    category = category, -- Processed in the same machine tier/planet
                    energy_required = 0.5, -- Base disassembling time
                    ingredients = {
                        { type = target.type == "fluid" and "fluid" or "item", name = name, amount = target.type == "fluid" and (input_qty * fluid_qty) or input_qty }
                    },
                    results = {
                        { type = "item", name = gprefix .. "dark-matter", amount = output_qty }
                    },
                    enabled = false,
                    hidden = false,
                    subgroup = planet_suffix and (gprefix .. "replication-resources") or (gprefix .. "replication-tier-" .. tier),
                    order = "y[" .. name .. "]"
                }

                data:extend({ derepl_recipe })
                derepl_count = derepl_count + 1
            end

            -- 7. Technology unlock binding
            if use_individual_techs then
                -- Define a technology for every item
                local tech_name = gprefix .. "tech-repl-" .. name .. "-tech"
                local tech_effects = {
                    { type = "unlock-recipe", recipe = recipe_name }
                }
                if return_ratio > 0 and output_qty > 0 then
                    table.insert(tech_effects, { type = "unlock-recipe", recipe = derepl_recipe_name })
                end

                -- Prerequisites mapping
                local prerequisites = {}
                local function add_prereq(tbl, p)
                    for _, v in ipairs(tbl) do
                        if v == p then return end
                    end
                    table.insert(tbl, p)
                end

                -- A. Base machine unlocks
                if planet_suffix then
                    add_prereq(prerequisites, gprefix .. "replication-" .. planet_suffix .. "-tech")
                else
                    if mods["space-age"] and tier == 3 then
                        add_prereq(prerequisites, gprefix .. "replication-2")
                    else
                        add_prereq(prerequisites, gprefix .. "replication-" .. tier)
                    end
                end

                -- B. Original item unlocks
                local original_recipe = data.raw.recipe[name]
                if original_recipe then
                    local recipe_obj = CostSolver.recipe_map[name]
                    if recipe_obj then
                        local original_tech = CostSolver.recipe_tech_map[recipe_obj.name]
                        if original_tech then
                            add_prereq(prerequisites, original_tech.name)
                        end
                    end
                end

                -- Research Materials using custom intermediate products
                local research_packs = {}
                if tier == 1 then
                    table.insert(research_packs, { gprefix .. "tenemut", 1 })
                elseif tier == 2 then
                    table.insert(research_packs, { gprefix .. "dark-matter-scoop", 1 })
                elseif tier == 3 then
                    table.insert(research_packs, { gprefix .. "dark-matter-transducer", 1 })
                elseif tier == 4 then
                    table.insert(research_packs, { gprefix .. "matter-conduit", 1 })
                elseif tier == 5 then
                    table.insert(research_packs, { gprefix .. "matter-conduit", 1 })
                    if planet_suffix == "aquilo" then
                        table.insert(research_packs, { "cryogenic-science-pack", 1 })
                    end
                end

                -- Planet Specific science add-on
                if planet_suffix == "vulcanus" then
                    table.insert(research_packs, { "metallurgic-science-pack", 1 })
                elseif planet_suffix == "fulgora" then
                    table.insert(research_packs, { "electromagnetic-science-pack", 1 })
                elseif planet_suffix == "gleba" then
                    table.insert(research_packs, { "agricultural-science-pack", 1 })
                end

                -- Scale research cost based on settings
                local repetitions = 10 * tier
                local multiplier = helpers.get_startup_setting("replresearch-item-multiplier", 25)
                local reps_count = math.max(1, math.ceil(repetitions * (multiplier / 25)))

                local tech_proto = {
                    type = "technology",
                    name = tech_name,
                    localised_name = {
                        "technology-name.dmrsa-repl-tech",
                        {
                            "?",
                            { "item-name." .. name },
                            { "entity-name." .. name },
                            { "fluid-name." .. name },
                            name
                        }
                    },
                    localised_description = {
                        "technology-description.dmrsa-repl-tech",
                        {
                            "?",
                            { "item-name." .. name },
                            { "entity-name." .. name },
                            { "fluid-name." .. name },
                            name
                        }
                    },
                    effects = tech_effects,
                    prerequisites = prerequisites,
                    unit = {
                        count = reps_count,
                        ingredients = research_packs,
                        time = helpers.get_startup_setting("replresearch-item-time", 5)
                    },
                    order = "a-r-" .. tier .. "[" .. name .. "]"
                }

                -- Layer custom border on technology icons
                tech_proto.icons = get_tech_icons(name, target, tier)
                tech_proto.icon_size = 128

                data:extend({ tech_proto })
                tech_count = tech_count + 1
            else
                -- Fallback traditional tech binding: attach to original or baseline techs
                local original_recipe = data.raw.recipe[name]
                local unlocked_by_tech = false

                if original_recipe then
                    local recipe_obj = CostSolver.recipe_map[name]
                    if recipe_obj then
                        local original_tech = CostSolver.recipe_tech_map[recipe_obj.name]
                        if original_tech then
                            original_tech.effects = original_tech.effects or {}
                            table.insert(original_tech.effects, { type = "unlock-recipe", recipe = recipe_name })
                            if return_ratio > 0 and output_qty > 0 then
                                table.insert(original_tech.effects, { type = "unlock-recipe", recipe = derepl_recipe_name })
                            end
                            unlocked_by_tech = true
                        end
                    end
                end

                -- If it has no original tech unlock, link it to the baseline/planetary techs
                if not unlocked_by_tech then
                    if planet_suffix then
                        table.insert(planetary_unlocks[planet_suffix], recipe_name)
                        if return_ratio > 0 and output_qty > 0 then
                            table.insert(planetary_unlocks[planet_suffix], derepl_recipe_name)
                        end
                    else
                        table.insert(baseline_unlocks[tier], recipe_name)
                        if return_ratio > 0 and output_qty > 0 then
                            table.insert(baseline_unlocks[tier], derepl_recipe_name)
                        end
                    end
                end
            end
        end
    end

    helpers.log("Dynamically compiled: " .. recipe_count .. " replication recipes, " .. derepl_count .. " de-replication recipes, and " .. tech_count .. " technology nodes.")
    return baseline_unlocks, planetary_unlocks
end

return DynamicGenerator
