require("defines")

local planets = { "Nauvis" }
local default_planet = "Nauvis" -- Default is always Nauvis for seamless early game progression
if mods["space-age"] then
	table.insert(planets, "Vulcanus")
	table.insert(planets, "Fulgora")
	table.insert(planets, "Gleba")
	table.insert(planets, "Aquilo")
end

-- v3.7.0 (C1): auto-detect overhaul mods. When Bob's / Angel's / K2 are
-- active, the grouped replication techs cover hundreds more items, so the
-- default grouped-tech cost multiplier is raised to keep research meaningful.
-- Zero-config: the player can still override the setting in the options.
local OVERHAUL_MOD_NAMES = {
    "bobplates", "bobassembly", "bobtech", "bobores", "boblogistics",
    "bobmodules", "bobwarfare", "bobpower", "bobmining",
    "angelssmelting", "angelsrefining", "angelsindustries", "angelspetrochem",
    "Krastorio2", "SpaceExtension",
}
local default_grouped_mult = 10.0
for _, mod_name in ipairs(OVERHAUL_MOD_NAMES) do
    if mods[mod_name] then
        default_grouped_mult = 15.0
        break
    end
end

-- DMR Startup and Balancing Settings
data:extend({
	{
		name = "dmrsa-log-level",
		type = "string-setting",
		order = "9-1",
		setting_type = "startup",
		allowed_values = { "none", "error", "warn", "info", "debug" },
		default_value = "warn",
	},
	{
		-- v4.3: where tenemut comes from.
		--   "Ore patches" (default)     — historical behaviour: tenemut ore
		--                                 generates in worldgen, and the
		--                                 synthesizer machine does not exist.
		--   "Ore patches + synthesis"   — the ore still generates AND the
		--                                 Dark Matter Synthesizer is available.
		--   "Synthesis only"            — tenemut is REMOVED from worldgen;
		--                                 the synthesizer (electricity only) is
		--                                 the only source.
		-- The resource prototype itself is always kept (save compatibility:
		-- maps already generated keep their patches); only its autoplace spec,
		-- the autoplace-control and the planet map-gen injection are gated.
		name = "dmrsa-tenemut-source",
		type = "string-setting",
		order = "1-0-1",
		setting_type = "startup",
		allowed_values = { "Ore patches", "Ore patches + synthesis", "Synthesis only" },
		default_value = "Ore patches",
	},
	{
		name = "tenemut-near-spawn",
		type = "bool-setting",
		order = "1-1-0",
		setting_type = "startup",
		default_value = true,
	},
	{
		name = "tenemut-spawning-planet",
		type = "string-setting",
		order = "1-1-1",
		setting_type = "startup",
		allowed_values = planets,
		default_value = default_planet, -- Fully configurable dropdown inside Factorio's Mod Settings
	},
	{
		name = "replstats-speed-base",
		type = "double-setting",
		order = "1-1-3",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0.001
	},
	{
		name = "replstats-speed-factor",
		type = "double-setting",
		order = "1-1-4",
		setting_type = "startup",
		default_value = 1.6, -- v4.2.2: B2 balance (1/1.6/2.56/4.1/6.55 ramp) — was 2 (pre-B2 stale, R1)
		minimum_value = 0.001
	},
	{
		name = "replstats-pollution-base",
		type = "double-setting",
		order = "1-3-1",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0
	},
	{
		name = "replstats-pollution-factor",
		type = "double-setting",
		order = "1-3-2",
		setting_type = "startup",
		default_value = 1.75,
		minimum_value = 0
	},
	{
		name = "replstats-size-base",
		type = "double-setting",
		order = "1-4-1",
		setting_type = "startup",
		default_value = 2,
		minimum_value = 1
	},
	{
		name = "replstats-size-addend",
		type = "double-setting",
		order = "1-4-3",
		setting_type = "startup",
		default_value = 0
	},
	{
		name = "replstats-modules-base",
		type = "double-setting",
		order = "1-5-1",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0
	},
	{
		name = "replstats-modules-addend",
		type = "double-setting",
		order = "1-5-3",
		setting_type = "startup",
		default_value = 0.5
	},
	{
		name = "replresearch-item-multiplier",
		type = "double-setting",
		order = "3-1-1",
		setting_type = "startup",
		default_value = 25,
		minimum_value = 0.001
	},
	{
		name = "replresearch-item-time",
		type = "double-setting",
		order = "3-1-2",
		setting_type = "startup",
		default_value = 5,
		minimum_value = 0.001
	},
	{
		name = "replresearch-space-lock",
		type = "int-setting",
		order = "3-2-1",
		setting_type = "startup",
		default_value = 6,
		allowed_values = {1, 2, 3, 4, 5, 6}
	},
	{
		name = "dmrsa-research-difficulty",
		type = "string-setting",
		order = "3-2-2",
		setting_type = "startup",
		allowed_values = { "Easy (Fast)", "Medium", "High", "Very Hard" },
		default_value = "Easy (Fast)",
	},
	{
		name = "dmrsa-research-pack-order",
		type = "string-setting",
		order = "3-2-3",
		setting_type = "startup",
		allowed_values = { "DMR Item First", "Science Pack First" },
		default_value = "DMR Item First",
	},
	{
		name = "replication-penalty",
		type = "double-setting",
		order = "4-1",
		setting_type = "startup",
		default_value = 0.5,
		minimum_value = 0
	},
	{
		name = "replication-fluid-quantity",
		type = "int-setting",
		order = "4-2",
		setting_type = "startup",
		default_value = 25,
		minimum_value = 1
	},
	{
		name = "dmrsa-tenemut-research-required",
		type = "bool-setting",
		order = "3-2-4",
		setting_type = "startup",
		-- v4.3: when disabled, the DMR material packs (tenemut, scoop,
		-- transducer, conduit) are no longer required to research replication —
		-- the techs use the vanilla science packs of their own tier instead.
		-- Nothing else changes: the packs stay craftable/usable.
		default_value = true,
	},
	{
		name = "dmrsa-tech-distribution",
		type = "string-setting",
		order = "5-1",
		setting_type = "startup",
		-- v4.0: Mirror (default) — árbol espejo: 1 tech por tech original del
		-- juego, tier = science level de la tech original, prereq = tech
		-- original + materials del tier. Individual (legacy) — 1 tech por item
		-- como v3.7.x. Grouped Categories fue ELIMINADO en v4.0.
		allowed_values = { "Mirror", "Individual" },
		default_value = "Mirror",
	},
	{
		name = "dmrsa-require-original-tech",
		type = "bool-setting",
		order = "5-1-b",
		setting_type = "startup",
		default_value = true,
	},
	{
		name = "dmrsa-grouped-tech-cost-multiplier",
		type = "double-setting",
		order = "5-1-a",
		setting_type = "startup",
		default_value = default_grouped_mult,  -- v3.7.0 (C1): 10.0 base, 15.0 with overhaul mods
		minimum_value = 0.1,
	},
	{
		name = "dmrsa-use-machine-efficiency",
		type = "bool-setting",
		order = "5-3",
		setting_type = "startup",
		default_value = true,
	},
	{
		name = "dmrsa-replicator-quality",
		type = "string-setting",
		order = "5-4",
		setting_type = "startup",
		allowed_values = { "Normal only", "Allow quality" },
		default_value = "Normal only",
	},
})

if mods["space-age"] then
	data:extend({
		{
			name = "tenemut-other-planets",
			type = "string-setting",
			order = "1-1-2",
			setting_type = "startup",
			allowed_values = { "None", "All Except Nauvis", "All" },
			default_value = "None"
		},
	})
end

if mods["space-exploration"] or mods["space-age"] then
	data:extend({
		{
			name = "replication-in-space",
			type = "bool-setting",
			order = "1-6-1",
			setting_type = "startup",
			default_value = false,
		}
	})
end