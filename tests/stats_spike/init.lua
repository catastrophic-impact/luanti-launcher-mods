local function log(s) core.log("action", "[STATS_TEST] NOTE " .. s) end
local function fmt(n) return string.format("%.2f", n) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		local base = vector.offset(vector.round(player:get_pos()), 3, 1, 0)
		local pet_obj = core.add_entity(base, "mobs_mc:ocelot")
		local tgt_obj = core.add_entity(vector.offset(base, 1.5, 0, 0), "mobs_mc:cow")
		core.after(1.5, function()
			local pet, tgt = pet_obj:get_luaentity(), tgt_obj:get_luaentity()
			log(string.format("pet defaults: damage=%s armor=%s hp_max=%s attack_type=%s reach=%s", tostring(pet.damage), core.serialize(pet.object:get_armor_groups()):gsub("\n", " "), pet.object:get_properties().hp_max, tostring(pet.attack_type), tostring(pet.reach)))
			-- A) per-hit damage through the mob's own attack path
			for _, want in ipairs({ 4, 8 }) do
				pet.damage = want
				local samples, sum, lo, hi = 0, 0, 1e9, 0
				for i = 1, 30 do
					tgt.object:set_properties({ hp_max = 1000 }); tgt.health = 1000
					pet.attack = tgt_obj
					pet:custom_attack()
					pet.attack = nil
					local lost = 1000 - tgt.health
					sum, samples, lo, hi = sum + lost, samples + 1, math.min(lo, lost), math.max(hi, lost)
				end
				log(string.format("damage stat %d -> target lost mean %s (min %s max %s) over %d hits", want, fmt(sum / samples), fmt(lo), fmt(hi), samples))
			end
			-- B) armor through armor groups on the pet being hit by a fixed punch
			local function hit_pet(fleshy)
				pet.object:set_armor_groups({ fleshy = fleshy })
				local lost = 0
				for i = 1, 10 do
					pet.object:set_properties({ hp_max = 1000 }); pet.health = 1000
					tgt.damage = 10
					tgt.attack = pet_obj
					tgt:custom_attack()
					tgt.attack = nil
					lost = lost + (1000 - pet.health)
				end
				return lost / 10
			end
			for _, f in ipairs({ 100, 70, 40 }) do
				log(string.format("armor group fleshy=%d -> pet lost mean %s from a stat-10 hit", f, fmt(hit_pet(f))))
			end
			-- C) crit-style bonus: is damage applied as a plain number we can double ourselves?
			pet.damage = 4
			log("SCENARIO_DONE")
			core.request_shutdown("done")
		end)
	end)
end)
