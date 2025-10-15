local Object = setmetatable({}, require("lua54.Object"))

function Object:new(tbl)
    assert(type(tbl) == "table", "Value passed to `CJS.Object` is not of type `Ctbl`.")

    self.data = tbl
end

function Object.isObject(v)
    return (getmetatable(v) or {}).__index == Object
end

return Object