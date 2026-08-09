--[[
Checks that everything Chatify puts in SavedVariables can actually be written
back out by the client.

    lua5.1 tools/savedvars_test.lua

Why this exists: "my settings reset at every logout" is almost never the addon
deliberately clearing anything. It is the SavedVariables file failing to be
written or failing to parse on the way back in, at which point the client
discards it and the addon starts from defaults. Both ChatifyDB and
ChatifyHistoryDB live in the same file, so one bad value in chat history takes
the settings with it.

The client's writer can only represent nil, booleans, numbers, strings and
tables of those. Anything else - a function, a frame, a coroutine - is silently
dropped or produces a file that will not load. Numbers have their own traps:
inf and nan are written as "inf"/"nan", which is not valid Lua on the way back.
Table keys must be strings or numbers, and the graph must be acyclic.

This walks the default profile and a simulated session and reports anything the
writer could not round-trip.
]]

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install(os.getenv("CHATIFY_STUB_MODE") or "retail")

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

for _, file in ipairs(tocFiles()) do
    assert(loadfile(file))(addonName, ns)
end

local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
if addon and addon.OnInitialize then
    pcall(addon.OnInitialize, addon)
end

-- ------------------------------------------------------------------ the check

local problems = {}

local function report(path, message)
    problems[#problems + 1] = path .. ": " .. message
end

local function describe(value)
    local t = type(value)
    if t == "number" then
        if value ~= value then return "nan" end
        if value == math.huge or value == -math.huge then return "inf" end
    end
    return t
end

local function check(value, path, seen)
    seen = seen or {}
    local t = type(value)

    if t == "nil" or t == "boolean" or t == "string" then
        return
    end

    if t == "number" then
        -- inf and nan are written literally and the file will not parse back.
        if value ~= value or value == math.huge or value == -math.huge then
            report(path, "number is " .. describe(value) .. ", which cannot round-trip")
        end
        return
    end

    if t ~= "table" then
        report(path, "value of type '" .. t .. "' cannot be saved")
        return
    end

    if seen[value] then
        report(path, "table is part of a cycle")
        return
    end
    seen[value] = true

    for key, sub in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then
            report(path, "table key of type '" .. keyType .. "' cannot be saved")
        elseif keyType == "number" and (key ~= key or key == math.huge) then
            report(path, "table key is " .. describe(key))
        end

        local childPath
        if keyType == "string" then
            childPath = path .. "." .. key
        else
            childPath = path .. "[" .. tostring(key) .. "]"
        end
        check(sub, childPath, seen)
    end

    seen[value] = nil
end

-- 1. The shipped defaults. Anything unsaveable here affects every user.
check(ns.defaults and ns.defaults.profile, "defaults.profile")

-- 2. The live profile after initialisation and the migrations that run on login.
local profile = addon and addon.db and addon.db.profile
check(profile, "ChatifyDB.profile")

-- 3. A simulated session: drive the history capture, then the logout save, and
--    check what would actually be written.
local history = addon and addon.modules and addon.modules.History
if history then
    pcall(history.OnEnable, history)

    local samples = {
        { "CHAT_MSG_SAY", "hello", "Bob" },
        { "CHAT_MSG_GUILD", "|cffa335ee|Hitem:19019|h[Thunderfury]|h|r wts", "Ann" },
        { "CHAT_MSG_CHANNEL", "wtb boost", "Cid", "", "1. General", "", 0, 1, "General" },
        { "CHAT_MSG_WHISPER", "hi \195\169\195\188\195\159 \208\191\209\128\208\184\208\178\209\150\209\130", "Dan" },
    }
    for _, sample in ipairs(samples) do
        pcall(history.OnChatEvent, history, unpack(sample))
    end

    pcall(history.SaveHistory, history)
    check(_G.ChatifyHistoryDB, "ChatifyHistoryDB")
end

-- ----------------------------------------------------------------- the verdict

print(("-"):rep(60))
if #problems == 0 then
    print("savedvars: everything can be written and read back")
    os.exit(0)
end

print("savedvars: " .. #problems .. " value(s) the client cannot save")
for _, problem in ipairs(problems) do
    print("  " .. problem)
end
os.exit(1)
