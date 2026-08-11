--[[
Full round trip: change a setting, run the logout sequence, serialise the
SavedVariables the way the client does, load the file back, and check the
setting survived.

    lua5.1 tools/roundtrip_test.lua

The existing savedvars_test only asks whether the data COULD be written. This
asks whether it actually comes back, which is the question a user reporting
"my settings reset at every logout" is really asking. It uses the real
AceDB-3.0 rather than a stub, because the reset behaviour lives in AceDB's
removeDefaults, which runs on PLAYER_LOGOUT.

Point ACE3_PATH at a checkout if the bundled libs are not populated:

    ACE3_PATH=/path/to/Ace3 lua5.1 tools/roundtrip_test.lua
]]

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install(os.getenv("CHATIFY_STUB_MODE") or "retail")

-- ------------------------------------------------------------- real AceDB

local acePath = os.getenv("ACE3_PATH")
local aceDBFile
for _, candidate in ipairs({
    acePath and (acePath .. "/AceDB-3.0/AceDB-3.0.lua") or nil,
    "libs/AceDB-3.0/AceDB-3.0.lua",
}) do
    local fh = candidate and io.open(candidate, "r")
    if fh then
        fh:close()
        aceDBFile = candidate
        break
    end
end

if not aceDBFile then
    print("roundtrip: AceDB-3.0 not found; set ACE3_PATH or populate libs/. Skipped.")
    os.exit(0)
end

-- AceDB reads a handful of unit and realm APIs at load time to build its keys.
-- The stub does not model them, so they are supplied here rather than bloating
-- the shared environment for every other test.
_G.UnitName = _G.UnitName or function() return "Tester" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetRealmName = function() return "TestRealm" end
_G.GetCurrentRegion = _G.GetCurrentRegion or function() return 3 end
_G.geterrorhandler = _G.geterrorhandler or function() return function(e) error(e) end end

-- The stub ships a simplified AceDB. Drop it so the real one registers instead.
local realLibStub = _G.LibStub
if realLibStub and realLibStub.libs then
    realLibStub.libs["AceDB-3.0"] = nil
    realLibStub.minors["AceDB-3.0"] = nil
end
-- AceDB's profile callbacks come from CallbackHandler; without it, the
-- RegisterCallback the addon uses on its database is nil.
local cbhFile = aceDBFile:gsub("AceDB%-3%.0/AceDB%-3%.0%.lua$",
    "CallbackHandler-1.0/CallbackHandler-1.0.lua")
local cbh = io.open(cbhFile, "r")
if cbh then
    cbh:close()
    if realLibStub and realLibStub.libs then
        realLibStub.libs["CallbackHandler-1.0"] = nil
        realLibStub.minors["CallbackHandler-1.0"] = nil
    end
    assert(loadfile(cbhFile))()
end

assert(loadfile(aceDBFile))()

-- ------------------------------------- a serialiser shaped like the client's

-- The client can write nil, booleans, numbers, strings and tables of those.
-- Keys must be strings or numbers. Anything else is dropped, which is precisely
-- how a setting silently fails to persist.
local dropped = {}

