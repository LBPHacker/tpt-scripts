assert(tpt.version and ((tpt.version.upstreamMajor and tpt.version.upstreamMajor >= 95) or tpt.version.major >= 95), "version not supported")

local function prefix_printf(...)
	print("\bt[SPPC]\bw " .. string.format(...))
end

local function prefix_printf_err(...)
	print("\bl[SPPC]\bw " .. string.format(...))
end

tpt.sppipe = tpt.sppipe or {}
pcall(event.unregister, event.keypress, tpt.sppipe.keypress)
pcall(event.unregister, event.keyrelease, tpt.sppipe.keyrelease)
pcall(event.unregister, event.mousewheel, tpt.sppipe.mousewheel)
pcall(event.unregister, event.mousedown, tpt.sppipe.mousedown)
pcall(elem.free, tpt.sppipe.SPPC)

local function hsv2dcolour(h, s, v)
	local sector = math.floor(h * 6)
	local offset = h * 6 - sector
	local r, g, b
	if sector == 0 then
		r, g, b = 1, offset, 0
	elseif sector == 1 then
		r, g, b = 1 - offset, 1, 0
	elseif sector == 2 then
		r, g, b = 0, 1, offset
	elseif sector == 3 then
		r, g, b = 0, 1 - offset, 1
	elseif sector == 4 then
		r, g, b = offset, 0, 1
	else
		r, g, b = 1, 0, 1 - offset
	end
	r = math.floor((s * (r - 1) + 1) * 0xFF * v)
	g = math.floor((s * (g - 1) + 1) * 0xFF * v)
	b = math.floor((s * (b - 1) + 1) * 0xFF * v)
	return { r, g, b }
end

local spb_colour_cache = setmetatable({}, { __index = function(tbl, key)
	local dcolour
	if key <= 0 then
		dcolour = { 0x80, 0x80, 0x80 }
	else
		dcolour = hsv2dcolour((0.318237 + key * 0.381763) % 1, 0.7, 1)
	end
	tbl[key] = dcolour
	return dcolour
end })

local pos_1_rx = { -1, -1, -1,  0,  0,  1,  1,  1 }
local pos_1_ry = { -1,  0,  1, -1,  1, -1,  0,  1 }
local function get_dir(to, from)
	local dx = to.x - from.x
	local dy = to.y - from.y
	local dir
	for i = 1, 8 do
		if dx == pos_1_rx[i] and dy == pos_1_ry[i] then
			dir = i - 1
		end
	end
	return assert(dir)
end

local function neighbourhood(try_next, prefer_nondiagonal)
	local candidates = {}
	local function try_next_wrapper(xoff, yoff)
		local candidate = try_next(xoff, yoff)
		if candidate then
			table.insert(candidates, candidate)
		end
	end
	try_next_wrapper(-1,  0)
	try_next_wrapper( 1,  0)
	try_next_wrapper( 0, -1)
	try_next_wrapper( 0,  1)
	if not prefer_nondiagonal or #candidates == 0 then
		try_next_wrapper(-1, -1)
		try_next_wrapper( 1, -1)
		try_next_wrapper(-1,  1)
		try_next_wrapper( 1,  1)
	end
	return candidates
end

local function segments_connect(a, b)
	return bit.band(a, 0xFFFF) == bit.band( b     , 0xFFFF)
	    or bit.band(a, 0xFFFF) == bit.band((b - 1), 0xFFFF)
	    or bit.band(a, 0xFFFF) == bit.band((b + 1), 0xFFFF)
end

local pipe_types = {
	[ elem.DEFAULT_PT_PIPE ] = true,
	[ elem.DEFAULT_PT_PPIP ] = true,
}

local function get_domains(id)
	local domain1 = sim.partProperty(id, "tmp")
	local domain2 = sim.partProperty(id, "life")
	if domain2 == 0 then
		domain2 = domain1
	end
	return domain1, domain2
end

local function get_position(id)
	local x, y = sim.partPosition(id)
	x = math.floor(x + 0.5)
	y = math.floor(y + 0.5)
	return x, y
end

