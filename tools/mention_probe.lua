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

-- 2b. The rendered line contains the player's own name inside Blizzard's sender
--     link, so the swap must land on the message body and nowhere else. Reported as
--     raw |Hplayer:...| markup appearing in chat.
local SENDER_LINK = "|Hplayer:Malivil-DefiasBrotherhood:9:SAY:|h[Malivil]|h says: "

local ITEM = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"

local selfName = render("CHAT_MSG_SAY", "Malivil", SENDER_LINK .. "Malivil", "Malivil-DefiasBrotherhood")

db.mentionRules[1].text = "Mal"
ns.RefreshMentionRuntime()
local short = render("CHAT_MSG_SAY", "Mal", SENDER_LINK .. "Mal", "Malivil-DefiasBrotherhood")
db.mentionRules[1].text = "Malivil"
ns.RefreshMentionRuntime()

local withItem = render("CHAT_MSG_SAY", ITEM .. " for Malivil",
    SENDER_LINK .. ITEM .. " for Malivil", "Bob")

-- The sender link must survive intact whichever path is in force: on the filter
-- path nothing touches the rendered line at all, on the render path the swap has to
-- land on the message body.
check("sender link is never corrupted",
    selfName:find("|Hplayer:Malivil-DefiasBrotherhood:9:SAY:|h[Malivil]|h says: ", 1, true) == 1
        and short:find("|Hplayer:Malivil-DefiasBrotherhood:9:SAY:|h[Malivil]|h says: ", 1, true) == 1,
    selfName)

if ns.ShouldHighlightMentionsOnRender() then
    check("only the message body is highlighted",
        selfName == SENDER_LINK .. "|cffffd700Malivil|r", selfName)
    check("short rule does not corrupt the sender link",
        short == SENDER_LINK .. "|cffffd700Mal|r", short)
    check("message opening with an item link is still highlighted",
        withItem:find("|cffffd700Malivil|r", 1, true) ~= nil
            and withItem:find("|Hitem:19019", 1, true) ~= nil, withItem)
else
    check("render path leaves the line alone entirely",
        selfName == SENDER_LINK .. "Malivil" and short == SENDER_LINK .. "Mal", selfName)
end

-- 2c. Two rules where one word is a prefix of the other, which is the reported
--     configuration ("Malivil" and "Mal", both whole-word). A parked message stays
--     in the queue for a few seconds so it can reach every chat frame, so the short
--     one must not attach itself to the next line.
db.mentionRules = {
    { text = "Malivil", color = "ffd700", sound = "None", channels = "SAY",
      ignoreCase = true, wholeWord = true, enabled = true },
    { text = "Mal", color = "ffd700", sound = "None", channels = "SAY",
      ignoreCase = true, wholeWord = true, enabled = true },
}
ns.RefreshMentionRuntime()

-- Whole-word matching itself, with both rules live.
check("whole word: 'Mal' does not match inside 'malivil'",
    ns.ApplyMentionRules("malivil", "CHAT_MSG_SAY", "Bob") == "|cffffd700malivil|r",
    ns.ApplyMentionRules("malivil", "CHAT_MSG_SAY", "Bob"))
check("whole word: 'yesterday' is not matched by a 'yes' style rule",
    ns.ApplyMentionRules("yesterday", "CHAT_MSG_SAY", "Bob") == "yesterday")

-- Now the queue. Send "Mal", then "Malivil", without clearing in between.
ns.StopMentionRenderCapture()
ns.RefreshMentionRenderCapture()
local function fireOnly(event, raw, ...)
    for _, f in ipairs(allFrames) do
        local handler = f.__scripts and f.__scripts.OnEvent
        if handler and f.__events and f.__events[event] then
            handler(f, event, raw, ...)
        end
    end
end

fireOnly("CHAT_MSG_SAY", "Mal", "Malivil-DefiasBrotherhood")
local firstLine = ns.ApplyPendingMentionRender(SENDER_LINK .. "Mal")
fireOnly("CHAT_MSG_SAY", "Malivil", "Malivil-DefiasBrotherhood")
local secondLine = ns.ApplyPendingMentionRender(SENDER_LINK .. "Malivil")
local thirdLine = ns.ApplyPendingMentionRender(SENDER_LINK .. "normal talk")

if ns.ShouldHighlightMentionsOnRender() then
    check("queued short message stays on its own line",
        firstLine == SENDER_LINK .. "|cffffd700Mal|r", firstLine)
    check("a stale entry does not colour part of a longer word",
        secondLine == SENDER_LINK .. "|cffffd700Malivil|r", secondLine)
    check("a stale entry does not touch an unrelated line",
        thirdLine == SENDER_LINK .. "normal talk", thirdLine)
end

db.mentionRules = {
    { text = "Malivil", color = "ffd700", sound = "None",
      channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
      ignoreCase = true, wholeWord = true, enabled = true },
}
ns.RefreshMentionRuntime()

-- 2d. A secret payload must be rejected by the capture frame, and must be rejected
--     by the guard rather than by a later check that has already read it.
--
--     The harness cannot reproduce the in-game error - see the note in wow_env.lua,
--     a marked value is an ordinary Lua string here and comparing it succeeds. What
--     is asserted is that the guard was consulted and nothing was queued.
if env.markSecret and env.secretString then
    local guardCalls = 0
    local realGuard = ns.CanMutateChatPayload
    ns.CanMutateChatPayload = function(...)
        guardCalls = guardCalls + 1
        return realGuard(...)
    end

    ns.StopMentionRenderCapture()
    ns.RefreshMentionRenderCapture()
    fireOnly("CHAT_MSG_GUILD", env.secretString, env.markSecret("Someone-Realm"))

    check("secret payload consults the guard", guardCalls > 0, guardCalls)
    check("secret payload is never queued",
        ns.ApplyPendingMentionRender("Guild line: " .. env.secretString)
            == "Guild line: " .. env.secretString)

    ns.CanMutateChatPayload = realGuard
end

-- 3. Channel scoping still applies: a rule limited to GUILD must not fire in SAY.
db.mentionRules[1].channels = "GUILD"
ns.RefreshMentionRuntime()
local scoped = render("CHAT_MSG_SAY", "hey Malivil", "Bob says: hey Malivil", "Bob")
check("rule scoped to GUILD does not fire in SAY",
    scoped == "Bob says: hey Malivil", scoped)

print(failures == 0 and "\nmention probe: PASS" or ("\nmention probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
