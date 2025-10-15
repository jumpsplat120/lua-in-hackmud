local Decoder, JS, Null, Function, Scriptor

Decoder = setmetatable({}, require("lua54.Object"))

JS       = require("lua54.JS")
Scriptor = require("lua54.Scriptor")

Null     = JS.Null()
Function = JS.Function()

--Options:
--  null_to_nil = true|false
--Create an object, then pass data to process it. Processing usually involves conversion, but sometimes can also
--throw an error, if javascript requested it. Conversion from JS is forced to be opinionated, since data from JS
--will rarely define explicit conversions (a response from #fs.scripts.lib() for example isn't going to define the
--difference between an empty array or an empty object). Unlike sending *to* JS, where that information is
--important (you wouldn't want to pass an empty array to a script when you meant to pass an empty object), once
--it's back in lua, it gets converted into the most reasonable thing. The only config option is null, since while
--undefined/nil is a safe conversion, null is often an explicitly defined "nothing" from the user, and therefore
--can be something you'd want to know in lua.
function Decoder:new(as_null)
    self.null_conversion = as_null
end

function Decoder:process(data)
    local action = data[1]

    self.index = 1

    --Whatever process we wanted to likely succeeded. Stuff like returnJS and error handling have no return data to
    --decode. Of course, we also know that, and aren't likely to try decoding something that isn't there, but it's
    --good to have for posterity.
    if action == 0 then
        return
    end

    --The following data is all data that we want to do something with.
    if action == 1 then
        return self:convert(data)
    end

    --The following is also data, but meant specifically for an error.
    if action == 2 then
        error(self:convert(data), 2)
    end

    malformed(1, action, 0, 2)
end

function Decoder:convert(data)
    local byte
    
    self.index = self.index + 1

    byte = data[self.index]

    self.index = self.index + 1

    if byte == 0 or byte == 1 then return self:boolean(data)  end
    if              byte == 2 then return self:number(data)   end
    if              byte == 3 then return self:string(data)   end
    if              byte == 4 then return self:array(data)    end
    if              byte == 5 then return self:object(data)   end
    if              byte == 6 then return self:scriptor(data) end
    if              byte == 7 then return self:func(data)     end
    if              byte == 8 then return self:null()         end  
    if              byte == 9 then return self:undefined()    end

    malformed(self.index - 1, byte, 0, 9)
end

function Decoder:boolean(data)
    --Boolean carries no data beyond it's iden byte.
    self.index = self.index - 1

    return data[self.index] == 1
end

function Decoder:number(data)
    return data[self.index]
end

function Decoder:string(data)
    local t = {}

    --The first value (after the string iden) is it's length.
    for _ = 1, data[self.index], 1 do
        self.index = self.index + 1

        table.insert(t, utf8.char(data[self.index]))
    end
    
    return table.concat(t, "")
end

function Decoder:array(data)
    local t, len
    
    t   = {}
    len = data[self.index]
    
    --The first value (after the array iden) is it's length. Recursively convert data until we finish.
    for _ = 1, len, 1 do
        table.insert(t, self:convert(data))
    end

    return t
end

function Decoder:object(data)
    local t, len
    
    t   = {}
    len = data[self.index]

    --The first value (after the obj iden) is it's length. Length is in key/value pairs.
    for _ = 1, len, 1 do
        t[self:convert(data)] = self:convert(data)
    end

    return t
end

function Decoder:scriptor(data)
    self.index = self.index + 1

    return Scriptor(self:string(data))
end

function Decoder:func(data)
    checker = math.random()

    return Function(data[self.index], checker)
end

function Decoder:null()
    --Null carries no data beyond it's iden byte.
    self.index = self.index - 1

    if self.null_conversion then return Null() end
end

function Decoder:undefined()
    --Undefined carries no data beyond it's iden byte. It's always nil, so beyond changing the index, we do nothing.
    self.index = self.index - 1
end

return Decoder()