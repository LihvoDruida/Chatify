-- Loads the addon against the stub and exercises its hot paths.
--
--     lua5.1 tools/stub/load_test.lua
--
-- Files are loaded in TOC order with the same (addonName, ns) varargs the game
-- passes, so the shared namespace behaves as it does in the client.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local mode = os.getenv("CHATIFY_STUB_MODE") or "classic"
env.install(mode)

local failures, notes = {}, {}

local function fail(stage, err)
    failures[#failures + 1] = stage .. ": " .. tostring(err)
end

-- --- read the load order straight out of the TOC -------------------------
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

local ns = {}
local addonName = "Chatify"

for _, file in ipairs(tocFiles()) do
    local chunk, err = loadfile(file)
    if not chunk then
        fail("compile " .. file, err)
    else
        local ok, runErr = pcall(chunk, addonName, ns)
        if not ok then
            fail("load " .. file, runErr)
        end
    end
end

-- --- drive the parts that only run in response to the game ---------------
local function try(label, fn, ...)
    if type(fn) ~= "function" then
        notes[#notes + 1] = label .. ": not defined, skipped"
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        fail(label, err)
    end
end

-- Bring the addon up the way AceAddon does, so the hot paths below run against a
-- real database instead of bailing on `not db` and reporting a false pass.
local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
if not addon then
    fail("bootstrap", "AceAddon never received a NewAddon call for " .. addonName)
else
    try("OnInitialize", addon.OnInitialize, addon)
    try("OnEnable", addon.OnEnable, addon)

    for modName, mod in pairs(addon.modules or {}) do
        try("module " .. modName .. ":OnInitialize", mod.OnInitialize, mod)
        try("module " .. modName .. ":OnEnable", mod.OnEnable, mod)
    end

    -- The options table is built lazily now, so nothing would construct it
    -- otherwise; a runtime error inside it takes the whole panel away in game.
    try("GetOptions", addon.GetOptions, addon)
    local registered = env.registeredOptions and env.registeredOptions[addonName]
    if type(registered) == "function" then
        try("registered options builder", registered)
    end
end

-- A profile shaped like the real defaults, so the hot paths see live settings
-- rather than an empty table.
local profile = ns.Defaults and ns.Defaults.profile
if type(profile) ~= "table" then
    profile = {
        shortChannels = true,
        enableTimestamps = true,
        channelModes = {},
        channelLabels = {},
        channelLabelsNamed = {},
        channelLabelNames = {},
        scrollbackLines = 500,
        chatFadeTime = 120,
        lineSpacing = 0,
        enableScrollTweaks = true,
        scrollLinesPerNotch = 3,
    }
end

if addon and addon.db and addon.db.profile then
    -- Turn everything on, so the label engine actually does work rather than
    -- short-circuiting on an inactive map and passing vacuously.
    local p = addon.db.profile
    p.shortChannels = true
    p.enableTimestamps = true
    p.channelModes = p.channelModes or {}
    for _, entry in ipairs((ns.Lists and ns.Lists.ChannelLabels) or {}) do
        p.channelModes[entry.token] = "short"
    end
    p.channelModes.GENERAL = "custom"
    p.channelLabelsNamed = p.channelLabelsNamed or {}
    p.channelLabelsNamed.GENERAL = "#Gen"
    p.channelModes.TRADE = "hidden"
    profile = p
    if type(ns.InvalidateChannelLabelCache) == "function" then
        pcall(ns.InvalidateChannelLabelCache)
    end
else
    notes[#notes + 1] = "addon.db.profile unavailable; label paths ran with defaults"
end

-- Channel label engine: the piece most recently rewritten, and the one that
-- runs once per rendered line.
local samples = {
    "|Hchannel:PARTY|h[Party]|h |Hplayer:Bob|h[Bob]|h: go",
    "|Hchannel:GUILD|h[Guild]|h |Hplayer:Ann|h[Ann]|h: hi",
    "|Hchannel:CHANNEL:1|h[1. General - Elwynn Forest]|h |Hplayer:C|h[C]|h: a",
    "|Hchannel:CHANNEL:2|h[2. Trade - City]|h wtb",
    "|Hplayer:Dan|h[Dan]|h whispers: yo",
    "|Hplayer:Eve|h[Eve]|h says: hello",
    "To |Hplayer:Fay|h[Fay]|h: bye",
    "plain system text with no markup",
    "",
}

for _, text in ipairs(samples) do
    try("ApplyChannelLabels(" .. (#text > 28 and text:sub(1, 28) .. "..." or text) .. ")",
        ns.ApplyChannelLabels, text)
end

-- Non-string and adversarial inputs: these reach the same function from
-- AddMessage, where anything can arrive.
for _, bad in ipairs({ 42, true, {}, "|Hchannel:|h[]|h", "|Hchannel:PARTY|h[" }) do
    try("ApplyChannelLabels(malformed)", ns.ApplyChannelLabels, bad)
end

-- Assert the engine produced an effect. Without this the suite passes even when
-- ApplyChannelLabels returns its input untouched, which is exactly the failure
-- mode that shipped in 0.11.29.
if type(ns.ApplyChannelLabels) == "function" then
    local checks = {
        { "|Hchannel:PARTY|h[Party]|h x", "%[P%]", "short label" },
        { "|Hchannel:CHANNEL:1|h[1. General - Elwynn Forest]|h x", "%[1%. Gen%]", "# expansion" },
    }
    for _, c in ipairs(checks) do
        local ok, out = pcall(ns.ApplyChannelLabels, c[1])
        if not ok then
            fail("effect check " .. c[3], out)
        elseif type(out) ~= "string" or not out:find(c[2]) then
            fail("effect check " .. c[3],
                 "expected " .. c[2] .. ", got " .. tostring(out))
        end
    end

    local okHide, hidden = pcall(ns.ApplyChannelLabels,
        "|Hchannel:CHANNEL:2|h[2. Trade - City]|h wtb")
    if okHide and type(hidden) == "string" and hidden:find("|Hchannel", 1, true) then
        fail("effect check hidden mode", "tag survived: " .. hidden)
    end
end

-- On the retail shape, push a value the client has marked secret through every
-- entry point that receives chat payloads.
--
-- The assertion is identity, not absence of an error. Almost everything here is
-- wrapped in pcall, so a swallowed error is indistinguishable from a clean pass;
-- what actually matters is that the payload comes back byte-identical, having
-- been passed through rather than rewritten.
if mode == "retail" and env.secretString then
    local secret = env.secretString

    local function mustPassThrough(label, fn, ...)
        if type(fn) ~= "function" then
            notes[#notes + 1] = label .. ": not defined, skipped"
            return
        end
        local ok, out = pcall(fn, ...)
        if not ok then
            fail(label, out)
        elseif type(out) == "string" and out ~= secret then
            fail(label, "rewrote a secret payload: " .. string.format("%q", out))
        end
    end

    mustPassThrough("ApplyChannelLabels(secret)", ns.ApplyChannelLabels, secret)
    mustPassThrough("FormatMessage(secret)", ns.FormatMessage, secret, "CHAT_MSG_GUILD", "Bob")

    try("HasSecretChatValue(secret)", ns.HasSecretChatValue, secret)
    try("CanAccessChatValue(secret)", ns.CanAccessChatValue, secret)
    try("ProcessSpamMessage(secret)", ns.ProcessSpamMessage, secret, "CHAT_MSG_CHANNEL", "Bob")

    -- HasSecretChatValue must actually recognise it, or every guard downstream
    -- is a no-op and the checks above pass for the wrong reason.
    if type(ns.HasSecretChatValue) == "function" then
        local ok, flagged = pcall(ns.HasSecretChatValue, secret)
        if not ok or not flagged then
            fail("HasSecretChatValue(secret)",
                 "did not recognise the payload as secret; every guard below it is inert")
        end
    end

    local frame = _G.ChatFrame1
    local ok, err = pcall(frame.AddMessage, frame, secret)
    if not ok then
        fail("AddMessage(secret)", err)
    elseif frame.__last ~= secret then
        fail("AddMessage(secret)",
             "the label hook rewrote a secret payload before passing it on: "
             .. string.format("%q", tostring(frame.__last)))
    end
end

try("GetJoinedChannels", ns.GetJoinedChannels)
try("NormalizeChannelName", ns.NormalizeChannelName, "General - Elwynn Forest")
try("ChannelNameKey", ns.ChannelNameKey, "Looking For Group")
try("GetKnownChannelKeys", ns.GetKnownChannelKeys, profile)
try("RememberChannelNames", ns.RememberChannelNames, profile)
try("MigrateChannelLabels", ns.MigrateChannelLabels, profile)
try("GetChannelMode", ns.GetChannelMode, profile, "PARTY",
    ns.Lists and ns.Lists.ChannelLabels and ns.Lists.ChannelLabels[1])
try("SplitChatTemplate", ns.SplitChatTemplate, "CHAT_WHISPER_GET")
try("SplitChatTemplate(missing)", ns.SplitChatTemplate, "NO_SUCH_GLOBALSTRING")

for _, entry in ipairs((ns.Lists and ns.Lists.ChannelLabels) or {}) do
    try("GetBuiltinChannelDefault(" .. entry.token .. ")",
        ns.GetBuiltinChannelDefault, entry)
end

try("ApplyVisuals", ns.ApplyVisuals)
try("RefreshChannelLabelHook", ns.RefreshChannelLabelHook)
try("RemoveChannelLabelHook", ns.RemoveChannelLabelHook)
try("InvalidateChannelLabelCache", ns.InvalidateChannelLabelCache)
try("InvalidateChannelListCache", ns.InvalidateChannelListCache)

try("GetCVarCompat", ns.GetCVarCompat, "showTimestamps")
try("SetCVarCompat", ns.SetCVarCompat, "showTimestamps", "none")
try("GetChatAPI", ns.GetChatAPI, "ChatFrame_OpenChat", "OpenChat")
try("CallChatAPI", ns.CallChatAPI, "FCF_GetCurrentChatFrame", "GetCurrentChatFrame")
try("GetProjectKey", ns.GetProjectKey)
try("IsRetailSecretValueBuild", ns.IsRetailSecretValueBuild)
try("HasSecretChatValue", ns.HasSecretChatValue, "text", nil, 5)
try("CanAccessChatValue", ns.CanAccessChatValue, "text", nil, 5)
try("GetRetailChatFilterMode", ns.GetRetailChatFilterMode)
try("CanUseMessageEventFilters", ns.CanUseMessageEventFilters)
try("InChatTaintRiskWindow", ns.InChatTaintRiskWindow)

-- The AddMessage hook, driven the way the game drives it.
if type(ns.RefreshChannelLabelHook) == "function" then
    local frame = _G.ChatFrame1
    for _, text in ipairs(samples) do
        local ok, err = pcall(frame.AddMessage, frame, text)
        if not ok then fail("ChatFrame1:AddMessage", err) end
    end
end

-- --- report --------------------------------------------------------------
print(("-"):rep(64))
print("mode: " .. mode)
if #notes > 0 then
    print("Notes:")
    for _, n in ipairs(notes) do print("  " .. n) end
    print()
end

local unknown = {}
for k in pairs(env.unknown) do unknown[#unknown + 1] = k end
table.sort(unknown)
if #unknown > 0 then
    print("Stub gaps touched by the addon (" .. #unknown .. "):")
    for _, u in ipairs(unknown) do print("  " .. u) end
    print()
end

if #failures == 0 then
    print("Load test passed: all files loaded and all exercised paths ran clean.")
    os.exit(0)
end

print("Load test FAILED (" .. #failures .. "):")
for _, f in ipairs(failures) do print("  " .. f) end
os.exit(1)
