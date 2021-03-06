
hb = {}
hb.hudtables = {}
hb.hudbars_count = 0 -- number of registered HUD bars
hb.registered_slots = {} -- table of HUD bars for automatic positioning
hb.settings = {}

local enable_damage = minetest.setting_getbool("enable_damage")
local gui_scale = tonumber(minetest.setting_get("gui_scaling")) or 1 -- scales hud

function hb.load_setting(sname, stype, defaultval, valid_values)

	local sval

	if stype == "string" then
		sval = minetest.setting_get(sname)
	elseif stype == "bool" then
		sval = minetest.setting_getbool(sname)
	elseif stype == "number" then
		sval = tonumber(minetest.setting_get(sname))
	end

	if not sval then
		return defaultval
	end

	if not valid_values then
		return sval
	end

	local valid = false

	for i = 1, #valid_values do

		if sval == valid_values[i] then
			valid = true
		end
	end

	if not valid then

--		minetest.log("error", "[hudbars] Invalid value for "
--			..sname.."! Using default value ("
--			..tostring(defaultval)..").")
		return defaultval
	end

	return sval
end

-- (hardcoded) default settings
hb.settings.max_bar_length = 160
hb.settings.statbar_length = 20

-- statbar positions
hb.settings.pos_left = {}
hb.settings.pos_right = {}
hb.settings.start_offset_left = {}
hb.settings.start_offset_right= {}

hb.settings.pos_left.x = hb.load_setting("hudbars_pos_left_x", "number", 0.5)
hb.settings.pos_left.y = hb.load_setting("hudbars_pos_left_y", "number", 1)
hb.settings.pos_right.x = hb.load_setting("hudbars_pos_right_x", "number", 0.5)
hb.settings.pos_right.y = hb.load_setting("hudbars_pos_right_y", "number", 1)
hb.settings.start_offset_left.x = hb.load_setting("hudbars_start_offset_left_x", "number", (-175 * gui_scale))
hb.settings.start_offset_left.y = hb.load_setting("hudbars_start_offset_left_y", "number", -86)
hb.settings.start_offset_right.x = hb.load_setting("hudbars_start_offset_right_x", "number", (15 * gui_scale))
hb.settings.start_offset_right.y = hb.load_setting("hudbars_start_offset_right_y", "number", -86)

hb.settings.vmargin  = hb.load_setting("hudbars_vmargin", "number", 24 * gui_scale)
hb.settings.tick = hb.load_setting("hudbars_tick", "number", 1) -- was 0.1

-- experimental setting: Changing this setting is not officially supported, do NOT rely on it!
hb.settings.forceload_default_hudbars = hb.load_setting("hudbars_forceload_default_hudbars", "bool", true)

--[[
- hudbars_alignment_pattern: This setting changes the way the HUD bars are ordered on the display. You can choose
  between a zig-zag pattern or a vertically stacked pattern.
  The following values are allowed:
    zigzag: Starting from the left bottom, the next is right from the first,
              the next is above the first, the next is right of the third, etc.
              This is the default.
    stack_up: The HUD bars are stacked vertically, going upwards.
    stack_down: The HUD bars are stacked vertically, going downwards.
]]

-- Misc. settings
hb.settings.alignment_pattern = hb.load_setting(
	"hudbars_alignment_pattern", "string", "zigzag", {"zigzag", "stack_up", "stack_down"})
hb.settings.bar_type = hb.load_setting(
	"hudbars_bar_type", "string", "statbar_modern",
	{"progress_bar", "statbar_classic", "statbar_modern"})
hb.settings.autohide_breath = hb.load_setting("hudbars_autohide_breath", "bool", true)
hb.direction = 0 -- 0: left-right, 1: right-left, 2: top-bottom, 3: bottom-top -TENPLUS1

if hb.settings.bar_type == "progress_bar" then
	hb.size = {x = 3 * gui_scale, y = 17 * gui_scale}
else
	hb.size = {x = 17 * gui_scale, y = 17 * gui_scale}
end

local sorting = minetest.setting_get("hudbars_sorting")

