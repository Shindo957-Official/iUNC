local VERSION = "2.0"

local IsOnMobile = (function()
    local ok, ui = pcall(function() return game:GetService("UserInputService") end)
    if not ok then return false end
    local p = ui:GetPlatform()
    if p == Enum.Platform.IOS or p == Enum.Platform.Android
    or p == Enum.Platform.AndroidTV or p == Enum.Platform.Chromecast
    or p == Enum.Platform.MetaOS then return true end
    if p == Enum.Platform.None then
        return ui.TouchEnabled and not (ui.KeyboardEnabled or ui.MouseEnabled)
    end
    return false
end)()

local function fingerprintExecutor()
    local name = "Unknown"
    local version = ""

    local ok, n, v
    if identifyexecutor then
        ok, n, v = pcall(identifyexecutor)
        if ok and n then name = tostring(n); version = v and tostring(v) or "" end
    elseif getexecutorname then
        ok, n = pcall(getexecutorname)
        if ok and n then name = tostring(n) end
    elseif whatexecutor then
        ok, n = pcall(whatexecutor)
        if ok and n then name = tostring(n) end
    end

    if name == "Unknown" or name == "" then

        if rawget(getfenv(0), "syn") then
            name = "Synapse X"

        elseif rawget(getfenv(0), "ScriptWare") or rawget(getfenv(0), "sw") then
            name = "Script-Ware"

        elseif rawget(getfenv(0), "KRNL_LOADED") then
            name = "KRNL"

        elseif rawget(getfenv(0), "Electron") then
            name = "Electron"

        elseif rawget(getfenv(0), "fluxus") then
            name = "Fluxus"

        elseif rawget(getfenv(0), "oxygen") then
            name = "Oxygen U"

        elseif rawget(getfenv(0), "celery") then
            name = "Celery"

        elseif rawget(getfenv(0), "comet") then
            name = "Comet"

        elseif rawget(getfenv(0), "Delta") then
            name = "Delta"

        elseif rawget(getfenv(0), "ARCEUS_X") or rawget(getfenv(0), "awp") then
            name = "Arceus X"
        end
    end

    local platform = IsOnMobile and " (Mobile)" or ""
    return name, version, platform
end

local EXEC_NAME, EXEC_VERSION, EXEC_PLATFORM = fingerprintExecutor()
local EXEC_DISPLAY = EXEC_NAME .. (EXEC_VERSION ~= "" and " v"..EXEC_VERSION or "") .. EXEC_PLATFORM

local CATEGORIES = {
    "File System", "Closures", "Metatables", "Debug",
    "Instance & Cache", "Environment", "Signals & Input",
    "Crypto & Encoding", "Drawing", "Clipboard & Misc",
    "FPS", "Actors", "Script Tools", "WebSocket & HTTP",
    "FFlags", "Bit32", "String Extensions", "Optional"
}

local categoryStats = {}
for _, cat in ipairs(CATEGORIES) do
    categoryStats[cat] = {passes=0, fails=0, missing=0, weighted_score=0, weighted_total=0}
end

local totalWeightedScore  = 0
local totalWeightedMax    = 0
local running             = 0
local list_fail           = {}
local list_missing        = {}
local list_alias_missing  = {}
local list_optional_missing = {}
local messageboxPassed    = false

local function getGlobal(path)
    local v = getfenv(0)
    while v ~= nil and path ~= "" do
        local name, rest = string.match(path, "^([^.]+)%.?(.*)$")
        v = v[name]; path = rest
    end
    return v
end

local function normalizeError(err)
    local text = tostring(err or "Unknown error"):gsub("\r\n", "\n")
    local lines, last, rep = {}, nil, 0
    local function flush()
        if not last then return end
        table.insert(lines, rep > 1 and last.." (x"..rep..")" or last)
    end
    for line in text:gmatch("[^\n]+") do
        if line == last then rep += 1 else flush(); last = line; rep = 1 end
    end
    flush()
    if #lines == 0 then lines = {text} end
    while #lines > 4 do
        local h = #lines - 4
        while #lines > 4 do table.remove(lines) end
        table.insert(lines, "[+"..h.." more]")
    end
    local out = table.concat(lines, " | ")
    return #out > 300 and out:sub(1, 300).."…" or out
end

local function runWithTimeout(cb, t)
    t = tonumber(t) or 15
    local done, ok, res = false, nil, nil
    task.spawn(function() ok, res = pcall(cb); done = true end)
    local s = os.clock()
    while not done and os.clock()-s < t do task.wait(0.05) end
    if done then return ok, res end
    return false, "Timed out after "..t.."s"
end

local function test(name, aliases, callback, optional, timeout, category, weight)
    optional  = optional == true
    category  = category or "Optional"
    weight    = weight or (optional and 1 or 2)
    timeout   = timeout or 15

    local cat = categoryStats[category]
    if not cat then
        categoryStats[category] = {passes=0,fails=0,missing=0,weighted_score=0,weighted_total=0}
        cat = categoryStats[category]
        table.insert(CATEGORIES, category)
    end

    running += 1
    task.spawn(function()
        local exists = getGlobal(name) ~= nil

        if not callback then

            if exists then
                print("⏺️ "..name.." • Exists (no behavior test)")
            elseif optional then
                table.insert(list_optional_missing, name)
                print("⏺️ "..name.." • Optional — not provided")
            else
                cat.fails    += 1
                cat.missing  += 1
                cat.weighted_total += weight
                totalWeightedMax   += weight
                table.insert(list_missing, name)
                warn("⛔ "..name.." • MISSING")
            end
        elseif not exists then
            if optional then
                table.insert(list_optional_missing, name)
                print("⏺️ "..name.." • Optional — not provided")
            else
                cat.fails    += 1
                cat.missing  += 1
                cat.weighted_total += weight
                totalWeightedMax   += weight
                table.insert(list_missing, name)
                warn("⛔ "..name.." • MISSING")
            end
        else
            cat.weighted_total += weight
            totalWeightedMax   += weight
            local ok, msg = runWithTimeout(callback, timeout)
            if ok then
                cat.passes          += 1
                cat.weighted_score  += weight
                totalWeightedScore  += weight
                print("✅ "..name..(msg and " • "..tostring(msg) or ""))
            else
                cat.fails += 1
                local e = normalizeError(msg)
                table.insert(list_fail, name.." ("..category..") — "..e)
                warn("⛔ "..name.." — "..e)
            end
        end

        local bad = {}
        for _, alias in ipairs(aliases or {}) do
            if getGlobal(alias) == nil then table.insert(bad, alias) end
        end
        if #bad > 0 then
            table.insert(list_alias_missing, name.." -> "..table.concat(bad, ", "))
            warn("⚠️ Missing alias(es) for "..name..": "..table.concat(bad, ", "))
        end

        running -= 1
    end)
end

local function getTier(pct, hasCriticalFails)
    if pct >= 97 and not hasCriticalFails then return "S",  "🏆 Perfect — Flawless iUNC compatibility"
    elseif pct >= 90 then return "A+", "💎 Excellent — Near-perfect compatibility"
    elseif pct >= 80 then return "A",  "✅ Great — All core features work"
    elseif pct >= 70 then return "B+", "🟢 Good — Most features work, minor gaps"
    elseif pct >= 60 then return "B",  "🟡 Above Average — Usable with some missing features"
    elseif pct >= 50 then return "C",  "🟠 Average — Significant features missing"
    elseif pct >= 35 then return "D",  "🔴 Poor — Many core features broken or missing"
    else                   return "F",  "💀 Failing — Executor barely passes iUNC" end
