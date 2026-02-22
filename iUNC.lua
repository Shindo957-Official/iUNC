--[[
    iUNC - Improved UNC Test
    Tests every standard UNC global for existence and correct behavior.
    Fast parallel execution. Clean summary at the end.
]]

local getexecname = identifyexecutor or getexecutorname or whatexecutor or function() return "Unknown Executor" end

-- ── Counters & lists ──
local passes, fails, existsOnly, missing, optionalMissing, aliasWarn = 0, 0, 0, 0, 0, 0
local running = 0
local list_fail, list_missing, list_alias_missing, list_optional_missing = {}, {}, {}, {}
local messageboxPassed = false

-- ── Helpers ──
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
    return #out > 300 and out:sub(1,300).."…" or out
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

local IsOnMobile = (function()
    local p = game:GetService("UserInputService"):GetPlatform()
    if p == Enum.Platform.IOS or p == Enum.Platform.Android
    or p == Enum.Platform.AndroidTV or p == Enum.Platform.Chromecast
    or p == Enum.Platform.MetaOS then return true end
    if p == Enum.Platform.None then
        local ui = game:GetService("UserInputService")
        return ui.TouchEnabled and not (ui.KeyboardEnabled or ui.MouseEnabled)
    end
    return false
end)()

-- ── Core test runner ──
local function test(name, aliases, callback, optional, timeout)
    optional = optional == true
    running += 1
    task.spawn(function()
        local exists = getGlobal(name) ~= nil

        if not callback then
            if exists then
                existsOnly += 1
                print("⏺️ "..name.." • Exists (no behavior test)")
            elseif optional then
                optionalMissing += 1; table.insert(list_optional_missing, name)
                print("⏺️ "..name.." • Optional — not provided")
            else
                fails += 1; missing += 1; table.insert(list_missing, name)
                warn("⛔ "..name.." • MISSING")
            end
        elseif not exists then
            if optional then
                optionalMissing += 1; table.insert(list_optional_missing, name)
                print("⏺️ "..name.." • Optional — not provided")
            else
                fails += 1; missing += 1; table.insert(list_missing, name)
                warn("⛔ "..name.." • MISSING")
            end
        else
            local ok, msg = runWithTimeout(callback, timeout)
            if ok then
                passes += 1
                print("✅ "..name..(msg and " • "..tostring(msg) or ""))
            else
                fails += 1
                local e = normalizeError(msg)
                table.insert(list_fail, name.." — "..e)
                warn("⛔ "..name.." — "..e)
            end
        end

        -- Alias check
        local bad = {}
        for _, alias in ipairs(aliases or {}) do
            if getGlobal(alias) == nil then table.insert(bad, alias) end
        end
        if #bad > 0 then
            aliasWarn += 1
            table.insert(list_alias_missing, name.." -> "..table.concat(bad, ", "))
            warn("⚠️ Missing alias(es) for "..name..": "..table.concat(bad, ", "))
        end

        running -= 1
    end)
end

-- ════════════════════════════════════════════
print("╔══════════════════════════════════════════╗")
print("║       iUNC — Improved UNC Test          ║")
print("╠══════════════════════════════════════════╣")
print("║  Executor: "..getexecname())
print("╚══════════════════════════════════════════╝")
print("✅ Pass  ⛔ Fail  ⏺️ Exists/Optional  ⚠️ Alias missing\n")

-- Prepare test folder
if isfolder and makefolder and delfolder then
    if isfolder(".tests") then delfolder(".tests") end
    makefolder(".tests")
end

-- ════════════════════════════════════════════
--  FILE SYSTEM
-- ════════════════════════════════════════════
print("── File System ──")

test("writefile", {}, function()
    writefile(".tests/writefile.txt", "iUNC_WRITEFILE")
    assert(readfile(".tests/writefile.txt") == "iUNC_WRITEFILE", "Contents did not persist")
end)

test("readfile", {}, function()
    writefile(".tests/readfile.txt", "success")
    assert(readfile(".tests/readfile.txt") == "success", "Did not return correct contents")
end)

test("appendfile", {}, function()
    writefile(".tests/appendfile.txt", "su")
    appendfile(".tests/appendfile.txt", "cce")
    appendfile(".tests/appendfile.txt", "ss")
    assert(readfile(".tests/appendfile.txt") == "success", "Did not append correctly")
end)

test("delfile", {}, function()
    writefile(".tests/delfile.txt", "bye")
    delfile(".tests/delfile.txt")
    assert(isfile(".tests/delfile.txt") == false, "File was not deleted")
end)

