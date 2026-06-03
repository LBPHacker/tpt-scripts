local SPACING = 6
local BUBBLES = true
local CALLBACK

local distance

local lastID, firstID
local button1_state = false

if tpt.SPWR then
	pcall(event.unregister, event.mousedown, tpt.SPWR.mousedown)
	pcall(event.unregister, event.mouseup, tpt.SPWR.mouseup)
end
tpt.SPWR = tpt.SPWR or {}
setmetatable(tpt.SPWR, {__index = function(tbl, key)
	if key == "callback" then
		return CALLBACK
	end
	if key == "spacing" then
		return SPACING
	end
	if key == "bubbles" then
		return BUBBLES
	end
end, __newindex = function(tbl, key, value)
	if key == "spacing" then
		if type(value) ~= "number" then
			print("spacing should be an integer, ignoring")
			return
		end
		if value ~= math.floor(value) then
			value = math.floor(value)
			print("spacing should be an integer, truncating to " .. value)
		end
		SPACING = value
		return
	end
	if key == "bubbles" then
		BUBBLES = value and true or false
		return
	end
	if key == "callback" then
		CALLBACK = value
		return
	end
	rawset(tbl, key, value)
end})
function tpt.SPWR.mousedown(mousexU, mouseyU, button)
	if button == 1 then
		button1_state = true
		distance = 0
	end
end
function tpt.SPWR.mouseup(mousexU, mouseyU, button)
	if button == 1 then
		button1_state = false
		if BUBBLES and lastID then
			for i in sim.neighbours(sim.partProperty(lastID, "x"), sim.partProperty(lastID, "y"), 6, 6) do
				if i == firstID then
					sim.partProperty(lastID, "tmp", firstID)
					local nextID = lastID
					repeat
						local otherID = sim.partProperty(nextID, "tmp")
						sim.partProperty(otherID, "ctype", 7)
						sim.partProperty(otherID, "tmp2", nextID)
						nextID = otherID
					until nextID == lastID
				end
			end
		end
		lastID = nil
	end
end
event.register(event.mousedown, tpt.SPWR.mousedown)
event.register(event.mouseup, tpt.SPWR.mouseup)

local function configure(i)
	if not button1_state then
		sim.partKill(i)
		return
	end
	distance = distance + 1
	if distance >= (type(SPACING) == "number" and SPACING or 6) then
		distance = 0
	else
		sim.partKill(i)
		return
	end
	sim.partChangeType(i, elem.DEFAULT_PT_SOAP)
	sim.partProperty(i, "life", 65535)
	sim.partProperty(i, "tmp2", 72456)
	sim.partProperty(i, "ctype", 55)
	if lastID then
		sim.partProperty(i, "tmp", lastID)
		sim.partProperty(lastID, "tmp", i)
	else
		firstID = i
		sim.partProperty(i, "tmp", i)
	end
	lastID = i
	if CALLBACK then
		local ok, err = pcall(CALLBACK, i)
		if not ok then
			print("tpt.SPWR.callback: " .. err)
		end
	end
end

pcall(elem.free, tpt.SPWR.elem)
if tools then
	pcall(tools.free, tpt.SPWR.tool)
end

local ELEM_GROUP  = "lbphacker"
local ELEM_NAME   = "soapworm"
local ELEM_MNAME  = "SPWR"
local ELEM_DESC   = [["Soapworm". Creates a continuous line of SOAP.]]
local ELEM_MCOLOR = 0xF5F5DC

if tools then
	tpt.SPWR.tool = tools.allocate(ELEM_GROUP, ELEM_NAME)
	tools.property(tpt.SPWR.tool, "Name", ELEM_MNAME)
	tools.property(tpt.SPWR.tool, "Description", ELEM_DESC)
	tools.property(tpt.SPWR.tool, "Color", ELEM_MCOLOR)
	tools.property(tpt.SPWR.tool, "Perform", function(i, x, y, strength, shift, ctrl, alt, bx, by)
		local i = sim.partCreate(-2, x, y, elem.DEFAULT_PT_SOAP)
		if i ~= -1 then
			configure(i)
		end
	end)
else
	tpt.SPWR.elem = elem.allocate(ELEM_GROUP, ELEM_NAME)
	elem.element(tpt.SPWR.elem, elem.element(elem.DEFAULT_PT_SOAP))
	elem.property(tpt.SPWR.elem, "Name", ELEM_MNAME)
	elem.property(tpt.SPWR.elem, "Description", ELEM_DESC)
	elem.property(tpt.SPWR.elem, "Color", ELEM_MCOLOR)
	elem.property(tpt.SPWR.elem, "Graphics", configure)
end
