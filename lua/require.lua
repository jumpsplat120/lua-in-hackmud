return function(path)
    local parts

    assert(not path:match("\n"), "Path can not contain newline characters.")
    assert(not path:match("%s"), "Path can not contain spacing characters.")
    assert(#path:gsub("[^%.]", "") <= 2, "Path can not contain more than 2 periods.")

    path  = path:gsub("%.lua$", "")
    parts = path:split(".", true)
    
    if #parts == 2 then
        assert(parts[1]:match("^[%l_]"), "Module author must begin with a lowercase letter or an underscore.")
        assert(#parts[1]:gsub("[%l%d_]", "") == 0, "Module author may only contain lowercase letters, numbers, or an underscore.")
    else
        table.insert(parts, 1, author)
    end
    
    --We always want a module to be author.module; this prevents issues where a user refers to their
    --module with both private and pubic syntax, causing us to fetch and load it twice.
    path = parts[1] .. "." .. parts[2]

    if loaded[path] == nil then
        local data
        
        --We can load, assert, and call all at the same time, because if the function errors,
        --it gets redirected to our error handler externally, so we don't need to worry about it.
        data = decoder:process(lua_tojs(encoder:convert(parts, false, 8))) 
        data = assert(load(data, path .. ".lua", "t", USER_ENV))()

        if data == nil then
            loaded[path] = true
        else
            loaded[path] = data
        end
    end

    return loaded[path]
end