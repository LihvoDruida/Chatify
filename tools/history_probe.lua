-- Chat history routing probe.
--
--     lua5.1 tools/history_probe.lua
--
-- Every chat frame that shows any numbered channel is registered for the single
-- CHAT_MSG_CHANNEL event, so event registration alone cannot say *which* channel a
-- frame receives. History used to file a channel message into every frame registered
-- for the event, which put a [1. General] line into every history tab.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install(os.getenv("CHATIFY_STUB_MODE") or "retail")

local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end

local addon = LibStub("AceAddon-3.0"):GetAddon("Chatify")
pcall(addon.OnInitialize, addon)
pcall(addon.OnEnable, addon)
for _, mod in pairs(addon.modules or {}) do
    pcall(mod.OnInitialize, mod)
    pcall(mod.OnEnable, mod)
end

local history = addon.modules["History"]
local db = addon.db.profile
db.enableHistory = true

local failures = 0
local function check(label, condition, detail)
    print(string.format("%-52s %s%s", label, condition and "PASS" or "FAIL",
        detail and ("  " .. tostring(detail)) or ""))
    if not condition then failures = failures + 1 end
end

-- Three frames all registered for CHAT_MSG_CHANNEL. Only ChatFrame3 is subscribed
-- to General; ChatFrame2 has a different custom channel.
for i = 1, 3 do
    local frame = _G["ChatFrame" .. i]
    frame.IsEventRegistered = function(_, event) return event == "CHAT_MSG_CHANNEL" end
    frame.channelList = {}
    frame.zoneChannelList = {}
end
_G.ChatFrame2.channelList = { "SomeGuildRecruitment" }
_G.ChatFrame3.channelList = { "General" }
_G.ChatFrame3.zoneChannelList = { 1 }

local function entryCount(index)
    local entries = ns.GetChatifyHistoryEntriesForFrame(_G["ChatFrame" .. index], 250)
    return entries and #entries or 0
end

history:OnChatEvent("CHAT_MSG_CHANNEL", "hello general", "Bob-Realm",
    "", "1. General", "", 0, 1, 1, "General")

check("subscribed frame receives the channel line", entryCount(3) == 1, entryCount(3))
check("unsubscribed frame does not", entryCount(1) == 0, entryCount(1))
check("frame on a different channel does not", entryCount(2) == 0, entryCount(2))

-- A channel nobody is subscribed to must not be dropped outright: filing it too
-- widely is a lesser failure than losing it, so the narrowing only applies when
-- something survived it.
history:OnChatEvent("CHAT_MSG_CHANNEL", "mystery channel", "Bob-Realm",
    "", "9. Unknown", "", 0, 9, 9, "UnknownChannel")
check("a channel no frame claims is still kept somewhere",
    entryCount(1) + entryCount(2) + entryCount(3) > 1)

-- Non-channel events keep routing by event registration alone.
for i = 1, 3 do
    _G["ChatFrame" .. i].IsEventRegistered = function(_, event)
        return event == "CHAT_MSG_GUILD" and i ~= 2
    end
end
local before = { entryCount(1), entryCount(2), entryCount(3) }
history:OnChatEvent("CHAT_MSG_GUILD", "guild line", "Bob-Realm")
check("guild line reaches frames registered for the event",
    entryCount(1) == before[1] + 1 and entryCount(3) == before[3] + 1)
check("guild line skips the frame not registered", entryCount(2) == before[2])

-- The shape a current client actually presents: the FrameXML globals and the
-- per-frame channel tables are gone, and the only membership test left is the
-- renamed ChatFrameUtil.ContainsChannel. Routing has to survive that, because it is
-- where the reported bug lives - every test answering "no opinion" means every
-- frame is kept and the line lands in all history tabs.
if _G.ChatFrameUtil and type(_G.ChatFrameUtil.ContainsChannel) == "function" then
    ns.ResetChatAPICache()
    _G.ChatFrame_ContainsChannel = nil
    if type(ns.InvalidateChatifyHistoryFrameCache) == "function" then
        ns.InvalidateChatifyHistoryFrameCache()
    end

    for i = 1, 3 do
        local frame = _G["ChatFrame" .. i]
        -- Restored: the guild section above narrowed registration to CHAT_MSG_GUILD.
        frame.IsEventRegistered = function(_, event) return event == "CHAT_MSG_CHANNEL" end
        frame.channelList = nil
        frame.zoneChannelList = nil
        frame.stubSubscribedChannels = {}
    end
    _G.ChatFrame3.stubSubscribedChannels = { "General" }

    local base = { entryCount(1), entryCount(2), entryCount(3) }
    history:OnChatEvent("CHAT_MSG_CHANNEL", "modern client line", "Bob-Realm",
        "", "1. General", "", 0, 1, 1, "General")

    check("renamed API narrows to the subscribed frame",
        entryCount(3) == base[3] + 1, entryCount(3) - base[3])
    check("renamed API keeps the line out of other frames",
        entryCount(1) == base[1] and entryCount(2) == base[2])
end

print(failures == 0 and "\nhistory probe: PASS"
    or ("\nhistory probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
