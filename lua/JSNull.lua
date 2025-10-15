local Null = setmetatable({}, require("lua54.Object"))

function Null:new()
end

function Null.isNull(v)
    return (getmetatable(v) or {}).__index == Null
end

return Null