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
-- STATE (SESSION ONLY)
-- =========================================================

-- STRUCTURE:
-- sessionHistory = {
--   SAY = {
--       [chatFrameID] = { msg1, msg2 }
--   },
--   CHANNEL = {
--       ["Trade"] = {
--           id = 2,
--           frames = {
--               [chatFrameID] = { msg1, msg2 }
--           }
--       }
--   }
-- }

local sessionHistory = {}

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

-- =========================================================
-- EVENT HANDLER
-- =========================================================

function History:OnChatEvent(event, message, author, ...)
    local db = Chatify.db.profile
    if not db.enableHistory then return end
    if type(message) ~= "string" or message == "" then return end

    local typeKey = eventTypeMap[event]
    if not typeKey then return end

    local targetFrames = GetTargetFrames(event)
    if #targetFrames == 0 then return end

    local limit = db.historyLimit or 50

    -- =====================================================
    -- CHANNEL (HYBRID ID + NAME)
    -- =====================================================
    if event == "CHAT_MSG_CHANNEL" then
        local channelName, _, channelID = ...

        if not channelName or not channelID then return end

        sessionHistory.CHANNEL = sessionHistory.CHANNEL or {}

        if not sessionHistory.CHANNEL[channelName] then
            sessionHistory.CHANNEL[channelName] = {
                id = channelID,
                frames = {}
            }
        end

        local channelData = sessionHistory.CHANNEL[channelName]
        channelData.id = channelID -- update if changed

        for _, chatID in ipairs(targetFrames) do
            if chatID ~= 2 then -- ignore combat log
                channelData.frames[chatID] =
                    channelData.frames[chatID] or {}

                AddWithLimit(
                    channelData.frames[chatID],
                    message,
                    limit
                )
            end
        end

        return
    end

    -- =====================================================
    -- NORMAL TYPES (SAY, GUILD, PARTY, RAID, etc.)
    -- =====================================================
    sessionHistory[typeKey] = sessionHistory[typeKey] or {}

    for _, chatID in ipairs(targetFrames) do
        if chatID ~= 2 then
            sessionHistory[typeKey][chatID] =
                sessionHistory[typeKey][chatID] or {}

            AddWithLimit(
                sessionHistory[typeKey][chatID],
                message,
                limit
            )
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

        -- CHANNEL SAVE (by NAME only)
        if typeKey == "CHANNEL" then
            ChatifyHistoryDB.CHANNEL = {}

            for channelName, channelData in pairs(data) do
                ChatifyHistoryDB.CHANNEL[channelName] = {}

                for chatID, messages in pairs(channelData.frames) do
                    if #messages > 0 then
                        ChatifyHistoryDB.CHANNEL[channelName][chatID] =
                            CopyTable(messages)
                    end
                end
            end

        -- NORMAL SAVE
        else
            ChatifyHistoryDB[typeKey] = {}

            for chatID, messages in pairs(data) do
                if #messages > 0 then
                    ChatifyHistoryDB[typeKey][chatID] =
                        CopyTable(messages)
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
    if not db.enableHistory then return end
    if not ChatifyHistoryDB then return end

    for typeKey, data in pairs(ChatifyHistoryDB) do

        -- =================================================
        -- CHANNEL RESTORE (HYBRID CHECK)
        -- =================================================
        if typeKey == "CHANNEL" then

            for channelName, chatFrames in pairs(data) do

                -- Only restore if player is currently in this channel
                local channelID = GetChannelName(channelName)
                if channelID then

                    for chatID, messages in pairs(chatFrames) do
                        local frame = _G["ChatFrame"..chatID]

                        if frame and chatID ~= 2 then
                            frame:AddMessage(
                                "──────── "..channelName.." History ────────",
                                0.6, 0.6, 0.6
                            )

                            for _, msg in ipairs(messages) do
                                if db.historyAlpha then
                                    frame:AddMessage("|cff888888"..msg.."|r")
                                else
                                    frame:AddMessage(msg)
                                end
                            end
                        end
                    end
                end
            end

        -- =================================================
        -- NORMAL RESTORE
        -- =================================================
        else
            for chatID, messages in pairs(data) do
                local frame = _G["ChatFrame"..chatID]

                if frame and chatID ~= 2 then
                    frame:AddMessage(
                        "──────── "..typeKey.." History ────────",
                        0.6, 0.6, 0.6
                    )

                    for _, msg in ipairs(messages) do
                        if db.historyAlpha then
                            frame:AddMessage("|cff888888"..msg.."|r")
                        else
                            frame:AddMessage(msg)
                        end
                    end
                end
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

    C_Timer.After(1, function()
        self:RestoreHistory()
    end)
end
