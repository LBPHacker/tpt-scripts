-- * Set this to false unless you're me
local USE_LBPHACKERS_CONFIG = tpt.get_name() == "LBPHacker"

-- * You'll have to manually the config below unless you're using
--   a script manager that exposes MANAGER.getsetting. In that
--   case, you'll have to edit the manager config.

local DEFAULTS = {
	-- * set this to true if you want the plugin to listen only to
	--   Ctrl+Shift+C/X/V events and nothing else
	--     * built-in copy/cut/paste functionality assigned to Ctrl+C/X/V only
	-- * set this to false if you want the plugin to listen only to
	--   Ctrl+C/X/V events and nothing else
	--     * built-in copy/cut/paste functionality assigned to Ctrl+Shift+C/X/V only
	combo_has_shift = true,
	
	-- * set this to true to disable layering when pasting with the left mouse button
	-- * set this to false to disable layering when pasting with the middle mouse button
	layering_has_middle = true,
	
	-- * set this to true to enable warning about ID order not being preserved
	id_order_warning = false,
	
	-- * set this to some unique string you won't likely get on your clipboard
	clipboard_header = "@TPT_BCCP_CLIPBOARD_DATA"
}

-- * Beware, I hate walls and usually build subframe stuff.
if USE_LBPHACKERS_CONFIG then -- * my setup
	DEFAULTS.combo_has_shift = false
	DEFAULTS.layering_has_middle = false
	DEFAULTS.id_order_warning = true
end

local BCCP_MANAGER_NAMESPACE = "bccp"

local PROPERTIES = {}
for key, value in pairs(sim) do
	if key:find("^FIELD_") and key ~= "FIELD_X" and key ~= "FIELD_Y" then
		PROPERTIES[value] = true
	end
end

local corners, pasted_mouseoffs
local pasted_parts, pasted_parts_ordered
local pasted_size = {}
local doing_copy, doing_paste = false, false
local do_cut
local old_pause, pasted_pause
local fake_boost_module = {}
local bottomleft_text, bottomleft_text_timeout
local pasted_layering
local doing_copy_button_1_down = false

local function sanitize()
	return math.min(corners.x1, corners.x2),
	       math.min(corners.y1, corners.y2),
	       math.max(corners.x1, corners.x2),
	       math.max(corners.y1, corners.y2)
end

local function copy_begin()
	if tpt.boost then
		tpt.boost.lock(fake_boost_module)
	end
	old_pause = tpt.set_pause()
	tpt.set_pause(1)
	if do_cut then
		bottomleft_text = "Click-and-drag to specify an area to copy then cut (right click = cancel)"
	else
		bottomleft_text = "Click-and-drag to specify an area to copy (right click = cancel)"
	end
	corners = {
		x1 = -1,
		y1 = -1,
		x2 = -1,
		y2 = -1
	}
	doing_copy = true
end

local function copy_end()
	doing_copy = false
	corners = nil
	bottomleft_text_timeout = 120
	tpt.set_pause(old_pause)
	if tpt.boost then
		tpt.boost.unlock()
	end
end

local function paste_rotate()
	local width = pasted_size.x
	pasted_size.x, pasted_size.y = pasted_size.y, pasted_size.x
	for key, value in pairs(pasted_parts) do
		value.x, value.y = value.y, width - value.x - 1
	end
end

local function paste_flip()
	local width = pasted_size.x
	for key, value in pairs(pasted_parts) do
		value.x = width - value.x
	end
end

local function paste_update_coords()
	local x, y = sim.adjustCoords(tpt.mousex, tpt.mousey)
	corners.x1 = pasted_mouseoffs.x + math.floor((x - math.floor(pasted_size.x / 2)) / 4) * 4
	corners.y1 = pasted_mouseoffs.y + math.floor((y - math.floor(pasted_size.y / 2)) / 4) * 4
	corners.x2 = corners.x1 + pasted_size.x - 1
	corners.y2 = corners.y1 + pasted_size.y - 1
	for key, value in pairs(pasted_parts) do
		sim.partPosition(key, corners.x1 + value.x, corners.y1 + value.y)
	end
end

local function paste_kill_layers()
	for key, value in pairs(pasted_parts) do
		sim.partPosition(key, -1, -1)
	end
	local lx, ly, hx, hy = sanitize()
	local rows = {}
	for iy = ly, hy do
		rows[iy] = {}
	end
	for key = 1, #pasted_parts_ordered do
		local value = pasted_parts_ordered[key]
		local id_under = rows[ly + value.fy][lx + value.fx]
		if id_under then
			sim.partKill(id_under)
		end
		sim.partPosition(value.id, lx + value.x, ly + value.y)
		rows[ly + value.fy][lx + value.fx] = value.id
	end
	-- * sim.partID is useless in this case.
	--   Setting the position of a particle is only visible in the next frame.
	--   This means I must bruteforce my way through all particles to get
	--   reliable info about layers.
	for partID in sim.parts() do if not pasted_parts[partID] then
		local x, y = sim.partPosition(partID)
		x, y = math.floor(x + 0.5), math.floor(y + 0.5)
		if x >= lx and x <= hx and y >= ly and y <= hy and rows[y][x] then
			sim.partKill(partID)
		end
	end end
