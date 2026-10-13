-- R1-07: exercise the real AutoReply event and ticker handlers with strict
-- queue contracts. These are synthetic API fixtures, not live server sends.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
local uptime, wall = 1000, 1791910000
_G.GetTime = function() return uptime end
_G.time = function() return wall end
_G.UnitIsAFK = function() return false end
_G.IsInInstance = function() return false, "none" end
_G.LE_LFG_CATEGORY_LFD, _G.LE_LFG_CATEGORY_RF, _G.LE_LFG_CATEGORY_SCENARIO = 1, 2, 3
local lfgMode, lfgWait, lfgName, failLFG = nil, nil, nil, false
local selectedLFGCategory = 1
_G.GetLFGMode = function(category)
    if failLFG then error("LFG transition") end
    return category == selectedLFGCategory and lfgMode or nil
end
_G.GetLFGQueueStats = function(category)
    if failLFG then error("LFG stats temporarily unavailable") end
    local args = { lfgMode ~= nil and category == selectedLFGCategory }
    args[11], args[16] = lfgName, lfgWait
    return unpack(args, 1, 18)
end
local bgStatus, bgWait, bgName, failBG = "none", nil, nil, false
_G.GetMaxBattlefieldID = function() return 2 end
_G.GetBattlefieldStatus = function(index)
    if failBG then error("BG queue status unavailable") end
    if index == 1 then
        return bgStatus, bgName, 0, false, false, "BATTLEGROUND", nil, 777777
    end
    return "none", nil
end
_G.GetBattlefieldEstimatedWaitTime = function(index)
    if failBG then error("BG estimate unavailable") end
    return index == 1 and bgWait or 0
end
_G.C_PvP = { GetActiveMatchState = function() return 0 end }
local ticker
C_Timer.NewTicker = function(_, callback)
    ticker = callback
    return { Cancel = function() end }
end
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))
local module = assert(addon.modules.AutoReply)
local db = assert(addon.db.profile.autoReply)
local char = assert(addon.db.char)
db.enabled, db.autoNotify, db.onlyFriends, db.guildReplyEnabled = true, true, false, true
local events, sent = {}, {}
module.RegisterEvent = function(_, name, fn)
    if type(fn) == "function" then events[name] = fn end
end
module.RegisterChatCommand = function() end
module.UnregisterAllEvents = function() events = {} end
module.UnregisterChatCommand = function() end
ns.IsFeatureAvailable = function() return true end
local sendingAllowed, sendingSucceeds = true, true
ns.CanSendAddonChat = function() return sendingAllowed end
ns.SendChatMessageCompat = function(message, channel, _, target)
    if not sendingAllowed or not sendingSucceeds then return false end
    sent[#sent+1] = {message=message, channel=channel, target=target}
    return true
end
module:OnEnable()
assert(type(ticker) == "function" and type(events.CHAT_MSG_WHISPER) == "function", "handlers not registered")
local tests = 0
local function check(ok, message)
    tests = tests + 1
    assert(ok, "auto-reply " .. message)
end
local function advance(seconds)
    uptime = uptime + (seconds or 4)
    wall = wall + (seconds or 4)
end
local function whisper(sender)
    events.CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "hello", sender or "Bob-Realm")