if sorting ~= nil then

	hb.settings.sorting = {}
	hb.settings.sorting_reverse = {}

	for k,v in string.gmatch(sorting, "(%w+)=(%w+)") do

		hb.settings.sorting[k] = tonumber(v)
		hb.settings.sorting_reverse[tonumber(v)] = k
	end
else
	-- swapped health & breath around and added hunger & armor
	hb.settings.sorting = { ["health"] = 0, ["hunger"] = 1, ["armor"] = 2, ["breath"] = 3}
	hb.settings.sorting_reverse = {}-- [0] = "breath", [1] = "health"}
end

-- Table which contains all players with active default HUD bars (only for internal use)
hb.players = {}

function hb.value_to_barlength(value, max)

	if max == 0 then
		return 0
	end

	local x

	if value < 0 then
		x = -0.5
	else
		x = 0.5
	end

	if hb.settings.bar_type == "progress_bar" then

		return math.modf( (value / max) * hb.settings.max_bar_length + x)
	end

	return math.modf( (value / max) * hb.settings.statbar_length + x)
end

function hb.get_hudtable(identifier)
	return hb.hudtables[identifier]
end

function hb.get_hudbar_position_index(identifier)

	if hb.settings.sorting[identifier] ~= nil then
		return hb.settings.sorting[identifier]
	end

	local i = 0

	while true do

		if hb.registered_slots[i] ~= true
		and hb.settings.sorting_reverse[i] == nil then
			return i
		end

		i = i + 1
	end
end

function hb.register_hudbar(identifier, text_color, label, textures,
	default_start_value, default_start_max, default_start_hidden, format_string)

--	minetest.log("action", "hb.register_hudbar: "..tostring(identifier))

	local hudtable = {}
	local pos, offset
	local index = math.floor(hb.get_hudbar_position_index(identifier))

	hb.registered_slots[index] = true

	if hb.settings.alignment_pattern == "stack_up" then

		pos = hb.settings.pos_left

		offset = {
			x = hb.settings.start_offset_left.x,
			y = hb.settings.start_offset_left.y - hb.settings.vmargin * index
		}

	elseif hb.settings.alignment_pattern == "stack_down" then

		pos = hb.settings.pos_left

		offset = {
			x = hb.settings.start_offset_left.x,
			y = hb.settings.start_offset_left.y + hb.settings.vmargin * index
		}
	else
		if index % 2 == 0 then

			pos = hb.settings.pos_left

			offset = {
				x = hb.settings.start_offset_left.x,
				y = hb.settings.start_offset_left.y - hb.settings.vmargin * (index / 2)
			}
		else
			pos = hb.settings.pos_right

			offset = {
				x = hb.settings.start_offset_right.x,
				y = hb.settings.start_offset_right.y - hb.settings.vmargin * ((index - 1) / 2)
			}
		end
	end

	format_string = format_string or "%s: %d/%d"

	hudtable.add_all = function(player, hudtable, start_value, start_max, start_hidden)

		start_value = start_value or hudtable.default_start_value

		start_max = start_max or hudtable.default_start_max

		start_hidden = start_hidden or hudtable.default_start_hidden

		local ids = {}
		local state = {}
		local name = player:get_player_name()
		local bgscale, iconscale, text, barnumber

		if start_max == 0
		or start_hidden then

			bgscale = {x = 0, y = 0}
		else
			bgscale = {x = 1 * gui_scale, y = 1 * gui_scale}
		end

		if start_hidden then

			iconscale = {x = 0, y = 0}
			barnumber = 0
			text = ""
		else
			iconscale = {x = 1 * gui_scale, y = 1 * gui_scale}
			barnumber = hb.value_to_barlength(start_value, start_max)
			text = string.format(format_string, label, start_value, start_max)
		end

		if hb.settings.bar_type == "progress_bar" then

			ids.bg = player:hud_add({
				hud_elem_type = "image",
				position = pos,
				scale = bgscale,
				--text = "hudbars_bar_background.png", -- REMOVED
				alignment = {x = 1, y = 1},
				offset = { x = offset.x - 2, y = offset.y - 2 }, -- ADDED - values
				direction = hb.direction, -- ADDED
				size = hb.size,
			})

			if textures.icon ~= nil then

				ids.icon = player:hud_add({
					hud_elem_type = "image",
					position = pos,
					scale = iconscale,
					text = textures.icon,
					alignment = {x=-1,y=1},
					offset = { x = offset.x - 3, y = offset.y },
					direction = hb.direction, -- ADDED
					size = hb.size,
				})
			end

		elseif hb.settings.bar_type == "statbar_modern" then

			if textures.bgicon ~= nil then

				ids.bg = player:hud_add({
					hud_elem_type = "statbar",
					position = pos,
					scale = bgscale,
					text = textures.bgicon,
					number = hb.settings.statbar_length,
					alignment = {x=-1,y=-1},
					offset = { x = offset.x, y = offset.y },
					direction = hb.direction, -- ADDED
					size = hb.size,
				})
			end
		end

		local bar_image

		if hb.settings.bar_type == "progress_bar" then

			bar_image = textures.bar

		elseif hb.settings.bar_type == "statbar_classic"
		or hb.settings.bar_type == "statbar_modern" then

			bar_image = textures.icon
		end

		ids.bar = player:hud_add({
			hud_elem_type = "statbar",
			position = pos,
			text = bar_image,
			number = barnumber,
			alignment = {x=-1,y=-1},
			offset = offset,
			direction = hb.direction, -- ADDED
			size = hb.size,
		})

		if hb.settings.bar_type == "progress_bar" then

			ids.text = player:hud_add({
				hud_elem_type = "text",
				position = pos,
				text = text,
				alignment = {x=1,y=1},
				number = text_color,
				offset = { x = offset.x + 2,  y = offset.y },
				direction = hb.direction, -- ADDED
				size = hb.size,
			})
		end

		-- Do not forget to update hb.get_hudbar_state if you add new fields to the state table
		state.hidden = start_hidden
		state.value = start_value
		state.max = start_max
		state.text = text
		state.barlength = hb.value_to_barlength(start_value, start_max)

		local main_error_text =
			"[hudbars] Bad initial values of HUD bar identifier “"
			..tostring(identifier).."” for player "..name..". "
