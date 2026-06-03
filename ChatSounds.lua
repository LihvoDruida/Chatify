local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Sounds = Chatify:NewModule("Sounds", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

local strlower = string.lower
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime
local tostring = tostring
local tinsert = table.insert
local tremove = table.remove
local type = type
local pcall = pcall
local select = select

local myName = UnitName("player")
local myNameLower = myName and strlower(myName)
local ignoreSelf = true

local lastNormalSound = 0
local MIN_THROTTLE = 0.3
local MAX_THROTTLE = 1.2
local ADAPTIVE_WINDOW = 2.0
local messageTimes = {}
local adaptiveThrottle = MIN_THROTTLE

local soundQueue = {}
local isQueueProcessing = false
local MAX_QUEUE_SIZE = 4

local eventMap = {
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_BN_WHISPER = "WHISPER",
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_OFFICER = "GUILD",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "RAID",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "RAID",
    CHAT_MSG_CHANNEL = false,
    CHAT_MSG_COMMUNITIES_CHANNEL = "GUILD",
    CHAT_MSG_SAY = false,
    CHAT_MSG_YELL = false,
}

local function GetSafeText(rawText)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(rawText)
    end

    if rawText == nil then
        return nil
    end

    if type(rawText) == "number" then
        return tostring(rawText)
    end

    if type(rawText) == "string" then
        return rawText
    end

    return nil
end

local function NormalizePlayerName(value)
    local safe = GetSafeText(value)
    if type(safe) ~= "string" or safe == "" then
        return nil, nil
    end

    local short = safe:match("([^%-]+)") or safe
    return safe, short
end

local function IsSelfAuthor(author)
    local _, shortAuthor = NormalizePlayerName(author)
    if not shortAuthor or not myName then
        return false
    end

    return strlower(shortAuthor) == myNameLower
end

local function UpdatePlayerIdentity()
    local name = UnitName("player")
    if type(name) == "string" and name ~= "" then
        myName = name
        myNameLower = strlower(name)
    end
end

local function UpdateAdaptiveThrottle()
    local now = GetTime()
    local i = 1

    while i <= #messageTimes do
        if (now - messageTimes[i]) > ADAPTIVE_WINDOW then
            tremove(messageTimes, i)
        else
            i = i + 1
        end
    end

    local count = #messageTimes
    if count <= 3 then
        adaptiveThrottle = MIN_THROTTLE
    elseif count <= 8 then
        adaptiveThrottle = 0.6
    else
        adaptiveThrottle = MAX_THROTTLE
    end
end

local function ProcessQueue()
    if isQueueProcessing then
        return
    end

    isQueueProcessing = true

    local function PlayNext()
        if #soundQueue == 0 then
            isQueueProcessing = false
            return
        end

        local item = tremove(soundQueue, 1)
        if item and item.file and type(PlaySoundFile) == "function" then
            pcall(PlaySoundFile, item.file, item.channel)
        end

        if type(ns.SafeAfter) == "function" then
            ns.SafeAfter(0.5, PlayNext)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.5, PlayNext)
        else
            isQueueProcessing = false
        end
    end

    PlayNext()
end

local function GetSoundConfig()
    local profile = ns.db or (Chatify and Chatify.db and Chatify.db.profile)
    local soundDb = profile and profile.sounds
    return profile, soundDb
end

function Sounds:Play(soundName)
    local _, db = GetSoundConfig()
    if not soundName or soundName == "None" then
        return
    end

    db = db or {}

    local soundFile = nil
    if type(ns.ResolveSoundPath) == "function" then
        soundFile = ns.ResolveSoundPath(soundName)
    else
        soundFile = LSM:Fetch("sound", soundName, true)
    end
    if not soundFile then
        return
    end

    local channel = db.masterVolume and "Master" or "SFX"

    local lastQueued = soundQueue[#soundQueue]
    if lastQueued and lastQueued.file == soundFile and lastQueued.channel == channel then
        return
    end

    if #soundQueue >= MAX_QUEUE_SIZE then
        tremove(soundQueue, 1)
    end

    tinsert(soundQueue, { file = soundFile, channel = channel })
    ProcessQueue()
end

local function IsBattleNetSelf(...)
    if not C_BattleNet or not C_BattleNet.GetAccountInfoByID then
        return false
    end

    -- Cross-version safe: try the first couple of numeric ids passed by the event payload.
    for i = 1, 3 do
        local value = select(i, ...)
        if type(value) == "number" then
            local ok, accountInfo = pcall(C_BattleNet.GetAccountInfoByID, value)
            if ok and accountInfo and accountInfo.isSelf then
                return true
            end
        end
    end

    return false
end

local function IsIncomingWhisperEvent(event)
    return event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER"
end

function Sounds:OnEvent(event, msg, author, ...)
    local profile, db = GetSoundConfig()
    local mentionEnabled = profile and profile.enableMentionManager ~= false
    local normalSoundsEnabled = db and db.enable == true

    if not mentionEnabled and not normalSoundsEnabled then
        return
    end

    db = db or { events = {} }
    db.events = db.events or {}

    if type(ns.ShouldBypassWhisperMutation) == "function" and ns.ShouldBypassWhisperMutation(event) then
        -- Keep the simple incoming-whisper notification without reading protected text.
        if normalSoundsEnabled and IsIncomingWhisperEvent(event) then
            local now = GetTime()
            if (now - lastNormalSound) >= adaptiveThrottle then
                self:Play(db.events["WHISPER"])
                lastNormalSound = now
            end
        end
        return
    end

    if type(ns.IsSecretValue) == "function" and (ns.IsSecretValue(msg) or ns.IsSecretValue(author)) then
        return
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
        return
    end

    local now = GetTime()
    tinsert(messageTimes, now)
    UpdateAdaptiveThrottle()

    local safeMsg = GetSafeText(msg)
    if not safeMsg then
        return
    end

    local safeAuthor = GetSafeText(author)
    local isSelf = IsSelfAuthor(safeAuthor)

    if not isSelf and event == "CHAT_MSG_BN_WHISPER" then
        isSelf = IsBattleNetSelf(...)
    end

    if mentionEnabled and safeMsg and not isSelf and type(ns.GetMentionRuleMatch) == "function" then
        local okRule, rule, ruleIndex = pcall(ns.GetMentionRuleMatch, safeMsg, event, ...)
        if okRule and rule then
            local soundName = rule.sound
            if type(soundName) == "string" and soundName ~= "" and soundName ~= "None" and type(ns.CanPlayMentionRuleSound) == "function" then
                local okCanPlay, canPlay = pcall(ns.CanPlayMentionRuleSound, rule, ruleIndex)
                if okCanPlay and canPlay then
                    self:Play(soundName)
                    return
                end
            end
        end
    end

    if not normalSoundsEnabled then
        return
    end

    local eventType = eventMap[event]
    if type(eventType) == "string" and (not isSelf or (isSelf and not ignoreSelf)) then
        if (now - lastNormalSound) >= adaptiveThrottle then
            self:Play(db.events[eventType])
            lastNormalSound = now
        end
    end
end

function Sounds:OnEnable()
    for event in pairs(eventMap) do
        if type(ns.RegisterEventIfSupported) == "function" then
            ns.RegisterEventIfSupported(self, event, "OnEvent")
        else
            pcall(self.RegisterEvent, self, event, "OnEvent")
        end
    end

    UpdatePlayerIdentity()
end


function Sounds:OnDisable()
    self:UnregisterAllEvents()
    soundQueue = {}
    isQueueProcessing = false
end
