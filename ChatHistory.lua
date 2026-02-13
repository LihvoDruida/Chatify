local addonName, ns = ...
local Chatify = ns.Chatify
local History = Chatify:NewModule("History", "AceEvent-3.0")

-- =========================================================
-- EVENT → TYPE MAP
-- =========================================================
local eventTypeMap = {
    CHAT_MSG_SAY            = "SAY",
    CHAT_MSG_YELL           = "YELL",
    CHAT_MSG_GUILD          = "GUILD",
    CHAT_MSG_OFFICER        = "GUILD",
    CHAT_MSG_PARTY          = "PARTY",
    CHAT_MSG_PARTY_LEADER   = "PARTY",
    CHAT_MSG_RAID           = "RAID",
    CHAT_MSG_RAID_LEADER    = "RAID",
    CHAT_MSG_WHISPER        = "WHISPER",
    CHAT_MSG_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_CHANNEL        = "CHANNEL",
}

-- =========================================================
-- SAFE EVENT WHITELIST
-- =========================================================
-- Define explicitly which events are safe to process. 
-- Events like BN_WHISPER, MONSTER_YELL, etc. are excluded to avoid tainted string errors.
local eventsToHandle = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_CHANNEL = true,
}

-- =========================================================
-- STATE
-- =========================================================
local sessionHistory = {}

-- =========================================================
-- SAFETY HELPER
-- =========================================================
local function GetSafeText(rawText)
    if rawText == nil then return nil end
    if type(rawText) == "number" then return tostring(rawText) end
    if type(rawText) ~= "string" then return nil end

    -- Create a "clean" copy via pcall
    local ok, clean = pcall(string.format, "%s", rawText)
    if not ok then return nil end

    -- Check for empty string only inside pcall
    local nonEmptyOk, result = pcall(function()
        if clean == "" then return nil end
        return clean
    end)

    if nonEmptyOk then
        return result
    else
        return nil
    end
end

-- =========================================================
-- HELPERS
-- =========================================================
local function GetTargetFrames(event)
    local frames = {}
    for i = 1, NUM_CHAT_WINDOWS do
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
    local shortAuthor = author
    if shortAuthor then
        local sep = string.find(shortAuthor, "-")
        if sep then shortAuthor = shortAuthor:sub(1, sep - 1) end
    end

    if shortAuthor and shortAuthor ~= "" then
        return string.format("|cffaaaaaa[%s]|r |cffffd700[%s]|r: %s", timestamp, shortAuthor, msg)
    else
        return string.format("|cffaaaaaa[%s]|r %s", timestamp, msg)
    end
end

-- =========================================================
-- EVENT HANDLER
-- =========================================================
function History:OnChatEvent(event, message, author, ...)
    local db = Chatify.db.profile
    if not db.enableHistory then return end

    -- Check if the event is in our safe whitelist before doing ANYTHING else.
    -- This prevents processing tainted events like BN_WHISPER entirely.
    if not eventsToHandle[event] then return end

    local safeMessage = GetSafeText(message)
    if not safeMessage then return end

    local safeAuthor = GetSafeText(author)

    local typeKey = eventTypeMap[event]
    if not typeKey then return end

    local targetFrames = GetTargetFrames(event)
    if #targetFrames == 0 then return end

    local limit = db.historyLimit or 50
    local fullMessage = FormatMessage(safeMessage, safeAuthor)

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
-- SAVE
-- =========================================================
function History:SaveHistory()
    local db = Chatify.db.profile
    if not db.enableHistory then return end
    ChatifyHistoryDB = {}

    for typeKey, data in pairs(sessionHistory) do
        if typeKey == "CHANNEL" then
            ChatifyHistoryDB.CHANNEL = {}
            for channelName, channelData in pairs(data) do
                ChatifyHistoryDB.CHANNEL[channelName] = {}
                for chatID, messages in pairs(channelData.frames) do
                    if #messages > 0 then
                        ChatifyHistoryDB.CHANNEL[channelName][chatID] = CopyTable(messages)
                    end
                end
            end
        else
            ChatifyHistoryDB[typeKey] = {}
            for chatID, messages in pairs(data) do
                if #messages > 0 then
                    ChatifyHistoryDB[typeKey][chatID] = CopyTable(messages)
                end
            end
        end
    end
end

-- =========================================================
-- RESTORE
-- =========================================================
function History:RestoreHistory()
    local db = Chatify.db.profile
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
                if GetChannelName(channelName) then
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
            pcall(frame.AddMessage, frame, "──────── Chat History ────────", 0.6, 0.6, 0.6)
            for _, msg in ipairs(messages) do
                pcall(function()
                    if db.historyAlpha then
                        frame:AddMessage("|cff888888"..msg.."|r")
                    else
                        frame:AddMessage(msg)
                    end
                end)
            end
        end
    end
end

-- =========================================================
-- INIT
-- =========================================================
function History:OnEnable()
    for event in pairs(eventTypeMap) do
        self:RegisterEvent(event, "OnChatEvent")
    end
    self:RegisterEvent("PLAYER_LOGOUT", "SaveHistory")
    self:RegisterEvent("PLAYER_LEAVING_WORLD", "SaveHistory")
    C_Timer.After(1, function() pcall(function() self:RestoreHistory() end) end)
end