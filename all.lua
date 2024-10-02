local xy_properties = {}
for _, name in pairs({ "x", "y" }) do
    xy_properties[name] = true
    xy_properties[sim["FIELD_" .. name:upper()]] = true
end
local float_properties = {}
for _, name in pairs({ "x", "y", "vx", "vx", "temp" }) do
    float_properties[name] = true
    float_properties[sim["FIELD_" .. name:upper()]] = true
end
local default_epsilon = 1e-3

local function round(a)
    return math.floor(a + 0.5)
end

local element_name_cache = {}
local function rebuild_element_name_cache()
    element_name_cache = {}
    for long_name, element_id in pairs(elem) do
        if type(long_name) == "string" and long_name:find("_PT_") then
            local ok, display_name = pcall(elem.property, element_id, "Name")
            if ok then
                element_name_cache[display_name:upper()] = element_id
            end
        end
    end
end

local function prop_value_smart(property_value)
    if type(property_value) == "string" then
        do -- * It may be a temperature value. Chicken wings, anyone?
            local num, kfc = property_value:upper():match("^(.+)([KFC])$")
            if num then
                num = tonumber(num)
            end
            if num then
                if kfc == "F" then
                    num = (num - 32) / 1.8
                    kfc = "C"
                end
                if kfc == "C" then
                    num = num + 273.15
                end
                return num
            end
        end
        do -- * It may be an element name.
            local upper = property_value:upper()
            local elementID = element_name_cache[upper]
            local ok, display_name = pcall(elem.property, elementID, "Name")
            if not ok or display_name:upper() ~= upper then
                rebuild_element_name_cache()
                elementID = element_name_cache[upper]
            end
            if elementID then
                return elementID
            end
        end
        do -- * It may be a # colour code.
            local lower = property_value:lower()
            local code = lower:match("^#([a-f%d][a-f%d][a-f%d][a-f%d][a-f%d][a-f%d])$")
            if not code then
                code = lower:match("^#([a-f%d][a-f%d][a-f%d])$")
                if code then
                    code = code:sub(1, 1):rep(2) .. code:sub(2, 2):rep(2) .. code:sub(3, 3):rep(2)
                end
            end
            if code then
                return tonumber("0xFF" .. code)
            end
        end
        do -- * It may be a number in string form.
            local num = tonumber(property_value)
            if num then
                return num
            end
        end
    end
    return property_value
end

local function prop_value(property_value)
    property_value = prop_value_smart(property_value)
    if type(property_value) ~= "number" then
        error("invalid property value")
    end
    return property_value
end

local function prop_value_func(property_value)
    return type(property_value) == "function" and property_value or prop_value(property_value)
end

local particle_proxy_m = {}

function particle_proxy_m:__index(property_key)
    return sim.partProperty(self.id, property_key)
end

function particle_proxy_m:__newindex(property_key, property_value)
    return sim.partProperty(self.id, property_key, prop_value(property_value))
end

local weak_proxy_store = setmetatable({}, { __mode = "v" })
local function make_particle_proxy(id)
    local grab_proxy = weak_proxy_store[id]
    if grab_proxy then
        return grab_proxy
    end
    local new_proxy = setmetatable({ id = id }, particle_proxy_m)
    weak_proxy_store[id] = new_proxy
    return new_proxy
end

local make_particle_set

local particle_set_i = {}
local particle_set_m = {}

function particle_set_m:__index(key)
    if type(key) == "number" then
        return self:range(key, key)
    else
        return particle_set_i[key]
    end
end

function particle_set_m:__add(other)
    local result = make_particle_set()
    for id in self:iterate() do
        result:insert(id)
    end
    for id in other:iterate() do
        result:insert(id)
    end
    return result
end

function particle_set_m:__sub(other)
    local result = make_particle_set()
    for id in self:iterate() do
        result:insert(id)
    end
    for id in other:iterate() do
        result:remove(id)
    end
    return result
end

