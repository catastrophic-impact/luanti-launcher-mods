-- Multiversatile: dimensions for Mineclonia.
-- Luanti has ONE map. A "dimension" here = a band of heights (ymin..ymax, inclusive) in it, as in Mineclonia (Overworld, Nether, End).
-- api.lua = registry + lookup + area slots; mineclonia.lua = registers Mineclonia's three and wraps mcl_worlds.y_to_layer.
multiversatile = {}
local path = core.get_modpath("multiversatile")
dofile(path .. "/api.lua")
dofile(path .. "/mineclonia.lua")
dofile(path .. "/limits.lua")
dofile(path .. "/outofbounds.lua")
dofile(path .. "/look.lua")
dofile(path .. "/travel.lua")