end

local function paste_begin()
	local clipboard_data = tpt.get_clipboard()
	local iterator = clipboard_data:gmatch("[^,]+")
	if iterator() ~= tpt.bccp.clipboard_header then
		print("No valid data on the clipboard")
		return
	end
	local num_new_parts = tonumber(iterator())
	pasted_pause = tonumber(iterator())
	if tpt.ambient_heat() ~= tonumber(iterator()) then
		print("Ambient heat setting mismatch")
		return
	end
	if tpt.heat() ~= tonumber(iterator()) then
		print("Heat setting mismatch")
		return
	end
	if (num_new_parts + tpt.get_numOfParts()) > (sim.XRES * sim.YRES) then
		print("Too many particles on the clipboard")
		return
	end
	local new_ids = {}
	for ix = 1, num_new_parts do
		new_ids[sim.partCreate(-3, 0, 0, 26)] = true
	end
	
	if tpt.boost then
		tpt.boost.lock(fake_boost_module)
	end
	old_pause = tpt.set_pause()
	tpt.set_pause(1)
	pasted_size.x = tonumber(iterator())
	pasted_size.y = tonumber(iterator())
	local xoff, yoff = tonumber(iterator()), tonumber(iterator())
	
	local lastID = -1
	local id_warning
	local prop_key, part_x, part_y
	local new_id_counter = 0
	pasted_parts, pasted_parts_ordered = {}, {}
	for word in iterator do -- process the rest
		if word == "@" then
			part_x, part_y = nil, nil
		elseif not part_x then
			part_x = tonumber(word)
		elseif not part_y then
			part_y = tonumber(word)
			local newID
			while not newID do
				newID = new_ids[new_id_counter] and new_id_counter
				new_id_counter = new_id_counter + 1
			end
			if newID < lastID then
				id_warning = true
			end
			lastID = newID
			local part = {
				id = newID,
				x = part_x,
				y = part_y,
				fx = math.floor(part_x + 0.5),
				fy = math.floor(part_y + 0.5)
			}
			pasted_parts[newID] = part
			table.insert(pasted_parts_ordered, part)
		else
			if prop_key then
				if PROPERTIES[prop_key] then
					sim.partProperty(lastID, prop_key, tonumber(word))
				end
				prop_key = nil
			else
				prop_key = tonumber(word)
			end
		end
	end
	if tpt.bccp.id_order_warning and id_warning then
		print("SANITY CHECK FAILURE: ID order not preserved")
	end
	
	pasted_rotation = 0
	pasted_flip = false
	pasted_mouseoffs = {
		x = xoff,
		y = yoff
	}
	corners = {}
	paste_update_coords()
	
	doing_paste = true
end

local function paste_end()
	doing_paste = false
	pasted_parts = nil
	corners = nil
	tpt.set_pause(old_pause)
	if tpt.boost then
		tpt.boost.unlock()
	end
end

if tpt.bccp then
	pcall(event.unregister, event.mousedown, tpt.bccp.mousedown)
	pcall(event.unregister, event.mousemove, tpt.bccp.mousemove)
	pcall(event.unregister, event.mouseup, tpt.bccp.mouseup)
	pcall(event.unregister, event.keypress, tpt.bccp.keypress)
	pcall(event.unregister, event.tick, tpt.bccp.tick)
end
tpt.bccp = tpt.bccp or {}
for key, value in pairs(DEFAULTS) do
	tpt.bccp[key] = MANAGER and MANAGER.getsetting(BCCP_MANAGER_NAMESPACE, key) or value
end
if MANAGER then
	for key, value in pairs(DEFAULTS) do
		MANAGER.savesetting(BCCP_MANAGER_NAMESPACE, tpt.bccp[key], value)
	end
end

function tpt.bccp.mousedown(ux, uy, button)
	local x, y = sim.adjustCoords(ux, uy)
	if doing_copy then
		if button == 1 then
			doing_copy_button_1_down = true
			corners.x1 = x
			corners.y1 = y
			corners.x2 = x
			corners.y2 = y
		elseif button == 4 then
			copy_end()
		end
		return false
	elseif doing_paste then
		return false
	end
end

function tpt.bccp.mousemove(ux, uy)
	if doing_copy_button_1_down then
		corners.x2, corners.y2 = sim.adjustCoords(ux, uy)
	end
end

