local addonName, ns = ...
local Chatify = ns.Chatify
local History = Chatify:NewModule("History", "AceEvent-3.0")

-- =========================================================
-- EVENT → TYPE MAP
-- =========================================================
local eventTypeMap = {
    -- Safe user chat channels only.
    -- Do not register monster/emote/achievement events on Retail 12.x,
    -- because merely touching those payloads can still taint Blizzard's
    -- HistoryKeeper path even if we later bail out.
    CHAT_MSG_CHANNEL = "CHANNEL",
    CHAT_MSG_SAY = "SAY",
    CHAT_MSG_YELL = "YELL",
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_BN_WHISPER = "WHISPER",
    CHAT_MSG_BN_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_BN_CONVERSATION = "WHISPER",
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_GUILD_MOTD = "GUILD",
    CHAT_MSG_OFFICER = "GUILD",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "RAID",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "RAID",
    CHAT_MSG_SYSTEM = "SYSTEM",
    CHAT_MSG_AFK = "SYSTEM",
    CHAT_MSG_DND = "SYSTEM",
    CHAT_MSG_COMMUNITIES_CHANNEL = "COMMUNITY",
    CHAT_MSG_LOOT = "LOOT",
}

-- =========================================================
-- SAFE EVENT WHITELIST
-- =========================================================
local eventsToHandle = {}
for event,_ in pairs(eventTypeMap) do
    eventsToHandle[event] = true
end

-- =========================================================
-- STATE
-- =========================================================
local sessionHistory = {}
local unpack = table.unpack or unpack
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

local function GetHistoryDB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return nil
end

local function AppendRestoredMessage(frame, text, ...)
    if not frame then
        return
    end

    if type(frame.BackFillMessage) == "function" then
        local ok = pcall(frame.BackFillMessage, frame, text, ...)
        if ok then
            return
        end
    end

    if type(frame.AddMessage) == "function" then
        pcall(frame.AddMessage, frame, text, ...)
    end
end

-- =========================================================
-- SAFE TEXT HELPER
-- =========================================================
local function GetSafeText(rawText)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(rawText)
    end
    if type(rawText) == "string" then return rawText end
    if type(rawText) == "number" then return tostring(rawText) end
    return nil
end