end
local function last() return sent[#sent] and sent[#sent].message or "" end
-- Dungeon LFG: mode is authoritative even when the estimate is zero/absent.
lfgMode, lfgWait, lfgName = "queued", 185, "Dungeon A"
whisper()
check(#sent == 1 and last():find("3 minutes", 1, true) ~= nil, "LFG seconds->minutes")
check(last():find("Dungeon A", 1, true) ~= nil, "LFG name from slot 11")
whisper()
check(#sent == 1, "sender cooldown")
advance(310)
lfgWait = 0
whisper()
check(#sent == 2 and last():find("? minutes", 1, true) ~= nil, "queued without estimate")
-- An unaccepted proposal still counts as queued (no estimate required).
advance(310)
lfgMode = "proposal"
whisper("Proposal-Realm")
check(#sent == 3 and last():find("? minutes", 1, true) ~= nil, "LFG proposal")
-- Some hybrid clients expose RF but not LFD. Lua ipairs must not stop at nil.
LE_LFG_CATEGORY_LFD = nil
selectedLFGCategory = 2
lfgMode, lfgName, lfgWait = "queued", "Raid Finder", 240
advance(4)
whisper("Raid-Realm")
check(#sent == 4 and last():find("4 minutes", 1, true) ~= nil, "RF without LFD constant")
LE_LFG_CATEGORY_LFD = 1
selectedLFGCategory = 1
-- The BG estimated time is milliseconds, NOT position #8 of status results.
lfgMode = nil
bgStatus, bgWait, bgName = "queued", 185000, "Warsong"
advance(4)
whisper("BG-Realm")
check(#sent == 5 and last():find("3 minutes", 1, true) ~= nil, "BG milliseconds->minutes")
check(last():find("Warsong", 1, true) ~= nil, "BG name")
advance(4)
bgStatus, bgWait = "confirm", nil
whisper("Confirm-Realm")
check(#sent == 6 and last():find("? minutes", 1, true) ~= nil, "BG confirmation without wait")
-- Active PvPMatchState enum must be treated as match context, not queue payload.
bgStatus = "active"
C_PvP.GetActiveMatchState = function() return 3 end
advance(4)
whisper("Match-Realm")
check(#sent == 7 and last():find("PvP", 1, true) ~= nil, "active match state enum")
C_PvP.GetActiveMatchState = function() return 0 end
-- API transient failures must not send premature return notices or clear pending.
failLFG, failBG = true, true
local before = #sent
advance(4)
ticker()
check(#sent == before and char.pendingWhispers["BG-Realm"] ~= nil, "unknown state preserved pending")
-- Return notifications are deferred during sending lockdown; retry preserves
-- pending, clears after a successful allowed attempt, and never double sends.
failLFG, failBG = false, false
bgStatus = "none"
sendingAllowed = false
advance(4)
ticker()
check(char.pendingWhispers["BG-Realm"] ~= nil and #sent == before, "lockdown preserves pending")
sendingAllowed = true
advance(16)
ticker()
check(#sent > before, "successful pending return")
check(next(char.pendingWhispers) == nil, "successful returns clear pending")
local after = #sent
advance(16)
ticker()
check(#sent == after, "return delivered only once")
-- A single sender may whisper AND mention us in guild. Return once only.
db.busyMode = true
advance(310)
whisper("Both-Realm")
assert(type(events.CHAT_MSG_GUILD) == "function", "guild handler missing")
events.CHAT_MSG_GUILD("CHAT_MSG_GUILD", "Tester check this", "Both-Realm")
check(char.pendingWhispers["Both-Realm"] ~= nil and char.pendingGuildMentions["Both-Realm"] ~= nil,
    "whisper and guild mention both tracked")
local beforeBoth = #sent
db.busyMode = false
advance(16)
ticker()
check(#sent == beforeBoth + 1, "deduplicate multi-channel pending return")
check(char.pendingWhispers["Both-Realm"] == nil and char.pendingGuildMentions["Both-Realm"] == nil,
    "clear both pending channels")
-- Explicit failed send, not merely a restricted API, must be retried.
db.busyMode = true
advance(310)
whisper("Retry-Realm")
check(char.pendingWhispers["Retry-Realm"] ~= nil, "pending before failed return")
db.busyMode = false
sendingSucceeds = false
advance(16)
ticker()
check(char.pendingWhispers["Retry-Realm"] ~= nil, "failed send does not lose pending")
sendingSucceeds = true
advance(16)
ticker()
check(char.pendingWhispers["Retry-Realm"] == nil, "failed send retried")
module:OnDisable()
print("auto-reply R1-07 queue/lifecycle: PASS " .. tests)