local function serialise(value, name, indent, path)
    indent = indent or "\t"
    local t = type(value)

    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            dropped[#dropped + 1] = path .. " (number is inf/nan)"
            return nil
        end
        return tostring(value)
    elseif t == "boolean" then
        return tostring(value)
    elseif t ~= "table" then
        dropped[#dropped + 1] = path .. " (type " .. t .. ")"
        return nil
    end

    local parts = {}
    for key, sub in pairs(value) do
        local keyText
        if type(key) == "string" then
            keyText = string.format("[%q]", key)
        elseif type(key) == "number" then
            keyText = "[" .. tostring(key) .. "]"
        else
            dropped[#dropped + 1] = path .. " (key of type " .. type(key) .. ")"
        end

        if keyText then
            local subText = serialise(sub, nil, indent .. "\t", path .. "." .. tostring(key))
            if subText then
                parts[#parts + 1] = indent .. keyText .. " = " .. subText .. ","
            end
        end
    end

    if #parts == 0 then
        return "{\n" .. indent:sub(2) .. "}"
    end
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent:sub(2) .. "}"
end

-- ------------------------------------------------------------- load the addon

local ns, addonName = {}, "Chatify"

local function tocFiles()
    local files = {}
    local fh = assert(io.open("Chatify.toc", "r"))
    for line in fh:lines() do
        line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") and line:match("%.lua$") then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    fh:close()
    return files
end

local failuresExtra = false
local files = tocFiles()
for _, file in ipairs(files) do
    assert(loadfile(file))(addonName, ns)
end

local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
addon:OnInitialize()

-- The rest of a real session, not just OnInitialize. Modules enable, the options
-- table is built, and the deferred login migrations run. Any of these can write
-- to the profile, and a previous version of this test missed all of them: it
-- reported a clean round trip while only ever exercising the database itself.
for name, mod in pairs(addon.modules or {}) do
    if type(mod.OnEnable) == "function" then
        local ok, err = pcall(mod.OnEnable, mod)
        if not ok then
            print("  note: module " .. name .. ":OnEnable failed: " .. tostring(err))
        end
    end
end

-- Registered as a function now, so it is rebuilt on every panel refresh; build
-- it several times, because a builder that mutates the profile would only show
-- up as drift across repeats.
for _ = 1, 3 do
    if type(addon.GetOptions) == "function" then
        pcall(addon.GetOptions, addon)
    end
end

-- Deferred work that C_Timer would run a few seconds after login.
if env.runPendingTimers then
    env.runPendingTimers(10)
end

-- ------------------------------------------------------- session one: change

local CHANGES = {
    { "shortChannels", false },
    { "enableTimestamps", false },
    { "historyLimit", 777 },
    { "fontSize", 15 },
}

for _, change in ipairs(CHANGES) do
    addon.db.profile[change[1]] = change[2]
end
addon.db.profile.channelLabels = addon.db.profile.channelLabels or {}
addon.db.profile.channelLabels.PARTY = "Grp"

-- Chatify's own logout handlers, then AceDB's, in the order the client fires
-- them. AceDB's removeDefaults is what strips values back down before the file
-- is written, so it has to run for this test to mean anything.
for _, mod in pairs(addon.modules or {}) do
    if type(mod.SaveHistory) == "function" then
        pcall(mod.SaveHistory, mod)
    end
end

-- AceDB installs its own PLAYER_LOGOUT frame; firing it is what runs
-- removeDefaults, which is the step that decides what actually reaches the file.
env.fireEvent("PLAYER_LOGOUT")

-- ------------------------------------------------------- write, then read back

local text = "\nChatifyDB = " .. (serialise(_G.ChatifyDB, nil, "\t", "ChatifyDB") or "nil") .. "\n"
if _G.ChatifyHistoryDB then
    text = text .. "ChatifyHistoryDB = " ..
        (serialise(_G.ChatifyHistoryDB, nil, "\t", "ChatifyHistoryDB") or "nil") .. "\n"
end

local chunk, err = loadstring(text, "SavedVariables")
if not chunk then
    print("roundtrip: the written file does not parse: " .. tostring(err))
    os.exit(1)
end

-- ------------------------------------------------- session two: fresh client

_G.ChatifyDB, _G.ChatifyHistoryDB = nil, nil
chunk()

local restoredSV = _G.ChatifyDB

-- Second session: a fresh AceDB reading the file that was just written. The
-- addon files are not reloaded (their locals would collide); only the database
-- is rebuilt, which is the part under test.
local addon2 = { db = LibStub("AceDB-3.0"):New("ChatifyDB", ns.defaults, true) }

-- The session marker must survive too, and it is the thing the /chatifydb
-- report leans on: it lives in the global section with no default, so AceDB's
-- removeDefaults never touches it. If this ever comes back nil, the report
-- would tell users their file was lost when it was not.
local markerCount = addon2.db.global and tonumber(addon2.db.global.sessionCount)
print("session marker after reload: " .. tostring(markerCount))
if not markerCount or markerCount < 1 then
    print("  LOST: global.sessionCount did not survive")
    failuresExtra = true
end

-- --------------------------------------------------------------- the verdict

local failures = 0
if failuresExtra then failures = failures + 1 end
print(("-"):rep(60))
print("file size: " .. #text .. " bytes")
print("profileKeys present: " .. tostring(restoredSV and restoredSV.profileKeys ~= nil))

for _, change in ipairs(CHANGES) do
    local key, want = change[1], change[2]
    local got = addon2.db.profile[key]
    local ok = got == want
    if not ok then failures = failures + 1 end
    print(string.format("  %-20s want %-8s got %-8s %s",
        key, tostring(want), tostring(got), ok and "ok" or "LOST"))
end

local label = addon2.db.profile.channelLabels and addon2.db.profile.channelLabels.PARTY
if label ~= "Grp" then
    failures = failures + 1
    print(string.format("  %-20s want %-8s got %-8s LOST", "channelLabels.PARTY", "Grp", tostring(label)))
else
    print(string.format("  %-20s want %-8s got %-8s ok", "channelLabels.PARTY", "Grp", tostring(label)))
end

if #dropped > 0 then
    print("values the writer could not represent:")
    for _, item in ipairs(dropped) do print("  " .. item) end
end

print(("-"):rep(60))
if failures == 0 then
    print("roundtrip: settings survive a logout")
    os.exit(0)
end
print("roundtrip: " .. failures .. " setting(s) lost across logout")
os.exit(1)
