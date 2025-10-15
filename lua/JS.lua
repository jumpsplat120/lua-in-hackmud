local JS, private

JS = setmetatable({}, require("lua54.Object"))

private = {}

function JS:new()
    private = {
        Null     = require("lua54.JSNull"),
        Array    = require("lua54.JSArray"),
        Object   = require("lua54.JSObject"),
        Function = require("lua54.JSFunction")
    }
end

function JS.Null()
    return private.Null
end

function JS.Array()
    return private.Array
end

function JS.Object()
    return private.Object
end

function JS.Function()
    return private.Function
end

return JS()