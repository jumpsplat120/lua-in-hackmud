local Array = setmetatable({}, require("lua54.Object"))

function Array:new(tbl)
    assert(type(tbl) == "table", "Value passed to `CJS.Array` is not of type `Ctbl`.")

    self.data = tbl
end

function Array.isArray(v)
    return (getmetatable(v) or {}).__index == Array
end

return Array