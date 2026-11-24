local function log(s) core.log("action", "[PQ_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function popup(player) for _, h in pairs(player:hud_get_all()) do if h.name == "award_bg" then return true end end return false end
local sounds = 0
local orig = core.sound_play
core.sound_play = function(s, p, ...) if type(s) == "table" and s.name == "awards_ui_toast_in" then sounds = sounds + 1 end return orig(s, p, ...) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		local n = "tester"
		check("default: advancement popups hidden", peaceandquiet.hides_advancements(n) == true)
		awards.unlock(n, "mcl:buildPickaxe")
		check("hidden: award still unlocked", mcl_achievements.award_unlocked(n, "mcl:buildPickaxe"))
		check("hidden: no popup and no sound", not popup(player) and sounds == 0, tostring(sounds))
		for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "peaceandquiet:main", { hide_adv = "false" }) end
		check("screen turns it off", peaceandquiet.hides_advancements(n) == false)
		awards.unlock(n, "mcl:buildFurnace")
		check("shown: popup appears and sound plays", popup(player) and sounds == 1, tostring(sounds))
		for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "peaceandquiet:main", { hide_adv = "true" }) end
		check("screen turns it back on", peaceandquiet.hides_advancements(n) == true)
		check("screen builds", core.registered_chatcommands["peaceandquiet"].func(n, "") == true)
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
