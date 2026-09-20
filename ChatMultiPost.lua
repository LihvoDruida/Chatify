local addonName, ns = ...
local Chatify = ns.Chatify
if not Chatify then return end

local MultiPost = Chatify:NewModule("MultiPost", "AceEvent-3.0")
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

local _G = _G
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local math = math
local string = string
local table = table
local pcall = pcall
local select = select

local MIN_MESSAGE_BYTES = 80
local MAX_MESSAGE_BYTES = 250
local COUNTER_RESERVE_BYTES = 16
local AUTO_DELAY_MIN = 0.5
local AUTO_DELAY_MAX = 5.0

local supportedChatTypes = {
    SAY = true,
    EMOTE = true,
    YELL = true,
    PARTY = true,
    RAID = true,
    RAID_WARNING = true,
    INSTANCE_CHAT = true,
    GUILD = true,
    OFFICER = true,
    WHISPER = true,
    CHANNEL = true,
}

local autoChatTypes = {
    EMOTE = true,
    PARTY = true,
    RAID = true,
    RAID_WARNING = true,
    INSTANCE_CHAT = true,
    GUILD = true,
    OFFICER = true,
    WHISPER = true,
}

local destinationValues = {
    CURRENT = "Current chat",
    SAY = "Say",
    EMOTE = "Emote",
    YELL = "Yell",
    PARTY = "Party",
    RAID = "Raid",
    RAID_WARNING = "Raid Warning",
    INSTANCE_CHAT = "Instance",
    GUILD = "Guild",
    OFFICER = "Officer",
    WHISPER = "Whisper",
    CHANNEL = "Channel",
}

local destinationOrder = {
    "CURRENT", "SAY", "EMOTE", "YELL", "PARTY", "RAID", "RAID_WARNING",
    "INSTANCE_CHAT", "GUILD", "OFFICER", "WHISPER", "CHANNEL",
}

local state = {
    chunks = nil,
    index = 1,
    route = nil,
    mode = nil,
    active = false,
    paused = false,
    pauseReason = nil,
    stagedEditBox = nil,
    stagedIndex = nil,
    advanceScheduled = false,
    autoTimerGeneration = 0,
    draftText = "",
    editorDestination = "CURRENT",
    editorTarget = "",
    frame = nil,
    editor = nil,
    statusLabel = nil,
    targetWidget = nil,
    destinationWidget = nil,
}

local function DB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return ns.db or {}
end

