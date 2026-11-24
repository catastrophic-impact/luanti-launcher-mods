-- SPIKE (throwaway): can a player drive an animal Mineclonia never made rideable?
local function log(s) core.log("action", "[RIDING_TEST] NOTE " .. s) end
local function fmt(n) return string.format("%.2f", n) end
local KINDS = { "cow", "chicken", "ocelot", "sheep" }

local function wait(sec, fn) core.after(sec, fn) end

local function run_kind(player, kind, done)
	local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
	local obj = core.add_entity(base, "mobs_mc:" .. kind)
	if not obj then log(kind .. ": FAIL could not spawn"); return done() end
	local ent = obj:get_luaentity()
	wait(2, function()
		local props = obj:get_properties()
		local top = props.collisionbox[5]
		log(string.format("%s: cbox top=%.2f movement_speed=%s drive_bonus=%s steer=%s jump_height=%s visual_size=%s", kind, top,
			tostring(ent.movement_speed), tostring(ent.drive_bonus), tostring(ent.steer_class), tostring(ent.jump_height), core.serialize(props.visual_size):gsub("\n", " ")))
		-- scripted controls: forward (and jump on demand). The real path reads player controls; this replaces only that read.
		local script = { forward = true, jump = false }
		ent.apply_driver_input = function(self, speed, self_pos, moveresult)
			self.acc_speed = speed
			self.acc_dir.z = script.forward and 1 or 0
			self.acc_dir.x = 0
			self._jump = script.jump
			-- the auto-jump the pig's "follow_item" steering uses, so pets climb one-block steps by themselves
			if script.forward and self:check_jump(self_pos, moveresult) then self._jump = true end
		end
		ent.driver_attach_at = { x = 0, y = top * 10 * 0.55, z = 0 }
		player:set_look_horizontal(-math.pi / 2) -- +x
		local ok = ent:attach(player)
		local attached = player:get_attach() == obj
		log(kind .. ": attach returned " .. tostring(ok) .. ", player attached=" .. tostring(attached) .. ", driver set=" .. tostring(ent.driver == player))
		-- 1) straight run for 1.5 s; the heading comes from the real player's look (the client owns it)
		local p0 = obj:get_pos()
		wait(1.5, function()
			local p1 = obj:get_pos()
			local dx, dz = p1.x - p0.x, p1.z - p0.z
			local d = math.sqrt(dx * dx + dz * dz)
			local ux, uz = dx / d, dz / d
			log(string.format("%s: ran %.2f blocks in 1.5 s = %s b/s = %.2f x movement_speed, heading (%.2f, %.2f), player-to-mob distance %.2f, anim=%s", kind, d, fmt(d / 1.5), (d / 1.5) / ent.movement_speed, ux, uz,
				vector.distance(player:get_pos(), p1), tostring(ent._current_animation)))
			-- 2) a one-block-high wall 4 blocks ahead, perpendicular to the heading (5 wide)
			local gy = math.floor(p1.y + 0.5) -- node level of a block standing on the ground the mob is on
			local walls = {}
			for k = -2, 2 do
				local pos = { x = math.floor(p1.x + ux * 4 - uz * k + 0.5), y = gy, z = math.floor(p1.z + uz * 4 + ux * k + 0.5) }
				core.set_node(pos, { name = "mcl_core:stone" })
				walls[#walls + 1] = pos
			end
			local y_before = p1.y
			local wall_dist0 = vector.distance({ x = p1.x, y = 0, z = p1.z }, { x = walls[3].x, y = 0, z = walls[3].z })
			local peak, tt = y_before, 0
			local function watch()
				tt = tt + 0.05
				peak = math.max(peak, obj:get_pos().y)
				if tt < 2.5 then core.after(0.05, watch) end
			end
			watch()
			wait(2.5, function()
				local p2 = obj:get_pos()
				log(string.format("%s: wall: peak feet y while crossing = %.2f (ground %.2f, wall top %.2f)", kind, peak, y_before, y_before + 1))
				local ahead = (p2.x - walls[3].x) * ux + (p2.z - walls[3].z) * uz
				log(string.format("%s: step: start %.1f blocks from the wall; feet y %.2f -> %.2f; now %.2f blocks %s the wall => %s", kind, wall_dist0, y_before, p2.y, math.abs(ahead), ahead > 0 and "PAST" or "BEFORE",
					(ahead > 0.6 and p2.y > y_before + 0.5) and "CLIMBED (stands on top or beyond)" or (ahead > 0.6 and "went around/over at ground level?" or "BLOCKED")))
				-- 3) jump on flat ground (stand still)
				script.forward = false
				wait(1, function()
					local py = obj:get_pos().y
					script.jump = true
					local maxy = py
					local t = 0
					local function sample()
						t = t + 0.05
						maxy = math.max(maxy, obj:get_pos().y)
						if t < 1.2 then return core.after(0.05, sample) end
						script.jump = false
						log(string.format("%s: jump: rose %.2f blocks", kind, maxy - py))
						-- 4) detach
						ent:detach(player, vector.new(0, 1, 0))
						wait(0.5, function()
							log(kind .. ": after detach, player attached=" .. tostring(player:get_attach() ~= nil) .. ", driver=" .. tostring(ent.driver ~= nil))
							obj:remove()
							-- clean the step blocks
							for _, w in ipairs(walls) do core.set_node(w, { name = "air" }) end
							player:set_pos(base)
							done()
						end)
					end
					sample()
				end)
			end)
		end)
	end)
end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		local i = 0
		local function nxt()
			i = i + 1
			if not KINDS[i] then log("SCENARIO_DONE"); return core.request_shutdown("done") end
			local ok, err = pcall(run_kind, player, KINDS[i], nxt)
			if not ok then log("ERROR " .. KINDS[i] .. ": " .. tostring(err)); nxt() end
		end
		nxt()
	end)
end)