function particle_set_m:__mul(other)
    local result = make_particle_set()
    for id in self:iterate() do
        result:insert(id)
    end
    for id in (tpt.all() - other):iterate() do
        result:remove(id)
    end
    return result
end

function particle_set_m:__eq(other)
    if self:count() ~= other:count() then
        return false
    end
    for id in self:iterate() do
        if not other:has(id) then
            return false
        end
    end
    return true
end

function particle_set_m:__lt(other)
    for id in self:iterate() do
        if not other:has(id) then
            return false
        end
    end
    for id in other:iterate() do
        if not self:has(id) then
            return true
        end
    end
    return false
end

function particle_set_m:__le(other)
    for id in self:iterate() do
        if not other:has(id) then
            return false
        end
    end
    for id in other:iterate() do
        if not self:has(id) then
            return true
        end
    end
    return true
end

function particle_set_m:__tostring()
    return tostring(self:count())
end

function particle_set_i:next(current_id)
    local next_id, next_proxy = next(self.particle_assoc, current_id)
    if not next_id then
        return
    end
    return next_id, next_proxy
end

function particle_set_i:iterate()
    return self.next, self
end

function particle_set_i:bbox(x1, y1, x2, y2, eyeball_xy)
    return self:gte("x", x1, eyeball_xy):gte("y", y1, eyeball_xy):lt("x", x2, eyeball_xy):lt("y", y2, eyeball_xy)
end

function particle_set_i:cursor(width, height, eyeball_xy)
    local x, y = sim.adjustCoords(tpt.mousex, tpt.mousey)
    return self:bbox(x, y, x + width, y + height, eyeball_xy)
end

function particle_set_i:filter(func, ...)
    local result = make_particle_set()
    for id, proxy in self:iterate() do
        if func(proxy, ...) then
            result:insert(id)
        end
    end
    return result
end

function particle_set_i:clone()
    return self:filter(function()
        return true
    end)
end

function particle_set_i:eq(property_key, property_value, eyeball_xy, epsilon)
    property_value = prop_value(property_value)
    if float_properties[property_key] then
        epsilon = epsilon or default_epsilon
        if eyeball_xy and xy_properties[property_key] then
            return self:filter(function(proxy)
                return round(proxy[property_key]) == property_value
            end)
        else
            return self:filter(function(proxy)
                return math.abs(proxy[property_key] - property_value) < epsilon
            end)
        end
    else
        return self:filter(function(proxy)
            return proxy[property_key] == property_value
        end)
    end
end

function particle_set_i:neq(property_key, property_value, eyeball_xy, epsilon)
    property_value = prop_value(property_value)
    if float_properties[property_key] then
        epsilon = epsilon or default_epsilon
        if eyeball_xy and xy_properties[property_key] then
            return self:filter(function(proxy)
                return round(proxy[property_key]) ~= property_value
            end)
        else
            return self:filter(function(proxy)
                return math.abs(proxy[property_key] - property_value) >= epsilon
            end)
        end
    else
        return self:filter(function(proxy)
            return proxy[property_key] ~= property_value
        end)
    end
end

function particle_set_i:gt(property_key, property_value, eyeball_xy)
    property_value = prop_value(property_value)
    if eyeball_xy and xy_properties[property_key] then
        return self:filter(function(proxy)
            return round(proxy[property_key]) > property_value
        end)
    else
        return self:filter(function(proxy)
            return proxy[property_key] > property_value
        end)
    end
end

function particle_set_i:gte(property_key, property_value, eyeball_xy)
    property_value = prop_value(property_value)
    if eyeball_xy and xy_properties[property_key] then
        return self:filter(function(proxy)
            return round(proxy[property_key]) >= property_value
        end)
    else
        return self:filter(function(proxy)
            return proxy[property_key] >= property_value
        end)
    end
end

function particle_set_i:lt(property_key, property_value, eyeball_xy)
    property_value = prop_value(property_value)
    if eyeball_xy and xy_properties[property_key] then
        return self:filter(function(proxy)
            return round(proxy[property_key]) < property_value
        end)
    else
        return self:filter(function(proxy)
            return proxy[property_key] < property_value
        end)
    end
