local addonName, ns = ...
local Chatify = ns.Chatify
local CopyModule = Chatify:NewModule("Copy", "AceHook-3.0")
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

-- =========================================================
-- 1. КЕШУВАННЯ ДЛЯ КОПІЮВАННЯ
-- =========================================================
local msgCache = {}
local msgIndex = 0
local fullChatCache = {}
local fullChatIndex = 0
local CACHE_SIZE = 500
local COPY_WINDOW_MAX_LINES = 250
local COPY_WINDOW_MAX_CHARS = 60000
local CHAT_CAPTURE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_ACHIEVEMENT",
}
local captureFrame
local lastEntrySignature
local lastEntryTime = 0

local PLAYER_COLORS = {
    "ff7ad7ff", "ffffd36b", "ff9dff7a", "ffff9a9a", "ffc79cff",
    "ff7affb2", "ffffb86b", "ff9ab7ff", "ffff7adf", "ffb7ffea",
}

local function SafeChatText(value)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(value)
    end

    if type(ns.IsSecretValue) == "function" and ns.IsSecretValue(value) then
        return nil
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(value) then
        return nil
    end

    if type(value) == "string" then
        return value
    end

    return nil
end

local function StripChatMarkup(text)
    if type(text) ~= "string" then
        return nil
    end

    local ok, clean = pcall(function()
        local value = text
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|r", "")
        value = value:gsub("|H.-|h(.-)|h", "%1")
        value = value:gsub("|T.-|t", "")
        value = value:gsub("||", "|")
        return value
    end)

    if ok and type(clean) == "string" then
        return clean
    end

    return text
end

local function NormalizeName(author)
    if type(author) ~= "string" or author == "" then
        return nil
    end

    local ok, name = pcall(function()
        local value = author
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|r", "")
        value = value:gsub("|H.-|h%[?(.-)%]?|h", "%1")
        value = value:gsub("^%[", ""):gsub("%]$", "")
        value = value:gsub("%-.+$", "")
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        return value
    end)

    if ok and type(name) == "string" and name ~= "" then
        return name
    end

    return nil
end

local function ExtractAuthorFromText(text)
    if type(text) ~= "string" then
        return nil
    end

    local _, linkName = text:match("|Hplayer:([^|:]+)[^|]*|h%[?([^%]|]+)%]?|h")
    if linkName then
        return NormalizeName(linkName)
    end

    local bracketName = text:match("^%s*%[([^%]]+)%]%s*:")
    if bracketName then
        return NormalizeName(bracketName)
    end

    local plainName = text:match("^%s*([^:%[%]]+)%s*:")
    if plainName and #plainName <= 32 then
        return NormalizeName(plainName)
    end

    return nil
end

local function GetNameColor(name)
    name = NormalizeName(name)
    if not name then
        return "ffffffff"
    end

    if type(UnitClass) == "function" then
        local ok, classFile = pcall(function()
            return select(2, UnitClass(name))
        end)
        if ok and classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
            local c = RAID_CLASS_COLORS[classFile]
            return string.format("ff%02x%02x%02x",
                math.floor(((c.r or 1) * 255) + 0.5),
                math.floor(((c.g or 1) * 255) + 0.5),
                math.floor(((c.b or 1) * 255) + 0.5))
        end
    end

    local hash = 0
    for i = 1, #name do
        hash = (hash + name:byte(i) * i) % #PLAYER_COLORS
    end
    return PLAYER_COLORS[hash + 1]
end

local function ColorName(name)
    name = NormalizeName(name)
    if not name then
        return ""
    end
    return "|c" .. GetNameColor(name) .. name .. "|r"
end

local function BuildEntry(text, author, timestamp)
    local cleanText = StripChatMarkup(text)
    if type(cleanText) ~= "string" or cleanText == "" then
        return nil
    end

    local cleanAuthor = NormalizeName(author) or ExtractAuthorFromText(text) or ExtractAuthorFromText(cleanText)
    local timeText = date("%H:%M:%S", tonumber(timestamp) or time())

    return {
        text = cleanText,
        raw = text,
        author = cleanAuthor,
        time = timeText,
    }
end

