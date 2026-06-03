function _G.rescanStamps()
	os.remove("stamps/stamps.def")
	local sj = assert(io.open("stamps/stamps.json", "wb"))
	local items = {}
	for _, item in ipairs(fs.list("stamps")) do
		local match = item:match("^(.+)%.stm$")
		if match then
			table.insert(items, [["]] .. match:gsub("[\\\"]", "\\%1") .. [["]])
		end
	end
	sj:write([[{"MostRecentlyUsedFirst":[]] .. table.concat(items, ",") .. [[]}]])
	assert(sj:close())
	platform.restart()
end
