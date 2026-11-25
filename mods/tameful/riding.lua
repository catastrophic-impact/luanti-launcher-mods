-- Riding: every land pet can be ridden with Mineclonia's generic "controls" driving (WASD steer, Space jump, Shift off).
-- Measured (tests/riding_spike): speed = 2.05 x movement_speed x drive_bonus; default jump ~1.25 blocks at jump_height 8.4.
local S = core.get_translator("tameful")
local mob_class = mcl_mobs.mob_class
local msg = tameful.msg
local SPEED_K = 2.05
local SADDLE_BONUS = 2 -- blocks/second
-- measured corrections for mobs with their own jump force (rabbit jumped 1.17 instead of 2 blocks)
local JUMP_FIX = { ["mobs_mc:rabbit"] = 1.39 }
local SADDLE_KINDS = { horse = true, donkey = true, mule = true, pig = true, strider = true, camel = true }

local function can_wear_saddle(ent)
	local short = ent.name:match("^mobs_mc:(.+)$") or ""
	return SADDLE_KINDS[short] or short:find("horse", 1, true) ~= nil
end

-- Mount speed in blocks/second for this pet right now.
function tameful.mount_speed(ent)
	local st = ent._tameful_stats or tameful.stats_for(ent.name)
	local v = st.speed
	local saddled = ent.saddle == "yes" or (type(ent._saddle) == "string" and ent._saddle ~= "")
	if saddled and can_wear_saddle(ent) then v = v + SADDLE_BONUS end
	return v
end

local OVERRIDDEN = { "steer_class", "steer_item", "drive_bonus", "jump_height", "driver_attach_at", "should_drive",
	"post_apply_driver_input", "apply_driver_input", "expel_underwater_drivers", "driver_scale" }

-- Hand-tuned seats { y, z, rider scale } in 1/10 block (before the parent's visual_size is divided out).
local SEAT_FIX = {
	rabbit = { 1.6, -4.5, 0.5 }, -- the ears stick up in front: sit well back
	cat = { 6, -2, 0.8 }, ocelot = { 6, -2, 0.8 },
	strider = { 5.1, -1.75, 1, true }, -- true: already in the parent's scaled space -- Mineclonia's own seat; the default one was too low (feet through the face)
}

local function setup(ent)
	ent._tameful_orig = {}
	for _, k in ipairs(OVERRIDDEN) do ent._tameful_orig[k] = rawget(ent, k) or false end
	local st = ent._tameful_stats or tameful.stats_for(ent.name)
	ent.steer_class = "controls"
	ent.steer_item = nil
	ent.drive_bonus = tameful.mount_speed(ent) / (SPEED_K * ent.movement_speed)
	-- jump: clear `st.jump` blocks with a 0.25 margin (1.25 blocks = jump_height 8.4, height grows with its square)
	ent.jump_height = 8.4 * math.sqrt((st.jump + 0.25) / 1.25) * (JUMP_FIX[ent.name] or 1)
	local props = ent.object:get_properties()
	local top = props.collisionbox[5]
	-- animals Mineclonia already lets you ride (horse, pig, strider...) keep their own seat
	local own = ent.driver_attach_at
	if not own or (own.x == 0 and own.y == 0 and own.z == 0) then
		-- Seat on the back, a bit behind the middle. Units are 1/10 block, but attachments live in the parent's scaled space
		-- (polar bear, strider have visual_size > 1): divide by it, and shrink the rider by it so it keeps its normal size.
		local vs = props.visual_size or { x = 1, y = 1 }
		local y, z, k = top * 10 * 0.55, 0, 1
		local short = ent.name:match("^mobs_mc:(.+)$") or ""
		local fix = SEAT_FIX[short]
		if fix then
			y, z, k = fix[1], fix[2], fix[3]
			if fix[4] then vs = { x = 1, y = 1 } end -- Mineclonia's numbers are not divided by the visual size
		elseif top < 0.8 then
			-- small animals: a full-size rider would sit on the head, so shrink the rider
			y, z, k = top * 10 * 0.7, -top * 10 * 0.2, 0.55
		elseif top >= 1 then -- cow, sheep, mooshroom, bear: the default seat sank into the body
			y, z = top * 10 * 0.72, -top * 10 * 0.12
		end
		ent.driver_attach_at = { x = 0, y = y / vs.y, z = z / vs.y }
		local vsr = props.visual_size or { x = 1, y = 1 }
		ent.driver_scale = { x = k / vsr.x, y = k / vsr.y }
	end
	ent._tameful_drive_bonus = ent.drive_bonus
	ent._tameful_riding = true
	ent.should_drive = mob_class.should_drive -- horses would insist on a saddle
	ent.post_apply_driver_input = function() end -- horse jump charge
	ent.expel_underwater_drivers = function() end -- pets swim: the rider stays on
	-- one-block steps are climbed by themselves
	ent.apply_driver_input = function(self, speed, pos, moveresult, dtime)
		local hook = tameful._ride_input -- test hook: scripted controls
		if hook then
			self.acc_speed = speed
			self.acc_dir.z = hook.forward and 1 or 0
			self.acc_dir.x = 0
			self._jump = hook.jump or false
		else
			mob_class.apply_driver_input(self, speed, pos, moveresult, dtime)
		end
		if self.acc_dir.z > 0 and self:check_jump(pos, moveresult) then self._jump = true end
	end
end

local function cleanup(ent)
	for k, v in pairs(ent._tameful_orig or {}) do ent[k] = v or nil end
	ent._tameful_orig = nil
	ent._tameful_riding = nil
end
tameful._ride_cleanup = cleanup

-- Returns ok, reason
function tameful.ride(ent, player)
	local pname = player:get_player_name()
	if ent.driver then return false, S("Someone is already riding it.") end
	if ent.child then return false, S("Babies cannot be ridden.") end
	local st = ent._tameful_stats or tameful.stats_for(ent.name)
	if st.jump == "fly" then return false, S("Flying pets cannot be ridden yet.") end
	if vector.distance(ent.object:get_pos(), player:get_pos()) > 6 then
		return false, S("That pet is too far away.")
	end
	if player:get_attach() then return false, S("You are already riding something.") end
	setup(ent)
	if not ent:attach(player) then cleanup(ent); return false, S("Could not mount.") end
	ent.order = ""
	return true
end

-- Wrap driver_detached for pets so the overrides go away.
local orig_detached = mob_class.driver_detached
local function wrap_detached(name)
	local def = core.registered_entities[name]
	if not def then return end
	local orig = def.driver_detached or orig_detached
	def.driver_detached = function(self, driver, deact)
		if self._tameful_riding then cleanup(self) end
		return orig(self, driver, deact)
	end
end
core.register_on_mods_loaded(function()
	for name, def in pairs(mcl_mobs.registered_mobs) do
		if def.type == "animal" then wrap_detached(name) end
	end
end)

-- Shift gets you off (poll, like Mineclonia's horse).
local acc = 0
core.register_globalstep(function(dtime)
	acc = acc + dtime
	if acc < 0.1 then return end
	acc = 0
	for _, player in ipairs(core.get_connected_players()) do
		local parent = player:get_attach()
		local ent = parent and parent:get_luaentity()
		if ent and ent._tameful_riding and player:get_player_control().sneak then
			ent:detach(player, vector.new(0, 0.5, 0))
		end
	end
end)

tameful._ride_setup = setup
