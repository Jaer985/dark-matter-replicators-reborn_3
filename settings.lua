require("defines")

local planets = { "Nauvis" }
local default_planet = "Nauvis" -- Default is always Nauvis for seamless early game progression
if mods["space-age"] then
	table.insert(planets, "Vulcanus")
	table.insert(planets, "Fulgora")
	table.insert(planets, "Gleba")
	table.insert(planets, "Aquilo")
end

-- DMR Startup and Balancing Settings
data:extend({
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
		default_value = 2,
		minimum_value = 0.001
	},
	{
		name = "replstats-energy-base",
		type = "double-setting",
		order = "1-2-1",
		setting_type = "startup",
		default_value = 256,
		minimum_value = 0.001
	},
	{
		name = "replstats-energy-factor",
		type = "double-setting",
		order = "1-2-2",
		setting_type = "startup",
		default_value = 2.5,
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
		name = "dmrsa-tech-distribution",
		type = "string-setting",
		order = "5-1",
		setting_type = "startup",
		allowed_values = { "Individual Technologies", "Base Game Technologies", "Grouped Categories" },
		default_value = "Grouped Categories",
	},
	{
		name = "dmrsa-grouped-tech-cost-multiplier",
		type = "double-setting",
		order = "5-1-a",
		setting_type = "startup",
		default_value = 5.0,
		minimum_value = 0.1,
	},
	{
		name = "dmrsa-cost-calculation-method",
		type = "string-setting",
		order = "5-2",
		setting_type = "startup",
		allowed_values = { "Recursive Steps (Compounding)", "Raw Ingredients (Flat)" },
		default_value = "Raw Ingredients (Flat)",
	},
	{
		name = "dmrsa-dereplication-ratio",
		type = "double-setting",
		order = "5-3",
		setting_type = "startup",
		default_value = 0.5,
		minimum_value = 0,
		maximum_value = 1
	}
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
			order = "1-1-3",
			setting_type = "startup",
			default_value = false,
		}
	})
end