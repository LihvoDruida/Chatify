local addonName, ns = ...
local Chatify = ns.Chatify or _G.Chatify
if not Chatify then return end

local Composer = Chatify:NewModule("Composer", "AceConsole-3.0", "AceEvent-3.0")
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

local function ClampAutomationDelay(value)
    value = tonumber(value) or 1.5
    if value < 0.8 then value = 0.8 end
    if value > 10 then value = 10 end
    return math.floor(value * 10 + 0.5) / 10
end

local fallbackTimerFrame
local fallbackTimerQueue = {}

local function ScheduleAfter(delay, callback)
    delay = tonumber(delay) or 0
    if type(callback) ~= "function" then return false end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(delay, callback)
        return true
    end
    if type(CreateFrame) ~= "function" then return false end
    if not fallbackTimerFrame then
        fallbackTimerFrame = CreateFrame("Frame")
        fallbackTimerFrame:SetScript("OnUpdate", function(_, dt)
            dt = tonumber(dt) or 0
            for i = #fallbackTimerQueue, 1, -1 do
                local task = fallbackTimerQueue[i]
                task.remaining = task.remaining - dt
                if task.remaining <= 0 then
                    table.remove(fallbackTimerQueue, i)
                    pcall(task.callback)
                end
            end
        end)
    end
    fallbackTimerQueue[#fallbackTimerQueue + 1] = {
        remaining = math.max(0, delay),
        callback = callback,
    }
    return true
end

local function AutomationNeedsHardwareEvent(chatType)
    -- These channels are hardware-event restricted on current clients in at
    -- least some contexts. Timed sends must never assume they are safe.
    return chatType == "SAY" or chatType == "YELL" or chatType == "CHANNEL"
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
    if type(c.whisperTarget) ~= "string" then c.whisperTarget = "" end
    if c.autoPreview == nil then c.autoPreview = true end
    if c.autoAdvance == nil then c.autoAdvance = true end
    if c.automationEnabled == nil then c.automationEnabled = false end
    c.automationDelay = ClampAutomationDelay(c.automationDelay)
    if c.automationAutoStart == nil then c.automationAutoStart = false end
    if c.automationResumeAfterManual == nil then c.automationResumeAfterManual = true end
    if c.automationResumeAfterLockdown == nil then c.automationResumeAfterLockdown = false end
    if c.lockFinalChunk == nil then c.lockFinalChunk = true end
    if c.rememberWhisperTarget == nil then c.rememberWhisperTarget = true end
    if c.spellcheckIntegration == nil then c.spellcheckIntegration = true end
    return c
end


local function StripSpellcheckMarkup(text)
    if type(text) ~= "string" then return "" end
    local spell = _G.Misspelled
    if spell and type(spell.RemoveHighlighting) == "function" then
        local ok, cleaned = pcall(spell.RemoveHighlighting, spell, text)
        if ok and type(cleaned) == "string" then
            return cleaned
        end
    end
    return text
end

local function WireSpellcheck(widget, profile)
    if not profile or profile.spellcheckIntegration == false or not widget then return false end
    local editBox = widget.editBox
    local spell = _G.Misspelled
    if not editBox or not spell or type(spell.WireUpEditBox) ~= "function" then return false end
    local ok = pcall(spell.WireUpEditBox, spell, editBox)
    return ok and true or false
end

local function IsComposerEnabled()
    local profile = GetProfile()
    return profile and profile.enabled == true or false
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

local function IsComposerChannel(chatType)
    if type(chatType) ~= "string" then return false end
    for _, entry in ipairs(CHANNELS) do
        if entry.value == chatType and entry.value ~= "PER_LINE" then
            return true
        end
    end
    return false
end

local function GetCurrentChatImport()
    if type(ns.GetActiveChatDraftContext) ~= "function" then return nil end
    local ok, context = pcall(ns.GetActiveChatDraftContext)
    if not ok or type(context) ~= "table" then return nil end
    if context.isShown ~= true then return nil end
    return context
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

function Composer:OpenHelp()
    if not AceGUI then return end
    if self.helpWindow then
        if self.helpWindow.frame and self.helpWindow.frame.Show then self.helpWindow.frame:Show() end
        return
    end

    local frame = AceGUI:Create("Frame")
    self.helpWindow = frame
    frame:SetTitle(T("Long Message Composer Help"))
    frame:SetLayout("Fill")
    frame:SetWidth(680)
    frame:SetHeight(560)
    frame:SetCallback("OnClose", function(widget)
        if widget.frame and widget.frame.Hide then widget.frame:Hide() end
    end)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    frame:AddChild(scroll)

    local text = AceGUI:Create("Label")
    text:SetFullWidth(true)
    text:SetText(T("LONG_MESSAGE_COMPOSER_HELP"))
    scroll:AddChild(text)
end

function Composer:OpenSettings()
    if Chatify and type(Chatify.OpenConfig) == "function" then
        Chatify:OpenConfig()
    end
    local dialog = LibStub and LibStub("AceConfigDialog-3.0", true) or nil
    if dialog and type(dialog.SelectGroup) == "function" then
        pcall(dialog.SelectGroup, dialog, "Chatify", "tabComposer")
    end
end

function Composer:GetEffectiveRouting(state, chunk)
    if not state or not chunk then return nil, nil end
    if state.chunksUsePerLineChannels then
        return chunk.channel, chunk.target
    end
    if state.channel == "PER_LINE" then
        return nil, nil
    end
    local target = state.channel == "WHISPER" and Trim(state.whisperTarget) or nil
    return state.channel, target
