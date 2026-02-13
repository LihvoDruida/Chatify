local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
-- Підключаємо LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0")
local VisualsModule = Chatify:NewModule("Visuals", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- 1. UTILITIES
-- =========================================================
local function NormalizeFontSize(size)
    if type(size) ~= "number" or size <= 0 then return 14 end
    local rounded = math.floor(size + 0.5)
    if rounded <= 0 or rounded > 64 then return 14 end
    return rounded
end

local function CleanTextTags(text)
    if not text then return "" end
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
end

function ns.GetEditBox(chatFrame)
    if not chatFrame then return nil end
    if chatFrame.editBox then return chatFrame.editBox end

    local name = chatFrame:GetName()
    if name then
        local suffixBox = _G[name .. "EditBox"]
        if suffixBox then return suffixBox end
    end

    local id = chatFrame:GetID()
    if id then
        local idBox = _G["ChatFrame" .. id .. "EditBox"]
        if idBox then return idBox end
    end

    return ChatFrame1EditBox
end

-- =========================================================
-- 2. FONT STYLING (ВИПРАВЛЕНО)
-- =========================================================
local function StyleFrame(frame)
    if not frame then return end
    -- Отримуємо профіль коректно
    local db = Chatify.db.profile
    if not db then return end

    -- 1. Отримуємо шлях до шрифту через LSM
    -- db.fontID зберігає назву шрифту (наприклад, "Arial Narrow")
    -- LSM:Fetch перетворює цю назву на шлях "Fonts\\ARIALN.TTF"
    local fontPath = nil
    if db.fontID then
        fontPath = LSM:Fetch("font", db.fontID)
    end

    -- Якщо шрифт не вибрано або не знайдено, беремо стандартний
    if not fontPath then
        fontPath = ChatFontNormal:GetFont()
    end

    -- 2. Розмір та Outline
    local size = db.fontSize or 14
    size = NormalizeFontSize(size)
    local outline = db.fontOutline or ""

    -- 3. Встановлюємо шрифт на Frame
    frame:SetFont(fontPath, size, outline)
    frame:SetShadowOffset(1, -1)

    -- 4. Встановлюємо шрифт на EditBox (поле вводу)
    local editBox = ns.GetEditBox(frame)
    if editBox then
        -- EditBox часто потребує перевірки на header/headerSuffix
        local header = _G[editBox:GetName().."Header"]
        if header then header:SetFont(fontPath, size, outline) end
        
        local suffix = _G[editBox:GetName().."HeaderSuffix"]
        if suffix then suffix:SetFont(fontPath, size, outline) end

        editBox:SetFont(fontPath, size, outline)
    end
end

-- =========================================================
-- 3. CHANNEL SHORTENING
-- =========================================================
-- (Без змін, код скорочення каналів виглядає коректно)
local ShortChannelMaps = {
    CHAT_GUILD_GET              = "|Hchannel:GUILD|h[G]|h %s:\32",
    CHAT_OFFICER_GET            = "|Hchannel:OFFICER|h[O]|h %s:\32",
    CHAT_PARTY_GET              = "|Hchannel:PARTY|h[P]|h %s:\32",
    CHAT_PARTY_LEADER_GET       = "|Hchannel:PARTY|h[PL]|h %s:\32",
    CHAT_RAID_GET               = "|Hchannel:RAID|h[R]|h %s:\32",
    CHAT_RAID_LEADER_GET        = "|Hchannel:RAID|h[RL]|h %s:\32",
    CHAT_INSTANCE_CHAT_GET      = "|Hchannel:INSTANCE|h[I]|h %s:\32",
    CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE|h[IL]|h %s:\32",
    CHAT_WHISPER_GET            = "[W] %s:\32",
    CHAT_WHISPER_INFORM_GET     = "[TO] %s:\32",
    CHAT_BN_WHISPER_GET         = "[BW] %s:\32",
    CHAT_BN_WHISPER_INFORM_GET  = "[BTO] %s:\32",
}

local OriginalChannelMaps = {}

-- Глобальна функція для оновлення візуалу
function ns.ApplyVisuals()
    local db = Chatify.db.profile
    if not db then return end

    -- 1. Оновлюємо шрифти для всіх вікон
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame"..i]
        if frame then 
            StyleFrame(frame) 
        end
    end

    -- 2. Оновлюємо імена каналів
    if db.shortChannels then
        -- Зберігаємо оригінали, якщо ще не зберегли
        if not next(OriginalChannelMaps) then
            for k, v in pairs(ShortChannelMaps) do
                if _G[k] then OriginalChannelMaps[k] = _G[k] end
            end
        end
        -- Застосовуємо короткі назви
        for k, v in pairs(ShortChannelMaps) do
            if _G[k] then _G[k] = v end
        end
    else
        -- Відновлюємо оригінали
        if next(OriginalChannelMaps) then
            for k, v in pairs(OriginalChannelMaps) do
                _G[k] = v
            end
        end
    end
end

-- =========================================================
-- 4. TIMESTAMPS (Оновлено для роботи з DB)
-- =========================================================
local function TimestampFilter(self, event, msg, author, ...)
    local db = Chatify.db.profile
    if not db then return false, msg, author, ... end

    -- Перевіряємо, чи увімкнені таймстемпи (якщо у вас є така опція)
     if not db.enableTimestamps then return false, msg, author, ... end

    -- Форматування часу
    -- Використовуємо db.timestampID або дефолтний формат
    local timestampFormat = "%H:%M" 
    if ns.Lists and ns.Lists.TimeFormats and db.timestampID then
       local formatData = ns.Lists.TimeFormats[db.timestampID]
       if formatData then timestampFormat = formatData.format end
    end

    local timestamp = db.useServerTime and GetServerTime() or time()
    local timeStr = date(timestampFormat, timestamp)

    -- Форматуємо колір
    local tsColor = db.timestampColor or "68ccef"
    local styledTime = string.format("|cff%s[%s]|r", tsColor, timeStr)

    -- Додаємо до повідомлення
    if db.timestampPost then
        msg = msg .. " " .. styledTime
    else
        msg = styledTime .. " " .. msg
    end

    return false, msg, author, ...
end

-- =========================================================
-- 5. MODULE LIFECYCLE
-- =========================================================
function VisualsModule:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN")
    
    -- Оновлюємо стиль при зміні налаштувань WoW
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyStyle")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "ApplyStyle")

    -- Хуки для нових вікон
    self:SecureHook("FCF_OpenTemporaryWindow", function() ns.ApplyVisuals() end)
    self:SecureHook("FCF_OpenNewWindow", function() ns.ApplyVisuals() end)

    -- Хук на зміну розміру шрифту через стандартний UI, щоб форсувати наш шрифт
    -- (FCF_SetChatWindowFontSize часто викликає FCF_SetChatWindowFont, тому ми перехоплюємо це)
    hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame)
        StyleFrame(chatFrame)
    end)

    -- Увімкнення кольорів класів у чаті
    for _, info in pairs(ChatTypeInfo) do
        if type(info) == "table" then
            info.colorNameByClass = true
        end
    end

    -- Реєстрація фільтрів таймстемпів
    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_MOTD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM",
        "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT"
    }

    for _, evt in ipairs(events) do
        ChatFrame_AddMessageEventFilter(evt, TimestampFilter)
    end

    -- Застосовуємо стиль при старті
    ns.ApplyVisuals()
end

function VisualsModule:PLAYER_LOGIN()
    ns.ApplyVisuals()
end

function VisualsModule:ApplyStyle()
    ns.ApplyVisuals()
end