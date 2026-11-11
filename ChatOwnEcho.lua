local addonName, ns = ...
local Chatify = ns.Chatify
local OwnEcho = Chatify:NewModule("OwnEcho", "AceEvent-3.0")

-- A local preview for Forever clients which never echo their own public-channel
-- messages. This deliberately does NOT claim that the server accepted a send.
-- Observe Blizzard's pre-send notification; never replace SendChatMessage or
-- modify the edit box, secure chat arguments, or Blizzard's message handlers.
local pending = {}
local callbackInstalled = false
local serial = 0
local MAX_PENDING = 12
local ECHO_DELAY = 1.25

local function Enabled()
    return type(ns.IsForeverClient) == "function" and ns.IsForeverClient()
        and Chatify.db and Chatify.db.profile
        and Chatify.db.profile.echoOwnPublicChannels == true
end

local function SafeString(value)
    if type(ns.IsProtectedChatValue) == "function" and ns.IsProtectedChatValue(value) then
        return nil
    end
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function ChannelForEditBox(editBox)
    if type(ns.GetChatEditBoxValue) ~= "function" or ns.GetChatEditBoxValue(editBox, "chatType") ~= "CHANNEL" then
        return nil
    end
    local rawId = ns.GetChatEditBoxValue(editBox, "channelTarget")
    local channelId = tonumber(rawId)
    if not channelId and type(rawId) == "string" and type(GetChannelName) == "function" then
        local ok, result = pcall(GetChannelName, rawId)
        if ok then channelId = tonumber(result) end
    end
    if not channelId or channelId <= 0 or channelId % 1 ~= 0 then return nil end
    local _, byId = ns.GetJoinedChannels()
    local channel = byId and byId[channelId]
    -- Only the named built-in channels requested by the player; never silently
    -- echo custom channels whose IDs may be recycled after /leave or zoning.
    -- Built-in channel names are localized by the WoW client.
    local generalKey = type(_G.GENERAL) == "string" and ns.ChannelNameKey(_G.GENERAL) or "GENERAL"
    local tradeKey = type(_G.TRADE) == "string" and ns.ChannelNameKey(_G.TRADE) or "TRADE"
    if channel and (channel.key == "GENERAL" or channel.key == "TRADE"
        or channel.key == generalKey or channel.key == tradeKey) then
        return channel
    end
    return nil
end

local function FindEditBox(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value and (type(value) == "table" or type(value) == "userdata") then
            local ok, getter = pcall(function() return value.GetText end)
            if ok and type(getter) == "function" then return value end
        end
    end
end

local function IsLocalAuthor(author)
    author = SafeString(author)
    if not author then return false end
    local identity = type(ns.GetPlayerMentionIdentity) == "function" and ns.GetPlayerMentionIdentity()
    if not identity or not identity.full then return false end
    local normalizer = ns.NormalizePlayerNameCompat
    if type(normalizer) ~= "function" then return false end
    local actual = normalizer(author)
    local wanted = normalizer(identity.full)
    return type(actual) == "string" and type(wanted) == "string" and actual:lower() == wanted:lower()
end

local function ShowLocal(entry)
    if not Enabled() then return end
    local label = string.format("|cff999999[Chatify: local copy /%d %s; delivery not verified]|r ", entry.id, entry.name)
    local line = label .. entry.text
    local displayed = false
    -- Respect individual Blizzard chat tabs instead of splashing the line into
    -- windows which are unsubscribed from General or Trade.
    local maxFrames = type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or 10
    for i = 1, maxFrames do
        local frame = _G["ChatFrame" .. i]
        if frame and type(frame.AddMessage) == "function" then
            local ok, contains = ns.CallChatFrameMethod(frame, "ContainsChannel", "ChatFrame_ContainsChannel", entry.name)
            if ok and contains then
                pcall(frame.AddMessage, frame, line, 0.75, 0.75, 0.75)
                displayed = true
            end
        end
    end
    if not displayed and DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line, 0.75, 0.75, 0.75)
    end
end

local function OnPreSend(...)
    if not Enabled() then return end
    local editBox = FindEditBox(...)
    if not editBox then return end
    local channel = ChannelForEditBox(editBox)
    if not channel then return end
    local ok, rawText = pcall(editBox.GetText, editBox)
    local text = ok and SafeString(rawText) or nil
    if not text then return end
    text = text:match("^%s*(.-)%s*$")
    -- Commands, blank sends and protected strings should not be presented as
    -- outgoing chat. After ParseText(), ordinary /1 and /2 already route to CHANNEL.
    if text == "" or text:sub(1, 1) == "/" then return end

    serial = serial + 1
    local entry = { serial = serial, id = channel.id, name = channel.name, text = text }
    pending[#pending + 1] = entry
    if #pending > MAX_PENDING then table.remove(pending, 1) end
    if not ns.SafeAfter(ECHO_DELAY, function()
        for i = #pending, 1, -1 do
            if pending[i] == entry then
                table.remove(pending, i)
                ShowLocal(entry)
                return
            end
        end
    end) then
        pending[#pending] = nil
    end
end

function OwnEcho:CHAT_MSG_CHANNEL(event, text, author, language, channelString, target, flags, channelNumber)
    if type(ns.IsProtectedChatValue) == "function" and ns.IsProtectedChatValue(text) then return end
    if not Enabled() or not IsLocalAuthor(author) then return end
    text = SafeString(text)
    local id = tonumber(channelNumber)
    if not text or not id then return end
    -- A genuine Blizzard echo takes precedence. Never show a second, invented
    -- 'success' line in place of the real chat event.
    for i = #pending, 1, -1 do
        local entry = pending[i]
        if entry.id == id and entry.text == text then
            table.remove(pending, i)
            return
        end
    end
end

function OwnEcho:OnEnable()
    if callbackInstalled then return end
    if type(ns.IsForeverClient) ~= "function" or not ns.IsForeverClient() then return end
    if type(_G.EventRegistry) ~= "table" or type(_G.EventRegistry.RegisterCallback) ~= "function" then return end
    local ok = pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
        "ChatFrame.OnEditBoxPreSendText", OnPreSend, OwnEcho)
    if not ok then return end
    callbackInstalled = true
    if type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL")
    else
        pcall(self.RegisterEvent, self, "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL")
    end
end

function OwnEcho:OnDisable()
    pending = {}
    if not callbackInstalled then return end
    callbackInstalled = false
    if type(_G.EventRegistry) == "table" and type(_G.EventRegistry.UnregisterCallback) == "function" then
        pcall(_G.EventRegistry.UnregisterCallback, _G.EventRegistry,
            "ChatFrame.OnEditBoxPreSendText", OwnEcho)
    end
end
