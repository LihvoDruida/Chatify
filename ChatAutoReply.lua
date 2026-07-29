local addonName, ns = ...
local Chatify = ns.Chatify
local AutoReply = Chatify:NewModule("AutoReply", "AceEvent-3.0", "AceConsole-3.0")
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

local C_Timer = C_Timer
local GetTime = GetTime
local UnitName = UnitName
local UnitIsAFK = UnitIsAFK
local IsInInstance = IsInInstance
local IsInGuild = IsInGuild
local UnitIsInMyGuild = UnitIsInMyGuild
local strsplit = strsplit
local pairs = pairs
local type = type
local tonumber = tonumber
local tostring = tostring
local pcall = pcall
local math_floor = math.floor
local Ambiguate = Ambiguate
local string_find = string.find
local string_format = string.format
local string_lower = string.lower

-- GetTime() is client uptime and resets to ~0 on every relog, so it MUST NOT be
-- written into SavedVariables (db.char): a stored cooldown/pending timestamp would
-- become larger than the fresh uptime and the "now - stored" delta goes negative,
-- permanently blocking auto-reply and preventing stale-state pruning. Wall clock
-- (time(), epoch seconds) is stable across sessions and is used for all persisted
-- timestamps below. GetTime() is kept only for in-memory, same-session throttling.
local WallClock = time
local activityTicker = nil
local lastGuildReplyTime = 0
local GUILD_REPLY_COOLDOWN = 600
local STALE_PENDING_SECONDS = 6 * 60 * 60
local STALE_REPLY_SECONDS = 7 * 24 * 60 * 60
local ACTIVITY_IDLE_INTERVAL = 3
local ACTIVITY_ACTIVE_INTERVAL = 1
local lastActivityMessage = nil
local lastActivityActive = false
local lastActivityCheckAt = 0

local function DB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return nil
end

local function CharDB()
    if Chatify and Chatify.db and Chatify.db.char then
        return Chatify.db.char
    end
    return nil
end

local function EnsureCharState()
    local db = CharDB()
    if not db then
        return nil
    end

    db.pendingWhispers = db.pendingWhispers or {}
    db.pendingGuildMentions = db.pendingGuildMentions or {}
    db.wasInActivity = db.wasInActivity or false
    db.lastReplyTime = db.lastReplyTime or {}
    return db
end

