-- Forever 1.60.1.70532 contracts; the stubs enforce actual argument/return shapes.
-- This does not reproduce Blizzard's secure execution or taint propagation.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
require("client_fixtures").install(env, "forever")
_G.RegionalUniqueNamesEnabled = function() return false end
local primary, realm, locationName = "Sebas Moonbloom", "ServerName", "Sebas Moonbloom"
_G.UnitNameUnmodified = function() return primary, realm end
_G.UnitName = function() return primary, realm end
_G.UnitFullName = function() return primary, realm end
local locationCalls = 0
_G.PlayerLocation = { CreateFromUnit = function(self, unit)
    assert(self == PlayerLocation and unit == "player")
    return { GetUnit = function() return unit end, IsUnit = function() return true end }
end }
_G.C_PlayerInfo = {
    ShouldDisplaySurname = function(...) assert(select("#", ...) == 0); return false end,
    GetName = function(location)
        assert(type(location.GetUnit) == "function" and location:GetUnit() == "player", "PlayerLocationMixin required")
        locationCalls = locationCalls + 1
        return locationName
    end,
}
local converterCalls = 0
_G.C_NameUtil = { ReplaceSurnameSeparatorWithLinkSeparator = function(value, ...)
    assert(select("#", ...) == 0 and type(value) == "string")
    converterCalls = converterCalls + 1
    return (value:gsub("%s+", "-"))
end }
local validityCalls = 0
_G.C_EventUtils = { IsEventValid = function(event, ...)
    assert(select("#", ...) == 0 and type(event) == "string")
    validityCalls = validityCalls + 1
    return event ~= "CHATIFY_REMOVED_EVENT" and event ~= "CHAT_MSG_BN_CONVERSATION"
end }
local ns = {}
for line in io.lines("Chatify_Camelot.toc") do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local checks = 0
local function check(condition, label)
    checks = checks + 1
    assert(condition, "Forever API contract: " .. label)
end
check(ns.IsForeverClient(), "client identity")
local identity = ns.GetPlayerMentionIdentity(true)
check(identity.first == "Sebas" and identity.surname == "Moonbloom", "full identity")
check(identity.shouldDisplaySurname == false and identity.surname == "Moonbloom", "display preference does not erase identity")
check(locationCalls > 0, "GetName fallback used the proper object factory")
primary, locationName = "Sebas", "Sebas Moonbloom"
identity = ns.GetPlayerMentionIdentity(true)
check(identity.source == "C_PlayerInfo.GetName" and identity.surname == "Moonbloom", "complete fallback beats first-only unit name")
locationName = "Sebas"
identity = ns.GetPlayerMentionIdentity(true)
check(identity.surname == nil and identity.full == "Sebas", "unitServer is not surname")
_G.RegionalUniqueNamesEnabled = function() return true end
primary, realm, locationName = "Sebas", "Moonbloom", "Sebas"
identity = ns.GetPlayerMentionIdentity(true)
check(identity.surname == "Moonbloom", "regional two-result identity preserves surname")
_G.NameUtil = { GetUnmodifiedUnitFullName = function(unit) assert(unit == "player"); return "Sebas Moonbloom" end }
identity = ns.GetPlayerMentionIdentity(true)
check(identity.source == "NameUtil.GetUnmodifiedUnitFullName" and identity.surname == "Moonbloom", "flavor full-name helper preferred")
NameUtil = nil
_G.RegionalUniqueNamesEnabled = function() return false end
primary, locationName = "Sebas Moonbloom", "Sebas Moonbloom"
ns.RefreshPlayerMentionIdentity()
check(ns.NormalizePlayerNameCompat("Sebas Moonbloom") == "Sebas-Moonbloom", "documented surname converter")
check(ns.NormalizePlayerNameCompat(env.secretString) == nil, "protected names rejected")
local countBefore = validityCalls
check(not ns.IsEventSupported("CHATIFY_REMOVED_EVENT"), "unsupported event")
check(not ns.IsEventSupported("CHATIFY_REMOVED_EVENT") and validityCalls == countBefore + 1, "event query cached")
local registrations = 0
local target = { RegisterEvent = function() registrations = registrations + 1 end }
check(not ns.RegisterEventIfSupported(target, "CHAT_MSG_BN_CONVERSATION") and registrations == 0, "removed event never registered")
check(ns.RegisterEventIfSupported(target, "CHAT_MSG_GUILD") and registrations == 1, "current event registered")
local box = {
    chatType = "SAY", tellTarget = "Stale-Name", channelTarget = "old channel",
    GetChatType = function() return "WHISPER" end,
    GetTellTarget = function() return "Sebas Moonbloom" end,
    GetChannelTarget = function() return 4 end,
    GetAttribute = function() error("modern getter must take precedence") end,
    IsShown = function() return true end, GetText = function() return "draft" end,
}
check(ns.GetChatEditBoxValue(box, "chatType") == "WHISPER", "modern chat type")
check(ns.GetChatEditBoxValue(box, "tellTarget") == "Sebas Moonbloom", "modern recipient")
check(ns.GetChatEditBoxValue(box, "channelTarget") == 4, "numeric channel getter")
ChatFrame1.GetObjectType = function() return "ScrollingMessageFrame" end
box.chatFrame = ChatFrame1
ChatFrame1.editBox = box
_G.ChatFrame1EditBox = box
ChatFrameUtil.GetLastActiveWindow = function() return box end
local context = ns.GetActiveChatDraftContext()
check(context and context.chatType == "WHISPER" and context.tellTarget == "Sebas Moonbloom" and context.text == "draft", "composer draft uses getters")
box.GetTellTarget = function() return env.secretString end
check(ns.GetChatEditBoxValue(box, "tellTarget") == nil, "secret getter has no stale fallback")
box.GetTellTarget = function() error("locked") end
check(ns.GetChatEditBoxValue(box, "tellTarget") == nil, "failed getter has no retry")
box.GetTellTarget = function() return nil end
check(ns.GetChatEditBoxValue(box, "tellTarget") == nil, "empty modern target stays empty")
local legacy = { GetAttribute = function(_, key) return key == "chatType" and "PARTY" or nil end, tellTarget = "Legacy-Realm" }
check(ns.GetChatEditBoxValue(legacy, "chatType") == "PARTY", "attribute fallback")
check(ns.GetChatEditBoxValue(legacy, "tellTarget") == "Legacy-Realm", "field fallback")
C_AddOns.IsAddOnLoaded = function() return true, false end
check(not ns.IsAddOnLoadedCompat("GW2_UI"), "loading is not loaded")
C_AddOns.IsAddOnLoaded = function() return true, true end
check(ns.IsAddOnLoadedCompat("GW2_UI"), "loaded result")
C_AddOns.IsAddOnLoaded = function() return true end
check(ns.IsAddOnLoadedCompat("GW2_UI"), "single-result backward compatibility")
C_CVar = { SetCVar = function() return false end }
check(not ns.SetCVarCompat("showTimestamps", "none"), "CVar explicit rejection")
local legacySends = 0
BNSendWhisper = function() legacySends = legacySends + 1 end
C_BattleNet.SendWhisper = function() return false end
check(not ns.SendBNetWhisperCompat(42, "hello") and legacySends == 0, "Battle.net explicit rejection without retry")
C_BattleNet.SendWhisper = function() return true end
check(ns.SendBNetWhisperCompat(42, "hello"), "Battle.net success")
local sentTo
C_ChatInfo.SendChatMessage = function(_, kind, _, targetName)
    assert(kind == "WHISPER"); sentTo = targetName