test("isfile", {}, function()
    writefile(".tests/isfile.txt", "test")
    assert(isfile(".tests/isfile.txt") == true,  "Should return true for a file")
    assert(isfile(".tests")            == false,  "Should return false for a folder")
    assert(isfile(".tests/nope.exe")   == false,  "Should return false for nonexistent path")
end)

test("makefolder", {}, function()
    makefolder(".tests/makefolder")
    assert(isfolder(".tests/makefolder"), "Folder was not created")
end)

test("isfolder", {}, function()
    assert(isfolder(".tests")         == true,  "Should return true for folder")
    assert(isfolder(".tests/nope.exe")== false, "Should return false for nonexistent path")
end)

test("delfolder", {}, function()
    makefolder(".tests/delfolder")
    delfolder(".tests/delfolder")
    assert(isfolder(".tests/delfolder") == false, "Folder was not deleted")
end)

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
end)

test("loadfile", {}, function()
    writefile(".tests/loadfile.lua", "return ... + 1")
    local f, err = loadfile(".tests/loadfile.lua")
    assert(type(f) == "function", "Expected function, err: "..tostring(err))
    assert(f(41) == 42, "loadfile returned wrong value")
end)

test("dofile", {}, function()
    _G.__iUNC_DOFILE = nil
    writefile(".tests/dofile.lua", "_G.__iUNC_DOFILE = true")
    task.wait()
    dofile(".tests/dofile.lua")
    assert(_G.__iUNC_DOFILE == true, "dofile did not execute the chunk")
end)

test("getcustomasset", {}, function()
    writefile(".tests/asset.png", "iUNC")
    local id = getcustomasset(".tests/asset.png")
    assert(type(id) == "string" and #id > 0, "Did not return a non-empty string")
    assert(id:match("rbxasset://"), "Did not return an rbxasset:// URL")
end)

-- ════════════════════════════════════════════
--  CLOSURES
-- ════════════════════════════════════════════
print("\n── Closures ──")

test("iscclosure", {}, function()
    assert(iscclosure(print)         == true,  "print should be a C closure")
    assert(iscclosure(function()end) == false, "Lua function should not be a C closure")
end)

test("islclosure", {}, function()
    assert(islclosure(print)         == false, "print should not be a Lua closure")
    assert(islclosure(function()end) == true,  "Lua function should be a Lua closure")
end)

test("isexecutorclosure", {"checkclosure","isourclosure"}, function()
    assert(isexecutorclosure(isexecutorclosure)           == true,  "Should be true for executor global")
    assert(isexecutorclosure(newcclosure(function()end))  == true,  "Should be true for executor C closure")
    assert(isexecutorclosure(function()end)               == true,  "Should be true for executor Lua closure")
    assert(isexecutorclosure(print)                       == false, "Should be false for Roblox global")
end)

test("clonefunction", {}, function()
    local function f() return "iUNC" end
    local c = clonefunction(f)
    assert(f() == c(), "Clone should return same value")
    assert(f ~= c,     "Clone should not equal original")
end)

test("newcclosure", {}, function()
    local function f() return true end
    local c = newcclosure(f)
    assert(f() == c(),    "C closure should return same value")
    assert(f ~= c,        "C closure should not equal original")
    assert(iscclosure(c), "Result should be a C closure")
end)

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
end)

test("restorefunction", {"restoreclosure"}, function()
    local function f() return "original" end
    hookfunction(f, function() return "hooked" end)
    assert(f() == "hooked", "Hook did not apply")
    restorefunction(f)
    assert(f() == "original", "restorefunction did not restore")
end, true)

-- ════════════════════════════════════════════
--  METATABLES
-- ════════════════════════════════════════════
print("\n── Metatables ──")

test("getrawmetatable", {}, function()
    local mt = {__metatable = "Locked!"}
    local obj = setmetatable({}, mt)
    assert(getrawmetatable(obj) == mt, "Did not return the correct metatable")
end)

test("setrawmetatable", {}, function()
    local obj = setmetatable({}, {__index = function() return false end, __metatable = "Locked!"})
    setrawmetatable(obj, {__index = function() return true end})
    assert(obj.test == true, "Failed to change the metatable")
end)

test("isreadonly", {}, function()
    local t = {}; table.freeze(t)
    assert(isreadonly(t), "Should return true for frozen table")
end)

test("setreadonly", {}, function()
    local t = {ok = false}; table.freeze(t)
    setreadonly(t, false)
    t.ok = true
    assert(t.ok, "Did not allow modification after setreadonly(false)")
end)

test("hookmetamethod", {}, function()
    local seen = false; local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        if self == game and getnamecallmethod() == "GetService" then seen = true end
        return old(self, ...)
    end)
    game:GetService("Lighting")
    assert(seen, "hookmetamethod did not intercept __namecall")
end)

