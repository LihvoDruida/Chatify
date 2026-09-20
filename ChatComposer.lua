local addonName, ns = ...
local Chatify = ns.Chatify or _G.Chatify
if not Chatify then return end

local Composer = Chatify:NewModule("Composer", "AceConsole-3.0")
local AceGUI = LibStub and LibStub("AceGUI-3.0", true) or nil

local DEFAULT_LIMIT = 245
local MIN_LIMIT = 80
local MAX_LIMIT = 255
local PREFIX_MARKER = ">> "
local SUFFIX_MARKER = " >>"

local CHANNELS = {
    { value = "SAY",           label = "Say" },
    { value = "EMOTE",         label = "Emote" },
    { value = "YELL",          label = "Yell" },
    { value = "PARTY",         label = "Party" },
    { value = "RAID",          label = "Raid" },
    { value = "RAID_WARNING",  label = "Raid Warning" },
    { value = "INSTANCE_CHAT", label = "Instance" },
    { value = "GUILD",         label = "Guild" },
    { value = "OFFICER",       label = "Officer" },
    { value = "WHISPER",       label = "Whisper" },
    { value = "PER_LINE",      label = "Per Line" },
}

local PER_LINE_CHANNELS = {
    s = "SAY", say = "SAY",
    e = "EMOTE", em = "EMOTE", emote = "EMOTE", me = "EMOTE",
    y = "YELL", yell = "YELL",
    p = "PARTY", party = "PARTY",
    ra = "RAID", raid = "RAID",
    rw = "RAID_WARNING",
    i = "INSTANCE_CHAT", inst = "INSTANCE_CHAT", instance = "INSTANCE_CHAT",
    g = "GUILD", guild = "GUILD",
    o = "OFFICER", officer = "OFFICER",
}

local TARGET_MARKERS = {
    { value = "{rt1}", label = "Star" },
    { value = "{rt2}", label = "Circle" },
    { value = "{rt3}", label = "Diamond" },
    { value = "{rt4}", label = "Triangle" },
    { value = "{rt5}", label = "Moon" },
    { value = "{rt6}", label = "Square" },
    { value = "{rt7}", label = "Cross" },
    { value = "{rt8}", label = "Skull" },
}

local CONTINUATION_MODES = {
    BOTH = "Both",
    START = "Start Only",
    END = "End Only",
    NONE = "None",
}

local function T(key)
    return ns.L and ns.L(key) or key
end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ClampLimit(value)
    value = tonumber(value) or DEFAULT_LIMIT
    value = math.floor(value)
    if value < MIN_LIMIT then value = MIN_LIMIT end
    if value > MAX_LIMIT then value = MAX_LIMIT end
    return value
end

local function GetProfile()
    local db = Chatify.db and Chatify.db.profile
    if not db then return nil end
    db.composer = type(db.composer) == "table" and db.composer or {}
    local c = db.composer
    c.chunkLimit = ClampLimit(c.chunkLimit)
    if c.showCounter == nil then c.showCounter = true end
    if c.continuation ~= "BOTH" and c.continuation ~= "START" and c.continuation ~= "END" and c.continuation ~= "NONE" then
        c.continuation = "BOTH"
    end
    if type(c.defaultChannel) ~= "string" or c.defaultChannel == "" then
        c.defaultChannel = "SAY"
    end
    return c
end

local function SafeBoolCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and value and true or false
end

local function IsInParty()
    if type(IsInGroup) ~= "function" then return false end
    if type(IsInRaid) == "function" and SafeBoolCall(IsInRaid) then return false end
    return SafeBoolCall(IsInGroup)
end

local function IsInInstanceGroup()
    if type(IsInGroup) ~= "function" then return false end
    local category = _G.LE_PARTY_CATEGORY_INSTANCE
    if category ~= nil then
        local ok, result = pcall(IsInGroup, category)
        if ok then return result and true or false end
    end
    return false
end