--[[
		if start_max < start_value then
			minetest.log("error", main_error_text.."start_max ("
			..start_max..") is smaller than start_value ("..start_value..")!")
		end
		if start_max < 0 then
			minetest.log("error", main_error_text.."start_max ("
			..start_max..") is smaller than 0!")
		end
		if start_value < 0 then
			minetest.log("error", main_error_text.."start_value ("
			..start_value..") is smaller than 0!")
		end
]]
		hb.hudtables[identifier].hudids[name] = ids
		hb.hudtables[identifier].hudstate[name] = state
	end

	hudtable.identifier = identifier
	hudtable.format_string = format_string
	hudtable.label = label
	hudtable.hudids = {}
	hudtable.hudstate = {}
	hudtable.default_start_hidden = default_start_hidden
	hudtable.default_start_value = default_start_value
	hudtable.default_start_max = default_start_max

	hb.hudbars_count= hb.hudbars_count + 1
	
	hb.hudtables[identifier] = hudtable
end

function hb.init_hudbar(player, identifier, start_value, start_max, start_hidden)

	local hudtable = hb.get_hudtable(identifier)

	hb.hudtables[identifier].add_all(player, hudtable, start_value, start_max, start_hidden)
end

function hb.change_hudbar(player, identifier, new_value, new_max_value,
		new_icon, new_bgicon, new_bar, new_label, new_text_color)

	if new_value == nil and new_max_value == nil and new_icon == nil
	and new_bgicon == nil and new_bar == nil and new_label == nil and new_text_color == nil then
		return
	end

	if not player then -- TENPLUS1
		return
	end

	local name = player:get_player_name()
	local hudtable = hb.get_hudtable(identifier)
	local value_changed, max_changed = false, false

	if not hudtable.hudstate[name] then -- TENPLUS1
		return
	end

	if new_value ~= nil then

		if new_value ~= hudtable.hudstate[name].value then

			hudtable.hudstate[name].value = new_value
			value_changed = true
		end
	else
		new_value = hudtable.hudstate[name].value
	end

	if new_max_value ~= nil then

		if new_max_value ~= hudtable.hudstate[name].max then

			hudtable.hudstate[name].max = new_max_value
			max_changed = true
		end
	else
		new_max_value = hudtable.hudstate[name].max
	end

	if hb.settings.bar_type == "progress_bar" then -- NEW block added in 1.40

		if new_icon ~= nil and hudtable.hudids[name].icon ~= nil then
			player:hud_change(hudtable.hudids[name].icon, "text", new_icon)
		end

		if new_bgicon ~= nil and hudtable.hudids[name].bgicon ~= nil then
			player:hud_change(hudtable.hudids[name].bgicon, "text", new_bgicon)
		end

		if new_bar ~= nil then
			player:hud_change(hudtable.hudids[name].bar , "text", new_bar)
		end

		if new_label ~= nil then

			hudtable.label = new_label

			local new_text = string.format(hudtable.format_string, new_label, hudtable.hudstate[name].value, hudtable.hudstate[name].max)

			player:hud_change(hudtable.hudids[name].text, "text", new_text)
		end

		if new_text_color ~= nil then
			player:hud_change(hudtable.hudids[name].text, "number", new_text_color)
		end
	else
		if new_icon ~= nil and hudtable.hudids[name].bar ~= nil then
			player:hud_change(hudtable.hudids[name].bar, "text", new_icon)
		end

		if new_bgicon ~= nil and hudtable.hudids[name].bg ~= nil then
			player:hud_change(hudtable.hudids[name].bg, "text", new_bgicon)
		end
	end

	local main_error_text =
		"[hudbars] Bad call to hb.change_hudbar, identifier: “"
		..tostring(identifier).."”, player name: “"..name.."”. "