end
check(ns.SendChatMessageCompat("hello", "WHISPER", nil, "Sebas Moonbloom") and sentTo == "Sebas-Moonbloom", "whisper preserves full recipient")
C_FriendList.GetFriendInfo = function() return {name = "Sebas Moonbloom"} end
check(ns.IsFriendCompat("Sebas-Moonbloom"), "friend space/hyphen identity")
check(not ns.IsFriendCompat("Sebas-Othername"), "different surname never inherits friend status")
check(converterCalls > 0, "new name API exercised")
-- Beta variants may omit an API: safe fallback must still preserve both parts.
C_NameUtil = nil
check(ns.NormalizePlayerNameCompat("Sebas Moonbloom") == "Sebas-Moonbloom", "surname fallback")
PlayerLocation = nil
primary = "Sebas-Moonbloom"
identity = ns.GetPlayerMentionIdentity(true)
check(identity.first == "Sebas" and identity.surname == "Moonbloom", "unit fallback without PlayerLocation")
-- The public modules must distinguish same first names with different surnames.
local addon = ns.Chatify
addon:OnInitialize()
local sounds = addon.modules.Sounds
addon.db.profile.sounds.enable = true
local soundsPlayed = 0
sounds.Play = function() soundsPlayed = soundsPlayed + 1 end
ns.GetMentionRuleMatch = function() return nil end
sounds:OnEnable()
sounds:OnEvent("CHAT_MSG_GUILD", "hello", "Sebas Moonbloom")
check(soundsPlayed == 0, "own full name does not trigger sound")
sounds:OnEvent("CHAT_MSG_GUILD", "hello", "Sebas-Othername")
check(soundsPlayed == 1, "same first name with another surname triggers sound")
local autoReply = addon.modules.AutoReply
local handlers, sent = {}, {}
autoReply.RegisterEvent = function(_, event, handler) if type(handler) == "function" then handlers[event] = handler end end
autoReply.RegisterChatCommand = function() end
addon.db.profile.autoReply.enabled = true
addon.db.profile.autoReply.busyMode = true
addon.db.profile.autoReply.onlyFriends = false
ns.IsFeatureAvailable = function() return true end
ns.SendChatMessageCompat = function(_, _, _, recipient) sent[#sent+1] = recipient; return true end
autoReply:OnEnable()
handlers.CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "hello", "Sebas Moonbloom")
check(#sent == 0, "own full name does not trigger auto reply")
handlers.CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "hello", "Sebas-Othername")
check(#sent == 1 and sent[1] == "Sebas-Othername", "auto reply preserves another player's surname")
-- Invalid linked handles must terminate even when editBox.chatFrame cycles.
ChatFrame1.GetObjectType = function() return nil end
check(pcall(ns.GetActiveChatDraftContext), "cyclic frame link terminates")
print("Forever API contracts: PASS (" .. checks .. " checks; build 1.60.1.70532; offline)")
