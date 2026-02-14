local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
-- Підключаємо LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0")
local VisualsModule = Chatify:NewModule("Visuals", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- SAFE EVENT WHITELIST (КРИТИЧНО ВАЖЛИВО)
-- =========================================================
-- Ми додаємо таймстемпи ТІЛЬКИ до цих подій.
-- Всі інші (MONSTER_YELL, SYSTEM, BN_WHISPER) ігноруються, щоб уникнути taint-крашів.
local eventsToHandle = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_GUILD_MOTD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_CHANNEL = true,
    -- CHAT_MSG_BN_WHISPER -- Видалено (taint ризик)
    -- CHAT_MSG_SYSTEM -- Видалено (taint ризик)
}

-- =========================================================
-- 1. UTILITIES & SAFETY
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

-- Безпечне отримання тексту (Deep Sanitization)
local function GetSafeText(rawText)
    if rawText == nil then return nil end
    if type(rawText) == "number" then return tostring(rawText) end
    if type(rawText) ~= "string" then return nil end

    -- Спроба створити нову копію рядка
    local ok, clean = pcall(string.format, "%s", rawText)
    if not ok then return nil end

    local nonEmptyOk, result = pcall(function()
        if clean == "" then return nil end
        return clean
    end)

    if nonEmptyOk then return result else return nil end
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
-- 2. FONT STYLING
-- =========================================================
local function StyleFrame(frame)
    if not frame then return end
    local db = Chatify.db.profile
    if not db then return end

    local fontPath = nil
    if db.fontID then
        fontPath = LSM:Fetch("font", db.fontID)
    end

    if not fontPath then
        fontPath = ChatFontNormal:GetFont()
    end

    -- Отримуємо поточний розмір або налаштування
    local _ , size, _ = frame:GetFont()
    size = NormalizeFontSize(size)
    local outline = db.fontOutline or ""

    frame:SetFont(fontPath, size, outline)
    frame:SetShadowOffset(1, -1)

    local editBox = ns.GetEditBox(frame)
    if editBox then
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

function ns.ApplyVisuals()
    local db = Chatify.db.profile
    if not db then return end

    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame"..i]
        if frame then 
            StyleFrame(frame) 
        end
    end

    if db.shortChannels then
        if not next(OriginalChannelMaps) then
            for k, v in pairs(ShortChannelMaps) do
                if _G[k] then OriginalChannelMaps[k] = _G[k] end
            end
        end
        for k, v in pairs(ShortChannelMaps) do
            if _G[k] then _G[k] = v end
        end
    else
        if next(OriginalChannelMaps) then
            for k, v in pairs(OriginalChannelMaps) do
                _G[k] = v
            end
        end
    end
end

-- =========================================================
-- 4. TIMESTAMPS (SECURE)
-- =========================================================
local function TimestampFilter(self, event, msg, author, ...)
    local db = Chatify.db.profile
    if not db then return false, msg, author, ... end

    -- Перевірка налаштувань
    if not db.enableTimestamps then return false, msg, author, ... end

    -- 1. БІЛИЙ СПИСОК: Якщо подія небезпечна, повертаємо оригінал без змін
    if not eventsToHandle[event] then
        return false, msg, author, ...
    end

    -- 2. САНІТАРНА ОБРОБКА: Отримуємо безпечний текст
    local safeMsg = GetSafeText(msg)
    if not safeMsg then
        -- Якщо текст tainted, не чіпаємо його
        return false, msg, author, ...
    end

    local timestampFormat = "%H:%M" 
    if ns.Lists and ns.Lists.TimeFormats and db.timestampID then
       local formatData = ns.Lists.TimeFormats[db.timestampID]
       if formatData then timestampFormat = formatData.format end
    end

    local timestamp = db.useServerTime and GetServerTime() or time()
    local timeStr = date(timestampFormat, timestamp)

    local tsColor = db.timestampColor or "68ccef"
    -- Використовуємо string.format для створення нового рядка
    local styledTime = string.format("|cff%s[%s]|r", tsColor, timeStr)

    -- Модифікуємо БЕЗПЕЧНУ копію повідомлення
    if db.timestampPost then
        safeMsg = safeMsg .. " " .. styledTime
    else
        safeMsg = styledTime .. " " .. safeMsg
    end

    -- Повертаємо нове, безпечне повідомлення
    return false, safeMsg, author, ...
end

-- =========================================================
-- 5. MODULE LIFECYCLE
-- =========================================================
function VisualsModule:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN")
    
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyStyle")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "ApplyStyle")

    self:SecureHook("FCF_OpenTemporaryWindow", function() ns.ApplyVisuals() end)
    self:SecureHook("FCF_OpenNewWindow", function() ns.ApplyVisuals() end)

    hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame)
        StyleFrame(chatFrame)
    end)

    for _, info in pairs(ChatTypeInfo) do
        if type(info) == "table" then
            info.colorNameByClass = true
        end
    end

    -- Реєструємо фільтри ТІЛЬКИ для подій з білого списку
    for evt in pairs(eventsToHandle) do
        ChatFrame_AddMessageEventFilter(evt, TimestampFilter)
    end

    ns.ApplyVisuals()
end

function VisualsModule:PLAYER_LOGIN()
    ns.ApplyVisuals()
end

function VisualsModule:ApplyStyle()
    ns.ApplyVisuals()
end