---@diagnostic disable: duplicate-set-field, param-type-mismatch
local op = {}

math.tau = math.pi * 2

math.uuid = function()
    local result = ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(x)
        return ("%x"):format(x == "x" and math.random(0, 0xf) or math.random(8, 0xb))
    end)

    return result
end

math.map = function(value, from_min, from_max, to_min, to_max)
    return (value - from_min) * (to_max - to_min) / (from_max - from_min) + to_min
end

math.clamp = function(value, min, max)
    if value <= min then return min end
    if value >= max then return max end
    return value
end

math.lerp = function(value, to, percent)
    return value + (to - value) * percent
end

math.round = function(value, sigfig)
    local mult = 10 ^ (sigfig or 0)

    return math.floor(value * mult + 0.5) / mult
end

math.between = function(value, a, b)
    return a <= value and value <= b
end

math.cycle = function(value, from, to)
    if math.clamp(value, from, to) == value then return value end

    local dt, res

    dt  = from - 1
    res = (value - dt) % (to - dt)

    return (res == 0 and to or res) + dt
end

os.tz_offset = function(timestamp)
    local utc, here

    timestamp = timestamp or os.time()

    utc  = os.date("!*t", timestamp)
    here = os.date("*t", timestamp)

    here.isdst = false

    ---@diagnostic disable-next-line: param-type-mismatch
    return os.difftime(os.time(here), os.time(utc)) / 3600
end

table.reverse = function(self)
    local n = #self

    for i = 1, n * 0.5 do
        self[i], self[n] = self[n], self[i]
        n = n - 1
    end

    return self
end

table.count = function(self)
    local count = 0

    for _, _ in pairs(self) do count = count + 1 end

    return count
end

