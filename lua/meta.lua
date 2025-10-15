err_msg = false

--Reimplementation of setfenv.
--https://leafo.net/guides/setfenv-in-lua52-and-above.html
function setfenv(fn, env)
    local i = 1

    while true do
        local name = debug.getupvalue(fn, i)

        if name == "_ENV" then
            debug.upvaluejoin(fn, i, function() return env end, 1)

            break
        elseif not name then
            break
        end

        i = i + 1
    end

    return fn
end

--Wrapper of the error function. When called, it fetches the traceback 1 level up, then saves that error in the
--err_msg variable within lua. At the end of everything, we check to see if an error exists in this variable. If it
--does, then we use that one. Otherwise, it's an error from a native function, and we use the one we recieved from
--xpcall in preload.
function error(str, level)
    err_msg = debug.traceback(str, (level or 1) + 1)

    oerror()
end

--Functions identically to error, expect it only errors if the first value returns false. We don't call error directly,
--because the traceback will be at the wrong level.
function assert(truthy, ...)
    if truthy then return truthy, ... end

    err_msg = debug.traceback(..., 2)

    oerror()
end

--A very specific type of error. We pass in the bytes that we failed at, so that we can pass that data to JS. On the
--JS side, if we recieve an error with this body, then instead of returning a notok object like usual, we throw a
--Malformed error. This is because, regardless of whether it happens on the lua or JS side, that is a severe data
--encoding error, one that should be reported to us, not one that should be disregarded as a regular lua error.
function malformed(i, v, a, b)
    lua_tojs(encoder:convert({ i, v, a, b }, false, 4))
    oerror()
end

--Lets us exit from anywhere in our code. This allows us to do things like wrap argument checking in a function, and
--halt the script execution from in there, or immediately exit when low on time, rather than needing to always return
--back to the top level before ending the script. Will return any and all values passed to exit as return values to
--javascript.
function exit(...)
    lua_tojs(encoder:convert(Array({ ... }), true, 0))
    oerror()
end

--Printing a value is effectively the same thing as returning it, since using #D() only works for lua54. That also
--means we don't need to do any conversions, as we can just send them wholesale, and let the CLI stringify it for
--us. We don't overwrite the existing print, so that we personally can still use it for debugging, if needed.
function my_print(...)
    lua_tojs(encoder:convert(Array({ ... }), true, 10))
end

--Sends data to JS, then immediately recieves it back. Just verifies that the round trip doesn't cause any data mangling.
function echo(v)
    return decoder:process(lua_tojs(encoder:convert(v, true, 9)), true)
end

--Retrieves current, remaining, and elapsed time.
function time()
    return decoder:process(lua_tojs(encoder:convert(nil, false, 6)))
end

--Returns true is the user's remaining time is below the number provided.
function timeout(num)
    assert(type(num) ~= "number", "Parameter `Cnum` was not of type `Cnumber`.")

    return time().remaining < num
end

--Returns the amount of seconds the script has been running for. Identical to os.clock().
function clock()
    return time().elapsed / 1000
end

--Either returns the current time, or formats it. Uses os.date() under the hood, but replaces it for the user.
function date(format, ts)
    ts = ts or (time().current / 1000)

    return os.date(format, ts)
end

--Returns context and args from JS. A user can call this, and save it locally to avoid anyone from affecting
--the values by modifying it in their own module.
function info()
    return decoder:process(lua_tojs(encoder:convert(nil, false, 5)))
end

--Simply returns time elapsed divided by 1000. Replaces os.clock()
function clock()
    return time().elapsed / 1000
end

--Helper function for handling dot notation.
function dot(name, plain)
    local parts = name:split(".", true)
    
    if #parts == 1 then return name, { "" } end
    
    if plain then return name:gsub("%.", "|"), { "" } end
    
    --When we concat the parts, this preceding empty string will cause a period to be added before the rest of the
    --elements.
    table.insert(parts, 2, "")

    return table.remove(parts, 1), parts
