local ELEM_GROUP = "LBPHACKER"
local ELEM_NAME = "DECONOISE"
local ELEM_MNAME = "NOIS"
local ELEM_DESC = "Add noise to decoration color."
local ELEM_MCOLOR = 0x421337
local INTENSITY = 3

local function add_noise_on(id)
	local deco = sim.partProperty(id, sim.FIELD_DCOLOUR)
	local a = bit.band(bit.rshift(deco, 24), 0xFF)
	local r = bit.band(bit.rshift(deco, 16), 0xFF)
	local g = bit.band(bit.rshift(deco, 8), 0xFF)
	local b = bit.band(deco, 0xFF)

	if a ~= 0xFF then
		a = a / 0xFF
		local elem_color = elem.property(sim.partProperty(id, sim.FIELD_TYPE), "Color")
		local er = bit.band(bit.rshift(elem_color, 16), 0xFF)
		local eg = bit.band(bit.rshift(elem_color, 8), 0xFF)
		local eb = bit.band(elem_color, 0xFF)
		r = math.floor(a * r + (1 - a) * er)
		g = math.floor(a * g + (1 - a) * eg)
		b = math.floor(a * b + (1 - a) * eb)
	end

	r = math.min(0xFF, math.max(0, r + math.random(-INTENSITY, INTENSITY)))
	g = math.min(0xFF, math.max(0, g + math.random(-INTENSITY, INTENSITY)))
	b = math.min(0xFF, math.max(0, b + math.random(-INTENSITY, INTENSITY)))
	sim.partProperty(id, sim.FIELD_DCOLOUR, bit.bor(bit.bor(bit.bor(0xFF000000, bit.lshift(r, 16)), bit.lshift(g, 8)), b))
end

if tpt.NOIS then
	pcall(event.unregister, event.mousedown, tpt.NOIS.mousedown)
	pcall(event.unregister, event.mousemove, tpt.NOIS.mousemove)
	pcall(event.unregister, event.mouseup, tpt.NOIS.mouseup)
	pcall(event.unregister, event.tick, tpt.NOIS.tick)
	pcall(elem.free, tpt.NOIS.elem_noise)
	if tools then
		pcall(tools.free, tpt.NOIS.tool_noise)
	end
else
	tpt.NOIS = {}
end

if tools then
	tpt.NOIS.tool_noise = tools.allocate(ELEM_GROUP, ELEM_NAME)
	tools.property(tpt.NOIS.tool_noise, "Name", ELEM_MNAME)
	tools.property(tpt.NOIS.tool_noise, "Description", ELEM_DESC)
	tools.property(tpt.NOIS.tool_noise, "Color", ELEM_MCOLOR)
	tools.property(tpt.NOIS.tool_noise, "Perform", function(i, x, y, strength, shift, ctrl, alt, bx, by)
		if i then
			add_noise_on(i)
		end
	end)
else
	local button_down
	local elem_unique_id = ELEM_GROUP .. "_PT_" .. ELEM_NAME
	local function add_noise(mousexU, mouseyU)
		if mousexU < sim.XRES and mouseyU < sim.YRES
		and ((tpt.selectedl == elem_unique_id and button_down == 1)
		or (tpt.selectedr == elem_unique_id and button_down == 4)
		or (tpt.selecteda == elem_unique_id and button_down == 2)) then
			local mousex, mousey = sim.adjustCoords(mousexU, mouseyU)
			for x, y in sim.brush(mousex, mousey, tpt.brushx, tpt.brushy) do
				local id = sim.partID(x, y)
				if id then
					add_noise_on(id)
				end
			end
			return false
		end
	end
	function tpt.NOIS.tick()
		add_noise(tpt.mousex, tpt.mousey)
	end
	function tpt.NOIS.mouseup(mousexU, mouseyU, button)
		if button_down == button then
			button_down = nil
		end
	end
	function tpt.NOIS.mousedown(mousexU, mouseyU, button)
		if not button_down then
			button_down = button
		end
		return tpt.NOIS.mousemove(mousexU, mouseyU, button)
	end
	function tpt.NOIS.mousemove(mousexU, mouseyU)
		add_noise(mousexU, mouseyU)
	end
	event.register(event.mousedown, tpt.NOIS.mousedown)
	event.register(event.mousemove, tpt.NOIS.mousemove)
	event.register(event.mouseup, tpt.NOIS.mouseup)
	event.register(event.tick, tpt.NOIS.tick)

	tpt.NOIS.elem_noise = elem.allocate(ELEM_GROUP, ELEM_NAME)
	elem.element(tpt.NOIS.elem_noise, elem.element(elem.DEFAULT_PT_DMND))
	elem.property(tpt.NOIS.elem_noise, "Name", ELEM_MNAME)
	elem.property(tpt.NOIS.elem_noise, "Color", ELEM_MCOLOR)
	elem.property(tpt.NOIS.elem_noise, "MenuSection", elem.SC_TOOL)
	elem.property(tpt.NOIS.elem_noise, "Description", ELEM_DESC)
	elem.property(tpt.NOIS.elem_noise, "Graphics", sim.partKill)
end