end

function particle_set_i:lte(property_key, property_value, eyeball_xy)
    property_value = prop_value(property_value)
    if eyeball_xy and xy_properties[property_key] then
        return self:filter(function(proxy)
            return round(proxy[property_key]) <= property_value
        end)
    else
        return self:filter(function(proxy)
            return proxy[property_key] <= property_value
        end)
    end
end

function particle_set_i:each(func, ...)
    for id, proxy in self:iterate() do
        func(proxy, ...)
    end
    return self
end

function particle_set_i:top()
    local new_ids = {}
    for id in self:iterate() do
        table.insert(new_ids, sim.partID(sim.partPosition(id)))
    end
    return tpt.all(new_ids)
end

function particle_set_i:range(first, last)
    local count = self:count()
    first = first or 1
    last = last or count
    if first < 0 then
        first = count + first + 1
    end
    if last < 0 then
        last = count + last + 1
    end
    local ordered = {}
    for id in self:iterate() do
        table.insert(ordered, id)
    end
    table.sort(ordered)
    local new_ids = {}
    for ix = first, last do
        table.insert(new_ids, ordered[ix])
    end
    return tpt.all(new_ids)
end

function particle_set_i:set(property_key, property_value)
    property_value = prop_value_func(property_value)
    for id, proxy in self:iterate() do
        if type(property_value) == "function" then
            proxy[property_key] = property_value(proxy)
        else
            proxy[property_key] = property_value
        end
    end
    return self
end

function particle_set_i:add(property_key, property_value)
    property_value = prop_value_func(property_value)
    for id, proxy in self:iterate() do
        if type(property_value) == "function" then
            proxy[property_key] = proxy[property_key] + property_value(proxy)
        else
            proxy[property_key] = proxy[property_key] + property_value
        end
    end
    return self
end

function particle_set_i:randomise(property_key, property_values)
    local pv_size = #property_values
    for ix = 1, pv_size do
        property_values[ix] = prop_value_func(property_values[ix])
    end
    for id, proxy in self:iterate() do
        local property_value = property_values[math.random(1, pv_size)]
        if type(property_value) == "function" then
            proxy[property_key] = property_value(proxy)
        else
            proxy[property_key] = property_value
        end
    end
    return self
end

function particle_set_i:rotate(angle, xcenter, ycenter)
    angle = (angle + 180) % 360 - 180
    do
        local x1, y1, x2, y2 = self:get_bbox(true)
        if not xcenter then
            xcenter = round((x1 + x2) / 2)
        end
        if not ycenter then
            ycenter = round((y1 + y2) / 2)
        end
    end
    local do180 = false
    if angle < -90 then
        angle = angle + 180
        do180 = true
    elseif angle > 90 then
        angle = angle - 180
        do180 = true
    end
    local rangle = math.rad(angle)
    local xf = -math.tan(rangle / 2)
    local yf = math.sin(rangle)
    for id, proxy in self:iterate() do
        local x0 = round(proxy.x)
        local y0 = round(proxy.y)
        if do180 then
            x0 = 2 * xcenter - x0
            y0 = 2 * ycenter - y0
        end
        local x1 = x0 + round(xf * (y0 - ycenter))
        local y1 = y0 + round(yf * (x1 - xcenter))
        local x2 = x1 + round(xf * (y1 - ycenter))
        proxy.x = x2
        if sim.partExists(id) then
            proxy.y = y1
        end
    end
end

local field_type = sim.FIELD_TYPE
local field_x = sim.FIELD_X
local field_y = sim.FIELD_Y
local fields = {}
for key, value in pairs(sim) do
    if key:find("^FIELD_") then
        fields[value] = true
    end
