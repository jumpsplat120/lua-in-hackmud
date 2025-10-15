local Scriptor, scriptors

Scriptor = setmetatable({}, require("lua54.Object"))

scriptors = {}

function Scriptor:new(str, as_null)
    assert(type(str) == "string", "Value passed to `CScriptor` is not of type `Cstring`.")

    if scriptors[str] then return scriptors[str] end

    self.name    = str
    self.as_null = not not as_null

    scriptors[str] = self
end

function Scriptor:call(...)
    return decode(lua_tojs(encode({ self, ... }, false, 2)), self.as_null)
end

function Scriptor.isScriptor(v)
    return (getmetatable(v) or {}).__index == Scriptor
end

return Scriptor