-- prototypes/entities/annihilator.lua
-- v4.4.0 (Part B): the ANNIHILATION CHAMBER — dark matter goes in, heat comes out.
--
-- WHY A REACTOR
--   The chamber is `type = "reactor"`: it has an output heat buffer, so it feeds
--   the VANILLA heat-exchanger -> steam-turbine chain with zero new fluids and
--   zero runtime scripts (the same pattern Space Age uses for its fusion
--   generator). Its burner energy_source accepts `dmrsa-dark-matter-fuel`, the
--   PRIVATE fuel category dmrsa-dark-matter carries since v4.4.0: no vanilla
--   burner accepts it, so a vanilla nuclear reactor (category `nuclear`) can NOT
--   burn dark matter any more. It used to — and a 2x2 reactor block burned it
--   with the reactor's 1.5-1.75x neighbour bonus, i.e. 37.5-43.75 GJ out of the
--   25 GJ the collider paid 50 GJ for (the C2 defect of this batch). The
--   fuel_value is unchanged at 25 GJ: the ledger below is untouched, only the
--   set of machines allowed to burn it shrank to this one.
--
-- THE BURN (declared in one place, so the ledger can be recomputed by hand)
--   fuel_value(dmrsa-dark-matter) = 25 GJ = 25 000 MJ
--   wanted: one unit == roughly 600 s (ten minutes) of heat
--   consumption = 25 GJ / 600 s = 41.6667 MW  ->  600.0 s per unit
--   `scale_energy_usage = false` (vanilla reactor behaviour: the fuel burns at a
--   constant rate while fuelled, it does not throttle when the heat buffer is full,
--   so the 600 s number is real and not "up to"). With the round 40MW the burn
--   would be 625 s — the exact number is chosen so 25 GJ / consumption = 600 s.
--
--   Heat -> electricity is ~100% through the vanilla chain (heat-exchanger burns
--   10 MW to make 103.09 steam/s at 500 C; a steam-turbine turns 60 steam/s into
--   5.82 MW), so one unit of dark matter is worth ~25 GJ of grid energy.
--   ONE unit per ten minutes = 41.7 MW of heat = ~4.2 vanilla heat exchangers.
--
-- NO NEIGHBOUR BONUS
--   neighbour_bonus = 0 and no `neighbour_connectable` — exactly how Space Age
--   builds its own non-breeder reactor (heating-tower: neighbour_bonus = 0, no
--   connectable), so two chambers side by side do NOT breed. The balance gate is
--   the collider loop (0.50x at L0 -> 2.00x at L3), never the reactor layout.
--
-- PLACEHOLDER GRAPHICS
--   The mod's OWN sprite, tinted — never a vanilla sheet. Verified on disk:
--     graphics/entity/replicator-4.png = 1243 x 273 px = 11 x 3 frames of 113x91
--     graphics/icons/replicator-4.png  = 64 x 64 px
--   A reactor draws a single `picture` (Sprite), not an animation, so the top-left
--   113x91 frame of the sheet is used as a static image.
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local CHAMBER_SPRITE = "__dark-matter-replicators-reborn__/graphics/entity/replicator-4.png"
local CHAMBER_ICON = "__dark-matter-replicators-reborn__/graphics/icons/replicator-4.png"
local FRAME_W, FRAME_H = 113, 91

-- v4.4.0 (D7, audit I2): 0.55/0.12/0.12 multiplied the icon's pixels down to
-- 8.6 % luminance — a dark silhouette (the audit measured 8 %). 0.9/0.35/0.30
-- keeps the "dark matter red" theme at 17.0 %, i.e. ~2x. ONE constant: the item icon, the
-- entity icon and the in-world `picture` all use it.
local CHAMBER_TINT = { r = 0.9, g = 0.35, b = 0.30, a = 1.0 }

-- 5x5, the vanilla reactor footprint (selection 2.5 / collision 2.2), so the heat
-- connections below line up with a standard heat-pipe grid.
local BOARD = 2.5
local HITBOX = 2.2
-- v4.4.0 (D1, audit G1): art-calibrated scale. The FRAME is 113x91 but the
-- solid art inside it is 95x85, so the old `1.42` (113 * 1.42 / 32 = 5.02 tiles
-- of FRAME) actually drew a 4.22 x 3.77 tile reactor inside the 5x5 box: 16 %
-- too small, with 0.70 / 0.57-tile empty bands and its centre 0.31 tiles left of
-- the entity centre. Next to the vanilla reactor art it visually replaces
-- (4.72 x 4.97 tiles) that reads as a small replicator in a big footprint.
--   art tiles = 95 * scale / 32 = 4.95 x 4.43 at scale = BOARD * 2 / 3 = 1.6667
--   shift     = the art's own bias inside its frame (7 px left, 1 px up)
--               * 1.6667 / 32 = { 0.36, 0.05 } tiles — a `picture` shift is in
--               tiles, the same units the sheet sprites use as `shift`.
-- Residual: 0.4 tiles of vertical air, unavoidable while the frame aspect
-- (113:91 = 1.24) is not square.
local SPRITE_SCALE = BOARD * 2 / 3
local SPRITE_SHIFT = { 0.36, 0.05 }

