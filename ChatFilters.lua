local addonName, ns = ...

local function ChatFilter(self, event, msg, author, ...)
    local db = ns.db
    if not db then return false, msg, author, ... end 
    
    -- Отримуємо ім'я та оригінальний текст НА ПОЧАТКУ
    local myName = UnitName("player")
    local originalMsg = msg -- Зберігаємо "чистий" текст для перевірки звуку

    -- 1. SPAM FILTER (Фільтр слів)
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

    -- 2. HIGHLIGHT KEYWORDS (Підсвітка слів зі списку)
    if db.highlightKeywords then
        for _, word in ipairs(db.highlightKeywords) do
            if word and word ~= "" then
                if msg:find(word) then
                    msg = msg:gsub(word, "|cff" .. (db.myHighlightColor or "ff0000") .. word .. "|r")
                end
            end
        end
    end

    -- 2.5. ПІДСВІТКА ІМЕНІ ПЕРСОНАЖА (Золотий колір)
    if myName and myName ~= "" then
        if msg:lower():find(myName:lower()) then
            -- Замінюємо ім'я на золоте (fffd700)
            msg = msg:gsub(myName, "|cffffd700" .. myName .. "|r")
        end
    end

    -- 3. URL LINKS (Клікабельні посилання)
    local function wrapURL(url)
        return "|cff33ffcc|Hurl:" .. url .. "|h[" .. url .. "]|h|r"
    end
    msg = msg:gsub("(https?://%S+)", wrapURL)
    msg = msg:gsub("(%s)(www%.%S+)", function(space, url)
        return space .. wrapURL(url)
    end)
    msg = msg:gsub("^(www%.%S+)", wrapURL)
    msg = msg:gsub("(%s)(discord%.gg/%S+)", function(space, url)
         return space .. wrapURL(url)
    end)
    msg = msg:gsub("^(discord%.gg/%S+)", wrapURL)


    -- 4. ADD TIMESTAMP (Час повідомлення)
    local formatList = ns.Lists.TimeFormats
    local timeData = formatList[db.timestampID] or formatList[1]
    
    if timeData then
        local timeString = date(timeData.format)
        local link = string.format("|cff%s|Hchatcopy|h[%s]|h|r", (db.timestampColor or "68ccef"), timeString)
        msg = link .. " " .. msg
    end

    -- 5. SOUND ALERTS (Звукові сповіщення)
    if db.enableSoundAlerts then
        local playSound = false
        
        -- А) Приватні повідомлення
        if event == "CHAT_MSG_WHISPER" then
            playSound = true
        end

        -- Б) Згадка імені (Група, Рейд, Гільдія, Інстанс)
        if myName and myName ~= "" then
            local isGroupChat = (event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER")
            local isRaidChat  = (event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER")
            local isGuildChat = (event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER")
            local isInstance  = (event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER")

            if (isGroupChat or isRaidChat or isGuildChat or isInstance) then
                -- Перевіряємо originalMsg, щоб уникнути проблем із кольоровими кодами
                if originalMsg:lower():find(myName:lower(), 1, true) then
                    playSound = true
                end
            end
        end

        if playSound then
            PlaySoundFile("Interface\\AddOns\\Chatify\\assets\\alert\\notification-0.ogg", "Master")
        end
    end

    return false, msg, author, ...
end

-- Реєстрація подій
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