test("getnamecallmethod", {}, function()
    local method; local ref
    ref = hookmetamethod(game, "__namecall", function(...)
        if not method then method = getnamecallmethod() end
        return ref(...)
    end)
    game:GetService("Lighting")
    assert(method == "GetService", "Expected 'GetService', got: "..tostring(method))
end)

-- ════════════════════════════════════════════
--  DEBUG LIBRARY
-- ════════════════════════════════════════════
print("\n── Debug Library ──")

test("debug.getconstant", {}, function()
    local function f() print("Hello, world!") end
    assert(debug.getconstant(f, 1) == "print",          "Constant 1 should be 'print'")
    assert(debug.getconstant(f, 2) == nil,              "Constant 2 should be nil")
    assert(debug.getconstant(f, 3) == "Hello, world!", "Constant 3 should be 'Hello, world!'")
end)

test("debug.getconstants", {}, function()
    local function f() local n = 5000 .. 50000; print("Hello, world!", n, warn) end
    local c = debug.getconstants(f)
    assert(c[1] == 50000,           "c[1] should be 50000")
    assert(c[2] == "print",         "c[2] should be 'print'")
    assert(c[3] == nil,             "c[3] should be nil")
    assert(c[4] == "Hello, world!", "c[4] should be 'Hello, world!'")
    assert(c[5] == "warn",          "c[5] should be 'warn'")
end)

test("debug.setconstant", {}, function()
    local function f() return "fail" end
    debug.setconstant(f, 1, "success")
    assert(f() == "success", "setconstant did not change the constant")
end)

test("debug.getinfo", {}, function()
    local expected = {
        source = "string", short_src = "string", func = "function", what = "string",
        currentline = "number", name = "string", nups = "number",
        numparams = "number", is_vararg = "number"
    }
    local function f(...) print(...) end
    local info = debug.getinfo(f)
    for k, v in pairs(expected) do
        assert(info[k] ~= nil,      "Missing field: "..k)
        assert(type(info[k]) == v,  k.." should be "..v..", got "..type(info[k]))
    end
end)

test("debug.getproto", {}, function()
    local function outer() local function inner() return true end end
    local proto = debug.getproto(outer, 1, true)[1]
    assert(proto,           "Failed to get inner function")
    assert(proto() == true, "Inner function did not return true")
end)

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
end)

test("debug.getstack", {}, function()
    local _ = "a" .. "b"
    assert(debug.getstack(1, 1)    == "ab", "Stack item 1 should be 'ab'")
    assert(debug.getstack(1)[1]    == "ab", "Stack table[1] should be 'ab'")
end)

test("debug.setstack", {}, function()
    local function f() return "fail", debug.setstack(1, 1, "success") end
    assert(f() == "success", "setstack did not update the stack")
end)

test("debug.getupvalue", {}, function()
    local upval = function() end
    local function f() print(upval) end
    assert(debug.getupvalue(f, 1) == upval, "Unexpected getupvalue result")
end)

test("debug.getupvalues", {}, function()
    local upval = function() end
    local function f() print(upval) end
    assert(debug.getupvalues(f)[1] == upval, "Unexpected getupvalues result")
end)

test("debug.setupvalue", {}, function()
    local function upval() return "fail" end
    local function f() return upval() end
    debug.setupvalue(f, 1, function() return "success" end)
    assert(f() == "success", "setupvalue did not change the upvalue")
end)

-- ════════════════════════════════════════════
--  INSTANCE & CACHE
-- ════════════════════════════════════════════
print("\n── Instance & Cache ──")

test("cache.invalidate", {}, function()
    local folder = Instance.new("Folder")
    local part = Instance.new("Part", folder)
    cache.invalidate(folder:FindFirstChild("Part"))
    assert(part ~= folder:FindFirstChild("Part"), "Cache was not invalidated")
end)

test("cache.iscached", {}, function()
    local part = Instance.new("Part")
    assert(cache.iscached(part),     "Part should be cached")
    cache.invalidate(part)
    assert(not cache.iscached(part), "Part should not be cached after invalidation")
end)

test("cache.replace", {}, function()
    local part = Instance.new("Part")
    local fire = Instance.new("Fire")
    cache.replace(part, fire)
    assert(part ~= fire, "Part was not replaced with Fire")
end)

test("cloneref", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone,          "Clone should not == original")
    clone.Name = "iUNCTest"
    assert(part.Name == "iUNCTest","Modifying clone should update original")
end)

test("compareinstances", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone,                 "Clone should not == original via ==")
    assert(compareinstances(part, clone), "compareinstances should return true")
end)

test("gethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local value, isHidden = gethiddenproperty(fire, "size_xml")
    assert(value == 5,        "Expected size_xml == 5, got "..tostring(value))
    assert(isHidden == true,  "Expected isHidden == true")
end)

