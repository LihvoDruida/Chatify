local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Sounds = Chatify:NewModule("Sounds", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- Локалізація для швидкодії
local strfind = string.find
local strlower = string.lower
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime
local tostring = tostring

-- Змінні модуля
local myName = UnitName("player")
local myNameLower = myName and strlower(myName)
local lastSoundTime = 0
local THROTTLE_INTERVAL = 0.5
local ignoreSelf = true

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
    ["CHAT_MSG_CHANNEL"] = nil, -- тільки для mentions
}

function Sounds:OnEnable()
    for event in pairs(eventMap) do
        self:RegisterEvent(event, "OnEvent")
    end
end

function Sounds:Play(soundName)
    if not soundName or soundName == "None" then return end
    local now = GetTime()
    if (now - lastSoundTime) < THROTTLE_INTERVAL then return end

    local soundFile = LSM:Fetch("sound", soundName)
    if soundFile then
        local channel = ns.db.sounds.masterVolume and "Master" or "SFX"
        PlaySoundFile(soundFile, channel)
        lastSoundTime = now
    end
end

function Sounds:OnEvent(event, msg, author, _, _, _, _, _, _, _, _, _, presenceID)
    local db = ns.db.sounds
    if not db or not db.enable then return end
    local now = GetTime()

    -- =====================================================
    -- THROTTLE
    -- =====================================================
    if (now - lastSoundTime) < THROTTLE_INTERVAL then return end

    -- =====================================================
    -- БЕЗПЕЧНІ ДАНІ
    -- =====================================================
    local safeAuthor = nil
    local safeMsg = nil

    -- Перевіряємо, що author та msg безпечні для порівнянь
    pcall(function() safeAuthor = tostring(author) end)
    pcall(function() safeMsg = tostring(msg) end)

    -- Перевірка автора (щоб не реагувати на себе)
    local isSelf = false
    if safeAuthor and myName and safeAuthor == myName then
        isSelf = true
    end
    if event == "CHAT_MSG_BN_WHISPER" and presenceID then
        local ok, accountInfo = pcall(C_BattleNet.GetAccountInfoByID, presenceID)
        if ok and accountInfo and accountInfo.isSelf then
            isSelf = true
        end
    end

    -- =====================================================
    -- MENTION PRIORITY
    -- =====================================================
    if safeMsg and myNameLower and strfind(strlower(safeMsg), myNameLower, 1, true) then
        self:Play(db.events["MENTION"])
        lastSoundTime = now
        return
    end

    -- =====================================================
    -- Звук для каналу / категорії
    -- =====================================================
    local eventType = eventMap[event]
    if eventType and (not isSelf or (isSelf and not ignoreSelf)) then
        self:Play(db.events[eventType])
        lastSoundTime = now
    end
end