end

function Composer:RefreshRuntimeState(event, addonName)
    local ui = self.ui
    if event == "ADDON_LOADED" and addonName == "Misspelled" then
        local profile = GetProfile()
        if profile and profile.spellcheckIntegration ~= false and self.inputWidget then
            WireSpellcheck(self.inputWidget, profile)
        end
    end
    if not ui or not ui.channelDrop or not self.sessionState then return end
    local values, order = GetAvailableChannelList()
    ui.channelValues, ui.channelOrder = values, order
    ui.channelDrop:SetList(values, order)
    local state = self.sessionState
    if state.channel ~= "PER_LINE" and not values[state.channel] then
        state.channel = order[1] or "SAY"
        ui.channelDrop:SetValue(state.channel)
    end
    if type(self.UpdateComposerUI) == "function" then
        self:UpdateComposerUI()
    end
end

function Composer:Open(options)
    options = type(options) == "table" and options or {}
    if not IsComposerEnabled() then
        self:Print(T("Long Message Mode is disabled. Enable it in Chatify settings."))
        return false
    end
    if not AceGUI then
        self:Print(T("The message composer UI is not available on this client."))
        return false
    end

    local profile = GetProfile()
    if not profile then return false end

    -- Reuse the same window/session instead of destroying the draft on close.
    if self.window then
        if self.window.frame and self.window.frame.Show then self.window.frame:Show() end
        if type(options.text) == "string" and options.text ~= "" and self.inputWidget then
            self.inputWidget:SetText(options.text)
            if options.autoSplit ~= false and profile.autoPreview ~= false and type(self.RebuildPreview) == "function" then
                self:RebuildPreview()
            end
        elseif options.importCurrentChat and type(self.ImportCurrentChat) == "function" then
            self:ImportCurrentChat(profile.autoPreview ~= false)
        end
        if self.inputWidget and type(self.inputWidget.SetFocus) == "function" then self.inputWidget:SetFocus() end
        return true
    end

    local state = self.sessionState or {
        chunks = {},
        index = 1,
        lastSentIndex = 0,
        finalChunkSent = false,
        previewDirty = false,
        chunksUsePerLineChannels = false,
        channel = profile.defaultChannel or "SAY",
        whisperTarget = profile.rememberWhisperTarget ~= false and (profile.whisperTarget or "") or "",
        inputText = "",
        automationRunning = false,
        automationPaused = false,
        automationWaitingManual = false,
        automationWaitingLockdown = false,
        automationRunId = 0,
        automationMessage = nil,
    }
    self.sessionState = state
    state.automationRunning = state.automationRunning == true
    state.automationPaused = state.automationPaused == true
    state.automationWaitingManual = state.automationWaitingManual == true
    state.automationWaitingLockdown = state.automationWaitingLockdown == true
    state.automationRunId = tonumber(state.automationRunId) or 0

    local initialImport = nil
    if options.importCurrentChat and profile.importCurrentDraft ~= false then
        initialImport = GetCurrentChatImport()
        if initialImport and IsComposerChannel(initialImport.chatType) then
            local usable = initialImport.chatType == "WHISPER" or IsChannelUsable(initialImport.chatType)
            if usable then
                state.channel = initialImport.chatType
                if initialImport.chatType == "WHISPER" then
                    state.whisperTarget = Trim(initialImport.tellTarget)
                end
            end
        end
        if initialImport and type(initialImport.text) == "string" and initialImport.text ~= "" then
            state.inputText = initialImport.text
        end
    elseif type(options.text) == "string" and options.text ~= "" then
        state.inputText = options.text
    end

    local channelValues, channelOrder = GetAvailableChannelList()
    if state.channel ~= "PER_LINE" and not channelValues[state.channel] then
        state.channel = channelOrder[1] or "SAY"
    end

    local frame = AceGUI:Create("Frame")
    self.window = frame
    frame:SetTitle(T("Chatify - Long Message Composer"))
    frame:SetStatusText(T("Manual sending is always available. Queue automation sends only supported channels and pauses when WoW requires a hardware click."))
    frame:SetLayout("Flow")
    frame:SetWidth(800)
    frame:SetHeight(880)
    frame:SetCallback("OnClose", function(widget)
        if self.inputWidget and type(self.inputWidget.GetText) == "function" then
            state.inputText = self.inputWidget:GetText() or ""
        end
        if type(self.StopAutomation) == "function" then self:StopAutomation(nil, true) end
        if widget.frame and widget.frame.Hide then widget.frame:Hide() end
    end)

    local channelDrop = AceGUI:Create("Dropdown")
    channelDrop:SetLabel(T("Channel"))
    channelDrop:SetList(channelValues, channelOrder)
    channelDrop:SetValue(state.channel)
    channelDrop:SetRelativeWidth(0.34)
    frame:AddChild(channelDrop)

    local targetBox = AceGUI:Create("EditBox")
    targetBox:SetLabel(T("Whisper Target"))
    targetBox:SetRelativeWidth(0.33)
    targetBox:SetText(state.whisperTarget or "")
    frame:AddChild(targetBox)

    local markerDrop = AceGUI:Create("Dropdown")
    local markerValues, markerOrder = {}, {}
    for _, marker in ipairs(TARGET_MARKERS) do
        markerValues[marker.value] = T(marker.label)
        markerOrder[#markerOrder + 1] = marker.value
    end
    markerDrop:SetLabel(T("Insert Raid Marker"))
    markerDrop:SetList(markerValues, markerOrder)
    markerDrop:SetRelativeWidth(0.33)
    frame:AddChild(markerDrop)

    -- Composer-local settings mirror the main Chatify settings and rebuild the
    -- loaded preview immediately, matching the original long-message workflow.
    local limitSlider = AceGUI:Create("Slider")
    limitSlider:SetLabel(T("Chunk Byte Limit"))
    limitSlider:SetSliderValues(MIN_LIMIT, MAX_LIMIT, 1)
    limitSlider:SetValue(ClampLimit(profile.chunkLimit))
    limitSlider:SetRelativeWidth(0.34)
    frame:AddChild(limitSlider)

    local counterCheck = AceGUI:Create("CheckBox")
    counterCheck:SetLabel(T("Show Chunk Counter"))
    counterCheck:SetValue(profile.showCounter ~= false)
    counterCheck:SetRelativeWidth(0.28)
    frame:AddChild(counterCheck)

    local continuationDrop = AceGUI:Create("Dropdown")
    continuationDrop:SetLabel(T("Continuation Markers"))
    continuationDrop:SetList(ns.GetComposerContinuationValues and ns.GetComposerContinuationValues() or CONTINUATION_MODES, { "BOTH", "START", "END", "NONE" })
    continuationDrop:SetValue(profile.continuation or "BOTH")
    continuationDrop:SetRelativeWidth(0.38)
    frame:AddChild(continuationDrop)

    local importDraftCheck = AceGUI:Create("CheckBox")
    importDraftCheck:SetLabel(T("Use Current Chat Draft"))
    importDraftCheck:SetValue(profile.importCurrentDraft ~= false)
    importDraftCheck:SetRelativeWidth(0.33)
    frame:AddChild(importDraftCheck)

    local rememberWhisperCheck = AceGUI:Create("CheckBox")
    rememberWhisperCheck:SetLabel(T("Remember Whisper Target"))
    rememberWhisperCheck:SetValue(profile.rememberWhisperTarget ~= false)
    rememberWhisperCheck:SetRelativeWidth(0.33)
    frame:AddChild(rememberWhisperCheck)

    local spellcheckCheck = AceGUI:Create("CheckBox")
    spellcheckCheck:SetLabel(T("Spell Check Integration"))
    spellcheckCheck:SetValue(profile.spellcheckIntegration ~= false)
    spellcheckCheck:SetRelativeWidth(0.34)
    if not (_G.Misspelled and type(_G.Misspelled.WireUpEditBox) == "function") then
        spellcheckCheck:SetDisabled(true)
    end
    frame:AddChild(spellcheckCheck)

    local autoPreviewCheck = AceGUI:Create("CheckBox")
    autoPreviewCheck:SetLabel(T("Auto-build Preview"))
    autoPreviewCheck:SetValue(profile.autoPreview ~= false)
    autoPreviewCheck:SetRelativeWidth(0.33)
    frame:AddChild(autoPreviewCheck)

    local autoAdvanceCheck = AceGUI:Create("CheckBox")
    autoAdvanceCheck:SetLabel(T("Advance After Send"))
    autoAdvanceCheck:SetValue(profile.autoAdvance ~= false)
    autoAdvanceCheck:SetRelativeWidth(0.33)
    frame:AddChild(autoAdvanceCheck)

    local finalLockCheck = AceGUI:Create("CheckBox")
    finalLockCheck:SetLabel(T("Protect Final Chunk"))
    finalLockCheck:SetValue(profile.lockFinalChunk ~= false)
    finalLockCheck:SetRelativeWidth(0.34)
    frame:AddChild(finalLockCheck)

    local automationCheck = AceGUI:Create("CheckBox")
    automationCheck:SetLabel(T("Enable Queue Automation"))
    automationCheck:SetValue(profile.automationEnabled == true)
    automationCheck:SetRelativeWidth(0.33)
    frame:AddChild(automationCheck)

    local automationDelaySlider = AceGUI:Create("Slider")
    automationDelaySlider:SetLabel(T("Automation Delay"))
    automationDelaySlider:SetSliderValues(0.8, 10, 0.1)
    automationDelaySlider:SetValue(ClampAutomationDelay(profile.automationDelay))
    automationDelaySlider:SetRelativeWidth(0.33)
    automationDelaySlider:SetDisabled(profile.automationEnabled ~= true)
    frame:AddChild(automationDelaySlider)

    local automationAutoStartCheck = AceGUI:Create("CheckBox")
    automationAutoStartCheck:SetLabel(T("Auto-start After Split"))
    automationAutoStartCheck:SetValue(profile.automationAutoStart == true)
    automationAutoStartCheck:SetRelativeWidth(0.34)
    automationAutoStartCheck:SetDisabled(profile.automationEnabled ~= true)
    frame:AddChild(automationAutoStartCheck)

    local automationResumeManualCheck = AceGUI:Create("CheckBox")
    automationResumeManualCheck:SetLabel(T("Resume After Manual Chunk"))
    automationResumeManualCheck:SetValue(profile.automationResumeAfterManual ~= false)
    automationResumeManualCheck:SetRelativeWidth(0.50)
    automationResumeManualCheck:SetDisabled(profile.automationEnabled ~= true)
    frame:AddChild(automationResumeManualCheck)

    local automationResumeLockdownCheck = AceGUI:Create("CheckBox")
    automationResumeLockdownCheck:SetLabel(T("Resume After Chat Lockdown"))
    automationResumeLockdownCheck:SetValue(profile.automationResumeAfterLockdown == true)
    automationResumeLockdownCheck:SetRelativeWidth(0.50)
    automationResumeLockdownCheck:SetDisabled(profile.automationEnabled ~= true)
    frame:AddChild(automationResumeLockdownCheck)

    local automationHint = AceGUI:Create("Label")
    automationHint:SetFullWidth(true)
    local automationHintText = T("Automation works for channels that WoW allows addons to send without a hardware click. Say, Yell and other restricted channels pause and wait for manual Send.")
    if type(ns.IsFeatureRisky) == "function" and ns.IsFeatureRisky("composerAutomation") then
        local warning = type(ns.GetFeatureWarningText) == "function" and ns.GetFeatureWarningText("composerAutomation") or nil
        if type(warning) == "string" and warning ~= "" then
            automationHintText = "|cffd69a5b" .. T("Warning:") .. " " .. T(warning) .. "|r\n" .. automationHintText
        end
    end
    automationHint:SetText(automationHintText)
    frame:AddChild(automationHint)

    local input = AceGUI:Create("MultiLineEditBox")
    self.inputWidget = input
    input:SetLabel(T("Message"))
    input:SetNumLines(12)
    input:SetFullWidth(true)
    input:DisableButton(true)
    input:SetText(state.inputText or "")
    frame:AddChild(input)

    local hint = AceGUI:Create("Label")
    hint:SetFullWidth(true)
    hint:SetText(T("Per Line mode supports /s, /e, /y, /p, /raid, /rw, /i, /g, /o and /w Name. Each non-empty line is parsed separately."))
    frame:AddChild(hint)

    local importButton = AceGUI:Create("Button")
    importButton:SetText(T("Use Current Chat"))
    importButton:SetRelativeWidth(0.20)
    frame:AddChild(importButton)

    local splitButton = AceGUI:Create("Button")
    splitButton:SetText(T("Split / Refresh Preview"))
    splitButton:SetRelativeWidth(0.25)
    frame:AddChild(splitButton)

    local clearButton = AceGUI:Create("Button")
    clearButton:SetText(T("Clear"))
    clearButton:SetRelativeWidth(0.13)
    frame:AddChild(clearButton)

    local helpButton = AceGUI:Create("Button")
    helpButton:SetText(T("Help"))
    helpButton:SetRelativeWidth(0.13)
    frame:AddChild(helpButton)

    local settingsButton = AceGUI:Create("Button")
    settingsButton:SetText(T("Settings"))
    settingsButton:SetRelativeWidth(0.13)
    frame:AddChild(settingsButton)

    local status = AceGUI:Create("Label")
    status:SetFullWidth(true)
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
    prevButton:SetText(T("Previous Chunk"))
    prevButton:SetRelativeWidth(0.20)
    frame:AddChild(prevButton)

    local nextButton = AceGUI:Create("Button")
    nextButton:SetText(T("Next Chunk"))
    nextButton:SetRelativeWidth(0.20)
    frame:AddChild(nextButton)

    local sendButton = AceGUI:Create("Button")
    sendButton:SetText(T("Send This Chunk"))
    sendButton:SetRelativeWidth(0.24)
    frame:AddChild(sendButton)

    local automationStartButton = AceGUI:Create("Button")
    automationStartButton:SetText(T("Start Auto Send"))
    automationStartButton:SetRelativeWidth(0.20)
    frame:AddChild(automationStartButton)

    local automationStopButton = AceGUI:Create("Button")
    automationStopButton:SetText(T("Stop Auto Send"))
    automationStopButton:SetRelativeWidth(0.20)
    frame:AddChild(automationStopButton)

    local info = AceGUI:Create("Label")
    info:SetRelativeWidth(0.36)
    info:SetText("")
    frame:AddChild(info)

    self.ui = {
        frame = frame,
        channelDrop = channelDrop,
        channelValues = channelValues,
        channelOrder = channelOrder,
        targetBox = targetBox,
        markerDrop = markerDrop,
        limitSlider = limitSlider,
        counterCheck = counterCheck,
        continuationDrop = continuationDrop,
        importDraftCheck = importDraftCheck,
        rememberWhisperCheck = rememberWhisperCheck,
        spellcheckCheck = spellcheckCheck,
        autoPreviewCheck = autoPreviewCheck,
        autoAdvanceCheck = autoAdvanceCheck,
        finalLockCheck = finalLockCheck,
        automationCheck = automationCheck,
        automationDelaySlider = automationDelaySlider,
        automationAutoStartCheck = automationAutoStartCheck,
        automationResumeManualCheck = automationResumeManualCheck,
        automationResumeLockdownCheck = automationResumeLockdownCheck,
        automationHint = automationHint,
        input = input,
        status = status,
        preview = preview,
        prevButton = prevButton,
        nextButton = nextButton,
        sendButton = sendButton,
        automationStartButton = automationStartButton,
        automationStopButton = automationStopButton,
        info = info,
    }

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

    local function EffectiveRouting(chunk)
        return self:GetEffectiveRouting(state, chunk)
    end

    local UpdatePreview

    local function InvalidateAutomationRun()
        state.automationRunId = (tonumber(state.automationRunId) or 0) + 1
        return state.automationRunId
    end

    local function SetAutomationStopped(message, paused, waitingManual, waitingLockdown)
        InvalidateAutomationRun()
        state.automationRunning = false
        state.automationPaused = paused == true
        state.automationWaitingManual = waitingManual == true
        state.automationWaitingLockdown = waitingLockdown == true
        state.automationMessage = message
        if UpdatePreview then UpdatePreview(message) end
    end

    local function StopAutomation(message, silent)
        InvalidateAutomationRun()
        state.automationRunning = false
        state.automationPaused = false
        state.automationWaitingManual = false
        state.automationWaitingLockdown = false
        state.automationMessage = message
        if not silent and UpdatePreview then UpdatePreview(message or T("Automation stopped.")) end
    end
    self.StopAutomation = StopAutomation

    local function FinishAutomation(message)
        InvalidateAutomationRun()
        state.automationRunning = false
        state.automationPaused = false
        state.automationWaitingManual = false
        state.automationWaitingLockdown = false
        state.automationMessage = message or T("Automation finished.")
        if UpdatePreview then UpdatePreview(state.automationMessage) end
    end

    local function StartAutomation(fromHardwareEvent)
        if profile.automationEnabled ~= true then
            UpdatePreview(T("Queue automation is disabled."))
            return false
        end
        if #state.chunks == 0 or state.previewDirty then
            UpdatePreview(T("Build a current preview before starting automation."))
            return false
        end

        local runId = InvalidateAutomationRun()
        state.automationRunning = true
        state.automationPaused = false
        state.automationWaitingManual = false
        state.automationWaitingLockdown = false
        state.automationMessage = T("Automation running.")

        local function Step(hardwareEvent)
            if runId ~= state.automationRunId or not state.automationRunning then return end
            if profile.automationEnabled ~= true then
                StopAutomation(T("Automation stopped because it was disabled."))
                return
            end
            if state.previewDirty or #state.chunks == 0 then
                SetAutomationStopped(T("Automation paused because the preview changed."), true, false, false)
                return
            end
            if state.index < 1 then state.index = 1 end
            if state.index > #state.chunks then
                FinishAutomation(T("Automation finished."))
                return
            end

            local chunk = state.chunks[state.index]
            local chatType, target = EffectiveRouting(chunk)
            if not chatType then
                SetAutomationStopped(T("Automation paused. Refresh the preview to apply Per Line routing."), true, false, false)
                return
            end

            if AutomationNeedsHardwareEvent(chatType) and not hardwareEvent then
                SetAutomationStopped(T("Automation paused. This channel requires a manual Send click."), true, true, false)
                return
            end

            if type(ns.CanSendAddonChat) == "function" and not ns.CanSendAddonChat() then
                if profile.automationResumeAfterLockdown == true then
                    state.automationWaitingLockdown = true
                    state.automationMessage = T("Automation is waiting for chat lockdown to end.")
                    if UpdatePreview then UpdatePreview(state.automationMessage) end
                    local delay = ClampAutomationDelay(profile.automationDelay)
                    if not ScheduleAfter(delay, function()
                        if runId ~= state.automationRunId or not state.automationRunning then return end
                        state.automationWaitingLockdown = false
                        Step(false)
                    end) then
                        SetAutomationStopped(T("Automation paused because no timer API is available."), true, false, false)
                    end
                else
                    SetAutomationStopped(T("Automation paused while WoW blocks addon chat."), true, false, true)
                end
                return
            end

            local outgoing = {
                text = StripSpellcheckMarkup(chunk.text or ""),
                channel = chatType,
                target = target,
            }
            local ok, reason = SendChunk(outgoing)
            if not ok then
                local shown = type(reason) == "string" and reason or T("The message could not be sent.")
                SetAutomationStopped(T("Automation paused: ") .. shown, true, false, false)
                return
            end

            state.lastSentIndex = state.index
            state.finalChunkSent = false
            if state.index >= #state.chunks then
                state.finalChunkSent = true
                FinishAutomation(T("Automation finished. Final chunk sent."))
                return
            end

            state.index = state.index + 1
            state.automationMessage = T("Automation running.")
            if UpdatePreview then UpdatePreview(state.automationMessage) end
            local delay = ClampAutomationDelay(profile.automationDelay)
            if not ScheduleAfter(delay, function() Step(false) end) then
                SetAutomationStopped(T("Automation paused because no timer API is available."), true, false, false)
            end
        end

        Step(fromHardwareEvent == true)
        return true
    end
    self.StartAutomation = StartAutomation

    UpdatePreview = function(message)
        local count = #state.chunks
        if count == 0 then
            preview:SetText("")
            status:SetText(message or state.automationMessage or T("No chunks yet."))
            info:SetText("")
            prevButton:SetDisabled(true)
            nextButton:SetDisabled(true)
            sendButton:SetDisabled(true)
            automationStartButton:SetDisabled(true)
            automationStopButton:SetDisabled(not (state.automationRunning or state.automationPaused))
            automationStartButton:SetText(state.automationPaused and T("Resume Auto Send") or T("Start Auto Send"))
            return
        end
        if state.index < 1 then state.index = 1 end
        if state.index > count then state.index = count end
        local chunk = state.chunks[state.index]
        preview:SetText(chunk.text or "")
        local chatType, target = EffectiveRouting(chunk)
        local channelName = chatType and ChannelLabel(chatType, target) or T("Refresh preview to apply Per Line mode.")
        local sentText = state.lastSentIndex > 0 and tostring(state.lastSentIndex) or T("None")
        local chunkStatus = string.format(T("Chunk %d of %d - %s - Last sent: %s"), state.index, count, channelName, sentText)
        if state.previewDirty then
            chunkStatus = T("Message changed. Refresh preview before sending.") .. "  " .. chunkStatus
        end
        local shownMessage = message
        if (type(shownMessage) ~= "string" or shownMessage == "") and type(state.automationMessage) == "string" then
            shownMessage = state.automationMessage
        end
        if type(shownMessage) == "string" and shownMessage ~= "" then
            chunkStatus = shownMessage .. "  " .. chunkStatus
        end
        status:SetText(chunkStatus)
        info:SetText(string.format(T("%d / %d bytes"), #(chunk.text or ""), ClampLimit(profile.chunkLimit)))
        prevButton:SetDisabled(state.index <= 1 or state.automationRunning)
        nextButton:SetDisabled(state.index >= count or state.automationRunning)
        local finalLocked = profile.lockFinalChunk ~= false and state.finalChunkSent and state.index == count
        local manualSendLocked = state.automationRunning and not state.automationWaitingManual
        sendButton:SetDisabled(state.previewDirty or finalLocked or not chatType or manualSendLocked)
        automationStartButton:SetText(state.automationPaused and T("Resume Auto Send") or T("Start Auto Send"))
        automationStartButton:SetDisabled(profile.automationEnabled ~= true or state.previewDirty or finalLocked or not chatType or state.automationRunning)
        automationStopButton:SetDisabled(not (state.automationRunning or state.automationPaused))
    end

    self.UpdateComposerUI = function()
        UpdateTargetVisibility()
        UpdatePreview()
    end

    local function Rebuild(message)
        if state.automationRunning or state.automationPaused then StopAutomation(nil, true) end
        state.whisperTarget = targetBox:GetText() or state.whisperTarget or ""
        if profile.rememberWhisperTarget ~= false then
            profile.whisperTarget = state.whisperTarget
        end
        local text = StripSpellcheckMarkup(input:GetText() or "")
        state.inputText = text
        local chunks, err = self:BuildChunks(text, state.channel, state.whisperTarget)
        if not chunks then
            state.chunks = {}
            state.index = 1
            state.lastSentIndex = 0
            state.finalChunkSent = false
            state.previewDirty = false
            UpdatePreview(err)
            return false
        end
        state.chunks = chunks
        state.index = 1
        state.lastSentIndex = 0
        state.finalChunkSent = false
        state.previewDirty = false
        state.chunksUsePerLineChannels = state.channel == "PER_LINE"
        UpdateTargetVisibility()
        UpdatePreview(message)
        return true
    end
    self.RebuildPreview = Rebuild

    local function ImportCurrentChat(autoBuild)
        if state.automationRunning or state.automationPaused then StopAutomation(nil, true) end
        local context = GetCurrentChatImport()
        if not context then
            UpdatePreview(T("No active chat input was found."))
            return false
        end
        local importedChannel = false
        if IsComposerChannel(context.chatType) then
            local usable = context.chatType == "WHISPER" or IsChannelUsable(context.chatType)
            if usable and (channelValues[context.chatType] or context.chatType == "PER_LINE") then
                state.channel = context.chatType
                channelDrop:SetValue(state.channel)
                importedChannel = true
                if state.channel == "WHISPER" then
                    state.whisperTarget = Trim(context.tellTarget)
                    targetBox:SetText(state.whisperTarget)
                    if profile.rememberWhisperTarget ~= false then profile.whisperTarget = state.whisperTarget end
                end
            end
        end
        if type(context.text) == "string" and context.text ~= "" then
            state.inputText = context.text
            input:SetText(context.text)
        end
        state.chunks = {}
        state.index = 1
        state.lastSentIndex = 0
        state.finalChunkSent = false
        state.previewDirty = false
        state.chunksUsePerLineChannels = false
        UpdateTargetVisibility()
        if autoBuild and state.inputText ~= "" then
            Rebuild(importedChannel and T("Current chat draft and channel imported.") or T("Current chat draft imported. The selected Composer channel was kept."))
        else
            UpdatePreview(importedChannel and T("Current chat draft and channel imported.") or T("Current chat draft imported. The selected Composer channel was kept."))
        end
        return true
    end
    self.ImportCurrentChat = ImportCurrentChat

    local function AutoRebuildSettings()
        if #state.chunks > 0 then
            Rebuild(T("Preview rebuilt with the new settings."))
        else
            UpdatePreview()
        end
    end

    channelDrop:SetCallback("OnValueChanged", function(_, _, value)
        if state.automationRunning or state.automationPaused then StopAutomation(T("Automation stopped because the channel changed.")) end
        state.channel = value
        profile.defaultChannel = value
        UpdateTargetVisibility()
        -- Normal channel changes affect the current chunk at send time, so no
        -- rebuild is needed. Per Line routing is fixed when Split is pressed.
        if value == "PER_LINE" and #state.chunks > 0 and not state.chunksUsePerLineChannels then
            UpdatePreview(T("Press Split / Refresh Preview to apply Per Line routing."))
        else
            UpdatePreview()
        end
    end)

    targetBox:SetCallback("OnTextChanged", function(_, _, value)
        if state.automationRunning or state.automationPaused then StopAutomation(T("Automation stopped because the target changed.")) end
        state.whisperTarget = value or ""
        if profile.rememberWhisperTarget ~= false then profile.whisperTarget = state.whisperTarget end
        UpdatePreview()
    end)

    markerDrop:SetCallback("OnValueChanged", function(_, _, value)
        InsertIntoMultiLine(input, value .. " ")
        markerDrop:SetValue(nil)
    end)

    limitSlider:SetCallback("OnValueChanged", function(_, _, value)
        profile.chunkLimit = ClampLimit(value)
        AutoRebuildSettings()
    end)
    counterCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.showCounter = value and true or false
        AutoRebuildSettings()
    end)
    continuationDrop:SetCallback("OnValueChanged", function(_, _, value)
        profile.continuation = value
        AutoRebuildSettings()
    end)
    importDraftCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.importCurrentDraft = value and true or false
    end)
    rememberWhisperCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.rememberWhisperTarget = value and true or false
        if value then profile.whisperTarget = state.whisperTarget or "" end
    end)
    spellcheckCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.spellcheckIntegration = value and true or false
        if value then WireSpellcheck(input, profile) end
    end)
    autoPreviewCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.autoPreview = value and true or false
    end)
    autoAdvanceCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.autoAdvance = value and true or false
    end)
    finalLockCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.lockFinalChunk = value and true or false
        UpdatePreview()
    end)
    automationCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.automationEnabled = value and true or false
        automationDelaySlider:SetDisabled(not value)
        automationAutoStartCheck:SetDisabled(not value)
        automationResumeManualCheck:SetDisabled(not value)
        automationResumeLockdownCheck:SetDisabled(not value)
        if not value then StopAutomation(T("Automation disabled."), false) end
        UpdatePreview()
    end)
    automationDelaySlider:SetCallback("OnValueChanged", function(_, _, value)
        profile.automationDelay = ClampAutomationDelay(value)
    end)
    automationAutoStartCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.automationAutoStart = value and true or false
    end)
    automationResumeManualCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.automationResumeAfterManual = value and true or false
    end)
    automationResumeLockdownCheck:SetCallback("OnValueChanged", function(_, _, value)
        profile.automationResumeAfterLockdown = value and true or false
    end)

    input:SetCallback("OnTextChanged", function(_, _, value)
        if state.automationRunning or state.automationPaused then StopAutomation(T("Automation stopped because the message changed.")) end
        state.inputText = value or ""
        if #state.chunks > 0 then
            state.previewDirty = true
            UpdatePreview()
        end
    end)

    importButton:SetCallback("OnClick", function() ImportCurrentChat(profile.autoPreview ~= false) end)
    splitButton:SetCallback("OnClick", function()
        if Rebuild() and profile.automationEnabled == true and profile.automationAutoStart == true then
            StartAutomation(true)
        end
    end)
    clearButton:SetCallback("OnClick", function()
        StopAutomation(nil, true)
        input:SetText("")
        state.inputText = ""
        state.chunks = {}
        state.index = 1
        state.lastSentIndex = 0
        state.finalChunkSent = false
        state.previewDirty = false
        state.chunksUsePerLineChannels = false
        -- Keep the whisper target, matching the previous long-message workflow.
        UpdatePreview(T("Composer cleared."))
        input:SetFocus()
    end)
    helpButton:SetCallback("OnClick", function() self:OpenHelp() end)
    settingsButton:SetCallback("OnClick", function() self:OpenSettings() end)

    prevButton:SetCallback("OnClick", function()
        if state.automationRunning or state.automationPaused then StopAutomation(T("Automation stopped for manual navigation.")) end
        if state.index > 1 then state.index = state.index - 1 end
        state.finalChunkSent = false
        UpdatePreview()
    end)
    nextButton:SetCallback("OnClick", function()
        if state.automationRunning or state.automationPaused then StopAutomation(T("Automation stopped for manual navigation.")) end
        if state.index < #state.chunks then state.index = state.index + 1 end
        state.finalChunkSent = false
        UpdatePreview()
    end)
    automationStartButton:SetCallback("OnClick", function()
        if #state.chunks == 0 or state.previewDirty then
            if not Rebuild() then return end
        end
        StartAutomation(true)
    end)
    automationStopButton:SetCallback("OnClick", function()
        StopAutomation(T("Automation stopped."))
    end)
    sendButton:SetCallback("OnClick", function()
        if #state.chunks == 0 or state.previewDirty then
            if not Rebuild() then return end
        end
        local chunk = state.chunks[state.index]
        local chatType, target = EffectiveRouting(chunk)
        if not chatType then
            UpdatePreview(T("Press Split / Refresh Preview to apply Per Line routing."))
            return
        end
        local outgoing = {
            text = StripSpellcheckMarkup(chunk.text or ""),
            channel = chatType,
            target = target,
        }
        local ok, reason = SendChunk(outgoing)
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

        local resumeAutomation = state.automationPaused and state.automationWaitingManual and profile.automationEnabled == true
        state.lastSentIndex = state.index
        state.automationPaused = false
        state.automationWaitingManual = false
        state.automationWaitingLockdown = false
        state.automationMessage = nil
        if state.index >= #state.chunks then
            state.finalChunkSent = true
            UpdatePreview(T("Final chunk sent."))
        elseif resumeAutomation then
            state.finalChunkSent = false
            state.index = state.index + 1
            UpdatePreview(T("Manual chunk sent."))
            if profile.automationResumeAfterManual ~= false then
                local expectedIndex = state.index
                local delay = ClampAutomationDelay(profile.automationDelay)
                ScheduleAfter(delay, function()
                    if self.sessionState == state and state.index == expectedIndex and not state.previewDirty then
                        StartAutomation(false)
                    end
                end)
            end
        elseif profile.autoAdvance ~= false then
            state.finalChunkSent = false
            state.index = state.index + 1
            UpdatePreview(T("Sent. Ready for the next chunk."))
        else
            state.finalChunkSent = false
            UpdatePreview(T("Chunk sent."))
        end
    end)

    WireSpellcheck(input, profile)
    UpdateTargetVisibility()

    if options.importCurrentChat and initialImport and state.inputText ~= "" and profile.autoPreview ~= false then
        Rebuild(T("Current chat draft imported."))
    elseif type(options.text) == "string" and options.text ~= "" and options.autoSplit ~= false and profile.autoPreview ~= false then
        Rebuild()
    elseif #state.chunks > 0 then
        UpdatePreview()
    else
        UpdatePreview()
    end
    input:SetFocus()
    return true
