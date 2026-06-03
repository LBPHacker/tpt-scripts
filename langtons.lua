-- * Langton's Ant with variations
-- * 2016, LBPHacker

-- * The script is portable and uses no hooks.
-- * Use tpt.LANGTONSANT.addType to define new types of ants,
--   see at the bottom of the script.
-- * LA[number] elements are placed in the Game Of Life section.
-- * The ants leave coloured DMND behind. The ctype of the DMND is
--   set to the type of the ant that created it.
-- * The ants themselves are white, their tmp shows their age.
-- * Every type of ant has its own colour. Cells retain a shade
--   of the colour of the ant that created them. The first letters
--   of the rule leave the darkest cells behind, the last letters
--   are responsible for the brightest ones.

local types = {}
local turns = {
	["N"] = 0,
	["L"] = 1,
	["U"] = 2,
	["R"] = 3
}
local directions = {
	[0] = {x =  1, y =  0},
	[1] = {x =  0, y = -1},
	[2] = {x = -1, y =  0},
	[3] = {x =  0, y =  1}
}

local function hue2rgb(hue)
	hue = hue % 6
	if hue > 5 then return 255, 0, 255 * (1 - (hue - 5)) end
	if hue > 4 then return 255 *      (hue - 4) , 0, 255 end
	if hue > 3 then return 0, 255 * (1 - (hue - 3)), 255 end
	if hue > 2 then return 0, 255, 255 *      (hue - 2)  end
	if hue > 1 then return 255 * (1 - (hue - 1)), 255, 0 end
	                return 255, 255 *       hue      , 0
end

local function funcUpdate(partID, px, py)
	if sim.partProperty(partID, "life") == 1 then
		local age = sim.partProperty(partID, "tmp")
		local my_type = sim.partProperty(partID, "type")
		local my_type_def = types[my_type]
		local turn_index = sim.partProperty(partID, "ctype")
		local new_turn_index = (turn_index + 1) % my_type_def.rules_length

		local facing = sim.partProperty(partID, "tmp2")
		local turn_id = my_type_def.rules:sub(turn_index + 1, turn_index + 1)
		if turn_id == "" then
			sim.partKill(partID)
			return -- two ants collided or something
		end
		local new_facing = (facing + turns[turn_id]) % 4
		local new_px = px + directions[new_facing].x
		local new_py = py + directions[new_facing].y

		local new_ant_id = sim.partID(new_px, new_py)
		local old_turn_index = 0
		if new_ant_id then
			old_turn_index = sim.partProperty(new_ant_id, "tmp")
			sim.partKill(new_ant_id)
		end
		new_ant_id = sim.partCreate(-2, new_px, new_py, my_type)
		sim.partProperty(new_ant_id, "life", 2)
		sim.partProperty(new_ant_id, "tmp", age + 1)
		sim.partProperty(new_ant_id, "ctype", old_turn_index)
		sim.partProperty(new_ant_id, "tmp2", new_facing)

		sim.partKill(partID)
		local new_me = sim.partCreate(-2, px, py, elem.DEFAULT_PT_DMND)
		local fac = new_turn_index / (my_type_def.rules_length - 1)
		sim.partProperty(new_me, "dcolour", 0xFF000000 +
			math.floor(my_type_def.cr * fac) * 0x10000 +
			math.floor(my_type_def.cg * fac) * 0x100 +
			math.floor(my_type_def.cb * fac)
		)
		sim.partProperty(new_me, "tmp", new_turn_index)
		sim.partProperty(new_me, "ctype", my_type)
	end
end

local function funcGraphics(partID)
	-- the graphics func can be used as a constructor
	if sim.partProperty(partID, "tmp") == 0 then
		sim.partProperty(partID, "life", 2)
	end
	return 0, ren.PMODE_FLAT, 255, 255, 255, 255, 0, 0, 0, 0
end

if tpt.LANGTONSANT then
	pcall(event.unregister, event.tick, tpt.LANGTONSANT.tick)
	for key in pairs(tpt.LANGTONSANT.types or {}) do
		pcall(elem.free, key)
	end
end
tpt.LANGTONSANT = {}
local counter = 0
local addType
local last_selectedl = tpt.selectedl
function tpt.LANGTONSANT.tick()
	if tpt.selectedl == "LBPHACKER_PT_LANGTONSANTADD" then
		local ruleset = tpt.input("Add Langton's Ant variant", "Enter ruleset for LA" .. (counter + 1))
		if ruleset ~= "" and addType(ruleset) then
			tpt.selectedl = "LBPHACKER_PT_LANGTONSANT" .. (counter - 1)
		else
			tpt.selectedl = last_selectedl
		end
	end
	last_selectedl = tpt.selectedl
end
tpt.LANGTONSANT.types = types
event.register(event.tick, tpt.LANGTONSANT.tick)

function addType(rules, desc)
	if type(desc) ~= "string" then
		desc = "Langton's Ant"
	end
	if type(rules) ~= "string" then
		print("String expected for rules")
		return
	end
	rules = rules:upper()
	for letter in rules:gmatch(".") do
		if not turns[letter] then
			print("'" .. letter .. "' is not a valid direction")
			return
		end
	end
	if #rules == 0 then
		print("Empty rules")
		return
	end
	local elementID = elem.allocate("lbphacker", "langtonsant" .. (counter + 1))
	if elementID == -1 then
		print("Out of element identifiers")
		return
	end
	local cr, cg, cb = hue2rgb(counter * 1.7834654)
	counter = counter + 1
	types[elementID] = {
		rules = rules,
		rules_length = #rules,
		cr = cr,
		cg = cg,
		cb = cb
	}
	elem.element(elementID, elem.element(elem.DEFAULT_PT_DMND))
	elem.property(elementID, "Name", "LA" .. counter)
	elem.property(elementID, "Description", desc .. " (#" .. counter .. ", " .. rules .. ")")
	elem.property(elementID, "MenuSection", elem.SC_LIFE)
	elem.property(elementID, "Properties", bit.bor(elem.property(elementID, "Properties"), elem.PROP_LIFE_DEC))
	elem.property(elementID, "Update", funcUpdate)
	elem.property(elementID, "Graphics", funcGraphics)
	elem.property(elementID, "Color", math.floor(cr) * 0x10000 + math.floor(cg) * 0x100 + math.floor(cb))

	return true
end

function tpt.LANGTONSANT.addType(rules, desc)
	if addType(rules, desc) then
		print("Created element 'LA" .. counter .. "'")
	end
end

local la_plus = elem.allocate("lbphacker", "langtonsantadd")
elem.element(la_plus, elem.element(elem.DEFAULT_PT_DMND))
elem.property(la_plus, "Name", "LA+")
elem.property(la_plus, "Description", "Select to add a Langton's Ant variant")
elem.property(la_plus, "MenuSection", elem.SC_LIFE)
elem.property(la_plus, "Color", 0x7F7F7F)

-- * These are from https://en.wikipedia.org/wiki/Langton%27s_ant
-- * L (left), R (right), U (U-turn) and N (nothing) are supported.
-- * addType is used instead of tpt.LANGTONSANT.addType so the screen
--   isn't cluttered with "Created element 'LA1..6'" on startup.
addType("RL", "Original Langton's Ant")
addType("RLR")
addType("LLRR")
addType("LRRRRRLLR")
addType("LLRRRLRLRLLR")
addType("RRLLLRLLLRRR")
