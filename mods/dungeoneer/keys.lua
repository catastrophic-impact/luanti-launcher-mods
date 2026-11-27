-- Keys come from play, not from the crafting grid: tier 1 drops (1%) from hostile mobs killed by a player, in any dimension; the key for the
-- next tier is in the boss chest of a dungeon (one for every player who was inside when the boss died, see chest.lua).
-- A player carries at most ONE key of any tier: keys stack to 1, a mob never drops one for a player who carries one, a picked-up key is
-- left lying when the player already carries one, and the chest hands out a key only to a player who carries none.
local mob_class = mcl_mobs.mob_class
dungeoneer.key_drop_chance = 0.01 -- raised by tests

function dungeoneer.carries_key(player)
	local inv = player:get_inventory()
	for _, list in ipairs({ "main", "offhand" }) do
		local l = inv:get_list(list)
		if l then for _, st in ipairs(l) do if st:get_name():find("^dungeoneer:key_") then return true end end end
	end
	return false
end

local orig_drop = mob_class.item_drop
function mob_class:item_drop(cooked, looting_level, mcl_reason)
	local r = orig_drop(self, cooked, looting_level, mcl_reason)
	if self.type == "monster" and not self._dg_run -- monsters of a dungeon never drop keys (that would be a free climb)
		and self.last_player_hit_name and self.last_player_hit_time and core.get_gametime() - self.last_player_hit_time <= 5
		and math.random() < dungeoneer.key_drop_chance then
		local killer = core.get_player_by_name(self.last_player_hit_name)
		local pos = self.object:get_pos()
		if killer and pos and not dungeoneer.carries_key(killer) then core.add_item(pos, "dungeoneer:key_1") end
	end
	return r
end

-- an item entity of a key is only picked up by a player who carries no key (Mineclonia calls the item's own on_pickup)
function dungeoneer.key_on_pickup(itemstack, picker, pointed_thing, ...)
	if picker and picker:is_player() and dungeoneer.carries_key(picker) then return itemstack end
	return core.item_pickup(itemstack, picker, pointed_thing, ...)
end