local function BuildPlainLine(entry)
    if type(entry) == "string" then
        return StripChatMarkup(entry) or entry
    end
    if type(entry) ~= "table" then
        return nil
    end

    if entry.author and entry.author ~= "" then
        return string.format("[%s] %s: %s", entry.time or "--:--:--", entry.author, entry.text or "")
    end

    return string.format("[%s] %s", entry.time or "--:--:--", entry.text or "")
end

local function BuildColoredLine(entry)
    if type(entry) == "string" then
        return StripChatMarkup(entry) or entry
    end
    if type(entry) ~= "table" then
        return ""
    end

    local timeText = string.format("|cff888888[%s]|r", entry.time or "--:--:--")
    if entry.author and entry.author ~= "" then
        return string.format("%s %s: %s", timeText, ColorName(entry.author), entry.text or "")
    end

    return string.format("%s %s", timeText, entry.text or "")
end

local function AddFullChatEntry(entry)
    if type(entry) ~= "table" then
        return
    end

    fullChatIndex = fullChatIndex + 1
    fullChatCache[fullChatIndex] = entry

    local pruneBefore = fullChatIndex - CACHE_SIZE
    if pruneBefore > 0 then
        fullChatCache[pruneBefore] = nil
    end
end

function ns.SaveToCache(text, author, timestamp)
    local safeText = SafeChatText(text)
    if type(safeText) ~= "string" or safeText == "" then
        return nil
    end

    local safeAuthor = SafeChatText(author)
    local entry = BuildEntry(safeText, safeAuthor, timestamp)
    if not entry then
        return nil
    end

    local now = time()
    local signature = (entry.author or "") .. "\31" .. (entry.text or "")
    if signature == lastEntrySignature and (now - lastEntryTime) <= 1 then
        return msgIndex > 0 and msgIndex or nil
    end
    lastEntrySignature = signature
    lastEntryTime = now

    msgIndex = msgIndex + 1
    msgCache[msgIndex] = entry
    AddFullChatEntry(entry)

    if msgIndex > CACHE_SIZE + 50 then
        for i = msgIndex - CACHE_SIZE - 50, msgIndex - CACHE_SIZE do
            msgCache[i] = nil
        end
    end

    return msgIndex
end

-- =========================================================
-- 2. ВІКНО КОПІЮВАННЯ
-- =========================================================
local copyFrame
local copyEditBox
local copyTitle
local copyScroll
local copyContent
local copyHint
local copyButton
local copyTextValue = ""
local copySettingText = false

local function StartCopyFrameMoving(frame)
    if not frame or not frame.StartMoving then
        return
    end

    frame:StartMoving()
end

local function StopCopyFrameMoving(frame)
    if not frame or not frame.StopMovingOrSizing then
        return
    end

    frame:StopMovingOrSizing()
end

local function ScrollCopyWindow(delta)
    if not copyScroll or not copyScroll.GetVerticalScroll or not copyScroll.SetVerticalScroll then
        return
    end

    local step = 28
    local current = copyScroll:GetVerticalScroll() or 0
    local maxScroll = 0
    local scrollbar = _G["ChatifyCopyPreviewScrollScrollBar"]
    if scrollbar and scrollbar.GetMinMaxValues then
        local _, maxValue = scrollbar:GetMinMaxValues()
        maxScroll = tonumber(maxValue) or 0
    end

    local nextValue = current - ((tonumber(delta) or 0) * step)
    if nextValue < 0 then
        nextValue = 0
    elseif maxScroll > 0 and nextValue > maxScroll then
        nextValue = maxScroll
    end

    copyScroll:SetVerticalScroll(nextValue)
    if scrollbar and scrollbar.SetValue then
        scrollbar:SetValue(nextValue)
    end
end

local function CreateMoveHandle(parent, name, anchorFunc)
    local handle = CreateFrame("Frame", name, parent)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    anchorFunc(handle)
    handle:SetScript("OnDragStart", function()
        StartCopyFrameMoving(parent)
    end)
    handle:SetScript("OnDragStop", function()
        StopCopyFrameMoving(parent)
    end)
    handle:SetScript("OnMouseUp", function()
        StopCopyFrameMoving(parent)
    end)
    return handle
end

