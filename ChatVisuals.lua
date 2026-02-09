local addonName, ns = ...

-- Функція стилізації конкретного фрейму
local function StyleFrame(frame)
    if not frame then return end
    local db = ns.db -- Беремо налаштування
    
    local name = frame:GetName()
    
    -- 1. ВИЗНАЧЕННЯ ШРИФТУ (ПО ID)
    local fontData = ns.Lists.Fonts[db.fontID] or ns.Lists.Fonts[1]
    local fontPath = fontData.path
    
    -- 2. ВИЗНАЧЕННЯ РОЗМІРУ (З ГРИ)
    local _, currentSize = frame:GetFont()
    local size = (currentSize and currentSize > 0) and currentSize or 14
    local outline = db.fontOutline or "" 

    -- 3. ЗАСТОСУВАННЯ ШРИФТУ
    -- Змінюємо тільки шрифт і тінь. Більше нічого не чіпаємо.
    frame:SetFont(fontPath, size, outline)
    frame:SetShadowOffset(db.shadowX or 1, db.shadowY or -1)

    -- 4. EDITBOX (Поле вводу)
    if name then
        local editBox = _G[name .. "EditBox"]
        if editBox then
            editBox:SetFont(fontPath, size, outline)
        end
    end
end

-- Глобальна функція для оновлення всього
function ns.ApplyVisuals()
    for i = 1, NUM_CHAT_WINDOWS do
        StyleFrame(_G["ChatFrame" .. i])
    end
end

------------------------------------------------------------
-- ІНІЦІАЛІЗАЦІЯ
------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    -- Завантажуємо SavedVariables
    ns.LoadConfig() 

    local db = ns.db

    -- 1. Налаштування каналів (Текст)
    -- Це залишаємо, бо це форматування тексту, а не приховування елементів
    if db.shortChannels then
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

    -- 2. Застосовуємо шрифти
    ns.ApplyVisuals()

    -- 3. Кольори класів
    for _, info in pairs(ChatTypeInfo) do
        info.colorNameByClass = true
    end
end)

------------------------------------------------------------
-- ХУКИ
------------------------------------------------------------
hooksecurefunc("FCF_OpenTemporaryWindow", ns.ApplyVisuals)
hooksecurefunc("FCF_OpenNewWindow", ns.ApplyVisuals)
hooksecurefunc("FCF_Tab_OnClick", ns.ApplyVisuals)

-- Хук на зміну розміру шрифту через меню гри
hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame, frame, size)
    StyleFrame(chatFrame) 
end)