local function Print(message)
    if type(message) ~= "string" or message == "" then return end
    if Chatify and type(Chatify.Print) == "function" then
        Chatify:Print(message)
    elseif DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage("Chatify: " .. message)
    end
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeNewlines(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    return text
end

local function IsUTF8Continuation(byte)
    return type(byte) == "number" and byte >= 0x80 and byte < 0xC0
end

local function SafeUTF8Boundary(text, byteLimit)
    local length = #text
    if byteLimit >= length then return length end
    local cut = math.max(0, math.min(byteLimit, length))

    -- If the next byte is a continuation byte, the byte at `cut` begins or sits
    -- inside a code point that would be truncated. Move before the whole code
    -- point. Ending on the final continuation byte is safe.
    while cut > 0 and IsUTF8Continuation(text:byte(cut + 1)) do
        cut = cut - 1
    end
    return cut
end

local function FindLinkRangeContaining(text, cut)
    -- WoW hyperlinks must remain intact. A valid link is:
    -- |Hdata|hvisible text|h
    -- If the proposed cut lands anywhere inside it, move the cut before the
    -- opening |H instead of producing a malformed chat payload.
    local searchFrom = 1
    while true do
        local linkStart = text:find("|H", searchFrom, true)
        if not linkStart or linkStart > cut then
            return nil
        end
        local firstClose = text:find("|h", linkStart + 2, true)
        if not firstClose then
            return nil
        end
        local secondClose = text:find("|h", firstClose + 2, true)
        if not secondClose then
            return nil
        end
        local linkEnd = secondClose + 1
        if cut >= linkStart and cut < linkEnd then
            return linkStart, linkEnd
        end
        searchFrom = linkEnd + 1
    end
end

local function AdjustCutForLinks(text, cut, maxBytes)
    local linkStart, linkEnd = FindLinkRangeContaining(text, cut)
    if not linkStart then
        return cut
    end

    if linkStart > 1 then
        return linkStart - 1
    end

    if linkEnd <= maxBytes then
        return linkEnd
    end

    return nil, "A single WoW link is longer than the configured message limit."
end

local function FindSmartBreak(text, cut, mode)
    if mode == "exact" then
        return cut
    end

    local minSearch = math.max(1, math.floor(cut * 0.55))

    if mode == "smart" then
        for i = cut, minSearch, -1 do
            local ch = text:sub(i, i)
            if (ch == "." or ch == "!" or ch == "?" or ch == ";" or ch == ":") then
                local nextByte = text:sub(i + 1, i + 1)
                if nextByte == "" or nextByte:match("%s") then
                    return i
                end
            end
        end
    end

    for i = cut, minSearch, -1 do
        local ch = text:sub(i, i)
        if ch:match("%s") then
            return i - 1
        end
    end

    return cut
end

local function SplitSegment(segment, byteLimit, splitMode, out)
    segment = Trim(segment)
    if segment == "" then return true end

    while #segment > byteLimit do
        local cut = SafeUTF8Boundary(segment, byteLimit)
        if cut <= 0 then
            return false, "Unable to find a valid UTF-8 split point."
        end

        local adjusted, err = AdjustCutForLinks(segment, cut, byteLimit)
        if not adjusted then
            return false, err
        end
        cut = adjusted

        cut = FindSmartBreak(segment, cut, splitMode)
        cut = SafeUTF8Boundary(segment, cut)
        if cut <= 0 then
            cut = SafeUTF8Boundary(segment, byteLimit)
        end
        if cut <= 0 then
            return false, "Unable to split this message safely."
        end

        local part = Trim(segment:sub(1, cut))
        if part == "" then
            cut = SafeUTF8Boundary(segment, byteLimit)
            part = Trim(segment:sub(1, cut))
        end
        if part == "" then
            return false, "Unable to split this message safely."
        end

        out[#out + 1] = part
        segment = Trim(segment:sub(cut + 1))
    end

    if segment ~= "" then
        out[#out + 1] = segment
    end
    return true
end

local function FormatCounter(index, total, style)
    local value = tostring(index) .. "/" .. tostring(total)
    if style == "plain" then
        return value
    elseif style == "parentheses" then
        return "(" .. value .. ")"
    end
    return "[" .. value .. "]"
end

local function ApplyCounters(chunks, maxBytes, style, position)
    local total = #chunks
    local result = {}
    for i = 1, total do
        local counter = FormatCounter(i, total, style)
        local value
        if position == "suffix" then
            value = chunks[i] .. " " .. counter
        else
            value = counter .. " " .. chunks[i]
        end
        if #value > maxBytes then
            return nil, "A numbered part exceeds the configured message limit."
        end
        result[#result + 1] = value
    end
    return result
end

function ns.SplitLongMessage(text, options)
    options = type(options) == "table" and options or {}
    text = NormalizeNewlines(text)

    if options.trim ~= false then
        text = Trim(text)
    end
    if text == "" then
        return nil, "Enter some text first."
    end

    local maxBytes = math.floor(Clamp(options.maxBytes or 240, MIN_MESSAGE_BYTES, MAX_MESSAGE_BYTES))
    local addCounters = options.addCounters == true
    local splitLimit = maxBytes - (addCounters and COUNTER_RESERVE_BYTES or 0)
    if splitLimit < MIN_MESSAGE_BYTES then
        splitLimit = MIN_MESSAGE_BYTES
    end

    local splitMode = options.splitMode
    if splitMode ~= "words" and splitMode ~= "exact" then
        splitMode = "smart"
    end

    local chunks = {}
    local preserveParagraphs = options.preserveParagraphs ~= false

    if preserveParagraphs then
        for paragraph in (text .. "\n"):gmatch("(.-)\n") do
            paragraph = Trim(paragraph)
            if paragraph ~= "" then
                local ok, err = SplitSegment(paragraph, splitLimit, splitMode, chunks)
                if not ok then return nil, err end
            end
        end
    else
        text = text:gsub("%s*\n+%s*", " ")
        local ok, err = SplitSegment(text, splitLimit, splitMode, chunks)
        if not ok then return nil, err end
    end

    if #chunks == 0 then
        return nil, "No sendable text was found."
    end

    if addCounters then
        local numbered, err = ApplyCounters(
            chunks,
            maxBytes,
            options.counterStyle or "brackets",
            options.counterPosition or "prefix"
        )
        if not numbered then return nil, err end
        chunks = numbered
    end

    for i = 1, #chunks do
        if #chunks[i] > maxBytes then
            return nil, "A message part exceeds the configured message limit."
        end
    end

    return chunks
end

local function GetEditBoxChatType(editBox)
    if not editBox then return nil end

    if type(editBox.GetChatType) == "function" then
        local ok, value = pcall(editBox.GetChatType, editBox)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end

    if type(editBox.GetAttribute) == "function" then
        local ok, value = pcall(editBox.GetAttribute, editBox, "chatType")
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end

    if type(editBox.chatType) == "string" and editBox.chatType ~= "" then
        return editBox.chatType
    end
    return nil
end

local function GetEditBoxTarget(editBox, chatType)
    if not editBox then return nil end

    if chatType == "WHISPER" then
        if type(editBox.GetTellTarget) == "function" then
            local ok, target = pcall(editBox.GetTellTarget, editBox)
            if ok and target and target ~= "" then return target end
        end
        if type(editBox.GetAttribute) == "function" then
            local ok, target = pcall(editBox.GetAttribute, editBox, "tellTarget")
            if ok and target and target ~= "" then return target end
        end
        return editBox.tellTarget
    elseif chatType == "CHANNEL" then
        if type(editBox.GetChannelTarget) == "function" then
            local ok, target = pcall(editBox.GetChannelTarget, editBox)
            if ok and target then return target end
        end
        if type(editBox.GetAttribute) == "function" then
            local ok, target = pcall(editBox.GetAttribute, editBox, "channelTarget")
            if ok and target then return target end
        end
        return editBox.channelTarget
    end
    return nil
end

local function GetLastChatEditBox()
    if type(ns.CallChatAPI) == "function" then
        local ok, editBox = ns.CallChatAPI("ChatEdit_GetLastActiveWindow", "GetLastActiveWindow")
        if ok and editBox then return editBox end
        ok, editBox = ns.CallChatAPI("ChatEdit_GetActiveWindow", "GetActiveWindow")
        if ok and editBox then return editBox end
    end

    if type(_G.ChatEdit_GetLastActiveWindow) == "function" then
        local ok, editBox = pcall(_G.ChatEdit_GetLastActiveWindow)
        if ok and editBox then return editBox end
    end

    local frame = type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame() or _G.DEFAULT_CHAT_FRAME
    if type(ns.GetChatEditBox) == "function" then
        return ns.GetChatEditBox(frame)
    end
    return frame and frame.editBox or _G.ChatFrame1EditBox
end

local function NormalizeChatType(chatType)
    if type(chatType) ~= "string" then return nil end
    chatType = chatType:upper()
    if chatType == "INSTANCE" then chatType = "INSTANCE_CHAT" end
    if supportedChatTypes[chatType] then return chatType end
    return nil
end

local function ResolveChannelTarget(rawTarget)
    local numeric = tonumber(rawTarget)
    if numeric and numeric > 0 then
        return math.floor(numeric)
    end

    local name = Trim(tostring(rawTarget or ""))
    if name == "" then return nil end
    if type(GetChannelName) == "function" then
        local ok, id = pcall(GetChannelName, name)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return math.floor(tonumber(id))
        end
    end
    return nil
end

local function ResolveRoute(destination, target)
    destination = destination or "CURRENT"

    if destination == "CURRENT" then
        local editBox = GetLastChatEditBox()
        local chatType = NormalizeChatType(GetEditBoxChatType(editBox) or "SAY")
        if not chatType then
            return nil, "The current chat type is not supported by Long Messages."
        end
        if chatType == "BN_WHISPER" then
            return nil, "Battle.net whispers are not supported by Long Messages."
        end
        local currentTarget = GetEditBoxTarget(editBox, chatType)
        if chatType == "WHISPER" and (not currentTarget or currentTarget == "") then
            return nil, "The current whisper has no target."
        elseif chatType == "CHANNEL" then
            currentTarget = ResolveChannelTarget(currentTarget)
            if not currentTarget then
                return nil, "The current channel could not be resolved."
            end
        end
        return {
            chatType = chatType,
            target = currentTarget,
            languageID = editBox and editBox.languageID or nil,
            editBox = editBox,
            label = destinationValues[chatType] or chatType,
        }
    end

    local chatType = NormalizeChatType(destination)
    if not chatType then
        return nil, "The selected chat type is not supported."
    end

    local resolvedTarget
    if chatType == "WHISPER" then
        resolvedTarget = Trim(tostring(target or ""))
        if resolvedTarget == "" then
            return nil, "Enter a player name for Whisper."
        end
    elseif chatType == "CHANNEL" then
        resolvedTarget = ResolveChannelTarget(target)
        if not resolvedTarget then
            return nil, "Enter a valid joined channel number or name."
        end
    end

    return {
        chatType = chatType,
        target = resolvedTarget,
        languageID = nil,
        label = destinationValues[chatType] or chatType,
    }
end

local function RouteIsAvailable(route)
    if not route or not route.chatType then
        return false, "No chat destination is selected."
    end

    local chatType = route.chatType
    if chatType == "PARTY" then
        if type(IsInGroup) == "function" and not IsInGroup() then
            return false, "You are not in a group."
        end
    elseif chatType == "RAID" or chatType == "RAID_WARNING" then
        if type(IsInGroup) == "function" and not IsInGroup() then
            return false, "You are not in a group."
        end
    elseif chatType == "INSTANCE_CHAT" then
        if type(IsInGroup) == "function" and _G.LE_PARTY_CATEGORY_INSTANCE then
            local ok, grouped = pcall(IsInGroup, _G.LE_PARTY_CATEGORY_INSTANCE)
            if ok and not grouped then
                return false, "You are not in an instance group."
            end
        end
    elseif chatType == "GUILD" or chatType == "OFFICER" then
        if type(IsInGuild) == "function" and not IsInGuild() then
            return false, "You are not in a guild."
        end
    elseif chatType == "WHISPER" then
        if not route.target or route.target == "" then
            return false, "Whisper requires a target."
        end
    elseif chatType == "CHANNEL" then
        if not tonumber(route.target) or tonumber(route.target) <= 0 then
            return false, "Channel requires a valid joined channel."
        end
    end

    return true
end

local function IsInsideInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    return ok and inInstance and instanceType ~= "none"
end

local function CanAutoSend(route)
    local available, reason = RouteIsAvailable(route)
    if not available then return false, reason end

    if type(ns.CanSendAddonChat) == "function" and not ns.CanSendAddonChat() then
        return false, "WoW is currently blocking addon-driven chat."
    end

    if route.chatType == "CHANNEL" then
        return false, "Automatic sending is never used for numbered or custom channels. Use Manual Enter mode."
    end

    if route.chatType == "SAY" or route.chatType == "YELL" then
        if not IsInsideInstance() then
            return false, "Automatic Say and Yell require an instance. Use Manual Enter mode outdoors."
        end
        return true
    end

    if not autoChatTypes[route.chatType] then
        return false, "This chat type only supports Manual Enter mode."
    end

    return true
end

local function SendChatMessageCompat(message, route)
    if type(message) ~= "string" or message == "" or not route then return false end

    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendChatMessage) == "function" then
        local ok = pcall(_G.C_ChatInfo.SendChatMessage, message, route.chatType, route.languageID, route.target)
        if ok then return true end
    end

    if type(_G.SendChatMessage) == "function" then
        local ok = pcall(_G.SendChatMessage, message, route.chatType, route.languageID, route.target)
        if ok then return true end
    end
    return false
end

local function SetStatus(text)
    text = tostring(text or "")
    if state.statusLabel and type(state.statusLabel.SetText) == "function" then
        state.statusLabel:SetText(text)
    end
end

local function QueueStatusText()
    if not state.active or type(state.chunks) ~= "table" then
        return L("No active Long Messages queue.")
    end

    local total = #state.chunks
    local current = math.min(state.index, total)
    local mode = state.mode == "auto" and L("Automatic") or L("Manual Enter")
    if state.paused then
        return string.format(L("Paused. Part %d of %d. %s"), current, total, state.pauseReason or "")
    end
    return string.format(L("%s mode. Part %d of %d."), mode, current, total)
end

local function UpdateStatus(extra)
    local base = QueueStatusText()
    if extra and extra ~= "" then
        base = base .. "\n" .. extra
    end
    SetStatus(base)
end

local function FinishQueue()
    local total = state.chunks and #state.chunks or 0
    state.active = false
    state.paused = false
    state.pauseReason = nil
    state.mode = nil
    state.route = nil
    state.chunks = nil
    state.index = 1
    state.stagedEditBox = nil
    state.stagedIndex = nil
    state.advanceScheduled = false
    state.autoTimerGeneration = state.autoTimerGeneration + 1
    SetStatus(L("Long Messages queue complete."))
    Print(string.format(L("Long Messages complete: %d parts sent."), total))

    local db = DB()
    if db.multiPostCloseWhenDone and state.frame then
        local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
        if AceGUI then
            AceGUI:Release(state.frame)
        end
        state.frame = nil
        state.editor = nil
        state.statusLabel = nil
        state.targetWidget = nil
        state.destinationWidget = nil
    end
end

local function CancelQueue(silent)
    local hadQueue = state.active
    state.active = false
    state.paused = false
    state.pauseReason = nil
    state.mode = nil
    state.route = nil
    state.chunks = nil
    state.index = 1
    state.stagedEditBox = nil
    state.stagedIndex = nil
    state.advanceScheduled = false
    state.autoTimerGeneration = state.autoTimerGeneration + 1
    SetStatus(L("No active Long Messages queue."))
    if hadQueue and not silent then
        Print(L("Long Messages queue cancelled."))
    end
end

local function SetEditBoxRoute(editBox, route)
    if not editBox or not route then return false end

    if type(editBox.SetChatType) == "function" then
        pcall(editBox.SetChatType, editBox, route.chatType)
    elseif type(editBox.SetAttribute) == "function" then
        pcall(editBox.SetAttribute, editBox, "chatType", route.chatType)
    else
        editBox.chatType = route.chatType
    end

    if route.chatType == "WHISPER" then
        if type(editBox.SetTellTarget) == "function" then
            pcall(editBox.SetTellTarget, editBox, route.target)
        elseif type(editBox.SetAttribute) == "function" then
            pcall(editBox.SetAttribute, editBox, "tellTarget", route.target)
        else
            editBox.tellTarget = route.target
        end
    elseif route.chatType == "CHANNEL" then
        if type(editBox.SetChannelTarget) == "function" then
            pcall(editBox.SetChannelTarget, editBox, route.target)
        elseif type(editBox.SetAttribute) == "function" then
            pcall(editBox.SetAttribute, editBox, "channelTarget", route.target)
        else
            editBox.channelTarget = route.target
        end
    end

    if type(editBox.UpdateHeader) == "function" then
        pcall(editBox.UpdateHeader, editBox)
    elseif type(_G.ChatEdit_UpdateHeader) == "function" then
        pcall(_G.ChatEdit_UpdateHeader, editBox)
    end

    return true
end

local function ChooseEditBox(route)
    if route and route.editBox then
        return route.editBox
    end

    local chatFrame = type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame() or _G.DEFAULT_CHAT_FRAME
    if type(ns.CallChatAPI) == "function" then
        local ok, editBox = ns.CallChatAPI("ChatEdit_ChooseBoxForSend", "ChooseBoxForSend", chatFrame)
        if ok and editBox then return editBox end
    end

    if type(ns.GetChatEditBox) == "function" then
        return ns.GetChatEditBox(chatFrame)
    end
    return chatFrame and chatFrame.editBox or _G.ChatFrame1EditBox
end

local function CanStageManualNow()
    -- Changing a chat edit box from addon code while modern protected chat is in
    -- its restricted state can taint the next send. Pause rather than fighting
    -- Blizzard's restriction. The queued text stays intact.
    if type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
        if type(ns.InChatMessagingLockdown) == "function" and ns.InChatMessagingLockdown(true) then
            return false, "WoW is currently protecting outgoing chat. Resume after the restriction ends."
        end
        if type(InCombatLockdown) == "function" then
            local ok, locked = pcall(InCombatLockdown)
            if ok and locked then
                return false, "Manual staging pauses during combat on protected clients. Resume after combat."
            end
        end
    end
    return true
end

local function StageNextManualPart()
    if not state.active or state.mode ~= "manual" or state.paused then return false end
    if not state.chunks or state.index > #state.chunks then
        FinishQueue()
        return true
    end

    local canStage, stageReason = CanStageManualNow()
    if not canStage then
        state.paused = true
        state.pauseReason = stageReason
        UpdateStatus(stageReason)
        return false
    end

    local available, reason = RouteIsAvailable(state.route)
    if not available then
        state.paused = true
        state.pauseReason = reason
        UpdateStatus(reason)
        return false
    end

    local editBox = ChooseEditBox(state.route)
    if not editBox or type(editBox.SetText) ~= "function" then
        state.paused = true
        state.pauseReason = "The Blizzard chat edit box is not available."
        UpdateStatus(state.pauseReason)
        return false
    end

    SetEditBoxRoute(editBox, state.route)
    local chunk = state.chunks[state.index]

    if type(editBox.Show) == "function" then pcall(editBox.Show, editBox) end
    pcall(editBox.SetText, editBox, chunk)
    if type(editBox.SetCursorPosition) == "function" then
        pcall(editBox.SetCursorPosition, editBox, #chunk)
    end
    if type(editBox.SetFocus) == "function" then pcall(editBox.SetFocus, editBox) end
    if type(editBox.UpdateHeader) == "function" then pcall(editBox.UpdateHeader, editBox) end

    state.stagedEditBox = editBox
    state.stagedIndex = state.index
    UpdateStatus(string.format(L("Part %d of %d is ready in Blizzard chat. Press Enter to send it."), state.index, #state.chunks))
    return true
end

local function ScheduleNextManualPart()
    if state.advanceScheduled then return end
    state.advanceScheduled = true

    local function advance()
        state.advanceScheduled = false
        if not state.active or state.mode ~= "manual" then return end
        state.index = state.index + 1
        state.stagedEditBox = nil
        state.stagedIndex = nil
        if state.index > #state.chunks then
            FinishQueue()
            return
        end
        StageNextManualPart()
    end

    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(0, advance)
    elseif _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, advance)
    else
        advance()
    end
end

local function OnNativeChatSend(editBox)
    if not state.active or state.mode ~= "manual" or state.paused then return end
    if not state.stagedEditBox or editBox ~= state.stagedEditBox then return end
    if state.stagedIndex ~= state.index then return end
    ScheduleNextManualPart()
end

local sendHooksInstalled = false
local eventRegistryCallback

local function FindEditBoxInArgs(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "table" and type(value.GetText) == "function" and type(value.SetText) == "function" then
            return value
        end
    end
    return nil
end

local function InstallSendHooks()
    if sendHooksInstalled then return true end
    local installed = false

    -- Retail/Midnight and Forever use the modern pre-send notification. Do not
    -- alter the text from this callback; it is only used as a notification that
    -- the user pressed Enter on the staged Blizzard edit box.
    if type(_G.EventRegistry) == "table" and type(_G.EventRegistry.RegisterCallback) == "function" then
        eventRegistryCallback = eventRegistryCallback or function(...)
            local editBox = FindEditBoxInArgs(...)
            if editBox then OnNativeChatSend(editBox) end
        end
        local ok = pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, "ChatFrame.OnEditBoxPreSendText", eventRegistryCallback, MultiPost)
        if ok then installed = true end
    end

    -- Legacy/current Classic branches can still route through the old send
    -- helper or a mixin method. Hooking both is safe because advanceScheduled
    -- collapses duplicate notifications from one physical Enter press.
    if type(_G.hooksecurefunc) == "function" then
        if type(_G.ChatEdit_SendText) == "function" then
            local ok = pcall(_G.hooksecurefunc, "ChatEdit_SendText", function(editBox)
                OnNativeChatSend(editBox)
            end)
            installed = ok or installed
        end

        for _, mixin in ipairs({ _G.ChatFrameEditBoxMixin, _G.ChatFrameEditBoxMixinBase, _G.ChatFrameEditBoxBaseMixin }) do
            if type(mixin) == "table" and type(mixin.SendText) == "function" then
                local ok = pcall(_G.hooksecurefunc, mixin, "SendText", function(editBox)
                    OnNativeChatSend(editBox)
                end)
                installed = ok or installed
            end
        end
    end

    sendHooksInstalled = installed
    return installed
end

local function AutoSendNext(generation)
    if generation ~= state.autoTimerGeneration then return end
    if not state.active or state.mode ~= "auto" or state.paused then return end
    if not state.chunks or state.index > #state.chunks then
        FinishQueue()
        return
    end

    local allowed, reason = CanAutoSend(state.route)
    if not allowed then
        state.paused = true
        state.pauseReason = reason
        UpdateStatus(reason)
        Print(L("Long Messages automatic queue paused: ") .. reason)
        return
    end

    local chunk = state.chunks[state.index]
    if not SendChatMessageCompat(chunk, state.route) then
        state.paused = true
        state.pauseReason = "WoW rejected the automatic chat send."
        UpdateStatus(state.pauseReason)
        Print(L("Long Messages automatic queue paused: WoW rejected the send."))
        return
    end

    state.index = state.index + 1
    if state.index > #state.chunks then
        FinishQueue()
        return
    end

    UpdateStatus()
    local delay = Clamp(DB().multiPostAutoDelay or 0.8, AUTO_DELAY_MIN, AUTO_DELAY_MAX)
    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(delay, function() AutoSendNext(generation) end)
    elseif _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(delay, function() AutoSendNext(generation) end)
    end
end

local function BuildQueue(text, destination, target, mode)
    local db = DB()
    if not db.multiPostEnabled then
        return false, "Long Messages mode is disabled in Chatify settings."
    end

    local route, routeErr = ResolveRoute(destination, target)
    if not route then return false, routeErr end

    local available, availabilityErr = RouteIsAvailable(route)
    if not available then return false, availabilityErr end

    if mode == "auto" then
        local autoAllowed, autoErr = CanAutoSend(route)
        if not autoAllowed then return false, autoErr end
    end

    local chunks, splitErr = ns.SplitLongMessage(text, {
        maxBytes = db.multiPostMaxBytes or 240,
        splitMode = db.multiPostSplitMode or "smart",
        preserveParagraphs = db.multiPostPreserveParagraphs ~= false,
        trim = db.multiPostTrimWhitespace ~= false,
        addCounters = db.multiPostAddCounters == true,
        counterStyle = db.multiPostCounterStyle or "brackets",
        counterPosition = db.multiPostCounterPosition or "prefix",
    })
    if not chunks then return false, splitErr end

    CancelQueue(true)
    state.chunks = chunks
    state.index = 1
    state.route = route
    state.mode = mode
    state.active = true
    state.paused = false
    state.pauseReason = nil
    state.stagedEditBox = nil
    state.stagedIndex = nil
    state.autoTimerGeneration = state.autoTimerGeneration + 1

    return true, chunks
end

function ns.PrepareMultiPostManual(text, destination, target)
    local ok, result = BuildQueue(text, destination, target, "manual")
    if not ok then return false, result end
    InstallSendHooks()
    local staged = StageNextManualPart()
    if not staged then
        return false, state.pauseReason or "Unable to stage the first message part."
    end
    return true, #result
end

function ns.StartMultiPostAuto(text, destination, target)
    if DB().multiPostAllowAuto ~= true then
        return false, "Automatic Queue is disabled in Chatify settings."
    end
    local ok, result = BuildQueue(text, destination, target, "auto")
    if not ok then return false, result end
    local generation = state.autoTimerGeneration
    AutoSendNext(generation)
    return true, #result
end

function ns.PauseMultiPost(reason)
    if not state.active then return false end
    state.paused = true
    state.pauseReason = reason or "Paused by user."
    state.autoTimerGeneration = state.autoTimerGeneration + 1
    UpdateStatus()
    return true
end

function ns.ResumeMultiPost()
    if not state.active then return false, "No active Long Messages queue." end
    state.paused = false
    state.pauseReason = nil
    if state.mode == "manual" then
        return StageNextManualPart()
    end

    local allowed, reason = CanAutoSend(state.route)
    if not allowed then
        state.paused = true
        state.pauseReason = reason
        UpdateStatus(reason)
        return false, reason
    end

    state.autoTimerGeneration = state.autoTimerGeneration + 1
    local generation = state.autoTimerGeneration
    AutoSendNext(generation)
    return true
end

function ns.CancelMultiPost()
    CancelQueue(false)
end

function ns.CloseMultiPostEditor()
    if not state.frame then return false end
    if state.editor and type(state.editor.GetText) == "function" then
        state.draftText = state.editor:GetText() or state.draftText or ""
    end
    local frame = state.frame
    state.frame = nil
    state.editor = nil
    state.statusLabel = nil
    state.targetWidget = nil
    state.destinationWidget = nil
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if AceGUI then
        AceGUI:Release(frame)
    end
    return true
end

function ns.GetMultiPostState()
    return state
end

local function RefreshTargetDescription()
    if not state.targetWidget then return end
    local destination = state.editorDestination
    local label
    if destination == "WHISPER" then
        label = L("Target player")
    elseif destination == "CHANNEL" then
        label = L("Channel number or name")
    else
        label = L("Target (used only for Whisper or Channel)")
    end
    if type(state.targetWidget.SetLabel) == "function" then
        state.targetWidget:SetLabel(label)
    end
end

function ns.OpenMultiPostEditor()
    local db = DB()
    if not db.multiPostEnabled then
        Print(L("Long Messages mode is disabled. Enable it in Chatify settings first."))
        return false
    end

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then
        Print(L("Long Messages editor is unavailable because AceGUI could not be loaded."))
        return false
    end

    if state.frame and state.frame.frame and state.frame.frame:IsShown() then
        state.frame.frame:Raise()
        return true
    end

    local frame = AceGUI:Create("Frame")
    state.frame = frame
    frame:SetTitle(L("Chatify Long Messages"))
    frame:SetStatusText(L("Write once, then send safely in multiple WoW chat messages."))
    frame:SetLayout("Flow")
    frame:SetWidth(720)
    frame:SetHeight(650)
    frame:EnableResize(true)
    frame:SetCallback("OnClose", function(widget)
        if state.editor and type(state.editor.GetText) == "function" then
            state.draftText = state.editor:GetText() or ""
        end
        if state.active and state.mode == "auto" then
            ns.PauseMultiPost("Editor closed. Reopen it to resume automatic sending.")
        end
        state.frame = nil
        state.editor = nil
        state.statusLabel = nil
        state.targetWidget = nil
        state.destinationWidget = nil
        AceGUI:Release(widget)
    end)

    local info = AceGUI:Create("Label")
    info:SetFullWidth(true)
    info:SetText(L("Manual Enter mode is the safest option. Chatify places one part in Blizzard chat and every Enter sends one part through the normal game path. Automatic mode is limited to chat types Blizzard allows addons to send without a hardware event."))
    frame:AddChild(info)

    local destination = AceGUI:Create("Dropdown")
    state.destinationWidget = destination
    destination:SetLabel(L("Destination"))
    local localizedValues = {}
    for key, value in pairs(destinationValues) do localizedValues[key] = L(value) end
    destination:SetList(localizedValues, destinationOrder)
    destination:SetValue(state.editorDestination or "CURRENT")
    destination:SetRelativeWidth(0.48)
    destination:SetCallback("OnValueChanged", function(_, _, value)
        state.editorDestination = value or "CURRENT"
        RefreshTargetDescription()
    end)
    frame:AddChild(destination)

    local target = AceGUI:Create("EditBox")
    state.targetWidget = target
    target:SetLabel(L("Target (used only for Whisper or Channel)"))
    target:SetText(state.editorTarget or "")
    target:SetRelativeWidth(0.48)
    target:SetCallback("OnEnterPressed", function(_, _, value)
        state.editorTarget = value or ""
    end)
    target:SetCallback("OnTextChanged", function(_, _, value)
        state.editorTarget = value or ""
    end)
    frame:AddChild(target)
    RefreshTargetDescription()

    local editor = AceGUI:Create("MultiLineEditBox")
    state.editor = editor
    editor:SetLabel(L("Long message"))
    editor:SetFullWidth(true)
    editor:SetNumLines(22)
    editor:SetMaxLetters(0)
    editor:DisableButton(true)
    editor:SetText(state.draftText or "")
    editor:SetCallback("OnTextChanged", function(_, _, value)
        state.draftText = value or ""
    end)
    frame:AddChild(editor)

    local status = AceGUI:Create("Label")
    state.statusLabel = status
    status:SetFullWidth(true)
    status:SetText(QueueStatusText())
    frame:AddChild(status)

    local manualButton = AceGUI:Create("Button")
    manualButton:SetText(L("Prepare Manual Enter Queue"))
    manualButton:SetRelativeWidth(0.32)
    manualButton:SetCallback("OnClick", function()
        local text = editor:GetText() or ""
        state.draftText = text
        state.editorTarget = (type(target.GetText) == "function" and target:GetText()) or state.editorTarget or ""
        local ok, result = ns.PrepareMultiPostManual(text, state.editorDestination, state.editorTarget)
        if not ok then
            UpdateStatus(result)
            Print(result)
        else
            UpdateStatus(string.format(L("Prepared %d parts."), result))
        end
    end)
    frame:AddChild(manualButton)

    local autoButton = AceGUI:Create("Button")
    autoButton:SetText(L("Start Automatic Queue"))
    autoButton:SetRelativeWidth(0.32)
    autoButton:SetDisabled(db.multiPostAllowAuto ~= true)
    autoButton:SetCallback("OnClick", function()
        local text = editor:GetText() or ""
        state.draftText = text
        state.editorTarget = (type(target.GetText) == "function" and target:GetText()) or state.editorTarget or ""
        local ok, result = ns.StartMultiPostAuto(text, state.editorDestination, state.editorTarget)
        if not ok then
            UpdateStatus(result)
            Print(result)
        else
            UpdateStatus(string.format(L("Automatic queue started with %d parts."), result))
        end
    end)
    frame:AddChild(autoButton)

    local resumeButton = AceGUI:Create("Button")
    resumeButton:SetText(L("Resume / Stage Next"))
    resumeButton:SetRelativeWidth(0.32)
    resumeButton:SetCallback("OnClick", function()
        local ok, reason = ns.ResumeMultiPost()
        if not ok and reason then
            UpdateStatus(reason)
            Print(reason)
        else
            UpdateStatus()
        end
    end)
    frame:AddChild(resumeButton)

    local pauseButton = AceGUI:Create("Button")
    pauseButton:SetText(L("Pause Queue"))
    pauseButton:SetRelativeWidth(0.32)
    pauseButton:SetCallback("OnClick", function()
        if ns.PauseMultiPost("Paused by user.") then
            UpdateStatus()
        end
    end)
    frame:AddChild(pauseButton)

    local cancelButton = AceGUI:Create("Button")
    cancelButton:SetText(L("Cancel Queue"))
    cancelButton:SetRelativeWidth(0.32)
    cancelButton:SetCallback("OnClick", function()
        CancelQueue(false)
    end)
    frame:AddChild(cancelButton)

    local clearButton = AceGUI:Create("Button")
    clearButton:SetText(L("Clear Draft"))
    clearButton:SetRelativeWidth(0.32)
    clearButton:SetCallback("OnClick", function()
        state.draftText = ""
        editor:SetText("")
    end)
    frame:AddChild(clearButton)

    return true
end

function Chatify:MultiPostCommand(input)
    input = Trim(tostring(input or ""))
    local command = input:lower()

    if command == "cancel" then
        CancelQueue(false)
        return
    elseif command == "pause" then
        if not ns.PauseMultiPost("Paused by user.") then Print(L("No active Long Messages queue.")) end
        return
    elseif command == "resume" or command == "next" then
        local ok, reason = ns.ResumeMultiPost()
        if not ok and reason then Print(reason) end
        return
    elseif command == "status" then
        Print(QueueStatusText())
        return
    end

    ns.OpenMultiPostEditor()
end

function MultiPost:OnEnable()
    InstallSendHooks()
end

function MultiPost:OnDisable()
    CancelQueue(true)
    ns.CloseMultiPostEditor()
end
