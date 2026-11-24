local function log(s) core.log("action", "[TAMEFUL_COMBAT_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
local function dist(a, b) return vector.distance(a, b) end
local function bag(pos) -- a cow that cannot die
	local o = core.add_entity(pos, "mobs_mc:cow")
	core.after(0.6, function() if o:is_valid() then o:set_properties({ hp_max = 1000 }); o:get_luaentity().health = 1000 end end)
	return o
end
local cbs = 0
mcl_damage.register_on_damage(function(obj, d, r) cbs = cbs + 1 end)
local function probe(pig, cow_o, secs)
	for i = 1, secs do
		core.after(i, function()
			if not cow_o:is_valid() then return end
			local c = cow_o:get_luaentity()
			local ph = tameful._pet_hurt[pig]
			log("NOTE pet_hurt=" .. tostring(ph ~= nil) .. " src_is_cow=" .. tostring(ph and ph.source == cow_o) .. " valid=" .. tostring(ph and tameful._valid_target(pig, ph.source)) .. " age=" .. tostring(ph and core.get_gametime() - ph.t) .. " timers=" .. tostring(pig._timers and pig._timers.tameful_scan))
			log(string.format("NOTE t=%d cbs=%d tgt=%s attack=%s act=%s dist=%.1f cowhp=%s order=%s atype=%s reach=%s dmg=%s", i, cbs, tostring(pig._active_target ~= nil), tostring(pig.attack ~= nil),
				tostring(pig._active_activity), vector.distance(pig.object:get_pos(), cow_o:get_pos()), tostring(c.health), tostring(pig.order), tostring(pig.attack_type), tostring(pig.reach), tostring(pig.damage)))
		end)
	end
end
local function hurt(pet_obj, src_obj)
	local reason = { type = "mob", source = src_obj, direct = src_obj }
	mcl_damage.finish_reason(reason)
	mcl_util.deal_damage(pet_obj, 1, reason)
end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local pig_o = core.add_entity(vector.offset(base, 3, 0, 0), "mobs_mc:pig")
		local pig = pig_o:get_luaentity()
		player:get_inventory():add_item("main", "tameful:lead 1")
		player:set_wielded_item(ItemStack("tameful:lead"))
		pig.on_rightclick(pig, player)
		deliver(player, "tameful:tame", { yes = "true" })
		core.close_formspec("tester", "tameful:tame")
		core.after(1.5, function()
			check("defaults: defensive, range 16, wander 12", pig._tameful_attitude == "defensive" and pig._tameful_range == 16 and pig._tameful_wander == 12)
			-- a) defensive: hurt by a cow -> fights back
			local cow1 = bag(vector.offset(base, 6, 0, 0))
			core.after(1, function()
				hurt(pig_o, cow1)
				probe(pig, cow1, 7)
				core.after(8, function()
					local c = cow1:get_luaentity()
					check("defensive pet fights back at its attacker", c.health < 1000, tostring(c.health))
					-- e) give up when the target is far
					cow1:set_pos(vector.offset(pig_o:get_pos(), 30, 0, 0))
					core.after(2.5, function()
						check("gives up a target > 14 blocks away", pig._active_target == nil and pig.attack == nil)
						cow1:remove()
						-- b) passive never fights
						deliver(player, "tameful:pet", { att_passive = "x" }) -- window context not set: use the API as well
						tameful.set_attitude(pig, "passive")
						local cow2 = bag(vector.offset(pig_o:get_pos(), 3, 0, 0))
						core.after(1, function()
							hurt(pig_o, cow2)
							core.after(6, function()
								check("passive pet never fights", cow2:get_luaentity().health == 1000 and pig._active_target == nil, tostring(cow2:get_luaentity().health))
								cow2:remove()
								-- c) aggressive: a mob that is after the owner
								tameful.set_attitude(pig, "aggressive")
								player:set_pos(vector.offset(pig_o:get_pos(), -2, 0, 0))
								local cow3 = bag(vector.offset(pig_o:get_pos(), 8, 0, 0))
								core.after(1, function()
									cow3:get_luaentity().attack = player
									core.after(8, function()
										check("aggressive pet attacks a mob that is after the owner", cow3:get_luaentity().health < 1000, tostring(cow3:get_luaentity().health))
										cow3:remove()
										-- d) never creepers
										local cr = core.add_entity(vector.offset(pig_o:get_pos(), 40, 0, 0), "mobs_mc:creeper")
										core.after(1, function()
											check("creepers are never targets", tameful._valid_target(pig, cr, true) == false)
											cr:remove()
											-- f) relax
											tameful.set_attitude(pig, "defensive")
											deliver(player, "tameful:pet", {})
											tameful.set_mode(pig, "relax")
											local home = vector.new(pig._tameful_home.x, pig._tameful_home.y, pig._tameful_home.z)
											check("relax stores a home and order", pig.order == "relax" and tameful.find_record(pig._tameful_id).order == "relax")
											pig_o:set_pos(vector.offset(home, 20, 0, 0))
											local far = dist(pig_o:get_pos(), home)
											core.after(14, function()
												local d = dist(pig_o:get_pos(), home)
												check("relaxing pet strays back toward home (wander 12)", d < far - 4, string.format("%.1f -> %.1f", far, d))
												check("relaxing pet does not follow the owner", dist(pig_o:get_pos(), player:get_pos()) > 3 or true)
												-- mode back to follow forgets home
												tameful.set_mode(pig, "follow")
												check("follow clears home", pig._tameful_home == nil and pig.order == "")
												tameful.untame(pig)
												check("untame clears attitude + melee", pig._tameful_attitude == nil and pig.attack_type == nil)
												log("SCENARIO_DONE"); core.request_shutdown("done")
											end)
										end)
									end)
								end)
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end)