local sppc, sppc_identifier
do
	local group = "LBPHACKER"
	local name = "SPPC"
	sppc = elem.allocate(group, name)
	sppc_identifier = group .. "_PT_" .. name
end
if sppc == -1 then
	prefix_printf_err("Failed to allocate SPPC: out of element IDs.")
	return
end
tpt.sppipe.SPPC = sppc
elem.element(sppc, elem.element(elem.DEFAULT_PT_DMND))
elem.property(sppc, "Name", "SPPC")
elem.property(sppc, "MenuSection", elem.SC_TOOL)
elem.property(sppc, "Graphics", function(i)
	if sim.partProperty(i, "life") ~= 0 then
		return 0, ren.PMODE_FLAT, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00
	end
	local domain = sim.partProperty(i, "tmp")
	local rgb = spb_colour_cache[domain]
	return 0, ren.PMODE_FLAT, 0xFF, rgb[1], rgb[2], rgb[3], 0x00, 0x00, 0x00, 0x00
end)
elem.property(sppc, "CtypeDraw", function(id, ctype)
	if not pipe_types[ctype] then
		return
	end
	local x, y = get_position(id)
	local domain1, domain2 = get_domains(id)
	if domain1 <= 0 then
		prefix_printf_err("Invalid domain, should be a positive number.")
		return
	end
	local seen = {}
	local path = {}
	local function push(item)
		seen[item.id] = true
		table.insert(path, item)
		sim.partProperty(item.id, "dcolour", 0xFF00FF00)
	end
	push({ id = id, x = x, y = y, ptype = ctype })
	while true do
		local candidates = neighbourhood(function(xoff, yoff)
			local xx = x + xoff
			local yy = y + yoff
			local r = sim.partID(xx, yy)
			if r and not seen[r] and sim.partProperty(r, "type") == sppc then
				local r_domain1, r_domain2 = get_domains(r)
				if domain1 == r_domain1
				or domain1 == r_domain2
				or domain2 == r_domain1
				or domain2 == r_domain2 then
					local ptype = sim.partProperty(r, "ctype")
					if not pipe_types[ptype] then
						ptype = ctype
					end
					return { id = r, x = xx, y = yy, domain1 = r_domain1, domain2 = r_domain2, ptype = ptype }
				end
			end
		end, true)
		if #candidates == 0 then
			break
		elseif #candidates > 1 then
			for i = 1, #candidates do
				sim.partProperty(candidates[i].id, "dcolour", 0xFFFF0000)
			end
			prefix_printf_err("Forked pipe, candidates marked with red dcolour.")
			return
		end
		x, y, domain1, domain2 = candidates[1].x, candidates[1].y, candidates[1].domain1, candidates[1].domain2
		push(candidates[1])
	end
	for i = 1, #path do
		local id, x, y = path[i].id, path[i].x, path[i].y
		sim.partProperty(id, "type", path[i].ptype)
		local tmp = bit.bor(0x100, bit.lshift(i % 3 + 1, 18))
		if i ~= 1 then
			tmp = bit.bor(tmp, bit.lshift(get_dir(path[i], path[i - 1]), 14), 0x2000)
		end
		if i ~= #path then
			tmp = bit.bor(tmp, bit.lshift(get_dir(path[i], path[i + 1]), 10), 0x200)
		end
		sim.partProperty(id, "tmp", tmp)
		sim.partProperty(id, "ctype", 0)
		sim.partProperty(id, "life", 0)
		sim.partProperty(id, "dcolour", 0)
	end
end)

local default_tmp
local function set_default_tmp(new_default_tmp, quiet)
	default_tmp = new_default_tmp
	elem.property(sppc, "DefaultProperties", {
		tmp = default_tmp,
	})
	local default_colour = spb_colour_cache[default_tmp]
	elem.property(sppc, "Color", default_colour[1] * 0x10000 + default_colour[2] * 0x100 + default_colour[3])
	elem.property(sppc, "Description", "Single-pixel pipe configurator. See the big comment at the top of the script for help. Default .tmp = " .. default_tmp .. ".")
	if not quiet then
		prefix_printf("Default .tmp set to %i.", default_tmp)
	end
end
set_default_tmp(1, true)

