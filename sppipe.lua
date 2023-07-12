--[[

Single-pixel pipe configurator script
LBPHacker, 2022-2023

This script adds a single element: SPPC, the single-pixel pipe configurator.

Basic usage is as simple as drawing a one pixel wide line of SPPC where you want
PIPE/PPIP to appear, and once satisfied, clicking on either end of the line with
PIPE/PPIP. This either results in the SPPC line being converted into the pipe
type of choice, or some error message regarding why the conversion cannot be
done. If conversion succeeds, the clicked end will be the input of the pipe.

Note that the process prefers non-diagonal neighbours over diagonal ones. This
is done so free-form drawn lines of SPPC can be converted to pipes easily, even
if they include L-shaped parts, which would be considered forks otherwise.

Advanced usage involves "adjacency domains", which let you cross lines of SPPC
and still have them convert into different pipes that don't leak into one
another. SPPC considers itself "logically" adjacent to any other, "physically"
adjacent SPPC if their .tmp values match, or if one of them has a .life value
that matches the .tmp value of the other. Physical adjacency is just being
adjacent on the pixel grid. Logical adjacency is what matters when discovering
the bounds of the pipe to be converted.

SPPC of different .tmp are rendered with different, vibrant colours. A special
case is .life != 0 SPPC, which is rendered with white, indicating that it acts
as a bridge between SPPC domains.

Drawing SPPC over any particle (the way you would normally set the ctype of
CLNE, for example) of a correctly configured single-pixel pipe converts the
entire pipe into SPPC, using as few bridge particles as possible.

]]

assert(tpt.version and tpt.version.major >= 95, "version not supported")

local prefix = "\bt[SPPIPE]\bw "

tpt.sppipe = tpt.sppipe or {}
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
	local dcolour = hsv2dcolour((0.318237 + key * 0.381763) % 1, 0.7, 1)
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

local sppc = elem.allocate("LBPHACKER", "SPPC")
if sppc == -1 then
	print(prefix .. "Failed to allocate SPPC: out of element IDs.")
	return
end
tpt.sppipe.SPPC = sppc
elem.element(sppc, elem.element(elem.DEFAULT_PT_DMND))
elem.property(sppc, "Name", "SPPC")
elem.property(sppc, "MenuSection", elem.SC_TOOL)

do
	local default_colour = spb_colour_cache[1]
	elem.property(sppc, "Color", default_colour[1] * 0x10000 + default_colour[2] * 0x100 + default_colour[3])
end
elem.property(sppc, "DefaultProperties", {
	tmp = 1,
})
elem.property(sppc, "Description", "Single-pixel pipe configurator. See the big comment at the top of the script for usage.")
elem.property(sppc, "Graphics", function(i)
	if sim.partProperty(i, "life") ~= 0 then
		return 0, ren.PMPDE_FLAT, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00
	end
	local domain = sim.partProperty(i, "tmp")
	local rgb = spb_colour_cache[domain]
	return 0, ren.PMPDE_FLAT, 0xFF, rgb[1], rgb[2], rgb[3], 0x00, 0x00, 0x00, 0x00
end)
elem.property(sppc, "CtypeDraw", function(id, ctype)
	if not pipe_types[ctype] then
		return
	end
	local x, y = get_position(id)
	local domain1, domain2 = get_domains(id)
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
			print(prefix .. "Forked pipe, candidates marked.")
			return
		end
		x, y, domain1, domain2 = candidates[1].x, candidates[1].y, candidates[1].domain1, candidates[1].domain2
		push(candidates[1])
	end
	for i = 1, #path do
		local id, x, y = path[i].id, path[i].x, path[i].y
		sim.partProperty(id, "type", path[i].ptype)
		-- print(path[i].ptype, sim.partProperty(id, "type"))
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

local function pipe_ctypedraw(id, ctype)
	if ctype ~= sppc then
		return
	end
	local x, y = get_position(id)
	local otype = sim.partProperty(id, "type")
	if bit.band(sim.partProperty(id, "tmp"), 0x100) == 0 then
		-- route_multi(id)
		print(prefix .. "Not a single-pixel pipe.")
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
		print(prefix .. "Broken links encountered.")
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
		print(prefix .. "Process yielded multiple domains.")
	end
	if parts_lost then
		print(prefix .. "In-pipe particles lost.")
	end
end

for ptype in pairs(pipe_types) do
	elem.property(ptype, "CtypeDraw", pipe_ctypedraw)
end
