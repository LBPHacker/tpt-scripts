assert(tpt.version and tpt.version.major >= 95, "version not supported")

local prefix = "\bt[SPPIPE]\bw "
local default_tmp = 1
local default_life = 0

tpt.sppipe = tpt.sppipe or {}
for _, value in pairs(tpt.sppipe) do
	pcall(elem.free, value)
end

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
	local dcolour = hsv2dcolour((0.7 + key * 0.381763) % 1, 0.7, 1)
	tbl[key] = dcolour
	return dcolour
end })

local function alloc_elem(name)
	local id = elem.allocate("LBPHACKER", name)
	if id == -1 then
		print(prefix .. "Failed to allocate element " .. name .. ": out of element IDs.")
		return
	end
	tpt.sppipe[name] = id
	elem.element(id, elem.element(elem.DEFAULT_PT_DMND))
	elem.property(id, "Name", name)
	elem.property(id, "MenuSection", elem.SC_TOOL)
	return id
end

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

local function neighbourhood_prefer_nondiagonal(try_next)
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
	if #candidates == 0 then
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

local sppc = alloc_elem("SPPC")
do
	local default_colour = spb_colour_cache[default_tmp]
	elem.property(sppc, "Color", default_colour[1] * 0x10000 + default_colour[2] * 0x100 + default_colour[3])
