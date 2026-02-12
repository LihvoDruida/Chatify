local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Sounds = Chatify:NewModule("Sounds", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- Локалізація функцій для швидкодії (micro-optimization)
local strfind = string.find
local strlower = string.lower
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime

-- Змінні модуля
local myName = nil
local myNameLower = nil
local lastSoundTime = 0
local THROTTLE_INTERVAL = 0.5 -- Мінімальний інтервал між звуками (секунди)

-- Таблиця мапінгу подій на типи звуків
-- Це замінює довгий блок if/elseif
local eventMap = {
    -- Whispers
    ["CHAT_MSG_WHISPER"]    = "WHISPER",
    ["CHAT_MSG_BN_WHISPER"] = "WHISPER",
    
    -- Guild/Officer
    ["CHAT_MSG_GUILD"]      = "GUILD",
    ["CHAT_MSG_OFFICER"]    = "GUILD",
    
    -- Party
    ["CHAT_MSG_PARTY"]        = "PARTY",
    ["CHAT_MSG_PARTY_LEADER"] = "PARTY",
    
    -- Raid / Instance
    ["CHAT_MSG_RAID"]                 = "RAID",
    ["CHAT_MSG_RAID_LEADER"]          = "RAID",
    ["CHAT_MSG_RAID_WARNING"]         = "RAID",
    ["CHAT_MSG_INSTANCE_CHAT"]        = "RAID", -- Можна змінити на окрему категорію, якщо потрібно
    ["CHAT_MSG_INSTANCE_CHAT_LEADER"] = "RAID",
    
    -- Channel (тільки для пошуку Mentions, тому тут nil або спец. тип)
    ["CHAT_MSG_CHANNEL"] = nil 
}

function Sounds:OnInitialize()
    -- Кешуємо ім'я гравця один раз при завантаженні
    myName = UnitName("player")
    if myName then
        myNameLower = strlower(myName)
    end
end

function Sounds:OnEnable()
    -- Реєструємо всі події з таблиці eventMap
    for event in pairs(eventMap) do
        self:RegisterEvent(event, "OnEvent")
    end
    -- CHAT_MSG_CHANNEL є в таблиці як ключ, тому він теж зареєструється
end

-- Основна функція обробки подій
function Sounds:OnEvent(event, msg, author, _, _, _, _, _, _, _, _, _, presenceID)
    local db = ns.db.sounds
    if not db or not db.enable then return end
    local now = GetTime()

    -- =====================================================
    -- THROTTLE
    -- =====================================================
    if (now - lastSoundTime) < THROTTLE_INTERVAL then return end

    local isSelf = false
    if author and myName and author == myName then
        isSelf = true
    end
    if event == "CHAT_MSG_BN_WHISPER" and presenceID then
        local accountInfo = C_BattleNet.GetAccountInfoByID(presenceID)
        if accountInfo and accountInfo.isSelf then
            isSelf = true
        end
    end

    -- =====================================================
    -- MENTION PRIORITY
    -- =====================================================
    if author and myName and author == myName then return end
    if msg and myNameLower and strfind(strlower(msg), myNameLower, 1, true) then
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



function Sounds:Play(soundName)
    if not soundName or soundName == "None" then return end

    -- Anti-Spam: не грати звуки надто часто
    local now = GetTime()
    if (now - lastSoundTime) < THROTTLE_INTERVAL then return end

    -- Отримуємо файл через LSM
    local soundFile = LSM:Fetch("sound", soundName)
    
    if soundFile then
        local channel = ns.db.sounds.masterVolume and "Master" or "SFX"
        PlaySoundFile(soundFile, channel)
        lastSoundTime = now
    end
end