local function Trim(value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:match("^%s*(.-)%s*$")
    if value == "" then
        return nil
    end

    return value
end

local function SafeChatText(value)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(value)
    end
    if type(ns.IsSecretValue) == "function" and ns.IsSecretValue(value) then
        return nil
    end
    if type(value) == "string" then
        return Trim(value)
    end
    return nil
end

local function CanAccess(...)
    -- Accessibility alone is not enough: a value can be readable and still be a
    -- secret string, which blows up on the first concatenation or :match(). Check
    -- both, in the same order the filter modules do.
    if type(ns.HasSecretChatValue) == "function" then
        local ok, hasSecret = pcall(ns.HasSecretChatValue, ...)
        if not ok or hasSecret then
            return false
        end
    end

    if type(ns.CanAccessChatValue) == "function" then
        local ok, accessible = pcall(ns.CanAccessChatValue, ...)
        return ok and accessible and true or false
    end

    return true
end

local function PlayerName()
    return UnitName("player")
end

local function NormalizePlayerName(name, ambiguity)
    local safeName = SafeChatText(name)
    if type(safeName) ~= "string" or safeName == "" then
        return nil
    end

    if type(Ambiguate) == "function" then
        local ok, result = pcall(Ambiguate, safeName, ambiguity or "none")
        if ok and type(result) == "string" and result ~= "" then
            return result
        end
    end

    return select(1, strsplit("-", safeName))
end

local function IsPlayerSender(sender)
    local playerName = PlayerName()
    local safeSender = SafeChatText(sender)
    if type(playerName) ~= "string" or playerName == "" or type(safeSender) ~= "string" or safeSender == "" then
        return false
    end

    local shortSender = NormalizePlayerName(safeSender, "none") or safeSender
    local shortPlayer = NormalizePlayerName(playerName, "none") or playerName
    return shortSender == shortPlayer
end

local function MakeStorageKey(sender, isBNet)
    if isBNet then
        if not CanAccess(sender) then
            return nil
        end
        local id = tonumber(sender)
        if not id then
            return nil
        end
        return "BN:" .. id
    end

    local safeSender = SafeChatText(sender)
    if type(safeSender) ~= "string" or safeSender == "" then
        return nil
    end
    return safeSender
end

local function CanSendAddonChat()
    if type(ns.CanSendAddonChat) == "function" then
        return ns.CanSendAddonChat()
    end
    return true
end

local function SendBNetMessage(accountID, message)
    if not accountID or type(message) ~= "string" or message == "" then
        return false
    end

    -- 12.0+ blocks addon-initiated whispers during chat messaging lockdown
    -- (encounters/M+/PvP) with ADDON_ACTION_BLOCKED. Skip silently instead of
    -- triggering the Blizzard error popup; the pending-return path still fires later.
    if not CanSendAddonChat() then
        return false
    end

    if type(BNSendWhisper) == "function" then
        local ok = pcall(BNSendWhisper, accountID, message)
        if ok then
            return true
        end
    end

    if C_BattleNet and C_BattleNet.SendAccountMessage then
        local ok = pcall(C_BattleNet.SendAccountMessage, accountID, message)
        return ok
    end

    return false
end

local function SendWhisper(target, message)
    if type(target) ~= "string" or target == "" or type(message) ~= "string" or message == "" then
        return false
    end

    if not CanSendAddonChat() then
        return false
    end

    target = NormalizePlayerName(target, "none") or target
    local ok = pcall(SendChatMessage, message, "WHISPER", nil, target)
    return ok
end

local function NormalizeQueueWaitSeconds(value)
    local num = tonumber(value)
    if not num or num <= 0 then
        return 0
    end
    if num >= 1000 then
        return math_floor(num / 1000)
    end
    return math_floor(num)
end

local function GetModernBattlegroundQueueInfo()
    if not C_PvP then
        return false, 0, nil
    end

    if type(C_PvP.GetActiveMatchState) == "function" then
        local ok, state = pcall(C_PvP.GetActiveMatchState)
        if ok and type(state) == "table" then
            local status = state.status or state.queueStatus
            if status == "queued" or status == "confirm" then
                local mapName = SafeChatText(state.mapName or state.name) or "battleground"
                local waitSeconds = NormalizeQueueWaitSeconds(state.estimatedWaitTimeSeconds or state.waitTime or state.estimatedWaitTime)
                return true, math_floor(waitSeconds / 60), mapName
            end
        end
    end

    if type(C_PvP.GetQueueState) == "function" then
        for index = 1, 4 do
            local ok, info = pcall(C_PvP.GetQueueState, index)
            if ok and type(info) == "table" then
                local status = info.status or info.queueStatus
                if status == "queued" or status == "confirm" then
                    local mapName = SafeChatText(info.mapName or info.name) or "battleground"
                    local waitSeconds = NormalizeQueueWaitSeconds(info.estimatedWaitTimeSeconds or info.waitTime or info.estimatedWaitTime)
                    return true, math_floor(waitSeconds / 60), mapName
                end
            end
        end
    end

    return false, 0, nil
end

local function GetQueueInfo()
    if type(GetLFGQueueStats) == "function" then
        local hasData, _, _, _, _, _, _, _, _, _, instanceName, _, _, _, _, myWait = GetLFGQueueStats(LE_LFG_CATEGORY_LFD)
        if hasData and myWait and myWait > 0 then
            return true, math_floor(myWait / 60), instanceName or "instance"
        end

        hasData, _, _, _, _, _, _, _, _, _, instanceName, _, _, _, _, myWait = GetLFGQueueStats(LE_LFG_CATEGORY_RF)
        if hasData and myWait and myWait > 0 then
            return true, math_floor(myWait / 60), instanceName or "raid"
        end
    end

    local okModern, waitMinutesModern, mapNameModern = GetModernBattlegroundQueueInfo()
    if okModern then
        return true, waitMinutesModern, mapNameModern
    end

    if type(GetBattlefieldStatus) == "function" then
        local maxQueues = 3
        if type(GetMaxBattlefieldID) == "function" then
            local ok, count = pcall(GetMaxBattlefieldID)
            if ok and type(count) == "number" and count > 0 then
                maxQueues = count
            end
        end

        for index = 1, maxQueues do
            local ok, status, mapName, _, _, _, _, legacyWait = pcall(GetBattlefieldStatus, index)
            if ok and (status == "queued" or status == "confirm") then
                local estimatedWaitTime = legacyWait
                if type(GetBattlefieldEstimatedWaitTime) == "function" then
                    local okWait, waitTime = pcall(GetBattlefieldEstimatedWaitTime, index)
                    if okWait and type(waitTime) == "number" and waitTime > 0 then
                        estimatedWaitTime = waitTime
                    end
                end

                local waitSeconds = NormalizeQueueWaitSeconds(estimatedWaitTime)
                return true, math_floor(waitSeconds / 60), SafeChatText(mapName) or "battleground"
            end
        end
    end

    return false, 0, nil
end


local function PruneCharState()
    local char = EnsureCharState()
    if not char then
        return
    end

    -- Persisted timestamps are wall-clock (epoch); prune against wall clock too.
    local now = WallClock()
    local cutoffPending = now - STALE_PENDING_SECONDS
    local cutoffReplies = now - STALE_REPLY_SECONDS

    for key, data in pairs(char.pendingWhispers) do
        if type(data) ~= "table" or type(data.time) ~= "number" or data.time < cutoffPending then
            char.pendingWhispers[key] = nil
        end
    end

    for key, data in pairs(char.pendingGuildMentions) do
        if type(data) ~= "table" or type(data.time) ~= "number" or data.time < cutoffPending then
            char.pendingGuildMentions[key] = nil
        end
    end

    for key, timestamp in pairs(char.lastReplyTime) do
        if type(timestamp) ~= "number" or timestamp < cutoffReplies then
            char.lastReplyTime[key] = nil
        end
    end
end

local function GetBNetPresenceID(...)
    -- The BNet sender presence id is arg13 of the CHAT_MSG_* payload. Prefer it
    -- explicitly; 12.1.0 appended a trailing `discordInfo` field to every
    -- CHAT_MSG_* event, so a blind "first positive number" scan is unreliable.
    local presenceID = select(13, ...)
    if type(presenceID) == "number" and presenceID > 0 and CanAccess(presenceID) then
        return presenceID
    end

    -- Fallback for older/edge payloads only: use the first positive number, but
    -- ignore obviously non-id small integers used as language/flags at the front.
    local count = select("#", ...)
    for i = 1, count do
        local value = select(i, ...)
        if type(value) == "number" and value > 1000 and CanAccess(value) then
            return value
        end
    end

    return nil
end

local function GetCurrentActivity(forceRefresh)
    local db = DB()
    if not db or not db.autoReply then
        return nil, false
    end

    local now = GetTime()
    local refreshInterval = lastActivityActive and ACTIVITY_ACTIVE_INTERVAL or ACTIVITY_IDLE_INTERVAL
    if not forceRefresh and lastActivityCheckAt > 0 and (now - lastActivityCheckAt) < refreshInterval then
        return lastActivityMessage, lastActivityActive
    end

    local ok, message, active = pcall(function()
        local cfg = db.autoReply
        local isAFK = UnitIsAFK("player")
        local inQueue, waitMinutes, queueName = GetQueueInfo()
        local inInstance, instanceType = IsInInstance()
        local inDungeon = inInstance and (instanceType == "party" or instanceType == "scenario")
        local inRaid = inInstance and instanceType == "raid"
        local inPvP = inInstance and (instanceType == "pvp" or instanceType == "arena")

        if cfg.busyMode and cfg.busyMessage and cfg.busyMessage ~= "" then
            return cfg.busyMessage, true
        elseif isAFK and cfg.afkMessage and cfg.afkMessage ~= "" then
            return cfg.afkMessage, true
        elseif inDungeon and cfg.dungeonMessage and cfg.dungeonMessage ~= "" then
            return cfg.dungeonMessage, true
        elseif inRaid and cfg.raidMessage and cfg.raidMessage ~= "" then
            return cfg.raidMessage, true
        elseif inPvP and cfg.pvpMessage and cfg.pvpMessage ~= "" then
            return cfg.pvpMessage, true
        elseif inQueue and cfg.queueMessage and cfg.queueMessage ~= "" then
            local formatted = cfg.queueMessage
            if string_find(formatted, "%s", 1, true) then
                formatted = string_format(formatted, waitMinutes)
            else
                formatted = formatted .. " " .. waitMinutes
            end
            if queueName and queueName ~= "" then
                formatted = formatted .. " (" .. queueName .. ")"
            end
            return formatted, true
        end

        return nil, false
    end)

    if ok then
        lastActivityCheckAt = now
        lastActivityMessage = message
        lastActivityActive = active and true or false
        return lastActivityMessage, lastActivityActive
    end

    lastActivityCheckAt = now
    lastActivityMessage = nil
    lastActivityActive = false
    return nil, false
end

local function IsAddonLikeWhisper(messageBody)
    local safe = SafeChatText(messageBody)
    if type(safe) ~= "string" or safe == "" then
        return false
    end
    return safe:find("^<") ~= nil or safe:find("^LVBM") ~= nil
end

local function IsAllowedSender(sender, isBNet)
    local db = DB()
    if not db or not db.autoReply or not db.autoReply.onlyFriends then
        return true
    end

    if isBNet then
        return true
    end

    local safeSender = SafeChatText(sender)
    if type(safeSender) ~= "string" or safeSender == "" then
        return false
    end

    local shortName = NormalizePlayerName(safeSender, "none") or safeSender

    if C_FriendList and C_FriendList.IsFriend then
        local ok, isFriend = pcall(C_FriendList.IsFriend, safeSender)
        if ok and isFriend then
            return true
        end
        ok, isFriend = pcall(C_FriendList.IsFriend, shortName)
        if ok and isFriend then
            return true
        end
    end

    if IsInGuild() then
        local ok, inGuild = pcall(UnitIsInMyGuild, safeSender)
        if ok and inGuild then
            return true
        end
        ok, inGuild = pcall(UnitIsInMyGuild, shortName)
        if ok and inGuild then
            return true
        end
    end

    return false
end

local function TrackPending(storageKey, isGuildMention)
    local char = EnsureCharState()
    if not char or type(storageKey) ~= "string" then
        return
    end

    local bucket = isGuildMention and char.pendingGuildMentions or char.pendingWhispers
    bucket[storageKey] = bucket[storageKey] or { count = 0, time = 0 }
    bucket[storageKey].count = (bucket[storageKey].count or 0) + 1
    bucket[storageKey].time = WallClock()
end

local function RemovePending(sender, isBNet)
    local char = EnsureCharState()
    if not char then
        return
    end

    if isBNet then
        local key = MakeStorageKey(sender, true)
        if key then
            char.pendingWhispers[key] = nil
            char.pendingGuildMentions[key] = nil
        end
        return
    end

    local safeTarget = SafeChatText(sender)
    if type(safeTarget) ~= "string" or safeTarget == "" then
        return
    end

    local shortName = NormalizePlayerName(safeTarget, "none")
    char.pendingWhispers[safeTarget] = nil
    char.pendingGuildMentions[safeTarget] = nil
    if shortName then
        char.pendingWhispers[shortName] = nil
        char.pendingGuildMentions[shortName] = nil
    end
end

local function IsPlayerMentioned(message)
    local safeMessage = SafeChatText(message)
    local playerName = PlayerName()
    if type(safeMessage) ~= "string" or safeMessage == "" or type(playerName) ~= "string" then
        return false
    end

    local ok, found = pcall(function()
        return string_find(string_lower(safeMessage), string_lower(playerName), 1, true) ~= nil
    end)
    return ok and found or false
end

local function SendGuildAutoReply(sender)
    local db = DB()
    if not db or not db.autoReply or not db.autoReply.guildReplyEnabled then
        return
    end

    local safeSender = SafeChatText(sender)
    if type(safeSender) ~= "string" or safeSender == "" then
        return
    end

    local message, active = GetCurrentActivity()
    if not active or type(message) ~= "string" or message == "" then
        return
    end

    local now = GetTime()
    TrackPending(safeSender, true)

    if (now - lastGuildReplyTime) < GUILD_REPLY_COOLDOWN then
        return
    end

    if not CanSendAddonChat() then
        return
    end

    if pcall(SendChatMessage, message, "GUILD") then
        lastGuildReplyTime = now
    end
end

local function SendAutoReply(sender, isBNet, messageBody)
    local db = DB()
    local char = EnsureCharState()
    if not db or not char or not db.autoReply or not db.autoReply.enabled then
        return
    end

    if IsAddonLikeWhisper(messageBody) then
        return
    end

    if not IsAllowedSender(sender, isBNet) then
        return
    end

    local storageKey = MakeStorageKey(sender, isBNet)
    if not storageKey then
        return
    end

    local now = WallClock()
    local cooldownSec = (tonumber(db.autoReply.cooldown) or 5) * 60
    local lastReplyTime = char.lastReplyTime or {}
    char.lastReplyTime = lastReplyTime

    -- A stored value that is somehow in the future (e.g. a legacy uptime-based
    -- timestamp from before the wall-clock migration) is treated as expired.
    local last = lastReplyTime[storageKey]
    if last and last <= now and (now - last) < cooldownSec then
        return
    end

    local messageToSend, active = GetCurrentActivity()
    if not active or type(messageToSend) ~= "string" or messageToSend == "" then
        return
    end

    TrackPending(storageKey, false)

    local sent = false
    if isBNet then
        local id = tonumber(sender)
        if id then
            sent = SendBNetMessage(id, messageToSend)
        end
    else
        local safeSender = SafeChatText(sender)
        if type(safeSender) == "string" and safeSender ~= "" then
            sent = SendWhisper(safeSender, messageToSend)
        end
    end

    if sent then
        lastReplyTime[storageKey] = now
    end
end

local function NotifyReturn(targetKey, message)
    if type(targetKey) ~= "string" or targetKey == "" or type(message) ~= "string" or message == "" then
        return false
    end

    if targetKey:find("^BN:") then
        local accountID = tonumber(targetKey:match("^BN:(%d+)"))
        if accountID then
            return SendBNetMessage(accountID, message)
        end
        return false
    end

    return SendWhisper(targetKey, message)
end

local function CheckActivityStatus()
    local db = DB()
    local char = EnsureCharState()
    if not db or not char or not db.autoReply then
        return
    end

    PruneCharState()

    local _, inActivity = GetCurrentActivity(true)
    if char.wasInActivity and not inActivity then
        local returnMessage = db.autoReply.returnMessage
        if db.autoReply.autoNotify and type(returnMessage) == "string" and returnMessage ~= "" then
            for playerKey in pairs(char.pendingWhispers) do
                NotifyReturn(playerKey, returnMessage)
            end
            for playerKey in pairs(char.pendingGuildMentions) do
                NotifyReturn(playerKey, returnMessage)
            end
        end

        char.pendingWhispers = {}
        char.pendingGuildMentions = {}
    end

    char.wasInActivity = inActivity and true or false
end

local function InvalidateActivityCache()
    lastActivityCheckAt = 0
end

function AutoReply:HandleCommand(input)
    local db = DB()
    if not db or not db.autoReply then
        return
    end

    input = type(input) == "string" and input:lower():match("^%s*(.-)%s*$") or ""

    if input == "" or input == "config" or input == "settings" then
        Chatify:OpenConfig()
        return
    end

    if input == "toggle" then
        db.autoReply.enabled = not db.autoReply.enabled
        self:Print(string.format(L("Auto-reply %s."), db.autoReply.enabled and L("enabled") or L("disabled")))
        return
    end

    if input == "busy" then
        db.autoReply.busyMode = not db.autoReply.busyMode
        self:Print(string.format(L("Busy mode %s."), db.autoReply.busyMode and L("enabled") or L("disabled")))
        return
    end

    if input == "status" then
        local _, active = GetCurrentActivity()
        self:Print(string.format(L("Auto-reply: %s, busy mode: %s, activity: %s."), db.autoReply.enabled and L("on") or L("off"), db.autoReply.busyMode and L("on") or L("off"), active and L("active") or L("idle")))
        return
    end

    self:Print(L("Commands: /cauto toggle, /cauto busy, /cauto status, /cauto config"))
end

local function RegisterEventSafe(module, eventName, method)
    if type(ns.RegisterEventIfSupported) == "function" then
        return ns.RegisterEventIfSupported(module, eventName, method)
    end
    if module and type(module.RegisterEvent) == "function" then
        local ok = pcall(module.RegisterEvent, module, eventName, method)
        return ok and true or false
    end
    return false
end

function AutoReply:OnEnable()
    EnsureCharState()
    InvalidateActivityCache()

    RegisterEventSafe(self, "PLAYER_FLAGS_CHANGED", InvalidateActivityCache)
    RegisterEventSafe(self, "ZONE_CHANGED_NEW_AREA", InvalidateActivityCache)
    RegisterEventSafe(self, "LFG_UPDATE", InvalidateActivityCache)
    RegisterEventSafe(self, "GROUP_ROSTER_UPDATE", InvalidateActivityCache)
    RegisterEventSafe(self, "PLAYER_ENTERING_WORLD", InvalidateActivityCache)

    local restrictedWhispers = type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()

    if not restrictedWhispers then
        RegisterEventSafe(self, "CHAT_MSG_WHISPER", function(_, message, sender, ...)
            if not CanAccess(message, sender, ...) then
                return
            end
            if IsPlayerSender(sender) then
                return
            end
            SendAutoReply(sender, false, message)
        end)

        RegisterEventSafe(self, "CHAT_MSG_BN_WHISPER", function(_, ...)
            if not CanAccess(...) then
                return
            end
            local message = select(1, ...)
            local presenceID = GetBNetPresenceID(...)
            if presenceID then
                SendAutoReply(presenceID, true, message)
            end
        end)
    end

    -- Guild chat is not whisper-sensitive, but its payload is still a secret value
    -- during chat messaging lockdown. IsPlayerMentioned does string work on the
    -- message, so without this guard every guild line inside an encounter threw
    -- "string conversion on a secret string value".
    RegisterEventSafe(self, "CHAT_MSG_GUILD", function(_, message, sender, ...)
        if not CanAccess(message, sender, ...) then
            return
        end
        if IsPlayerSender(sender) then
            return
        end
        if IsPlayerMentioned(message) then
            SendGuildAutoReply(sender)
        end
    end)

    if not restrictedWhispers then
        RegisterEventSafe(self, "CHAT_MSG_WHISPER_INFORM", function(_, _, target, ...)
            if not CanAccess(target, ...) then
                return
            end
            RemovePending(target, false)
        end)

        RegisterEventSafe(self, "CHAT_MSG_BN_WHISPER_INFORM", function(_, ...)
            if not CanAccess(...) then
                return
            end
            local presenceID = GetBNetPresenceID(...)
            if presenceID then
                RemovePending(presenceID, true)
            end
        end)
    end

    self:RegisterChatCommand("cauto", "HandleCommand")
    self:RegisterChatCommand("chatifyreply", "HandleCommand")

    if activityTicker then
        activityTicker:Cancel()
        activityTicker = nil
    end

    -- The ticker itself runs every second, but the expensive activity recompute is
    -- rate-limited inside GetCurrentActivity() via ACTIVITY_IDLE_INTERVAL /
    -- ACTIVITY_ACTIVE_INTERVAL, so a fixed 1s cadence keeps state fresh cheaply.
    if C_Timer and C_Timer.NewTicker then
        local ok, ticker = pcall(C_Timer.NewTicker, 1, CheckActivityStatus)
        if ok then activityTicker = ticker end
    end
end

function AutoReply:OnDisable()
    if activityTicker then
        activityTicker:Cancel()
        activityTicker = nil
    end

    self:UnregisterAllEvents()
    self:UnregisterChatCommand("cauto")
    self:UnregisterChatCommand("chatifyreply")
end
