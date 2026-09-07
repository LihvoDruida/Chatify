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

-- 2. The render path. Blizzard's chat frames draw the line before any addon frame
--    sees the event, so the highlight is applied to the rendered line directly and
--    nothing is carried over from a previous message.
local function render(rendered)
    return ns.HighlightMentionsInRenderedLine(rendered)
end

local SENDER_LINK = "|Hplayer:Malivil-DefiasBrotherhood:9:SAY:|h[Malivil]|h says: "
local GUILD_LINK = "|Hplayer:Bob-Realm:11:GUILD:|h[Bob]|h: "
local CHANNEL_LINK = "|Hchannel:channel:2|h[2. General]|h |Hplayer:Bob-Realm:12:CHANNEL:2|h[Bob]|h: "
local ITEM = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"

local say = render(SENDER_LINK .. "hey Malivil can you inv")
local chan = render(CHANNEL_LINK .. "MALIVIL come here")
local miss = render(SENDER_LINK .. "nothing to see")

if ns.ShouldHighlightMentionsOnRender() then
    check("SAY highlight reaches the rendered line",
        say:find("|cffffd700Malivil|r", 1, true) ~= nil, say)
    check("CHANNEL highlight reaches the rendered line",
        chan:find("|cffffd700MALIVIL|r", 1, true) ~= nil, chan)
else
    check("render path idle when it has nowhere to run",
        say:find("|cffffd700", 1, true) == nil and chan:find("|cffffd700", 1, true) == nil, say)
end

check("non-matching line is untouched", miss == SENDER_LINK .. "nothing to see", miss)

-- 2a. The first message of a given casing must be highlighted. The parking design
--     could only highlight the second identical one, because the event arrived
--     after the line had already been drawn.
if ns.ShouldHighlightMentionsOnRender() then
    db.mentionRules = {
        { text = "hi", color = "ffd700", sound = "None", channels = "SAY",
          ignoreCase = true, wholeWord = true, enabled = true },
    }
    ns.RefreshMentionRuntime()

    check("first 'hi' is highlighted",
        render(SENDER_LINK .. "hi") == SENDER_LINK .. "|cffffd700hi|r",
        render(SENDER_LINK .. "hi"))
    check("first 'Hi' of a new casing is highlighted",
        render(SENDER_LINK .. "Hi") == SENDER_LINK .. "|cffffd700Hi|r",
        render(SENDER_LINK .. "Hi"))
end

db.mentionRules = {
    { text = "Malivil", color = "ffd700", sound = "None", channels = "SAY",
      ignoreCase = true, wholeWord = true, enabled = true },
    { text = "Mal", color = "ffd700", sound = "None", channels = "SAY",
      ignoreCase = true, wholeWord = true, enabled = true },
}
ns.RefreshMentionRuntime()

-- 2b. The sender's own name sits inside Blizzard's player link. Colouring there
--     breaks the link and prints raw |Hplayer:...| markup.
local selfName = render(SENDER_LINK .. "Malivil")
local short = render(SENDER_LINK .. "Mal")
local withItem = render(SENDER_LINK .. ITEM .. " for Malivil")

check("sender link is never corrupted",
    selfName:find(SENDER_LINK, 1, true) == 1 and short:find(SENDER_LINK, 1, true) == 1,
    selfName)

check("whole word: 'Mal' does not match inside 'malivil'",
    ns.ApplyMentionRules("malivil", "CHAT_MSG_SAY", "Bob") == "|cffffd700malivil|r",
    ns.ApplyMentionRules("malivil", "CHAT_MSG_SAY", "Bob"))
check("whole word: a 'yes' style rule does not match 'yesterday'",
    ns.ApplyMentionRules("yesterday", "CHAT_MSG_SAY", "Bob") == "yesterday")

if ns.ShouldHighlightMentionsOnRender() then
    check("only the message body is highlighted",
        selfName == SENDER_LINK .. "|cffffd700Malivil|r", selfName)
    check("a short rule does not colour part of a longer word",
        selfName:find("|cffffd700Mal|rivil", 1, true) == nil, selfName)
    check("message containing an item link keeps the link intact",
        withItem:find("|cffffd700Malivil|r", 1, true) ~= nil
            and withItem:find("|Hitem:19019", 1, true) ~= nil, withItem)
    check("a GUILD line is not highlighted by a SAY-only rule",
        render(GUILD_LINK .. "Malivil") == GUILD_LINK .. "Malivil",
        render(GUILD_LINK .. "Malivil"))
    check("a system line with no sender link is left alone",
        render("Total time played: 141 days") == "Total time played: 141 days")
end

