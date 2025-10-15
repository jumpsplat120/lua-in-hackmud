return {
    __call = function(class, ...)
        local ins = setmetatable({
            __OBJECT_INSTANCE = true
        }, {
            __index = class,
            __call = function(self, ...)
                assert(self.call, "Tried to call a table value.")

                return self:call(...)
            end
        })

        return ins:new(...) or ins
    end
}