local addonName, ns = ...
local Chatify = ns.Chatify
local History = Chatify:NewModule("History", "AceEvent-3.0")

-- =========================================================
-- EVENT → TYPE MAP
-- =========================================================
local eventTypeMap = {
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
    CHAT_MSG_MONEY = "LOOT",
}

-- Modern Retail-safe history capture. This intentionally mirrors the ChatCopy
-- safe event policy: no whisper/BN/emote/achievement payload capture on secret-
-- value clients, and no Combat Log / Voice frames.
local retailSafeEventTypeMap = {
    CHAT_MSG_CHANNEL = "CHANNEL",
    CHAT_MSG_SAY = "SAY",
    CHAT_MSG_YELL = "YELL",
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_OFFICER = "GUILD",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "RAID",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "RAID",
    CHAT_MSG_SYSTEM = "SYSTEM",
    CHAT_MSG_LOOT = "LOOT",
    CHAT_MSG_MONEY = "LOOT",
}

-- =========================================================
-- STATE
-- =========================================================
local frameHistory = {}
local targetFrameCache = {}
local activeEventTypeMap = {}
local savedSeeded = false
local restoredToChatFrames = false
local unpack = table.unpack or unpack
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

local function GetHistoryDB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return nil
end

local function IsRetailSecretValueBuild()
    return type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() or false
end

local function GetActiveEventTypeMap()
    if IsRetailSecretValueBuild() then
        return retailSafeEventTypeMap
    end
    return eventTypeMap
end

local function IsHistoryEventAllowed(event)
    return activeEventTypeMap and activeEventTypeMap[event] ~= nil
end

local function GetSafeText(rawText)
    if type(ns.IsSecretValue) == "function" then
        local ok, secret = pcall(ns.IsSecretValue, rawText)
        if not ok or secret then
            return nil
        end
    end

    if type(ns.TryMakeSafeText) == "function" then
        local ok, safe = pcall(ns.TryMakeSafeText, rawText)
        if ok and type(safe) == "string" then
            return safe
        elseif not ok then
            return nil
        end
    end

    if type(rawText) == "string" then return rawText end
    if type(rawText) == "number" then return tostring(rawText) end
    return nil
end

local function NormalizeFrameID(chatFrameOrID)
    local chatID = tonumber(chatFrameOrID)
    if not chatID and chatFrameOrID and type(chatFrameOrID.GetID) == "function" then
        local ok, value = pcall(chatFrameOrID.GetID, chatFrameOrID)
        if ok then
            chatID = tonumber(value)
        end
    end

    if chatID and chatID > 0 and chatID ~= 2 then
        return chatID
    end
    return nil
end

local function IsFrameAllowed(chatFrame)
    if not chatFrame then
        return false
    end
    if type(ns.IsChatifyCopyFrameAllowed) == "function" then
        local ok, allowed = pcall(ns.IsChatifyCopyFrameAllowed, chatFrame)
        return ok and allowed == true
    end
    return NormalizeFrameID(chatFrame) ~= nil
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

local function InvalidateTargetFrameCache()
    targetFrameCache = {}
end

local function GetMaxChatWindows()
    local total = tonumber(NUM_CHAT_WINDOWS) or 10
    if type(ns.GetMaxChatWindows) == "function" then
        local ok, value = pcall(ns.GetMaxChatWindows)
        if ok and type(value) == "number" and value > 0 then
            total = value
        end
    end
    return math.max(1, math.min(total, 20))
end

