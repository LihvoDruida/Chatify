local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Filters = Chatify:NewModule("Filters", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- 1. UTILITIES
-- =========================================================
local function stripColors(text)
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
end

local function escapePattern(text)
    return text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

local function wrapURL(url)
    local cleanUrl = url:gsub("[%.,:;!'\"]+$", "")
    return "|cff33ffcc|Hurl:" .. cleanUrl .. "|h[" .. cleanUrl .. "]|h|r"
end

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

-- =========================================================
-- 2. CORE FORMATTING LOGIC
-- =========================================================
function ns.FormatMessage(msg)
    local db = ns.db 
    if not db then return msg end

    local myName = UnitName("player")
    local originalMsg = msg
    local linkPositions = getLinkPositions(msg)
    local searchMsg = stripColors(originalMsg)
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
        local safeWord = escapePattern(p.word)
        msg = msg:gsub("()"..safeWord.."()", function(startPos, endPos)
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

    if myName and myName ~= "" then
        local safeName = escapePattern(myName)
        msg = msg:gsub("()"..safeName.."()", function(startPos, endPos)
            if not isInsideLink(startPos, linkPositions) then
                return "|cffffd700" .. myName .. "|r"
            else
                return myName
            end
        end)
    end
    
    return msg
end

-- =========================================================
-- 3. STANDARD CHAT FILTER
-- =========================================================
local function ChatFilter(self, event, msg, author, ...)
    local db = ns.db
    if not db then return false, msg, author, ... end
    local myName = UnitName("player")

    if db.enableSpamFilter and db.spamKeywords then
        local msgUpper = msg:upper()
        for _, word in ipairs(db.spamKeywords) do
            if word and word ~= "" and msgUpper:find(word:upper(), 1, true) then
                return true
            end
        end
    end

    msg = ns.FormatMessage(msg)

    if ns.Lists and ns.Lists.TimeFormats then
        local formatList = ns.Lists.TimeFormats
        local timeData = formatList[db.timestampID] or formatList[1]
        
        if timeData then
            local timeString = date(timeData.format)
            local cleanContent = stripColors(msg)
            local copyText = string.format("[%s] %s: %s", timeString, (author or "System"), cleanContent)
            
            if ns.SaveToCache then
                local msgID = ns.SaveToCache(copyText)
                local link = string.format("|cff%s|Hchatcopy:%d|h[%s]|h|r", (db.timestampColor or "68ccef"), msgID, timeString)
                msg = link .. " " .. msg
            else
                local link = string.format("|cff%s|Hchatcopy|h[%s]|h|r", (db.timestampColor or "68ccef"), timeString)
                msg = link .. " " .. msg
            end
        end
    end

    if db.enableSoundAlerts and author and not author:find(myName, 1, true) then
        local playSound = false
        if event == "CHAT_MSG_WHISPER" then
            playSound = true
        else
            local groupEvents = {
                CHAT_MSG_PARTY=true, CHAT_MSG_PARTY_LEADER=true,
                CHAT_MSG_RAID=true, CHAT_MSG_RAID_LEADER=true,
                CHAT_MSG_GUILD=true, CHAT_MSG_OFFICER=true,
                CHAT_MSG_INSTANCE_CHAT=true, CHAT_MSG_INSTANCE_CHAT_LEADER=true,
            }
            if groupEvents[event] then
                local cleanSearch = stripColors(msg):lower()
                if cleanSearch:find(myName:lower(), 1, true) then
                    playSound = true
                end
            end
        end
        if playSound then
            PlaySoundFile("Interface\\AddOns\\Chatify\\Assets\\Alert\\notification-0.ogg", "Master")
        end
    end

    return false, msg, author, ...
end

-- =========================================================
-- 4. GUILD & COMMUNITIES HOOKS
-- =========================================================
function Filters:OnEnable()
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

    -- !!! ВИПРАВЛЕННЯ ТУТ: Використання C_AddOns.IsAddOnLoaded !!!
    if C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
        self:HookCommunities()
    else
        self:RegisterEvent("ADDON_LOADED")
    end
end

function Filters:ADDON_LOADED(event, name)
    if name == "Blizzard_Communities" then
        self:HookCommunities()
        self:UnregisterEvent("ADDON_LOADED")
    end
end

function Filters:HookCommunities()
    if CommunitiesChatLineMixin and CommunitiesChatLineMixin.SetMessage then
        self:SecureHook(CommunitiesChatLineMixin, "SetMessage", function(frame, messageInfo)
            if not messageInfo or not messageInfo.text then return end
            
            local newText = ns.FormatMessage(messageInfo.text)
            frame.Message:SetText(newText)
            
            if ns.db and ns.Lists and ns.Lists.Fonts then
                local fontData = ns.Lists.Fonts[ns.db.fontID]
                if fontData and fontData.path then
                    local _, size, flags = frame.Message:GetFont()
                    frame.Message:SetFont(fontData.path, size, flags)
                end
            end
        end)
    end
    
    local cf = _G["CommunitiesFrame"]
    if cf then
        local editBox = cf.ChatEditBox or (cf.Chat and cf.Chat.EditBox)
        
        if editBox and ns.db and ns.Lists and ns.Lists.Fonts then
            local fontData = ns.Lists.Fonts[ns.db.fontID]
            
            if fontData and fontData.path then
                local _, size, flags = editBox:GetFont()
                editBox:SetFont(fontData.path, size, flags)
                
                editBox:HookScript("OnShow", function(self)
                    local _, s, f = self:GetFont()
                    self:SetFont(fontData.path, s, f)
                end)
            end
        end
    end
end