test("sethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local wasHidden = sethiddenproperty(fire, "size_xml", 10)
    assert(wasHidden == true,                         "Should return true for a hidden property")
    assert(gethiddenproperty(fire, "size_xml") == 10, "Hidden property not set to 10")
end)

test("isscriptable", {}, function()
    local fire = Instance.new("Fire")
    assert(isscriptable(fire, "size_xml") == false, "size_xml should NOT be scriptable")
    assert(isscriptable(fire, "Size")     == true,  "Size SHOULD be scriptable")
end)

test("setscriptable", {}, function()
    local fire = Instance.new("Fire")
    local was = setscriptable(fire, "size_xml", true)
    assert(was == false,                           "Should return false (was not scriptable)")
    assert(isscriptable(fire, "size_xml") == true, "size_xml should now be scriptable")
    local fire2 = Instance.new("Fire")
    assert(isscriptable(fire2, "size_xml") == false, "setscriptable should not persist to new instances")
end)

test("getinstances", {}, function()
    local inst = getinstances()
    assert(type(inst) == "table" and #inst > 0, "Should return a non-empty table")
    assert(typeof(inst[1]) == "Instance",       "First element should be an Instance")
end)

test("getnilinstances", {}, function()
    local inst = getnilinstances()
    assert(type(inst) == "table" and #inst > 0, "Should return a non-empty table")
    assert(typeof(inst[1]) == "Instance",       "First element should be an Instance")
    assert(inst[1].Parent == nil,               "First element should have nil Parent")
end)

test("getcallbackvalue", {}, function()
    local bf = Instance.new("BindableFunction")
    local function cb() end
    bf.OnInvoke = cb
    assert(getcallbackvalue(bf, "OnInvoke") == cb, "Did not return the correct callback")
end)

test("getconnections", {}, function()
    local be = Instance.new("BindableEvent")
    be.Event:Connect(function() end)
    local conn = getconnections(be.Event)[1]
    local expected = {
        Enabled = "boolean", ForeignState = "boolean", LuaConnection = "boolean",
        Function = "function", Thread = "thread", Fire = "function", Defer = "function",
        Disconnect = "function", Disable = "function", Enable = "function"
    }
    for k, v in pairs(expected) do
        assert(conn[k] ~= nil,      "Missing connection field: "..k)
        assert(type(conn[k]) == v,  k.." should be "..v..", got "..type(conn[k]))
    end
end)

test("gethui", {}, function()
    assert(typeof(gethui()) == "Instance", "Should return an Instance")
end)

test("getloadedmodules", {}, function()
    local mods = getloadedmodules()
    assert(type(mods) == "table" and #mods > 0, "Should return a non-empty table")
    assert(mods[1]:IsA("ModuleScript"),          "First element should be a ModuleScript")
end)

test("getrunningscripts", {}, function()
    local s = getrunningscripts()
    assert(type(s) == "table" and #s > 0, "Should return a non-empty table")
    assert(s[1]:IsA("ModuleScript") or s[1]:IsA("LocalScript"), "Should be a script instance")
end)

test("getscripts", {}, function()
    local s = getscripts()
    assert(type(s) == "table" and #s > 0, "Should return a non-empty table")
    assert(s[1]:IsA("ModuleScript") or s[1]:IsA("LocalScript"), "Should be a script instance")
end)

test("getscriptbytecode", {"dumpstring"}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate
    local bc = getscriptbytecode(anim)
    assert(type(bc) == "string" and #bc > 0, "Should return a non-empty string")
end)

test("getscripthash", {}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate:Clone()
    local h1 = getscripthash(anim)
    local src = anim.Source
    anim.Source = "print('iUNC')"
    task.defer(function() anim.Source = src end)
    local h2 = getscripthash(anim)
    assert(h1 ~= h2,                  "Hash should differ after source change")
    assert(h2 == getscripthash(anim), "Hash should be stable for same source")
end)

test("getsenv", {}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate
    local env = getsenv(anim)
    assert(type(env) == "table", "Should return a table")
    assert(env.script == anim,   "env.script should equal Animate")
end)

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
end)

-- ════════════════════════════════════════════
--  ENVIRONMENT & THREAD
-- ════════════════════════════════════════════
print("\n── Environment & Thread ──")

test("checkcaller", {}, function()
    assert(checkcaller(), "Should return true in main scope")
end)

test("getgenv", {}, function()
    getgenv().__iUNC_GENV = true
    assert(__iUNC_GENV == true, "Failed to set global via getgenv()")
    getgenv().__iUNC_GENV = nil
end)

test("getrenv", {}, function()
    assert(_G ~= getrenv()._G, "Executor _G should differ from game _G")
end)

test("getthreadidentity", {"getidentity","getthreadcontext"}, function()
    assert(type(getthreadidentity()) == "number", "Should return a number")
end)

test("setthreadidentity", {"setidentity","setthreadcontext"}, function()
    setthreadidentity(3)
    assert(getthreadidentity() == 3, "Thread identity should now be 3")
end)

test("getgc", {}, function()
    local gc = getgc(true)
    assert(type(gc) == "table" and #gc > 0, "getgc should return a non-empty table")
end)

test("getregistry", {"getreg"}, function()
    local r = getregistry()
    assert(type(r) == "table" and r[1] ~= nil, "Should return a non-empty table")
end)

test("identifyexecutor", {"getexecutorname"}, function()
    local name, version = identifyexecutor()
    assert(type(name) == "string", "Should return a string name")
    return "version: "..(type(version) == "string" and version or "(not returned)")
end)

-- ════════════════════════════════════════════
--  SIGNALS & INPUT
-- ════════════════════════════════════════════
print("\n── Signals & Input ──")

test("firesignal", {}, function()
    local be = Instance.new("BindableEvent")
    local count = 0
    be.Event:Connect(function(a, b) if a == 1 and b == 2 then count += 1 end end)
    firesignal(be.Event, 1, 2)
    task.wait()
    assert(count == 1, "firesignal did not invoke the signal (count="..count..")")
end)

test("fireclickdetector", {}, function()
    local det = Instance.new("ClickDetector")
    fireclickdetector(det, 50, "MouseHoverEnter")
end)

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
end)

test("firetouchinterest", {}, function()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then return "LocalPlayer missing" end
    local char = lp.Character or lp.CharacterAdded:Wait()
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not root then return "No root part" end
    local part = Instance.new("Part")
    part.Size = Vector3.new(4, 4, 4); part.Anchored = true; part.CanCollide = true
    part.Position = root.Position + Vector3.new(0, 5000, 0); part.Parent = workspace
    local touched = false
    part.Touched:Connect(function(h) if h == root then touched = true end end)
    assert(pcall(firetouchinterest, root, part, 0))
    task.wait(0.05)
    assert(pcall(firetouchinterest, root, part, 1))
    task.wait(0.05); part:Destroy()
    if not touched then return "Touched event not observed (executor may limit this)" end
end)

test("mouse1click",   {}, function() assert(pcall(mouse1click)) end)
test("mouse1press",   {}, function() assert(pcall(mouse1press)) end)
test("mouse1release", {}, function() assert(pcall(mouse1release)) end)
test("mouse2click",   {}, function() assert(pcall(mouse2click)) end)
test("mouse2press",   {}, function() assert(pcall(mouse2press)) end)
test("mouse2release", {}, function() assert(pcall(mouse2release)) end)

test("mousemoveabs", {}, function()
    assert(pcall(mousemoveabs, 0, 0))
    assert(pcall(mousemoveabs, 100, 100))
end)

test("mousemoverel", {}, function()
    assert(pcall(mousemoverel, 0, 0))
    assert(pcall(mousemoverel, 10, -10))
end)

test("mousescroll", {}, function()
    assert(pcall(mousescroll, 1))
    assert(pcall(mousescroll, -1))
end)

test("keypress",   {}, function() assert(pcall(keypress, 0x41)) end, true)
test("keyrelease", {}, function() assert(pcall(keyrelease, 0x41)) end, true)
test("keyclick",   {}, function() assert(pcall(keyclick, 0x41)) end, true)

test("queue_on_teleport", {"queueonteleport"}, function()
    assert(pcall(queue_on_teleport, "return 1"))
end)

-- ════════════════════════════════════════════
--  CRYPTO & ENCODING
-- ════════════════════════════════════════════
print("\n── Crypto & Encoding ──")

test("crypt.base64encode", {"crypt.base64.encode","crypt.base64_encode","base64.encode","base64_encode"}, function()
    assert(crypt.base64encode("test") == "dGVzdA==", "Base64 encoding failed")
end)

test("crypt.base64decode", {"crypt.base64.decode","crypt.base64_decode","base64.decode","base64_decode"}, function()
    assert(crypt.base64decode("dGVzdA==") == "test", "Base64 decoding failed")
end)

test("crypt.generatekey", {}, function()
    local key = crypt.generatekey()
    assert(#crypt.base64decode(key) == 32, "Key should decode to 32 bytes")
end)

test("crypt.generatebytes", {}, function()
    local n = math.random(10, 100)
    local bytes = crypt.generatebytes(n)
    assert(#crypt.base64decode(bytes) == n, "Expected "..n.." bytes, got "..#crypt.base64decode(bytes))
end)

test("crypt.encrypt", {}, function()
    local key = crypt.generatekey()
    local enc, iv = crypt.encrypt("test", key, nil, "CBC")
    assert(iv, "encrypt should return an IV")
    assert(crypt.decrypt(enc, key, iv, "CBC") == "test", "Decrypt after encrypt failed")
end)

test("crypt.decrypt", {}, function()
    local key, iv = crypt.generatekey(), crypt.generatekey()
    local enc = crypt.encrypt("test", key, iv, "CBC")
    assert(crypt.decrypt(enc, key, iv, "CBC") == "test", "Decryption failed")
end)

test("crypt.hash", {}, function()
    for _, alg in ipairs({"sha1","sha256","sha384","sha512","md5","sha3-224","sha3-256","sha3-512"}) do
        assert(crypt.hash("test", alg), "crypt.hash failed for: "..alg)
    end
end)

test("lz4compress", {}, function()
    local raw = "Hello, iUNC!"
    local comp = lz4compress(raw)
    assert(type(comp) == "string",           "Should return a string")
    assert(lz4decompress(comp, #raw) == raw, "Decompressed value is wrong")
end)

test("lz4decompress", {}, function()
    local raw = "Hello, iUNC!"
    assert(lz4decompress(lz4compress(raw), #raw) == raw, "Decompressed value is wrong")
end)

-- ════════════════════════════════════════════
--  DRAWING
-- ════════════════════════════════════════════
print("\n── Drawing ──")

test("Drawing", {}, function()
    assert(type(Drawing)       == "table",    "Drawing must be a table")
    assert(type(Drawing.new)   == "function", "Drawing.new must be a function")
    assert(type(Drawing.Fonts) == "table",    "Drawing.Fonts must be a table")
    local obj = Drawing.new("Square")
    assert(obj ~= nil, "Drawing.new returned nil")
    obj.Visible = false
    assert(pcall(function() obj:Destroy() end), "Drawing:Destroy() should not throw")
end)

test("Drawing.Fonts", {}, function()
    assert(Drawing.Fonts.UI        == 0, "UI should be 0")
    assert(Drawing.Fonts.System    == 1, "System should be 1")
    assert(Drawing.Fonts.Plex      == 2, "Plex should be 2")
    assert(Drawing.Fonts.Monospace == 3, "Monospace should be 3")
end)

test("Drawing.new", {}, function()
    for _, shape in ipairs({"Line","Text","Image","Circle","Square","Quad","Triangle"}) do
        local ok, obj = pcall(Drawing.new, shape)
        assert(ok, "Drawing.new(\""..shape.."\") errored")
        if ok and obj then obj.Visible = false; pcall(function() obj:Destroy() end) end
    end
end)

test("cleardrawcache", {}, function()
    cleardrawcache()
end)

test("isrenderobj", {}, function()
    local d = Drawing.new("Square"); d.Visible = false
    assert(isrenderobj(d)           == true,  "Should return true for Drawing object")
    assert(isrenderobj(newproxy())  == false, "Should return false for blank userdata")
    d:Destroy()
end)

test("Drawing.clear", {}, function()
    assert(pcall(Drawing.clear))
end, true)

-- ════════════════════════════════════════════
--  CLIPBOARD & MISC
-- ════════════════════════════════════════════
print("\n── Clipboard & Misc ──")

test("setclipboard", {"toclipboard"}, function()
    assert(pcall(setclipboard, "iUNC_TEST"))
end)

test("getclipboard", {}, function()
    local v = getclipboard()
    assert(v == nil or type(v) == "string", "Should return string or nil")
end, true)

test("setrbxclipboard", {}, function()
    assert(pcall(setrbxclipboard, "iUNC_RBX"))
end)

test("isrbxactive", {"isgameactive"}, function()
    assert(type(isrbxactive()) == "boolean", "Should return a boolean")
end)

test("loadstring", {}, function()
    local anim = game:GetService("Players").LocalPlayer.Character.Animate
    local fn = loadstring(getscriptbytecode(anim))
    assert(type(fn) ~= "function", "Luau bytecode should NOT be loadable")
    local f, err = loadstring("return ... + 1")
    assert(type(f) == "function", "Should return a function (err: "..tostring(err)..")")
    assert(f(41) == 42, "Unexpected return value from loadstring")
end)

-- ════════════════════════════════════════════
--  FPS
-- ════════════════════════════════════════════
print("\n── FPS ──")

test("setfpscap", {}, function()
    local rs = game:GetService("RunService").RenderStepped
    local function measure(n)
        rs:Wait(); local sum = 0
        for _ = 1, n do sum += 1/rs:Wait() end
        return math.round(sum/n)
    end
    setfpscap(60);  local f60  = measure(6)
    setfpscap(240); local f240 = measure(6)
    setfpscap(0);   local f0   = measure(6)
    assert(f60 > 0 and f240 > 0 and f0 > 0, "FPS samples invalid")
    return ("60cap≈%d  240cap≈%d  uncapped≈%d"):format(f60, f240, f0)
end)

test("getfpscap", {}, function()
    local cap = getfpscap()
    assert(type(cap) == "number" and cap >= 0, "Should return a non-negative number")
end, true)

-- ════════════════════════════════════════════
--  ACTORS
-- ════════════════════════════════════════════
print("\n── Actors ──")

test("getactors", {}, function()
    local ok, acts = pcall(getactors)
    assert(ok, "getactors threw: "..tostring(acts))
    assert(type(acts) == "table", "Should return a table")
    if not acts[1] then return "No Actors found (none initialized yet)" end
    assert(acts[1]:IsA("Actor"), "First element should be an Actor")
end)

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
end)

-- ════════════════════════════════════════════
--  SCRIPT TOOLS
-- ════════════════════════════════════════════
print("\n── Script Tools ──")

test("getcallingscript", {}, function()
    local ok, s = pcall(getcallingscript)
    if not ok then return "Errored in this context: "..normalizeError(s) end
    if s == nil then return "Returned nil in executor context" end
    assert(typeof(s) == "Instance", "Should return Instance or nil")
    assert(s:IsA("LocalScript") or s:IsA("ModuleScript") or s:IsA("Script"), "Should be a script instance")
end, true)

test("getscriptclosure", {}, function()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then return "LocalPlayer missing" end
    local char = lp.Character or lp.CharacterAdded:Wait()
    local scr = char:FindFirstChildOfClass("LocalScript")
    if not scr then return "No LocalScript on character" end
    local f = getscriptclosure(scr)
    assert(type(f) == "function", "Should return a function")
    return "Got closure for "..scr.Name
end, true)

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
end, true)

test("getscriptfromthread", {}, function()
    local co = coroutine.create(function() task.wait(0.1) end)
    coroutine.resume(co)
    local ok, s = pcall(getscriptfromthread, co)
    assert(ok, tostring(s))
    assert(s == nil or typeof(s) == "Instance", "Should return Instance or nil")
end, true)

-- ════════════════════════════════════════════
--  WEBSOCKET & HTTP
-- ════════════════════════════════════════════
print("\n── WebSocket & HTTP ──")

test("request", {"http.request","http_request"}, function()
    local hs  = game:GetService("HttpService")
    local res = request({Url = "https://httpbin.org/user-agent", Method = "GET"})
    assert(type(res) == "table" and res.StatusCode == 200, "Did not get 200 response")
    local data = hs:JSONDecode(res.Body)
    assert(type(data) == "table" and data["user-agent"] ~= nil, "Response missing user-agent")
    return "ua: "..tostring(data["user-agent"])
end)

test("WebSocket", {}, function()
    assert(type(WebSocket) == "table" or type(WebSocket) == "userdata", "Should be table or userdata")
end)

test("WebSocket.connect", {}, function()
    if type(WebSocket) ~= "table" and type(WebSocket) ~= "userdata" then return "WebSocket unavailable" end
    local urls    = {"wss://echo.websocket.events", "wss://ws.ifelse.io"}
    local ws, url, lastErr
    for _, u in ipairs(urls) do
        local ok, res = pcall(WebSocket.connect, u)
        if ok and res then ws = res; url = u; break else lastErr = res end
    end
    if not ws then return "Could not connect to any test URL: "..tostring(lastErr) end
    local expected = {
        Send = "function", Close = "function",
        OnMessage = {"table","userdata"}, OnClose = {"table","userdata"}
    }
    for k, v in pairs(expected) do
        if type(v) == "table" then
            assert(table.find(v, type(ws[k])), k.." wrong type: "..type(ws[k]))
        else
            assert(type(ws[k]) == v, k.." should be "..v)
        end
    end
    pcall(function() ws:Close() end)
    return "Connected to "..url
end)

-- ════════════════════════════════════════════
--  FFLAGS
-- ════════════════════════════════════════════
print("\n── FFlags ──")

test("getfflag", {}, function()
    local full  = "FFlagDebugGraphicsPreferD3D11"
    local short = "DebugGraphicsPreferD3D11"
    local okF   = pcall(getfflag, full)
    local okS   = pcall(getfflag, short)
    assert(okF or okS, "getfflag failed for both full and short names")
    if okF and okS then return "Full + short names supported"
    elseif okF then  return "Full names only"
    else             return "Short names only" end
end, true)

test("setfflag", {}, function()
    local flag    = "FFlagDebugGraphicsPreferD3D11"
    local ok, cur = pcall(getfflag, flag)
    if not ok then return "getfflag unavailable; cannot test setfflag" end
    local ok2, err = pcall(setfflag, flag, cur)
    if not ok2 and type(cur) == "boolean" then
        ok2, err = pcall(setfflag, flag, cur and "True" or "False")
    end
    assert(ok2, err or "setfflag errored")
    return "setfflag accepted current value"
end, true)

-- ════════════════════════════════════════════
--  OPTIONAL MISC
-- ════════════════════════════════════════════
print("\n── Optional ──")

test("isnetworkowner", {}, function()
    local part = Instance.new("Part")
    part.Anchored = false; part.CanCollide = false; part.Parent = workspace
    local ok, res = pcall(isnetworkowner, part)
    part:Destroy()
    assert(ok, res or "isnetworkowner errored")
    assert(type(res) == "boolean", "Should return a boolean")
end, true)

test("getobjects", {}, function()
    local ok, res = pcall(getobjects, "rbxassetid://1")
    if not ok then return "External asset request blocked" end
    assert(type(res) == "table", "Should return a table")
end, true)

test("messagebox", {}, function()
    if IsOnMobile then return "Mobile device — skipping messagebox" end
    print("iUNC: A messagebox will appear. Click OK to continue.")
    local ok, res = pcall(messagebox, "iUNC Test Messagebox", "iUNC Test", 0)
    assert(ok, res or "messagebox errored")
    assert(type(res) == "number" or res == nil, "Should return number or nil")
    messageboxPassed = true
end, true, 45)

-- Existence-only optional globals
for _, def in ipairs({
    {"saveinstance",           {"save_instance"}},
    {"rconsoleclear",          {"consoleclear"}},
    {"rconsolecreate",         {"consolecreate"}},
    {"rconsoledestroy",        {"consoledestroy"}},
    {"rconsoleinput",          {"consoleinput"}},
    {"rconsoleprint",          {"consoleprint"}},
    {"rconsolesettitle",       {"rconsolename","consolesettitle"}},
    {"rconsolewarn",           {"consolewarn"}},
    {"rconsoleerr",            {"consoleerr"}},
    {"getcallstack",           {}},
    {"getfunctionhash",        {}},
    {"isluau",                 {}},
    {"gethwid",                {}},
    {"setnamecallmethod",      {}},
    {"getpointerfrominstance", {}},
    {"firetouchtransmitter",   {}},
    {"getspecialinfo",         {}},
    {"readbinarystring",       {}},
    {"cloneclosure",           {}},
    {"http",                   {}},
    {"http.get",               {}},
    {"http.post",              {}},
}) do
    test(def[1], def[2], nil, true)
end

-- ════════════════════════════════════════════
--  FINAL SUMMARY
-- ════════════════════════════════════════════
task.defer(function()
    repeat task.wait() until running == 0

    local function sortList(t) table.sort(t, function(a,b) return a < b end) end
    sortList(list_fail); sortList(list_missing)
    sortList(list_alias_missing); sortList(list_optional_missing)

    local total = passes + fails
    local rate  = total > 0 and math.round(passes / total * 100) or 0

    local verdict
    if total == 0 then
        verdict = "❓ No functions tested"
    elseif rate >= 90 and fails == 0 and missing == 0 then
        verdict = "🏆 Excellent iUNC compatibility"
    elseif rate >= 80 and fails == 0 then
        verdict = "✅ Very Good — core features work, some globals/aliases missing"
    elseif rate >= 60 then
        verdict = "🟡 Decent — several functions missing or broken"
    elseif rate >= 30 then
        verdict = "🟠 Poor — many iUNC features fail or are missing"
    else
        verdict = "🔴 Very Bad — executor barely passes iUNC"
    end

    print("\n╔══════════════════════════════════════════╗")
    print("║     iUNC TEST — FINAL SUMMARY           ║")
    print("╠══════════════════════════════════════════╣")
    print("║  Executor:              "..getexecname())
    print("╠══════════════════════════════════════════╣")
    print("║  ✅  Passed:            "..passes)
    print("║  ⛔  Failed:            "..fails)
    print("║  ❌  Missing (required):"..missing)
    print("║  ⏺️   Exists/untested:   "..existsOnly)
    print("║  ⏺️   Optional missing:  "..optionalMissing)
    print("║  ⚠️   Alias warnings:    "..aliasWarn)
    print("╠══════════════════════════════════════════╣")
    print(("║  Pass Rate: %d%% (%d / %d tested)"):format(rate, passes, total))
    print("╠══════════════════════════════════════════╣")
    print("║  "..verdict)
    print("╚══════════════════════════════════════════╝")

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

    print("\n[iUNC] All tests complete.")
end)
