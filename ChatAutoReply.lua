local addonName, ns = ...
local Chatify = ns.Chatify
local AutoReply = Chatify:NewModule("AutoReply", "AceEvent-3.0", "AceConsole-3.0")

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

local activityTicker = nil
local lastGuildReplyTime = 0
local GUILD_REPLY_COOLDOWN = 600

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

local function SafeChatText(value)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(value)
    end
    if type(ns.IsSecretValue) == "function" and ns.IsSecretValue(value) then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    return nil
end

local function CanAccess(...)
    if type(ns.CanAccessChatValue) == "function" then
        return ns.CanAccessChatValue(...)
    end
    return true
end

local function PlayerName()
    return UnitName("player")
end

local function IsPlayerSender(sender)
    local playerName = PlayerName()
    local safeSender = SafeChatText(sender)
    if type(playerName) ~= "string" or playerName == "" or type(safeSender) ~= "string" or safeSender == "" then
        return false
    end

    local shortSender = StripRealm(safeSender) or safeSender
    return shortSender == playerName
end

local function StripRealm(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return select(1, strsplit("-", name))
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

local function SendBNetMessage(accountID, message)
    if not accountID or type(message) ~= "string" or message == "" then
        return false
    end

    if C_BattleNet and C_BattleNet.SendAccountMessage then
        local ok = pcall(C_BattleNet.SendAccountMessage, accountID, message)
        return ok
    end

    if type(BNSendWhisper) == "function" then
        local ok = pcall(BNSendWhisper, accountID, message)
        return ok
    end

    return false
end

local function SendWhisper(target, message)
    if type(target) ~= "string" or target == "" or type(message) ~= "string" or message == "" then
        return false
    end
    local ok = pcall(SendChatMessage, message, "WHISPER", nil, target)
    return ok
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

                local waitMinutes = 0
                if type(estimatedWaitTime) == "number" and estimatedWaitTime > 0 then
                    if estimatedWaitTime >= 1000 then
                        waitMinutes = math_floor(estimatedWaitTime / 60000)
                    else
                        waitMinutes = math_floor(estimatedWaitTime / 60)
                    end
                end

                return true, waitMinutes, mapName or "battleground"
            end
        end
    end

    return false, 0, nil
end

local function GetCurrentActivity()
    local db = DB()
    if not db or not db.autoReply then
        return nil, false
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
            if formatted:find("%s", 1, true) then
                formatted = string.format(formatted, waitMinutes)
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
        return message, active
    end

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

    local shortName = StripRealm(safeSender) or safeSender

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
    bucket[storageKey].time = GetTime()
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

    local shortName = StripRealm(safeTarget)
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
        return string.find(string.lower(safeMessage), string.lower(playerName), 1, true) ~= nil
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

    local now = GetTime()
    local cooldownSec = (tonumber(db.autoReply.cooldown) or 5) * 60
    local lastReplyTime = char.lastReplyTime or {}
    char.lastReplyTime = lastReplyTime

    if lastReplyTime[storageKey] and (now - lastReplyTime[storageKey]) < cooldownSec then
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

    local _, inActivity = GetCurrentActivity()
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
        self:Print("Auto-reply " .. (db.autoReply.enabled and "enabled" or "disabled") .. ".")
        return
    end

    if input == "busy" then
        db.autoReply.busyMode = not db.autoReply.busyMode
        self:Print("Busy mode " .. (db.autoReply.busyMode and "enabled" or "disabled") .. ".")
        return
    end

    if input == "status" then
        local _, active = GetCurrentActivity()
        self:Print("Auto-reply: " .. (db.autoReply.enabled and "on" or "off") .. ", busy mode: " .. (db.autoReply.busyMode and "on" or "off") .. ", activity: " .. (active and "active" or "idle") .. ".")
        return
    end

    self:Print("Commands: /cauto toggle, /cauto busy, /cauto status, /cauto config")
end

function AutoReply:OnEnable()
    EnsureCharState()

    self:RegisterEvent("CHAT_MSG_WHISPER", function(_, message, sender)
        if IsPlayerSender(sender) then
            return
        end
        SendAutoReply(sender, false, message)
    end)

    self:RegisterEvent("CHAT_MSG_BN_WHISPER", function(_, message, _, _, _, _, _, _, _, _, _, _, presenceID)
        if presenceID and CanAccess(presenceID) then
            SendAutoReply(presenceID, true, message)
        end
    end)

    self:RegisterEvent("CHAT_MSG_GUILD", function(_, message, sender)
        if IsPlayerSender(sender) then
            return
        end
        if IsPlayerMentioned(message) then
            SendGuildAutoReply(sender)
        end
    end)

    self:RegisterEvent("CHAT_MSG_WHISPER_INFORM", function(_, _, target)
        RemovePending(target, false)
    end)

    self:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM", function(_, _, _, _, _, _, _, _, _, _, _, _, presenceID)
        if presenceID and CanAccess(presenceID) then
            RemovePending(presenceID, true)
        end
    end)

    self:RegisterChatCommand("cauto", "HandleCommand")
    self:RegisterChatCommand("chatifyreply", "HandleCommand")

    if activityTicker then
        activityTicker:Cancel()
        activityTicker = nil
    end

    if C_Timer and C_Timer.NewTicker then
        activityTicker = C_Timer.NewTicker(1, CheckActivityStatus)
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
