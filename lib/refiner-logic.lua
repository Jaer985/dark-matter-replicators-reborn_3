-- lib/refiner-logic.lua — v4.6.0
--
-- Pure logic for the AUTOMATIC Quality Refiner. No engine calls at module load:
-- everything takes its inputs as arguments so dmr-tests can exercise it with
-- plain Lua 5.2 (the mod's test harness).
--
-- Design (author-approved 2026-10-24):
--   * the refiner has NO recipes to choose. One hidden fixed recipe keeps the
--     machine powered; control.lua does the work on a timer.
--   * a cycle takes `cycle_seconds(repl_time)` = clamp(round(repl_time / 6.32), 1, 5)
--     seconds — i.e. 1 s per tier, 1..5.
--   * each attempt moves an item ONE quality level at most: probability by
--     position in the sorted ladder (5 %, 2.5 %, 1.25 %, 1 %, floor 1 %) and a
--     flat 1 % chance of destroying the item. No skips, ever.

local M = {}

M.BASE_SECONDS = 6.32   -- tier-1 replication time (timing model v3)
M.LOSS_PROB = 0.01
M.FIRST_STEP_P = 0.05
M.STEP_MIN_P = 0.01

--- Sorted quality ladder from a prototypes.quality-like table.
-- Skips the engine's `quality-unknown` pseudo-quality and anything without a
-- numeric level (the test fixtures omit it — QUALITY_NAME_RANK covers that).
function M.ladder(qualities)
    local rank = { normal = 0, uncommon = 1, rare = 2, epic = 3, legendary = 5 }
    local list = {}
    for name, proto in pairs(qualities or {}) do
        if name ~= "quality-unknown" then
            local lvl = proto and proto.level
            if type(lvl) ~= "number" then lvl = rank[name] end
            if lvl then list[#list + 1] = { name = name, level = lvl } end
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

--- Index of `level` in the ladder (1-based), or nil.
function M.index_of(ladder, level)
    for i, q in ipairs(ladder) do
        if q.level == level then return i end
    end
    return nil
end

--- The next quality up, or nil when already at the top.
function M.next_level(ladder, level)
    local i = M.index_of(ladder, level)
    if not i then return nil end
    return ladder[i + 1], i
end

--- Probability of one successful step, by ladder position.
function M.step_probability(position)
    local p = M.FIRST_STEP_P * (0.5 ^ (position - 1))
    if p < M.STEP_MIN_P then p = M.STEP_MIN_P end
    return p
end

--- Seconds per attempt: one per tier, 1..5.
-- The replication ladder DOUBLES per tier (6.32, 12.64, 25.28, 50.56, 101.12),
-- so the tier is log2(time / base) + 1 — not a linear division.
function M.cycle_seconds(repl_time)
    local ratio = (repl_time or M.BASE_SECONDS) / M.BASE_SECONDS
    if ratio < 1 then ratio = 1 end
    local tier = math.floor(math.log(ratio) / math.log(2) + 0.5) + 1
    if tier < 1 then tier = 1 end
    if tier > 5 then tier = 5 end
    return tier
end

--- Outcome of one attempt. `rnd` is injected (math.random in game) so the tests
-- are deterministic.
-- @return "up" | "loss" | "keep"
function M.roll(p_up, rnd, p_loss)
    local x = rnd or 0
    if x < p_up then return "up" end
    if x < p_up + (p_loss or M.LOSS_PROB) then return "loss" end
    return "keep"
end

return M
