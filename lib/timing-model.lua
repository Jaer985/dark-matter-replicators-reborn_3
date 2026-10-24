-- lib/timing-model.lua
-- v4.4.0 (Part A): closed-form replication-TIME model ("timing model v3").
--
-- Replaces the recursive-solver cost + per-tier BAND_LO/HI soft-clamp that
-- used to decide a replication recipe's `energy_required`. ONE equation with
-- declared tables:
--
--     time(item) = B * g^(tier-1) * C(steps)
--         B        = 6.32 s           base seconds for a tier-1 simple item
--         g        = 2                growth per whole tier
--         C(steps) = 1 + 0.02*steps   capped at 1.50
--         ceiling  = 200 s            clamp on the LADDER (promethium anchors it)
--
-- The 200 s clamp applies to time_for() (the progression ladder). Two classes
-- are priced outside it on purpose, and BOTH are documented in the table that
-- owns them: the fuel class (burn value, 200-3000 s — clamping it re-opens the
-- energy printer, F-2a) and the C5 arbitrage floor (the recycle break-even can
-- exceed 200 s for a megastructure whose parts bill does too). Everything else
-- — ladders, ores, fluids, DMR items — lands at or below the clamp.
--
--     tier = max(pack_tier, chain_tier)          decimals allowed
--
-- Everything else (dark-matter cost model, machine efficiency, ore floors,
-- difficulty caps) is untouched — only the TIME derivation changed.
--
-- The module is pure data-stage Lua: it never mutates prototypes and reads
-- data.raw lazily, so it is loadable/unit-testable outside Factorio.
--
-- ══════════════════════════════════════════════════════════════════════════
-- v4.4.0 ECONOMY BATCH (audit-brief-v440 §F, decisions F-1a/F-2a/F-3b/F-5b/
-- F-7a/C4/C5) — what changed here and why:
--
--  F-1a tenemut_tier() is 5 again (AGENTS.md §5/§10: tenemut replicates ONLY
--       on the tier-5 machine "Mastery of Dark Matter"). The planet-band
--       logic (planet_tier()) stays for every other ore.
--  F-2a NO CAP ON FUELS: FUEL_MAX_BURN (100 MJ) is gone. EVERY burnable is
--       priced by the energy it returns — the old cap priced uranium fuel
--       cells (8 GJ) at 88 MJ = a 90x energy printer (271x in a 2x2 reactor).
--  F-3b the fuel reference is the BEST burner (heating tower, effectivity
--       2.5), never a 1 MW boiler: t = 2 * fuel_value * 2.5 / R.  With F-5b
--       (R = 1.0) that is 5 s per MJ of burn value, so duplication L0 always
--       costs 5x what the fuel returns even through a heating tower.
--  F-5b the fuel class is forced onto the tier-1 machine (see
--       MirrorGenerator.category_for), so R = 1.0 exactly for every fuel.
--  F-7a the research-difficulty multiplier (replic_mult 1.5/2.0/3.0) is
--       applied INSIDE time_for(), BEFORE the 200 s clamp — before this fix
--       the caller multiplied after the clamp, so the "200 s ceiling" was
--       really 300/400/600 s on Medium/High/Very Hard.
-- C4/M3 fluids are priced by a DECLARED per-unit ladder (FLUID_UNIT_TIMES):
--       water 0.5 s / steam 1 s per craft, the oil family from crude at
--       67.5 s, planet fluids 12.5-25 s. The old derived-value pass priced
--       water, steam and both oils at the 200 s ceiling; it is gone from
--       pricing and stays only as the dmr-tests cross-check below.
--  C5  arbitrage_clamp(): replicate-and-recycle is bounded by the recipe's
--       own parts bill (see the function; used by mirror-generator).
-- ══════════════════════════════════════════════════════════════════════════

local helpers = require("lib.helpers")

local TimingModel = {}

-- ══════════════════════════════════════════════════════════════════
-- 1. Equation constants
-- ══════════════════════════════════════════════════════════════════
TimingModel.B          = 6.32   -- base seconds (tier 1, minimal complexity)
TimingModel.G          = 2      -- per-tier growth factor
TimingModel.C_WEIGHT   = 0.02   -- complexity weight per step
TimingModel.C_CAP      = 1.50   -- complexity cap  (+50 %)
TimingModel.CEILING    = 200    -- hard ceiling (s)
TimingModel.MIN_TIME   = 0.1    -- Factorio: energy_required floor

-- Fuel energy rule (F-2a / F-3b / F-5b).
--   t_fuel = 2 * fuel_value * FUEL_BURNER_EFFECTIVITY / R
-- FUEL_BURNER_EFFECTIVITY = 2.5 is the heating tower (the only burner above
-- 1.0 in vanilla + Space Age); pricing against a 1 MW boiler made L0 fuel
-- duplication a net gain the moment the ring sat on Aquilo.  FUEL_TIME_PER_J
-- folds 2 * 2.5 / 1 MW into a single factor: 5 seconds per MJ of burn value.
TimingModel.FUEL_BURNER_EFFECTIVITY = 2.5  -- heating tower
TimingModel.FUEL_REFERENCE_MW       = 1e6  -- 1 MJ/s reference second
TimingModel.FUEL_TIME_PER_J         = 2 * 2.5 / 1e6   -- s per Joule (= 5/MJ)
TimingModel.FUEL_CLASS_R            = 1.0  -- F-5b: the fuel class runs on the
                                           -- tier-1 machine, R = 1.0 exactly