db.mentionRules = {
    { text = "Malivil", color = "ffd700", sound = "None",
      channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
      ignoreCase = true, wholeWord = true, enabled = true },
}
ns.RefreshMentionRuntime()

-- 3. Channel scoping still applies on the filter path, which is what runs on
--    clients where the message-event filters are available.
db.mentionRules[1].channels = "GUILD"
ns.RefreshMentionRuntime()
check("rule scoped to GUILD does not fire in SAY",
    ns.ApplyMentionRules("hey Malivil", "CHAT_MSG_SAY", "Bob") == "hey Malivil",
    ns.ApplyMentionRules("hey Malivil", "CHAT_MSG_SAY", "Bob"))
check("rule scoped to GUILD does fire in GUILD",
    ns.ApplyMentionRules("hey Malivil", "CHAT_MSG_GUILD", "Bob")
        == "hey |cffffd700Malivil|r",
    ns.ApplyMentionRules("hey Malivil", "CHAT_MSG_GUILD", "Bob"))

-- The taint-free alert route.
--
-- This is the only mention path that does not require Chatify to rewrite Blizzard's
-- line, so it is the one that keeps working regardless of how the taint question in
-- docs/own_handler_scope.md is eventually answered. It calls AddMessage rather than
-- replacing it, which is why it cannot taint anything.
local function RunAlertChecks()
    local frame = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    local shown

    local savedAdd = rawget(frame, "AddMessage")
    frame.AddMessage = function(_, line) shown = line return true end

    -- The alert only speaks when nothing else will, and in both shipped configurations
    -- something else does: filters own the line on Classic, the render hook owns it on
    -- Retail. So the condition has to be arranged rather than waited for, using the
    -- same lever /chatifytaint filtertest uses.
    -- Asserted before the conditional below, because every assertion in this block is
    -- guarded by a state that has to be arranged. Run against a build with no alert
    -- route, those guards simply do not open and the probe would report PASS having
    -- tested nothing. The existence of the route is the one thing that must be checked
    -- unconditionally.
    check("the alert route exists",
        type(ns.AnnounceMentionAlert) == "function"
        and type(ns.BuildMentionAlertLine) == "function"
        and type(ns.ShouldAnnounceMentionAlert) == "function")

    if type(ns.AnnounceMentionAlert) ~= "function" then
        return
    end

    local db = ns.db
    local savedLever = db and db.disableRenderHook
    if db then db.disableRenderHook = true end

    local filtersOwnIt = ns.AreMessageFiltersInstalled()
    if filtersOwnIt then
        -- Correct behaviour, not a skipped test: announcing a mention twice is its own
        -- bug, so with the filters installed the alert must stay silent.
        shown = nil
        local suppressed = ns.AnnounceMentionAlert("hey Malivil", "CHAT_MSG_GUILD", "Bob-Realm")
        check("filters owning the line suppress the alert",
            suppressed == false and shown == nil, shown)
    end

    if not filtersOwnIt and not ns.ShouldHighlightMentionsOnRender() then
        shown = nil
        local ok = ns.AnnounceMentionAlert("hey Malivil are you there", "CHAT_MSG_GUILD", "Bob-Realm")
        check("alert is announced when no in-line route is live", ok == true)
        check("alert carries the highlight",
            type(shown) == "string" and shown:find("|cffffd700", 1, true) ~= nil, shown)
        check("alert carries the message text",
            type(shown) == "string" and shown:find("are you there", 1, true) ~= nil, shown)
        check("alert names the author",
            type(shown) == "string" and shown:find("Bob", 1, true) ~= nil, shown)

        -- Announcing twice is its own bug. The render path owning the line must
        -- suppress the alert, not compete with it.
        shown = nil
        local db = ns.db
        local savedEcho = db and db.mentionEcho
        if db then db.mentionEcho = false end
        local offResult = ns.AnnounceMentionAlert("hey Malivil", "CHAT_MSG_GUILD", "Bob-Realm")
        check("the setting suppresses the alert", offResult == false and shown == nil)
        if db then db.mentionEcho = savedEcho end

        -- A secret payload cannot be matched at all, by any route. Blizzard withholds
        -- those from addon filters for the same reason, so this is a limit of the
        -- feature rather than of this implementation.
        if env.secretString then
            shown = nil
            local secretResult = ns.AnnounceMentionAlert(env.secretString, "CHAT_MSG_GUILD", "Bob-Realm")
            check("a secret payload produces no alert",
                secretResult == false and shown == nil)
        end
    end

    if db then db.disableRenderHook = savedLever end
    if savedAdd ~= nil then frame.AddMessage = savedAdd else frame.AddMessage = nil end
end

RunAlertChecks()

print(failures == 0 and "\nmention probe: PASS" or ("\nmention probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
