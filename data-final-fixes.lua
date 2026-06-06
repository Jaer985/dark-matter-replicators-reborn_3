require("defines")
local helpers = require("lib.helpers")

-- 1. Gather all actual registered item and fluid names
local item_prototype_names = {}
local item_classes = {
    "item", "ammo", "armor", "gun", "capsule", "tool", "module",
    "item-with-entity-data", "item-with-tags", "spidertron-remote",
    "space-platform-starter"
}

for _, class in ipairs(item_classes) do
    if data.raw[class] then
        for k in pairs(data.raw[class]) do
            item_prototype_names[k] = true
        end
    end
end

if data.raw.fluid then
    for k in pairs(data.raw.fluid) do
        item_prototype_names[k] = true
    end
end

-- 2. Verify all dynamically generated replication recipes
local recipes = data.raw.recipe
if recipes then
    for rname, recipe in pairs(recipes) do
        if string.find(rname, "^" .. gprefix .. "repl-") then
            local is_valid = true

            -- Verify ingredients exist
            local ingredients = recipe.ingredients
            if ingredients then
                for _, ing in ipairs(ingredients) do
                    local name = ing.name or ing[1]
                    if name and not item_prototype_names[name] then
                        is_valid = false
                        helpers.log("Removing replication recipe " .. rname .. " due to missing ingredient: " .. name)
                        break
                    end
                end
            end

            -- Verify results exist
            if is_valid then
                local results = recipe.results
                if results then
                    for _, res in ipairs(results) do
                        local name = res.name or res[1]
                        if name and not item_prototype_names[name] then
                            is_valid = false
                            helpers.log("Removing replication recipe " .. rname .. " due to missing product: " .. name)
                            break
                        end
                    end
                end
            end

            -- Delete recipe from registry if invalid
            if not is_valid then
                recipes[rname] = nil

                local item_name = string.sub(rname, string.len(gprefix .. "repl-") + 1)
                local derepl_name = gprefix .. "derepl-" .. item_name
                if recipes[derepl_name] then
                    recipes[derepl_name] = nil
                end

                local tech_name = gprefix .. "tech-repl-" .. item_name .. "-tech"
                if data.raw.technology and data.raw.technology[tech_name] then
                    data.raw.technology[tech_name] = nil
                end

                -- Also remove from unlock technology effects
                if data.raw.technology then
                    for _, tech in pairs(data.raw.technology) do
                        if tech.effects then
                            local cleaned_effects = {}
                            for _, effect in ipairs(tech.effects) do
                                if effect.recipe ~= rname and effect.recipe ~= derepl_name then
                                    table.insert(cleaned_effects, effect)
                                end
                            end
                            tech.effects = cleaned_effects
                        end
                    end
                end
            end
        end
    end
end

-- 3. Clean up Replication Lab input items
local lab = data.raw.lab[gprefix .. "replication-lab"]
if lab and lab.inputs then
    local cleaned_inputs = {}
    for _, input in ipairs(lab.inputs) do
        if item_prototype_names[input] then
            table.insert(cleaned_inputs, input)
        end
    end
    lab.inputs = cleaned_inputs
end

-- 4. BULLETPROOF SAFETY: Remove any technology prerequisites that do not actually exist in the registry
local techs = data.raw.technology
if techs then
    for tech_name, tech in pairs(techs) do
        if string.find(tech_name, "^" .. gprefix) then
            local prerequisites = tech.prerequisites
            if prerequisites then
                local cleaned_prereqs = {}
                for _, prereq in ipairs(prerequisites) do
                    if techs[prereq] then
                        table.insert(cleaned_prereqs, prereq)
                    else
                        helpers.log("Removed missing prerequisite '" .. prereq .. "' from technology '" .. tech_name .. "'")
                    end
                end
                tech.prerequisites = cleaned_prereqs
            end
        end
    end
end