TimingModel.FUEL_MIN_TIME           = 1    -- energy_required floor (plan §6.3)
-- ESCAPE HATCH (F-2a): a burnable whose fair price exceeds FUEL_MAX_TIME is
-- NOT replicable at all — see fuel_price_over_max().  Any shorter craft would
-- be a printer again (the craft cannot return 2x an 8 GJ cell without paying
-- tens of GJ), and a 11-55 hour craft is dead content; the only honest option
-- left is "manufactured, not replicated".
TimingModel.FUEL_MAX_TIME           = 3000 -- s

-- ══ v4.4.0 (A7): the REPLICATION CEILING ══
-- An item whose FINAL fair time lands above this is NOT a replication target:
-- the mirror skips its recipe, its unlock effect and its tech (an hour of
-- crafting per item is dead content, not compaction). The C5 arbitrage floor
-- can LIFT a recipe above this, so the rule is applied to the final time, not
-- just to the model time. The mod's own machines are excluded unconditionally
-- by lib/mirror-generator.lua (a machine that replicates itself is a loop).
TimingModel.REPLICATION_CEILING     = 3600 -- s

-- Escape-hatch predicate for the ceiling (strictly ABOVE: 3600 s stays).
function TimingModel.over_replication_ceiling(t)
    return t ~= nil and t > TimingModel.REPLICATION_CEILING
end

-- The 100 MJ threshold SURVIVES only as the Quality Refiner's fuel blacklist
-- (lib/refiner-generator.lua uses is_cheap_fuel); it no longer prices
-- anything. Do not reintroduce it into resolve().
TimingModel.REFINER_FUEL_BLACKLIST_MJ = 100e6

-- Machine R = energy_usage / crafting_speed = "MJ per craft-second".
-- energy_per_craft = energy_required * R.  Dump-measured (audit-w1-balance-
-- energy §0) — the fuel / parts-bill rules are written against R = 1.0.
TimingModel.MACHINE_R = { 1.0, 1.875, 3.125, 3.6621, 4.5776 }
TimingModel.PLANET_R = {
    vulcanus = 13.3333, fulgora = 13.3333, gleba = 13.3333, aquilo = 16.0,
}

-- Duplication ladder (B1/B11): three techs, +100 % productivity each,
-- cumulative +100 %/+200 %/+300 % = 2/3/4 items per cycle = 1/2/3/4x output
-- at L0/L1/L2/L3.  Declared here so dmr-tests can assert the ladder.
TimingModel.FUEL_DUP_LEVELS       = { 3, 4, 5 }
TimingModel.DUP_CHANGE_PER_TECH   = 1.0
function TimingModel.fuel_ladder_output(level)
    level = level or 0
    if level < 0 then level = 0 end
    if level > 3 then level = 3 end
    return level + 1        -- 1 / 2 / 3 / 4 items
end

-- ══════════════════════════════════════════════════════════════════
-- 2. Declared pack rungs
--    The pack-set rule cannot place the packs themselves (a tech's pack set
--    is what it is, not what it unlocks), so the 12 packs get an explicit
--    rung. Space/promethium anchor the top of the curve.
-- ══════════════════════════════════════════════════════════════════
TimingModel.PACK_RUNGS = {
    ["automation-science-pack"]    = 1.0,
    ["logistic-science-pack"]      = 2.0,
    ["military-science-pack"]      = 2.1,
    ["chemical-science-pack"]      = 3.0,
    ["production-science-pack"]    = 3.2,
    ["utility-science-pack"]       = 3.4,
    ["space-science-pack"]         = 5.0,
    ["promethium-science-pack"]    = 5.4,
}

-- ══════════════════════════════════════════════════════════════════
-- 3. Planets own a tier (post-rocket, NOT endgame)
-- ══════════════════════════════════════════════════════════════════
TimingModel.PLANET_TIERS = {
    vulcanus = 4.0,
    fulgora  = 4.2,
    gleba    = 4.4,
    aquilo   = 4.6,
}
-- Within a planet band: +0.2 per extra complexity step, never past 4.9.
TimingModel.PLANET_BAND_STEP = 0.2
TimingModel.PLANET_STEPS_PER_SLOT = 10  -- 10 complexity steps = one +0.2 slot
TimingModel.PLANET_BAND_CAP = 4.9

