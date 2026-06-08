local helpers = require("lib.helpers")

local CostSolver = {}

local BASE_RESOURCE_COSTS = {
    ["iron-ore"] = { dark_matter = 1.0, time = 1.0, tier = 1 },
    ["copper-ore"] = { dark_matter = 1.0, time = 1.0, tier = 1 },
    ["coal"] = { dark_matter = 1.0, time = 1.0, tier = 1 },
    ["stone"] = { dark_matter = 0.8, time = 0.8, tier = 1 },
    ["wood"] = { dark_matter = 0.5, time = 0.5, tier = 1 },
    ["water"] = { dark_matter = 0.01, time = 0.01, tier = 1 },
    ["crude-oil"] = { dark_matter = 0.1, time = 0.1, tier = 1 },
    ["uranium-ore"] = { dark_matter = 5.0, time = 5.0, tier = 3 },
    
    -- Space Age Specific Ores/Plants
    ["calcite"] = { dark_matter = 1.2, time = 1.2, tier = 2 },
    ["scrap"] = { dark_matter = 0.6, time = 0.6, tier = 1 },
    ["holmium-ore"] = { dark_matter = 4.0, time = 4.0, tier = 3 },
    ["tungsten-ore"] = { dark_matter = 4.0, time = 4.0, tier = 3 },
    ["jellynut"] = { dark_matter = 2.0, time = 2.0, tier = 3 },
    ["yumako"] = { dark_matter = 2.0, time = 2.0, tier = 3 },
    ["spoiled-organic-substrate"] = { dark_matter = 0.5, time = 0.5, tier = 3 },
    ["metallic-asteroid-chunk"] = { dark_matter = 2.0, time = 2.0, tier = 4 },
    ["carbonaceous-asteroid-chunk"] = { dark_matter = 2.0, time = 2.0, tier = 4 },
    ["oxide-asteroid-chunk"] = { dark_matter = 2.0, time = 2.0, tier = 4 },
    ["promethium-ore"] = { dark_matter = 20.0, time = 20.0, tier = 5 },
    ["promethium-science-pack"] = { dark_matter = 50.0, time = 50.0, tier = 5 }
}

local recipe_map = {}
local recipe_tech_map = {}
local solved_cache = {}

-- Scans all resource entities to discover dynamic base resource products (e.g. from mods)
function CostSolver.initialize_base_resources()
    local resources = data.raw.resource
    if not resources then return end

    for _, res in pairs(resources) do
        if res.minable then
            local results = res.minable.results
            if not results and res.minable.result then
                results = { { name = res.minable.result, amount = 1 } }
            end

            if results and #results > 0 then
                for _, result in ipairs(results) do
                    local name = result.name or result[1]
                    if name and not BASE_RESOURCE_COSTS[name] then
                        -- Detect if it requires advanced fluid mining (e.g. uranium, holmium)
                        local requires_fluid = res.minable.required_fluid ~= nil
                        local base_tier = requires_fluid and 3 or 1
                        local base_cost = requires_fluid and 4.0 or 1.5

                        BASE_RESOURCE_COSTS[name] = {
                            dark_matter = base_cost,
                            time = base_cost,
                            tier = base_tier
                        }
                        helpers.log("Dynamically mapped base resource: " .. name .. " (Tier " .. base_tier .. ", Cost " .. base_cost .. ")")
                    end
                end
            end
        end
    end
end

-- Builds recipe mapping for quick product -> recipe lookups
function CostSolver.build_recipe_map()
    if not data or not data.raw or not data.raw.recipe then return end

    for name, recipe in pairs(data.raw.recipe) do
        -- EXCLUDE recycling, unbarreling, and cyclic byproduct recipes to prevent massive cost infinite loops
        local is_valid_recipe = true
        if recipe.category == "recycling" or string.find(name, "%-recycling$") then
            is_valid_recipe = false
        end
        if recipe.category == "barreling" or string.find(name, "empty%-") or string.find(name, "%-unbarrel") then
            is_valid_recipe = false
        end

        if is_valid_recipe then
            local results = {}
            if recipe.results then
                results = recipe.results
            elseif recipe.result then
                local count = recipe.result_count or 1
                results = { { name = recipe.result, amount = count, type = "item" } }
            elseif recipe.normal and recipe.normal.results then
                results = recipe.normal.results
            elseif recipe.normal and recipe.normal.result then
                local count = recipe.normal.result_count or 1
                results = { { name = recipe.normal.result, amount = count, type = "item" } }
            end

            if #results > 0 then
                for _, product in ipairs(results) do
                    local product_name = product.name or product[1]
                    if product_name then
                        -- Prefer simpler recipes if duplicates exist
                        if not recipe_map[product_name] then
                            recipe_map[product_name] = recipe
                        else
                            local current_recipe = recipe_map[product_name]
                            local current_ing_count = current_recipe.ingredients and #current_recipe.ingredients or 99
                            local new_ing_count = recipe.ingredients and #recipe.ingredients or 99
                            if new_ing_count > 0 and new_ing_count < current_ing_count then
                                recipe_map[product_name] = recipe
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Builds technology unlock mapping to determine item tiers
function CostSolver.build_tech_map()
    local techs = data.raw.technology
    if not techs then return end

    for tech_name, tech in pairs(techs) do
        local effects = tech.effects
        if effects then
            for _, effect in ipairs(effects) do
                if effect.type == "unlock-recipe" and effect.recipe then
                    recipe_tech_map[effect.recipe] = tech
                end
            end
        end
    end