end
function particle_set_i:reorder()
    local props = {}
    local ids = {}
    for _, proxy in self:iterate() do
        local part = {
            proxy = proxy,
            x = round(proxy.x),
            y = round(proxy.y),
        }
        for field in pairs(fields) do
            part[field] = proxy[field]
        end
        table.insert(props, part)
        table.insert(ids, proxy)
    end
    table.sort(ids, function(a, b)
        return a.id < b.id
    end)
    table.sort(props, function(a, b)
        if a.y < b.y then return  true end
        if a.y > b.y then return false end
        if a.x < b.x then return  true end
        if a.x > b.x then return false end
        return a.proxy.id < b.proxy.id
    end)
    for ix, part in pairs(props) do
        local proxy = ids[ix]
        proxy[field_type] = part[field_type]
        for field in pairs(fields) do
            if field ~= field_type then
                proxy[field] = part[field]
            end
        end
    end
    return self
end

function particle_set_i:get(property_key)
    local result
    local multiple_values = false
    for id, proxy in self:iterate() do
        local value = proxy[property_key]
        if result then
            if result ~= value then
                multiple_values = true
                break
            end
        else
            result = value
        end
    end
    return not multiple_values and result
end

function particle_set_i:get_bbox(eyeball_xy)
    local x1 = math.huge
    local y1 = math.huge
    local x2 = -math.huge
    local y2 = -math.huge
    for id, proxy in self:iterate() do
        local x, y = proxy.x, proxy.y
        if eyeball_xy then
            x = round(x)
            y = round(y)
        end
        x1 = math.min(x1, x)
        y1 = math.min(y1, y)
        x2 = math.max(x2, x)
        y2 = math.max(y2, y)
    end
    return x1, y1, x2 + 1, y2 + 1
end

function particle_set_i:average(property_key)
    local result = 0
    for id, proxy in self:iterate() do
        result = result + proxy[property_key]
    end
    return result / self.particle_count
end

function particle_set_i:kill()
    return self:each(function(proxy)
        sim.partKill(proxy.id)
    end)
end

function particle_set_i:insert(id)
    if not self.particle_assoc[id] then
        self.particle_assoc[id] = make_particle_proxy(id)
        self.particle_count = self.particle_count + 1
    end
    return self
end

function particle_set_i:remove(id)
    if self.particle_assoc[id] then
        self.particle_assoc[id] = nil
        self.particle_count = self.particle_count - 1
    end
    return self
end

function particle_set_i:has(id)
    return self.particle_assoc[id] and true
end

function particle_set_i:count()
    return self.particle_count
end

function particle_set_i:array()
    local exported = {}
    for id in self:iterate() do
        table.insert(exported, id)
    end
    return exported
end

function particle_set_i:assoc()
    local exported = {}
    for id in self:iterate() do
        exported[id] = true
    end
    return exported
end