--[[
	if new_max_value < new_value then
		minetest.log("error", main_error_text.."new_max_value ("
		..new_max_value..") is smaller than new_value ("..new_value..")!")
	end
	if new_max_value < 0 then
		minetest.log("error", main_error_text.."new_max_value ("
		..new_max_value..") is smaller than 0!")
	end
	if new_value < 0 then
		minetest.log("error", main_error_text.."new_value ("
		..new_value..") is smaller than 0!")
	end
]]
	if hudtable.hudstate[name].hidden == false then

		if max_changed and hb.settings.bar_type == "progress_bar" then

			if hudtable.hudstate[name].max == 0 then

				player:hud_change(hudtable.hudids[name].bg, "scale", {x = 0, y = 0})
			else
				player:hud_change(hudtable.hudids[name].bg, "scale", {x = 1, y = 1})
			end
		end

		if value_changed or max_changed then

			local new_barlength = hb.value_to_barlength(new_value, new_max_value)

			if new_barlength ~= hudtable.hudstate[name].barlength then

				player:hud_change(
					hudtable.hudids[name].bar,
					"number",
					hb.value_to_barlength(new_value, new_max_value)
				)

				hudtable.hudstate[name].barlength = new_barlength
			end

			if hb.settings.bar_type == "progress_bar" then

				local new_text = string.format(
					hudtable.format_string,
					hudtable.label,
					new_value, new_max_value
				)

				if new_text ~= hudtable.hudstate[name].text then

					player:hud_change(
						hudtable.hudids[name].text,
						"text",
						new_text
					)

					hudtable.hudstate[name].text = new_text
				end
			end
		end
	end
end

function hb.hide_hudbar(player, identifier)

	if not player then -- TENPLUS1
		return
	end

	local name = player:get_player_name()
	local hudtable = hb.get_hudtable(identifier)

	if hudtable.hudstate[name]
	and hudtable.hudstate[name].hidden ~= false then
		return
	end

	if hb.settings.bar_type == "progress_bar" then

		if hudtable.hudids[name].icon ~= nil then

			player:hud_change(
				hudtable.hudids[name].icon,
				"scale",
				{x = 0, y = 0}
			)
		end

		player:hud_change(
			hudtable.hudids[name].bg,
			"scale",
			{x = 0, y = 0}
		)

		player:hud_change(
			hudtable.hudids[name].text,
			"text",
			""
		)
	end

	player:hud_change(
		hudtable.hudids[name].bar,
		"number",
		0
	)

	hudtable.hudstate[name].hidden = true
end