end

-- Classifies technology science requirements into tier levels
function CostSolver.get_tier_from_tech(tech)
    if not tech or not tech.unit or not tech.unit.ingredients then return 1 end
    
    local max_tier = 1
    for _, ingredient in ipairs(tech.unit.ingredients) do
        local name = ingredient.name or ingredient[1]
        if name == "chemical-science-pack" then
            max_tier = math.max(max_tier, 2)
        elseif name == "metallurgic-science-pack" or name == "electromagnetic-science-pack" or name == "agricultural-science-pack" then
            max_tier = math.max(max_tier, 3)
        elseif name == "production-science-pack" or name == "utility-science-pack" then
            max_tier = math.max(max_tier, 4)
        elseif name == "space-science-pack" or name == "cryogenic-science-pack" or name == "promethium-science-pack" then
            max_tier = math.max(max_tier, 5)
        end
    end
    return max_tier
end

-- Safely calculates replication cost recursively with cycle detection
function CostSolver.solve_cost(name, visited, is_root)
    if is_root == nil then is_root = true end

    -- 1. Check cache
    if solved_cache[name] then
        local cached = solved_cache[name]
        if is_root then
            local method = helpers.get_startup_setting("dmrsa-cost-calculation-method", "Raw Ingredients (Flat)")
            if method == "Raw Ingredients (Flat)" then
                local penalty = helpers.get_startup_setting("replication-penalty", 0.5)
                return {
                    dark_matter = cached.dark_matter * (1.0 + penalty),
                    time = cached.time * (1.0 + penalty * 0.5),
                    tier = cached.tier
                }
            end
        end
        return cached
    end

    -- 2. Base resources check
    if BASE_RESOURCE_COSTS[name] then
        return BASE_RESOURCE_COSTS[name]
    end

    -- 3. Cycle prevention
    visited = visited or {}
    if visited[name] then
        -- Return moderate fallback to break the loop without compounding values
        return { dark_matter = 5.0, time = 2.0, tier = 1 }
    end
    visited[name] = true

    -- 4. Find recipe
    local recipe = recipe_map[name]
    if not recipe then
        -- Unknown item with no recipe, return fallback
        return { dark_matter = 10.0, time = 3.0, tier = 2 }
    end

    -- Parse ingredients safely
    local ingredients = recipe.ingredients
    if recipe.normal and recipe.normal.ingredients then
        ingredients = recipe.normal.ingredients
    end

    if not ingredients or #ingredients == 0 then
        return { dark_matter = 1.0, time = 1.0, tier = 1 }
    end

    local total_dm = 0
    local total_time = 0.5 -- Base crafting overhead
    local max_tier = 1

    -- Sum up ingredient costs recursively
    for _, ing in ipairs(ingredients) do
        local ing_name = ing.name or ing[1]
        local ing_amount = ing.amount or ing[2] or 1
        if ing_name then
            -- Copy visited table to prevent siblings from interfering with cycle state
            local local_visited = helpers.deep_copy(visited)
            local solved = CostSolver.solve_cost(ing_name, local_visited, false)
            total_dm = total_dm + (solved.dark_matter * ing_amount)
            total_time = total_time + (solved.time * ing_amount * 0.1)
            max_tier = math.max(max_tier, solved.tier)
        end
    end

    -- Extract result amount
    local result_amount = 1
    local results = recipe.results
    if recipe.normal and recipe.normal.results then
        results = recipe.normal.results
    end

    if results then
        for _, res in ipairs(results) do
            if (res.name or res[1]) == name then
                result_amount = res.amount or res[2] or 1
                break
            end
        end
    elseif recipe.result_count then
        result_amount = recipe.result_count
    elseif recipe.normal and recipe.normal.result_count then
        result_amount = recipe.normal.result_count
    end

    if result_amount <= 0 then result_amount = 1 end

    -- Normalize per single item
    local final_dm = total_dm / result_amount
    local final_time = total_time / result_amount

    -- Determine tier based on tech unlock
    local unlock_tech = recipe_tech_map[recipe.name]
    if unlock_tech then
        local tech_tier = CostSolver.get_tier_from_tech(unlock_tech)
        max_tier = math.max(max_tier, tech_tier)
    end

    -- Clean up cycle tracker
    visited[name] = nil

    local method = helpers.get_startup_setting("dmrsa-cost-calculation-method", "Raw Ingredients (Flat)")
    local penalty = helpers.get_startup_setting("replication-penalty", 0.5)

    local cached_dm = final_dm
    local cached_time = final_time

    if method == "Recursive Steps (Compounding)" then
        -- Apply thermodynamic efficiency loss (Replication Penalty) at each step
        cached_dm = final_dm * (1.0 + penalty)
        cached_time = final_time * (1.0 + penalty * 0.5)
    end

    local result = {
        dark_matter = cached_dm,
        time = cached_time,
        tier = max_tier
    }

    -- Cache result
    solved_cache[name] = result

    if is_root and method == "Raw Ingredients (Flat)" then
        -- Apply thermodynamic efficiency loss (Replication Penalty) once at the end
        return {
            dark_matter = cached_dm * (1.0 + penalty),
            time = cached_time * (1.0 + penalty * 0.5),
            tier = max_tier
        }
    end

    return result
end

CostSolver.recipe_map = recipe_map
CostSolver.recipe_tech_map = recipe_tech_map

return CostSolver
