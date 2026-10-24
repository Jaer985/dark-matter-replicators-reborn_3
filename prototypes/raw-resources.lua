require("defines")
local helpers = require("lib.helpers")
local resource_autoplace = require("resource-autoplace")

-- v4.3 (mod portal request, evil_star): tenemut can now be produced from
-- electricity instead of being mined, so the ore itself is optional.
--
-- `dmrsa-tenemut-source = "Synthesis only"` removes tenemut from world
-- generation COMPLETELY:
--   * the resource-autoplace patch set is not initialized,
--   * the autoplace spec is not attached to the resource,
--   * no autoplace-control prototype is registered (so the map-generation
--     screen has no Tenemut slider and no preset can enable it), and
--   * data-updates.lua does not inject the control into any planet.
--
-- The `resource` prototype ITSELF is kept in every mode on purpose: it carries
-- no autoplace in synthesis-only mode (so nothing can ever be placed), but
-- dropping it would break every existing save that already mined/placed
-- tenemut patches — those maps keep their ore and stay loadable.

local worldgen_enabled = helpers.tenemut_worldgen_enabled()

if worldgen_enabled then
	-- Registers the patch set the autoplacer uses for this resource. Must only
	-- run when the resource actually autocplaces.
	resource_autoplace.initialize_patch_set(gprefix.."tenemut", true)
end

local autoplace_table = {
	name = gprefix.."tenemut",
	order = "c",
	base_density = 0.9,
	--base_spots_per_km2 = 1.25,
	base_spots_per_km2 = 1.0,
	has_starting_area_placement = true,
	random_spot_size_minimum = 2,
	random_spot_size_maximum = 4,
	regular_rq_factor_multiplier = 1
}

local spawn_setting = settings.startup["tenemut-near-spawn"]
if spawn_setting and spawn_setting.value == false then
	autoplace_table.has_starting_area_placement = false
end

if worldgen_enabled and mods["space-exploration"] then
--[[
se_default = {
  base_density = 5,
  has_starting_area_placement = true,
  name = "dmrsa-tenemut",
  order = "z-dmrsa-tenemut",
  regular_rq_factor_multiplier = 1.1000000000000001,
  starting_rq_factor_multiplier = 1
}
]]
	se_resources = se_resources or {}
	autoplace_table.base_density = 5
	se_resources[gprefix.."tenemut"] = autoplace_table

	se_core_fragment_resources = se_core_fragment_resources or {}
	se_core_fragment_resources[gprefix.."tenemut"] = { multiplier = 0.2, omni_multiplier = 0.01}
end

local resource = {
	type = "resource",
	name = gprefix.."tenemut",
	icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png",
	icon_size = 64,
	flags = {"placeable-neutral"},
	order = "b-b-rep",
	tree_removal_probability = 0.2,
	tree_removal_max_distance = 16 * 16,
	minable = {
		mining_particle = gprefix.."tenemut-particle",
		mining_time = 2.5,
		result = gprefix.."tenemut"
	},
	collision_box = {{ -0.1, -0.1}, {0.1, 0.1}},
	selection_box = {{ -0.5, -0.5}, {0.5, 0.5}},
	-- v4.3: no autoplace spec in "Synthesis only" — the game's autoplacer has
	-- nothing to place, and the control it would reference is not registered.
	autoplace = worldgen_enabled and resource_autoplace.resource_autoplace_settings(autoplace_table) or nil,
	stage_counts = {2500, 2000, 1500, 1000, 500, 250, 100, 40},
	stages = {
		sheet = {
			filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut.png",
			priority = "extra-high",
			width = 64,
			height = 64,
			frame_count = 8,
			variation_count = 8
		}
	},
	map_color = {r=0.550, g=0.392, b=0.550}
}

-- The mining particle is a plain visual used by the resource's minable: keep
-- it in every mode (it costs nothing and keeps the prototype set identical
-- between modes, which is friendlier to blueprint/save diffs).
data:extend(
{
	{
		type = "optimized-particle",
		name = gprefix.."tenemut-particle",
		flags = {}, --{"not-on-map"},
		life_time = 180,
		pictures =
		{
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-1.png",
				priority = "extra-high",
				width = 5,
				height = 5,
				frame_count = 1
			},
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-2.png",
				priority = "extra-high",
				width = 6,
				height = 4,
				frame_count = 1
			},
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-3.png",
				priority = "extra-high",
				width = 7,
				height = 8,
				frame_count = 1
			},
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-4.png",
				priority = "extra-high",
				width = 6,
				height = 5,
				frame_count = 1
			}
		},
		shadows =
		{
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-shadow-1.png",
				priority = "extra-high",
				width = 5,
				height = 5,
				frame_count = 1
			},
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-shadow-2.png",
				priority = "extra-high",
				width = 6,
				height = 4,
				frame_count = 1
			},
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-shadow-3.png",
				priority = "extra-high",
				width = 7,
				height = 8,
				frame_count = 1
			},
			{
				filename = "__dark-matter-replicators-reborn__/graphics/entity/tenemut-particle-shadow-4.png",
				priority = "extra-high",
				width = 6,
				height = 5,
				frame_count = 1
			}
		}
	},

	resource
})

if worldgen_enabled then
	data:extend(
	{
		{
			type = "autoplace-control",
			name = gprefix.."tenemut",
			richness = true,
			order = "b-rep",
			category = "resource"
		}
	})
else
	helpers.info("Tenemut world generation disabled (dmrsa-tenemut-source = \"Synthesis only\"): "
		.. "resource kept without autoplace for save compatibility, no autoplace-control registered.")
end
