/* All lua specific source code has been snipped from this file.
 * This code was written directly into lua.c, from the lua 5.4 source.
 * You should be able to copy paste this in directly.
 */

#include <emscripten.h>


/* 
 * +====================+
 * |                    |
 * |  LUA TO JS FOR HM  |
 * |                    |
 * +====================+
 * 
 */

//Placeholder implementation. Our real implementation is not this, but using extern doesn't
//let C recognize the function call correctly. I imagine there is some extra step involving
//linking a library of JS code, or some such thing, but that step is excluded because it
//assumes an environment we're not working in.
EM_JS(lua_Number*, read_data, (lua_Number* data, double len), {
    return data;
});

//Take a string from lua, and run it in JS, then take the result from JS, and pass it back to lua.
//All lua_* functions that have a raw version, we use it, since the tables we are manipulating shouldn't
//have metatables to worry about, and the assumption is that raw is faster (we haven't actually checked
//that though).
int lua_tojs(lua_State *L) {
    //Verify that arg[1] (stack[1]) is a lua table, and throws an error if it isn't.
    luaL_checktype(L, 1, LUA_TTABLE);
    
    //We ignore any other args that may have been passed to the function.
    lua_settop(L, 1);
    
    //Get the size of the table.
    //NOTE: Technically, lua_rawlen can return a table length of up to lua_Unsigned (unsigned long long).
    //However, a table of that length would take more than the hackmud runtime of 5 seconds to fill
    //anyways, and so therefore isn't worth accounting for. Instead, we convert the length to a double
    //to avoid having to deal with BigInt's on the Javascript side.
    const double len = (double)lua_rawlen(L, 1);
    
    //Allocate memory for the table. It should contain lua_Numbers, which are doubles (usually).
    lua_Number* values = malloc(len * sizeof(lua_Number));

    //If we fail to allocate, we throw a lua error, which is then handled by JS.
    if (values == NULL) {
        return luaL_error(L, "Size of table is too large for WASM instance. Failed to allocate memory.");
    }

    //Iterate through the table, pulling out all of the numbers.
    for (int i = 0; i < len; i++) {
        //Get stack[args[1]][args[2]]. Push the resulting value onto the stack.
        lua_rawgeti(L, 1, i + 1);
        
        //Rather than checktype, we check with isnumber so that we can free 'values' before
        //throwing. The err is a luaerror, which is handled by the LUA_OK check in interpet.
        if (!lua_isnumber(L, 2)) {
            free(values);

            return luaL_error(L, "Value in table for lua_tojs was not of type 'number', but instead %d.", lua_type(L, 2));
        }

        //Pull the value of our table and place it into values[i].
        values[i] = lua_tonumber(L, 2);
        
        //lua_pop does not remove ITEM n, it removes n ITEMS. So, pop off 1 value (the value
        //from the table we'd just pushed).
        lua_pop(L, 1);
    }

    //Clear the stack; we're done with all values on it.
    lua_settop(L, 0);

    //Pass in the pointer to our array. JS reads it, then spits back out another pointer
    //to a new set of data, which we place back into lua to be processed. C doesn't do anything
    //other than verifying types.
    lua_Number* result = read_data(values, len);
    
    //Once JS has finished reading our values, we can free that memory.
    free(values);

    //The first value passed is the length of our new table. Everything following is data.
    int length = result[0];

    //Push table onto stack.
    lua_newtable(L);
    
    //We skip the first value when sending stuff across, since the first value is the length
    //of the table, which is only information C needs to know. lua doesn't need to send that
    //like JS does because we use lua_len.
    for (int i = 1; i < length + 1; i++) {
        //Add our current number to the top of the stack.
        lua_pushnumber(L, result[i]);
        
        //Do stack[args[1]][args[2]] = stack[#stack]. Pops the value from the top of the
        //stack.
        lua_rawseti(L, 1, i);
    }

    //We no longer need the array, since we've pushed all the values into lua, so we can free it.
    free(result);

    //Number of results from the function.
    return 1;
}

//Takes lua code as a string, and interprets it. If unsuccessful, returns a pointer a string, which
//will either contain 0 (Failure to create a luastate), contain a \1 (Ran succesfully), or will contain
//some arbitrary amount of data (usually an error string from a lua failure.)  The true return values
//of a lua run are discarded; meta.lua should handle return values via lua_tojs, so that we can
//arbitrarily return any amount and/or type of data without having to account for it within C.
char* interpret(const char* string) {
    int status, result;

    lua_State *L = luaL_newstate();
    
    //Failed to create a luastate.
    if (L == NULL) return "\1";

    luaL_openlibs(L);

    //the luatojs function is what lets us call out from lua back to js, while still in the middle
    //of our lua code.
    lua_pushcfunction(L, lua_tojs);
    lua_setglobal(L, "lua_tojs");
    
    //If dostring is unsuccessful, we get a luaerror, which we then need to pull off the stack. We
    //assumes that the error object is a string, as it was either generated by Lua or by 'msghandler'.
    if (luaL_dostring(L, string) != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        
        lua_pop(L, 1);
        lua_close(L);

        return msg;
    }

    lua_close(L);

    return "";
}