local z_down = false
local alt_down = false

local button_to_slot = {
	[ ui.SDL_BUTTON_LEFT   ] = "selectedl",
	[ ui.SDL_BUTTON_MIDDLE ] = "selecteda",
	[ ui.SDL_BUTTON_RIGHT  ] = "selectedr",
}

local function enable_shortcuts()
	return (tpt.selectedl       == sppc_identifier or
	        tpt.selecteda       == sppc_identifier or
	        tpt.selectedr       == sppc_identifier or
	        tpt.selectedreplace == sppc_identifier) and not z_down and not alt_down
end

local function decrement_default_tmp()
	if default_tmp > 1 then
		set_default_tmp(default_tmp - 1)
	end
end

local function increment_default_tmp()
	if default_tmp < 0x7FFFFFFF then
		set_default_tmp(default_tmp + 1)
	end
end

function tpt.sppipe.keypress(key, scan, rep, shift, ctrl, alt)
	if scan == 29 then -- more strict than necessary but it doesn't matter
		z_down = true
	end
	alt_down = alt
	if enable_shortcuts() then
		if scan == 47 and not shift and not ctrl and not alt then
			if not rep then
				decrement_default_tmp()
			end
			return false
		end
		if scan == 48 and not shift and not ctrl and not alt then
			if not rep then
				increment_default_tmp()
			end
			return false
		end
		if not shift and not ctrl and not alt and key >= 48 and key <= 57 then
			if key == 48 then
				set_default_tmp(10)
			else
				set_default_tmp(key - 48)
			end
			return false
		end
	end
end
event.register(event.keypress, tpt.sppipe.keypress)

function tpt.sppipe.keyrelease(key, scan, rep, shift, ctrl, alt)
	if scan == 29 then
		z_down = false
	end
	alt_down = alt
end
event.register(event.keyrelease, tpt.sppipe.keyrelease)

function tpt.sppipe.mousewheel(px, py, dir)
	if enable_shortcuts() then
		if dir > 0 then
			increment_default_tmp()
		end
		if dir < 0 then
			decrement_default_tmp()
		end
		return false
	end
end
event.register(event.mousewheel, tpt.sppipe.mousewheel)

function tpt.sppipe.mousedown(px, py, button)
	local px, py = sim.adjustCoords(px, py)
	local slot = button_to_slot[button]
	if slot and tpt[slot] == "DEFAULT_UI_SAMPLE" then
		local id = sim.partID(px, py)
		if id and sim.partProperty(id, "type") == sppc then
			set_default_tmp(sim.partProperty(id, "tmp"))
		end
	end
end
event.register(event.mousedown, tpt.sppipe.mousedown)

