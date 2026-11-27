-- Monster packs. Nothing spawns on its own in the dungeon dimension (Mineclonia only spawns in its own dimensions); every monster is
-- placed by hand when the dungeon is built, tagged with its run (_dg_run), persistent (never despawned for distance).
-- Dungeon monsters never hurt each other (arrows, bites, summoned helpers).
local KINDS = {
	{ "mobs_mc:zombie", "mobs_mc:skeleton" },
	{ "mobs_mc:zombie", "mobs_mc:skeleton", "mobs_mc:husk", "mobs_mc:spider" },
	{ "mobs_mc:zombie", "mobs_mc:skeleton", "mobs_mc:husk", "mobs_mc:spider", "mobs_mc:stray", "mobs_mc:vindicator" },
	{ "mobs_mc:zombie", "mobs_mc:skeleton", "mobs_mc:husk", "mobs_mc:spider", "mobs_mc:stray", "mobs_mc:vindicator", "mobs_mc:witherskeleton" },
}
local COUNT = { { 2, 3 }, { 3, 4 }, { 3, 5 }, { 4, 6 } }
local HEALTH = { 1.0, 1.25, 1.5, 1.75 } -- tougher with the tier: damage taken is divided by this (works whenever the monster is active)

-- Tag a monster as belonging to a run.
function dungeoneer.tag_mob(obj, run_id)
	local ent = obj and obj:get_luaentity()
	if not ent then return end
	ent._dg_run = run_id
	ent.persistent = true
	return ent
end

function dungeoneer.spawn_mobs(run, minp, layout)
	local rng = PcgRandom(run.seed + 1)
	local kinds, cnt = KINDS[run.tier], COUNT[run.tier]
	local n_total = 0
	for _, r in ipairs(layout.rooms) do
		if r.kind == "room" then
			for _ = 1, rng:next(cnt[1], cnt[2]) do
				local dx, dz = rng:next(-r.hs + 1, r.hs - 1), rng:next(-r.hs + 1, r.hs - 1)
				local pos = vector.new(minp.x + r.cx + dx, minp.y + r.y0 + 0.5, minp.z + r.cz + dz)
				local kind = kinds[rng:next(1, #kinds)]
				local obj = core.add_entity(pos, kind)
				if not obj then core.log("warning", "[dungeoneer] add_entity failed: " .. kind .. " at " .. core.pos_to_string(pos, 0)) end
				local ent = dungeoneer.tag_mob(obj, run.id)
				if ent then n_total = n_total + 1; ent._dg_hp = HEALTH[run.tier] end
			end
		end
	end
	core.log("action", "[dungeoneer] spawned " .. n_total .. " monsters for run " .. run.id)
	return n_total
end

-- no friendly fire: damage from one dungeon monster (or its arrow/summon) to another is ignored
local mob_class = mcl_mobs.mob_class
local orig = mob_class.receive_damage
function mob_class:receive_damage(mcl_reason, damage)
	if self._dg_run and self._dg_hp and damage > 0 then damage = damage / self._dg_hp end
	if self._dg_run and mcl_reason then
		for _, o in ipairs({ mcl_reason.source, mcl_reason.direct }) do
			if o and o:get_luaentity() then
				local e = o:get_luaentity()
				local src = e._dg_run and e or (e._source_object and e._source_object:get_luaentity())
				if src and src._dg_run then return false end
			end
		end
	end
	return orig(self, mcl_reason, damage)
end