end

--DB functions, for internal use.
db = {
    insert = function(...)
        return decoder:process(lua_tojs(encoder:convert({ 2, Null(), { ... } }, true, 1)))
    end,
    upsert = function(query, command)
        return decoder:process(lua_tojs(encoder:convert({ 7, Null(), { query, command } }, true, 1)))
    end,
    update = function(query, command)
        return decoder:process(lua_tojs(encoder:convert({ 5, Null(), { query, command } }, true, 1)))
    end,
    updateOne = function(query, command)
        return decoder:process(lua_tojs(encoder:convert({ 6, Null(), { query, command } }, true, 1)))
    end,
    remove = function(query, confirm)
        return decoder:process(lua_tojs(encoder:convert({ 4, Null(), query, not not confirm }, true, 1)))
    end,
    find = function(query, projection, method, cursor_arg)
        return decoder:process(lua_tojs(encoder:convert({ 1, method, { query, projection }, cursor_arg }, true, 1)), true)
    end,
    oid = function()
        return decoder:process(lua_tojs(encoder:convert({ 3 }, false, 1)))
    end,
    INCLUDE = 1,
    EXCLUDE = 2,
    INCLUDE_PLAIN = 3,
    EXCLUDE_PLAIN = 4
}

--Assumes that the value being passed is an item or items to be added to an array in the DB. If item is a sequentially
--indexed table (#tbl > 0), then it assumes each item is to be pushed individually. Otherwise, assumes that item is a
--single item to be pushed. The first parameter is the name of the array you want to add to, and it will create one
--if one doesn't exist. Uses select() to count all items, so nils will be passed and converted to nulls. If no array
--exists, will create one. Will use dot notation unless plain is set to true.
function push(name, items, plain)
    assert(type(name) == "string", "Parameter `Cname` is not of type `Cstring`.")
    assert(type(items) == "table", "Parameter `Citems` is not of type `Ctable`.")

    local id, rest = dot(name, plain)
    
    return db.upsert({
        _id = id,
        author = author,
        is_data = true,
    }, {
        ["$push"] = {
            ["data" .. table.concat(rest, ".")] = {
                ["$each"] = items
            }
        }
    })
end

--Removes a specific item from an assumed array in the DB. The first parameter is the name of the array, while the
--second is the index. If no index is present, will pop from the end of the array. If index is a number, then it
--pulls the value at that index. If index is a table containing numbers, then it treats them all as indexes, and
--pulls each item. Does *not* return the item. If no array to pop from exists, will throw an error. Will use dot
--notation unless plain is set to true.
function pop(name, index, plain)
    local is_tbl, query, id, rest
    
    is_tbl = type(index) == "table"

    assert(type(name) == "string", "Parameter `Cname` is not of type `Cstring`.")
    assert(index == nil or type(index) == "number" or is_tbl, "Parameter `Cindex` is not of type `Cnumber`, `Ctable`, or `Cnil`.")

    id, rest = dot(name, plain)

    query = {
        _id = id,
        author = author,
        is_data = true
    }
    
    if not index then
        return db.update(query, {
            ["$pop"] = {
                ["data" .. table.concat(rest, ".")] = 1
            }
        })
    elseif is_tbl then
        for i, v in ipairs(index) do
            assert(type(v) == "number", "Parameter `Cindex``B[``C" .. i .. "``B]` is not of type `Cnumber`.")
        end
    end

    return db.update(query, {
        [is_tbl and "$pullAll" or "$pull"] = {
            ["data" .. table.concat(rest, ".") .. ".$[]"] = index
        }
    })
end

--Assumes that name is a numeric value in the db, and increases it by 1, or amount if passed. Will use dot notation
--unless plain is set to true.
function increment(name, amount, plain)
    assert(type(name) == "string", "Parameter `Cname` is not of type `Cstring`.")
    assert(amount == nil or type(amount) == "number", "Parameter `Camount` is not of type `Cnumber` or `Cnil`.")

    local id, rest = dot(name, plain)

    return db.upsert({
        name = id,
        author = author,
        is_data = true,
    }, {
        ["$inc"] = {
            ["data" .. table.concat(rest, ".")] = amount or 1
        }
    })
end

--A wrapper for increment that simply multiplies the amount by -1.
function decrement(name, amount, plain)
    assert(type(name) == "string", "Parameter `Cname` is not of type `Cstring`.")

    if amount ~= nil then
        assert(type(amount) == "number", "Parameter `Camount` is not of type `Cnumber` or `Cnil`.")

        amount = amount * -1
    end

    return increment(name, amount, plain)
end

--Increments multiple values by some amount. Each item must be a table, where the first item is required, and is
--the key of the document to increment. The second value is optional, and will be set to 1 if nil. The third value
--is optional, and says whether the key should use dot notation.
function increments(...)
    local args, value, fields, count, id, rest
    
    count = select("#", ...)

    args   = { ... }
    fields = {}

    if count == 0 then return { ok = false } end

    for i = 1, count, 1 do
        value = args[i]

        assert(type(value[1]) == "string", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C1``B]` is not of type `Cstring`.")
        assert(value[2] == nil or type(value[2]) == "number", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C2``B]` is not of type `Cstring` or `Cnil`.")

        id, rest = dot(value[1], value[3])

        fields[id .. ".data" .. table.concat(rest, ".")] = value[2] or 1
    end

    return db.upsert({
        author = author,
        is_data = true,
    }, {
        ["$inc"] = fields
    })
end

--A wrapper for increments that simply multiplies the amounts by -1. Returns ok:false if no values were passed.
function decrements(...)
    local args, count
    
    count = select("#", ...)
    args  = { ... }

    if count == 0 then return { ok = false } end

    for i = 1, count, 1 do
        value = args[i]

        assert(type(value[1]) == "string", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C1``B]` is not of type `Cstring`.")
        
        if value[2] ~= nil then
            assert(type(value[2]) == "number", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C2``B]` is not of type `Cstring` or `Cnil`.")
        
            value[2] = value[2] * -1
        end
    end

    return increments(table.unpack(args))
end

--Creates a document, and uploads the value to the db. If no value is passed (is nil), then removes the value in the
--db, if one exists. We never need to confirm, since set will only ever match one value at a time. If the name uses
--dot notation, then attempts to set/change the resulting value. So "my.value" assumes a document called "my" with a
--key called "value", and tries to change that key's value. If you want "my.value" to be treated as one whole key
--name, you can set plain to true.
function set(name, value, plain)
    local query, id, rest

    assert(type(name) == "string", "Parameter `Cname` is not of type `Cstring`.")

    id, rest = dot(name, plain)

    query = {
        _id = id,
        author = author,
        is_data = true
    }
    
    if value == nil then
        if rest[1] == "" then
            return db.remove(query)
        end

        --The value of unset has no affect; using a boolean is the least amount of bytes to encode.
        return db.update(query, {
            ["$unset"] = {
                ["data" .. table.concat(rest, ".")] = true
            }
        })
    end

    return db.upsert(query, {
        ["$set"] = {
            ["data" .. table.concat(rest, ".")] = value
        }
    })
end

--Gets the data of whatever document has this name. Will return nil if none is found. Will use dot notation unless
--plain is set to true.
function get(name, plain)
    local id, rest, projection

    assert(type(name) == "string", "Parameter `Cname` is not of type `Cstring`.")

    id, rest = dot(name, plain)
    
    --Using a projection reduces the amount of data that needs to be encoded.
    if #rest > 1 then
        projection = {
            ["data" .. table.concat(rest, ".")] = 1
        }
    end
    
    --Remove the prepended space.
    table.remove(rest, 1)

    return table.deepget(db.find({
        _id = id,
        author = author,
        is_data = true
    }, projection, "first") or {}, "data", table.unpack(rest))
end

--Insert an arbitrary amount of documents simultaneously. Formatting is strict; each value for assert must be a
--table, where the first value is the key's name, and the second value is the value itself. An optional third value
--can be true if the key's name is meant to be treated as plain, otherwise dot notation will be used. Insert is
--not set; if a document already exists with this key, then it will throw an error. Returns ok:false if no values
--were inserted.
function insert(...)
    local args, value, docs, count, id, rest
    
    count = select("#", ...)

    args = { ... }
    docs = {}

    if count == 0 then return { ok = false } end

    for i = 1, count, 1 do
        value = args[i]

        assert(type(value[1]) == "string", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C1``B]` is not of type `Cstring`.")

        id, rest = dot(value[1], value[3])

        table.insert(docs, {
            _id = id,
            ["data" .. table.concat(rest, ".")] = value[2],
            author = author,
            is_data = true
        })
    end

    return db.insert(table.unpack(docs))
end

--Retrieves an arbitrary amount of documents simultaneously. Each value can either be a string, or a table. If it's
--a table, the table's first value must be a string to represent the key, while an optional third value can be true
--or false, to define whether the key should be treated as having dot notation or not. Returns ok:false if no
--values were passed.
function retrieve(...)
    local args, value, ids, response, results, count, id, rest, fields
    
    count = select("#", ...)

    args    = { ... }
    ids     = {}
    fields  = {}
    results = {}

    if count == 0 then return { ok = false } end

    for i = 1, count, 1 do
        value = args[i]

        assert(type(value[1]) == "string", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C1``B]` is not of type `Cstring`.")

        id, rest = dot(value[1], value[3])

        table.insert(ids, { _id = id })
        
        if not fields[id] then
            fields[id] = {}
        end

        table.insert(fields[id], rest)
    end

    response = db.find({
        ["$and"] = {
            {
                ["$or"] = ids
            },
            {
                author = author,
                is_data = true
            }
        }
    }, nil, "array")

    for _, v in ipairs(response) do
        results[v._id] = {}

        --Take each table of fields in fields[v._id], and find the value it's referencing in v.
        --Then put that value in a results table in the same spot. So if we have { "a.b", "a.c" }
        --As 'field', then we want to take a = { b = 'this value and ', c = 'this value, but', d = 'not this one'  }
        --It's effectively a projection, but we don't want to pass a projection to find, because the projection
        --is document specific. Each document has it's own values we want to fetch, and so we have to do the logic
        --ourselves.
        for _, field in ipairs(fields[v._id]) do
            if #field > 1 then
                --Remove the prepended space.
                table.remove(field, 1)

                local args = { table.unpack(field) }

                table.insert(args, table.deepget(v, "data", table.unpack(field)))

                table.deepset(results[v._id], "data", table.unpack(args))
            end
        end
    end

    return results
end

--Removes an arbitrary amount of documents simultaneously. Each value can either be a string, or a table. If it's a
--table, the table's first value must be a string, while an optional second value can be true or false, to define
--whether the key should be treated as having dot notation or not. If the final value is explicitly true, then is
--treated as a confirmation (attempting to delete more than 10 items at a time will throw an error, and must be
--explicitly confirmed).
function remove(...)
    local args, value, ids, T, count, confirm, fields, removed, updated
    
    count = select("#", ...)

    args   = { ... }
    ids    = {}
    fields = {}

    if count == 0 then return { ok = false } end

    for i = 1, count, 1 do
        value = args[i]
        T     = type(value)

        --If our last value is explicitly a boolean, then we are assuming it's a confirmation to remove more than
        --10 documents in a single call.
        if i == count and type(value) == "boolean" then
            confirm = value

            break
        end

        assert(T == "string" or T == "table", "Parameter `B<``C...``B>[``C" .. i .. "``B]` is not of type `Cstring` or `Ctable`.")
        
        if T == "string" then
            table.insert(ids, { _id = value })
        elseif T == "table" then
            assert(type(value[1]) == "string", "Parameter `B<``C...``B>[``C" .. i .. "``B][``C1``B]` is not of type `Cstring`.")
            
            id, rest = dot(value[1], value[2])

            --We only want to add an unset field if we actually have a key to add. Everything in ids is stuff we
            --want to remove wholesale, while everything in fields is stuff we want to unset.
            if #rest > 1 then
                table.insert(fields, {
                    [id .. ".data" .. table.concat(rest, ".")] = true
                })
            else
                table.insert(ids, { _id = id })
            end
        end
    end

    if #ids > 0 then
        removed = db.remove({
            ["$and"] = {
                {
                    ["$or"] = ids
                },
                {
                    author = author,
                    is_data = true
                }
            }
        }, confirm)
    end

    if #table.keys(fields) > 0 then
        updated = db.update({
            author = author,
            is_data = true
        }, {
            ["$unset"] = fields
        })
    end

    return {
        ok = true,
        removed = removed.removed or nil,
        modified = updated.modified or nil,
        op_time = (updated.op_time or 0) + (removed.op_time or 0)
    }
end

--The function that retrieves data from JS. Like require, but skips a few steps to make things a bit faster.
--We don't assert, since the user can't call this. Preloaded stuff is already encoded, and we already know
--it's meant to be a string as well. We don't need to check loaded, because preload only ever runs unique
--code.
function preload(path, is_main)
    data = decoder:process(lua_tojs(encoder:convert(path, false, 12)))
    func = assert(load(data, path .. ".lua", "t", USER_ENV))

    if is_main then
        return xpcall(func, debug.traceback)
    end

    loaded[path] = func()

    if loaded[path] == nil then
        loaded[path] = true
    end
end

--Wrapper for load, to prevent a user from running binary chunks. Minimal configuration; they're only allowed
--to change the chunkname. Otherwise, they can load a string (or a func), it will have USER_ENV, and that's it.
function my_load(chunk, chunkname)
    return load(chunk, chunkname, "t", USER_ENV)
end

--User's _G. Anything here, they have access to. Anything that isn't, they don't.
USER_ENV = {
    os = {
        exit = exit,
        date = date,
        clock = clock,
        timeout = timeout,
    },
    hm = {
        Scriptor = Scriptor,
        fs = {
            accts = {
                xfer_gc_to_caller = Scriptor("accts.xfer_gc_to_caller"),
                balance_of_owner  = Scriptor("accts.balance_of_owner")
            },
            bbs = {
                read = Scriptor("bbs.read"),
                r    = Scriptor("bbs.r")
            },
            chats = {
                create = Scriptor("chats.create"),
                send   = Scriptor("chats.send"),
                tell   = Scriptor("chats.tell")
            },
            escrow = {
                charge = Scriptor("escrow.charge")
            },
            market = {
                browse = Scriptor("market.browse")
            },
            scripts = {
                get_access_level = Scriptor("scripts.get_access_level"),
                get_level        = Scriptor("scripts.get_level"),
                nullsec          = Scriptor("scripts.nullsec"),
                fullsec          = Scriptor("scripts.fullsec"),
                highsec          = Scriptor("scripts.highsec"),
                lowsec           = Scriptor("scripts.lowsec"),
                midsec           = Scriptor("scripts.midsec"),
                quine            = Scriptor("scripts.quine"),
                trust            = Scriptor("scripts.trust"),
                lib              = Scriptor("scripts.lib")
            },
            sys = {
                xfer_upgrade_to_caller = Scriptor("sys.xfer_upgrade_to_caller"),
                upgrades_of_owner      = Scriptor("sys.upgrades_of_owner"),
                w4rn_message           = Scriptor("sys.w4rn_message")
            },
            users = {
                last_action = Scriptor("users.last_action"),
                active      = Scriptor("users.active"),
                top         = Scriptor("users.top")
            }
        },
        hs = {
            accts = {
                transactions = Scriptor("accts.transactions"),
                balance      = Scriptor("accts.balance")
            },
            scripts = {
                sys = Scriptor("scripts.sys")
            },
            sys = {
                upgrade_log = Scriptor("sys.upgrade_log"),
                upgrades    = Scriptor("sys.upgrades"),
                inspect     = Scriptor("sys.inspect"),
                status      = Scriptor("sys.status"),
                specs       = Scriptor("sys.specs")
            }
        },
        ms = {
            accts = {
                xfer_gc_to = Scriptor("accts.xfer_gc_to")
            },
            chats = {
                channels = Scriptor("chats.channels"),
                leave    = Scriptor("chats.leave"),
                users    = Scriptor("chats.users"),
                join     = Scriptor("chats.join")
            },
            escrow = {
                stats = Scriptor("escrow.stats")
            },
            market = {
                stats = Scriptor("market.stats"),
                buy   = Scriptor("market.buy")
            },
            scripts = {
                user = Scriptor("scripts.user")
            },
            sys = {
                manage = Scriptor("sys.manage")
            },
            autos = {
                reset = Scriptor("autos.reset")
            }
        },
        ls = {
            market = {
                sell = Scriptor("market.sell")
            },
            sys = {
                expose_transactions = Scriptor("sys.expose_transactions"),
                expose_upgrade_log  = Scriptor("sys.expose_upgrade_log"),
                expose_access_log   = Scriptor("sys.expose_access_log"),
                xfer_upgrade_from   = Scriptor("sys.xfer_upgrade_from"),
                expose_upgrades     = Scriptor("sys.expose_upgrades"),
                xfer_upgrade_to     = Scriptor("sys.xfer_upgrade_to"),
                expose_balance      = Scriptor("sys.expose_balance"),
                xfer_gc_from        = Scriptor("sys.xfer_gc_from"),
                access_log          = Scriptor("sys.access_log"),
                write_log           = Scriptor("sys.write_log"),
                cull                = Scriptor("sys.cull"),
                loc                 = Scriptor("sys.loc")
            },
            kernel = {
                hardline = Scriptor("kernel.hardline")
            }
        },
        ns = {
            sys = {
                breach = Scriptor("sys.breach")
            },
            users = {
                config = Scriptor("users.config")
            },
            corps = {
                create = Scriptor("corps.create"),
                manage = Scriptor("corps.manage"),
                offers = Scriptor("corps.offers"),
                hire   = Scriptor("corps.hire"),
                quit   = Scriptor("corps.quit"),
                top    = Scriptor("corps.top")
            },
            binmat = {
                connect = Scriptor("binmat.connect"),
                xform   = Scriptor("binmat.xform"),
                c       = Scriptor("binmat.c"),
                x       = Scriptor("binmat.x")
            },
            trust = {
                me = Scriptor("trust.me")
            }
        }
    },
    db = {
        set = set,
        get = get,
        pop = pop,
        oid = db.oid,
        push = push,
        insert = insert,
        remove = remove,
        retrieve = retrieve,
        increment = increment,
        decrement = decrement,
        decrements = decrements,
        increments = increments
    },
    debug = {
        traceback = debug.traceback
    },
    print = my_print,
    assert = assert,
    error = error,
    ipairs = ipairs,
    pairs = pairs,
    getmetatable = getmetatable,
    setmetatable = setmetatable,
    load = my_load,
    next = next,
    pcall = pcall,
    xpcall = xpcall,
    rawequal = rawequal,
    rawget = rawget,
    rawlen = rawlen,
    rawset = rawset,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    _VERSION = _VERSION,
    coroutine = coroutine,
    require = require,
    string = string,
    utf8 = utf8,
    table = table,
    math = math
}