end

function Composer:HandleCommand(input)
    input = Trim(input)
    if input ~= "" then
        self:Open({ text = input, autoSplit = true })
    else
        self:Open({ importCurrentChat = true })
    end
end

function Composer:OnSettingsChanged()
    local profile = GetProfile()
    local ui = self.ui
    if not profile then return end
    if profile.enabled ~= true and self.window and self.window.frame and self.window.frame.Hide then
        self.window.frame:Hide()
    end
    if not ui then return end
    if ui.limitSlider then ui.limitSlider:SetValue(ClampLimit(profile.chunkLimit)) end
    if ui.counterCheck then ui.counterCheck:SetValue(profile.showCounter ~= false) end
    if ui.continuationDrop then ui.continuationDrop:SetValue(profile.continuation or "BOTH") end
    if ui.importDraftCheck then ui.importDraftCheck:SetValue(profile.importCurrentDraft ~= false) end
    if ui.rememberWhisperCheck then ui.rememberWhisperCheck:SetValue(profile.rememberWhisperTarget ~= false) end
    if ui.spellcheckCheck then ui.spellcheckCheck:SetValue(profile.spellcheckIntegration ~= false) end
    if ui.autoPreviewCheck then ui.autoPreviewCheck:SetValue(profile.autoPreview ~= false) end
    if ui.autoAdvanceCheck then ui.autoAdvanceCheck:SetValue(profile.autoAdvance ~= false) end
    if ui.finalLockCheck then ui.finalLockCheck:SetValue(profile.lockFinalChunk ~= false) end
    if ui.automationCheck then ui.automationCheck:SetValue(profile.automationEnabled == true) end
    if ui.automationDelaySlider then
        ui.automationDelaySlider:SetValue(ClampAutomationDelay(profile.automationDelay))
        ui.automationDelaySlider:SetDisabled(profile.automationEnabled ~= true)
    end
    if ui.automationAutoStartCheck then
        ui.automationAutoStartCheck:SetValue(profile.automationAutoStart == true)
        ui.automationAutoStartCheck:SetDisabled(profile.automationEnabled ~= true)
    end
    if ui.automationResumeManualCheck then
        ui.automationResumeManualCheck:SetValue(profile.automationResumeAfterManual ~= false)
        ui.automationResumeManualCheck:SetDisabled(profile.automationEnabled ~= true)
    end
    if ui.automationResumeLockdownCheck then
        ui.automationResumeLockdownCheck:SetValue(profile.automationResumeAfterLockdown == true)
        ui.automationResumeLockdownCheck:SetDisabled(profile.automationEnabled ~= true)
    end
    if profile.automationEnabled ~= true and type(self.StopAutomation) == "function" then
        self:StopAutomation(nil, true)
    end
    if self.sessionState and #self.sessionState.chunks == 0 and profile.defaultChannel then
        self.sessionState.channel = profile.defaultChannel
        if ui.channelDrop then ui.channelDrop:SetValue(profile.defaultChannel) end
    end
    if profile.spellcheckIntegration ~= false and self.inputWidget then WireSpellcheck(self.inputWidget, profile) end
    if self.sessionState and #self.sessionState.chunks > 0 and type(self.RebuildPreview) == "function" then
        self:RebuildPreview(T("Preview rebuilt with the new settings."))
    elseif type(self.UpdateComposerUI) == "function" then
        self:UpdateComposerUI()
    end
