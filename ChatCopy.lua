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

local function IsProtectedChatValue(value)
    if type(ns.IsProtectedChatValue) == "function" then
        local ok, protected = pcall(ns.IsProtectedChatValue, value)
        if ok then
            return protected and true or false
        end
        return true
    end

    if type(ns.IsSecretValue) == "function" then
        local ok, secret = pcall(ns.IsSecretValue, value)
        if ok and secret then
            return true
        end
    end

    if type(ns.CanAccessChatValue) == "function" then
        local ok, accessible = pcall(ns.CanAccessChatValue, value)
        if ok and not accessible then
            return true
        elseif not ok then
            return true
        end
    end

    return false
end

local function SafeChatText(value)
    if IsProtectedChatValue(value) then
        return nil
    end

    if type(ns.TryMakeSafeText) == "function" then
        local ok, safe = pcall(ns.TryMakeSafeText, value)
        if ok and type(safe) == "string" then
            return safe
        elseif not ok then
            return nil
        end
    end

    if type(value) == "number" then
        return tostring(value)
    end

    if type(value) == "string" then
        return value
    end

    return nil
end

local function IsNonEmptyString(value)
    if type(value) ~= "string" then
        return false
    end

    local ok, length = pcall(string.len, value)
    return ok and length > 0
end

local function GetMessagePayload(value)
    if type(value) ~= "table" then
        return value
    end

    return value.message or value.text or value[1]
end

local function GetMessageAuthor(value)
    if type(value) ~= "table" then
        return nil
    end

    return value.author or value.sender or value.playerName or value[2]
end

local function StripChatMarkup(text)
    local safe = SafeChatText(text)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, clean = pcall(function()
        local value = safe
        -- Prat-style safety: replace protected/K hyperlinks with a visible marker,
        -- then strip normal color/texture/hyperlink markup without touching secret payloads.
        value = value:gsub("|K.-|k", "<protected>")
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|r", "")
        value = value:gsub("|H.-|h(.-)|h", "%1")
        value = value:gsub("|T.-|t", "")
        value = value:gsub("||", "|")
        return value
    end)

    if ok and not IsProtectedChatValue(clean) and IsNonEmptyString(clean) then
        return clean
    end

    return nil
end

local function NormalizeName(author)
    local safe = SafeChatText(author)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, name = pcall(function()
        local value = safe
        value = value:gsub("|K.-|k", "")
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|r", "")
        value = value:gsub("|H.-|h%[?(.-)%]?|h", "%1")
        value = value:gsub("^%[", ""):gsub("%]$", "")
        value = value:gsub("%-.+$", "")
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        return value
    end)

    if ok and not IsProtectedChatValue(name) and IsNonEmptyString(name) then
        return name
    end

    return nil
end

local function ExtractAuthorFromText(text)
    local safe = SafeChatText(text)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, author = pcall(function()
        local _, linkName = safe:match("|Hplayer:([^|:]+)[^|]*|h%[?([^%]|]+)%]?|h")
        if linkName then
            return NormalizeName(linkName)
        end

        local bracketName = safe:match("^%s*%[([^%]]+)%]%s*:")
        if bracketName then
            return NormalizeName(bracketName)
        end

        local plainName = safe:match("^%s*([^:%[%]]+)%s*:")
        if plainName and #plainName <= 32 then
            return NormalizeName(plainName)
        end

        return nil
    end)

    if ok and IsNonEmptyString(author) then
        return author
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

local function BuildProtectedEntry(label, timestamp)
    local fallback = L("Protected chat line omitted.")
    local safeLabel = StripChatMarkup(label) or fallback
    return {
        text = safeLabel,
        raw = safeLabel,
        author = nil,
        time = date("%H:%M:%S", tonumber(timestamp) or time()),
        protected = true,
    }
end

local function BuildEntry(text, author, timestamp)
    local rawPayload = GetMessagePayload(text)
    local rawAuthor = author or GetMessageAuthor(text)
    local cleanText = StripChatMarkup(rawPayload)
    if not IsNonEmptyString(cleanText) then
        return nil
    end

    local cleanAuthor = NormalizeName(rawAuthor) or ExtractAuthorFromText(rawPayload) or ExtractAuthorFromText(cleanText)
    local timeText = date("%H:%M:%S", tonumber(timestamp) or time())

    return {
        text = cleanText,
        raw = cleanText,
        author = cleanAuthor,
        time = timeText,
    }
