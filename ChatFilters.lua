local addonName, ns = ...

-- ===============================
-- Utility: Strip WoW Color Codes
-- ===============================
local function stripColors(text)
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
end

-- ===============================
-- URL Wrapper
-- ===============================
local function wrapURL(url)
    local cleanUrl = url:gsub("[%.,:;!'\"]+$", "")
    return "|cff33ffcc|Hurl:" .. cleanUrl .. "|h[" .. cleanUrl .. "]|h|r"
end

-- ===============================
-- Get WoW links positions
-- ===============================
local function getLinkPositions(msg)
    local positions = {}
    for startPos, endPos in msg:gmatch("()|H.-|h.-|h()") do
        table.insert(positions, {startPos, endPos-1})
    end
    return positions
end

local function isInsideLink(pos, linkPositions)
    for _, range in ipairs(linkPositions) do
        if pos >= range[1] and pos <= range[2] then
            return true
        end
    end
    return false
end

-- ===============================
-- MAIN CHAT FILTER
-- ===============================
local function ChatFilter(self, event, msg, author, ...)

    local db = ns.db
    if not db then return false, msg, author, ... end

    local myName = UnitName("player")
    local originalMsg = msg

    -- 1. SPAM FILTER
    if db.enableSpamFilter and db.spamKeywords then
        local msgUpper = msg:upper()
        for _, word in ipairs(db.spamKeywords) do
            if word and word ~= "" and msgUpper:find(word:upper(), 1, true) then
                return true
            end
        end
    end

    -- PROTECT WOW LINKS
    local linkPositions = getLinkPositions(msg)
    local searchMsg = stripColors(originalMsg)

    -- 2 & 3: Highlight keywords & URLs
    local patterns = {}
    
    if db.highlightKeywords then
        for _, word in ipairs(db.highlightKeywords) do
            if word and word ~= "" then
                table.insert(patterns, {word=word, type="highlight"})
            end
        end
    end

    local urlPattern = "[%w%.%:%/%-%_%?%=%&%%%+%#%~]+"
    for url in searchMsg:gmatch("(https?://" .. urlPattern .. ")") do
        table.insert(patterns, {word=url, type="url"})
    end
    for url in searchMsg:gmatch("(%f[%w]www%." .. urlPattern .. ")") do
        table.insert(patterns, {word=url, type="url"})
    end
    for url in searchMsg:gmatch("(%f[%w]discord%.gg/" .. urlPattern .. ")") do
        table.insert(patterns, {word=url, type="url"})
    end

    for _, p in ipairs(patterns) do
        msg = msg:gsub("()"..p.word.."()", function(startPos, endPos)
            if not isInsideLink(startPos, linkPositions) then
                if p.type=="highlight" then
                    return "|cff" .. (db.myHighlightColor or "ff0000") .. p.word .. "|r"
                elseif p.type=="url" then
                    return wrapURL(p.word)
                end
            end
            return p.word
        end)
    end

    -- 2.5 Highlight Player Name
    if myName and myName ~= "" then
        msg = msg:gsub("()"..myName.."()", function(startPos, endPos)
            if not isInsideLink(startPos, linkPositions) then
                return "|cffffd700" .. myName .. "|r"
            else
                return myName
            end
        end)
    end

    -- 4. TIMESTAMP & COPY PREPARATION
    if ns.Lists and ns.Lists.TimeFormats then
        local formatList = ns.Lists.TimeFormats
        local timeData = formatList[db.timestampID] or formatList[1]
        
        if timeData then
            local timeString = date(timeData.format)
            local cleanContent = stripColors(originalMsg)
            local copyText = string.format("[%s] %s: %s", timeString, (author or "System"), cleanContent)
            
            -- [ВАЖЛИВО] Викликаємо функцію з ChatCopy.lua через ns.
            if ns.SaveToCache then
                local msgID = ns.SaveToCache(copyText)
                local link = string.format("|cff%s|Hchatcopy:%d|h[%s]|h|r", 
                    (db.timestampColor or "68ccef"), msgID, timeString)
                msg = link .. " " .. msg
            else
                -- Fallback (якщо ChatCopy.lua не завантажився)
                local link = string.format("|cff%s|Hchatcopy|h[%s]|h|r", 
                    (db.timestampColor or "68ccef"), timeString)
                msg = link .. " " .. msg
            end
        end
    end

    -- 5. SOUND ALERTS
    if db.enableSoundAlerts then
        local playSound = false
        if author and not author:find(myName, 1, true) then
            if event == "CHAT_MSG_WHISPER" then
                playSound = true
            else
                local groupEvents = {
                    CHAT_MSG_PARTY=true, CHAT_MSG_PARTY_LEADER=true,
                    CHAT_MSG_RAID=true, CHAT_MSG_RAID_LEADER=true,
                    CHAT_MSG_GUILD=true, CHAT_MSG_OFFICER=true, CHAT_MSG_GUILD_MOTD=true,
                    CHAT_MSG_INSTANCE_CHAT=true, CHAT_MSG_INSTANCE_CHAT_LEADER=true,
                    CHAT_MSG_CHANNEL=true,
                }
                if groupEvents[event] then
                    local cleanSearch = stripColors(originalMsg):lower()
                    if cleanSearch:find(myName:lower(), 1, true) then
                        playSound = true
                    end
                end
            end
        end
        if playSound then
            PlaySoundFile("Interface\\AddOns\\Chatify\\Assets\\Alert\\notification-0.ogg", "Master")
        end
    end

    return false, msg, author, ...
end

-- ===============================
-- Event Registration
-- ===============================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end

    local events = {
        "CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_EMOTE","CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_GUILD","CHAT_MSG_GUILD_MOTD","CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER","CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING","CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM","CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM","CHAT_MSG_CHANNEL","CHAT_MSG_SYSTEM",
        "CHAT_MSG_ACHIEVEMENT","CHAT_MSG_GUILD_ACHIEVEMENT"
    }

    for _, eventName in ipairs(events) do
        ChatFrame_AddMessageEventFilter(eventName, ChatFilter)
    end
end)