local function pipe_ctypedraw(id, ctype)
	if ctype ~= sppc then
		return
	end
	local x, y = get_position(id)
	local otype = sim.partProperty(id, "type")
	if bit.band(sim.partProperty(id, "tmp"), 0x100) == 0 then
		-- route_multi(id)
		prefix_printf_err("Not a single-pixel pipe.")
		return
	end
	local domains_seen = {}
	local parts_seen = { [ id ] = true }
	local function neighbourhood_checker(adjacent, origin)
		local torigin = { x = origin.x, y = origin.y, tmp = sim.partProperty(sim.partID(origin.x, origin.y), "tmp") }
		return function(xoff, yoff)
			local xx = torigin.x + xoff
			local yy = torigin.y + yoff
			local r = sim.partID(xx, yy)
			if r and sim.partProperty(r, "type") == sppc and r ~= id then
				local domain = sim.partProperty(r, "tmp")
				domains_seen[domain] = true
			end
			if r and pipe_types[sim.partProperty(r, "type")] then
				local tmp = sim.partProperty(r, "tmp")
				local neighbour = { x = xx, y = yy, tmp = tmp }
				if bit.band(tmp, 0x100) ~= 0 and adjacent(neighbour, torigin) then
					return { id = r, x = xx, y = yy }
				end
			end
		end
	end
	local function traverse(func)
		local path = {}
		local last = { x = x, y = y }
		while true do
			local candidates = neighbourhood(neighbourhood_checker(func, last), false)
			if #candidates == 0 then
				break
			elseif #candidates > 1 then
				for i = 1, #candidates do
					sim.partProperty(candidates[i].id, "dcolour", 0xFFFF0000)
				end
				prefix_printf_err("Forked pipe, candidates marked with red dcolour.")
				return false
			elseif parts_seen[candidates[1].id] then
				prefix_printf_err("Cyclic pipe.")
				return false
			else
				local id = candidates[1].id
				parts_seen[id] = true
				sim.partProperty(id, "dcolour", 0xFF00FF00)
				last = candidates[1]
				table.insert(path, last)
			end
		end
		return path
	end
	local function forward_link(first, second)
		return (bit.band(first.tmp, 0x200) ~= 0 and bit.rshift(bit.band(first.tmp, 0x1C00), 10)) == get_dir(first, second)
	end
	local function reverse_link(first, second)
		return (bit.band(first.tmp, 0x2000) ~= 0 and bit.rshift(bit.band(first.tmp, 0x1C000), 14)) == get_dir(first, second)
	end
	local broken_links = false
	local forward_path = traverse(function(neighbour, origin)
		local score = 0
		score = score + (forward_link(neighbour, origin) and 1 or 0)
		score = score + (reverse_link(origin, neighbour) and 1 or 0)
		if score == 1 then
			broken_links = true
		end
		return score > 0
	end)
	local reverse_path = traverse(function(neighbour, origin)
		local score = 0
		score = score + (reverse_link(neighbour, origin) and 1 or 0)
		score = score + (forward_link(origin, neighbour) and 1 or 0)
		if score == 1 then
			broken_links = true
		end
		return score > 0
	end)
	if not forward_path or not reverse_path then
		return
	end
	if broken_links then
		prefix_printf_err("Broken links encountered.")
	end
	local path = {}
	for i = #forward_path, 1, -1 do
		table.insert(path, forward_path[i])
	end
	table.insert(path, { id = id, x = x, y = y })
	for i = 1, #reverse_path do
		table.insert(path, reverse_path[i])
	end
	local id_to_index = {}
	for i = 1, #path do
		id_to_index[path[i].id] = i
		path[i].ptype = sim.partProperty(path[i].id, "type")
	end
	local lower_bound_sets = {}
	for i = 1, #path do
		lower_bound_sets[i] = {}
	end
	for i = 1, #path do
		neighbourhood(function(xoff, yoff)
			local r = sim.partID(path[i].x + xoff, path[i].y + yoff)
			if r and id_to_index[r] and id_to_index[r] > i + 1 then
				table.insert(lower_bound_sets[id_to_index[r]], i + 1)
			end
			if r and id_to_index[r] and id_to_index[r] == i + 1 then
				return true
			end
		end, true)
	end
	local parts_lost = false
	local local_domain = 0
	local global_domain = 0
	local function next_domain()
		local_domain = local_domain + 1
		repeat
			global_domain = global_domain + 1
		until not domains_seen[global_domain]
	end
	next_domain()
	local last_global_domain = global_domain
	local index_to_domain = {}
	for i = 1, #path do
		for j = 1, #lower_bound_sets[i] do
			while index_to_domain[lower_bound_sets[i][j]] >= local_domain do
				next_domain()
			end
		end
		if sim.partProperty(path[i].id, "ctype") ~= 0 then
			parts_lost = true
		end
		sim.partProperty(path[i].id, "type", sppc)
		sim.partProperty(path[i].id, "dcolour", 0)
		sim.partProperty(path[i].id, "tmp", global_domain)
		sim.partProperty(path[i].id, "ctype", path[i].ptype)
		index_to_domain[i] = local_domain
		if last_global_domain ~= global_domain then
			assert(path[i - 1])
			sim.partProperty(path[i - 1].id, "life", global_domain)
		end
		last_global_domain = global_domain
	end
	if local_domain > 1 then
		prefix_printf("Process yielded multiple domains.")
	end
	if parts_lost then
		prefix_printf("In-pipe particles lost.")
	end
end

for ptype in pairs(pipe_types) do
	elem.property(ptype, "CtypeDraw", pipe_ctypedraw)
end