end
elem.property(sppc, "Description", "Single-pixel pipe configurator. Draw over with a pipe type to finalize. Set domain with tmp. Domain 0 is a wildcard.")
elem.property(sppc, "Graphics", function(i)
	local domain = sim.partProperty(i, "tmp")
	local rgb = spb_colour_cache[domain]
	return 0, ren.PMPDE_FLAT, 255, rgb[1], rgb[2], rgb[3], 0, 0, 0, 0
end)
local next_create_tmp, next_create_life, next_create_id
elem.property(sppc, "Create", function(id)
	local tmp = default_tmp
	local life = default_life
	if next_create_tmp and next_create_id == id then
		tmp = next_create_tmp
		life = next_create_life
		next_create_tmp = nil
		next_create_life = nil
		next_create_id = nil
	end
	sim.partProperty(id, "tmp", tmp)
	sim.partProperty(id, "life", life)
end)
elem.property(sppc, "CtypeDraw", function(id, ctype)
	if not pipe_types[ctype] then
		return
	end
	local x, y = sim.partPosition(id)
	x = math.floor(x + 0.5)
	y = math.floor(y + 0.5)
	local domain = sim.partProperty(id, "tmp")
	local segment = sim.partProperty(id, "life")
	local seen = {}
	local path = {}
	local function push(item)
		seen[item.id] = true
		table.insert(path, item)
		sim.partProperty(item.id, "dcolour", 0xFF00FF00)
	end
	push({ id = id, x = x, y = y })
	while true do
		local candidates = neighbourhood_prefer_nondiagonal(function(xoff, yoff)
			local xx = x + xoff
			local yy = y + yoff
			local r = sim.partID(xx, yy)
			if r and not seen[r] and sim.partProperty(r, "type") == sppc then
				local r_domain = sim.partProperty(r, "tmp")
				local r_segment = sim.partProperty(r, "life")
				if domain == 0 or r_domain == 0 or (r_domain == domain and segments_connect(r_segment, segment)) then
					return { id = r, x = xx, y = yy, domain = r_domain, segment = r_segment }
				end
			end
		end)
		if #candidates == 0 then
			break
		elseif #candidates > 1 then
			for i = 1, #candidates do
				sim.partProperty(candidates[i].id, "dcolour", 0xFFFF0000)
			end
			print(prefix .. "Forked pipe, candidates marked.")
			return
		end
		x, y, domain, segment = candidates[1].x, candidates[1].y, candidates[1].domain, candidates[1].segment
		push(candidates[1])
	end
	for i = 1, #path do
		local id, x, y = path[i].id
		local x = path[i].x
		local y = path[i].y
		sim.partProperty(id, "type", ctype)
		local tmp = bit.bor(0x100, bit.lshift(i % 3 + 1, 18))
		if i ~= 1 then
			tmp = bit.bor(tmp, bit.lshift(get_dir(path[i], path[i - 1]), 14), 0x2000)
		end
		if i ~= #path then
			tmp = bit.bor(tmp, bit.lshift(get_dir(path[i], path[i + 1]), 10), 0x200)
		end
		sim.partProperty(id, "tmp", tmp)
		sim.partProperty(id, "life", 0)
		sim.partProperty(id, "dcolour", 0)
	end
end)
elem.property(sppc, "ChangeType", function(id, x, y, otype, ntype)
	if otype == sppc and ntype == sppc then
		-- Hack: Smuggle SPPC's tmp and life through the replacement with itself.
		next_create_tmp = sim.partProperty(id, "tmp")
		next_create_life = sim.partProperty(id, "life")
		next_create_id = id
		return
	end
	if not pipe_types[otype] then
		return
	end
	local domains_seen = {}
	local parts_seen = { [ id ] = true }
	local function neighbourhood_checker(adjacent, replaced)
		return function(xoff, yoff)
			local xx = replaced.x + xoff
			local yy = replaced.y + yoff
			local r = sim.partID(xx, yy)
			if r and sim.partProperty(r, "type") == sppc and r ~= id then
				local domain = sim.partProperty(r, "tmp")
				domains_seen[domain] = true
			end
			if r and pipe_types[sim.partProperty(r, "type")] then
				local tmp = sim.partProperty(r, "tmp")
				if bit.band(tmp, 0x100) ~= 0 and adjacent(tmp, { x = xx, y = yy }, replaced) then
					return { id = r, x = xx, y = yy }
				end
			end
		end
	end
	local function traverse(func)
		local path = {}
		local last = { x = x, y = y }
		while true do
			local candidates = neighbourhood_prefer_nondiagonal(neighbourhood_checker(func, last))
			if #candidates == 0 then
				break
			elseif #candidates > 1 then
				for i = 1, #candidates do
					sim.partProperty(candidates[i].id, "dcolour", 0xFFFF0000)
				end
				print(prefix .. "Forked pipe, candidates marked.")
				return false
			elseif parts_seen[candidates[1].id] then
				print(prefix .. "Cyclic pipe.")
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
	local forward_path = traverse(function(tmp, neighbour, replaced)
		return (bit.band(tmp, 0x200) ~= 0 and bit.rshift(bit.band(tmp, 0x1C00), 10)) == get_dir(neighbour, replaced)
	end)
	local reverse_path = traverse(function(tmp, neighbour, replaced)
		return (bit.band(tmp, 0x2000) ~= 0 and bit.rshift(bit.band(tmp, 0x1C000), 14)) == get_dir(neighbour, replaced)
	end)
	if not forward_path or not reverse_path then
		return
	end
	local path = {}
	for i = #forward_path, 1, -1 do
		table.insert(path, forward_path[i])
	end
	table.insert(path, { id = id, x = x, y = y })
	for i = 1, #reverse_path do
		table.insert(path, reverse_path[i])
	end
	local mixed = false
	for i = 1, #path do
		local ptype = sim.partProperty(path[i].id, "type")
		if ptype ~= otype and ptype ~= sppc then
			mixed = true
			sim.partProperty(path[i].id, "dcolour", 0xFFFF0000)
		end
	end
	if mixed then
		print(prefix .. "Mixed pipe, foreign type marked.")
		return
	end
	local domain = 1
	while domains_seen[domain] do
		domain = domain + 1
	end
	local segment = 0
	for i = 1, #path do
		local transition = false
		local max_earlier_segment = 0
		for yoff = -1, 1 do
			for xoff = -1, 1 do
				local r = sim.partID(path[i].x + xoff, path[i].y + yoff)
				if  r
				and r ~= id
				and parts_seen[r]
				and sim.partProperty(r, "type") == sppc
				and sim.partProperty(r, "life") > segment - 2
				and path[i - 1]
				and path[i - 1].id ~= r
				and path[i - 2]
				and path[i - 2].id ~= r then
					transition = true
					max_earlier_segment = math.max(max_earlier_segment, sim.partProperty(r, "life"))
				end
			end
		end
		local id = path[i].id
		sim.partProperty(id, "type", sppc)
		sim.partProperty(id, "tmp", domain)
		sim.partProperty(id, "dcolour", 0)
		if transition then
			segment = segment + 1
			sim.partProperty(id, "dcolour", 0xFFFFFF00)
			sim.partProperty(path[i - 1].id, "dcolour", 0xFFFFFF00)
			if max_earlier_segment == segment - 1 then
				sim.partProperty(path[i - 1].id, "life", segment)
				if path[i - 2] then
					sim.partProperty(path[i - 2].id, "dcolour", 0xFFFFFF00)
				end
				segment = segment + 1
			end
		end
		sim.partProperty(id, "life", segment)
	end
	if segment ~= 0 then
		print(prefix .. "Deconstruction yielded multiple segments, transitions marked.")
	end
	if segment >= 0x10000 then
		print(prefix .. "Deconstruction yielded too many segments, result possibly invalid.")
	end
end)