local function GetTargetFrames(event)
    local cached = targetFrameCache[event]
    if cached then
        return cached
    end

    local frames = {}
    for i = 1, GetMaxChatWindows() do
        local frame = _G["ChatFrame"..i]
        if frame and IsFrameAllowed(frame) and type(frame.IsEventRegistered) == "function" then
            local ok, registered = pcall(frame.IsEventRegistered, frame, event)
            if ok and registered then
                frames[#frames + 1] = i
            end
        end
    end

    targetFrameCache[event] = frames
    return frames
end

local function AddWithLimit(tbl, message, limit)
    if type(tbl) ~= "table" or type(message) ~= "string" or message == "" then
        return
    end

    limit = tonumber(limit) or 250
    if limit < 1 then
        limit = 1
    elseif limit > 1000 then
        limit = 1000
    end

    tbl[#tbl + 1] = message

    local overflow = #tbl - limit
    if overflow > 16 then
        for i = 1, limit do
            tbl[i] = tbl[i + overflow]
        end
        for i = limit + 1, #tbl do
            tbl[i] = nil
        end
    elseif overflow > 0 then
        table.remove(tbl, 1)
    end
end

-- The history window follows the same timestamp setting as the chat frames.
--
-- This used to call date("%H:%M") directly, which ignored the configured format
-- outright: someone using HH:MM:SS saw their seconds disappear in the history
-- window and nowhere else. ns.FormatChatTimestamp resolves the setting in one
-- place and also honours the server-time preference.
local function FormatMessage(msg, author)
    local timestamp
    if type(ns.FormatChatTimestamp) == "function" then
        timestamp = ns.FormatChatTimestamp(GetHistoryDB())
    else
        local okDate, fallback = pcall(date, "%H:%M")
        timestamp = okDate and type(fallback) == "string" and fallback or nil
    end

    local prefix = ""
    if type(timestamp) == "string" and timestamp ~= "" then
        prefix = string.format("|cffaaaaaa[%s]|r ", timestamp)
    end

    if author and author ~= "" then
        local okAuthor, shortAuthor = pcall(function() return author:match("([^%-]+)") or author end)
        if not okAuthor or type(shortAuthor) ~= "string" then
            shortAuthor = tostring(author or "")
        end
        return string.format("%s|cffffd700[%s]|r: %s", prefix, shortAuthor, msg)
    end

    return string.format("%s%s", prefix, msg)
end

local function AddFrameHistory(chatID, message, limit)
    chatID = NormalizeFrameID(chatID)
    if not chatID then
        return
    end

    frameHistory[chatID] = frameHistory[chatID] or {}
    AddWithLimit(frameHistory[chatID], message, limit)
end

local function SeedFrameHistoryFromSaved()
    if savedSeeded then
        return
    end
    savedSeeded = true

    local db = GetHistoryDB()
    local limit = tonumber(db and db.historyLimit) or 250
    if type(ChatifyHistoryDB) ~= "table" then
        return
    end

    if type(ChatifyHistoryDB.frames) == "table" then
        for chatID, messages in pairs(ChatifyHistoryDB.frames) do
            chatID = NormalizeFrameID(chatID)
            if chatID and type(messages) == "table" then
                frameHistory[chatID] = frameHistory[chatID] or {}
                for _, msg in ipairs(messages) do
                    local safeMsg = GetSafeText(msg)
                    if safeMsg then
                        AddWithLimit(frameHistory[chatID], safeMsg, limit)
                    end
                end
            end
        end
        return
    end

    -- Legacy ChatifyHistoryDB format: grouped by chat type/channel. Import it into
    -- the per-frame store so the new History popup can still display older data.
    for typeKey, data in pairs(ChatifyHistoryDB) do
        if typeKey == "CHANNEL" and type(data) == "table" then
            for _, chatFrames in pairs(data) do
                if type(chatFrames) == "table" then
                    for chatID, messages in pairs(chatFrames) do
                        chatID = NormalizeFrameID(chatID)
                        if chatID and type(messages) == "table" then
                            for _, msg in ipairs(messages) do
                                local safeMsg = GetSafeText(msg)
                                if safeMsg then
                                    AddFrameHistory(chatID, safeMsg, limit)
                                end
                            end
                        end
                    end
                end
            end
        elseif type(data) == "table" and typeKey ~= "frames" then
            for chatID, messages in pairs(data) do
                chatID = NormalizeFrameID(chatID)
                if chatID and type(messages) == "table" then
                    for _, msg in ipairs(messages) do
                        local safeMsg = GetSafeText(msg)
                        if safeMsg then
                            AddFrameHistory(chatID, safeMsg, limit)
                        end
                    end
                end
            end
        end
    end
end

function ns.GetChatifyHistoryEntriesForFrame(chatFrame, maxLines)
    local db = GetHistoryDB()
    if not db or db.enableHistory == false then
        return nil
    end
    if not IsFrameAllowed(chatFrame) then
        return nil
    end

    SeedFrameHistoryFromSaved()

    local chatID
    if type(ns.GetChatifyCopyFrameID) == "function" then
        local ok, value = pcall(ns.GetChatifyCopyFrameID, chatFrame)
        if ok then
            chatID = NormalizeFrameID(value)
        end
    end
    chatID = chatID or NormalizeFrameID(chatFrame)
    if not chatID then
        return nil
    end

    local source = frameHistory[chatID]
    if type(source) ~= "table" or #source == 0 then
        return nil
    end

    local limit = tonumber(maxLines) or tonumber(db.historyLimit) or 250
    if limit < 1 then
        limit = 1
    elseif limit > 1000 then
        limit = 1000
    end

    local entries = {}
    local first = math.max(1, #source - limit + 1)
    for i = first, #source do
        entries[#entries + 1] = source[i]
    end
    return entries
end

-- =========================================================
-- EVENT HANDLER
-- =========================================================
function History:OnChatEvent(event, message, author, ...)
    local db = GetHistoryDB()
    if not db or db.enableHistory == false then return end
    if not IsHistoryEventAllowed(event) then return end

    if type(ns.ShouldBypassChatCaptureEvent) == "function" and ns.ShouldBypassChatCaptureEvent(event) then
        return
    end

    if type(ns.CanMutateChatPayload) == "function" then
        if not ns.CanMutateChatPayload(event, message, author, ...) then
            return
        end
    elseif type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(message, author, ...) then
        return
    end

    local safeMessage = GetSafeText(message)
    if not safeMessage then return end
    local safeAuthor = GetSafeText(author)

    local typeKey = activeEventTypeMap[event]
    if not typeKey then return end

    local targetFrames = GetTargetFrames(event)
    if #targetFrames == 0 then return end

    local limit = tonumber(db.historyLimit) or 250
    local okFormatted, fullMessage = pcall(FormatMessage, safeMessage, safeAuthor)
    if not okFormatted or type(fullMessage) ~= "string" then
        return
    end

    local channelName, channelID
    if event == "CHAT_MSG_CHANNEL" then
        local languageName, channelString, target, flags, unknown, channelNumber, channelBaseName = ...
        channelName = GetSafeText(channelBaseName) or GetSafeText(channelString) or GetSafeText(languageName)
        channelID = tonumber(channelNumber) or tonumber(unknown)
    end

    for _, chatID in ipairs(targetFrames) do
        chatID = NormalizeFrameID(chatID)
        if chatID then
            AddFrameHistory(chatID, fullMessage, limit)
        end
    end
end

-- =========================================================
-- SAVE HISTORY
-- =========================================================
-- The logout write.
--
-- This runs from PLAYER_LOGOUT, which is the single most dangerous place in an
-- addon to throw: the client is serialising SavedVariables at that moment, and an
-- error raised here can leave the file unwritten. Both ChatifyDB and
-- ChatifyHistoryDB live in that one file, so a fault while saving chat history
-- takes every setting with it - and it does so on every logout, which is exactly
-- what "my settings keep resetting" looks like from the outside.
--
-- Everything below is therefore written to be unable to throw: the whole body
-- runs inside SaveHistoryUnprotected, called through pcall, and each loop checks
-- that what it is about to iterate is really a table. Losing a session of chat
-- history is a small cost; losing the user's configuration is not.
-- SAVED_VARIABLES_TOO_LARGE.
--
-- The client fires this when an addon's SavedVariables file exceeds what it is
-- willing to write, and then it writes NOTHING - so the settings go with the
-- history, and they go again at every logout for as long as the file stays over
-- the line. That is the one failure mode that produces "my settings reset every
-- time I log out" while nothing in the addon resets anything.
--
-- Chat history is the only thing here that grows without bound in practice, so
-- the response is to cut it back hard and tell the user, rather than fail
-- silently again next time.
function History:SAVED_VARIABLES_TOO_LARGE(event, addon)
    if addon and addon ~= "Chatify" then
        return
    end

    local db = GetHistoryDB()
    if db then
        -- Well below any plausible limit, and applied to the profile so it
        -- survives into the next session rather than being undone at login.
        db.historyLimit = 50
    end

    frameHistory = {}
    ChatifyHistoryDB = { version = 2, savedAt = time(), frames = {} }

    local frame = DEFAULT_CHAT_FRAME
    if frame and type(frame.AddMessage) == "function" then
        pcall(frame.AddMessage, frame,
            "|cffffd200Chatify:|r " .. (type(ns.L) == "table" and ns.L["SavedVariables file was too large. Chat history has been cleared and the limit reduced to 50 lines so your settings can be saved."] or
            "SavedVariables file was too large. Chat history has been cleared and the limit reduced to 50 lines so your settings can be saved."))
    end
end

-- Rough byte estimate of what the history will occupy on disk. Used by
-- /chatifydb; deliberately approximate, since the point is spotting an order of
-- magnitude, not an exact figure.
function ns.EstimateHistorySize()
    local total = 0
    if type(ChatifyHistoryDB) ~= "table" then
        return 0
    end

    for _, messages in pairs(ChatifyHistoryDB.frames or {}) do
        if type(messages) == "table" then
            for index = 1, #messages do
                local value = messages[index]
                if type(value) == "string" then
                    -- The string, its quotes, the index and the surrounding
                    -- syntax the client writes around each entry.
                    total = total + #value + 16
                end
            end
        end
    end

    return total
end

function History:SaveHistory()
    if type(ns.SafeCall) == "function" then
        ns.SafeCall("History:SaveHistory", History.SaveHistoryUnprotected, self)
    else
        pcall(History.SaveHistoryUnprotected, self)
    end
end

function History:SaveHistoryUnprotected()
    local db = GetHistoryDB()
    if not db or db.enableHistory == false then return end
    SeedFrameHistoryFromSaved()

    local output = {
        version = 2,
        savedAt = time(),
        frames = {},
    }

    -- ChatRouter keeps its virtual-chat lines under ChatifyHistoryDB.Virtual.
    -- This function replaces ChatifyHistoryDB wholesale, so without carrying that
    -- branch across it was destroyed on every logout.
    if type(ChatifyHistoryDB) == "table" and type(ChatifyHistoryDB.Virtual) == "table" then
        output.Virtual = ChatifyHistoryDB.Virtual
    end

    -- CopyList rather than unpack: unpack on a long array raises "too many
    -- results to unpack", and the whole point here is that nothing throws.
    local function CopyList(messages)
        if type(messages) ~= "table" then
            return nil
        end
        local copy, count = {}, 0
        for index = 1, #messages do
            local value = messages[index]
            if type(value) == "string" then
                count = count + 1
                copy[count] = value
            end
        end
        if count == 0 then
            return nil
        end
        return copy
    end

    if type(frameHistory) == "table" then
        for chatID, messages in pairs(frameHistory) do
            chatID = NormalizeFrameID(chatID)
            local copy = chatID and CopyList(messages)
            if copy then
                output.frames[chatID] = copy
            end
        end
    end

    -- The legacy grouped format is no longer written.
    --
    -- Every message was stored twice - once under frames, once again under its
    -- chat type - and channel messages three times. The saved file was therefore
    -- two to three times larger than the data in it, which matters because an
    -- oversized SavedVariables file is refused by the client outright
    -- (SAVED_VARIABLES_TOO_LARGE) and then NOTHING is written, settings included.
    --
    -- Nothing is lost by dropping it: SeedFrameHistoryFromSaved still reads the
    -- legacy layout, so files written by older versions import normally.

    ChatifyHistoryDB = output
end

-- =========================================================
-- POPUP-ONLY HISTORY RESTORE GUARD
-- =========================================================
function History:RestoreHistory()
    -- History is popup-only. Do not replay saved lines into live Blizzard
    -- chat frames: that creates duplicate/noisy messages and is not how
    -- Prat/Chattynator-style history viewers behave. Saved lines are shown
    -- only through the Chatify History window and its per-chat tabs.
    restoredToChatFrames = true
end

-- =========================================================
-- INIT
-- =========================================================
function History:OnEnable()
    if Chatify and Chatify.db and Chatify.db.profile and type(ns.EnforceRetailSafeMode) == "function" then
        ns.EnforceRetailSafeMode(Chatify.db.profile)
    end

    if Chatify and Chatify.db and Chatify.db.profile and Chatify.db.profile.useVirtualChat then
        return
    end

    activeEventTypeMap = GetActiveEventTypeMap()

    for event in pairs(activeEventTypeMap) do
        if type(ns.RegisterEventIfSupported) == "function" then
            ns.RegisterEventIfSupported(self, event, "OnChatEvent")
        else
            pcall(self.RegisterEvent, self, event, "OnChatEvent")
        end
    end

    if type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "PLAYER_LOGOUT", "SaveHistory")
        ns.RegisterEventIfSupported(self, "SAVED_VARIABLES_TOO_LARGE", "SAVED_VARIABLES_TOO_LARGE")
        ns.RegisterEventIfSupported(self, "PLAYER_LEAVING_WORLD", "SaveHistory")
        ns.RegisterEventIfSupported(self, "UPDATE_CHAT_WINDOWS", InvalidateTargetFrameCache)
        ns.RegisterEventIfSupported(self, "UPDATE_FLOATING_CHAT_WINDOWS", InvalidateTargetFrameCache)
        ns.RegisterEventIfSupported(self, "CHANNEL_UI_UPDATE", InvalidateTargetFrameCache)
    else
        pcall(self.RegisterEvent, self, "PLAYER_LOGOUT", "SaveHistory")
        pcall(self.RegisterEvent, self, "SAVED_VARIABLES_TOO_LARGE", "SAVED_VARIABLES_TOO_LARGE")
        pcall(self.RegisterEvent, self, "PLAYER_LEAVING_WORLD", "SaveHistory")
        pcall(self.RegisterEvent, self, "UPDATE_CHAT_WINDOWS", InvalidateTargetFrameCache)
        pcall(self.RegisterEvent, self, "UPDATE_FLOATING_CHAT_WINDOWS", InvalidateTargetFrameCache)
        pcall(self.RegisterEvent, self, "CHANNEL_UI_UPDATE", InvalidateTargetFrameCache)
    end

    InvalidateTargetFrameCache()
    SeedFrameHistoryFromSaved()
    -- Keep history silent. It is stored for the History popup only and must
    -- never be written back into the visible chat frames on login/reload.
end

function History:OnDisable()
    self:UnregisterAllEvents()
    InvalidateTargetFrameCache()
end