-- ══════════════════════════════════════════════════════════════════
-- 4. Ore ladder (raws) — floor only:
--    time = max(mining_time * K, S(rung))
--    Rungs x1.5 apart, all of them: 3 / 4.5 / 6.8 / 10 / 15.
--    EXCEPTION: a raw listed in DECLARED_RAW_TIMES (dmrsa-tenemut) is
--    priced by that declared value, not by its rung — see the table.
--    R5 was briefly 20 s (2026-10-19) on the strength of the mod's own
--    BASE_RESOURCE_COSTS, but that 20.0 belongs to the DEAD `promethium-ore`
--    entry; the real chunk is listed at 10.0 there. 15 s keeps the rung ladder
--    arithmetic and matches dmr-tests/test_timing_model_v3.lua.
--    v4.4.0 fix: `promethium-ore` was removed — it is NOT a prototype in the
--    game data (only promethium-asteroid-chunk + promethium-science-pack exist).
-- ══════════════════════════════════════════════════════════════════
TimingModel.ORE_K = 3
TimingModel.ORE_RUNGS = { [1] = 3, [2] = 4.5, [3] = 6.8, [4] = 10, [5] = 15 }
TimingModel.ORE_RUNG = {
    -- R1 abundant (mine 0.5-1 s)
    ["iron-ore"]   = 1,
    ["copper-ore"] = 1,
    ["coal"]       = 1,
    ["stone"]      = 1,
    ["calcite"]    = 1,
    ["scrap"]      = 1,
    -- R2 gated (acid, far patches)
    ["uranium-ore"] = 2,
    -- R3 planet-limited solids
    ["tungsten-ore"] = 3,
    -- R4 endgame solids / byproduct
    ["dmrsa-tenemut"] = 4,
    ["holmium-ore"]   = 4,
    -- R5 deepest (→ 20 s, see ORE_RUNGS). `promethium-ore` used to sit here but
    -- is not a prototype in the dumped modlist — removed (dead entry carried by
    -- the mod's own BASE_RESOURCE_COSTS).
    ["promethium-asteroid-chunk"] = 5,
}
-- Fallback mining times (dump-measured). Live data.raw.resource wins when
-- available; this table keeps the model testable outside Factorio.
TimingModel.DECLARED_MINING_TIME = {
    ["iron-ore"] = 1, ["copper-ore"] = 1, ["coal"] = 1, ["stone"] = 1,
    ["calcite"] = 1, ["scrap"] = 0.5, ["uranium-ore"] = 2,
    ["tungsten-ore"] = 5, ["dmrsa-tenemut"] = 2.5,
}

-- DECLARED RAW OVERRIDES — raws whose price is NOT their mining rung.
--
-- dmrsa-tenemut is the mod's GATING resource, not a bulk raw. Its ore rung
-- (R4 = 10 s) priced it at 45.8 MJ on the tier-5 machine — 2.3 % of the
-- Accelerator Ring's 50 GJ cycle — so the ore line was a rounding error and a
-- player who never mined a patch lost nothing (review R3 §3). It is declared
-- at the 200 s ceiling instead = 915.5 MJ on dmrsa-replicator-5 (R 4.5776):
-- 25 tenemut = 22.9 GJ = 46 % of one dark matter, and the L3 ring loop stays
-- positive (50 GJ + 22.9 GJ in -> 100 GJ out = 1.37x). The rung stays in
-- ORE_RUNG as documentation of the price this override replaces; raw_time()
-- checks the override FIRST.
TimingModel.DECLARED_RAW_TIMES = {
    ["dmrsa-tenemut"] = 200,
}

-- Fluids are pumped or refined, not mined — they get their own DECLARED
-- ladder, in SECONDS PER UNIT (the recipe time is per_unit * the replication
-- fluid quantity, 25 by default; the old table was per-craft, which silently
-- coupled the price to the `replication-fluid-quantity` setting).
--
-- M3 (review r1) — WHY THE DERIVED-VALUE PASS WAS REPLACED:
--   `derived_value_time` followed the fluid's downstream chain until it met a
--   BURNABLE and priced the fluid at that burnable's value. That is a printer
--   GUARD, not a price, and it was measuring the wrong end of the chain:
--   water -> steam -> heavy-oil -> solid fuel (depth 3) made water worth 20
--   s/UNIT, so `dmrsa-repl-water` shipped at the 200 s ceiling = 8 MJ per unit
--   of the one fluid the game gives away free. Steam, heavy oil and light oil
--   landed on the same ceiling, and crude oil shipped at 200 s although the
--   receipt documented 67.5 s. The depth-2 comment claimed that kept water out
--   of the net; it did not (a depth-2 path from water reaches solid fuel
--   through heavy oil).
--   Water is FREE in game and a pump costs nothing, so no price derived from
--   its downstream fuel can be honest. The prices below are declared, per
--   unit, ordered by what the fluid actually costs the player:
--     pumped raws (water, steam) -> nominal, at the model floor;
--     the oil family -> priced FROM CRUDE at the solid-fuel rate
--       (100 crude -> 45 light -> solid fuel = 22.2 crude per solid fuel,
--       60 s / 22.2 = 2.70 s per crude unit = 67.5 s per 25-unit craft), so
--       heavy/light/PG inherit crude's price instead of their own burn path;
--     planet/endgame fluids that the derived pass pinned at the ceiling
--       (ammonia, holmium-solution, molten-iron) -> a declared, cheap value.
--   The remaining fluids keep the ladder (they are manufactured, not pumped:
--   lubricant 27.8 s, electrolyte 29.3 s, molten-copper 53.6 s,
--   fluoroketone-hot 125.4 s, thruster fuel/oxidizer 113.3 s per craft), so
--   nothing a player would actually replicate sits at the ceiling.
TimingModel.FLUID_UNIT_TIMES = {
    -- pumped raws: free or near-free in game
    ["water"]            = 0.02,   -- 0.5 s per 25-unit craft
    ["steam"]            = 0.04,   -- 1.0 s (boiled water)
    -- the oil family, priced from crude (see above)
    ["crude-oil"]        = 2.70,   -- 67.5 s per 25-unit craft
    ["heavy-oil"]        = 2.70,   -- 67.5 s
    ["light-oil"]        = 2.70,   -- 67.5 s
    ["petroleum-gas"]    = 2.70,   -- 67.5 s (was 75 s on the ladder)
    -- planet / endgame fluids the derived pass used to pin at the ceiling
    ["ammonia"]          = 1.00,   -- 25 s (was 200 s)
    ["holmium-solution"] = 1.00,   -- 25 s (was 200 s)
    ["molten-iron"]      = 0.50,   -- 12.5 s (was 200 s; lava is unlimited)
    -- declared per-craft values from the previous pass, expressed per unit
    ["lithium-brine"]    = 0.18,   -- 4.5 s per craft
    ["fluorine"]         = 0.18,   -- 4.5 s per craft
    ["fusion-plasma"]    = 1.00,   -- 25 s per craft
}

-- Depth of the (now audit-only) derived-value walk. Kept at 2 because that is
-- the documented crude-oil printer path (crude -> light -> solid fuel); the
-- function no longer prices anything — see derived_value_time().
TimingModel.FLUID_DERIVE_DEPTH = 2

-- Non-minable / non-craftable raws: there is no game number to read, so they
-- get an explicit time (see plan §1 "other non-minables").
TimingModel.NON_MINABLE_TIMES = {
    ["wood"]   = 2,
    ["jellynut"] = 4, ["yumako"] = 4,
    ["jellynut-seed"] = 4, ["yumako-seed"] = 4,
    ["biter-egg"]   = 8,
    ["pentapod-egg"] = 8,
    ["raw-fish"]    = 5,
    ["depleted-uranium-fuel-cell"] = 10,
}

-- DMR's own items have no external chain — own tier, complexity 1.00.
TimingModel.REPLICATOR_TIERS = {
    ["dmrsa-replicator-1"] = 1, ["dmrsa-replicator-2"] = 2,
    ["dmrsa-replicator-3"] = 3, ["dmrsa-replicator-4"] = 4,
    ["dmrsa-replicator-5"] = 5,
}

-- ══════════════════════════════════════════════════════════════════
-- 5. Pure helpers
-- ══════════════════════════════════════════════════════════════════

-- Complexity factor C(steps), capped at C_CAP.
function TimingModel.complexity_factor(steps)
    local c = 1 + TimingModel.C_WEIGHT * (steps or 0)
    if c > TimingModel.C_CAP then c = TimingModel.C_CAP end
    return c
end

-- time = B * g^(tier-1) * C(steps) * replic_mult, clamped to [MIN_TIME, CEILING].
-- F-7a: replic_mult (research difficulty) is applied HERE, before the clamp —
-- the 200 s ceiling is a true ceiling on every difficulty.
function TimingModel.time_for(tier, steps, replic_mult)
    tier = tier or 1
    if tier < 1 then tier = 1 end
    local mult = replic_mult or 1
    local t = TimingModel.B * (TimingModel.G ^ (tier - 1)) * TimingModel.complexity_factor(steps) * mult
    if t > TimingModel.CEILING then t = TimingModel.CEILING end
    if t < TimingModel.MIN_TIME then t = TimingModel.MIN_TIME end
    return t
end

-- Machine R (MJ per craft-second) for a replication recipe's category.
-- tier 1..5, or a planet suffix (the planetary replicators accept ONLY their
-- own category, so a planet-tagged recipe always runs at the planet's R).
function TimingModel.machine_r(tier, planet)
    if planet and TimingModel.PLANET_R[planet] then return TimingModel.PLANET_R[planet] end
    tier = math.floor(tier or 1)
    if tier < 1 then tier = 1 end
    if tier > 5 then tier = 5 end
    return TimingModel.MACHINE_R[tier]
end

-- Pack-set rule: the highest declared rung present in the set; automation-only
-- content sits mid-band (1.5) because the 1.0-1.9 band is red-science content;
-- no packs at all -> 1.0.
function TimingModel.pack_tier_from_set(set)
    if type(set) ~= "table" then return 1.0 end
    local base = 0
    for p in pairs(set) do
        local r = TimingModel.PACK_RUNGS[p]
        if r and r > base then base = r end
    end
    if base == 0 then return 1.0 end
    if base == TimingModel.PACK_RUNGS["automation-science-pack"] then
        return 1.5
    end
    return base
end

-- Planet band: base tier + 0.2 per extra complexity slot, capped at 4.9.
function TimingModel.planet_tier(planet, steps)
    local base = TimingModel.PLANET_TIERS[planet]
    if not base then return nil end
    local slots = math.floor((steps or 0) / TimingModel.PLANET_STEPS_PER_SLOT)
    local tier = base + slots * TimingModel.PLANET_BAND_STEP
    if tier > TimingModel.PLANET_BAND_CAP then tier = TimingModel.PLANET_BAND_CAP end
    return tier
end

-- Ore ladder: time = max(mining_time * K, S(rung)).
function TimingModel.ore_time(rung, mining_time)
    local s = TimingModel.ORE_RUNGS[rung] or TimingModel.ORE_RUNGS[1]
    local mined = (mining_time or 0) * TimingModel.ORE_K
    if mined > s then return mined end
    return s
end

-- fuel_value may be a number (Joules) or a string ("4MJ", "100kJ", "25GJ").
local FUEL_UNITS = { kj = 1e3, mj = 1e6, gj = 1e9, tj = 1e12 }
function TimingModel.fuel_joules(v)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    local num, unit = string.match(v, "^%s*([%d%.]+)%s*(%a+)%s*$")
    if not num then
        local n = tonumber(v)
        return n
    end
    local mult = FUEL_UNITS[string.lower(unit)]
    if not mult then return nil end
    return tonumber(num) * mult
end

-- TRUE for a burnable SOLID/CAPSULE carrying a positive fuel_value.
-- C4: a fluid is never a burnable for pricing purposes (thruster-fuel and
-- thruster-oxidizer at 50 kJ must not enter the fuel ladder), and F-2a: there
-- is no burn-value ceiling any more — every one of them is priced by energy.
function TimingModel.is_burnable(proto)
    if type(proto) ~= "table" then return false end
    if proto.type == "fluid" then return false end
    local j = TimingModel.fuel_joules(proto.fuel_value)
    if not j or j <= 0 then return false end
    return true
end

-- Legacy predicate kept for the Quality Refiner's fuel blacklist
-- (lib/refiner-generator.lua). It is NOT used for pricing any more.
function TimingModel.is_cheap_fuel(proto)
    if type(proto) ~= "table" then return false end
    local j = TimingModel.fuel_joules(proto.fuel_value)
    if not j or j <= 0 then return false end
    return j <= TimingModel.REFINER_FUEL_BLACKLIST_MJ
end

-- The burn-value price (F-2a/F-3b): t = 2 * fuel_value * 2.5 / R seconds,
-- i.e. 5 s per MJ of burn value at R = 1.0 (the fuel class, F-5b), and less
-- time in a machine with a bigger R for exactly the same energy bill.
-- NOT clamped by CEILING: the fuel ladder needs 200-3000 s crafts, and
-- clamping would turn the class back into a printer (F-2a/F-3b decision).
function TimingModel.fuel_time(joules, r)
    local j = joules or 0
    local ratio = r or TimingModel.FUEL_CLASS_R
    if ratio <= 0 then ratio = TimingModel.FUEL_CLASS_R end
    local t = 2 * j * TimingModel.FUEL_BURNER_EFFECTIVITY / (TimingModel.FUEL_REFERENCE_MW * ratio)
    if t < TimingModel.FUEL_MIN_TIME then t = TimingModel.FUEL_MIN_TIME end
    return t
end

-- Escape-hatch predicate: is this burnable's fair price above FUEL_MAX_TIME?
-- (mirror-generator then leaves the item manufacturable but NOT replicable).
function TimingModel.fuel_price_over_max(proto)
    if not TimingModel.is_burnable(proto) then return false end
    local j = TimingModel.fuel_joules(proto.fuel_value)
    return TimingModel.fuel_time(j) > TimingModel.FUEL_MAX_TIME
end

-- C5 — replicate-and-recycle arbitrage clamp.
--
-- APPROVED DECISION (audit-brief-v440 §F-4a, re-derived in review R3 §2.2):
--   floor   repl_time >= parts_bill / (4 * R)
--   ceiling repl_time <= 4 * parts_bill / R
--
-- The floor is the RECYCLE BREAK-EVEN, nothing more: a vanilla recycler
-- returns 25 % of a recipe's parts, so at t = parts/(4R) one craft costs
-- parts/4 MJ == exactly what the recycler gives back (1.00x return — no
-- profit, the exploit is closed). Charging the FULL parts bill per craft
-- (t = parts/R, which shipped in the first 4.4.0 apply pass) is 4x stricter
-- than the exploit requires: it pushed 71 of 259 recipes past the 200 s
-- ceiling, up to 16.6 h for the fusion reactor, and made the replicator dead
-- content for every megastructure. The ceiling stays at 4x the bill (41 items
-- used to sit at 0.086x parts = dead content).
--   parts_mj = SUM over the recipe's ingredients of (amount * replication
--              cost of that ingredient)  — see mirror-generator
--   r        = machine R (MJ per craft-second)
-- returns: time, action ("floor"/"ceiling"/nil), ratio = parts_mj/(time*r)
--   ratio = 4 at the floor (craft == the recycler's 25 % yield),
--   ratio = 0.25 at the ceiling.
function TimingModel.arbitrage_clamp(time, parts_mj, r)
    if not parts_mj or parts_mj <= 0 or not r or r <= 0 then return time, nil, nil end
    local lo = parts_mj / (4 * r)      -- recycle break-even: craft == 0.25 * parts
    local hi = 4 * parts_mj / r
    local action
    if time < lo then
        time, action = lo, "floor"
    elseif time > hi then
        time, action = hi, "ceiling"
    end
    return time, action, parts_mj / (time * r)
end

-- C5 — the FIXED-POINT pass (v4.4.0 A6): the floor above is only exact when the
-- parts bill is priced with the FINAL (post-floor) cost of every ingredient.
-- One pass over a hash table is NOT that: a recipe whose ingredient was itself
-- floored still bills that ingredient at its MODEL time, so the recycler keeps
-- a profit on the difference (measured: rail-support 5.26x, space-platform
-- starter pack 1.29x, assembling-machine-3 1.15x, cargo-bay 1.09x).
--
-- Because every edge of the dependency graph points from a target to the
-- targets among its own recipe's ingredients, ONE pass in TOPOLOGICAL order is
-- an exact fixed point: by the time a target is priced, every ingredient it
-- depends on already holds its final time. No iteration is needed (and none is
-- wanted — iterating a cyclic graph is what blew fusion-reactor up to 1e7 s in
-- the rejected experiment; a DAG has no such feedback).
--
--   entries[name] = { model_time = s, r = MJ/craft-second, amount = result_amount }
--   deps[name]    = { [other_name] = true }   (this target's ingredients)
--   bill_of(name, price) -> parts bill in MJ, where price(ingredient) returns
--                    the FINAL per-unit MJ of an ingredient (nil when the
--                    ingredient is not a priced target)
--
-- Returns results[name] = { time, action, ratio, bill, model_time, r } plus a
-- report { order, floors, ceilings, total, cycles = { {from,to}, ... } }.
-- A dependency cycle cannot hang: the back-edge ingredient is priced at its
-- nominal (model) time and the cycle is reported as an approximation.
function TimingModel.arbitrage_fixpoint(entries, deps, bill_of)
    local names = {}
    for name in pairs(entries or {}) do names[#names + 1] = name end
    table.sort(names)                       -- deterministic on every host

    local results, order, state = {}, {}, {}
    local cycles, seen_cycle = {}, {}

    local function price(name)
        local e = entries[name]
        if not e then return nil end
        local done = results[name]
        local t = done and done.time or e.model_time
        return (t * e.r) / (e.amount or 1)
    end

    local function visit(name, parent)
        if state[name] == 2 then return end
        if state[name] == 1 then
            -- back-edge: the caller keeps this dependency at its nominal price
            local key = (parent or "?") .. "->" .. name
            if not seen_cycle[key] then
                seen_cycle[key] = true
                cycles[#cycles + 1] = { from = parent, to = name }
            end
            return
        end
        state[name] = 1
        local ds = {}
        for d in pairs(deps[name] or {}) do ds[#ds + 1] = d end
        table.sort(ds)
        for _, d in ipairs(ds) do
            if entries[d] and state[d] ~= 2 then visit(d, name) end
        end
        state[name] = 2
        order[#order + 1] = name
    end
    for _, name in ipairs(names) do visit(name, nil) end

    local floors, ceilings = 0, 0
    for _, name in ipairs(order) do
        local e = entries[name]
        local bill = bill_of(name, price)
        local t, action, ratio = TimingModel.arbitrage_clamp(e.model_time, bill, e.r)
        -- Round UP to the shipped 0.01 s: rounding DOWN would put the craft a
        -- hair under the floor and leave a 1.0001x residual on the dump check.
        local shipped = math.max(TimingModel.MIN_TIME, math.ceil(t * 100 - 1e-9) / 100)
        results[name] = {
            time = shipped, action = action, ratio = ratio, bill = bill,
            model_time = e.model_time, r = e.r,
        }
        if action == "floor" then floors = floors + 1
        elseif action == "ceiling" then ceilings = ceilings + 1 end
    end

    -- cycles[i].to is the ingredient that was still unfinished; resolve the
    -- pair for the log (the DFS parent is not tracked, so report the node).
    return results, {
        order = order, floors = floors, ceilings = ceilings,
        total = #order, cycles = cycles,
    }
end

-- C5 — the PARTS BILL of an item, in MJ, measured in the mirror's own terms.
--   ingredient_lists = array of candidate recipes, each an array of
--                      { name, amount } pairs (the item's producing recipes)
--   cost_of(name)    -> MJ of replicating one unit of that ingredient
-- Returns the MINIMUM bill over the candidates (the arbitrage question is
-- literally "is there a cheaper way to make this from replicated parts?"),
-- or nil when no candidate has ingredients.
-- Minimum and not "the simplest recipe" on purpose: several recipes can
-- produce the same item (concrete vs concrete-from-molten-iron) and a
-- metal-casting recipe would otherwise invent a parts bill out of a fluid
-- byproduct chain.
function TimingModel.parts_bill_mj(ingredient_lists, cost_of)
    local bill
    for _, ings in ipairs(ingredient_lists or {}) do
        if ings and #ings > 0 then
            local sum = 0
            for _, ing in ipairs(ings) do
                local iname, amount = ing[1], ing[2]
                if iname and amount then
                    local c = cost_of(iname)
                    if c then sum = sum + amount * c end
                end
            end
            if sum > 0 and (not bill or sum < bill) then bill = sum end
        end
    end
    return bill
end

-- ══════════════════════════════════════════════════════════════════
-- 6. Live data readers (lazy)
-- ══════════════════════════════════════════════════════════════════
local mining_index = nil
local function resource_mining_time(name)
    if mining_index == nil then
        mining_index = {}
        local resources = (data and data.raw and data.raw.resource) or {}
        for _, res in pairs(resources) do
            if type(res) == "table" and res.minable then
                local t = res.minable.mining_time
                local results = res.minable.results
                if not results and res.minable.result then
                    results = { { name = res.minable.result } }
                end
                if results and t then
                    for _, r in ipairs(results) do
                        local rn = r.name or r[1]
                        if rn then
                            local cur = mining_index[rn]
                            if not cur or t < cur then mining_index[rn] = t end
                        end
                    end
                end
            end
        end
    end
    if mining_index[name] then return mining_index[name] end
    return TimingModel.DECLARED_MINING_TIME[name]
end

-- Explicit raw/non-craftable time, or nil when `name` is not a raw.
-- Fluids are handled by resolve() (declared base + derived-value floor).
function TimingModel.raw_time(name)
    local declared = TimingModel.DECLARED_RAW_TIMES[name]
    if declared then return declared, "declared" end
    local rung = TimingModel.ORE_RUNG[name]
    if rung then
        return TimingModel.ore_time(rung, resource_mining_time(name)), "ore"
    end
    local nt = TimingModel.NON_MINABLE_TIMES[name]
    if nt then return nt, "non-minable" end
    return nil
end

-- Item/fuel prototype lookup by name across the item registries (a chemical
-- fuel lives in `item` or `capsule` in the real data). Returns nil outside
-- Factorio or when the name is unknown. resolve() uses it so the energy rule
-- still fires when the caller did not pass opts.item_proto.
TimingModel.PROTO_REGISTRIES = {
    "item", "capsule", "ammo", "module", "tool", "armor", "gun",
    "item-with-entity-data", "item-with-tags", "spidertron-remote",
    "space-platform-starter-pack",
}
function TimingModel.find_proto(name)
    if type(name) ~= "string" then return nil end
    local raw = data and data.raw
    if not raw then return nil end
    if raw.fluid and raw.fluid[name] then return raw.fluid[name] end
    for _, reg in ipairs(TimingModel.PROTO_REGISTRIES) do
        local tbl = raw[reg]
        if tbl and tbl[name] then return tbl[name] end
    end
    return nil
end

-- F-1a (decision 2026-10-19): tenemut replicates ONLY on the tier-5 machine
-- ("Dominio de la Materia Oscura", AGENTS.md §5/§10). The v4.4.0 experiment of
-- following where the ore appears put it on tier 1 (a tier-1 replicator at
-- 1 MW, 10 s = 10 MJ per tenemut), which removed the mod's ore-scarcity
-- premise. Where-tenemut-appears logic stays available for other ores through
-- planet_tier(); tenemut itself is pinned to 5.
function TimingModel.tenemut_tier()
    return 5
end

-- Kept for reference/documentation: the tier tenemut WOULD have got from the
-- source setting ("Synthesis only"/"Ore patches + synthesis" → 1.0 = the
-- synthesizer is a day-one machine; a planet list → the LOWEST planet).
function TimingModel.tenemut_source_tier()
    local src = "Ore patches"
    if helpers and helpers.get_tenemut_source then
        src = helpers.get_tenemut_source() or "Ore patches"
    end
    if src == "Synthesis only" or src == "Ore patches + synthesis" then
        return 1.0
    end
    local spawning = "Nauvis"
    if helpers and helpers.get_startup_setting then
        spawning = helpers.get_startup_setting("tenemut-spawning-planet", "Nauvis") or "Nauvis"
    end
    local candidates = {}
    if spawning == "Nauvis" then
        candidates["nauvis"] = 1.0
    else
        local p = string.lower(spawning)
        if TimingModel.PLANET_TIERS[p] then candidates[p] = TimingModel.PLANET_TIERS[p] end
    end
    local other = "None"
    if helpers and helpers.get_startup_setting then
        other = helpers.get_startup_setting("tenemut-other-planets", "None") or "None"
    end
    if other == "All Except Nauvis" or other == "All" then
        for p, t in pairs(TimingModel.PLANET_TIERS) do candidates[p] = t end
    end
    if other == "All" then candidates["nauvis"] = 1.0 end
    local best
    for _, t in pairs(candidates) do
        if not best or t < best then best = t end
    end
    return best or 1.0
end

-- ══════════════════════════════════════════════════════════════════
-- 7. Complexity (steps) = unique crafted items in the item's tree
-- ══════════════════════════════════════════════════════════════════
local recipe_index = nil

-- product name -> simplest producing recipe (fewest ingredients), excluding
-- recycling/barreling and DMR's own generated recipes (same class as the
-- cost-solver map).
function TimingModel.build_recipe_index()
    recipe_index = {}
    local recipes = (data and data.raw and data.raw.recipe) or {}
    local function ing_count(r)
        local ings = r.ingredients or (r.normal and r.normal.ingredients)
        if ings then return #ings end
        return 99
    end
    for rname, r in pairs(recipes) do
        local skip = string.find(rname, "^dmrsa%-")
            or rname == "recycling"
            or string.find(rname, "%-recycling$")
            or string.find(rname, "^empty%-")
            or string.find(rname, "%-unbarrel$")
        if not skip then
            local results = r.results
            if not results and r.normal and r.normal.results then results = r.normal.results end
            if not results and r.result then
                results = { { name = r.result } }
            end
            if results then
                for _, res in ipairs(results) do
                    local pn = res.name or res[1]
                    if pn then
                        local cur = recipe_index[pn]
                        if not cur or ing_count(r) < ing_count(cur) then
                            recipe_index[pn] = r
                        end
                    end
                end
            end
        end
    end
    return recipe_index
end

function TimingModel.get_recipe_index()
    if not recipe_index then TimingModel.build_recipe_index() end
    return recipe_index
end

-- The recipe the model considers the item's producer (nil for raws).
function TimingModel.recipe_for(name)
    return TimingModel.get_recipe_index()[name]
end

-- C4: recipe index keyed by CONSUMER — fluid/item name -> { producing recipes }.
local consumer_index = nil
function TimingModel.build_consumer_index()
    consumer_index = {}
    local recipes = (data and data.raw and data.raw.recipe) or {}
    for rname, r in pairs(recipes) do
        local skip = string.find(rname, "^dmrsa%-")
            or rname == "recycling"
            or string.find(rname, "%-recycling$")
            or string.find(rname, "^empty%-")
            or string.find(rname, "%-unbarrel$")
        if not skip then
            local ings = r.ingredients or (r.normal and r.normal.ingredients)
            local results = r.results or (r.normal and r.normal.results)
            if not results and r.result then results = { { name = r.result } } end
            if ings and results then
                for _, ing in ipairs(ings) do
                    local iname = ing.name or ing[1]
                    if iname then
                        consumer_index[iname] = consumer_index[iname] or {}
                        table.insert(consumer_index[iname], r)
                    end
                end
            end
        end
    end
    return consumer_index
end

function TimingModel.get_consumer_index()
    if not consumer_index then TimingModel.build_consumer_index() end
    return consumer_index
end

-- C4 — DERIVED VALUE of one unit of a fluid, in seconds at R = 1.0.
-- AUDIT TOOL, NOT A PRICE (M3): resolve() no longer calls this. It walks the
-- recipes that consume the fluid (depth <= FLUID_DERIVE_DEPTH) and reports the
-- burn value of the fuel it ultimately becomes, which is what the old pricing
-- rule used — and why water shipped at 500 s/craft: at depth 2 water reaches
-- solid fuel through heavy oil, so "water is at depth 3" was false. Kept
-- because dmr-tests uses it as the printer cross-check (a fluid priced below
-- its derived value would be a fuel printer); the DECLARED ladder wins.
-- Example (dump):
--   crude-oil -> advanced-oil-processing (100 crude -> 45 light) -> solid-fuel
--   from light-oil (10 light -> 1 solid fuel): 22.2 crude per solid fuel =>
--   derived(1 crude) = 60 s / 22.2 = 2.7 s => 67.5 s per 25-unit craft
--   (the flat 1 s row that used to make crude oil a 7.1x printer).
-- Returns nil when the fluid never becomes a burnable.
function TimingModel.derived_value_time(name)
    local idx = TimingModel.get_consumer_index()
    local best = nil
    local function expand(current, units_per_current, depth, seen)
        if depth > TimingModel.FLUID_DERIVE_DEPTH then return end
        for _, recipe in ipairs(idx[current] or {}) do
            local ings = recipe.ingredients or (recipe.normal and recipe.normal.ingredients)
            local res = recipe.results or (recipe.normal and recipe.normal.results)
            if not res and recipe.result then res = { { name = recipe.result } } end
            if ings and res then
                local consumed = 0
                for _, ing in ipairs(ings) do
                    if (ing.name or ing[1]) == current then
                        consumed = consumed + (ing.amount or 1)
                    end
                end
                if consumed > 0 then
                    for _, out in ipairs(res) do
                        local pname = out.name or out[1]
                        local pamount = out.amount or 1
                        if pname and pamount > 0 and pname ~= current then
                            local per_product = units_per_current * consumed / pamount
                            local proto = TimingModel.find_proto(pname)
                            local j = proto and TimingModel.fuel_joules(proto.fuel_value)
                            if j and j > 0 and proto.type ~= "fluid" then
                                local v = TimingModel.fuel_time(j) / per_product
                                if not best or v > best then best = v end
                            elseif not seen[pname] then
                                seen[pname] = true
                                expand(pname, per_product, depth + 1, seen)
                                seen[pname] = nil
                            end
                        end
                    end
                end
            end
        end
    end
    expand(name, 1, 1, { [name] = true })
    return best
end

-- Count the unique crafted items in `name`'s full ingredient tree (the item
-- itself included when it has a recipe). Cycle-safe.
function TimingModel.steps_of(name)
    local idx = TimingModel.get_recipe_index()
    local seen, stack = {}, { name }
    local n = 0
    while #stack > 0 do
        local item = table.remove(stack)
        if not seen[item] then
            local recipe = idx[item]
            if recipe then
                seen[item] = true
                n = n + 1
                local ings = recipe.ingredients or (recipe.normal and recipe.normal.ingredients)
                if ings then
                    for _, ing in ipairs(ings) do
                        local iname = ing.name or ing[1]
                        if iname and not seen[iname] and idx[iname] then
                            stack[#stack + 1] = iname
                        end
                    end
                end
            end
        end
    end
    return n
end

-- ══════════════════════════════════════════════════════════════════
-- 8. Top-level resolution
--    opts = { name, chain_tier, planet, pack_tier, steps, item_proto,
--             replic_mult, result_amount, is_fluid }
--    returns { time, tier, source, exempt_caps }
--    `exempt_caps` is true only for the fuel class: its price is written for
--    R = 1.0 and must NOT be squeezed back under the 200 s ceiling or the
--    per-difficulty safety cap (F-2a/F-3b — clamping it re-opens the printer).
-- ══════════════════════════════════════════════════════════════════
function TimingModel.resolve(opts)
    opts = opts or {}
    local name = opts.name
    local steps = opts.steps or 0
    local chain = opts.chain_tier or 1
    local mult = opts.replic_mult or 1
    local result_amount = opts.result_amount or 1

    -- (a) declared pack rung
    local pr = TimingModel.PACK_RUNGS[name]
    if pr then
        return { time = TimingModel.time_for(pr, steps, mult), tier = pr, source = "pack-rung" }
    end

    local proto = opts.item_proto or TimingModel.find_proto(name)

    -- (b) BURNABLE SOLIDS priced by ENERGY (F-2a/F-3b) — takes precedence over
    --     the ore ladder, the fluid rule and the tier ladder. A burnable's
    --     replication time is set by the energy it returns, never by a
    --     mining/ladder rung: before this fix uranium fuel cells (8 GJ, above
    --     the old 100 MJ cap) fell through to the ladder and priced at 88 MJ
    --     = a 90x printer. Fluids are excluded (C4) — see (c).
    if proto and TimingModel.is_burnable(proto) then
        local j = TimingModel.fuel_joules(proto.fuel_value)
        return {
            time = TimingModel.fuel_time(j) * mult,
            tier = chain,
            source = "fuel",
            exempt_caps = true,
        }
    end

    -- (c) fluids: declared per-unit price (M3) or the tier ladder. The
    --     derived-value walk is NOT applied any more — it priced water at the
    --     ceiling; see FLUID_UNIT_TIMES.
    local is_fluid = opts.is_fluid
        or (proto and proto.type == "fluid")
        or (TimingModel.FLUID_UNIT_TIMES[name] ~= nil)
        or (data and data.raw and data.raw.fluid and data.raw.fluid[name] ~= nil)
    if is_fluid then
        local per_unit = TimingModel.FLUID_UNIT_TIMES[name]
        local t, source
        if per_unit then
            t, source = per_unit * result_amount * mult, "fluid"
        else
            t = TimingModel.time_for(math.max(chain, opts.pack_tier or 1.0), steps, mult)
            source = "fluid-ladder"
        end
        if t > TimingModel.CEILING then t = TimingModel.CEILING end
        if t < TimingModel.MIN_TIME then t = TimingModel.MIN_TIME end
        return { time = t, tier = chain, source = source }
    end

    -- (d) raw / non-minable ladder (no tier ladder)
    local rt, rkind = TimingModel.raw_time(name)
    if rt then
        rt = rt * mult
        if rt > TimingModel.CEILING then rt = TimingModel.CEILING end
        if rt < TimingModel.MIN_TIME then rt = TimingModel.MIN_TIME end
        return { time = rt, tier = chain, source = rkind }
    end

    -- (e) DMR replicators: own tier, complexity 1.00
    local repl = TimingModel.REPLICATOR_TIERS[name]
    if repl then
        return { time = TimingModel.time_for(repl, 0, mult), tier = repl, source = "replicator" }
    end

    -- (f) planet band
    if opts.planet then
        local pt = TimingModel.planet_tier(opts.planet, steps) or chain
        return { time = TimingModel.time_for(pt, steps, mult), tier = pt, source = "planet" }
    end

    -- (g) tier = max(pack_tier, chain_tier)
    local tier = math.max(chain, opts.pack_tier or 1.0)
    return { time = TimingModel.time_for(tier, steps, mult), tier = tier, source = "ladder" }
end

return TimingModel