local easy_operators = {
    [ "[]" ] = { takes_name = false, takes_value = 4, func = function(set, _, params)
        return set:bbox(params[1], params[2], params[3], params[4])
    end },
    [ "@" ] = { takes_name = false, takes_value = 2, func = function(set, _, params)
        return set:cursor(params[1], params[2])
    end },
    [ "==" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:eq(prop, params[1])
    end },
    [ "!=" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:neq(prop, params[1])
    end },
    [ "<" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:lt(prop, params[1])
    end },
    [ "<=" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:lte(prop, params[1])
    end },
    [ ">" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:gt(prop, params[1])
    end },
    [ ">=" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:gte(prop, params[1])
    end },
    [ "^" ] = { takes_name = false, takes_value = 0, func = function(set, _, _)
        return set:top()
    end },
    [ "=" ] = { takes_name = true, takes_value = nil, func = function(set, prop, params)
        if #params == 1 then
            return set:set(prop, params[1])
        else
            return set:randomise(prop, params)
        end
    end },
    [ "+=" ] = { takes_name = true, takes_value = 1, func = function(set, prop, params)
        return set:add(prop, params[1])
    end },
    [ "?" ] = { takes_name = true, takes_value = 0, func = function(set, prop, _)
        return set:get(prop)
    end },
    [ "?/" ] = { takes_name = true, takes_value = 0, func = function(set, prop, _)
        return set:average(prop)
    end },
    [ "!" ] = { takes_name = false, takes_value = 0, func = function(set, _, _)
        return set:kill()
    end },
    [ "$" ] = { takes_name = false, takes_value = 0, func = function(set, _, _)
        return set:count()
    end },
    [ "*" ] = { takes_name = false, takes_value = 0, func = function(set, _, _)
        return set:reorder()
    end },
}
function particle_set_i:easy(str)
    local counter = 0
    local result = self:clone()
    for word in str:gmatch("%S+") do
        counter = counter + 1
        local prop, op_str, params_str = word:match("^([%a%d]*)([!=<>?/$*+^@]+)([%a%d#.%-,]*)$")
        if not op_str then
            error("#" .. counter .. ": missing operator")
        end
        local op = easy_operators[op_str]
        if not op then
            error("#" .. counter .. ": unknown operator")
        end
        local params = {}
        for param in params_str:gmatch("[^,]+") do
            table.insert(params, prop_value(param))
        end
        if op.takes_value and op.takes_value ~= #params then
            error("#" .. counter .. ": takes " .. op.takes_value .. " values")
        end
        if #prop > 0 and not op.takes_name then
            error("#" .. counter .. ": takes no property")
        end
        if #prop == 0 and op.takes_name then
            error("#" .. counter .. ": needs a property")
        end
        result = op.func(result, prop, params)
    end
    return result
end

function make_particle_set()
    return setmetatable({
        particle_count = 0,
        particle_assoc = {},
    }, particle_set_m)
end

tpt.all = setmetatable({}, { __call = function(self, param, param2)
    if type(param2) == "number" and type(param) == "number" then
        return tpt.all.at(param, param2)
    end
    if param == false then
        return tpt.all.zero()
    elseif type(param) == "number" then
        return tpt.all.one(param)
    elseif type(param) == "string" then
        return tpt.all.easy(param)
    elseif type(param) == "table" then
        return tpt.all.array(param)
    elseif type(param) == "function" then
        return tpt.all.buffer(param)
    end
    local all_particles = make_particle_set()
    for id in sim.parts() do
        all_particles:insert(id)
    end
    return all_particles
end })

function tpt.all.at(x, y)
    local id = sim.partID(x, y)
    return id and tpt.all.one(id) or nil
end

function tpt.all.zero()
    return make_particle_set()
end

function tpt.all.one(id)
    local one_particle = make_particle_set()
    one_particle:insert(id)
    return one_particle
end

function tpt.all.easy(param)
    return tpt.all():easy(param)
end

function tpt.all.proxy(id)
    return make_particle_proxy(id)
end

function tpt.all.array(id_array)
    local all_particles = make_particle_set()
    for ix = 1, #id_array do
        all_particles:insert(id_array[ix])
    end
    return all_particles
end

function tpt.all.buffer(func, ...)
    local all_particles
    local sim_partCreate_original = sim.partCreate
    local ok, err = pcall(function(...)
        local id_buffer = {}
        sim.partCreate = function(...)
            local id = sim_partCreate_original(...)
            if id then
                id_buffer[id] = true
            end
            return id
        end
        func(...)
        all_particles = tpt.all.assoc(id_buffer)
    end, ...)
    sim.partCreate = sim_partCreate_original
    if not ok then
        error(err)
    end
    return all_particles
end

function tpt.all.assoc(id_assoc)
    local all_particles = make_particle_set()
    for id in pairs(id_assoc) do
        all_particles:insert(id)
    end
    return all_particles
end

function tpt.all.fill(particle_type)
    if particle_type then
        particle_type = prop_value(particle_type)
    else
        particle_type = elem.DEFAULT_PT_DMND
    end
    for ix = 0, sim.XRES - 1 do
        for iy = 0, sim.YRES - 1 do
            sim.partCreate(-2, ix, iy, particle_type)
        end
    end
end