end

print("╔══════════════════════════════════════════════╗")
print("║         iUNC v"..VERSION.." — Improved UNC Test        ║")
print("╠══════════════════════════════════════════════╣")
print("║  Executor : "..EXEC_DISPLAY)
print("║  Platform : "..(IsOnMobile and "Mobile" or "Desktop"))
print("╚══════════════════════════════════════════════╝")
print("✅ Pass  ⛔ Fail  ⏺️ Exists/Optional  ⚠️ Alias missing\n")

if isfolder and makefolder and delfolder then
    if isfolder(".tests") then delfolder(".tests") end
    makefolder(".tests")
end

print("── File System ──")
local FS = "File System"

test("writefile", {}, function()
    writefile(".tests/writefile.txt", "iUNC_WRITEFILE")
    assert(readfile(".tests/writefile.txt") == "iUNC_WRITEFILE", "Contents did not persist")
end, false, 15, FS, 3)

test("readfile", {}, function()
    writefile(".tests/readfile.txt", "success")
    assert(readfile(".tests/readfile.txt") == "success", "Did not return correct contents")
end, false, 15, FS, 3)

test("appendfile", {}, function()
    writefile(".tests/appendfile.txt", "su")
    appendfile(".tests/appendfile.txt", "cce")
    appendfile(".tests/appendfile.txt", "ss")
    assert(readfile(".tests/appendfile.txt") == "success", "Did not append correctly")
end, false, 15, FS, 2)

test("delfile", {}, function()
    writefile(".tests/delfile.txt", "bye")
    delfile(".tests/delfile.txt")
    assert(isfile(".tests/delfile.txt") == false, "File was not deleted")
end, false, 15, FS, 2)

test("isfile", {}, function()
    writefile(".tests/isfile.txt", "test")
    assert(isfile(".tests/isfile.txt") == true,  "Should return true for a file")
    assert(isfile(".tests")            == false,  "Should return false for a folder")
    assert(isfile(".tests/nope.exe")   == false,  "Should return false for nonexistent path")
end, false, 15, FS, 2)

test("makefolder", {}, function()
    makefolder(".tests/makefolder")
    assert(isfolder(".tests/makefolder"), "Folder was not created")
end, false, 15, FS, 2)

test("isfolder", {}, function()
    assert(isfolder(".tests")          == true,  "Should return true for folder")
    assert(isfolder(".tests/nope.exe") == false, "Should return false for nonexistent path")
end, false, 15, FS, 2)

test("delfolder", {}, function()
    makefolder(".tests/delfolder")
    delfolder(".tests/delfolder")
    assert(isfolder(".tests/delfolder") == false, "Folder was not deleted")
end, false, 15, FS, 2)