-- ---- the burn, in one place -------------------------------------------------
local FUEL_GJ = 25              -- dmrsa-dark-matter fuel_value (items/dark-matter.lua)
local BURN_SECONDS = 600        -- one unit == ten minutes of heat
local CONSUMPTION_MW = FUEL_GJ * 1000 / BURN_SECONDS   -- 41.6667 MW
local CONSUMPTION = string.format("%.4fMW", CONSUMPTION_MW)

-- Heat pipe connections on the border of the 5x5 box (the vanilla reactor's own
-- layout uses 3 per side at +/-2 including the shared corners). The chamber sits on
-- a normal heat-pipe grid; nothing else needs to be configured for heat to flow.
local function heat_connections()
    local out = {}
    local edge = { -2, 0, 2 }
    for _, x in ipairs(edge) do
        table.insert(out, { position = { x, -2 }, direction = defines.direction.north })
    end
    for _, y in ipairs(edge) do
        table.insert(out, { position = { 2, y }, direction = defines.direction.east })
    end
    for _, x in ipairs(edge) do
        table.insert(out, { position = { x, 2 }, direction = defines.direction.south })
    end
    for _, y in ipairs(edge) do
        table.insert(out, { position = { -2, y }, direction = defines.direction.west })
    end
    return out
end

data:extend({
    -- Item (the building)
    {
        type = "item",
        name = gprefix .. "annihilator",
        icons = {
            {
                icon = CHAMBER_ICON,
                tint = CHAMBER_TINT
            }
        },
        icon_size = 64,
        subgroup = gprefix .. "replicators",
        order = "f",
        place_result = gprefix .. "annihilator",
        stack_size = 20
    },

    -- Entity: a dark-matter reactor with no neighbour bonus.
    {
        type = "reactor",
        name = gprefix .. "annihilator",
        icons = {
            {
                icon = CHAMBER_ICON,
                tint = CHAMBER_TINT
            }
        },
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.5, result = gprefix .. "annihilator" },
        fast_replaceable_group = gprefix .. "annihilator",
        max_health = 500,
        resistances = {
            {
                type = "fire",
                percent = 90
            },
            {
                type = "explosion",
                percent = 30
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -HITBOX, -HITBOX }, { HITBOX, HITBOX } },
        selection_box = { { -BOARD, -BOARD }, { BOARD, BOARD } },

        -- 25 GJ / 600 s = 41.6667 MW of heat per chamber.
        consumption = CONSUMPTION,
        -- No breeding: side by side, two chambers give each other nothing.
        neighbour_bonus = 0,
        -- Constant burn while fuelled (vanilla reactor behaviour) — this is what
        -- makes "one dark matter == ten minutes of heat" an exact statement.
        scale_energy_usage = false,

        energy_source = {
            type = "burner",
            -- The PRIVATE category (see prototypes/items/dark-matter.lua): it is
            -- what makes the C2 fix work — no vanilla reactor, boiler or
            -- generator accepts it, so dark matter can only be burned here.
            fuel_categories = { "dmrsa-dark-matter-fuel" },
            effectivity = 1,
            fuel_inventory_size = 1,
            burnt_inventory_size = 1,
            emissions_per_minute = { pollution = 30 },
            light_flicker = {
                color = { 0, 0, 0 },
                minimum_intensity = 0.7,
                maximum_intensity = 0.95
            }
        },

        picture = {
            filename = CHAMBER_SPRITE,
            width = FRAME_W,
            height = FRAME_H,
            scale = SPRITE_SCALE,
            shift = SPRITE_SHIFT,
            tint = CHAMBER_TINT
        },

        working_sound = {
            sound = {
                {
                    filename = "__base__/sound/lab.ogg",
                    volume = 0.7
                }
            },
            idle_sound = { filename = "__base__/sound/idle1.ogg", volume = 0.6 },
            apparent_volume = 1.5
        },
        light = { intensity = 0.8, size = 12 },

        heat_buffer = {
            max_temperature = 1000,
            specific_heat = "10MJ",
            max_transfer = "10GW",
            minimum_glow_temperature = 350,
            connections = heat_connections()
        }
    }
})
