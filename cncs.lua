local function plot_conic_section(x, y, plotfunc)
	local matrix, swap_row, swap_column
	local matrix_real = {}
	for ix = 1, 5 do
		table.insert(matrix_real, {x[ix] * x[ix], x[ix] * y[ix], y[ix] * y[ix], x[ix], y[ix], 1})
	end
	local rowmap = {1, 2, 3, 4, 5}
	local colmap = {1, 2, 3, 4, 5, 6}
	do
		local magic_row_mt = {__index = function(t, k)
			return matrix_real[rowmap[t.i]][colmap[k]]
		end, __newindex = function(t, k, v)
			matrix_real[rowmap[t.i]][colmap[k]] = v
		end}
		local magic_row = {}
		for ix = 1, 5 do
			magic_row[ix] = setmetatable({i = ix}, magic_row_mt)
		end
		matrix = setmetatable({}, {__index = function(t, k)
			return magic_row[k]
		end})
	end
	for i = 1, 4 do
		local max, max_ii, max_jj = -math.huge
		for ii = i, 5 do
			for jj = i, 5 do
				local c = math.abs(matrix[ii][jj])
				if max < c then
					max = c
					max_ii = ii
					max_jj = jj
				end
			end
		end
		rowmap[i], rowmap[max_ii] = rowmap[max_ii], rowmap[i]
		colmap[i], colmap[max_jj] = colmap[max_jj], colmap[i]
		local d = matrix[i][i]
		if d == 0 then
			return false
		end
		for j = i + 1, 5 do
			local e = matrix[j][i] / d
			matrix[j][i] = 0
			for ii = i + 1, 6 do
				matrix[j][ii] = matrix[j][ii] - e * matrix[i][ii]
			end
		end
	end
	if matrix[5][5] == 0 then
		return false
	end
	for i = 5, 2, -1 do
		local d = matrix[i][i]
		if d == 0 then
			return false
		end
		for j = i - 1, 1, -1 do
			local e = matrix[j][i] / d
			matrix[j][i] = 0
			for ii = i - 1, 1, -1 do
				matrix[j][ii] = matrix[j][ii] - e * matrix[i][ii]
			end
			matrix[j][6] = matrix[j][6] - e * matrix[i][6]
		end
	end
	if matrix[1][1] == 0 then
		return false
	end
	for j = 1, 5 do
		matrix[j][6] = matrix[j][6] / matrix[j][j]
	end
	local xr, yr = sim.XRES, sim.YRES
	local val1 = {}
	do
		local revmap = {}
		for j = 1, 5 do
			revmap[colmap[j]] = j
		end
		local cxx = matrix[revmap[1]][6]
		local cxy = matrix[revmap[2]][6]
		local cyy = matrix[revmap[3]][6]
		local cx = matrix[revmap[4]][6]
		local cy = matrix[revmap[5]][6]
		local val1_row_mt = {__index = function(t, y)
			local v = (cxx * t.x + cxy * y + cx) * t.x + (cyy * y + cy) * y
			t[y] = v
			return v
		end}
		setmetatable(val1, {__index = function(t, x)
			local v = setmetatable({x = x}, val1_row_mt)
			t[x] = v
			return v
		end})
	end
	local visited = setmetatable({}, {__index = function(t, k)
		local v = {}
		t[k] = v
		return v
	end})
	local to_visit = {}
	for ix = 0, xr - 1 do
		table.insert(to_visit, {ix, 0})
		table.insert(to_visit, {ix, yr - 1})
	end
	for iy = 0, yr - 1 do
		table.insert(to_visit, {0, iy})
		table.insert(to_visit, {xr - 1, iy})
	end
	for ix = 1, 5 do
		table.insert(to_visit, {x[ix], y[ix]})
	end
	while next(to_visit) do
		local new_to_visit = {}
		for key, pos in pairs(to_visit) do
			local c = val1[pos[1]][pos[2]] > 1
			for dx = math.max(0, pos[1] - 1), math.min(xr - 1, pos[1] + 1) do
				for dy = math.max(0, pos[2] - 1), math.min(yr - 1, pos[2] + 1) do
					local c2 = val1[dx][dy] > 1
					if c ~= c2 then
						plotfunc(dx, dy)
						if not visited[dx][dy] then
							table.insert(new_to_visit, {dx, dy})
							visited[dx][dy] = true
						end
					end
				end
			end
		end
		to_visit = new_to_visit
	end
	return true
end

tpt.CNCS = tpt.CNCS or {}
pcall(elem.free, tpt.CNCS.elem)
if tools then
	pcall(tools.free, tpt.CNCS.tool)
end
pcall(event.unregister, event.tick, tpt.CNCS.overlay)
pcall(event.unregister, event.tick, tpt.CNCS.tool_overlay)

local x, y = {}, {}
local function trigger()
	if #x == 4 then
		event.register(event.tick, tpt.CNCS.overlay)
	elseif #x == 5 then
		event.unregister(event.tick, tpt.CNCS.overlay)
		if not plot_conic_section(x, y, function(dx, dy)
			sim.partCreate(-2, dx, dy, elem.DEFAULT_PT_DMND)
		end) then
			print("No non-degenerate conic exists that passes through all five points.")
		end
		x, y = {}, {}
	end
end

local ELEM_GROUP  = "lbphacker"
local ELEM_NAME   = "conicsection"
local ELEM_MNAME  = "CNCS"
local ELEM_DESC   = "Conic section generator. Place five of them using the smallest brush to get a conic section made from DMND."
local ELEM_MCOLOR = 0x882647
if tools then
	tpt.CNCS.tool = tools.allocate(ELEM_GROUP, ELEM_NAME)
	tools.property(tpt.CNCS.tool, "Name", ELEM_MNAME)
	tools.property(tpt.CNCS.tool, "Description", ELEM_DESC)
	tools.property(tpt.CNCS.tool, "Color", ELEM_MCOLOR)
	tools.property(tpt.CNCS.tool, "Click", function(brush, px, py, strength, shift, ctrl, alt)
		x[#x + 1], y[#x + 1] = px, py
		trigger()
	end)

	function tpt.CNCS.tool_overlay()
		for i = 1, #x do
			gfx.drawLine(x[i] + 3, y[i] - 3, x[i] - 3, y[i] + 3)
			gfx.drawLine(x[i] - 3, y[i] - 3, x[i] + 3, y[i] + 3)
		end
	end
	event.register(event.tick, tpt.CNCS.tool_overlay)
else
	tpt.CNCS.elem = elem.allocate(ELEM_GROUP, ELEM_NAME)
	elem.element(tpt.CNCS.elem, elem.element(elem.DEFAULT_PT_DMND))
	elem.property(tpt.CNCS.elem, "Name", ELEM_MNAME)
	elem.property(tpt.CNCS.elem, "MenuSection", elem.SC_TOOL)
	elem.property(tpt.CNCS.elem, "Description", ELEM_DESC)
	elem.property(tpt.CNCS.elem, "Color", ELEM_MCOLOR)
	elem.property(tpt.CNCS.elem, "Graphics", function(i)
		sim.partChangeType(i, elem.DEFAULT_PT_DMND)
		x[#x + 1], y[#x + 1] = sim.partPosition(i)
		trigger()
	end)
end

function tpt.CNCS.overlay()
	x[5], y[5] = sim.adjustCoords(tpt.mousex, tpt.mousey)
	plot_conic_section(x, y, function(dx, dy)
		gfx.drawLine(dx, dy, dx, dy)
	end)
	x[5], y[5] = nil, nil
end
