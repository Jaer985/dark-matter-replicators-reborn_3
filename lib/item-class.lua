-- lib/item-class.lua
-- v4.5.1 — STRUCTURAL item classifier for the replication picker.
--
-- Why this file exists: the old `get_item_category` (two copies, in
-- prototypes/recipes/dynamic-generator.lua and lib/mirror-generator.lua) guessed
-- the bucket from the item's NAME: "plate", "gear", "cable", "ore"… Everything
-- it failed to recognise fell into `general`, which is why the 4.5.1 dump shows
-- 104 recipes in General and 68 in Resources — two dumping grounds — with
-- `iron-chest` filed under "Pure Elements" and `copper-cable` under "Shaped
-- Objects".
--
-- This classifier reads the PROTOTYPE instead:
--   * a placeable item's `place_result` entity type decides the machine buckets
--     (machines / power / logistics / military turrets);
--   * the item type decides modules, ammo, guns, capsules, armour and fluids;
--   * `fuel_value` decides fuels;
--   * "was it mined and never crafted" decides ores;
--   * "is it produced by a smelting recipe" decides plates & alloys;
--   * a spoilable prototype decides organic;
--   * everything else is an intermediate.
--
-- The result is one of the categories the author approved (2026-10-24):
--   machines · power · science · modules · ores · plates · intermediates ·
--   chemicals · logistics · military · fuels · organic · darkmatter
--
-- One source of truth: both generators (the mirror recipes and the grouped
-- techs) call ItemClass.classify, so the picker and the tech tree can never
-- disagree.

local ItemClass = {}

-- Placeable item -> entity type -> bucket. Entity names are resolved through
-- an index built once (data.raw is keyed by prototype TYPE, not by entity name).
local MACHINE_TYPES = {
    ["assembling-machine"] = true, ["furnace"] = true, ["mining-drill"] = true,
    ["lab"] = true, ["centrifuge"] = true, ["rocket-silo"] = true,
    ["beacon"] = true, ["roboport"] = true, ["radar"] = true,
    ["spider-vehicle"] = true, ["car"] = true, ["locomotive"] = true,
    ["cargo-wagon"] = true, ["fluid-wagon"] = true,
}
local POWER_TYPES = {
    ["boiler"] = true, ["generator"] = true, ["reactor"] = true,
    ["solar-panel"] = true, ["accumulator"] = true,
    ["fusion-reactor"] = true, ["fusion-generator"] = true,
    ["heating-tower"] = true, ["thruster"] = true,
    ["lightning-attractor"] = true, ["asteroid-collector"] = true,
    ["space-platform-hub"] = true, ["cargo-pod"] = true, ["agricultural-tower"] = true,
}
local LOGISTICS_TYPES = {
    ["transport-belt"] = true, ["splitter"] = true, ["underground-belt"] = true,
    ["loader"] = true, ["linked-belt"] = true, ["inserter"] = true,
    ["electric-pole"] = true, ["container"] = true, ["logistic-container"] = true,
    ["infinity-container"] = true, ["pipe"] = true, ["pipe-to-ground"] = true,
    ["storage-tank"] = true, ["pump"] = true, ["offshore-pump"] = true,
    ["wall"] = true, ["gate"] = true, ["lamp"] = true,
    ["rail"] = true, ["straight-rail"] = true, ["curved-rail"] = true,
    ["half-diagonal-rail"] = true, ["rail-signal"] = true,
    ["rail-chain-signal"] = true, ["train-stop"] = true, ["artillery-wagon"] = true,
}
local MILITARY_ENTITY_TYPES = {
    ["ammo-turret"] = true, ["electric-turret"] = true, ["fluid-turret"] = true,
    ["artillery-turret"] = true,
}
local MILITARY_ITEM_TYPES = {
    ["ammo"] = true, ["gun"] = true, ["capsule"] = true, ["armor"] = true,
}
local POWER_MACHINE_NAMES = {
    ["solar-panel-equipment"] = nil,
}

local entity_type_of            -- entity name -> prototype type (lazy)
local smelted_items             -- item name -> true when a smelting recipe makes it
local crafted_items             -- item name -> true when ANY recipe makes it

