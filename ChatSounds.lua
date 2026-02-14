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
local tinsert = table.insert
local tremove = table.remove

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
local isQueueProcessing = false

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
-- Safe text conversion (Deep Sanitization)
-- ==========================
-- Ця функція створює нову копію рядка через string.format,
-- що знімає статус "secret" (taint).
local function GetSafeText(rawText)
    if rawText == nil then return nil end
    
    if type(rawText) == "number" then
        return tostring(rawText)
    end

    if type(rawText) ~= "string" then
        return nil
    end

    -- Створення чистої копії
    local ok, cleanCopy = pcall(string.format, "%s", rawText)

    if ok and cleanCopy then
        -- Перевірка на порожнечу всередині pcall для безпеки
        local checkOk, isNotEmpty = pcall(function() return cleanCopy ~= "" end)
        if checkOk and isNotEmpty then
            return cleanCopy
        end
    end

    return nil
end

-- ==========================
-- Adaptive Throttle
-- ==========================
local function UpdateAdaptiveThrottle()
    local now = GetTime()
    -- Очищення старих записів
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

-- ==========================
-- Sound Queue
-- ==========================
local function ProcessQueue()
    if isQueueProcessing then return end
    isQueueProcessing = true

    -- Використовуємо C_Timer для асинхронної обробки черги
    local function PlayNext()
        if #soundQueue == 0 then
            isQueueProcessing = false
            return
        end

        local item = tremove(soundQueue, 1)
        PlaySoundFile(item.file, item.channel)
        
        -- Невелика затримка між звуками, щоб вони не зливалися
        C_Timer.After(0.5, PlayNext) 
    end

    PlayNext()
end

-- ==========================
-- Play sound helper
-- ==========================
function Sounds:Play(soundName)
    local db = ns.db and ns.db.sounds
    if not db or not soundName or soundName == "None" then return end

    local soundFile = LSM:Fetch("sound", soundName)
    if not soundFile then return end

    local channel = db.masterVolume and "Master" or "SFX"
    
    tinsert(soundQueue, {file = soundFile, channel = channel})
    ProcessQueue()
end

-- ==========================
-- Main Event Handler
-- ==========================
function Sounds:OnEvent(event, msg, author, ...)
    local db = ns.db and ns.db.sounds
    if not db or not db.enable then return end

    -- Оновлення тротлінгу
    local now = GetTime()
    tinsert(messageTimes, now)
    UpdateAdaptiveThrottle()

    -- 1. Безпечне отримання тексту та автора
    local safeMsg = GetSafeText(msg)
    -- Якщо повідомлення секретне або порожнє, ми його не обробляємо
    if not safeMsg then return end

    local safeAuthor = GetSafeText(author)

    -- 2. Перевірка на "Себе" (Self Check)
    local isSelf = false
    
    -- Використовуємо pcall для порівняння, на всяк випадок
    if safeAuthor and myName then
        local ok, result = pcall(function() return safeAuthor == myName end)
        if ok and result then isSelf = true end
    end

    -- Додаткова перевірка для Battle.net (presenceID)
    if not isSelf and event == "CHAT_MSG_BN_WHISPER" then
        -- presenceID is usually the 13th argument
        local presenceID = select(13, event, msg, author, ...) 
        if presenceID then
            local ok, accountInfo = pcall(C_BattleNet.GetAccountInfoByID, presenceID)
            if ok and accountInfo and accountInfo.isSelf then
                isSelf = true
            end
        end
    end

    -- 3. Обробка Mentions (Згадувань)
    if safeMsg and myNameLower then
        local msgLower = strlower(safeMsg)
        -- Пошук ніку (word boundary)
        if strfind(msgLower, "%f[%w]"..myNameLower.."%f[%W]") then
            if (now - lastMentionSound) >= MENTION_THROTTLE then
                self:Play(db.events["MENTION"])
                lastMentionSound = now
            end
            return -- Якщо згадали нік, звук каналу вже не граємо
        end
    end

    -- 4. Звук категорії (Channel Sound)
    local eventType = eventMap[event]
    
    -- Граємо звук, якщо це не ми (або якщо ми не ігноруємо себе)
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
    
    -- Оновлення імені гравця при старті
    local name = UnitName("player")
    if name then
        myName = name
        myNameLower = strlower(name)
    end
end