local function IsRaidLeaderOrAssistant()
    if not SafeBoolCall(IsInRaid) then return false end
    if SafeBoolCall(UnitIsGroupLeader, "player") then return true end
    if SafeBoolCall(UnitIsGroupAssistant, "player") then return true end
    return false
end

local function IsChannelUsable(chatType, target)
    if chatType == "PER_LINE" then return true end
    if chatType == "PARTY" then
        return IsInParty(), T("You are not in a party.")
    elseif chatType == "RAID" then
        return SafeBoolCall(IsInRaid), T("You are not in a raid.")
    elseif chatType == "RAID_WARNING" then
        if not SafeBoolCall(IsInRaid) then
            return false, T("You are not in a raid.")
        end
        if not IsRaidLeaderOrAssistant() then
            return false, T("Raid Warning requires raid leader or assistant permission.")
        end
        return true
    elseif chatType == "INSTANCE_CHAT" then
        return IsInInstanceGroup(), T("Instance chat is not available right now.")
    elseif chatType == "GUILD" or chatType == "OFFICER" then
        return SafeBoolCall(IsInGuild), T("You are not in a guild.")
    elseif chatType == "WHISPER" then
        if Trim(target) == "" then
            return false, T("Enter a whisper target.")
        end
        return true
    end
    return true
end

