local Function, funcs, private

Function = setmetatable({}, require("lua54.Object"))

funcs   = {}
private = {}

function Function:new(num, check)
    assert(check == checker, "You may not call the `CJS.Function` constructor directly.")

    if funcs[num] then return funcs[num] end

    --We hide this so the user can't change this value. That way, we know that a function object has a matching
    --function call in JS, since the user can only get a function from a scriptor call or passed arg to begin with.
    private[self] = { ptr = num }

    self.as_null = false

    funcs[num] = self
end

function Function:call(...)
    return decode(lua_tojs(encode({ self, ... }, false, 3)), self.as_null)
end

function Function.isFunction(v)
    return (getmetatable(v) or {}).__index == Function
end

function Function:pointer()
    return private[self].ptr
end

return Function