function (c, a) { // help: true
    a = a || {};

    //Since help autofills, a user may not remove it when uploading their script. To avoid frustration, we check that
    //the only key passed is help, otherwise we simply ignore it.
    if (Object.keys(a).length === 1 && a.help) return `To upload a module, provide\`q:\` { code: "return 1 + 1", name: "my_module" }
Module's are private by default. You can define your module's visibility like so\`q:\` { code: "return 'foo'", name:"foo_module", public:true }
To change whether your module is public or private, simply set \`Npublic\` to be \`Vtrue\` or \`Vfalse\` without providing any \`Ncode\`.

Module names are unique per user. If you provide a non-unique \`Nname\` to your module, you'll instead be prompted to update the old module with the newly provided code. Module names can contain any characters \`Cexcept\` for whitespace, or periods. Module's are case sensitive.

To remove your module, set \`Ncode\` to an empty string\`q:\` { code: "", name:"foo_module" }

To view your uploaded modules, run { list:true }

To access your own module, you can simply run \`Crequire\`\`B(\`\`C"my_module"\`\`B)\` in your lua code. To access other's modules, append their name to the string\`q:\` \`Crequire\`\`B(\`\`C"seanmakesgames\`\`B.\`\`Cmy_module"\`\`B)\``;

    if (a.quine) return #fs.scripts.quine();

    if (a.list) return #db.f({ author: c.caller, lua_module: true }, { _id: 1 }).array().map(v => v._id);

    if (!a.name) return "Please provide a `Nname` for your module.";

    if (typeof a.name !== "string") return ({ ok: false, msg: "`Nname` must be a string." });

    const filter = {
        _id: a.name,
        author: c.caller,
        lua_module: true
    };

    //We can use first, because the process of uploading will only ever allow one version of a module to exist at a time.
    //If a script author uploads another module, then the first module is overwritten.
    const data = #db.f(filter).first();
    
    if (a.code === undefined && a["public"] !== undefined) {
        if (!data) return ({ ok: false, msg: `No module found with the name \`C${a.name}\`.` });

        #db.u1(filter, { ["$set"]: { ["public"]: !!a["public"] } });
        
        return { ok: true, msg: `You have set module \`C${a.name}\`'s visibility to be \`C${a["public"] ? "public" : "private"}\`.` };
    }

    if (a.code === undefined) return "Please provide your `Ncode`.";
    
    if (typeof a.code !== "string") return ({ ok: false, msg: "`Ncode` must be a string." });

    if (a.code === "") {
        if (!a.remove) return ({ ok: false, msg: `You are about to remove the module \`C${a.name}\`. Provide remove:true to confirm that you want to delete this module permanantly. This cannot be undone.`});

        #db.r(filter);

        return { ok: true, msg: `You have succesfully deleted \`C${a.name}\`.` };
    }

    if (data && !a.update) return ({ ok: false, msg: `You have an existing module under the name \`C${a.name}\`. Provide update:true to confirm that you want to overwrite the old module with this new code.` });

    let pub = a["public"];

    if (pub === undefined) pub = (data || { ["public"]: false })["public"];

    const code = [];

    //Pre "compile" user modules, so that when fetching them, they're already encoded, and can just be sent straight
    //off. 1 means "return value", 3 means "string", followed by the string length, followed by the encoded string.
    code.push(1, 3, a.code.length, ...([...a.code]).map(cp => cp.codePointAt(0)));

    //If a.public is set, then we use that. Otherwise, we use data.public, and if that doesn't exist, then we set to
    //public to false.
    const response = #db.us(filter, {
        ["$set"]: {
            code: code,
            raw: a.code,
            ["public"]: pub
        }
    })[0];
    
    return {
        ok: true,
        msg: `Module \`C${a.name}\` has been \`C${response.upserted === undefined ? "updated" : "created"}\`, and it's visibility is set to \`C${pub ? "public" : "private"}\`.`
    };
}