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
    f:SetSize(640, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetPoint("TOPRIGHT", -42, -12)
    title:SetJustifyH("LEFT")
    title:SetText(L("Chatify Copy"))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local previewBg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    previewBg:SetPoint("TOPLEFT", 14, -42)
    previewBg:SetPoint("BOTTOMRIGHT", -32, 54)
    if previewBg.SetBackdrop then
        previewBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        previewBg:SetBackdropColor(0.02, 0.02, 0.025, 0.88)
        previewBg:SetBackdropBorderColor(0.42, 0.32, 0.12, 0.90)
    end

    local scrollArea = CreateFrame("ScrollFrame", "ChatifyCopyPreviewScroll", f, "UIPanelScrollFrameTemplate")
    scrollArea:SetPoint("TOPLEFT", previewBg, "TOPLEFT", 8, -8)
    scrollArea:SetPoint("BOTTOMRIGHT", previewBg, "BOTTOMRIGHT", -26, 8)

    -- Selectable copy field.
    -- Users can manually select any text directly in the window,
    -- or click Copy All to select the full prepared export.
    local eb = CreateFrame("EditBox", "ChatifyCopySelectableEditBox", scrollArea)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(COPY_WINDOW_MAX_CHARS + 1000)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(0.92, 0.92, 0.92, 1)
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("TOP")
    eb:SetWidth(560)
    eb:SetHeight(1)
    eb:EnableMouse(true)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    eb:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        if ScrollingEdit_OnCursorChanged then
            ScrollingEdit_OnCursorChanged(self, 0, y, 0, cursorHeight)
        end
    end)
    eb:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then
            ScrollingEdit_OnUpdate(self, elapsed, scrollArea)
        end
    end)
    scrollArea:SetScrollChild(eb)

    local content = eb

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(108, 24)
    btn:SetPoint("BOTTOMRIGHT", -16, 16)
    btn:SetText(L("Copy All"))
    btn:SetScript("OnClick", function()
        if copyEditBox then
            copyEditBox:SetFocus()
            copyEditBox:HighlightText()
        end
        if copyHint then
            copyHint:SetText(L("Selected text is ready. Press Ctrl+C to copy."))
        end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 20)
    hint:SetPoint("RIGHT", btn, "LEFT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("Select text manually, or click Copy All and press Ctrl+C."))

    copyFrame = f
    copyEditBox = eb
    copyTitle = title
    copyScroll = scrollArea
    copyContent = content
    copyHint = hint
    copyButton = btn
end

local BuildTextFromEntries

local function ClearCopyPreview()
    if copyContent and type(copyContent.SetText) == "function" then
        copyContent:SetText("")
        copyContent:SetCursorPosition(0)
        copyContent:HighlightText(0, 0)
        copyContent:ClearFocus()
    end
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
    copyContent:SetText(text)
    copyContent:SetCursorPosition(0)
    copyContent:HighlightText(0, 0)
    copyContent:ClearFocus()

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
        copyHint:SetText(L("Select text manually, or click Copy All and press Ctrl+C."))
    end

    RenderCopyPreview(entries)

    copyEditBox:SetText(BuildTextFromEntries(entries, COPY_WINDOW_MAX_CHARS))
    copyEditBox:ClearFocus()
    copyEditBox:HighlightText(0, 0)
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


local function ReadMessageHistory(chatFrame, maxLines)
    if not chatFrame then
        return nil
    end

    local entries = {}
    maxLines = tonumber(maxLines) or COPY_WINDOW_MAX_LINES

    if type(chatFrame.GetNumMessages) == "function" and type(chatFrame.GetMessageInfo) == "function" then
        local okCount, count = pcall(chatFrame.GetNumMessages, chatFrame)
        if okCount and type(count) == "number" and count > 0 then
            local first = math.max(1, count - maxLines + 1)
            for i = first, count do
                local ok, msg = pcall(chatFrame.GetMessageInfo, chatFrame, i)
                if ok and msg then
                    local entry = BuildEntry(msg)
                    if entry then
                        entries[#entries + 1] = entry
                    end
                end
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

    local entries = BuildCachedChatEntries(maxLines, COPY_WINDOW_MAX_CHARS)
    if not entries then
        entries = ReadMessageHistory(chatFrame, maxLines)
    end

    if not entries then
        entries = ReadVisibleChatLines(chatFrame)
    end

    if not entries then
        entries = { BuildEntry(L("Chat buffer is empty. Send or receive a new message, then open this window again.")) }
    end

    ShowCopyWindow(entries, L("Chatify Copy — recent chat"))
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
            eb:SetText(data)
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
    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author) then
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
        pcall(captureFrame.RegisterEvent, captureFrame, eventName)
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
