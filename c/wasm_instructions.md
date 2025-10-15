# Setup

These instructions can likely be simplified through the use of a batch file or something similar. This is, however, the exact prorcess we used to get this working.

Install emscripten, then install this [patch](https://gitlab.bbguimaraes.com/bbguimaraes/nngn/-/blob/master/scripts/emscripten/patches/lua.patch).

Run the following like in Terminal (or whatever your CLI is):
<emmake_folder>\emmake make generic ALL=liblua.a

This will generate .o files, as well as a liblua.a file. Once that's been generated, run:
<emmake_folder>\emcc -Os lua.c liblua.a -s "EXPORTED_FUNCTIONS=['_interpret', '_allocate', '_deallocate']" --no-entry

This should create a.out.wasm, as well as some JS that isn't needed. This wasm file needs to be converted to an array of bytes to place it within hackmud. My specific strategy was to use an incredibly small node.js project that loads the wasm as an instance (with all imports simply being no-ops), then to read the bytes into a file, where I could then copy paste them out, and into the game. The lua54.exe script has the ability to read in a comma seperated string of numbers, then convert them and place them within the game's mongoDB. If you're curious, the exact code used was as follows: 
```js
const buf = await fs.readFile("a.out.wasm");
const module = new WebAssembly.Module(buf.buffer);

const e = new WebAssembly.Instance(module, {
    env: {
        read_data: _ => _,
        invoke_vii: _ => _,
        _emscripten_throw_longjmp: _ => _,
        _emscripten_system: _ => _,
        __syscall_dup3: _ => _,
        __syscall_unlinkat: _ => _,
        __syscall_rmdir: _ => _,
        __syscall_renameat: _ => _,
        __syscall_readlinkat: _ => _
        },
    wasi_snapshot_preview1: {
        environ_sizes_get: _ => _,
        environ_get: _ => _,
        proc_exit: _ => _,
        clock_time_get: _ => _,
        fd_close: _ => _,
        fd_write: _ => _,
        fd_read: _ => _,
        fd_seek: _ => _
    }
}).exports;

//upload to buffer.txt
const out = [];
let linesize = 0;

for (let i = 0; i < buf.length; i++) {
    let val = buf[i].toString();

    linesize += val.length + 1;

    if (linesize > 10000) {
        val = val + "\n";
        linesize = 0;
    } else if (i + 1 !== buf.length) {
        val = val + ",";
}

    out.push(val);
}

await fs.writeFile("buffer.txt", out.join(""))
```
Once the bytes have been saved, you can either copy paste them into the game by hand, or use something like AutoHotKey to automate the process. My exact AHK script for this process was:
```AHK
#Requires AutoHotkey v2.0

+F:: {
    Pause
}

; Press SPACE to start script
Space:: {
    Loop read, "buffer.txt" {
        A_Clipboard := "lua54.exe " A_LoopReadLine
        Click "Right"
        Sleep 100
        Send "{Enter}"
        Sleep 5000
    }
    ExitApp
}
```