local function GetAvailableChannelList()
    local values = {}
    local order = {}
    for _, entry in ipairs(CHANNELS) do
        local usable = entry.value == "WHISPER" or entry.value == "PER_LINE" or IsChannelUsable(entry.value)
        if usable then
            values[entry.value] = T(entry.label)
            order[#order + 1] = entry.value
        end
    end
    return values, order
end

local function NormalizeInput(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("[ \t]+", " ")
    text = text:gsub(" *\n *", "\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Returns a byte position that never ends in the middle of a UTF-8 codepoint.
-- WoW's chat limit is byte-based, so we keep byte accounting but only cut at a
-- valid character boundary.
local function UTF8SafeCut(text, maxBytes)
    local length = #text
    if length <= maxBytes then return length end
    local cut = math.max(0, math.min(maxBytes, length))
    while cut > 0 and cut < length do
        local nextByte = string.byte(text, cut + 1)
        if not nextByte or nextByte < 0x80 or nextByte > 0xBF then
            break
        end
        cut = cut - 1
    end
    return cut
end

local function AdjustCutForWoWHyperlink(text, cut)
    if cut <= 0 then return cut end
    local before = text:sub(1, cut)
    local linkStart
    local searchFrom = 1
    while true do
        local s = before:find("|H", searchFrom, true)
        if not s then break end
        linkStart = s
        searchFrom = s + 2
    end
    if not linkStart then return cut end

    local firstClose = text:find("|h", linkStart + 2, true)
    local secondClose = firstClose and text:find("|h", firstClose + 2, true) or nil
    if secondClose and secondClose + 1 > cut then
        if linkStart > 1 then
            return UTF8SafeCut(text, linkStart - 1)
        end
    end
    return cut
end

local function FindBestCut(text, maxBytes)
    local safeCut = UTF8SafeCut(text, maxBytes)
    safeCut = AdjustCutForWoWHyperlink(text, safeCut)
    if safeCut <= 0 then
        safeCut = UTF8SafeCut(text, maxBytes)
    end
    if safeCut >= #text then return #text end

    local after = text:sub(safeCut + 1, safeCut + 1)
    if after == " " or after == "\n" or after == "\t" then
        return safeCut
    end

    for i = safeCut, 1, -1 do
        local c = text:sub(i, i)
        if c == " " or c == "\n" or c == "\t" then
            local candidate = UTF8SafeCut(text, i - 1)
            if candidate > 0 then return candidate end
        end
    end

    return safeCut
end

local function ContinuationAtStart(settings)
    return settings.continuation == "BOTH" or settings.continuation == "START"
end

local function ContinuationAtEnd(settings)
    return settings.continuation == "BOTH" or settings.continuation == "END"
end

local function CounterSuffix(settings, index, total)
    if settings.showCounter == false or total <= 1 then return "" end
    return " (" .. tostring(index) .. "/" .. tostring(total) .. ")"
end

local function SplitLogicalLine(result, entry, settings, expectedTotal)
    local remaining = Trim(entry.text)
    local piece = 1
    while remaining ~= "" do
        local globalIndex = #result + 1
        local prefix = (piece > 1 and ContinuationAtStart(settings)) and PREFIX_MARKER or ""
        local finalSuffix = CounterSuffix(settings, globalIndex, expectedTotal)
        local finalCapacity = math.max(1, settings.chunkLimit - #prefix - #finalSuffix)

        if #remaining <= finalCapacity then
            result[#result + 1] = {
                text = prefix .. remaining .. finalSuffix,
                channel = entry.channel,
                target = entry.target,
            }
            return
        end

        local continuedSuffix = CounterSuffix(settings, globalIndex, expectedTotal)
        if ContinuationAtEnd(settings) then
            continuedSuffix = continuedSuffix .. SUFFIX_MARKER
        end
        local capacity = math.max(1, settings.chunkLimit - #prefix - #continuedSuffix)
        local cut = FindBestCut(remaining, capacity)
        if cut <= 0 then
            cut = UTF8SafeCut(remaining, capacity)
        end
        if cut <= 0 then return end

        local part = Trim(remaining:sub(1, cut))
        if part ~= "" then
            result[#result + 1] = {
                text = prefix .. part .. continuedSuffix,
                channel = entry.channel,
                target = entry.target,
            }
        end
        remaining = Trim(remaining:sub(cut + 1))
        piece = piece + 1
    end
end

local function ParsePerLine(line, lineNumber)
    local command, payload = line:match("^/(%S+)%s+(.+)$")
    if not command or not payload then
        return nil, string.format(T("Line %d needs a channel prefix such as /s, /raid, /rw, /g or /w Name."), lineNumber)
    end

    command = command:lower()
    if command == "w" or command == "whisper" then
        local target, message = payload:match("^(%S+)%s+(.+)$")
        if not target or not message then
            return nil, string.format(T("Line %d needs /w Name followed by a message."), lineNumber)
        end
        return { text = message, channel = "WHISPER", target = target }
    end

    local chatType = PER_LINE_CHANNELS[command]
    if not chatType then
        return nil, string.format(T("Line %d has an unsupported channel prefix: /%s"), lineNumber, command)
    end
    return { text = payload, channel = chatType }
end

local function BuildLogicalLines(text, channel, whisperTarget)
    text = NormalizeInput(text)
    if text == "" then
        return nil, T("Enter a message first.")
    end

    local lines = {}
    local lineNumber = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lineNumber = lineNumber + 1
        line = Trim(line)
        if line ~= "" then
            if channel == "PER_LINE" then
                local parsed, err = ParsePerLine(line, lineNumber)
                if not parsed then return nil, err end
                lines[#lines + 1] = parsed
            else
                lines[#lines + 1] = {
                    text = line,
                    channel = channel,
                    target = channel == "WHISPER" and Trim(whisperTarget) or nil,
                }
            end
        end
    end

    if #lines == 0 then
        return nil, T("Enter a message first.")
    end
    return lines
end

local function SplitMessage(text, channel, whisperTarget, profile)
    local logical, err = BuildLogicalLines(text, channel, whisperTarget)
    if not logical then return nil, err end

    local settings = {
        chunkLimit = ClampLimit(profile.chunkLimit),
        showCounter = profile.showCounter ~= false,
        continuation = profile.continuation or "BOTH",
    }

    -- Counter width changes when the chunk count changes (9 -> 10, 99 -> 100),
    -- so recalculate until the count stabilizes.
    local expected = 1
    local result
    for _ = 1, 8 do
        result = {}
        for _, entry in ipairs(logical) do
            SplitLogicalLine(result, entry, settings, expected)
        end
        if #result == expected then break end
        expected = math.max(1, #result)
    end

    result = {}
    for _, entry in ipairs(logical) do
        SplitLogicalLine(result, entry, settings, expected)
    end
    if #result ~= expected then
        expected = #result
        result = {}
        for _, entry in ipairs(logical) do
            SplitLogicalLine(result, entry, settings, expected)
        end
    end

    if #result == 0 then
        return nil, T("No sendable text was produced.")
    end
    return result
end

local function ChannelLabel(chatType, target)
    if chatType == "WHISPER" then
        return T("Whisper") .. (Trim(target) ~= "" and (" " .. Trim(target)) or "")
    end
    for _, entry in ipairs(CHANNELS) do
        if entry.value == chatType then return T(entry.label) end
    end
    return tostring(chatType or "?")
end

local function SendChunk(chunk)
    if type(chunk) ~= "table" or type(chunk.text) ~= "string" or chunk.text == "" then
        return false, T("This chunk is empty.")
    end

    if type(ns.IsProtectedChatValue) == "function" and ns.IsProtectedChatValue(chunk.text) then
        return false, T("WoW marked this text as protected. It was not sent.")
    end
    if chunk.target and type(ns.IsProtectedChatValue) == "function" and ns.IsProtectedChatValue(chunk.target) then
        return false, T("WoW marked the target as protected. It was not sent.")
    end

    local usable, reason = IsChannelUsable(chunk.channel, chunk.target)
    if not usable then return false, reason end

    if type(ns.CanSendAddonChat) == "function" and not ns.CanSendAddonChat() then
        return false, T("WoW is blocking addon chat sends right now. Try again after the protected activity ends.")
    end

    if type(ns.SendChatMessageCompat) == "function" then
        local ok, sendReason = ns.SendChatMessageCompat(chunk.text, chunk.channel, nil, chunk.target)
        if ok then return true end
        return false, sendReason or T("The message could not be sent.")
    end

    if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then
        local ok = pcall(C_ChatInfo.SendChatMessage, chunk.text, chunk.channel, nil, chunk.target)
        if ok then return true end
    end
    if type(SendChatMessage) == "function" then
        local ok = pcall(SendChatMessage, chunk.text, chunk.channel, nil, chunk.target)
        if ok then return true end
    end
    return false, T("No supported chat send API is available on this client.")
end

local function InsertIntoMultiLine(widget, text)
    if not widget or type(text) ~= "string" then return end
    local editBox = widget.editBox
    if editBox and type(editBox.Insert) == "function" then
        editBox:SetFocus()
        editBox:Insert(text)
        return
    end
    local current = type(widget.GetText) == "function" and widget:GetText() or ""
    if type(widget.SetText) == "function" then
        widget:SetText(current .. text)
    end
end

function Composer:BuildChunks(text, channel, whisperTarget)
    local profile = GetProfile()
    if not profile then return nil, T("Chatify settings are not ready yet.") end
    return SplitMessage(text, channel, whisperTarget, profile)
end

function Composer:Open()
    if not AceGUI then
        self:Print(T("The message composer UI is not available on this client."))
        return
    end

    if self.window then
        if self.window.frame and self.window.frame.Show then self.window.frame:Show() end
        return
    end

    local profile = GetProfile()
    if not profile then return end

    local frame = AceGUI:Create("Frame")
    self.window = frame
    frame:SetTitle(T("Chatify - Long Message Composer"))
    frame:SetStatusText(T("Messages are sent one chunk at a time. Chatify never auto-spams the queue."))
    frame:SetLayout("Flow")
    frame:SetWidth(760)
    frame:SetHeight(700)
    frame:SetCallback("OnClose", function(widget)
        self.window = nil
        self.inputWidget = nil
        AceGUI:Release(widget)
    end)

    local state = {
        chunks = {},
        index = 1,
        channel = profile.defaultChannel or "SAY",
        whisperTarget = "",
    }

    local channelValues, channelOrder = GetAvailableChannelList()
    if not channelValues[state.channel] then
        state.channel = channelOrder[1] or "SAY"
    end

    local channelDrop = AceGUI:Create("Dropdown")
    channelDrop:SetLabel(T("Channel"))
    channelDrop:SetList(channelValues, channelOrder)
    channelDrop:SetValue(state.channel)
    channelDrop:SetRelativeWidth(0.42)
    frame:AddChild(channelDrop)

    local targetBox = AceGUI:Create("EditBox")
    targetBox:SetLabel(T("Whisper Target"))
    targetBox:SetRelativeWidth(0.36)
    targetBox:SetText("")
    frame:AddChild(targetBox)

    local markerDrop = AceGUI:Create("Dropdown")
    local markerValues, markerOrder = {}, {}
    for _, marker in ipairs(TARGET_MARKERS) do
        markerValues[marker.value] = T(marker.label)
        markerOrder[#markerOrder + 1] = marker.value
    end
    markerDrop:SetLabel(T("Insert Raid Marker"))
    markerDrop:SetList(markerValues, markerOrder)
    markerDrop:SetRelativeWidth(0.22)
    frame:AddChild(markerDrop)

    local input = AceGUI:Create("MultiLineEditBox")
    self.inputWidget = input
    input:SetLabel(T("Message"))
    input:SetNumLines(12)
    input:SetFullWidth(true)
    input:DisableButton(true)
    frame:AddChild(input)

    local hint = AceGUI:Create("Label")
    hint:SetFullWidth(true)
    hint:SetText(T("Per Line mode supports /s, /e, /y, /p, /raid, /rw, /i, /g, /o and /w Name. Each non-empty line is parsed separately."))
    frame:AddChild(hint)

    local splitButton = AceGUI:Create("Button")
    splitButton:SetText(T("Split / Refresh Preview"))
    splitButton:SetRelativeWidth(0.34)
    frame:AddChild(splitButton)

    local clearButton = AceGUI:Create("Button")
    clearButton:SetText(T("Clear"))
    clearButton:SetRelativeWidth(0.18)
    frame:AddChild(clearButton)

    local status = AceGUI:Create("Label")
    status:SetRelativeWidth(0.48)
    status:SetText(T("No chunks yet."))
    frame:AddChild(status)

    local preview = AceGUI:Create("MultiLineEditBox")
    preview:SetLabel(T("Current Chunk Preview"))
    preview:SetNumLines(7)
    preview:SetFullWidth(true)
    preview:DisableButton(true)
    preview:SetDisabled(true)
    frame:AddChild(preview)

    local prevButton = AceGUI:Create("Button")
    prevButton:SetText(T("Previous"))
    prevButton:SetRelativeWidth(0.2)
    frame:AddChild(prevButton)

    local sendButton = AceGUI:Create("Button")
    sendButton:SetText(T("Send Current Chunk"))
    sendButton:SetRelativeWidth(0.4)
    frame:AddChild(sendButton)

    local nextButton = AceGUI:Create("Button")
    nextButton:SetText(T("Next"))
    nextButton:SetRelativeWidth(0.2)
    frame:AddChild(nextButton)

    local info = AceGUI:Create("Label")
    info:SetRelativeWidth(0.2)
    info:SetText("")
    frame:AddChild(info)

    local function UpdateTargetVisibility()
        local visible = state.channel == "WHISPER"
        if targetBox.frame then
            if visible and type(targetBox.frame.Show) == "function" then
                targetBox.frame:Show()
            elseif not visible and type(targetBox.frame.Hide) == "function" then
                targetBox.frame:Hide()
            end
        end
        if frame and type(frame.DoLayout) == "function" then frame:DoLayout() end
    end

    local function UpdatePreview(message)
        local count = #state.chunks
        if count == 0 then
            preview:SetText("")
            status:SetText(message or T("No chunks yet."))
            info:SetText("")
            return
        end
        if state.index < 1 then state.index = 1 end
        if state.index > count then state.index = count end
        local chunk = state.chunks[state.index]
        preview:SetText(chunk.text or "")
        local channelName = ChannelLabel(chunk.channel, chunk.target)
        local chunkStatus = string.format(T("Chunk %d of %d - %s"), state.index, count, channelName)
        if type(message) == "string" and message ~= "" then
            chunkStatus = message .. "  " .. chunkStatus
        end
        status:SetText(chunkStatus)
        info:SetText(string.format(T("%d / %d bytes"), #(chunk.text or ""), ClampLimit(profile.chunkLimit)))
    end

    local function Rebuild()
        state.whisperTarget = targetBox:GetText() or ""
        local chunks, err = self:BuildChunks(input:GetText() or "", state.channel, state.whisperTarget)
        if not chunks then
            state.chunks = {}
            state.index = 1
            UpdatePreview(err)
            return
        end
        state.chunks = chunks
        state.index = 1
        UpdatePreview()
    end

    channelDrop:SetCallback("OnValueChanged", function(_, _, value)
        state.channel = value
        profile.defaultChannel = value
        UpdateTargetVisibility()
        if #state.chunks > 0 then Rebuild() end
    end)

    targetBox:SetCallback("OnTextChanged", function(_, _, value)
        state.whisperTarget = value or ""
    end)

    markerDrop:SetCallback("OnValueChanged", function(_, _, value)
        InsertIntoMultiLine(input, value .. " ")
        markerDrop:SetValue(nil)
    end)

    splitButton:SetCallback("OnClick", Rebuild)
    clearButton:SetCallback("OnClick", function()
        input:SetText("")
        targetBox:SetText("")
        state.chunks = {}
        state.index = 1
        UpdatePreview(T("Composer cleared."))
    end)
    prevButton:SetCallback("OnClick", function()
        if state.index > 1 then state.index = state.index - 1 end
        UpdatePreview()
    end)
    nextButton:SetCallback("OnClick", function()
        if state.index < #state.chunks then state.index = state.index + 1 end
        UpdatePreview()
    end)
    sendButton:SetCallback("OnClick", function()
        if #state.chunks == 0 then
            Rebuild()
            if #state.chunks == 0 then return end
        end
        local chunk = state.chunks[state.index]
        local ok, reason = SendChunk(chunk)
        if not ok then
            local shown = reason
            if reason == "chat messaging lockdown" then
                shown = T("WoW is blocking addon chat sends right now. Try again after the protected activity ends.")
            elseif reason == "protected message" or reason == "protected target" then
                shown = T("WoW protected this message or target. It was not sent.")
            elseif type(reason) ~= "string" or reason == "" then
                shown = T("The message could not be sent.")
            end
            UpdatePreview(shown)
            return
        end
        if state.index < #state.chunks then
            state.index = state.index + 1
            UpdatePreview(T("Sent. Ready for the next chunk."))
        else
            UpdatePreview(T("Final chunk sent."))
        end
    end)

    UpdateTargetVisibility()
    UpdatePreview()
    input:SetFocus()
end

function Composer:HandleCommand(input)
    input = Trim(input)
    self:Open()
    if input ~= "" and self.inputWidget and type(self.inputWidget.SetText) == "function" then
        self.inputWidget:SetText(input)
        self.inputWidget:SetFocus()
    end
end

function Composer:OnEnable()
    if type(ns.IsFeatureAvailable) == "function" and not ns.IsFeatureAvailable("composer") then
        ns.OpenChatComposer = nil
        return
    end

    self:RegisterChatCommand("chatcompose", "HandleCommand")
    self:RegisterChatCommand("chatcomposer", "HandleCommand")
    ns.OpenChatComposer = function()
        if type(ns.IsFeatureAvailable) == "function" and not ns.IsFeatureAvailable("composer") then
            return false
        end
        local module = Chatify:GetModule("Composer", true)
        if module and type(module.Open) == "function" then
            module:Open()
            return true
        end
        return false
    end
end

ns.GetComposerChannelValues = function()
    local values = {}
    for _, entry in ipairs(CHANNELS) do
        if entry.value ~= "PER_LINE" then
            values[entry.value] = T(entry.label)
        end
    end
    values.PER_LINE = T("Per Line")
    return values
end

ns.GetComposerContinuationValues = function()
    local values = {}
    for key, value in pairs(CONTINUATION_MODES) do
        values[key] = T(value)
    end
    return values
end
