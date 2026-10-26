-- control.lua — v4.7.1, the mod's only runtime script.
--
-- The Quality Refiner is a CRAFTING MACHINE again (author's call, 2026-10-24):
-- one recipe per item per quality step, real power draw, real progress bar. The
-- recipes themselves do the work — each attempt keeps the same quality or moves
-- it up ONE step, with a 1 % chance of destroying the item (the probabilities
-- live in lib/refiner-generator.lua).
--
-- What this script does is the AUTO-DETECTION the author asked for: it watches
-- each refiner and keeps its recipe pointed at the step that matches the item's
-- CURRENT quality. Pick "refine to uncommon" once and the machine keeps going —
-- after a success the item is uncommon, the script switches the recipe to
-- "refine to rare", and so on. You never reselect anything.
--
-- Why a recipe has to exist at all (engine fact, measured): an assembling
-- machine builds its input inventory FROM its recipe's ingredient list — with no
-- recipe it has zero slots and can_insert() is false for everything, so nothing
-- could be inserted (that was the 4.6.x "refining nothing" bug).
--
-- Cost model: only the refiners registered in `storage.refiners` are touched,
-- twice per second. No map scan.

local LOGIC = require("lib.refiner-logic")

local REFINER = "dmrsa-refiner"
local PREFIX = "dmrsa-"
local TICK_INTERVAL = 30
local FUEL_SKIP_MAX = 100e6

local function ladder()
    if not storage.ladder then
        storage.ladder = LOGIC.ladder(prototypes.quality)
    end
    return storage.ladder
end

-- NOTE: a runtime LuaRecipePrototype exposes `energy` (seconds), NOT
-- `energy_required` — that key only exists in the data stage.
local function repl_time(name)
    local r = prototypes.recipe[PREFIX .. "repl-" .. name]
    return r and r.energy or nil
end

--- Allowed = replicable, solid, not a chemical fuel.
local function allowed(name)
    local item = prototypes.item[name]
    if not item then return nil end
    local t = repl_time(name)
    if not t then return nil end
    local fuel = item.fuel_value
    if type(fuel) == "number" and fuel > 0 and fuel <= FUEL_SKIP_MAX then return nil end
    return t
end

local function register(entity)
    if not (entity and entity.valid and entity.name == REFINER) then return end
    storage.refiners = storage.refiners or {}
    storage.refiners[entity.unit_number] = { entity = entity }
end

local function unregister(entity)
    if storage.refiners and entity and entity.unit_number then
        storage.refiners[entity.unit_number] = nil
    end
end

local function scan()
    storage.refiners = {}
    storage.ladder = nil
    -- The Quality Refiner only exists when a quality mod is active
    -- (`prototypes/entities/refiner.lua` returns early otherwise), so probing the
    -- name unconditionally throws "Unknown entity name" on vanilla / no-quality
    -- modlists — reproduced on 2.1.23 with quality+space-age disabled (v4.7.1,
    -- on_init). Guard before the query.
    if not prototypes.entity[REFINER] then return end
    for _, surface in pairs(game.surfaces) do
        for _, e in pairs(surface.find_entities_filtered{ name = REFINER }) do
            register(e)
        end
    end
end

script.on_init(scan)
script.on_configuration_changed(scan)

script.on_event(defines.events.on_built_entity, function(ev) register(ev.created_entity) end)
script.on_event(defines.events.on_robot_built_entity, function(ev) register(ev.created_entity) end)
script.on_event(defines.events.script_raised_built, function(ev) register(ev.entity) end)
script.on_event(defines.events.script_raised_revive, function(ev) register(ev.entity) end)
script.on_event(defines.events.on_entity_cloned, function(ev) register(ev.destination) end)
script.on_event(defines.events.on_entity_died, function(ev) unregister(ev.entity) end)
script.on_event(defines.events.on_player_mined_entity, function(ev) unregister(ev.entity) end)
script.on_event(defines.events.on_robot_mined_entity, function(ev) unregister(ev.entity) end)
script.on_event(defines.events.script_raised_destroy, function(ev) unregister(ev.entity) end)

--- First allowed item in an inventory -> { name, level } or nil.
local function first_allowed(inv)
    if not inv then return nil end
    for i = 1, #inv do
        local stack = inv[i]
        if stack and stack.valid_for_read and allowed(stack.name) then
            return { name = stack.name, level = stack.quality and stack.quality.level or 0 }
        end
    end
    return nil
end

--- Point the machine's recipe at the step matching the item's current quality.
local function sync_recipe(entity)
    local pick = first_allowed(entity.get_inventory(defines.inventory.crafter_input))
        or first_allowed(entity.get_inventory(defines.inventory.crafter_output))
    if not pick then return end
    local next_q = LOGIC.next_level(ladder(), pick.level)
    if not next_q then return end                      -- already top quality
    local want = PREFIX .. "refine-" .. pick.name .. "-" .. next_q.name
    if not prototypes.recipe[want] then return end
    local current = entity.get_recipe()
    if current and current.name == want then return end
    entity.set_recipe(want)
end

script.on_nth_tick(TICK_INTERVAL, function()
    if not storage.refiners then return end
    for uid, rec in pairs(storage.refiners) do
        local entity = rec.entity
        if entity and entity.valid then
            sync_recipe(entity)
        else
            storage.refiners[uid] = nil
        end
    end
end)