table.entries = function(self)
    local result = {}

    for k, v in pairs(self) do
        result[#result + 1] = { k, v }
    end

    return result
end

table.deduplicate = function(self)
    local tmp, result

    tmp    = {}
    result = {}

    for _, v in ipairs(self) do
        tmp[v] = true
    end
    
    for k, _ in pairs(tmp) do
        result[#result + 1] = k 
    end

    return result
end

table.set = function(...)
    local tmp, output

    output = {}
    tmp    = {}

    for _, tbl in ipairs{ ... } do
        for _, val in ipairs(tbl) do
            if not tmp[val] then tmp[val] = 0 end

            tmp[val] = tmp[val] + 1
        end
    end

    for k, v in pairs(tmp) do
        if v > 1 then output[#output + 1] = k end 
    end

    return output
end

table.values = function(self)
    local result = {}

    for _, v in pairs(self) do
        result[#result + 1] = v
    end

    return result
end

table.keys = function(self)
    local result = {}

    for k, _ in pairs(self) do
        result[#result + 1] = k
    end

    return result
end

table.join = function(self, sep, last)
    local str = ""

    sep  = sep or " "
    last = last or sep

    if select(2, ipairs(self)) then
        local amount = #self

        for i, v in ipairs(self) do
            str = str .. tostring(v)

            if i - 1 == amount then
                str = str .. last
            elseif i ~= amount then
                str = str .. sep
            end
        end

        return str
    elseif select(2, pairs(self)) then
        local amount, i

        amount = table.count(self)
        i      = 1

        for _, v in pairs(self) do
            str = str .. tostring(v)

            if i - 1 == amount then
                str = str .. last
            elseif i ~= amount then
                str = str .. sep
            end

            i = i + 1
        end

        return str
    end

    error("Table value does not implement '__ipairs' or '__pairs'.")
end

table.merge = function(...)
    local args, main
    
    args = { ... }
    main = table.remove(args, 1)

    for _, v in ipairs(args) do
        for k, vv in pairs(v) do
            main[k] = vv
        end
    end

    return main
end

table.imerge =  function(...)
    local result = {}

    for _, i in ipairs({...}) do
        if i ~= nil then
            if type(i) == "table" then
                for _, j in ipairs(i) do
                    result[#result + 1] = j
                end
            else
                result[#result + 1] = i
            end
        end
    end

    return result
end

table.filter = function(self, func)
    local result = {}

    for i, v in ipairs(self) do
        if func(i, v) then
            result[#result + 1] = v
        end
    end
    
    return result
end

table.find = function(self, search)
    for i, v in ipairs(self) do if v == search then return i end end
end

table.map = function(self, func)
    local clone = {}

    for k, v in pairs(self) do clone[k] = v end

    for k, v in pairs(clone) do
        local a, b = func(k, v)

        if a == nil and b == nil then self[k] = nil end
        if a        and b == nil then self[a] = v   end
        if a == nil and b        then self[k] = b   end
        if a and b               then self[a] = b   end
    end

    return self
end

table.flatten = function(self, result)
    result = result or {}

    if type(self) == "table" then
        for _, v in pairs(self) do table.flatten(v, result) end
    else
        result[#result + 1] = self
    end

    return result
end

table.foreach = function(self, func)
    local clone = {}

    for i, v in ipairs(self) do clone[i] = v end

    for i, v in ipairs(clone) do
        local a, b = func(i, v)

        self[i] = nil

        if a and b == nil then self[a] = v end
        if a == nil and b then self[i] = b end
        if a and b        then self[a] = b end
    end

    return self
end

table.mdarray = function(self, func, depth)
    local p

    op[self] = op[self] or {
        final = true,
        index = 1
    }

    p     = op[self]
    depth = depth or 2

    for i, v in ipairs(self) do
        if depth > 1 then
            table.mdarray(v, function(...)
                if p.final then
                    func(p.index, i, ...)

                    p.index = p.index + 1
                else
                    func(i, ...)
                end
            end, depth - 1)
        end

        if depth == 1 then
            func(i, v)
        end
    end

    op[self] = nil

    return self
end

table.shuffle = function(self)
    local result = {}

    for _ = 1, #self, 1 do
        result[#result + 1] = table.remove(self, math.random(#self))
    end

    for i, v in ipairs(result) do self[i] = v end

    return self
end

table.reduce = function(self, func, init)
    for i, v in ipairs(self) do
        if init == nil then
            init = v
        else
            init = func(i, v, init)
        end
    end

    return init
end

table.deepset = function(self, ...)
    local args, result, value, last_key

    result   = self
    args     = { ... }
    value    = table.remove(args)
    last_key = table.remove(args)

    for _, v in ipairs(args) do
        assert(result[v] == nil or type(result[v]) == "table", "Reached non-table or non-nil value.")

        if result[v] == nil then result[v] = {} end

        result = result[v]
    end

    result[last_key] = value

    return self
end

table.deepget = function(self, ...)
    local result, output, args

    result = self or {}
    args   = { ... }
    len    = #args

    for i, v in ipairs(args) do
        output = result[v]

        if i == len then return output end
        if not output then return end

        result = output
    end
end

table.random = function(self)
    return self[math.random(#self)]
end

table.randpop = function(self)
    if #self == 0 then return end

    return table.remove(self, math.random(#self))
end

table.equals = function(...)
    local first, args, len

    args  = { ... }
    len   = #args
    first = table.remove(args, 1)

    for _, v in ipairs(args) do
        if len ~= #v then return false end

        for ii, vv in ipairs(first) do
            if v[ii] ~= vv then return false end
        end
    end

    return true
end

table.subset = function(self, i, j)
    local result = {}

    j = j or 0

    for a = i, j <= 0 and #self + j or j, 1 do
        result[#result + 1] = self[a]
    end

    return result
end

table.copy = function(tbl)
    local otype, copy

    otype = type(tbl)
    copy  = tbl

    if otype == "table" then
        copy = {}

        for k, v in next, tbl, nil do
            copy[table.copy(k)] = table.copy(v)
        end
    end

    return copy
end

string.split = function(self, separator, plain, keep)
    local result, index

    result = {}
    index  = 1
    plain  = plain == nil or plain

    if keep == nil then keep = false end
    if not not keep then keep = 0 else keep = 1 end

    if separator == nil or separator == "" then
        for i, chr in self do result[i] = chr end

        return result
    end

    while true do
        local start, fin = self:find(separator, index, plain)

        if not start then
            if index <= #self then
                result[#result + 1] = self:sub(index)
            end

            break
        end

        result[#result + 1] = self:sub(index, start - keep)

        index = fin + 1
    end

    return result
end

string.after = function(self, separator, plain)
    if plain == nil then plain = true end

    local start, fin = self:find(separator, 1, plain)

    if not start then return self end

    return self:sub(fin + 1)
end

string.before = function(self, separator, plain)
    if plain == nil then plain = true end

    local start, fin = self:find(separator, 1, plain)

    if not start                  then return self end
    if fin - separator:len() == 0 then return ""   end

    return self:sub(1, fin - separator:len())
end

string.title = function(self) 
    local result = {}

    for i, v in ipairs(self:split(" ")) do
        result[i] = v:sub(1, 1):upper() .. v:sub(2)
    end

    return table.concat(result, " ")
end

string.endswith = function(self, str)
    return not not self:match(str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$")
end

string.startswith = function(self, str)
    return not not self:match("^" .. str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

string.padleft = function(self, num, str)
    while #self < num do
        self = str .. self
    end

    return self
end

string.padright = function(self, num, str)
    while #self < num do
        self = self .. str
    end

    return self
end

string.trim = function(self)
    local result = self:gsub("^%s*", ""):gsub("%s*$", "")

    return result
end

string.count = function(self, pattern)
    return select(2, self:gsub(pattern, ""))
end

local function char_iterator(self, index)
    index = index + 1

    if index > utf8.len(self) then return end

    return index, utf8.char(utf8.codepoint(self, utf8.offset(self, index)))
end

debug.setmetatable("", {
    __call = function(self, ...)
        local value = select(2, ...)

        if type(value) ~= "number" then
            return char_iterator(self, 0)
        end

        return char_iterator(self, value)
    end,
    __index = string
})

debug.setmetatable(0, {
    __index = math
})