function hb.unhide_hudbar(player, identifier)

	if not player then -- TenPlus1
		return
	end

	local name = player:get_player_name()
	local hudtable = hb.get_hudtable(identifier)

	if not hudtable or not hudtable.hudstate[name] then -- ADDED
		return
	end

	if hudtable.hudstate[name].hidden == false then
		return
	end

	local name = player:get_player_name()
	local value = hudtable.hudstate[name].value
	local max = hudtable.hudstate[name].max

	if hb.settings.bar_type == "progress_bar" then

		if hudtable.hudids[name].icon ~= nil then

			player:hud_change(
				hudtable.hudids[name].icon,
				"scale",
				{x = 1, y = 1}
			)
		end

		if hudtable.hudstate[name].max ~= 0 then

			player:hud_change(
				hudtable.hudids[name].bg,
				"scale",
				{x = 1, y = 1}
			)
		end

		player:hud_change(
			hudtable.hudids[name].text,
			"text",
			tostring(
				string.format(
					hudtable.format_string,
					hudtable.label,
					value,
					max
				)
			)
		)
	end

	player:hud_change(
		hudtable.hudids[name].bar,
		"number",
		hb.value_to_barlength(value, max)
	)

	hudtable.hudstate[name].hidden = false
end

function hb.get_hudbar_state(player, identifier)

	local ref = hb.get_hudtable(identifier).hudstate[player:get_player_name()]

	-- Do not forget to update this chunk of code in case the state changes
	local copy = {
		hidden = ref.hidden,
		value = ref.value,
		max = ref.max,
		text = ref.text,
		barlength = ref.barlength,
	}

	return copy
end

--register built-in HUD bars
if enable_damage
or hb.settings.forceload_default_hudbars then

	hb.register_hudbar("health", 0xFFFFFF, "Health",
	{
		bar = "hudbars_bar_health.png",
		icon = "hudbars_icon_health.png",
		bgicon = "hudbars_bgicon_health.png"
	},
	20, 20, false)

	hb.register_hudbar("breath", 0xFFFFFF, "Breath",
	{
		bar = "hudbars_bar_breath.png",
		icon = "hudbars_icon_breath.png"
	},
	10, 10, true)
end

local function hide_builtin(player)

	local flags = player:hud_get_flags()

	flags.healthbar = false
	flags.breathbar = false

	player:hud_set_flags(flags)
end


local function custom_hud(player)

	if enable_damage or hb.settings.forceload_default_hudbars then

		local hide = true

		if enable_damage then
			hide = false
		end

		hb.init_hudbar(player, "health", player:get_hp(), nil, hide)

		local breath = player:get_breath()
		local hide_breath = false

		if breath == 11
		and hb.settings.autohide_breath == true then
			hide_breath = true
		end

		hb.init_hudbar(player, "breath", math.min(breath, 10), nil, hide_breath or hide)
	end
end


-- update built-in HUD bars
local function update_hud(player)

	if enable_damage then

		if hb.settings.forceload_default_hudbars then
			hb.unhide_hudbar(player, "health")
		end

		--air
		local breath = player:get_breath() or 11 -- TenPlus1 (or 11)

		if breath == 11 and hb.settings.autohide_breath == true then

			hb.hide_hudbar(player, "breath")
		else
			hb.unhide_hudbar(player, "breath")
			hb.change_hudbar(player, "breath", breath) -- math.min(breath, 10))
		end
		
		--health
		hb.change_hudbar(player, "health", player:get_hp())

	elseif hb.settings.forceload_default_hudbars then

		hb.hide_hudbar(player, "health")
		hb.hide_hudbar(player, "breath")
	end
end

minetest.register_on_joinplayer(function(player)

	hide_builtin(player)

	custom_hud(player)

	hb.players[player:get_player_name()] = player
end)

minetest.register_on_leaveplayer(function(player)

	hb.players[player:get_player_name()] = nil
end)

local main_timer = 0
local x

minetest.register_globalstep(function(dtime)

	main_timer = main_timer + dtime

	if main_timer > hb.settings.tick then

		main_timer = 0

		-- only proceed if damage is enabled
		if enable_damage
		or hb.settings.forceload_default_hudbars then

			for playername, player in pairs(hb.players) do

				update_hud(player)
			end
		end
	end
end)
