
hbarmor = {}
hbarmor.armor = {} -- HUD statbar values
hbarmor.player_active = {} -- stores if player hug has been init. so far
hbarmor.tick = 1 -- was 0.1
hbarmor.autohide = true -- hide when player not wearing armor

local armor_hud = {} -- HUD item id's
local enable_damage = minetest.setting_getbool("enable_damage")

--[[load custom settings
local set = io.open(minetest.get_modpath("hbarmor").."/hbarmor.conf", "r")
if set then 
	dofile(minetest.get_modpath("hbarmor").."/hbarmor.conf")
	set:close()
end--]]

local must_hide = function(playername, arm)
	return ((not armor.def[playername].count or armor.def[playername].count == 0) and arm == 0)
end

local arm_printable = function(arm)
	return math.ceil(math.floor(arm + 0.5))
end

local function custom_hud(player)

	local name = player:get_player_name()

	if not enable_damage then
		return
	end

	if hbarmor.get_armor(player) == false then

		minetest.log("error",
			"[hbarmor] Call to hbarmor.get_armor in custom_hud returned with false!")
	end

	local arm = tonumber(hbarmor.armor[name]) or 0

	local hide = false

	if hbarmor.autohide then
		hide = must_hide(name, arm)
	end

	hb.init_hudbar(player, "armor", arm_printable(arm), nil, hide)
end

--register and define armor HUD bar
hb.register_hudbar("armor", 0xFFFFFF, "Armor",
	{ icon = "hbarmor_icon.png", bar = "hbarmor_bar.png" }, 0, 100, hbarmor.autohide, "%s: %d%%")


minetest.after(0, function()

	if not armor.def then

		minetest.after(2,minetest.chat_send_all,
			"#Better HUD: Please update your version of 3darmor")

		HUD_SHOW_ARMOR = false
	end
end)

function hbarmor.get_armor(player)

	if not player or not armor.def then
		return false
	end

	local name = player:get_player_name()
	local def = armor.def[name] or nil

	if def and def.state and def.count then

		hbarmor.set_armor(name, def.state, def.count)
	else
		return false
	end

	return true
end

function hbarmor.set_armor(player_name, ges_state, items)

	local max_items = 4

	if items == 5 then
		max_items = items
	end

	local max = max_items * 65535
	local lvl = max - ges_state

	lvl = lvl / max

	if ges_state == 0 and items == 0 then
		lvl = 0
	end

	hbarmor.armor[player_name] = lvl * (items * (100 / max_items))

end


-- update hud elemtens if value has changed
local function update_hud(player)

	if not player then
		return
	end

	local name = player:get_player_name()
	local arm = tonumber(hbarmor.armor[name])

	if not arm then
		arm = 0
		hbarmor.armor[name] = 0
	end

	if hbarmor.autohide then

		-- hide armor bar completely when there is none
		if must_hide(name, arm) then

			hb.hide_hudbar(player, "armor")
		else
			hb.change_hudbar(player, "armor", arm_printable(arm))
			hb.unhide_hudbar(player, "armor")
		end
	else
		hb.change_hudbar(player, "armor", arm_printable(arm))
	end
end

minetest.register_on_joinplayer(function(player)

	local name = player:get_player_name()

	custom_hud(player)

	hbarmor.player_active[name] = true
end)

minetest.register_on_leaveplayer(function(player)

	local name = player:get_player_name()

	hbarmor.player_active[name] = false
end)

local main_timer = 0

minetest.register_globalstep(function(dtime)

	main_timer = main_timer + dtime

	if main_timer > hbarmor.tick then

		if enable_damage then

			if main_timer > hbarmor.tick then
				main_timer = 0
			end

			for _,player in pairs(minetest.get_connected_players()) do

				local name = player:get_player_name()

				if hbarmor.player_active[name] == true then

					if hbarmor.get_armor(player) == false then

						minetest.log("error",
						"[hbarmor] Call to hbarmor.get_armor in globalstep returned with false!")
					end

					update_hud(player)
				end
			end
		end
	end
end)
