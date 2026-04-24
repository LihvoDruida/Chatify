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

local function AddFullChatLine(text)
    local clean = StripChatMarkup(text)
    if type(clean) ~= "string" or clean == "" then
        return
    end

    fullChatIndex = fullChatIndex + 1
    fullChatCache[fullChatIndex] = clean

    local pruneBefore = fullChatIndex - CACHE_SIZE
    if pruneBefore > 0 then
        fullChatCache[pruneBefore] = nil
    end
end

function ns.SaveToCache(text)
    msgIndex = msgIndex + 1
    msgCache[msgIndex] = text
    AddFullChatLine(text)

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

local function CreateCopyWindow()
    if copyFrame then return end

    local f = CreateFrame("Frame", "ChatifyCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 5, bottom = 3 }
        })
        f:SetBackdropColor(0, 0, 0, 0.92)
    end
    f:SetSize(560, 420)
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
    title:SetText("Chatify Copy")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local scrollArea = CreateFrame("ScrollFrame", "ChatifyCopyScroll", f, "UIPanelScrollFrameTemplate")
    scrollArea:SetPoint("TOPLEFT", 12, -38)
    scrollArea:SetPoint("BOTTOMRIGHT", -30, 12)

    local eb = CreateFrame("EditBox", nil, scrollArea)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(COPY_WINDOW_MAX_CHARS + 1000)
    eb:EnableMouse(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(510)
    eb:SetHeight(400)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)

    scrollArea:SetScrollChild(eb)

    copyFrame = f
    copyEditBox = eb
    copyTitle = title
    copyScroll = scrollArea
end

local function ShowCopyWindow(text, title)
    if not copyFrame then CreateCopyWindow() end

    copyFrame:Show()
    if copyTitle then
        copyTitle:SetText(title or "Chatify Copy")
    end
    copyEditBox:SetText(text or "")
    copyEditBox:HighlightText()
    copyEditBox:SetFocus()
    if copyScroll and copyScroll.SetVerticalScroll then
        copyScroll:SetVerticalScroll(0)
    end
end

local function BuildCachedChatText(maxLines, maxChars)
    maxLines = tonumber(maxLines) or COPY_WINDOW_MAX_LINES
    maxChars = tonumber(maxChars) or COPY_WINDOW_MAX_CHARS

    local lines = {}
    local chars = 0
    local startIndex = math.max(1, fullChatIndex - maxLines + 1)

    for i = startIndex, fullChatIndex do
        local line = fullChatCache[i]
        if type(line) == "string" and line ~= "" then
            chars = chars + #line + 1
            if chars > maxChars then
                lines[#lines + 1] = "..."
                break
            end
            lines[#lines + 1] = line
        end
    end

    if #lines == 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

local function ReadVisibleChatLines(chatFrame)
    if not chatFrame or type(chatFrame.GetRegions) ~= "function" then
        return nil
    end

    local lines = {}
    local regions = { chatFrame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" and type(region.GetText) == "function" then
            local ok, text = pcall(region.GetText, region)
            text = ok and StripChatMarkup(text) or nil
            if type(text) == "string" and text ~= "" then
                lines[#lines + 1] = text
            end
        end
    end

    if #lines == 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

function ns.OpenChatCopyWindow(chatFrame, maxLines)
    chatFrame = chatFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME

    local text = BuildCachedChatText(maxLines, COPY_WINDOW_MAX_CHARS)
    if not text or text == "" then
        text = ReadVisibleChatLines(chatFrame)
    end

    if not text or text == "" then
        text = "No cached chat lines yet. New messages will become available after Chatify processes them."
    end

    ShowCopyWindow(text, "Chatify Copy — recent chat")
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
function CopyModule:OnEnable()
    self:RawHook("SetItemRef", true)
end

function CopyModule:SetItemRef(link, text, button, chatFrame)
    if type(ns.IsSecretValue) == "function" and ns.IsSecretValue(link) then
        return self.hooks.SetItemRef(link, text, button, chatFrame)
    end

    if type(link) ~= "string" or link == "" then
        return self.hooks.SetItemRef(link, text, button, chatFrame)
    end

    if link:sub(1, 9) == "chatcopy:" then
        local id = tonumber(link:sub(10))
        local payload = (ns.GetCachedChatLine and ns.GetCachedChatLine(id)) or msgCache[id]
        if id and payload then
            ShowCopyWindow(StripChatMarkup(payload) or payload, "Chatify Copy — selected line")
        end
        return
    end

    if link:sub(1, 4) == "url:" then
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, link:sub(5))
        return
    end

    self.hooks.SetItemRef(link, text, button, chatFrame)
end
