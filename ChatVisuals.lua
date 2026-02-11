local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")

-- Підключаємо AceHook-3.0 та AceEvent-3.0
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
-- 2. FONT STYLING
-- =========================================================
local function StyleFrame(frame)
    if not frame then return end
    
    local db = nil
    if ns.db then db = ns.db
    elseif Chatify.db then db = Chatify.db.profile end
    
    if not db then return end 

    -- Шрифт
    local fontPath, _, _ = ChatFontNormal:GetFont()
    if ns.Lists and ns.Lists.Fonts and db.fontID then
        local selectedFont = ns.Lists.Fonts[db.fontID]
        if selectedFont and selectedFont.path then
            fontPath = selectedFont.path
        end
    end
    
    -- Розмір та стиль
    local _, currentSize = frame:GetFont()
    local size = NormalizeFontSize(currentSize)
    local outline = db.fontOutline or "" 

    frame:SetFont(fontPath, size, outline)
    frame:SetShadowOffset(1, -1)

    -- EditBox
    local editBox = ns.GetEditBox(frame)
    if editBox and editBox.SetFont then
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
    local db = ns.db or (Chatify.db and Chatify.db.profile)
    
    -- 1. Apply Fonts
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then StyleFrame(frame) end
    end
    
    -- 2. Apply Short Channels
    if db and db.shortChannels then
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
-- 4. TIMESTAMPS (Advanced)
-- =========================================================
local function TimestampFilter(self, event, msg, author, ...)
    local db = ns.db
    if not db then return false, msg, author, ... end
    
    if ns.Lists and ns.Lists.TimeFormats then
        local formatData = ns.Lists.TimeFormats[db.timestampID] or ns.Lists.TimeFormats[1]
        
        if formatData then
            -- Вибір між Серверним та Локальним часом
            -- Якщо db.useServerTime не задано, використовуємо локальний (time())
            local timestamp = db.useServerTime and GetServerTime() or time()
            local timeStr = date(formatData.format, timestamp)
            
            local cleanContent = CleanTextTags(msg)
            local copyText = string.format("[%s] %s: %s", timeStr, (author or "System"), cleanContent)
            local tsColor = db.timestampColor or "68ccef"
            local styledTime
            
            -- Створення клікабельного елементу
            if ns.SaveToCache then
                local id = ns.SaveToCache(copyText)
                styledTime = string.format("|cff%s|Hchatcopy:%d|h[%s]|h|r", tsColor, id, timeStr)
            else
                styledTime = string.format("|cff%s|Hchatcopy|h[%s]|h|r", tsColor, timeStr)
            end
            
            -- Позиціонування (Pre/Post)
            if db.timestampPost then
                -- Час в кінці
                msg = msg .. " " .. styledTime
            else
                -- Час на початку (стандарт)
                msg = styledTime .. " " .. msg
            end
        end
    end
    
    return false, msg, author, ...
end

-- =========================================================
-- 5. MODULE LIFECYCLE
-- =========================================================
function VisualsModule:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyStyle")
    
    -- Хуки для оновлення візуалу
    self:SecureHook("FCF_OpenTemporaryWindow", ns.ApplyVisuals)
    self:SecureHook("FCF_OpenNewWindow", ns.ApplyVisuals)
    
    if FCF_SetChatWindowFontSize then
        self:SecureHook("FCF_SetChatWindowFontSize", function(chatFrame)
            StyleFrame(chatFrame)
        end)
    end
    
    -- Кольори класів
    for _, info in pairs(ChatTypeInfo) do
        if type(info) == "table" then
            info.colorNameByClass = true
        end
    end
    
    -- Реєстрація подій для TimestampFilter
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
    
    ns.ApplyVisuals()
end

function VisualsModule:PLAYER_LOGIN()
    ns.ApplyVisuals()
end

function VisualsModule:ApplyStyle()
    ns.ApplyVisuals()
end