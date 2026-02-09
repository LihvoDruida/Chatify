local addonName, ns = ...

local function ChatFilter(self, event, msg, author, ...)
    local db = ns.db
    if not db then return false, msg, author, ... end 
    
    -- 1. СПАМ ФІЛЬТР 
    if db.enableSpamFilter and db.spamKeywords then
        local msgUpper = msg:upper()
        for _, word in ipairs(db.spamKeywords) do
            if word and word ~= "" then
                if msgUpper:find(word:upper(), 1, true) then 
                    return true 
                end
            end
        end
    end

    -- 2. ПІДСВІТКА НІКІВ/СЛІВ
    if db.highlightKeywords then
        for _, word in ipairs(db.highlightKeywords) do
            if word and word ~= "" then
                if msg:find(word) then
                    msg = msg:gsub(word, "|cff" .. (db.myHighlightColor or "ff0000") .. word .. "|r")
                end
            end
        end
    end

    -- 4. ДОДАВАННЯ ЧАСУ
    local formatList = ns.Lists.TimeFormats
    local timeData = formatList[db.timestampID] or formatList[1]
    
    if timeData then
        local timeString = date(timeData.format)
        local link = string.format("|cff%s|Hchatcopy|h[%s]|h|r", (db.timestampColor or "68ccef"), timeString)
        msg = link .. " " .. msg
    end

    -- [НОВЕ] 5. ЗВУКОВІ СПОВІЩЕННЯ (Sound Alerts)
    if db.enableSoundAlerts then
        local playSound = false
        
        -- А. Якщо це приватне повідомлення (Whisper)
        if event == "CHAT_MSG_WHISPER" then
            playSound = true
        end

        -- Б. Якщо згадують ваше ім'я в рейді або групі
        local myName = UnitName("player") -- Отримуємо ім'я нашого персонажа
        if myName and (event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER") then
            -- Шукаємо ім'я в повідомленні (case insensitive не обов'язково, але бажано)
            if msg:find(myName) then
                playSound = true
            end
        end

        if playSound then
            PlaySound(12867, "Master") 
        end
    end

    return false, msg, author, ...
end

-- Реєстрація подій (БЕЗ ЗМІН)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", 
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_SYSTEM", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT" 
    }
    
    for _, event in ipairs(events) do
        ChatFrame_AddMessageEventFilter(event, ChatFilter)
    end
end)