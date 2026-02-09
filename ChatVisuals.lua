local addonName, ns = ...

-- =========================================================
-- 1. ДОПОМІЖНІ ФУНКЦІЇ
-- =========================================================

-- Очищує розмір шрифту (захист від значень типу 14.00001 або -1)
local function NormalizeFontSize(size)
    if type(size) ~= "number" or size <= 0 then
        return nil
    end
    local rounded = math.floor(size + 0.5)
    if rounded <= 0 or rounded > 64 then
        return nil
    end
    return rounded
end

-- "Розумний" пошук поля вводу (EditBox)
function ns.GetEditBox(chatFrame)
    if not chatFrame then return nil end
    if chatFrame.editBox then return chatFrame.editBox end
    if chatFrame.GetName then
        local name = chatFrame:GetName()
        if name then
            local suffixBox = _G[name .. "EditBox"]
            if suffixBox then return suffixBox end
        end
    end
    local id = chatFrame:GetID()
    if id then
        local idBox = _G["ChatFrame" .. id .. "EditBox"]
        if idBox then return idBox end
    end
    return ChatFrame1EditBox
end

-- Примусове збереження налаштувань
local function ForceSaveSettings()
    if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(ChatFrame1) end
    if FCF_SaveChatWindow then FCF_SaveChatWindow(ChatFrame1) end
    if FCF_SaveDock then FCF_SaveDock() end
    if FCF_SaveChatWindows then FCF_SaveChatWindows() end
end

-- =========================================================
-- 2. СТИЛІЗАЦІЯ
-- =========================================================

local function StyleFrame(frame)
    if not frame then return end
    local db = ns.db
    if not db then return end 

    -- 1. ОТРИМУЄМО СТАНДАРТНИЙ ШРИФТ ГРИ
    -- Беремо те, що зараз використовує WoW (або ElvUI, якщо він стоїть)
    local standardFont, standardSize, standardFlags = ChatFontNormal:GetFont()
    local fontPath = standardFont 

    -- 2. ЯКЩО КОРИСТУВАЧ ВИБРАВ КАСТОМНИЙ ШРИФТ
    -- Перевіряємо, чи є список і чи вибрано щось відмінне від дефолту
    if ns.Lists and ns.Lists.Fonts and db.fontID then
        local selectedFont = ns.Lists.Fonts[db.fontID]
        if selectedFont and selectedFont.path then
            fontPath = selectedFont.path
        end
    end
    
    -- 3. ВИЗНАЧЕННЯ РОЗМІРУ (Безпечне)
    local _, currentSize = frame:GetFont()
    local size = NormalizeFontSize(currentSize) or 14
    local outline = db.fontOutline or "" 

    -- 4. ЗАСТОСУВАННЯ ШРИФТУ ДО ЧАТУ
    -- Встановлюємо шлях, розмір та контур
    frame:SetFont(fontPath, size, outline)
    frame:SetShadowOffset(db.shadowX or 1, db.shadowY or -1)

    -- 5. ЗАСТОСУВАННЯ ДО EDITBOX
    local editBox = ns.GetEditBox(frame)
    if editBox then
        editBox:SetFont(fontPath, size, outline)
    end
end

-- Глобальна функція для оновлення всього
function ns.ApplyVisuals()
    for i = 1, NUM_CHAT_WINDOWS do
        StyleFrame(_G["ChatFrame" .. i])
    end
    ForceSaveSettings()
end

-- =========================================================
-- 3. ІНІЦІАЛІЗАЦІЯ ТА ПОДІЇ
-- =========================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    
    if ns.LoadConfig then ns.LoadConfig() end
    local db = ns.db

    -- Скорочення каналів
    if db and db.shortChannels then
        _G.CHAT_GUILD_GET             = "|Hchannel:GUILD|h[G]|h %s:\32"
        _G.CHAT_OFFICER_GET           = "|Hchannel:OFFICER|h[O]|h %s:\32"
        _G.CHAT_PARTY_GET             = "|Hchannel:PARTY|h[P]|h %s:\32"
        _G.CHAT_PARTY_LEADER_GET      = "|Hchannel:PARTY|h[PL]|h %s:\32"
        _G.CHAT_RAID_GET              = "|Hchannel:RAID|h[R]|h %s:\32"
        _G.CHAT_RAID_LEADER_GET       = "|Hchannel:RAID|h[RL]|h %s:\32"
        _G.CHAT_INSTANCE_CHAT_GET     = "|Hchannel:INSTANCE|h[I]|h %s:\32"
        _G.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE|h[IL]|h %s:\32"
        _G.CHAT_WHISPER_GET           = "from %s:\32"
        _G.CHAT_WHISPER_INFORM_GET    = "to %s:\32"
        _G.CHAT_SAY_GET               = "%s:\32"
        _G.CHAT_YELL_GET              = "%s:\32"
    end

    ns.ApplyVisuals()

    for _, info in pairs(ChatTypeInfo) do
        info.colorNameByClass = true
    end
end)

-- =========================================================
-- 4. ХУКИ
-- =========================================================
hooksecurefunc("FCF_OpenTemporaryWindow", ns.ApplyVisuals)
hooksecurefunc("FCF_OpenNewWindow", ns.ApplyVisuals)
hooksecurefunc("FCF_Tab_OnClick", ns.ApplyVisuals)

hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame, frame, size)
    StyleFrame(chatFrame) 
    ForceSaveSettings()
end)