local addonName, ns = ...
-- Отримуємо головний об'єкт аддону
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
-- Створюємо модуль "Copy" та підключаємо бібліотеку хуків
local CopyModule = Chatify:NewModule("Copy", "AceHook-3.0")

-- =========================================================
-- 1. КЕШУВАННЯ (CACHE SYSTEM)
-- =========================================================
local msgCache = {}
local msgIndex = 0
local CACHE_SIZE = 500

-- Глобальна функція для ns (використовується в ChatFilters.lua)
function ns.SaveToCache(text)
    msgIndex = msgIndex + 1
    msgCache[msgIndex] = text
    
    -- Очищення старого кешу
    if msgIndex > CACHE_SIZE + 50 then
        for i = msgIndex - CACHE_SIZE - 50, msgIndex - CACHE_SIZE do
            msgCache[i] = nil
        end
    end
    
    return msgIndex
end

-- =========================================================
-- 2. ВІКНО КОПІЮВАННЯ (Створюється при потребі)
-- =========================================================
local copyFrame
local copyEditBox

local function CreateCopyWindow()
    if copyFrame then return end -- Вже створено

    -- Головний фрейм
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
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Кнопка закриття
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    
    -- Скрол
    local scrollArea = CreateFrame("ScrollFrame", "MyChatCopyScroll", f, "UIPanelScrollFrameTemplate")
    scrollArea:SetPoint("TOPLEFT", 10, -30)
    scrollArea:SetPoint("BOTTOMRIGHT", -30, 10)
    
    -- Поле тексту
    local eb = CreateFrame("EditBox", nil, scrollArea)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(99999)
    eb:EnableMouse(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(460)
    eb:SetHeight(400) 
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    
    scrollArea:SetScrollChild(eb)
    
    copyFrame = f
    copyEditBox = eb
end

local function ShowCopyWindow(text)
    if not copyFrame then CreateCopyWindow() end
    
    copyFrame:Show()
    copyEditBox:SetText(text)
    copyEditBox:HighlightText()
    copyEditBox:SetFocus()
end

-- =========================================================
-- 3. ПОПАП ДЛЯ URL
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
-- 4. ПЕРЕХОПЛЕННЯ КЛІКІВ (HOOKS)
-- =========================================================

function CopyModule:OnEnable()
    -- RawHook повністю замінює оригінальну функцію.
    -- Ми самі вирішуємо, коли викликати оригінал.
    self:RawHook("SetItemRef", true)
end

function CopyModule:SetItemRef(link, text, button, chatFrame)
    -- 1. Клік на TIMESTAMP (chatcopy:ID)
    if link:sub(1, 9) == "chatcopy:" then
        local id = tonumber(link:sub(10))
        if id and msgCache[id] then
            ShowCopyWindow(msgCache[id])
        end
        return -- Не викликаємо оригінал, бо це наше посилання
    end

    -- 2. Клік на URL (url:LINK)
    if link:sub(1, 4) == "url:" then
        local currentLink = link:sub(5)
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, currentLink)
        return -- Не викликаємо оригінал
    end

    -- 3. Якщо це не наше посилання, передаємо керування грі
    self.hooks.SetItemRef(link, text, button, chatFrame)
end