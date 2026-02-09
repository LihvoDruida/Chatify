local addonName, ns = ...

-- =========================================================
-- 0. CACHE SYSTEM
-- =========================================================
local msgCache = {}
local msgIndex = 0
local CACHE_SIZE = 500

-- Функція доступна для ChatFilters.lua
function ns.SaveToCache(text)
    msgIndex = msgIndex + 1
    msgCache[msgIndex] = text
    
    if msgIndex > CACHE_SIZE + 50 then
        for i = msgIndex - CACHE_SIZE - 50, msgIndex - CACHE_SIZE do
            msgCache[i] = nil
        end
    end
    return msgIndex
end

-- =========================================================
-- 1. WINDOW FOR COPYING TEXT
-- =========================================================
local f = CreateFrame("Frame", "MyChatCopyFrame", UIParent, "BackdropTemplate")

f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 }
})
f:SetBackdropColor(0, 0, 0, 0.9)
f:SetSize(500, 400)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:Hide()
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

local scrollArea = CreateFrame("ScrollFrame", "MyChatCopyScroll", f, "UIPanelScrollFrameTemplate")
scrollArea:SetPoint("TOPLEFT", 10, -30)
scrollArea:SetPoint("BOTTOMRIGHT", -30, 10)

local editBox = CreateFrame("EditBox", nil, scrollArea)
editBox:SetMultiLine(true)
editBox:SetMaxLetters(99999)
editBox:EnableMouse(true)
editBox:SetAutoFocus(false)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(460)
editBox:SetHeight(400) 
editBox:SetScript("OnEscapePressed", function() f:Hide() end)

scrollArea:SetScrollChild(editBox)

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 0, 0)

local function ShowCopyWindow(text)
    f:Show()
    editBox:SetText(text)
    editBox:HighlightText()
    editBox:SetFocus()
end

-- =========================================================
-- 2. POPUP FOR URLS
-- =========================================================
StaticPopupDialogs["CHATIFY_COPY_URL"] = {
    text = "Press Ctrl+C to copy the link:",
    button1 = "OK",
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self, data)
        local eb = self.EditBox
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
-- 3. CLICK HANDLER
-- =========================================================
local OldSetItemRef = SetItemRef
function SetItemRef(link, text, button, chatFrame)
    -- Click on TIMESTAMP (chatcopy:ID)
    if link:sub(1, 9) == "chatcopy:" then
        local id = tonumber(link:sub(10))

        if id and msgCache[id] then
            ShowCopyWindow(msgCache[id])
        end
        return
    end

    -- Click on URL (url:LINK)
    if link:sub(1, 4) == "url:" then
        local currentLink = link:sub(5)
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, currentLink)
        return
    end

    OldSetItemRef(link, text, button, chatFrame)
end