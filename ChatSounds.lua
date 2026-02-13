local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Sounds = Chatify:NewModule("Sounds", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- Локалізація функцій
local strfind = string.find
local strlower = string.lower
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime
local tostring = tostring

-- ==========================
-- Змінні модуля
-- ==========================
local myName = UnitName("player")
local myNameLower = myName and strlower(myName)
local ignoreSelf = true

-- Throttle для звичайних та mention звуків
local lastNormalSound = 0
local lastMentionSound = 0
local MIN_THROTTLE = 0.3
local MAX_THROTTLE = 1.2
local MENTION_THROTTLE = 0.8
local ADAPTIVE_WINDOW = 2.0
local messageTimes = {}
local adaptiveThrottle = MIN_THROTTLE

-- Sound queue
local soundQueue = {}
local queueProcessing = false

-- Мапінг подій на типи звуків
local eventMap = {
    ["CHAT_MSG_WHISPER"]    = "WHISPER",
    ["CHAT_MSG_BN_WHISPER"] = "WHISPER",
    ["CHAT_MSG_GUILD"]      = "GUILD",
    ["CHAT_MSG_OFFICER"]    = "GUILD",
    ["CHAT_MSG_PARTY"]        = "PARTY",
    ["CHAT_MSG_PARTY_LEADER"] = "PARTY",
    ["CHAT_MSG_RAID"]                 = "RAID",
    ["CHAT_MSG_RAID_LEADER"]          = "RAID",
    ["CHAT_MSG_RAID_WARNING"]         = "RAID",
    ["CHAT_MSG_INSTANCE_CHAT"]        = "RAID",
    ["CHAT_MSG_INSTANCE_CHAT_LEADER"] = "RAID",
    ["CHAT_MSG_CHANNEL"] = nil, -- лише для mentions
}

-- ==========================
-- Adaptive Throttle
-- ==========================
local function UpdateAdaptiveThrottle()
    local now = GetTime()
    for i = #messageTimes, 1, -1 do
        if (now - messageTimes[i]) > ADAPTIVE_WINDOW then
            table.remove(messageTimes, i)
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

-- ==========================
-- Sound Queue
-- ==========================
local function ProcessQueue()
    if queueProcessing then return end
    queueProcessing = true

    C_Timer.NewTicker(0.05, function(ticker)
        if #soundQueue == 0 then
            ticker:Cancel()
            queueProcessing = false
            return
        end
        local item = table.remove(soundQueue, 1)
        PlaySoundFile(item.file, item.channel)
        item.lastTime = GetTime()
    end)
end

-- ==========================
-- Safe text conversion
-- ==========================
local function SafeStr(val)
    local ok, s = pcall(tostring, val)
    if ok and type(s) == "string" then return s end
    return nil
end

-- ==========================
-- Play sound
-- ==========================
function Sounds:Play(soundName)
    if not soundName or soundName == "None" then return end

    local soundFile = LSM:Fetch("sound", soundName)
    if not soundFile then return end

    local channel = ns.db.sounds.masterVolume and "Master" or "SFX"
    table.insert(soundQueue, {file = soundFile, channel = channel})
    ProcessQueue()
end

-- ==========================
-- Main Event Handler
-- ==========================
function Sounds:OnEvent(event, msg, author, _, _, _, _, _, _, _, _, _, presenceID)
    local db = ns.db.sounds
    if not db or not db.enable then return end

    local now = GetTime()
    table.insert(messageTimes, now)
    UpdateAdaptiveThrottle()

    local safeAuthor = SafeStr(author)
    local safeMsg = SafeStr(msg)

    -- Check self
    local isSelf = false
    if safeAuthor and safeAuthor == myName then
        isSelf = true
    end
    if event == "CHAT_MSG_BN_WHISPER" and presenceID then
        local ok, accountInfo = pcall(C_BattleNet.GetAccountInfoByID, presenceID)
        if ok and accountInfo and accountInfo.isSelf then
            isSelf = true
        end
    end

    -- =======================
    -- Mentions
    -- =======================
    if safeMsg and myNameLower then
        -- regex word boundary
        if strfind(strlower(safeMsg), "%f[%w]"..myNameLower.."%f[%W]") then
            if (now - lastMentionSound) >= MENTION_THROTTLE then
                self:Play(db.events["MENTION"])
                lastMentionSound = now
            end
            return
        end
    end

    -- =======================
    -- Category sound
    -- =======================
    local eventType = eventMap[event]
    if eventType and (not isSelf or (isSelf and not ignoreSelf)) then
        if (now - lastNormalSound) >= adaptiveThrottle then
            self:Play(db.events[eventType])
            lastNormalSound = now
        end
    end
end

-- ==========================
-- Enable Module
-- ==========================
function Sounds:OnEnable()
    for event in pairs(eventMap) do
        self:RegisterEvent(event, "OnEvent")
    end
end
