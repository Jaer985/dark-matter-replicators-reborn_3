local helpers = require("lib.helpers")
local CostSolver = require("lib.cost-solver")
local TargetMapper = require("lib.target-mapper")
local repltypes = require("lib.repltypes")
local ItemClass = require("lib.item-class")
local gprefix = "dmrsa-"

-- Helper to layer appropriate border graphic on dynamic replication technology icons
local function get_tech_icons(name, target, tier)
    local border = "tech-device" .. tier
    if tier < 2 then
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
            -- v3.6.0: drop mipmaps — they belong to the original icon's own
            -- rendering pipeline; copying them into a bordered 128x128 icon
            -- with a different scale misrenders (shows only top-left corner)
            -- on high-DPI / large-icon items.
            spec.icon_mipmaps = nil
            local isize = spec.icon_size or target.icon_size or 64
            if type(isize) ~= "number" or isize <= 0 then isize = 64 end
            
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
        if type(isize) ~= "number" or isize <= 0 then isize = 64 end
        table.insert(icons, {
            icon = icon_path,
            icon_size = isize,
            scale = 64 / isize
        })
    end

    return icons
end

-- Helper to determine category for grouped technologies (expanded from original repltypes)
-- Category determines BASE tier; cost-solver can still push tier HIGHER.
local function get_item_category(name, target)
    local subgroup = target.subgroup or ""
    local type_name = target.type or ""
    local item_proto = data.raw[target.type] and data.raw[target.type][name]

    -- 0. Space Age organic detection (SA spoilable items)
    if mods["space-age"] and item_proto then
        local is_organic = false
        if item_proto.spoil_ticks or item_proto.spoil_to or item_proto.spoil_result then
            is_organic = true
        end
        if is_organic or string.find(name, "yumako") or string.find(name, "jellynut") or name == "spoiled-organic-substrate" or name == "nutrients" then
            return "organic"
        end
    end

    -- 1. ORE (tier 1): directly mineable resources
    if type_name == "resource"
       or subgroup == "ore" or subgroup == "raw-resource"
       or string.find(name, "ore$") or string.find(name, "%-ore")
       or string.find(name, "ore-") then
        return "ore"
    end

    -- 2. SCIENCE (dynamic tier): science packs
    if string.find(name, "science%-pack") then
        return "science"
    end

    -- 3. FLUID → chemical (tier 3)
    if type_name == "fluid" then
        return "chemical"
    end

    -- 4. MODULE (tier 3 base; tier 4 for advanced -3 modules)
    --    Vanilla progression: speed/eff/prod module 1-2 unlock with chemical
    --    (tier 3); module 3 unlocks with space (tier 4). Splitting keeps
    --    replication mirrors vanilla instead of gating all modules to tier 5.
    if string.find(name, "module") or subgroup == "module" then
        if string.find(name, "module%-3") then
            return "module-advanced"
        end
        return "module"
    end

    -- 5. MILITARY (tier 3 base; tier 5 for endgame weapons/ammo)
    --    Basic weapons (pistol, shotgun, magazines, grenades) are early/mid
    --    game in vanilla → tier 3. Endgame ordnance (uranium, artillery,
    --    explosive rockets, cluster, nuke, spidertron) → tier 5.
    local is_military = false
    if type_name == "gun" or type_name == "ammo" or type_name == "armor"
       or type_name == "capsule" then
        is_military = true
    end
    -- Also check name patterns for weapons
    if string.find(name, "weapon") or string.find(name, "bullet")
       or string.find(name, "magazine") or string.find(name, "rocket")
       or string.find(name, "grenade") or string.find(name, "shotgun")
       or string.find(name, "rifle") or string.find(name, "cannon")
       or string.find(name, "missile") or string.find(name, "mine%-")
       or string.find(name, "%-mine") or string.find(name, "capsule")
       or subgroup == "gun" or subgroup == "ammo" then
        is_military = true
    end

    if is_military then
        -- Endgame ordnance patterns → military-advanced (tier 5)
        -- v3.7.0 (A2): extended with overhaul-mod endgame weapon/armor patterns
        -- (Bob's sniper/laser rifles, gatling, plasma, tiered turrets, mk3+
        -- power armor, tank upgrades). Without these, bob-sniper-rifle /
        -- bob-power-armor-mk5 / bob-laser-turret-5 etc. landed in the tier-3
        -- military category — replicable far too early with a modded combat
        -- progression.
        if string.find(name, "uranium") or string.find(name, "artillery")
           or string.find(name, "explosive%-rocket") or string.find(name, "cluster")
           or string.find(name, "spidertron") or string.find(name, "nuke")
           or string.find(name, "nuclear") or string.find(name, "explosive%-cannon")
           or string.find(name, "explosive%-uranium")
           -- Bob's / mod endgame rifles
           or string.find(name, "sniper") or string.find(name, "laser%-rifle")
           or string.find(name, "gatling") or string.find(name, "plasma")
           -- Tiered turrets: gun-turret-3+ / laser-turret-3+ / plasma-turret-N
           or string.find(name, "turret%-[3-9]")
           -- Power armor mk3+ / mech armor parts
           or string.find(name, "armor%-mk[3-9]") or string.find(name, "mech%-")
           -- Tank upgrades
           or string.find(name, "tank%-[2-9]") then
            return "military-advanced"
        end
        return "military"
    end

    -- 6. ALLOY (tier 3): plates, alloys, and sheet materials
    if string.find(name, "plate") or string.find(name, "alloy")
       or string.find(name, "foil") or string.find(name, "sheet")
       or subgroup == "plate" or subgroup == "alloy" then
        return "alloy"
    end

    -- 7. SHAPE (tier 2): simple shaped/molded items
    if string.find(name, "gear") or string.find(name, "pipe")
       or string.find(name, "stick") or string.find(name, "cable")
       or string.find(name, "wire") or string.find(name, "brick")
       or string.find(name, "frame") or string.find(name, "bearing")
       or string.find(name, "spring") or string.find(name, "ring")
       or string.find(name, "rod") or string.find(name, "tube")
       or string.find(name, "barrel") or string.find(name, "coil")
       or string.find(name, "%-ball") or string.find(name, "ball%-")
       or subgroup == "component" or subgroup == "part"
       or subgroup == "intermediate" then
        return "shape"
    end

    -- 8. ELEMENT (tier 2): detect pure elements by name
    if item_proto then
        local name_lower = string.lower(name)
        for _, elem in ipairs(repltypes.element_names) do
            if string.find(name_lower, elem) then
                return "element"
            end
        end
    end

    -- 9. EXOTIC (tier 5): exotic matter, artifacts
    if string.find(name, "exotic") or string.find(name, "artifact")
       or subgroup == "artifact" then
        return "exotic"
    end

    -- 10. MAGIC (tier 5)
    if string.find(name, "magic") or string.find(name, "mana")
       or string.find(name, "arcane") then
        return "magic"
    end

    -- 11. ALIEN (tier 5)
    if string.find(name, "alien") or subgroup == "alien" then
        return "alien"
    end

    -- 12. LIFE (tier 5): living creatures, spawners
    if string.find(name, "spawner") or string.find(name, "worm")
       or type_name == "capsule" and string.find(name, "spawn")
       or subgroup == "living" then
        return "life"
    end

    -- 13. GENERAL (dynamic tier): everything else
    -- The cost-solver determines tier for these
    return "general"
