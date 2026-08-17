-- Mention Manager end-to-end probe.
--
--     lua5.1 tools/mention_probe.lua              (retail, secret values)
--     CHATIFY_STUB_MODE=classic lua5.1 tools/mention_probe.lua
--
-- Reproduces the 0.11.38 bug in one run: on a 12.x client the message-event
-- filters are never installed, so ns.ApplyMentionRules is never reached and the
-- Mention Manager is silently inert. Then it drives the render-time fallback the
-- way the game does - chat event first, AddMessage second - and asserts the
-- highlight actually lands in the rendered line.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local mode = os.getenv("CHATIFY_STUB_MODE") or "retail"
env.install(mode)

local installedFilters = {}
_G.ChatFrame_AddMessageEventFilter = function(event)
    installedFilters[#installedFilters + 1] = event
    return true
end
if _G.C_ChatInfo then
    _G.C_ChatInfo.AddMessageEventFilter = _G.ChatFrame_AddMessageEventFilter
end

-- Every frame the addon creates, so the probe can drive the mention capture frame
-- the way the client drives it.
local allFrames = {}
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(...)
    local frame = realCreateFrame(...)
    allFrames[#allFrames + 1] = frame
    return frame
end

local ns, addonName = {}, "Chatify"
local function tocFiles()
    local files = {}
    for line in assert(io.open("Chatify.toc")):lines() do
        line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") and line:match("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end
for _, file in ipairs(tocFiles()) do assert(loadfile(file))(addonName, ns) end

local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
pcall(addon.OnInitialize, addon)
pcall(addon.OnEnable, addon)
for _, mod in pairs(addon.modules or {}) do
    pcall(mod.OnInitialize, mod)
    pcall(mod.OnEnable, mod)
end

local db = addon.db and addon.db.profile
print("mode                       :", mode)
print("IsRetailSecretValueBuild   :", ns.IsRetailSecretValueBuild())
print("GetRetailChatFilterMode    :", ns.GetRetailChatFilterMode())
print("CanUseMessageEventFilters  :", ns.CanUseMessageEventFilters())
print("message filters installed  :", #installedFilters)
print("highlight on render        :", ns.ShouldHighlightMentionsOnRender())

-- The rule from the bug report.
db.enableMentionManager = true
db.mentionRules = { {
    text = "Malivil", color = "ffd700", sound = "None",
    channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
    ignoreCase = true, wholeWord = true, enabled = true,
} }
ns.db = db
ns.RefreshMentionRuntime()

local failures = 0
local function check(label, condition, detail)
    print(string.format("%-46s %s%s", label, condition and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
    if not condition then failures = failures + 1 end
end

-- 1. The matching logic itself, called directly.
local direct = ns.ApplyMentionRules("hey malivil can you inv", "CHAT_MSG_SAY", "Bob")
check("rule matches through ApplyMentionRules", direct:find("|cffffd700", 1, true) ~= nil, direct)

-- 2. The render path: chat event, then the line Blizzard would build.
local function render(event, raw, rendered, ...)
    ns.StopMentionRenderCapture()
    ns.RefreshMentionRenderCapture()
    -- Drive the capture frame the way the client does.
    for _, f in ipairs(allFrames) do
        local handler = f.__scripts and f.__scripts.OnEvent
        if handler and f.__events and f.__events[event] then
            handler(f, event, raw, ...)
        end
    end
    return ns.ApplyPendingMentionRender(rendered)
end

local say = render("CHAT_MSG_SAY", "hey Malivil can you inv",
    "Bob says: hey Malivil can you inv", "Bob")
local chan = render("CHAT_MSG_CHANNEL", "MALIVIL come here",
    "[2. General] Bob: MALIVIL come here", "Bob", "", 0, 2, "", 0, 2, "General")
local miss = render("CHAT_MSG_SAY", "nothing to see", "Bob says: nothing to see", "Bob")

if ns.ShouldHighlightMentionsOnRender() then
    check("SAY highlight reaches the rendered line",
        say:find("|cffffd700Malivil|r", 1, true) ~= nil, say)
    check("CHANNEL highlight reaches the rendered line",
        chan:find("|cffffd700MALIVIL|r", 1, true) ~= nil, chan)
else
    -- The filter path is in force, so the render path must stay out of the way or
    -- every mention would be coloured twice.
    check("render path idle while filters are installed",
        say:find("|cffffd700", 1, true) == nil and chan:find("|cffffd700", 1, true) == nil, say)
end

check("non-matching line is untouched", miss == "Bob says: nothing to see", miss)

-- 3. Channel scoping still applies: a rule limited to GUILD must not fire in SAY.
db.mentionRules[1].channels = "GUILD"
ns.RefreshMentionRuntime()
local scoped = render("CHAT_MSG_SAY", "hey Malivil", "Bob says: hey Malivil", "Bob")
check("rule scoped to GUILD does not fire in SAY",
    scoped == "Bob says: hey Malivil", scoped)

print(failures == 0 and "\nmention probe: PASS" or ("\nmention probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