local function build_indexes()
    if entity_type_of then return end
    entity_type_of = {}
    for _, list in ipairs({ MACHINE_TYPES, POWER_TYPES, LOGISTICS_TYPES, MILITARY_ENTITY_TYPES }) do
        for etype in pairs(list) do
            for ename in pairs(data.raw[etype] or {}) do entity_type_of[ename] = etype end
        end
    end
    smelted_items, crafted_items = {}, {}
    for _, r in pairs(data.raw.recipe or {}) do
        local res = r.results or (r.normal and r.normal.results) or {}
        local smelt = (r.category == "smelting")
            or (r.categories and r.categories[1] == "smelting")
        for _, out in ipairs(res) do
            local n = out.name or out[1]
            if n then
                crafted_items[n] = true
                if smelt then smelted_items[n] = true end
            end
        end
    end
end

-- Is the item produced by ANY recipe? (a mined-only item is an ore)
local function is_crafted(name)
    build_indexes()
    return crafted_items[name] == true
end

--- Classify one replication target.
-- @param name   prototype name
-- @param target  { type = <prototype type>, subgroup = <subgroup> }
-- @return one of the 13 approved categories
function ItemClass.classify(name, target)
    build_indexes()
    local type_name = (target and target.type) or "item"
    local proto = data.raw[type_name] and data.raw[type_name][name]

    -- 1. the mod's own prototypes: the replicators are machines, the rest of
    -- the dmrsa- family (tenemut, scoop, transducer, conduit, dark matter) is
    -- the dark-matter material row.
    if string.sub(name, 1, 6) == "dmrsa-" then
        if string.find(name, "replicator") then return "machines" end
        return "darkmatter"
    end

    -- 2. fluids are chemicals (they have no quality and no place_result)
    if type_name == "fluid" or (proto and proto.type == "fluid") then return "chemicals" end

    -- 3. modules (and beacons, which are placeable but belong to the module row)
    if type_name == "module" or (proto and proto.type == "module") then return "modules" end

    -- 4. weapons, ammo, capsules, armour
    if MILITARY_ITEM_TYPES[type_name] then return "military" end

    -- 5. placeable things, by the type of the entity they place
    local place = proto and proto.place_result
    local etype = place and entity_type_of[place]
    if etype then
        if MILITARY_ENTITY_TYPES[etype] then return "military" end
        if POWER_TYPES[etype] then return "power" end
        if LOGISTICS_TYPES[etype] then return "logistics" end
        if MACHINE_TYPES[etype] then return "machines" end
    end
    if name == "beacon" then return "modules" end

    -- 6. science packs
    if (proto and proto.subgroup == "science-pack")
       or string.find(name, "science%-pack") then
        return "science"
    end

    -- 7. fuels: anything burnable is a fuel, even when it is also an ore (coal)
    local fuel = proto and proto.fuel_value
    if fuel then
        local j = fuel
        if type(fuel) == "string" then j = require("lib.timing-model").fuel_joules(fuel) or 0 end
        if (j or 0) >= 1e6 then return "fuels" end
    end

    -- 8. organic: spoilable prototypes and the Gleba crops
    if proto and (proto.spoil_ticks or proto.spoil_to or proto.spoil_result) then
        return "organic"
    end

    -- 9. ores: minable and ore-shaped. This CANNOT be "never crafted": Space
    -- Age crushes asteroids into iron-ore/copper-ore/coal, so every ore is
    -- "craftable" there and used to fall through to intermediates.
    -- NOTE: an ITEM prototype carries no `minable` field — mining lives on the
    -- resource prototype — so the subgroup/name is the only structural signal
    -- available here.
    if type_name == "resource"
       or (proto and (proto.subgroup == "ore" or proto.subgroup == "raw-resource"))
       or string.find(name, "ore") then
        return "ores"
    end

    -- 10. plates & alloys: anything a smelting recipe produces
    if smelted_items[name] then return "plates" end
    if (proto and proto.subgroup == "plate") or string.find(name, "plate") then
        return "plates"
    end

    -- 11. everything else is an intermediate (gears, circuits, cables, pipes…)
    return "intermediates"
end

return ItemClass