end

-- v3.6.0: Insert a research pack into the tech's ingredients list, honoring
-- the `dmrsa-research-pack-order` setting:
--   "DMR Item First" (default)  → [DMR item, ... science packs]
--   "Science Pack First"        → [science packs ..., DMR item]
-- The DMR item is the custom intermediate (tenemut/scoop/transducer/conduit);
-- science packs are the vanilla/SA packs. The setting only affects display
-- order in the tech tree — research cost is unchanged.
-- v4.3: `dmrsa-tenemut-research-required = false` skips the DMR intermediate
-- entirely; the caller's fallback then gives the tech its vanilla packs so an
-- ingredient list can never come out empty (the v4.2 "no cost" bug).
local function add_research_pack(research_packs, pack, is_dmr_item)
    if is_dmr_item and not helpers.dmr_research_pack_required() then
        return
    end
    local order = helpers.get_startup_setting("dmrsa-research-pack-order", "DMR Item First")
    if order == "Science Pack First" and is_dmr_item then
        table.insert(research_packs, 1, pack)
    else
        table.insert(research_packs, pack)
    end
end

local DynamicGenerator = {}

-- Main entry point to run the dynamic generation
function DynamicGenerator.generate()
    helpers.info("Starting dynamic recipe generation...")

    -- 1. Initialize solver states
    CostSolver.initialize_base_resources()
    CostSolver.build_recipe_map()
    CostSolver.build_tech_map()

    -- 2. Map potential replication targets via target-mapper
    local targets = TargetMapper.get_potential_replication_targets()
    local recipe_count = 0
    local tech_count = 0

    -- Retrieve settings safely
    local fluid_qty = helpers.get_startup_setting("replication-fluid-quantity", 25)
    -- v4.0: tech-distribution is "Mirror" (default, handled by MirrorGenerator)
    -- or "Individual" (legacy, this file). Grouped Categories was removed.
    -- This legacy generator only runs for Individual.
    local tech_dist = helpers.get_startup_setting("dmrsa-tech-distribution", "Mirror")
    local use_individual_techs = (tech_dist == "Individual")
    local use_grouped_techs = false
    local group_accum = {}

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

            -- Determine item category and apply FIXED tier override.
            -- Category determines the FLOOR tier; cost-solver can still push HIGHER.
            local item_category = ItemClass.classify(name, target)
            local category_def = repltypes[item_category]
            if category_def and category_def.tier then
                if tier < category_def.tier then
                    helpers.debug("Tier override " .. name .. ": computed=" .. tier .. " -> category=" .. category_def.tier .. " (" .. item_category .. ")")
                    tier = category_def.tier
                end
            end

            -- Science packs: anchor to their replication tier by name, NOT the
            -- cost-solver chain (which pushes chemical-science-pack to 4-5 via
            -- its recipe ingredients). Progression: automation/logistic → 1,
            -- military → 2, chemical/production/utility → 3 (before planets),
            -- planetary → 4, space/cryo/promethium → 5.
            if item_category == "science" then
                local science_tier
                -- v3.7.0 (fix): match 'advanced-logistic' BEFORE plain
                -- 'logistic'. bob-advanced-logistic-science-pack contains
                -- "logistic", so the old order forced it to tier 1 (log
                -- evidence: "Science tier force bob-advanced-logistic-science-
                -- pack: cost-solver=3 -> 1"). Bob's advanced-logistic pack is a
                -- mid-game pack (tier 3), not a tier-1 pack.
                if string.find(name, "advanced%-logistic") then
                    science_tier = 3
                elseif string.find(name, "automation") or string.find(name, "logistic") then
                    science_tier = 1
                elseif string.find(name, "military") then
                    science_tier = 2
                elseif string.find(name, "chemical") or string.find(name, "production")
                       or string.find(name, "utility") then
                    science_tier = 3
                elseif string.find(name, "metallurgic") or string.find(name, "electromagnetic")
                       or string.find(name, "agricultural") then
                    science_tier = 4
                else
                    science_tier = 5  -- space, cryogenic, promethium, unknown
                end
                if tier < science_tier then
                    helpers.debug("Science tier override " .. name .. ": computed=" .. tier .. " -> " .. science_tier)
                    tier = science_tier
                end
                -- FORCE the science pack tier (set absolute, not just floor).
                -- The cost-solver recipe chain can push chemical-science-pack to
                -- tier 4-5 (advanced circuits, engines, etc.), but its
                -- replication position is defined by progression (chemical=3),
                -- so we always override DOWN as well as up.
                if tier > science_tier then
                    helpers.debug("Science tier force " .. name .. ": cost-solver=" .. tier .. " -> " .. science_tier)
                    tier = science_tier
                end
            end

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
                elseif string.find(name, "holmium") or string.find(name, "scrap") or name == "superconducting-cable" or name == "electromagnetic-science-pack" then
                    category = gprefix .. "replication-fulgora"
                    planet_suffix = "fulgora"
                elseif name == "ice" or string.find(name, "lithium") or string.find(name, "fluoroketone") or name == "fluorine" or name == "cryogenic-science-pack" then
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
            -- Hard cap: no replication recipe should take more than N seconds
            -- base, where N scales with the research difficulty setting
            -- (v3.7.0): Easy (Fast)=600 (historical), Medium=1000, High=1800,
            -- Very Hard=3200. The replicator's crafting_speed (doubles per
            -- tier, up to 16x at T5) already provides meaningful progression;
            -- this cap prevents absurd compounding edge cases in deep recipe
            -- chains while letting harder modes stretch real crafting time.
            local time_cap = helpers.get_replication_time_cap()
            if dark_matter_cost > time_cap then
                dark_matter_cost = time_cap
            end
            time_cost = math.max(0.1, tonumber(string.format("%.2f", time_cost)))

            -- 5. Construct unique replication recipe
            local recipe_name = gprefix .. "repl-" .. name
            -- Precompute the correct localization prefix based on target type.
            -- Factorio 2.x LocalisedString uses "?" as the KEY (not a parameter)
            -- to enable fallback selection. The previous implementation passed
            -- "?" as a parameter, which Factorio interpreted as a positional
            -- parameter and rendered as literal "parameter-N" placeholders.
            local loc_prefix
            if target.type == "fluid" then
                loc_prefix = "fluid-name"
            elseif target.type == "item" or target.type == "ammo" or target.type == "armor"
                or target.type == "gun" or target.type == "capsule" or target.type == "tool"
                or target.type == "module" or target.type == "item-with-entity-data"
                or target.type == "item-with-tags" or target.type == "spidertron-remote"
                or target.type == "space-platform-starter" then
                -- Placeable items (place_result) have their locale in
                -- [entity-name], NOT [item-name]. Using item-name produces
                -- "Unknown key: item-name.X" warnings for every placeable
                -- (chests, furnaces, miners, inserters, poles, assemblers...).
                local item_proto = data.raw[target.type] and data.raw[target.type][name]
                if item_proto and item_proto.place_result then
                    loc_prefix = "entity-name"
                else
                    loc_prefix = "item-name"
                end
            else
                loc_prefix = "entity-name"
            end
            -- v3.5.21: subgroup by replication CATEGORY (easy to find in
            -- crafting menu). Planetary items go to replication-resources.
            -- Falls back to tier subgroup for safety if category is unknown.
            local recipe_subgroup
            if planet_suffix then
                recipe_subgroup = gprefix .. "replication-resources"
            elseif item_category and repltypes[item_category] then
                recipe_subgroup = gprefix .. "replication-" .. item_category
            else
                recipe_subgroup = gprefix .. "replication-tier-" .. tier
            end

            local repl_recipe = {
                type = "recipe",
                name = recipe_name,
                localised_name = {
                    "recipe-name.dmrsa-replication-recipe",
                    { loc_prefix .. "." .. name }
                },
                energy_required = dark_matter_cost,
                ingredients = {},
                results = {
                    { type = target.type == "fluid" and "fluid" or "item", name = name, amount = result_amount }
                },
                enabled = false,
                hidden = false,
                subgroup = recipe_subgroup,
                order = "z[" .. name .. "]"
            }
            -- v4.0: Factorio 2.1 format — categories array (no dual-compat)
            repl_recipe.categories = { category }

            if name == "promethium-science-pack" then
                repl_recipe.surface_conditions = {
                    { property = "gravity", max = 0 }
                }
            end

            -- Fail-safe: verify crafting category exists before extending recipe
            if not data.raw["recipe-category"][category] then
                helpers.warn("Skipping '" .. name .. "': crafting category '" .. category .. "' not found.")
                goto continue_item
            end

            -- Safely extend recipe
            data:extend({ repl_recipe })
            recipe_count = recipe_count + 1

            -- 7. Technology unlock binding
            if use_individual_techs then
                -- Define a technology for every item
                local tech_name = gprefix .. "tech-repl-" .. name .. "-tech"
                local tech_effects = {
                    { type = "unlock-recipe", recipe = recipe_name }
                }
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

                -- B. Safe prerequisite: original item's technology (if it exists)
                -- Re-enabled with safe existence check to prevent 'Error in assignID'
                -- crashes when other mods remove technologies in data-final-fixes.
                -- If the original tech doesn't exist, we skip it gracefully — the base
                -- machine prereq (A) still gates access so replication can't be reached
                -- before the corresponding replicator tier.
                local original_recipe = data.raw.recipe[name]
                if original_recipe then
                    local recipe_obj = CostSolver.recipe_map[name]
                    if recipe_obj then
                        local original_tech = CostSolver.recipe_tech_map[recipe_obj.name]
                        if original_tech and not original_tech.hidden and data.raw.technology[original_tech.name] then
                            add_prereq(prerequisites, original_tech.name)
                        end
                    end
                end

                -- Research Materials using custom intermediate products
                local research_packs = {}
                if tier == 1 then
                    add_research_pack(research_packs, { gprefix .. "tenemut", 1 }, true)
                elseif tier == 2 then
                    add_research_pack(research_packs, { gprefix .. "dark-matter-scoop", 1 }, true)
                elseif tier == 3 then
                    add_research_pack(research_packs, { gprefix .. "dark-matter-transducer", 1 }, true)
                elseif tier == 4 then
                    add_research_pack(research_packs, { gprefix .. "matter-conduit", 1 }, true)
                elseif tier == 5 then
                    add_research_pack(research_packs, { gprefix .. "matter-conduit", 1 }, true)
                    if planet_suffix == "aquilo" then
                        add_research_pack(research_packs, { "cryogenic-science-pack", 1 }, false)
                    end
                end

                -- Planet Specific science add-on
                if planet_suffix == "vulcanus" then
                    add_research_pack(research_packs, { "metallurgic-science-pack", 1 }, false)
                elseif planet_suffix == "fulgora" then
                    add_research_pack(research_packs, { "electromagnetic-science-pack", 1 }, false)
                elseif planet_suffix == "gleba" then
                    add_research_pack(research_packs, { "agricultural-science-pack", 1 }, false)
                end

                -- v4.3: safety net — with `dmrsa-tenemut-research-required`
                -- disabled the DMR pack above was skipped, so a tech could end
                -- up with NO pack at all (the v4.2 "no cost" failure mode).
                if #research_packs == 0 then
                    add_research_pack(research_packs, { "automation-science-pack", 1 }, false)
                    add_research_pack(research_packs, { "logistic-science-pack", 1 }, false)
                end

                -- Scale research cost based on settings (v3.7.0: single
                -- difficulty table — cost is absolute, Easy reads player
                -- settings, harder levels use fixed values)
                local repetitions = 10 * tier
                local diff_vals = helpers.get_research_difficulty_values()
                local reps_count = math.max(1, math.ceil(repetitions * (diff_vals.cost / 25)))
                local tech_time = math.ceil(diff_vals.time)

                local tech_proto = {
                    type = "technology",
                    name = tech_name,
                    localised_name = {
                        "technology-name.dmrsa-repl-tech",
                        { loc_prefix .. "." .. name }
                    },
                    localised_description = {
                        "technology-description.dmrsa-repl-tech",
                        { loc_prefix .. "." .. name }
                    },
                    effects = tech_effects,
                    prerequisites = prerequisites,
                    unit = {
                        count = reps_count,
                        ingredients = research_packs,
                        time = tech_time
                    },
                    order = "a-r-" .. tier .. "[" .. name .. "]"
                }

                -- Layer custom border on technology icons
                tech_proto.icons = get_tech_icons(name, target, tier)
                tech_proto.icon_size = 128

                -- Fail-safe: validate science packs and prerequisites exist
                local tech_valid = true
                for _, pack in ipairs(research_packs) do
                    if not helpers.item_exists(pack[1]) then
                        helpers.warn("Skipping tech for '" .. name .. "': science pack '" .. pack[1] .. "' not found.")
                        tech_valid = false
                        break
                    end
                end
                if tech_valid then
                    for _, prereq in ipairs(prerequisites) do
                        if not data.raw.technology[prereq] then
                            helpers.warn("Skipping tech for '" .. name .. "': prerequisite '" .. prereq .. "' not found.")
                            tech_valid = false
                            break
                        end
                    end
                end

                if tech_valid then
                    local ok, err = pcall(data.extend, data, { tech_proto })
                    if ok then
                        tech_count = tech_count + 1
                    else
                        helpers.error("Could not create individual tech '" .. tech_name .. "': " .. tostring(err))
                    end
                end
            elseif use_grouped_techs then
                local item_cat = item_category
                local group_key = planet_suffix and (planet_suffix .. "-" .. item_cat) or (tier .. "-" .. item_cat)
                
                if not group_accum[group_key] then
                    group_accum[group_key] = {
                        recipes = {},
                        tier = tier,
                        planet_suffix = planet_suffix,
                        category = item_cat,
                        items = {},
                        original_techs = {}
                    }
                end
                
                local group = group_accum[group_key]
                table.insert(group.recipes, recipe_name)
                table.insert(group.items, { name = name, target = target })
                
                local original_recipe = data.raw.recipe[name]
                if original_recipe then
                    local recipe_obj = CostSolver.recipe_map[name]
                    if recipe_obj then
                        local original_tech = CostSolver.recipe_tech_map[recipe_obj.name]
                        if original_tech and not original_tech.hidden then
                            group.original_techs[original_tech.name] = true
                        end
                    end
                end
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
                            unlocked_by_tech = true
                        end
                    end
                end

                -- If it has no original tech unlock, link it to the baseline/planetary techs
                if not unlocked_by_tech then
                    if planet_suffix then
                        table.insert(planetary_unlocks[planet_suffix], recipe_name)
                    else
                        table.insert(baseline_unlocks[tier], recipe_name)
                    end
                end
            end
        end
        ::continue_item::
    end

    if use_grouped_techs then
        local cost_multiplier = helpers.get_startup_setting("dmrsa-grouped-tech-cost-multiplier", 5.0)
        for group_key, group in pairs(group_accum) do
            local tier = group.tier
            local category = group.category
            local planet_suffix = group.planet_suffix
            local num_items = #group.items

            if num_items > 0 then
                -- representative item
                local rep_item = group.items[1]
                local tech_name = gprefix .. "grouped-repl-" .. group_key .. "-tech"

                -- Effects: unlock all recipes in group
                local tech_effects = {}
                for _, r_name in ipairs(group.recipes) do
                    table.insert(tech_effects, { type = "unlock-recipe", recipe = r_name })
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

                -- B. Previous tier same category unlock (progression chain)
                if not planet_suffix and tier > 1 then
                    local prev_key = (tier - 1) .. "-" .. category
                    if group_accum[prev_key] and #group_accum[prev_key].items > 0 then
                        add_prereq(prerequisites, gprefix .. "grouped-repl-" .. prev_key .. "-tech")
                    end
                end

                -- C. Safe prerequisite: original items' technologies (if they exist)
                -- Re-enabled with safe existence check. If a mod removes a technology
                -- in data-final-fixes, we gracefully skip it instead of crashing.
                for original_tech_name, _ in pairs(group.original_techs) do
                    if data.raw.technology[original_tech_name] then
                        add_prereq(prerequisites, original_tech_name)
                    end
                end

                -- D. Final deduplication pass (belt-and-suspenders for mods like Angel's that share tech names)
                local prereq_dedup = {}
                local clean_prereqs = {}
                for _, p in ipairs(prerequisites) do
                    if not prereq_dedup[p] then
                        prereq_dedup[p] = true
                        table.insert(clean_prereqs, p)
                    end
                end
                if #clean_prereqs ~= #prerequisites then
                    helpers.warn("Deduplicated " .. (#prerequisites - #clean_prereqs) .. " duplicate prerequisite(s) in grouped tech '" .. tech_name .. "'")
                end
                prerequisites = clean_prereqs

                -- E. Redundant prerequisite removal (smart cleanup from original).
                -- If a prerequisite is already implied by another prerequisite
                -- (e.g. A requires B and B requires C → C is redundant in A's list),
                -- remove the redundant entry. This prevents overly long tech trees.
                local function collect_all_prereqs(tech_name, visited)
                    if visited[tech_name] then return {} end
                    visited[tech_name] = true
                    local collected = {}
                    local tech = data.raw.technology[tech_name]
                    if tech and tech.prerequisites then
                        for _, p in ipairs(tech.prerequisites) do
                            collected[p] = true
                            local sub = collect_all_prereqs(p, visited)
                            for k, _ in pairs(sub) do
                                collected[k] = true
                            end
                        end
                    end
                    return collected
                end
                local redundant = {}
                for i, p in ipairs(prerequisites) do
                    local sub_prereqs = collect_all_prereqs(p, {})
                    for sub_p, _ in pairs(sub_prereqs) do
                        if redundant[sub_p] == nil then
                            -- Check if this sub-prereq is ALSO in our direct prereq list
                            for j, dp in ipairs(prerequisites) do
                                if dp == sub_p then
                                    redundant[sub_p] = true
                                    helpers.debug("Redundant prereq '" .. sub_p .. "' removed from '" .. tech_name .. "' (implied by '" .. p .. "')")
                                end
                            end
                        end
                    end
                end
                local filtered_prereqs = {}
                for _, p in ipairs(prerequisites) do
                    if not redundant[p] then
                        table.insert(filtered_prereqs, p)
                    end
                end
                if #filtered_prereqs ~= #prerequisites then
                    helpers.warn("Removed " .. (#prerequisites - #filtered_prereqs) .. " redundant prerequisite(s) from grouped tech '" .. tech_name .. "'")
                end
                prerequisites = filtered_prereqs

                -- Research Materials using custom intermediate products
                local research_packs = {}
                if tier == 1 then
                    add_research_pack(research_packs, { gprefix .. "tenemut", 1 }, true)
                elseif tier == 2 then
                    add_research_pack(research_packs, { gprefix .. "dark-matter-scoop", 1 }, true)
                elseif tier == 3 then
                    add_research_pack(research_packs, { gprefix .. "dark-matter-transducer", 1 }, true)
                elseif tier == 4 then
                    add_research_pack(research_packs, { gprefix .. "matter-conduit", 1 }, true)
                elseif tier == 5 then
                    add_research_pack(research_packs, { gprefix .. "matter-conduit", 1 }, true)
                    if planet_suffix == "aquilo" then
                        add_research_pack(research_packs, { "cryogenic-science-pack", 1 }, false)
                    end
                end

                -- Planet Specific science add-on
                if planet_suffix == "vulcanus" then
                    add_research_pack(research_packs, { "metallurgic-science-pack", 1 }, false)
                elseif planet_suffix == "fulgora" then
                    add_research_pack(research_packs, { "electromagnetic-science-pack", 1 }, false)
                elseif planet_suffix == "gleba" then
                    add_research_pack(research_packs, { "agricultural-science-pack", 1 }, false)
                end

                -- v4.3: same safety net as the individual-tech path — a tech
                -- never ships with an empty ingredient list.
                if #research_packs == 0 then
                    add_research_pack(research_packs, { "automation-science-pack", 1 }, false)
                    add_research_pack(research_packs, { "logistic-science-pack", 1 }, false)
                end

                -- Scale research cost based on settings and number of items
                -- (v3.7.0: single difficulty table — cost is absolute)
                local base_repetitions = 10 * tier
                local diff_vals = helpers.get_research_difficulty_values()
                local reps_count = math.ceil(base_repetitions * (diff_vals.cost / 25) * num_items * cost_multiplier)
                reps_count = math.max(1, reps_count)

                -- 5x time increase for time-gated research (difficulty-scaled)
                local tech_time = math.max(1, math.ceil(diff_vals.time * 5))

                -- Localized name: Replication: [Category] (Tier X) or (Planet)
                -- For planetary names, prefer planet-name.X over the literal suffix
                -- (avoid the "?" parameter pitfall that Factorio 2.x interprets
                -- as a positional argument, not a fallback key).
                -- The planet template has exactly 2 placeholders (__1__, __2__), so
                -- we pass exactly 2 parameters to avoid "Unknown key: ...parameter-N"
                -- runtime warnings from extra positional args.
                local loc_name
                if planet_suffix then
                    loc_name = {
                        "technology-name.dmrsa-grouped-repl-planet-tech",
                        { "replcategory-name." .. category },
                        { "planet-name." .. planet_suffix }
                    }
                else
                    loc_name = {
                        "technology-name.dmrsa-grouped-repl-tech",
                        { "replcategory-name." .. category },
                        tostring(tier)
                    }
                end

                local tech_proto = {
                    type = "technology",
                    name = tech_name,
                    localised_name = loc_name,
                    localised_description = {
                        "technology-description.dmrsa-repl-tech",
                        { "replcategory-name." .. category }
                    },
                    effects = tech_effects,
                    prerequisites = prerequisites,
                    unit = {
                        count = reps_count,
                        ingredients = research_packs,
                        time = tech_time
                    },
                    order = "a-r-g-" .. tier .. "[" .. category .. "]"
                }

                -- Layer custom border on technology icons using the representative item
                tech_proto.icons = get_tech_icons(rep_item.name, rep_item.target, tier)
                tech_proto.icon_size = 128

                -- Fail-safe: validate science packs and prerequisites exist
                local tech_valid = true
                for _, pack in ipairs(research_packs) do
                    if not helpers.item_exists(pack[1]) then
                        helpers.warn("Skipping group tech '" .. tech_name .. "': science pack '" .. pack[1] .. "' not found.")
                        tech_valid = false
                        break
                    end
                end
                if tech_valid then
                    for _, prereq in ipairs(prerequisites) do
                        -- If it is one of our own grouped technologies, it is valid because we ensured it exists
                        local is_our_grouped = string.sub(prereq, 1, string.len(gprefix .. "grouped-repl-")) == (gprefix .. "grouped-repl-")
                        if not is_our_grouped and not data.raw.technology[prereq] then
                            helpers.warn("Skipping group tech '" .. tech_name .. "': prerequisite '" .. prereq .. "' not found.")
                            tech_valid = false
                            break
                        end
                    end
                end

                if tech_valid then
                    local ok, err = pcall(data.extend, data, { tech_proto })
                    if ok then
                        tech_count = tech_count + 1
                    else
                        helpers.error("Could not create grouped tech '" .. tech_name .. "': " .. tostring(err))
                        -- Fallback: if technology fails (e.g. duplicate prerequisite), add recipes to baseline unlocks
                        for _, r_name in ipairs(group.recipes) do
                            if planet_suffix then
                                table.insert(planetary_unlocks[planet_suffix], r_name)
                            else
                                table.insert(baseline_unlocks[tier], r_name)
                            end
                        end
                    end
                else
                    -- Fallback: if technology is invalid (e.g. missing prerequisite), add recipes to baseline unlocks
                    for _, r_name in ipairs(group.recipes) do
                        if planet_suffix then
                            table.insert(planetary_unlocks[planet_suffix], r_name)
                        else
                            table.insert(baseline_unlocks[tier], r_name)
                        end
                    end
                end
            end
        end
    end

    helpers.info("Dynamically compiled: " .. recipe_count .. " replication recipes and " .. tech_count .. " technology nodes.")
    return baseline_unlocks, planetary_unlocks
end

return DynamicGenerator
