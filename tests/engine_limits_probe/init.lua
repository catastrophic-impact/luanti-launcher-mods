local function log(s) core.log("action", "[PROBE_TEST] DIAG " .. s) end
core.after(2, function()
	local n, maxid, groups = 0, 0, {}
	for name in pairs(core.registered_nodes) do
		n = n + 1
		local id = core.get_content_id(name)
		if id > maxid then maxid = id end
	end
	local items, tools, ents = 0, 0, 0
	for _ in pairs(core.registered_items) do items = items + 1 end
	for _ in pairs(core.registered_tools) do tools = tools + 1 end
	for _ in pairs(core.registered_entities) do ents = ents + 1 end
	log("registered nodes=" .. n .. " max content id=" .. maxid .. " (limit 65535) items=" .. items .. " tools=" .. tools .. " entities=" .. ents)
	log("version " .. core.get_version().string .. " proto " .. tostring(core.get_version().proto_max))
	log("_VERSION=" .. _VERSION)
	if jit then
		log("jit.version=" .. tostring(jit.version) .. " arch=" .. tostring(jit.arch) .. " os=" .. tostring(jit.os) .. " status=" .. tostring((jit.status())))
	else log("jit=nil (plain Lua)") end
	log("ffi reachable=" .. tostring(rawget(_G, "ffi") ~= nil) .. " package=" .. tostring(rawget(_G, "package") ~= nil) .. " bit=" .. tostring(rawget(_G, "bit") ~= nil))
	log("ptr size test: 2^53+1 == 2^53 -> " .. tostring(2^53 + 1 == 2^53))
	log("lua memory now KB=" .. math.floor(collectgarbage("count")))
	-- memory ceiling: hold 64 MB strings until allocation fails or 2.5 GB is reached
	local hold, mb = {}, 0
	local ok, err = pcall(function()
		for i = 1, 40 do
			hold[i] = string.rep(string.char(i), 64 * 1024 * 1024)
			mb = mb + 64
		end
	end)
	log("alloc test: reached " .. mb .. " MB ok=" .. tostring(ok) .. " err=" .. tostring(err))
	hold = nil; collectgarbage()
	core.log("action", "[PROBE_TEST] SCENARIO_DONE")
	core.request_shutdown("probe done", false, 0)
end)
