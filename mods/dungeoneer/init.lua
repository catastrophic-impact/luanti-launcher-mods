-- Dungeoneer (Luanti/Mineclonia port of the Fabric "Dungeoneer" mod; spec = the wiki page, ported from scratch).
-- nodes.lua = dungeon blocks; generator.lua = castle layout + building; runs.lua = the dimension, slots and runs.
dungeoneer = {}
local path = core.get_modpath("dungeoneer")
dofile(path .. "/nodes.lua")
dofile(path .. "/generator.lua")
dofile(path .. "/mobs.lua")
dofile(path .. "/boss.lua")
dofile(path .. "/chest.lua")
dofile(path .. "/runs.lua")
dofile(path .. "/keys.lua")
dofile(path .. "/items.lua")
dofile(path .. "/portal.lua")
dofile(path .. "/window.lua")
dofile(path .. "/settings.lua")