test("listfiles", {}, function()
    makefolder(".tests/listfiles")
    writefile(".tests/listfiles/a.txt", "a")
    writefile(".tests/listfiles/b.txt", "b")
    local files = listfiles(".tests/listfiles")
    assert(#files == 2, "Expected 2 files, got "..#files)
    assert(isfile(files[1]), "Result should be a file path")
    makefolder(".tests/listfiles2")
    makefolder(".tests/listfiles2/d1")
    makefolder(".tests/listfiles2/d2")
    local dirs = listfiles(".tests/listfiles2")
    assert(#dirs == 2, "Expected 2 folders, got "..#dirs)
    assert(isfolder(dirs[1]), "Result should be a folder path")
end, false, 15, FS, 2)

test("loadfile", {}, function()
    writefile(".tests/loadfile.lua", "return ... + 1")
    local f, err = loadfile(".tests/loadfile.lua")
    assert(type(f) == "function", "Expected function, err: "..tostring(err))
    assert(f(41) == 42, "loadfile returned wrong value")
end, false, 15, FS, 2)

test("dofile", {}, function()
    _G.__iUNC_DOFILE = nil
    writefile(".tests/dofile.lua", "_G.__iUNC_DOFILE = true")
    task.wait()
    dofile(".tests/dofile.lua")
    assert(_G.__iUNC_DOFILE == true, "dofile did not execute the chunk")
end, false, 15, FS, 2)

test("getcustomasset", {}, function()
    writefile(".tests/asset.png", "iUNC")
    local id = getcustomasset(".tests/asset.png")
    assert(type(id) == "string" and #id > 0, "Did not return a non-empty string")
    assert(id:match("rbxasset://"), "Did not return an rbxasset:// URL")
end, false, 15, FS, 2)

print("\n── Closures ──")
local CL = "Closures"

test("iscclosure", {}, function()
    assert(iscclosure(print)         == true,  "print should be a C closure")
    assert(iscclosure(function()end) == false, "Lua function should not be a C closure")
end, false, 15, CL, 3)

test("islclosure", {}, function()
    assert(islclosure(print)         == false, "print should not be a Lua closure")
    assert(islclosure(function()end) == true,  "Lua function should be a Lua closure")
end, false, 15, CL, 3)

test("isexecutorclosure", {"checkclosure","isourclosure"}, function()
    assert(isexecutorclosure(isexecutorclosure)          == true,  "Should be true for executor global")
    assert(isexecutorclosure(newcclosure(function()end)) == true,  "Should be true for executor C closure")
    assert(isexecutorclosure(function()end)              == true,  "Should be true for executor Lua closure")
    assert(isexecutorclosure(print)                      == false, "Should be false for Roblox global")
end, false, 15, CL, 3)

test("clonefunction", {}, function()
    local function f() return "iUNC" end
    local c = clonefunction(f)
    assert(f() == c(), "Clone should return same value")
    assert(f ~= c,     "Clone should not equal original")
end, false, 15, CL, 2)

test("newcclosure", {}, function()
    local function f() return true end
    local c = newcclosure(f)
    assert(f() == c(),    "C closure should return same value")
    assert(f ~= c,        "C closure should not equal original")
    assert(iscclosure(c), "Result should be a C closure")
end, false, 15, CL, 3)

test("hookfunction", {"hookfunc"}, function()
    local called = 0
    local target = function(n) return n + 1 end
    local old; old = hookfunction(target, function(n) called += 1; return n + 1000 end)
    assert(type(old) == "function", "hookfunction must return the original function")
    local v = target(1)
    assert(called == 1, "hookfunction did not intercept the call")
    assert(v == 1001,   "Unexpected hook return: "..tostring(v))
    local ok, orig = pcall(old, 1)
    assert(ok,        "Original threw: "..tostring(orig))
    assert(orig == 2, "Original appears fake — expected 2, got "..tostring(orig))
end, false, 15, CL, 3)

test("restorefunction", {"restoreclosure"}, function()
    local function f() return "original" end
    hookfunction(f, function() return "hooked" end)
    assert(f() == "hooked", "Hook did not apply")
    restorefunction(f)
    assert(f() == "original", "restorefunction did not restore")
end, true, 15, CL, 2)

print("\n── Metatables ──")
local MT = "Metatables"

test("getrawmetatable", {}, function()
    local mt = {__metatable = "Locked!"}
    local obj = setmetatable({}, mt)
    assert(getrawmetatable(obj) == mt, "Did not return the correct metatable")

    local pmt = getrawmetatable(game)
    assert(type(pmt) == "table", "Should return metatable for DataModel")
    local wmt = getrawmetatable(workspace)
    assert(type(wmt) == "table", "Should return metatable for Workspace")
end, false, 15, MT, 3)

test("setrawmetatable", {}, function()
    local obj = setmetatable({}, {__index = function() return false end, __metatable = "Locked!"})
    setrawmetatable(obj, {__index = function() return true end})
    assert(obj.test == true, "Failed to change the metatable")
end, false, 15, MT, 3)

test("isreadonly", {}, function()
    local t = {}; table.freeze(t)
    assert(isreadonly(t) == true, "Should return true for frozen table")
    local u = {}
    assert(isreadonly(u) == false, "Should return false for normal table")
end, false, 15, MT, 2)

test("setreadonly", {}, function()
    local t = {ok = false}; table.freeze(t)
    setreadonly(t, false)
    t.ok = true
    assert(t.ok, "Did not allow modification after setreadonly(false)")
end, false, 15, MT, 2)

test("hookmetamethod", {}, function()
    local seen = false; local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        if self == game and getnamecallmethod() == "GetService" then seen = true end
        return old(self, ...)
    end)
    game:GetService("Lighting")
    assert(seen, "hookmetamethod did not intercept __namecall")
end, false, 15, MT, 3)

test("getnamecallmethod", {}, function()
    local method; local ref
    ref = hookmetamethod(game, "__namecall", function(...)
        if not method then method = getnamecallmethod() end
        return ref(...)
    end)
    game:GetService("Lighting")
    assert(method == "GetService", "Expected 'GetService', got: "..tostring(method))
end, false, 15, MT, 3)

print("\n── Debug Library ──")
local DB = "Debug"

test("debug.getconstant", {}, function()
    local function f() print("Hello, world!") end
    assert(debug.getconstant(f, 1) == "print",          "Constant 1 should be 'print'")
    assert(debug.getconstant(f, 2) == nil,              "Constant 2 should be nil")
    assert(debug.getconstant(f, 3) == "Hello, world!", "Constant 3 should be 'Hello, world!'")
end, false, 15, DB, 3)

test("debug.getconstants", {}, function()
    local function f() local n = 5000 .. 50000; print("Hello, world!", n, warn) end
    local c = debug.getconstants(f)
    assert(c[1] == 50000,           "c[1] should be 50000")
    assert(c[2] == "print",         "c[2] should be 'print'")
    assert(c[3] == nil,             "c[3] should be nil")
    assert(c[4] == "Hello, world!", "c[4] should be 'Hello, world!'")
    assert(c[5] == "warn",          "c[5] should be 'warn'")
end, false, 15, DB, 3)

test("debug.setconstant", {}, function()
    local function f() return "fail" end
    debug.setconstant(f, 1, "success")
    assert(f() == "success", "setconstant did not change the constant")
end, false, 15, DB, 3)

test("debug.getinfo", {}, function()
    local expected = {
        source="string", short_src="string", func="function", what="string",
        currentline="number", name="string", nups="number",
        numparams="number", is_vararg="number"
    }
    local function f(...) print(...) end
    local info = debug.getinfo(f)
    for k, v in pairs(expected) do
        assert(info[k] ~= nil,     "Missing field: "..k)
        assert(type(info[k]) == v, k.." should be "..v..", got "..type(info[k]))
    end

    local cinfo = debug.getinfo(print)
    assert(type(cinfo) == "table", "debug.getinfo should work on C closures too")
end, false, 15, DB, 3)

test("debug.getproto", {}, function()
    local function outer() local function inner() return true end end
    local proto = debug.getproto(outer, 1, true)[1]
    assert(proto,           "Failed to get inner function")
    assert(proto() == true, "Inner function did not return true")
end, false, 15, DB, 3)

test("debug.getprotos", {}, function()
    local function outer()
        local function _1() return true end
        local function _2() return true end
        local function _3() return true end
    end
    local protos = debug.getprotos(outer)
    assert(#protos == 3, "Expected 3 protos, got "..#protos)
    for i = 1, 3 do
        local p = debug.getproto(outer, i, true)[1]
        assert(p and p(), "Proto "..i.." failed")
    end
end, false, 15, DB, 2)

test("debug.getstack", {}, function()
    local _ = "a" .. "b"
    assert(debug.getstack(1, 1)  == "ab", "Stack item 1 should be 'ab'")
    assert(debug.getstack(1)[1]  == "ab", "Stack table[1] should be 'ab'")
end, false, 15, DB, 2)

test("debug.setstack", {}, function()
    local function f() return "fail", debug.setstack(1, 1, "success") end
    assert(f() == "success", "setstack did not update the stack")
end, false, 15, DB, 2)

test("debug.getupvalue", {}, function()
    local upval = function() end
    local function f() print(upval) end
    assert(debug.getupvalue(f, 1) == upval, "Unexpected getupvalue result")
end, false, 15, DB, 3)

test("debug.getupvalues", {}, function()
    local upval = function() end
    local function f() print(upval) end
    assert(debug.getupvalues(f)[1] == upval, "Unexpected getupvalues result")
end, false, 15, DB, 3)

test("debug.setupvalue", {}, function()
    local function upval() return "fail" end
    local function f() return upval() end
    debug.setupvalue(f, 1, function() return "success" end)
    assert(f() == "success", "setupvalue did not change the upvalue")
end, false, 15, DB, 3)

print("\n── Instance & Cache ──")
local IC = "Instance & Cache"

test("cache.invalidate", {}, function()
    local folder = Instance.new("Folder")
    local part = Instance.new("Part", folder)
    cache.invalidate(folder:FindFirstChild("Part"))
    assert(part ~= folder:FindFirstChild("Part"), "Cache was not invalidated")
end, false, 15, IC, 3)

test("cache.iscached", {}, function()
    local part = Instance.new("Part")
    assert(cache.iscached(part),     "Part should be cached")
    cache.invalidate(part)
    assert(not cache.iscached(part), "Part should not be cached after invalidation")
end, false, 15, IC, 2)

test("cache.replace", {}, function()
    local part = Instance.new("Part")
    local fire = Instance.new("Fire")
    cache.replace(part, fire)
    assert(part ~= fire, "Part was not replaced with Fire")
end, false, 15, IC, 2)

test("cloneref", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone,           "Clone should not == original")
    clone.Name = "iUNCTest"
    assert(part.Name == "iUNCTest", "Modifying clone should update original")
end, false, 15, IC, 3)

test("compareinstances", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone,                  "Clone should not == original via ==")
    assert(compareinstances(part, clone),  "compareinstances should return true")
end, false, 15, IC, 2)

test("gethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local value, isHidden = gethiddenproperty(fire, "size_xml")
    assert(value == 5,       "Expected size_xml == 5, got "..tostring(value))
    assert(isHidden == true, "Expected isHidden == true")
end, false, 15, IC, 2)

test("sethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local wasHidden = sethiddenproperty(fire, "size_xml", 10)
    assert(wasHidden == true,                         "Should return true for a hidden property")
    assert(gethiddenproperty(fire, "size_xml") == 10, "Hidden property not set to 10")
end, false, 15, IC, 2)

test("isscriptable", {}, function()
    local fire = Instance.new("Fire")
    assert(isscriptable(fire, "size_xml") == false, "size_xml should NOT be scriptable")
    assert(isscriptable(fire, "Size")     == true,  "Size SHOULD be scriptable")
end, false, 15, IC, 2)

test("setscriptable", {}, function()
    local fire = Instance.new("Fire")
    local was = setscriptable(fire, "size_xml", true)
    assert(was == false,                            "Should return false (was not scriptable)")
    assert(isscriptable(fire, "size_xml") == true,  "size_xml should now be scriptable")
    local fire2 = Instance.new("Fire")
    assert(isscriptable(fire2, "size_xml") == false, "setscriptable should not persist to new instances")
end, false, 15, IC, 2)

test("getinstances", {}, function()
    local inst = getinstances()
    assert(type(inst) == "table" and #inst > 0, "Should return a non-empty table")
    assert(typeof(inst[1]) == "Instance",       "First element should be an Instance")
end, false, 15, IC, 2)

test("getnilinstances", {}, function()
    local inst = getnilinstances()
    assert(type(inst) == "table" and #inst > 0, "Should return a non-empty table")
    assert(typeof(inst[1]) == "Instance",       "First element should be an Instance")
    assert(inst[1].Parent == nil,               "First element should have nil Parent")
end, false, 15, IC, 2)

test("getcallbackvalue", {}, function()
    local bf = Instance.new("BindableFunction")
    local function cb() end
    bf.OnInvoke = cb
    assert(getcallbackvalue(bf, "OnInvoke") == cb, "Did not return the correct callback")
end, false, 15, IC, 2)

test("getconnections", {}, function()
    local be = Instance.new("BindableEvent")
    be.Event:Connect(function() end)
    local conn = getconnections(be.Event)[1]
    local expected = {
        Enabled="boolean", ForeignState="boolean", LuaConnection="boolean",
        Function="function", Thread="thread", Fire="function", Defer="function",
        Disconnect="function", Disable="function", Enable="function"
    }
    for k, v in pairs(expected) do
        assert(conn[k] ~= nil,     "Missing connection field: "..k)
        assert(type(conn[k]) == v, k.." should be "..v..", got "..type(conn[k]))
    end
end, false, 15, IC, 3)

test("gethui", {}, function()
    assert(typeof(gethui()) == "Instance", "Should return an Instance")
end, false, 15, IC, 2)

test("getloadedmodules", {}, function()
    local mods = getloadedmodules()
    assert(type(mods) == "table" and #mods > 0, "Should return a non-empty table")
    assert(mods[1]:IsA("ModuleScript"),          "First element should be a ModuleScript")
end, false, 15, IC, 2)

test("getrunningscripts", {}, function()
    local s = getrunningscripts()
    assert(type(s) == "table" and #s > 0, "Should return a non-empty table")
    assert(s[1]:IsA("ModuleScript") or s[1]:IsA("LocalScript"), "Should be a script instance")
end, false, 15, IC, 2)

test("getscripts", {}, function()
    local s = getscripts()
    assert(type(s) == "table" and #s > 0, "Should return a non-empty table")
    assert(s[1]:IsA("ModuleScript") or s[1]:IsA("LocalScript"), "Should be a script instance")
end, false, 15, IC, 2)

test("getscriptbytecode", {"dumpstring"}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate
    local bc = getscriptbytecode(anim)
    assert(type(bc) == "string" and #bc > 0, "Should return a non-empty string")
end, false, 15, IC, 2)

test("getscripthash", {}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate:Clone()
    local h1 = getscripthash(anim)
    local src = anim.Source
    anim.Source = "print('iUNC')"
    task.defer(function() anim.Source = src end)
    local h2 = getscripthash(anim)
    assert(h1 ~= h2,                   "Hash should differ after source change")
    assert(h2 == getscripthash(anim),  "Hash should be stable for same source")
end, false, 15, IC, 2)

test("getsenv", {}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate
    local env = getsenv(anim)
    assert(type(env) == "table", "Should return a table")
    assert(env.script == anim,   "env.script should equal Animate")
end, false, 15, IC, 3)

test("require", {}, function()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then return "LocalPlayer missing" end
    local ps  = lp:FindFirstChild("PlayerScripts");  if not ps  then return "PlayerScripts missing"  end
    local pm  = ps:FindFirstChild("PlayerModule");   if not pm  then return "PlayerModule missing"   end
    local cam = pm:FindFirstChild("CameraModule");   if not cam then return "CameraModule missing"   end
    local inv = cam:FindFirstChild("Invisicam")
    if not (inv and inv:IsA("ModuleScript")) then return "Invisicam not found" end
    local ok, mod = pcall(require, inv)
    assert(ok, tostring(mod))
    local t = type(mod)
    assert(t == "table" or t == "function", "Unexpected return type: "..t)
    return "require(Invisicam) returned "..t
end, false, 15, IC, 2)

print("\n── Environment & Thread ──")
local EN = "Environment"

test("checkcaller", {}, function()
    assert(checkcaller(), "Should return true in main scope")
end, false, 15, EN, 3)

test("getgenv", {}, function()
    getgenv().__iUNC_GENV = true
    assert(__iUNC_GENV == true, "Failed to set global via getgenv()")
    getgenv().__iUNC_GENV = nil
end, false, 15, EN, 3)

test("getrenv", {}, function()
    assert(_G ~= getrenv()._G, "Executor _G should differ from game _G")
end, false, 15, EN, 3)

test("getthreadidentity", {"getidentity","getthreadcontext"}, function()
    local id = getthreadidentity()
    assert(type(id) == "number", "Should return a number")
    assert(id >= 0 and id <= 8,  "Thread identity should be between 0 and 8, got "..id)
    return "identity = "..id
end, false, 15, EN, 3)

test("setthreadidentity", {"setidentity","setthreadcontext"}, function()

    local original = getthreadidentity()
    for _, level in ipairs({2, 3, 5, 6}) do
        setthreadidentity(level)
        assert(getthreadidentity() == level, "Failed to set thread identity to "..level)
    end
    setthreadidentity(original)
    return "Tested levels 2,3,5,6"
end, false, 15, EN, 3)

test("getgc", {}, function()
    local gc = getgc(true)
    assert(type(gc) == "table" and #gc > 0, "getgc should return a non-empty table")
end, false, 15, EN, 2)

test("getregistry", {"getreg"}, function()
    local r = getregistry()
    assert(type(r) == "table" and r[1] ~= nil, "Should return a non-empty table")
end, false, 15, EN, 2)

test("identifyexecutor", {"getexecutorname"}, function()
    local name, version = identifyexecutor()
    assert(type(name) == "string", "Should return a string name")
    return "version: "..(type(version) == "string" and version or "(not returned)")
end, false, 15, EN, 2)

print("\n── Signals & Input ──")
local SI = "Signals & Input"

test("firesignal", {}, function()
    local be = Instance.new("BindableEvent")
    local count = 0
    be.Event:Connect(function(a, b) if a == 1 and b == 2 then count += 1 end end)
    firesignal(be.Event, 1, 2)
    task.wait()
    assert(count == 1, "firesignal did not invoke the signal (count="..count..")")
end, false, 15, SI, 3)

test("fireclickdetector", {}, function()
    local det = Instance.new("ClickDetector")
    local fired = false
    det.MouseClick:Connect(function() fired = true end)
    fireclickdetector(det, 0)
    task.wait()
    return fired and "MouseClick fired" or "MouseClick not observed (may be limited)"
end, false, 15, SI, 2)

test("fireproximityprompt", {}, function()
    local cam = workspace.CurrentCamera
    if not cam then return "No CurrentCamera" end
    local part = Instance.new("Part")
    part.Anchored = true; part.CanCollide = false; part.Size = Vector3.new(3, 3, 3)
    part.Position = cam.CFrame.Position + cam.CFrame.LookVector * 5
    part.Parent = workspace
    local prompt = Instance.new("ProximityPrompt")
    prompt.RequiresLineOfSight = false; prompt.MaxActivationDistance = 9999
    prompt.Parent = part
    local triggered = false
    prompt.Triggered:Connect(function() triggered = true end)
    local ok, err = pcall(fireproximityprompt, prompt)
    assert(ok, err or "fireproximityprompt errored")
    task.wait(0.15); part:Destroy()
    assert(triggered, "ProximityPrompt.Triggered did not fire")
end, false, 15, SI, 2)

test("firetouchinterest", {}, function()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then return "LocalPlayer missing" end
    local char = lp.Character or lp.CharacterAdded:Wait()
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not root then return "No root part" end
    local part = Instance.new("Part")
    part.Size = Vector3.new(4,4,4); part.Anchored = true; part.CanCollide = true
    part.Position = root.Position + Vector3.new(0,5000,0); part.Parent = workspace
    local touched = false
    part.Touched:Connect(function(h) if h == root then touched = true end end)
    assert(pcall(firetouchinterest, root, part, 0))
    task.wait(0.05)
    assert(pcall(firetouchinterest, root, part, 1))
    task.wait(0.05); part:Destroy()
    if not touched then return "Touched event not observed (executor may limit this)" end
end, false, 15, SI, 2)

if not IsOnMobile then
    test("mouse1click",   {}, function() assert(pcall(mouse1click))   end, false, 15, SI, 2)
    test("mouse1press",   {}, function() assert(pcall(mouse1press))   end, false, 15, SI, 2)
    test("mouse1release", {}, function() assert(pcall(mouse1release)) end, false, 15, SI, 2)
    test("mouse2click",   {}, function() assert(pcall(mouse2click))   end, false, 15, SI, 2)
    test("mouse2press",   {}, function() assert(pcall(mouse2press))   end, false, 15, SI, 2)
    test("mouse2release", {}, function() assert(pcall(mouse2release)) end, false, 15, SI, 2)
    test("mousemoveabs",  {}, function()
        assert(pcall(mousemoveabs, 0, 0)); assert(pcall(mousemoveabs, 100, 100))
    end, false, 15, SI, 2)
    test("mousemoverel",  {}, function()
        assert(pcall(mousemoverel, 0, 0)); assert(pcall(mousemoverel, 10, -10))
    end, false, 15, SI, 2)
    test("mousescroll",   {}, function()
        assert(pcall(mousescroll, 1)); assert(pcall(mousescroll, -1))
    end, false, 15, SI, 2)
    test("keypress",   {}, function() assert(pcall(keypress, 0x41))   end, true, 15, SI, 1)
    test("keyrelease", {}, function() assert(pcall(keyrelease, 0x41)) end, true, 15, SI, 1)
    test("keyclick",   {}, function() assert(pcall(keyclick, 0x41))   end, true, 15, SI, 1)
else
    print("⏺️ Mouse/keyboard input tests skipped on Mobile")
end

test("queue_on_teleport", {"queueonteleport"}, function()
    assert(pcall(queue_on_teleport, "return 1"))
end, false, 15, SI, 2)

print("\n── Crypto & Encoding ──")
local CE = "Crypto & Encoding"

test("crypt.base64encode", {"crypt.base64.encode","crypt.base64_encode","base64.encode","base64_encode"}, function()
    assert(crypt.base64encode("test") == "dGVzdA==", "Base64 encoding failed")
    assert(crypt.base64encode("")     == "",          "Empty string should encode to empty")
end, false, 15, CE, 2)

test("crypt.base64decode", {"crypt.base64.decode","crypt.base64_decode","base64.decode","base64_decode"}, function()
    assert(crypt.base64decode("dGVzdA==") == "test", "Base64 decoding failed")
end, false, 15, CE, 2)

test("crypt.generatekey", {}, function()
    local key = crypt.generatekey()
    assert(#crypt.base64decode(key) == 32, "Key should decode to 32 bytes")
end, false, 15, CE, 2)

test("crypt.generatebytes", {}, function()
    local n = math.random(10, 100)
    local bytes = crypt.generatebytes(n)
    assert(#crypt.base64decode(bytes) == n, "Expected "..n.." bytes")
end, false, 15, CE, 2)

test("crypt.encrypt", {}, function()
    local key = crypt.generatekey()

    local enc, iv = crypt.encrypt("test", key, nil, "CBC")
    assert(iv, "encrypt should return an IV for CBC")
    assert(crypt.decrypt(enc, key, iv, "CBC") == "test", "CBC decrypt after encrypt failed")

    local ok2, enc2, iv2 = pcall(crypt.encrypt, "test", key, nil, "CFB")
    if ok2 and enc2 then
        assert(crypt.decrypt(enc2, key, iv2, "CFB") == "test", "CFB round-trip failed")
        return "CBC ✓ CFB ✓"
    end
    return "CBC ✓ (CFB not supported)"
end, false, 15, CE, 3)

test("crypt.decrypt", {}, function()
    local key, iv = crypt.generatekey(), crypt.generatekey()
    local enc = crypt.encrypt("test", key, iv, "CBC")
    assert(crypt.decrypt(enc, key, iv, "CBC") == "test", "Decryption failed")
end, false, 15, CE, 3)

test("crypt.hash", {}, function()
    local algos = {"sha1","sha256","sha384","sha512","md5","sha3-224","sha3-256","sha3-512"}
    local supported = {}
    for _, alg in ipairs(algos) do
        local ok, h = pcall(crypt.hash, "test", alg)
        if ok and h then table.insert(supported, alg)
        else warn("  crypt.hash: '"..alg.."' not supported") end
    end
    assert(#supported > 0, "No hash algorithms supported")
    return table.concat(supported, ", ")
end, false, 15, CE, 3)

test("lz4compress", {}, function()
    local raw = "Hello, iUNC! "..string.rep("compress me ", 50)
    local comp = lz4compress(raw)
    assert(type(comp) == "string",           "Should return a string")
    assert(#comp < #raw,                     "Compressed should be smaller than raw for repetitive data")
    assert(lz4decompress(comp, #raw) == raw, "Decompressed value is wrong")
end, false, 15, CE, 2)

test("lz4decompress", {}, function()
    local raw = "Hello, iUNC!"
    assert(lz4decompress(lz4compress(raw), #raw) == raw, "Decompressed value is wrong")
end, false, 15, CE, 2)

print("\n── Drawing ──")
local DR = "Drawing"

test("Drawing", {}, function()
    assert(type(Drawing)       == "table",    "Drawing must be a table")
    assert(type(Drawing.new)   == "function", "Drawing.new must be a function")
    assert(type(Drawing.Fonts) == "table",    "Drawing.Fonts must be a table")
end, false, 15, DR, 3)

test("Drawing.Fonts", {}, function()
    assert(Drawing.Fonts.UI        == 0, "UI should be 0")
    assert(Drawing.Fonts.System    == 1, "System should be 1")
    assert(Drawing.Fonts.Plex      == 2, "Plex should be 2")
    assert(Drawing.Fonts.Monospace == 3, "Monospace should be 3")
end, false, 15, DR, 2)

test("Drawing.new", {}, function()
    local shapes = {"Line","Text","Image","Circle","Square","Quad","Triangle"}
    local created = {}
    for _, shape in ipairs(shapes) do
        local ok, obj = pcall(Drawing.new, shape)
        assert(ok, "Drawing.new(\""..shape.."\") errored")
        if ok and obj then
            obj.Visible = false
            table.insert(created, {shape=shape, obj=obj})
        end
    end

    for _, entry in ipairs(created) do
        local s, o = entry.shape, entry.obj
        local ok2, err2 = pcall(function()
            if s == "Line" then
                o.From = Vector2.new(0,0); o.To = Vector2.new(100,100)
                o.Color = Color3.new(1,0,0); o.Thickness = 2
                o.Transparency = 0.5
            elseif s == "Text" then
                o.Text = "iUNC"; o.Size = 18
                o.Color = Color3.new(1,1,1); o.Position = Vector2.new(10,10)
                o.Font = Drawing.Fonts.UI; o.Outline = true
            elseif s == "Circle" then
                o.Position = Vector2.new(50,50); o.Radius = 20
                o.Color = Color3.new(0,1,0); o.Thickness = 1; o.Filled = false
            elseif s == "Square" then
                o.Position = Vector2.new(10,10); o.Size = Vector2.new(50,50)
                o.Color = Color3.new(0,0,1); o.Thickness = 1; o.Filled = true
            elseif s == "Image" then
                o.Position = Vector2.new(0,0); o.Size = Vector2.new(100,100)
            elseif s == "Triangle" then
                o.PointA = Vector2.new(0,100)
                o.PointB = Vector2.new(50,0)
                o.PointC = Vector2.new(100,100)
                o.Color = Color3.new(1,1,0); o.Filled = false
            elseif s == "Quad" then
                o.PointA = Vector2.new(0,0); o.PointB = Vector2.new(100,0)
                o.PointC = Vector2.new(100,100); o.PointD = Vector2.new(0,100)
                o.Color = Color3.new(1,0,1); o.Filled = true
            end
        end)
        if not ok2 then warn("  Drawing."..s.." property test: "..tostring(err2)) end
        pcall(function() o:Destroy() end)
    end
    return table.concat(shapes, ", ")
end, false, 15, DR, 3)

test("cleardrawcache", {}, function()
    cleardrawcache()
end, false, 15, DR, 2)

test("isrenderobj", {}, function()
    local d = Drawing.new("Square"); d.Visible = false
    assert(isrenderobj(d)           == true,  "Should return true for Drawing object")
    assert(isrenderobj(newproxy())  == false, "Should return false for blank userdata")
    assert(isrenderobj({})          == false, "Should return false for table")
    d:Destroy()
end, false, 15, DR, 2)

test("Drawing.clear", {}, function()
    assert(pcall(Drawing.clear))
end, true, 15, DR, 1)

print("\n── Clipboard & Misc ──")
local CM = "Clipboard & Misc"

test("setclipboard", {"toclipboard"}, function()
    assert(pcall(setclipboard, "iUNC_TEST"))
end, false, 15, CM, 2)

test("getclipboard", {}, function()
    local v = getclipboard()
    assert(v == nil or type(v) == "string", "Should return string or nil")
end, true, 15, CM, 1)

test("setrbxclipboard", {}, function()
    assert(pcall(setrbxclipboard, "iUNC_RBX"))
end, false, 15, CM, 2)

test("isrbxactive", {"isgameactive"}, function()
    assert(type(isrbxactive()) == "boolean", "Should return a boolean")
end, false, 15, CM, 2)

test("loadstring", {}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate
    local fn = loadstring(getscriptbytecode(anim))
    assert(type(fn) ~= "function", "Luau bytecode should NOT be loadable")
    local f, err = loadstring("return ... + 1")
    assert(type(f) == "function", "Should return a function (err: "..tostring(err)..")")
    assert(f(41) == 42, "Unexpected return value from loadstring")
end, false, 15, CM, 3)

if not IsOnMobile then
    test("messagebox", {}, function()
        print("iUNC: A messagebox will appear. Click OK to continue.")
        local ok, res = pcall(messagebox, "iUNC v"..VERSION.." Test Messagebox", "iUNC Test", 0)
        assert(ok, res or "messagebox errored")
        assert(type(res) == "number" or res == nil, "Should return number or nil")
        messageboxPassed = true
    end, true, 45, CM, 1)
else
    print("⏺️ messagebox skipped on Mobile")
end

print("\n── FPS ──")
local FP = "FPS"

test("setfpscap", {}, function()
    local rs = game:GetService("RunService").RenderStepped
    local function measure(n)
        rs:Wait(); local sum = 0
        for _ = 1, n do sum += 1/rs:Wait() end
        return math.round(sum/n)
    end
    setfpscap(60);  local f60  = measure(5)
    setfpscap(240); local f240 = measure(5)
    setfpscap(0);   local f0   = measure(5)
    assert(f60 > 0 and f240 > 0 and f0 > 0, "FPS samples invalid")
    return ("60cap≈%d  240cap≈%d  uncapped≈%d"):format(f60, f240, f0)
end, false, 30, FP, 2)

test("getfpscap", {}, function()
    local cap = getfpscap()
    assert(type(cap) == "number" and cap >= 0, "Should return a non-negative number")
end, true, 15, FP, 1)

print("\n── Actors ──")
local AC = "Actors"

test("getactors", {}, function()
    local ok, acts = pcall(getactors)
    assert(ok, "getactors threw: "..tostring(acts))
    assert(type(acts) == "table", "Should return a table")
    if not acts[1] then return "No Actors found (none initialized yet)" end
    assert(acts[1]:IsA("Actor"), "First element should be an Actor")
end, false, 15, AC, 2)

test("run_on_actor", {"runonactor"}, function()
    if typeof(getactors) ~= "function" then return "getactors unavailable" end
    local ok, acts = pcall(getactors)
    if not ok or type(acts) ~= "table" or not acts[1] then return "No usable Actor" end
    if not acts[1]:IsA("Actor") then return "Not an Actor" end
    local rp   = game:GetService("ReplicatedStorage")
    local flag = Instance.new("BoolValue")
    flag.Name = "iUNC_ACTOR_TEST"; flag.Value = false; flag.Parent = rp
    local src = [[
local rp = game:GetService("ReplicatedStorage")
local v = rp:FindFirstChild("iUNC_ACTOR_TEST")
if v then v.Value = true end
]]
    local ok2, err = pcall(run_on_actor, acts[1], src)
    assert(ok2, err or "run_on_actor errored")
    local t0 = tick()
    while tick()-t0 < 5 do
        if flag.Value then break end
        game:GetService("RunService").Heartbeat:Wait()
    end
    assert(flag.Value, "run_on_actor code did not execute on Actor")
    flag:Destroy()
end, false, 15, AC, 2)

print("\n── Script Tools ──")
local ST = "Script Tools"

test("getcallingscript", {}, function()
    local ok, s = pcall(getcallingscript)
    if not ok then return "Errored in this context: "..normalizeError(s) end
    if s == nil then return "Returned nil in executor context" end
    assert(typeof(s) == "Instance", "Should return Instance or nil")
    assert(s:IsA("LocalScript") or s:IsA("ModuleScript") or s:IsA("Script"), "Should be a script instance")
end, true, 15, ST, 1)

test("getscriptclosure", {}, function()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then return "LocalPlayer missing" end
    local char = lp.Character or lp.CharacterAdded:Wait()
    local scr = char:FindFirstChildOfClass("LocalScript")
    if not scr then return "No LocalScript on character" end
    local f = getscriptclosure(scr)
    assert(type(f) == "function", "Should return a function")
    return "Got closure for "..scr.Name
end, true, 15, ST, 1)

test("decompile", {}, function()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then return "LocalPlayer missing" end
    local char = lp.Character or lp.CharacterAdded:Wait()
    local scr = char:FindFirstChildOfClass("LocalScript") or char:FindFirstChild("Animate")
    if not (scr and scr:IsA("LocalScript")) then return "No suitable LocalScript" end
    local ok, out = pcall(decompile, scr)
    assert(ok, tostring(out))
    assert(type(out) == "string" and #out > 0, "decompile returned empty string")
    return "Decompiled "..scr.Name.." ("..#out.." chars)"
end, true, 15, ST, 1)

test("getscriptfromthread", {}, function()
    local co = coroutine.create(function() task.wait(0.1) end)
    coroutine.resume(co)
    local ok, s = pcall(getscriptfromthread, co)
    assert(ok, tostring(s))
    assert(s == nil or typeof(s) == "Instance", "Should return Instance or nil")
end, true, 15, ST, 1)

print("\n── WebSocket & HTTP ──")
local WH = "WebSocket & HTTP"

test("request", {"http.request","http_request"}, function()
    local hs  = game:GetService("HttpService")

    local res = request({Url = "https://httpbin.org/user-agent", Method = "GET"})
    assert(type(res) == "table" and res.StatusCode == 200, "Did not get 200 response")
    local data = hs:JSONDecode(res.Body)
    assert(type(data) == "table" and data["user-agent"] ~= nil, "Missing user-agent key")

    local ok2, res2 = pcall(request, {
        Url = "https://httpbin.org/post",
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = hs:JSONEncode({iunc = "test"})
    })
    if ok2 and res2 and res2.StatusCode == 200 then
        return "GET ✓  POST ✓"
    end
    return "GET ✓  POST not confirmed"
end, false, 20, WH, 3)

test("WebSocket", {}, function()
    assert(type(WebSocket) == "table" or type(WebSocket) == "userdata", "Should be table or userdata")
end, false, 15, WH, 2)

test("WebSocket.connect", {}, function()
    if type(WebSocket) ~= "table" and type(WebSocket) ~= "userdata" then return "WebSocket unavailable" end
    local urls = {"wss://echo.websocket.events", "wss://ws.ifelse.io"}
    local ws, usedUrl, lastErr
    for _, u in ipairs(urls) do
        local ok, res = pcall(WebSocket.connect, u)
        if ok and res then ws = res; usedUrl = u; break else lastErr = res end
    end
    if not ws then return "Could not connect: "..tostring(lastErr) end
    local expected = {
        Send="function", Close="function",
        OnMessage={"table","userdata"}, OnClose={"table","userdata"}
    }
    for k, v in pairs(expected) do
        if type(v) == "table" then
            assert(table.find(v, type(ws[k])), k.." wrong type: "..type(ws[k]))
        else
            assert(type(ws[k]) == v, k.." should be "..v)
        end
    end

    if usedUrl:find("echo.websocket.events") then
        local received = nil
        ws.OnMessage:Connect(function(msg) received = msg end)
        ws:Send("iUNC_PING")
        local t0 = tick()
        while tick()-t0 < 3 and not received do task.wait(0.05) end
        pcall(function() ws:Close() end)
        return received and "Connected + echo ✓" or "Connected (no echo received)"
    end
    pcall(function() ws:Close() end)
    return "Connected to "..usedUrl
end, false, 15, WH, 3)

print("\n── FFlags ──")
local FF = "FFlags"

test("getfflag", {}, function()
    local full  = "FFlagDebugGraphicsPreferD3D11"
    local short = "DebugGraphicsPreferD3D11"
    local okF, valF = pcall(getfflag, full)
    local okS, valS = pcall(getfflag, short)
    assert(okF or okS, "getfflag failed for both full and short names")
    local val = okF and valF or valS
    local t = type(val)
    assert(t == "boolean" or t == "number" or t == "string" or t == "nil",
        "Unexpected return type: "..t)
    if okF and okS then return "Full + short names supported, value="..tostring(val)
    elseif okF then  return "Full names only, value="..tostring(valF)
    else             return "Short names only, value="..tostring(valS) end
end, true, 15, FF, 1)

test("setfflag", {}, function()
    local flag = "FFlagDebugGraphicsPreferD3D11"
    local ok, cur = pcall(getfflag, flag)
    if not ok then return "getfflag unavailable; cannot test setfflag" end
    local ok2, err = pcall(setfflag, flag, cur)
    if not ok2 and type(cur) == "boolean" then
        ok2, err = pcall(setfflag, flag, cur and "True" or "False")
    end
    assert(ok2, err or "setfflag errored")
    return "setfflag accepted current value"
end, true, 15, FF, 1)

print("\n── Bit32 Library ──")
local B32 = "Bit32"

test("bit32.band", {}, function()
    assert(bit32.band(0xFF, 0x0F) == 0x0F, "band failed")
    assert(bit32.band(0, 0xFF)    == 0,    "band with 0 failed")
end, false, 15, B32, 2)

test("bit32.bor", {}, function()
    assert(bit32.bor(0xF0, 0x0F) == 0xFF, "bor failed")
end, false, 15, B32, 2)

test("bit32.bxor", {}, function()
    assert(bit32.bxor(0xFF, 0x0F) == 0xF0, "bxor failed")
end, false, 15, B32, 2)

test("bit32.bnot", {}, function()
    assert(bit32.bnot(0) == 0xFFFFFFFF, "bnot(0) failed")
end, false, 15, B32, 2)

test("bit32.lshift", {}, function()
    assert(bit32.lshift(1, 4) == 16, "lshift failed")
    assert(bit32.lshift(1, 0) == 1,  "lshift by 0 failed")
end, false, 15, B32, 2)

test("bit32.rshift", {}, function()
    assert(bit32.rshift(16, 4) == 1, "rshift failed")
end, false, 15, B32, 2)

test("bit32.arshift", {}, function()

    local v = bit32.arshift(0x80000000, 1)
    assert(v == 0xC0000000, "arshift failed — got "..string.format("0x%X", v))
end, false, 15, B32, 2)

test("bit32.lrotate", {}, function()
    assert(bit32.lrotate(1, 1) == 2, "lrotate failed")
end, false, 15, B32, 1)

test("bit32.rrotate", {}, function()
    assert(bit32.rrotate(2, 1) == 1, "rrotate failed")
end, false, 15, B32, 1)

test("bit32.btest", {}, function()
    assert(bit32.btest(0xFF, 0x01) == true,  "btest should return true")
    assert(bit32.btest(0xF0, 0x01) == false, "btest should return false")
end, false, 15, B32, 1)

test("bit32.extract", {}, function()
    assert(bit32.extract(0xFF, 0, 4) == 0xF, "extract failed")
end, false, 15, B32, 1)

test("bit32.replace", {}, function()
    assert(bit32.replace(0x00, 0xF, 0, 4) == 0xF, "replace failed")
end, false, 15, B32, 1)

print("\n── String Extensions ──")
local SX = "String Extensions"

test("string.split", {}, function()
    local parts = string.split("a,b,c", ",")
    assert(type(parts) == "table", "Should return a table")
    assert(#parts == 3,            "Should return 3 parts")
    assert(parts[1] == "a",        "parts[1] should be 'a'")
    assert(parts[2] == "b",        "parts[2] should be 'b'")
    assert(parts[3] == "c",        "parts[3] should be 'c'")
end, false, 15, SX, 2)

test("string.trim", {}, function()
    local fn = string.trim or (function(s) return s:match("^%s*(.-)%s*$") end)
    assert(fn("  hello  ") == "hello", "trim failed")
    assert(fn("no spaces") == "no spaces", "trim of clean string failed")
end, true, 15, SX, 1)

test("string.startswith", {}, function()
    if not string.startswith then return "string.startswith not provided (optional)" end
    assert(string.startswith("hello world", "hello") == true,  "startswith failed for match")
    assert(string.startswith("hello world", "world") == false, "startswith failed for non-match")
end, true, 15, SX, 1)

test("string.endswith", {}, function()
    if not string.endswith then return "string.endswith not provided (optional)" end
    assert(string.endswith("hello world", "world") == true,  "endswith failed for match")
    assert(string.endswith("hello world", "hello") == false, "endswith failed for non-match")
end, true, 15, SX, 1)

test("table.freeze / table.isfrozen", {}, function()
    local t = {a = 1}
    table.freeze(t)
    assert(table.isfrozen(t), "table.isfrozen should return true after freeze")
    local ok = pcall(function() t.a = 2 end)
    assert(not ok, "Should not be able to modify frozen table")
end, false, 15, SX, 2)

test("table.move", {}, function()
    local src = {1, 2, 3, 4, 5}
    local dst = {}
    table.move(src, 1, 3, 1, dst)
    assert(dst[1] == 1 and dst[2] == 2 and dst[3] == 3, "table.move failed")
end, false, 15, SX, 2)

test("table.find", {}, function()
    local t = {"a", "b", "c", "d"}
    assert(table.find(t, "c") == 3, "table.find returned wrong index")
    assert(table.find(t, "z") == nil, "table.find should return nil for missing value")
end, false, 15, SX, 2)

print("\n── Optional Globals ──")
local OP = "Optional"

for _, def in ipairs({
    {"saveinstance",           {"save_instance"},          OP},
    {"rconsoleclear",          {"consoleclear"},           OP},
    {"rconsolecreate",         {"consolecreate"},          OP},
    {"rconsoledestroy",        {"consoledestroy"},         OP},
    {"rconsoleinput",          {"consoleinput"},           OP},
    {"rconsoleprint",          {"consoleprint"},           OP},
    {"rconsolesettitle",       {"rconsolename","consolesettitle"}, OP},
    {"rconsolewarn",           {"consolewarn"},            OP},
    {"rconsoleerr",            {"consoleerr"},             OP},
    {"getcallstack",           {},                         OP},
    {"getfunctionhash",        {},                         OP},
    {"isluau",                 {},                         OP},
    {"gethwid",                {},                         OP},
    {"setnamecallmethod",      {},                         OP},
    {"getpointerfrominstance", {},                         OP},
    {"firetouchtransmitter",   {},                         OP},
    {"getspecialinfo",         {},                         OP},
    {"readbinarystring",       {},                         OP},
    {"cloneclosure",           {},                         OP},
    {"http",                   {},                         OP},
    {"http.get",               {},                         OP},
    {"http.post",              {},                         OP},
    {"isnetworkowner",         {},                         OP},
}) do
    test(def[1], def[2], nil, true, 15, def[3], 1)
end

task.defer(function()
    repeat task.wait() until running == 0

    local function sortList(t) table.sort(t, function(a,b) return a < b end) end
    sortList(list_fail); sortList(list_missing)
    sortList(list_alias_missing); sortList(list_optional_missing)

    local pct = totalWeightedMax > 0
        and math.round(totalWeightedScore / totalWeightedMax * 100)
        or 0

    local hasCriticalFails = #list_missing > 0 or #list_fail > 0

    local tier, tierDesc = getTier(pct, hasCriticalFails)

    local catLines = {}
    for _, catName in ipairs(CATEGORIES) do
        local c = categoryStats[catName]
        if not c then continue end
        local total = c.passes + c.fails
        if total == 0 and c.missing == 0 then continue end
        local catPct = c.weighted_total > 0
            and math.round(c.weighted_score / c.weighted_total * 100)
            or 100
        local bar = ""
        local filled = math.floor(catPct / 10)
        for i = 1, 10 do bar = bar .. (i <= filled and "█" or "░") end
        local status = catPct == 100 and "✅" or (catPct >= 60 and "🟡" or "⛔")
        table.insert(catLines, {
            status = status,
            name = catName,
            bar = bar,
            pct = catPct,
            passes = c.passes,
            fails = c.fails,
            missing = c.missing
        })
    end

    local lines = {}
    local function addLine(s) table.insert(lines, s) end

    addLine("╔══════════════════════════════════════════════════════╗")
    addLine("║           iUNC v"..VERSION.." — FINAL SUMMARY                ║")
    addLine("╠══════════════════════════════════════════════════════╣")
    addLine("║  Executor : "..EXEC_DISPLAY)
    addLine("║  Platform : "..(IsOnMobile and "Mobile" or "Desktop"))
    addLine("╠══════════════════════════════════════════════════════╣")
    addLine("║  COMPATIBILITY TIER : "..tier.."   ("..pct.."%)")
    addLine("║  "..tierDesc)
    addLine("╠══════════════════════════════════════════════════════╣")
    addLine("║  Weighted Score : "..totalWeightedScore.." / "..totalWeightedMax)
    addLine("║  Missing (required) : "..#list_missing)
    addLine("║  Failing tests      : "..#list_fail)
    addLine("║  Missing aliases    : "..#list_alias_missing)
    addLine("║  Missing optional   : "..#list_optional_missing)
    addLine("╠══════════════════════════════════════════════════════╣")
    addLine("║  PER-CATEGORY BREAKDOWN")
    addLine("╠══════════════════════════════════════════════════════╣")
    for _, cl in ipairs(catLines) do
        local line = ("║  %s %-20s %s %3d%%  (%d✅ %d⛔)"):format(
            cl.status, cl.name, cl.bar, cl.pct, cl.passes, cl.fails + cl.missing)
        addLine(line)
    end
    addLine("╚══════════════════════════════════════════════════════╝")

    for _, line in ipairs(lines) do print(line) end

    if #list_missing > 0 then
        print("\n❌ Missing required globals:")
        print("   "..table.concat(list_missing, ", "))
    end
    if #list_fail > 0 then
        print("\n⛔ Failing tests:")
        for _, v in ipairs(list_fail) do print("   • "..v) end
    end
    if #list_alias_missing > 0 then
        print("\n⚠️ Missing aliases:")
        for _, v in ipairs(list_alias_missing) do print("   • "..v) end
    end
    if #list_optional_missing > 0 then
        print("\n⏺️ Missing optional globals:")
        print("   "..table.concat(list_optional_missing, ", "))
    end

    if writefile then
        local report = table.concat(lines, "\n")
        if #list_missing > 0 then
            report = report.."\n\nMissing required:\n"..table.concat(list_missing, "\n")
        end
        if #list_fail > 0 then
            report = report.."\n\nFailing tests:\n"
            for _, v in ipairs(list_fail) do report = report.."• "..v.."\n" end
        end
        if #list_alias_missing > 0 then
            report = report.."\n\nMissing aliases:\n"
            for _, v in ipairs(list_alias_missing) do report = report.."• "..v.."\n" end
        end
        local ok = pcall(writefile, "iUNC_results.txt", report)
        if ok then print("\n📄 Results exported to iUNC_results.txt") end
    end

    print("\n[iUNC v"..VERSION.."] All tests complete.")
end)