local function CreateCopyWindow()
    if copyFrame then return end

    local f = CreateFrame("Frame", "ChatifyCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.98)
        f:SetBackdropBorderColor(0.95, 0.72, 0.18, 1)
    end
    f:SetSize(660, 486)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()

    local titleBar = CreateMoveHandle(f, "ChatifyCopyFrameMoveTitle", function(handle)
        handle:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
        handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -6)
        handle:SetHeight(32)
    end)

    CreateMoveHandle(f, "ChatifyCopyFrameMoveLeft", function(handle)
        handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        handle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        handle:SetWidth(14)
    end)
    CreateMoveHandle(f, "ChatifyCopyFrameMoveRight", function(handle)
        handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        handle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        handle:SetWidth(14)
    end)
    CreateMoveHandle(f, "ChatifyCopyFrameMoveBottom", function(handle)
        handle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        handle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        handle:SetHeight(14)
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -13)
    title:SetPoint("TOPRIGHT", -42, -13)
    title:SetJustifyH("LEFT")
    title:SetText(L("Chatify Copy"))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local previewBg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    previewBg:SetPoint("TOPLEFT", 16, -46)
    previewBg:SetPoint("BOTTOMRIGHT", -34, 58)
    previewBg:EnableMouse(false)
    if previewBg.SetBackdrop then
        previewBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        previewBg:SetBackdropColor(0.02, 0.02, 0.025, 0.92)
        previewBg:SetBackdropBorderColor(0.42, 0.32, 0.12, 0.95)
    end

    local scrollArea = CreateFrame("ScrollFrame", "ChatifyCopyPreviewScroll", f, "UIPanelScrollFrameTemplate")
    scrollArea:SetPoint("TOPLEFT", previewBg, "TOPLEFT", 10, -10)
    scrollArea:SetPoint("BOTTOMRIGHT", previewBg, "BOTTOMRIGHT", -28, 10)
    scrollArea:EnableMouse(true)
    scrollArea:EnableMouseWheel(true)
    scrollArea:SetScript("OnMouseWheel", function(_, delta)
        ScrollCopyWindow(delta)
    end)

    -- Prat-style copy surface: one plain scrollable EditBox.
    -- The EditBox owns mouse selection; only the title/borders can move the popup.
    local eb = CreateFrame("EditBox", "ChatifyCopySelectableEditBox", scrollArea)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(COPY_WINDOW_MAX_CHARS + 1000)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(0.94, 0.94, 0.94, 1)
    if eb.SetHighlightColor then
        eb:SetHighlightColor(0.95, 0.72, 0.18, 0.35)
    end
    if eb.SetTextInsets then
        eb:SetTextInsets(4, 4, 4, 4)
    end
    if eb.SetSpacing then
        eb:SetSpacing(2)
    end
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("TOP")
    eb:SetWidth(580)
    eb:SetHeight(1)
    eb:EnableMouse(true)
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(_, delta)
        ScrollCopyWindow(delta)
    end)
    eb:SetScript("OnMouseDown", function(self)
        self:SetFocus()
    end)
    eb:SetScript("OnEditFocusGained", function()
        if copyHint then
            copyHint:SetText(L("Select the needed text, then press Ctrl+C."))
        end
    end)
    eb:SetScript("OnEditFocusLost", function()
        if copyHint then
            copyHint:SetText(L("Click Select All for the full export, or select part of the text manually."))
        end
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    eb:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then
            ScrollingEdit_OnCursorChanged(self, x, y, w, h)
        end
    end)
    eb:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then
            ScrollingEdit_OnUpdate(self, elapsed, scrollArea)
        end
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not copySettingText then
            local cursor = self:GetCursorPosition() or 0
            copySettingText = true
            self:SetText(copyTextValue or "")
            self:SetCursorPosition(math.min(cursor, #(copyTextValue or "")))
            copySettingText = false
            return
        end

        if scrollArea.UpdateScrollChildRect then
            scrollArea:UpdateScrollChildRect()
        end
    end)
    scrollArea:SetScrollChild(eb)

    local content = eb

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(116, 24)
    btn:SetPoint("BOTTOMRIGHT", -18, 18)
    btn:SetText(L("Select All"))
    btn:SetScript("OnClick", function()
        if copyEditBox then
            copyEditBox:SetFocus()
            copyEditBox:SetCursorPosition(0)
            copyEditBox:HighlightText(0, -1)
        end
        if copyHint then
            copyHint:SetText(L("Selected text is ready. Press Ctrl+C to copy."))
        end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 18, 22)
    hint:SetPoint("RIGHT", btn, "LEFT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("Click Select All for the full export, or select part of the text manually."))

    titleBar:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
    close:SetFrameLevel((f:GetFrameLevel() or 1) + 3)

    copyFrame = f
    copyEditBox = eb
    copyTitle = title
    copyScroll = scrollArea
    copyContent = content
    copyHint = hint
    copyButton = btn
end

local BuildTextFromEntries

local function SetCopyEditText(text)
    copyTextValue = text or ""
    if copyContent and type(copyContent.SetText) == "function" then
        copySettingText = true
        copyContent:SetText(copyTextValue)
        copyContent:SetCursorPosition(0)
        copyContent:HighlightText(0, 0)
        copyContent:ClearFocus()
        copySettingText = false
    end
end

local function ClearCopyPreview()
    SetCopyEditText("")
end

local function RenderCopyPreview(entries)
    if not copyContent then
        return
    end

    local width = 545
    if copyScroll and copyScroll.GetWidth then
        width = math.max(260, math.floor((copyScroll:GetWidth() or 575) - 12))
    end

    local text = BuildTextFromEntries(entries, COPY_WINDOW_MAX_CHARS)
    copyContent:SetWidth(width)
    SetCopyEditText(text)

    local lineCount = 1
    for _ in string.gmatch(text or "", "\n") do
        lineCount = lineCount + 1
    end
    copyContent:SetHeight(math.max(1, lineCount * 16 + 24))
end

BuildTextFromEntries = function(entries, maxChars)
    local lines = {}
    local chars = 0
    maxChars = tonumber(maxChars) or COPY_WINDOW_MAX_CHARS

    for i = 1, #entries do
        local line = BuildPlainLine(entries[i])
        if type(line) == "string" and line ~= "" then
            chars = chars + #line + 1
            if chars > maxChars then
                lines[#lines + 1] = "..."
                break
            end
            lines[#lines + 1] = line
        end
    end

    return table.concat(lines, "\n")
end

local function ShowCopyWindow(entries, title)
    if not copyFrame then CreateCopyWindow() end

    if type(entries) == "string" then
        entries = { BuildEntry(entries) or entries }
    elseif type(entries) ~= "table" then
        entries = {}
    end

    copyFrame:Show()
    if copyTitle then
        copyTitle:SetText(title or L("Chatify Copy"))
    end
    if copyHint then
        copyHint:SetText(L("Click Select All for the full export, or select part of the text manually."))
    end

    RenderCopyPreview(entries)

    if copyEditBox then
        copyEditBox:ClearFocus()
        copyEditBox:HighlightText(0, 0)
    end
    if copyScroll and copyScroll.SetVerticalScroll then
        copyScroll:SetVerticalScroll(0)
    end
end

local function BuildCachedChatEntries(maxLines, maxChars)
    maxLines = tonumber(maxLines) or COPY_WINDOW_MAX_LINES
    maxChars = tonumber(maxChars) or COPY_WINDOW_MAX_CHARS

    local entries = {}
    local chars = 0
    local startIndex = math.max(1, fullChatIndex - maxLines + 1)

    for i = startIndex, fullChatIndex do
        local entry = fullChatCache[i]
        local line = BuildPlainLine(entry)
        if type(line) == "string" and line ~= "" then
            chars = chars + #line + 1
            if chars > maxChars then
                entries[#entries + 1] = BuildEntry("...")
                break
            end
            entries[#entries + 1] = entry
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function ReadVisibleChatLines(chatFrame)
    if not chatFrame or type(chatFrame.GetRegions) ~= "function" then
        return nil
    end

    local entries = {}
    local regions = { chatFrame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" and type(region.GetText) == "function" then
            local ok, text = pcall(region.GetText, region)
            if ok then
                local entry = BuildEntry(text)
                if entry then
                    entries[#entries + 1] = entry
                end
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end


local function AddHistoryEntry(entries, rawText)
    local entry = BuildEntry(rawText)
    if entry then
        entries[#entries + 1] = entry
        return true
    end
    return false
end

local function ReadMessageHistory(chatFrame, maxLines)
    if not chatFrame then
        return nil
    end

    local entries = {}
    maxLines = tonumber(maxLines) or COPY_WINDOW_MAX_LINES

    local count = 0
    if type(chatFrame.GetNumMessages) == "function" then
        local okCount, value = pcall(chatFrame.GetNumMessages, chatFrame)
        if okCount and type(value) == "number" and value > 0 then
            count = value
        end
    end

    if count > 0 and chatFrame.historyBuffer and type(chatFrame.historyBuffer.GetEntryAtIndex) == "function" then
        local first = math.max(1, count - maxLines + 1)
        for i = first, count do
            local ok, historyEntry = pcall(chatFrame.historyBuffer.GetEntryAtIndex, chatFrame.historyBuffer, i)
            local msg = ok and historyEntry and historyEntry.message or nil
            AddHistoryEntry(entries, msg)
        end
    end

    if #entries == 0 and count > 0 and type(chatFrame.GetMessageInfo) == "function" then
        local first = math.max(1, count - maxLines + 1)
        for i = first, count do
            local ok, msg = pcall(chatFrame.GetMessageInfo, chatFrame, i)
            if ok then
                AddHistoryEntry(entries, msg)
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

function ns.OpenChatCopyWindow(chatFrame, maxLines)
    chatFrame = chatFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME

    -- Match Prat's behavior: copy the selected chat frame first.
    -- The global event cache is only a fallback for clients/frames that do not expose history.
    local entries = ReadMessageHistory(chatFrame, maxLines)
    if not entries then
        entries = ReadVisibleChatLines(chatFrame)
    end

    if not entries then
        entries = BuildCachedChatEntries(maxLines, COPY_WINDOW_MAX_CHARS)
    end

    if not entries then
        entries = { BuildEntry(L("Chat buffer is empty. Send or receive a new message, then open this window again.")) }
    end

    ShowCopyWindow(entries, L("Chatify Copy — selected chat"))
end

-- =========================================================
-- 3. ПОПАП ДЛЯ URL
-- =========================================================
StaticPopupDialogs["CHATIFY_COPY_URL"] = {
    text = L("Press Ctrl+C to copy the link:"),
    button1 = L("OK"),
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then
            eb:SetText(type(data) == "string" and data or tostring(data or ""))
            eb:SetFocus()
            eb:HighlightText()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =========================================================
-- 4. ПЕРЕХОПЛЕННЯ КЛІКІВ
-- =========================================================
local function OnCaptureEvent(_, event, msg, author, ...)
    if type(ns.ShouldBypassWhisperMutation) == "function" and ns.ShouldBypassWhisperMutation(event) then
        return
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
        return
    end

    local safeMsg = SafeChatText(msg)
    if type(safeMsg) ~= "string" or safeMsg == "" then
        return
    end

    local safeAuthor = SafeChatText(author)
    ns.SaveToCache(safeMsg, safeAuthor, time())
end

local function EnsureChatCapture()
    if captureFrame then
        return
    end

    captureFrame = CreateFrame("Frame")
    for _, eventName in ipairs(CHAT_CAPTURE_EVENTS) do
        if not (type(ns.ShouldBypassWhisperMutation) == "function" and ns.ShouldBypassWhisperMutation(eventName)) then
            pcall(captureFrame.RegisterEvent, captureFrame, eventName)
        end
    end
    captureFrame:SetScript("OnEvent", OnCaptureEvent)
end

function CopyModule:OnEnable()
    self:RawHook("SetItemRef", true)
    EnsureChatCapture()
end

function CopyModule:SetItemRef(link, text, button, chatFrame)
    if type(ns.IsSecretValue) == "function" and ns.IsSecretValue(link) then
        return self.hooks.SetItemRef(link, text, button, chatFrame)
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(link) then
        return self.hooks.SetItemRef(link, text, button, chatFrame)
    end

    if type(link) ~= "string" or link == "" then
        return self.hooks.SetItemRef(link, text, button, chatFrame)
    end

    if link:sub(1, 9) == "chatcopy:" then
        local id = tonumber(link:sub(10))
        local payload = (ns.GetCachedChatLine and ns.GetCachedChatLine(id)) or msgCache[id]
        if id and payload then
            ShowCopyWindow({ payload }, L("Chatify Copy — selected line"))
        end
        return
    end

    if link:sub(1, 4) == "url:" then
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, link:sub(5))
        return
    end

    self.hooks.SetItemRef(link, text, button, chatFrame)
end