end

local function BuildPlainLine(entry)
    if type(entry) == "string" then
        return StripChatMarkup(entry)
    end
    if type(entry) ~= "table" then
        return nil
    end

    local text = StripChatMarkup(entry.text)
    if not IsNonEmptyString(text) then
        return nil
    end

    local author = NormalizeName(entry.author)
    if IsNonEmptyString(author) then
        return string.format("[%s] %s: %s", entry.time or "--:--:--", author, text)
    end

    return string.format("[%s] %s", entry.time or "--:--:--", text)
end

local function BuildColoredLine(entry)
    if type(entry) == "string" then
        return StripChatMarkup(entry) or ""
    end
    if type(entry) ~= "table" then
        return ""
    end

    local text = StripChatMarkup(entry.text)
    if not IsNonEmptyString(text) then
        return ""
    end

    local timeText = string.format("|cff888888[%s]|r", entry.time or "--:--:--")
    local author = NormalizeName(entry.author)
    if IsNonEmptyString(author) then
        return string.format("%s %s: %s", timeText, ColorName(author), text)
    end

    return string.format("%s %s", timeText, text)
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
    if not IsNonEmptyString(safeText) then
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
local nativeCopySessions = setmetatable({}, { __mode = "k" })
local nativeCopySessionId = 0

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

    if type(entries) ~= "table" then
        return L("Chat buffer is empty. Send or receive a new message, then open this window again.")
    end

    for i = 1, #entries do
        local line = BuildPlainLine(entries[i])
        if IsNonEmptyString(line) then
            chars = chars + #line + 1
            if chars > maxChars then
                lines[#lines + 1] = "..."
                break
            end
            lines[#lines + 1] = line
        end
    end

    if #lines == 0 then
        lines[#lines + 1] = L("No readable chat lines were available for the copy window.")
        if type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
            lines[#lines + 1] = L("Use Right Click or Shift+Left Click on the copy button for Blizzard native selection.")
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
        if IsNonEmptyString(line) then
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

local function ReadVisibleLineMessages(chatFrame)
    if not chatFrame or type(chatFrame.visibleLines) ~= "table" then
        return nil
    end

    local entries = {}
    for i = 1, #chatFrame.visibleLines do
        local line = chatFrame.visibleLines[i]
        local text

        if line and line.messageInfo then
            text = line.messageInfo.message
        end

        if not text and line and type(line.GetText) == "function" then
            local ok, value = pcall(line.GetText, line)
            if ok then
                text = value
            end
        end

        local entry = BuildEntry(text)
        if entry then
            entries[#entries + 1] = entry
        elseif IsProtectedChatValue(text) then
            entries[#entries + 1] = BuildProtectedEntry()
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function ReadVisibleChatLines(chatFrame)
    local visibleLineEntries = ReadVisibleLineMessages(chatFrame)
    if visibleLineEntries then
        return visibleLineEntries
    end

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
                elseif IsProtectedChatValue(text) then
                    entries[#entries + 1] = BuildProtectedEntry()
                end
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function AddHistoryEntry(entries, rawText, author, timestamp)
    local payload = GetMessagePayload(rawText)
    local payloadAuthor = author or GetMessageAuthor(rawText)
    local entry = BuildEntry(payload, payloadAuthor, timestamp)
    if entry then
        entries[#entries + 1] = entry
        return true
    end

    if IsProtectedChatValue(payload) then
        entries[#entries + 1] = BuildProtectedEntry(nil, timestamp)
        return true
    end

    return false
end

local function HasReadableEntries(entries)
    if type(entries) ~= "table" or #entries == 0 then
        return false
    end

    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and not entry.protected and IsNonEmptyString(entry.text) then
            return true
        elseif type(entry) == "string" and IsNonEmptyString(entry) then
            return true
        end
    end

    return false
end

local function HasAnyCopyEntries(entries)
    return type(entries) == "table" and #entries > 0
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

    -- Prat's copy window uses GetMessageInfo first. Keep that path, but
    -- collect only the first return value and never treat normal Retail text
    -- as protected just because canaccessvalue() exists.
    if count > 0 and type(chatFrame.GetMessageInfo) == "function" then
        local first = math.max(1, count - maxLines + 1)
        for i = first, count do
            local ok, msg, r, g, b, messageId, extraData = pcall(chatFrame.GetMessageInfo, chatFrame, i)
            if ok then
                AddHistoryEntry(entries, msg, nil, nil)
            end
        end
    end

    if not HasReadableEntries(entries) and count > 0 and chatFrame.historyBuffer and type(chatFrame.historyBuffer.GetEntryAtIndex) == "function" then
        local fallbackEntries = {}
        local first = math.max(1, count - maxLines + 1)
        for i = first, count do
            local ok, historyEntry = pcall(chatFrame.historyBuffer.GetEntryAtIndex, chatFrame.historyBuffer, i)
            if ok then
                AddHistoryEntry(fallbackEntries, historyEntry)
            end
        end
        if HasReadableEntries(fallbackEntries) or #entries == 0 then
            entries = fallbackEntries
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function GetFrameMouseEnabled(frame)
    if not frame or type(frame.IsMouseEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsMouseEnabled, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function GetFrameTextCopyable(frame)
    if not frame or type(frame.IsTextCopyable) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsTextCopyable, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function GetFrameMouseClickEnabled(frame)
    if not frame or type(frame.IsMouseClickEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsMouseClickEnabled, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function GetFrameMouseMotionEnabled(frame)
    if not frame or type(frame.IsMouseMotionEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsMouseMotionEnabled, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function IsNativeCopyFrame(frame)
    return type(frame) == "table" and type(frame.SetTextCopyable) == "function"
end

local function AddNativeCandidate(list, seen, frame)
    if not IsNativeCopyFrame(frame) or seen[frame] then
        return
    end

    seen[frame] = true
    list[#list + 1] = frame
end

local function AddNamedChatFrameCandidates(list, seen)
    local total = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    if total < 1 then
        total = 10
    elseif total > 20 then
        total = 20
    end

    for i = 1, total do
        local frame = _G["ChatFrame" .. i]
        if frame and (type(frame.IsShown) ~= "function" or frame:IsShown()) then
            AddNativeCandidate(list, seen, frame)
        end
    end
end

local function GetDockSelectedFrame()
    if type(_G.FCFDock_GetSelectedWindow) == "function" and _G.GeneralDockManager then
        local ok, frame = pcall(_G.FCFDock_GetSelectedWindow, _G.GeneralDockManager)
        if ok and frame then
            return frame
        end
    end

    if _G.GeneralDockManager then
        return _G.GeneralDockManager.selected or _G.GeneralDockManager.primary
    end

    return nil
end

local function ResolveNativeCopyFrames(preferred)
    local list = {}
    local seen = {}

    AddNativeCandidate(list, seen, preferred)

    if type(ns.GetSelectedChatFrame) == "function" then
        local ok, frame = pcall(ns.GetSelectedChatFrame)
        if ok then
            AddNativeCandidate(list, seen, frame)
        end
    end

    AddNativeCandidate(list, seen, SELECTED_CHAT_FRAME)
    AddNativeCandidate(list, seen, GetDockSelectedFrame())
    AddNativeCandidate(list, seen, DEFAULT_CHAT_FRAME)
    AddNativeCandidate(list, seen, _G.ChatFrame1)
    AddNamedChatFrameCandidates(list, seen)

    return list
end

local function RestoreNativeFrame(frame, session)
    if not frame or not session then
        return
    end

    if type(frame.SetOnTextCopiedCallback) == "function" then
        pcall(frame.SetOnTextCopiedCallback, frame, nil)
    end

    if session.originalCopyable ~= true and type(frame.SetTextCopyable) == "function" then
        pcall(frame.SetTextCopyable, frame, false)
    end

    if session.originalClickEnabled == false and type(frame.SetMouseClickEnabled) == "function" then
        pcall(frame.SetMouseClickEnabled, frame, false)
    elseif session.originalClickEnabled == true and type(frame.SetMouseClickEnabled) == "function" then
        pcall(frame.SetMouseClickEnabled, frame, true)
    end

    if session.originalMotionEnabled == false and type(frame.SetMouseMotionEnabled) == "function" then
        pcall(frame.SetMouseMotionEnabled, frame, false)
    elseif session.originalMotionEnabled == true and type(frame.SetMouseMotionEnabled) == "function" then
        pcall(frame.SetMouseMotionEnabled, frame, true)
    end

    if session.originalMouseEnabled == false and type(frame.EnableMouse) == "function" then
        pcall(frame.EnableMouse, frame, false)
    elseif session.originalMouseEnabled == true and type(frame.EnableMouse) == "function" then
        pcall(frame.EnableMouse, frame, true)
    end
end

local function RestoreNativeCopySession(sessionId)
    for frame, session in pairs(nativeCopySessions) do
        if session and session.id == sessionId then
            nativeCopySessions[frame] = nil
            RestoreNativeFrame(frame, session)
        end
    end
end

local function RestoreNativeChatCopyMode(frame, sessionId)
    local session = frame and nativeCopySessions[frame]
    if not session or session.id ~= sessionId then
        return
    end

    -- One successful native copy should close the whole Chatify native-copy
    -- session. This matches the Prat idea, but avoids leaving secondary chat
    -- frames copyable when we enabled multiple visible candidates.
    RestoreNativeCopySession(sessionId)
end

local function EnableNativeCopyOnFrame(frame, sessionId)
    if not IsNativeCopyFrame(frame) then
        return false
    end

    nativeCopySessions[frame] = {
        id = sessionId,
        originalMouseEnabled = GetFrameMouseEnabled(frame),
        originalCopyable = GetFrameTextCopyable(frame),
        originalClickEnabled = GetFrameMouseClickEnabled(frame),
        originalMotionEnabled = GetFrameMouseMotionEnabled(frame),
    }

    local okCopyable = pcall(frame.SetTextCopyable, frame, true)
    if not okCopyable then
        nativeCopySessions[frame] = nil
        return false
    end

    -- Prat only calls EnableMouse(true). Retail clients may split mouse click
    -- and motion handling, so enable those when the methods exist. We restore
    -- the original state after copy/timeout only for frames changed by Chatify.
    if type(frame.EnableMouse) == "function" then
        pcall(frame.EnableMouse, frame, true)
    end
    if type(frame.SetMouseClickEnabled) == "function" then
        pcall(frame.SetMouseClickEnabled, frame, true)
    end
    if type(frame.SetMouseMotionEnabled) == "function" then
        pcall(frame.SetMouseMotionEnabled, frame, true)
    end

    if type(frame.SetOnTextCopiedCallback) == "function" then
        pcall(frame.SetOnTextCopiedCallback, frame, function(this)
            RestoreNativeChatCopyMode(this or frame, sessionId)
        end)
    end

    return true
end

local function NotifyNativeCopyEnabled(enabledCount)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME,
            string.format("|cffffd200Chatify:|r native chat selection enabled on %d chat frame(s). Drag text in chat, then press Ctrl+C.", tonumber(enabledCount) or 1))
    end
end

function ns.EnterNativeChatCopyMode(chatFrame)
    local frames = ResolveNativeCopyFrames(chatFrame)
    if type(frames) ~= "table" or #frames == 0 then
        return false
    end

    nativeCopySessionId = nativeCopySessionId + 1
    local sessionId = nativeCopySessionId
    local enabledCount = 0

    for i = 1, #frames do
        if EnableNativeCopyOnFrame(frames[i], sessionId) then
            enabledCount = enabledCount + 1
        end
    end

    if enabledCount == 0 then
        return false
    end

    NotifyNativeCopyEnabled(enabledCount)

    -- Do not run the fallback immediately on clients without C_Timer; immediate
    -- restore is exactly what makes native mode look broken. With C_Timer we
    -- clean up later so ElvUI/Prat/Blizzard frames are not left modified forever.
    local function delayedRestore()
        RestoreNativeCopySession(sessionId)
    end

    if type(ns.SafeAfter) == "function" and C_Timer and type(C_Timer.After) == "function" then
        ns.SafeAfter(120, delayedRestore)
    elseif C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, 120, delayedRestore)
    end

    return true
end

function ns.OpenChatCopyWindow(chatFrame, maxLines)
    chatFrame = chatFrame or (type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame()) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME

    -- Match Prat's behavior: copy the selected chat frame first.
    -- The global event cache is only a fallback for clients/frames that do not expose history.
    local entries = ReadMessageHistory(chatFrame, maxLines)
    if not HasReadableEntries(entries) then
        local visibleEntries = ReadVisibleChatLines(chatFrame)
        if HasReadableEntries(visibleEntries) or (not HasAnyCopyEntries(entries) and HasAnyCopyEntries(visibleEntries)) then
            entries = visibleEntries
        end
    end

    if not HasReadableEntries(entries) then
        local cachedEntries = BuildCachedChatEntries(maxLines, COPY_WINDOW_MAX_CHARS)
        if HasReadableEntries(cachedEntries) or (not HasAnyCopyEntries(entries) and HasAnyCopyEntries(cachedEntries)) then
            entries = cachedEntries
        end
    end

    if not HasAnyCopyEntries(entries) then
        entries = { BuildEntry(L("Chat buffer is empty. Send or receive a new message, then open this window again.")) }
    elseif not HasReadableEntries(entries) and type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
        entries[#entries + 1] = BuildEntry(L("Some lines are protected by Blizzard and cannot be exported by addons. Use Right Click or Shift+Left Click on the copy button for native selection."))
    end

    ShowCopyWindow(entries, L("Chatify Copy — selected chat"))
end

-- =========================================================
-- 3. ПОПАП ДЛЯ URL
-- =========================================================
if type(StaticPopupDialogs) == "table" then
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
end

local function ShowUrlCopyPopup(url)
    url = SafeChatText(url) or tostring(url or "")
    if type(StaticPopup_Show) == "function" and type(StaticPopupDialogs) == "table" and StaticPopupDialogs["CHATIFY_COPY_URL"] then
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, url)
        return
    end
    ShowCopyWindow({ BuildEntry(url) or url }, L("Chatify Copy — link"))
end

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
    if not IsNonEmptyString(safeMsg) then
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

local function DisableChatCapture()
    if not captureFrame then
        return
    end

    if type(captureFrame.UnregisterAllEvents) == "function" then
        pcall(captureFrame.UnregisterAllEvents, captureFrame)
    end
    if type(captureFrame.SetScript) == "function" then
        pcall(captureFrame.SetScript, captureFrame, "OnEvent", nil)
    end
    captureFrame = nil
end

function CopyModule:OnEnable()
    if type(SetItemRef) == "function" and not self:IsHooked("SetItemRef") then
        self:RawHook("SetItemRef", true)
    end
    EnsureChatCapture()
    if Chatify and type(Chatify.RegisterChatCommand) == "function" then
        if type(Chatify.UnregisterChatCommand) == "function" then
            pcall(Chatify.UnregisterChatCommand, Chatify, "chatcopy")
        end
        pcall(Chatify.RegisterChatCommand, Chatify, "chatcopy", function(input)
            local command = type(input) == "string" and input:lower():match("^%s*(.-)%s*$") or ""
            local frame = (type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame()) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME

            if command == "select" or command == "native" then
                if type(ns.EnterNativeChatCopyMode) == "function" then
                    ns.EnterNativeChatCopyMode(frame)
                end
                return
            end

            if command == "full" or command == "all" then
                ns.OpenChatCopyWindow(frame, 5000)
                return
            end

            ns.OpenChatCopyWindow(frame, COPY_WINDOW_MAX_LINES)
        end)
    end
end

function CopyModule:SetItemRef(link, text, button, chatFrame)
    local safeLink = SafeChatText(link)
    if not IsNonEmptyString(safeLink) then
        return self.hooks.SetItemRef(link, text, button, chatFrame)
    end

    if safeLink:sub(1, 9) == "chatcopy:" then
        local id = tonumber(safeLink:sub(10))
        local payload = (ns.GetCachedChatLine and ns.GetCachedChatLine(id)) or msgCache[id]
        if id and payload then
            ShowCopyWindow({ payload }, L("Chatify Copy — selected line"))
        end
        return
    end

    if safeLink:sub(1, 4) == "url:" then
        ShowUrlCopyPopup(safeLink:sub(5))
        return
    end

    self.hooks.SetItemRef(link, text, button, chatFrame)
end


function CopyModule:OnDisable()
    DisableChatCapture()
    if self:IsHooked("SetItemRef") then
        self:Unhook("SetItemRef")
    end
    if Chatify and type(Chatify.UnregisterChatCommand) == "function" then
        pcall(Chatify.UnregisterChatCommand, Chatify, "chatcopy")
    end
end
