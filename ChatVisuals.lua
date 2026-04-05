local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
-- Підключаємо LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0")
local VisualsModule = Chatify:NewModule("Visuals", "AceEvent-3.0", "AceHook-3.0")
local visualsFiltersInstalled = false
local C_Timer = C_Timer
local GetServerTime = GetServerTime

local function GetVisualDB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return ns and ns.db or nil
end

-- =========================================================
-- SAFE EVENT WHITELIST (КРИТИЧНО ВАЖЛИВО)
-- =========================================================
-- Ми додаємо таймстемпи ТІЛЬКИ до цих подій.
-- Всі інші (MONSTER_YELL, SYSTEM, BN_WHISPER) ігноруються, щоб уникнути taint-крашів.
local eventsToHandle = {
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_GUILD_MOTD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_BN_CONVERSATION = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_AFK = true,
    CHAT_MSG_DND = true,
    CHAT_MSG_ACHIEVEMENT = true,
    CHAT_MSG_GUILD_ACHIEVEMENT = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_LOOT = true,
    CHAT_MSG_MONSTER_SAY = true,
    CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_MONSTER_WHISPER = true,
    CHAT_MSG_MONSTER_BOSS_WHISPER = true,
    CHAT_MSG_MONSTER_BOSS_EMOTE = true,
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
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(rawText)
    end

    if rawText == nil then return nil end
    if type(rawText) == "number" then return tostring(rawText) end
    if type(rawText) ~= "string" then return nil end
    return rawText
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
    local db = GetVisualDB()
    if not db then return end

    local fontPath = nil
    if type(ns.ResolveFontPath) == "function" then
        fontPath = ns.ResolveFontPath(db.fontID)
    elseif db.fontID then
        fontPath = LSM:Fetch("font", db.fontID, true)
    end

    if not fontPath and ChatFontNormal and ChatFontNormal.GetFont then
        fontPath = ChatFontNormal:GetFont()
    end

    local _, size, flags = frame:GetFont()
    size = NormalizeFontSize(size)
    local outline = db.fontOutline or flags or ""

    local ok = pcall(frame.SetFont, frame, fontPath, size, outline)
    if not ok and ChatFontNormal and ChatFontNormal.GetFont then
        local fallbackPath = ChatFontNormal:GetFont()
        pcall(frame.SetFont, frame, fallbackPath, size, flags or "")
    end
    frame:SetShadowOffset(1, -1)

    local editBox = ns.GetEditBox(frame)
    if editBox then
        local header = _G[editBox:GetName().."Header"]
        if header then pcall(header.SetFont, header, fontPath, size, outline) end

        local suffix = _G[editBox:GetName().."HeaderSuffix"]
        if suffix then pcall(suffix.SetFont, suffix, fontPath, size, outline) end

        pcall(editBox.SetFont, editBox, fontPath, size, outline)
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

local function IsRetailRestricted()
    return type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
end

function ns.ApplyVisuals()
    local db = GetVisualDB()
    if not db then return end
    local retailRestricted = IsRetailRestricted()

    for i = 1, (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or NUM_CHAT_WINDOWS or 10) do
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
    local db = GetVisualDB()
    if not db then return false, msg, author, ... end
    if not db.enableTimestamps then return false, msg, author, ... end
    if not eventsToHandle[event] then return false, msg, author, ... end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
        return false, msg, author, ...
    end

    local safeMsg = GetSafeText(msg)
    if not safeMsg or type(safeMsg) ~= "string" then
        return false, msg, author, ...
    end

    if safeMsg:find("|Hchatcopy:", 1, true) then
        return false, msg, author, ...
    end

    local timestampFormat = "%H:%M"
    if ns.Lists and ns.Lists.TimeFormats and db.timestampID then
        local formatData = ns.Lists.TimeFormats[db.timestampID]
        if formatData then
            if formatData.format == nil then
                return false, msg, author, ...
            end
            timestampFormat = formatData.format or timestampFormat
        end
    end

    local timestamp = db.useServerTime and GetServerTime() or time()
    local okBuild, finalMsg = pcall(function()
        local timeStr = date(timestampFormat, timestamp)
        local tsColor = db.timestampColor or "68ccef"
        local cacheId = nil
        if type(ns.SaveToCache) == "function" then
            cacheId = ns.SaveToCache(safeMsg)
        end

        local styledTime
        if cacheId then
            styledTime = string.format("|cff%s|Hchatcopy:%d|h[%s]|h|r", tsColor, cacheId, timeStr)
        else
            styledTime = string.format("|cff%s[%s]|r", tsColor, timeStr)
        end

        if db.timestampPost then
            return safeMsg .. " " .. styledTime
        end

        return styledTime .. " " .. safeMsg
    end)

    if not okBuild or type(finalMsg) ~= "string" then
        return false, msg, author, ...
    end

    return false, finalMsg, author, ...
end

-- =========================================================
-- 5. MODULE LIFECYCLE
-- =========================================================
function VisualsModule:OnEnable()
    if Chatify and Chatify.db and Chatify.db.profile then
        ns.EnforceRetailSafeMode(Chatify.db.profile)
    end

    local retailRestricted = IsRetailRestricted()

    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyStyle")

    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyStyle")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "ApplyStyle")

    self:SecureHook("FCF_OpenTemporaryWindow", function() ns.ApplyVisuals() end)
    self:SecureHook("FCF_OpenNewWindow", function() ns.ApplyVisuals() end)

    hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame)
        StyleFrame(chatFrame)
    end)

    if not retailRestricted then
        for _, info in pairs(ChatTypeInfo) do
            if type(info) == "table" then
                info.colorNameByClass = true
            end
        end
    end

    -- Віртуальний чат додає власні таймстемпи через Router, тому тут не дублюємо їх.
    -- На Retail 12.x використовуємо той самий safe message-event filter path, яким Prat-подібно обробляємо повідомлення.
    if not visualsFiltersInstalled and not (Chatify and Chatify.db and Chatify.db.profile and Chatify.db.profile.useVirtualChat) then
        for evt in pairs(eventsToHandle) do
            ChatFrame_AddMessageEventFilter(evt, TimestampFilter)
        end
        visualsFiltersInstalled = true
    end

    ns.ApplyVisuals()
end

function VisualsModule:PLAYER_LOGIN()
    ns.ApplyVisuals()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() ns.ApplyVisuals() end)
        C_Timer.After(1, function() ns.ApplyVisuals() end)
        C_Timer.After(3, function() ns.ApplyVisuals() end)
    end
end

function VisualsModule:ApplyStyle()
    ns.ApplyVisuals()
end