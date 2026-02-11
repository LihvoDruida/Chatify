local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Sounds = Chatify:NewModule("Sounds", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

function Sounds:OnEnable()
    -- Реєструємо події чату, на які хочемо реагувати
    self:RegisterEvent("CHAT_MSG_WHISPER")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER")
    
    self:RegisterEvent("CHAT_MSG_GUILD")
    self:RegisterEvent("CHAT_MSG_OFFICER")
    
    self:RegisterEvent("CHAT_MSG_PARTY")
    self:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    
    self:RegisterEvent("CHAT_MSG_RAID")
    self:RegisterEvent("CHAT_MSG_RAID_LEADER")
    self:RegisterEvent("CHAT_MSG_RAID_WARNING")
    
    self:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
    self:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
    
    self:RegisterEvent("CHAT_MSG_CHANNEL") -- Для пошуку по ніку в загальних чатах
end

-- Основна функція обробки подій (Dispatcher)
function Sounds:OnEvent(event, msg, author, ...)
    local db = ns.db.sounds
    if not db.enable then return end

    local myName = UnitName("player")
    -- Ігноруємо свої повідомлення
    if author == myName then return end

    local soundToPlay = nil
    local eventType = nil

    -- 1. Логіка нормалізації подій (як у Prat)
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        eventType = "WHISPER"
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        eventType = "GUILD"
    elseif event:find("PARTY") then
        eventType = "PARTY"
    elseif event:find("RAID") or event:find("INSTANCE") then
        -- Визначаємо пріоритет (Рейд важливіше)
        eventType = "RAID"
    end

    -- 2. Перевірка на згадування ніку (MENTION)
    -- Це має вищий пріоритет, ніж канал
    if msg and myName and msg:lower():find(myName:lower(), 1, true) then
        soundToPlay = db.events["MENTION"]
    end

    -- 3. Якщо нік не згадали, беремо звук каналу
    if not soundToPlay and eventType then
        soundToPlay = db.events[eventType]
    end

    -- 4. Програвання звуку
    self:Play(soundToPlay)
end

function Sounds:Play(soundName)
    if not soundName or soundName == "None" then return end

    -- Отримуємо файл через LSM
    local soundFile = LSM:Fetch("sound", soundName)
    
    if soundFile then
        local channel = ns.db.sounds.masterVolume and "Master" or "SFX"
        PlaySoundFile(soundFile, channel)
    end
end

-- Динамічна прив'язка подій до єдиного обробника
-- Це дозволяє не писати окрему функцію для кожної події
local events = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_CHANNEL"
}

function Sounds:OnEnable()
    for _, event in ipairs(events) do
        self:RegisterEvent(event, "OnEvent")
    end
end