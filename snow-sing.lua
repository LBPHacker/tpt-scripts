tpt.SSNG = tpt.SSNG or {}
pcall(elem.free, tpt.SSNG.elem)
if tools then
	pcall(tools.free, tpt.SSNG.tool)
end

local ELEM_GROUP  = "lbphacker"
local ELEM_NAME   = "singsnow"
local ELEM_MNAME  = "SSNG"
local ELEM_DESC   = "SNOWified SING. Makes nice explosions instead of melting."
local ELEM_MCOLOR = 0xC0E0FF

local function configure(i)
	sim.partProperty(i, "ctype", elem.DEFAULT_PT_SING)
	sim.partProperty(i, "tmp", 5000)
end

if tools then
	tpt.SSNG.tool = tools.allocate(ELEM_GROUP, ELEM_NAME)
	tools.property(tpt.SSNG.tool, "Name", ELEM_MNAME)
	tools.property(tpt.SSNG.tool, "Description", ELEM_DESC)
	tools.property(tpt.SSNG.tool, "Color", ELEM_MCOLOR)
	tools.property(tpt.SSNG.tool, "Perform", function(i, x, y, strength, shift, ctrl, alt, bx, by)
		local i = sim.partCreate(-2, x, y, elem.DEFAULT_PT_SNOW)
		if i ~= -1 then
			configure(i)
		end
	end)
else
	tpt.SSNG.elem = elem.allocate(ELEM_GROUP, ELEM_NAME)
	elem.element(tpt.SSNG.elem, elem.element(elem.DEFAULT_PT_SNOW))
	elem.property(tpt.SSNG.elem, "Name", ELEM_MNAME)
	elem.property(tpt.SSNG.elem, "Description", ELEM_DESC)
	elem.property(tpt.SSNG.elem, "Color", ELEM_MCOLOR)
	elem.property(tpt.SSNG.elem, "Graphics", function(i)
		sim.partChangeType(i, elem.DEFAULT_PT_SNOW)
		configure(i)
	end)
end