end

function Composer:OnEnable()
    if type(ns.IsFeatureAvailable) == "function" and not ns.IsFeatureAvailable("composer") then
        ns.OpenChatComposer = nil
        return
    end

    self:RegisterChatCommand("chatcompose", "HandleCommand")
    self:RegisterChatCommand("chatcomposer", "HandleCommand")
    self:RegisterChatCommand("chatlong", "HandleCommand")

    for _, eventName in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do
        pcall(self.RegisterEvent, self, eventName, "RefreshRuntimeState")
    end
    ns.OpenChatComposer = function(options)
        if type(ns.IsFeatureAvailable) == "function" and not ns.IsFeatureAvailable("composer") then
            return false
        end
        if not IsComposerEnabled() then
            return false
        end
        local module = Chatify:GetModule("Composer", true)
        if module and type(module.Open) == "function" then
            module:Open(options)
            return true
        end
        return false
    end

    ns.NotifyComposerSettingsChanged = function()
        local module = Chatify:GetModule("Composer", true)
        if module and type(module.OnSettingsChanged) == "function" then
            module:OnSettingsChanged()
        end
    end

    if type(ns.NotifyQuickChatSettingsChanged) == "function" then
        ns.NotifyQuickChatSettingsChanged()
    end
end

function Composer:OnDisable()
    if type(self.StopAutomation) == "function" then self:StopAutomation(nil, true) end
    ns.OpenChatComposer = nil
    ns.NotifyComposerSettingsChanged = nil
    if self.window then
        if AceGUI and type(AceGUI.Release) == "function" then AceGUI:Release(self.window) end
        self.window = nil
    end
    if self.helpWindow then
        if AceGUI and type(AceGUI.Release) == "function" then AceGUI:Release(self.helpWindow) end
        self.helpWindow = nil
    end
    self.ui = nil
    self.inputWidget = nil
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