-- =========================================================
-- CHAT HELPERS
-- =========================================================
local function GetTargetFrames(event)
    local frames = {}
    for i = 1, (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame"..i]
        if frame and frame:IsEventRegistered(event) then
            table.insert(frames, i)
        end
    end
    return frames
end

local function AddWithLimit(tbl, message, limit)
    table.insert(tbl, message)
    if #tbl > limit then
        table.remove(tbl, 1)
    end
end

local function FormatMessage(msg, author)
    local timestamp = date("%H:%M")
    if author and author ~= "" then
        local shortAuthor = author:match("([^%-]+)") or author
        return string.format("|cffaaaaaa[%s]|r |cffffd700[%s]|r: %s", timestamp, shortAuthor, msg)
    else
        return string.format("|cffaaaaaa[%s]|r %s", timestamp, msg)
    end
end

-- =========================================================
-- EVENT HANDLER
-- =========================================================
function History:OnChatEvent(event, message, author, ...)
    local db = GetHistoryDB()
    if not db then return end
    if not db.enableHistory then return end

    if type(ns.IsSecretValue) == "function" and (ns.IsSecretValue(message) or ns.IsSecretValue(author)) then
        return
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(message, author, ...) then
        return
    end

    -- Ігноруємо події, які не в whitelist
    if not eventsToHandle[event] then return end

    -- Безпечне повідомлення та автор
    local safeMessage = GetSafeText(message)
    if not safeMessage then return end
    local safeAuthor = GetSafeText(author)

    local typeKey = eventTypeMap[event]
    if not typeKey then return end

    local targetFrames = GetTargetFrames(event)
    if #targetFrames == 0 then return end

    local limit = db.historyLimit or 50
    local okFormatted, fullMessage = pcall(FormatMessage, safeMessage, safeAuthor)
    if not okFormatted or type(fullMessage) ~= "string" then
        return
    end

    -- CHANNEL
    if event == "CHAT_MSG_CHANNEL" then
        local channelName, _, channelID = ...
        local safeChannelName = GetSafeText(channelName)
        if not safeChannelName or not channelID then return end

        sessionHistory.CHANNEL = sessionHistory.CHANNEL or {}
        sessionHistory.CHANNEL[safeChannelName] = sessionHistory.CHANNEL[safeChannelName] or {id = channelID, frames = {}}
        local channelData = sessionHistory.CHANNEL[safeChannelName]
        channelData.id = channelID

        for _, chatID in ipairs(targetFrames) do
            if chatID ~= 2 then
                channelData.frames[chatID] = channelData.frames[chatID] or {}
                AddWithLimit(channelData.frames[chatID], fullMessage, limit)
            end
        end
        return
    end

    -- NORMAL TYPES
    sessionHistory[typeKey] = sessionHistory[typeKey] or {}
    for _, chatID in ipairs(targetFrames) do
        if chatID ~= 2 then
            sessionHistory[typeKey][chatID] = sessionHistory[typeKey][chatID] or {}
            AddWithLimit(sessionHistory[typeKey][chatID], fullMessage, limit)
        end
    end
end

-- =========================================================
-- SAVE HISTORY
-- =========================================================
function History:SaveHistory()
    local db = GetHistoryDB()
    if not db then return end
    if not db.enableHistory then return end
    ChatifyHistoryDB = {}

    for typeKey, data in pairs(sessionHistory) do
        if typeKey == "CHANNEL" then
            ChatifyHistoryDB.CHANNEL = {}
            for channelName, channelData in pairs(data) do
                ChatifyHistoryDB.CHANNEL[channelName] = {}
                for chatID, messages in pairs(channelData.frames) do
                    if #messages > 0 then
                        ChatifyHistoryDB.CHANNEL[channelName][chatID] = {unpack(messages)}
                    end
                end
            end
        else
            ChatifyHistoryDB[typeKey] = {}
            for chatID, messages in pairs(data) do
                if #messages > 0 then
                    ChatifyHistoryDB[typeKey][chatID] = {unpack(messages)}
                end
            end
        end
    end
end

-- =========================================================
-- RESTORE HISTORY
-- =========================================================
function History:RestoreHistory()
    local db = GetHistoryDB()
    if not db then return end
    if not db.enableHistory or not ChatifyHistoryDB then return end
    local buffer = {}

    local function addToBuffer(chatID, messages)
        if not messages or #messages == 0 then return end
        buffer[chatID] = buffer[chatID] or {}
        for _, msg in ipairs(messages) do
            local safeMsg = GetSafeText(msg)
            if safeMsg then table.insert(buffer[chatID], safeMsg) end
        end
    end

    for typeKey, data in pairs(ChatifyHistoryDB) do
        if typeKey == "CHANNEL" then
            for channelName, chatFrames in pairs(data) do
                local channelID = GetChannelName(channelName)
                if channelID and channelID > 0 then
                    for chatID, messages in pairs(chatFrames) do
                        addToBuffer(chatID, messages)
                    end
                end
            end
        else
            for chatID, messages in pairs(data) do
                addToBuffer(chatID, messages)
            end
        end
    end

    for chatID, messages in pairs(buffer) do
        local frame = _G["ChatFrame"..chatID]
        if frame and chatID ~= 2 then
            AppendRestoredMessage(frame, L("------------------------------------------"), 0.6, 0.6, 0.6)
            for _, msg in ipairs(messages) do
                if db.historyAlpha then
                    AppendRestoredMessage(frame, "|cff888888"..msg.."|r")
                else
                    AppendRestoredMessage(frame, msg)
                end
            end
            AppendRestoredMessage(frame, L("-------------- Chat History --------------"), 0.6, 0.6, 0.6)
            if type(frame.ResetAllFadeTimes) == "function" then
                pcall(frame.ResetAllFadeTimes, frame)
            end
        end
    end
end

-- =========================================================
-- INIT
-- =========================================================
function History:OnEnable()
    local retailRestricted = false
    if Chatify and Chatify.db and Chatify.db.profile then
        ns.EnforceRetailSafeMode(Chatify.db.profile)
        retailRestricted = type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() or false
    end

    -- Retail 12.x: custom history tracking through standalone chat events is not
    -- equivalent to Prat's full MessageEventHandler path and can taint Blizzard's
    -- protected HistoryKeeper tables. Keep this module disabled on modern Retail.
    if retailRestricted then
        return
    end

    if Chatify and Chatify.db and Chatify.db.profile and Chatify.db.profile.useVirtualChat then
        return
    end
    for event in pairs(eventTypeMap) do
        if type(ns.RegisterEventIfSupported) == "function" then
            ns.RegisterEventIfSupported(self, event, "OnChatEvent")
        else
            self:RegisterEvent(event, "OnChatEvent")
        end
    end

    if type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "PLAYER_LOGOUT", "SaveHistory")
        ns.RegisterEventIfSupported(self, "PLAYER_LEAVING_WORLD", "SaveHistory")
    else
        self:RegisterEvent("PLAYER_LOGOUT", "SaveHistory")
        self:RegisterEvent("PLAYER_LEAVING_WORLD", "SaveHistory")
    end
    C_Timer.After(1, function() pcall(function() self:RestoreHistory() end) end)
end
