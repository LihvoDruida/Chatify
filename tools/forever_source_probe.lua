-- Exercise Chatify against actual Lua implementations from a pinned Forever UI
-- checkout. C functions, the message buffer and security context remain modeled.
-- FOREVER_UI_SOURCE=/path/to/wow-ui-source lua5.1 tools/forever_source_probe.lua
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
require("client_fixtures").install(env, "forever")
local root = assert(os.getenv("FOREVER_UI_SOURCE"), "FOREVER_UI_SOURCE is required")
local unpack = table.unpack or unpack
_G.CreateFromMixins = function(...)
    local result = {}
    for i = 1, select("#", ...) do
        for key, value in pairs(select(i, ...) or {}) do result[key] = value end
    end
    return result
end
for _, file in ipairs({
    "Blizzard_ObjectAPI/Mainline/PlayerLocation.lua",
    "Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua",
    "Blizzard_SharedXML/ScrollingMessageFrame.lua",
}) do
    assert(loadfile(root .. "/Interface/AddOns/" .. file))()
end
_G.UnitNameUnmodified = function() return "Sebas", "ARealm" end
_G.C_PlayerInfo = {GetName = function(location)
    assert(location:IsUnit() and location:GetUnit() == "player", "real PlayerLocation factory not used")
    return "Sebas Moonbloom"
end}
local frame = ChatFrame1
frame.GetObjectType = function() return "ScrollingMessageFrame" end
local entries = {}
frame.historyBuffer = {
    PushFront = function(_, entry) table.insert(entries, 1, entry); return true end,
    GetNumElements = function() return #entries end,
    GetEntryAtIndex = function(_, index) return entries[index] end,
    RemoveIf = function(_, predicate, unpackage)
        local removed = false
        for i = #entries, 1, -1 do
            if predicate(unpackage(entries[i])) then table.remove(entries, i); removed = true end
        end
        return removed
    end,
    TransformIf = function(_, predicate, transform, unpackage)
        local changed = false
        for i, entry in ipairs(entries) do
            if predicate(unpackage(entry)) then entries[i] = transform(unpackage(entry)); changed = true end
        end
        return changed
    end,
}
for _, name in ipairs({"AddMessage", "GetNumMessages", "GetMessageInfo", "PackageEntry", "UnpackageEntry", "MarkDisplayDirty"}) do
    frame[name] = ScrollingMessageFrameMixin[name]
end
frame.TransformMessages = ScrollingMessageFrameSecureMixin.TransformMessages
frame.RemoveMessagesByPredicate = ScrollingMessageFrameSecureMixin.RemoveMessagesByPredicate
frame.GetScrollOffset = function() return 0 end
local attributes = {chatType = "WHISPER", tellTarget = "Sebas Moonbloom", channelTarget = "4"}
local box = CreateFromMixins(ChatFrameEditBoxBaseMixin)
box.GetAttribute = function(_, key) return attributes[key] end
box.SetAttribute = function(_, key, value) attributes[key] = value end
frame.editBox = box
_G.GetChannelName = function(target) assert(target == "4"); return 4, "General" end
_G.hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then return end
    local previous = target[method]
    target[method] = function(self, ...)
        previous(self, ...)
        callback(self, ...)
    end
end
local ns = {}
for line in io.lines("Chatify_Camelot.toc") do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = ns.Chatify
addon:OnInitialize()
local identity = ns.GetPlayerMentionIdentity(true)
assert(identity.source == "C_PlayerInfo.GetName" and identity.surname == "Moonbloom")
_G.Constants = {CharacterNameSeparatorConsts = {CHARACTERNAME_SURNAME_SEPARATOR = " "}}
assert(loadfile(root .. "/Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua"))()
_G.RegionalUniqueNamesEnabled = function() return true end
_G.UnitNameUnmodified = function() return "Sebas", "Moonbloom" end
identity = ns.GetPlayerMentionIdentity(true)
assert(identity.source == "NameUtil.GetUnmodifiedUnitFullName" and identity.surname == "Moonbloom", "actual Camelot naming helper ignored")
assert(ns.GetChatEditBoxValue(box, "chatType") == "WHISPER")
assert(ns.GetChatEditBoxValue(box, "tellTarget") == "Sebas Moonbloom")
assert(ns.GetChatEditBoxValue(box, "channelTarget") == 4)
box:SetTellTarget("Other Surname")
assert(ns.GetChatEditBoxValue(box, "tellTarget") == "Other Surname")
ns.AreMessageFiltersInstalled = function() return false end
ns.ApplyChannelLabels = function(text) return "PRESENTED:" .. text end
ns.ProcessSpamMessage = function(_, message) return message == "block-me" end
addon.modules.History:OnEnable()
ns.RefreshSecureChatTransforms()
local function history() return ns.GetChatifyHistoryEntriesForFrame(frame, 1000) or {} end
local before = #history()
frame:AddMessage("hello", 1,1,1, nil,0,0, "CHAT_MSG_GUILD", {"hello", "Friend Surname"})
assert(frame:GetNumMessages() == 1 and entries[1].message == "PRESENTED:hello", "real transform did not update stored line")
assert(#history() == before + 1, "real rendered line not captured once")
frame:AddMessage("block-me", 1,1,1, nil,0,0, "CHAT_MSG_GUILD", {"block-me", "Seller Surname"})
assert(frame:GetNumMessages() == 1, "real void-return removal failed")
assert(#history() == before + 1, "removed line leaked into history")
assert(ns.GetChatTransformStats().errors == 0, "transform runtime errors")
-- Direct system lines have no eventArgs; exercise real PackageEntry/UnpackageEntry
-- and RemoveMessagesByPredicate rather than just a test buffer's argument order.
ChatTypeInfo = { SYSTEM = { id = 1 }, PARTY = { id = 2 } }
ERR_PLAYERLIST_JOINED_BATTLE = "%d players have joined the battle: %s."
addon.db.profile.hideBattleRosterMessages = true
local systemLine = "2 players have joined the battle: One, Two."
local count, saved = #entries, #history()
frame:AddMessage(systemLine, 1, 1, 0, 1)
assert(#entries == count and #history() == saved, "direct system notice survived real removal/history")
frame:AddMessage(systemLine, 1, 1, 0, 2)
assert(#entries == count + 1 and #history() == saved + 1, "party quote was removed as system")
print("Forever source integration: PASS (actual Camelot NameUtil, PlayerLocation, edit-box getters and secure message-frame Lua methods, including direct system notice removal; modeled C/security)")
