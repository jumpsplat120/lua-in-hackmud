local Encoder, JS, Array, Null, Function, Object, Scriptor

Encoder = setmetatable({}, require("lua54.Object"))

JS       = require("lua54.JS")
Scriptor = require("lua54.Scriptor")

Null     = JS.Null()
Array    = JS.Array()
Object   = JS.Object()
Function = JS.Function()

--Create an object, then pass data to "convert" to automatically convert it to an array of doubles, for passing to
--JS. It is important for the user (or the helper scripts) to be explicit when passing values to JS. If they want
--something to be an empty object over an empty array, then they should provide that explicitly. If you explicitly
--want an object with numeric keys, then you need to wrap your table in a JS.Object. If you want your sparsely filled
--array to be treated as a sparsely filled array and not an object, then you need to wrap it in JS.Array. If you want
--a value to be a null and not undefined, then you need to pass in a JS.Null. Rather than make assumptions, the user
--is obligated to specify the look of their data. A JS.Function, if it exists, can be passed like expected. A lua
--function can not. Userdata and threads will also throw, if the user has somehow managed to get their hands on those
--data types. Throwing makes it clear to the user, and they can always catch the error if they need to.
function Encoder:new()
    self.data = {}
end

function Encoder:convert(data, safe, new)
    local T = type(data)

    if new ~= nil then self.data = { new } end

    if T == "boolean" then
        self:boolean(data)
    elseif T == "number" then
        self:number(data)
    elseif T == "string" then
        self:string(data)
    elseif T == "nil" then
        --Nil more closely aligns with undefined in js. If the user wants to send an explicit null, then they can use
        --JS.Null.
        self:undefined()
    elseif T == "table" then
        local count

        if Array.isArray(data) then
            self:array(data.data, safe)
        elseif Object.isObject(data) then
            self:object(data.data, safe)
        elseif Null.isNull(data) then
            self:null()
        elseif Function.isFunction(data) then
            self:func(data)
        elseif Scriptor.isScriptor(data) then
            self:scriptor(data)
        else
            --We don't bother counting keys until all the way down here to save on cycles.
            count = #table.keys(data)
            
            if count == 0 then
                --There are no values in the table at all. An empty object is more likely desired than an empty
                --array(parameters for a script call, for example).
                self:object(data, safe)
            elseif count > #data then
                --Data only shows sequentially ordered data, while count is all keys. If count is greater than data,
                --then that means we need to treat it as an object, with some of the object keys being numbers.
                --If #data == 0, then it's just a regular object.
                self:object(data, safe)
            else
                self:array(data, safe)
            end
        end
    elseif safe then
        self:string(tostring(data))
    else
        error("You are not allowed to send a `C" .. T .. "` value to Javascript. Pass `Ctrue` as a second parameter if you'd like this data to be converted to a `Cstring`.")
    end

    return self.data
end

function Encoder:boolean(bool)
    table.insert(self.data, bool and 1 or 0)
end

function Encoder:number(num)
    table.insert(self.data, 2)
    table.insert(self.data, num)
end

function Encoder:string(str)
    local len, invalid = utf8.len(str)

    assert(invalid == nil, "Invalid utf8 character found at index `C" .. tostring(invalid) .. "`.")
    
    table.insert(self.data, 3)
    table.insert(self.data, len)

    for i = 1, len, 1 do
        table.insert(self.data, utf8.codepoint(str, utf8.offset(str, i)))
    end
end

function Encoder:array(tbl, safe)
    table.insert(self.data, 4)
    table.insert(self.data, #tbl)

    for _, v in ipairs(tbl) do
        self:convert(v, safe)
    end
end

function Encoder:object(tbl, safe)
    table.insert(self.data, 5)
    table.insert(self.data, #table.keys(tbl))

    for k, v in pairs(tbl) do
        self:convert(k, safe)
        self:convert(v, safe)
    end
end

function Encoder:scriptor(scriptor)
    table.insert(self.data, 6)

    self:string(scriptor.name)
end

function Encoder:func(func)
    table.insert(self.data, 7)
    table.insert(self.data, func:pointer())
end

function Encoder:null()
    table.insert(self.data, 8)
end

function Encoder:undefined()
    table.insert(self.data, 9)
end

return Encoder()