function tpt.bccp.mouseup(ux, uy, button)
	local x, y = sim.adjustCoords(ux, uy)
	if doing_copy then
		if button == 1 then
			doing_copy_button_1_down = false
			corners.x2 = x
			corners.y2 = y
			local lx, ly, hx, hy = sanitize()
			local lxa, lya = math.floor(lx / 4) * 4, math.floor(ly / 4) * 4
			local rows = {}
			local parts_to_copy = 0
			for partID in sim.parts() do
				local px, py = sim.partPosition(partID)
				px = math.floor(px + 0.5)
				py = math.floor(py + 0.5)
				if px >= lx and px <= hx and py >= ly and py <= hy then
					rows[py] = rows[py] or {}
					rows[py][px] = rows[py][px] or {}
					table.insert(rows[py][px], partID)
					parts_to_copy = parts_to_copy + 1
				end
			end
			local clipboard_data = {
				tpt.bccp.clipboard_header,
				parts_to_copy,
				old_pause,
				tpt.ambient_heat(),
				tpt.heat(),
				hx - lx + 1,
				hy - ly + 1,
				lx - lxa,
				ly - lya
			}
			for iy = ly, hy do
				local row = rows[iy]
				if row then for ix = lx, hx do
					local stack = row[ix]
					if stack then for is = 1, #stack do
						local partID = stack[is]
						local px, py = sim.partPosition(partID)
						px, py = math.floor(px + 0.5), math.floor(py + 0.5)
						table.insert(clipboard_data, "@")
						table.insert(clipboard_data, px - lx)
						table.insert(clipboard_data, py - ly)
						for key in pairs(PROPERTIES) do
							table.insert(clipboard_data, key)
							table.insert(clipboard_data, sim.partProperty(partID, key))
						end
						if do_cut then
							sim.partKill(partID)
						end
					end end
				end end
			end
			tpt.set_clipboard(table.concat(clipboard_data, ","))
			copy_end()
		end
		return false
	elseif doing_paste then
		if button == 1 then
			old_pause = (pasted_pause == 1 or old_pause == 1) and 1 or 0
			if tpt.bccp.layering_has_middle then
				paste_kill_layers()
			end
			paste_end()
		elseif button == 2 then
			old_pause = (pasted_pause == 1 or old_pause == 1) and 1 or 0
			if not tpt.bccp.layering_has_middle then
				paste_kill_layers()
			end
			paste_end()
		elseif button == 4 then
			for key in pairs(pasted_parts) do
				sim.partKill(key)
			end
			paste_end()
		end
		return false
	end
end

function tpt.bccp.keypress(key, scan, rep, shift, ctrl, alt)
	local combo_check
	if tpt.bccp.combo_has_shift then
		combo_check = shift and ctrl and not alt
	else
		combo_check = not shift and ctrl and not alt
	end
	if not doing_copy and not doing_paste and combo_check and (not tpt.boost or not tpt.boost.lock_on) then
		if scan == 6 or scan == 27 then
			do_cut = scan == 27
			copy_begin()
			return false
		elseif scan == 25 then
			if not pcall(paste_begin) then
				if pasted_parts then
					for key in pairs(pasted_parts) do
						sim.partKill(key)
					end
				end
				paste_end()
				print("Corrupted data on the clipboard")
			end
			return false
		end
	end
	if doing_paste then
		if not shift and not ctrl and not alt then
			if scan == 44 then
				return false
			elseif scan == 21 then
				paste_rotate()
				paste_update_coords()
				return false
			elseif scan == 82 then
				pasted_mouseoffs.y = pasted_mouseoffs.y - 1
				paste_update_coords()
				return false
			elseif scan == 81 then
				pasted_mouseoffs.y = pasted_mouseoffs.y + 1
				paste_update_coords()
				return false
			elseif scan == 79 then
				pasted_mouseoffs.x = pasted_mouseoffs.x + 1
				paste_update_coords()
				return false
			elseif scan == 80 then
				pasted_mouseoffs.x = pasted_mouseoffs.x - 1
				paste_update_coords()
				return false
			end
		elseif shift and not ctrl and not alt then
			if scan == 21 then
				paste_flip()
				paste_update_coords()
				return false
			end
		end
	end
end

function tpt.bccp.tick()
	if doing_paste then
		paste_update_coords()
	end
	if corners then
		local lx, ly, hx, hy = sanitize()
		gfx.fillRect( 0,  0,      gfx.WIDTH,              ly, 0, 0, 0, 100)
		gfx.fillRect( 0, hy,      gfx.WIDTH, gfx.HEIGHT - hy, 0, 0, 0, 100)
		gfx.fillRect( 0, ly,             lx,         hy - ly, 0, 0, 0, 100)
		gfx.fillRect(hx, ly, gfx.WIDTH - hx,         hy - ly, 0, 0, 0, 100)
		gfx.drawLine(lx, ly, hx, ly)
		gfx.drawLine(lx, hy, hx, hy)
		gfx.drawLine(lx, ly, lx, hy)
		gfx.drawLine(hx, ly, hx, hy)
	end
	if bottomleft_text then
		if bottomleft_text_timeout then
			bottomleft_text_timeout = bottomleft_text_timeout - 1
		end
		gfx.drawText(16, 360, bottomleft_text, 239, 239, 16, bottomleft_text_timeout and math.min(bottomleft_text_timeout * 5, 255) or 255)
		if bottomleft_text_timeout == 0 then
			bottomleft_text_timeout = nil
			bottomleft_text = nil
		end
	end
end

event.register(event.mousedown, tpt.bccp.mousedown)
event.register(event.mousemove, tpt.bccp.mousemove)
event.register(event.mouseup, tpt.bccp.mouseup)
event.register(event.keypress, tpt.bccp.keypress)
event.register(event.tick, tpt.bccp.tick)
