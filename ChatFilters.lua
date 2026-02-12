local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Filters = Chatify:NewModule("Filters", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- 1. UPVALUES & CONSTANTS (PERFORMANCE)
-- =========================================================
local strfind, gsub, format, sub, upper = string.find, string.gsub, string.format, string.sub, string.upper
local ipairs, pairs, insert = ipairs, pairs, table.insert
local select = select -- Додаємо select для отримання LineID
local GetTime = GetTime
local UnitName = UnitName

local PLAYER_NAME = UnitName("player")

local SystemEvents = {
    ["CHAT_MSG_CHANNEL_JOIN"] = true,
    ["CHAT_MSG_CHANNEL_LEAVE"] = true,
    ["CHAT_MSG_CHANNEL_NOTICE"] = true,
    ["CHAT_MSG_CHANNEL_NOTICE_USER"] = true,
}

-- Розділяємо історію на дві таблиці для оптимізації (менше Garbage Collection)
local HistoryTime = {} -- Зберігає час
local HistoryID = {}   -- Зберігає унікальний ID повідомлення
local LAST_CLEANUP = GetTime()
local CLEANUP_INTERVAL = 300
local CachedKeywords = nil 

-- =========================================================
-- 2. DATA (TLD & REGEX)
-- =========================================================
local ValidTopLevelDomains = {}
local TLD_STRING = [[
ONION COM NET ORG EDU GOV MIL UA RU UK DE FR PL US CA IO CO ME EU TV INFO BIZ
AC AD AE AERO AF AG AI AL AM AR AS ASIA AT AU AW AX AZ BA BB BE BG BH BI BJ BM BN
BO BR BS BT BY BZ CC CD CH CI CL CN CR CU CX CY CZ DK DM DO DZ EC EE EG ES ET FI
FJ FM FO GA GD GE GF GG GH GI GL GM GN GR GS GT GU HK HN HR HT HU ID IE IL IM IN
INT IQ IR IS IT JE JM JO JP KG KH KR KW KZ LA LB LI LK LT LU LV LY MA MC MD MG MK
ML MM MN MO MOBI MP MQ MR MS MT MU MV MW MX MY MZ NA NAME NC NE NG NI NL NO NP NR NU
NZ OM PA PE PF PG PH PK PM PN PR PRO PS PT PW PY QA RE RO RS RW SA SB SC SD SE SG
SH SI SJ SK SL SM SN SO SR ST SU SV SY SZ TC TD TEL TG TH TJ TK TL TM TN TO TR TRAVEL
TT TW TZ UG UY UZ VA VC VE VG VI VN VU WS ZA ZM ZW PP KR JP CN ID
]]
for tld in TLD_STRING:gmatch("%S+") do ValidTopLevelDomains[tld] = true end

local LinkRegexRules = {
    { exp = "^(%a[%w+.-]+://%S+)", verifyDomain = false },
    { exp = "%f[%S](%a[%w+.-]+://%S+)", verifyDomain = false },
    { exp = '^(%"[^%"]+%"@[%w_.-%%]+%.(%a%a+))', verifyDomain = true },
    { exp = '%f[%S](%"[^%"]+%"@[%w_.-%%]+%.(%a%a+))', verifyDomain = true },
    { exp = "(%S+@[%w_.-%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "^([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d[:/]%S+)", verifyDomain = false },
    { exp = "%f[%S]([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d[:/]%S+)", verifyDomain = false },
    { exp = "^([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d)%f[%D]", verifyDomain = false },
    { exp = "%f[%S]([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d)%f[%D]", verifyDomain = false },
    { exp = "^(www%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S](www%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "^([%w_.-%%]+[%w_-%%]%.(%a%a+):%d+)", verifyDomain = true },
    { exp = "%f[%S]([%w_.-%%]+[%w_-%%]%.(%a%a+):%d+)", verifyDomain = true },
    { exp = "^([%w_.-%%]+[%w_-%%]%.(%a%a+)/%S+)", verifyDomain = true },
    { exp = "%f[%S]([%w_.-%%]+[%w_-%%]%.(%a%a+)/%S+)", verifyDomain = true },
    { exp = "^([-%w_%%]+%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S]([-%w_%%]+%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "^([-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S]([-%w_%%]+%.(%a%a+))", verifyDomain = true },
}

-- =========================================================
-- 3. HELPER FUNCTIONS
-- =========================================================

local function NormalizeText(text)
    if not text then return "" end
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "") 
    text = gsub(text, "|H.-|h.-|h", "")         
    text = gsub(text, "[%s%p%c]", "")           
    return upper(text)
end

function ns.UpdateSpamCache()
    if not ns.db or not ns.db.spamKeywords then return end
    CachedKeywords = {}
    for _, word in ipairs(ns.db.spamKeywords) do
        if word and word ~= "" then
            insert(CachedKeywords, NormalizeText(word))
        end
    end
end

local function DecorateLink(url)
    local db = ns.db
    if not db then return url end
    
    local cleanUrl = url:gsub("[%.,:;!'\"%)%]]+$", "")
    local color = db.urlColor or "0099FF"
    
    return string.format("|cff%s|Hurl:%s|h[%s]|h|r", color, cleanUrl, cleanUrl)
end

local function IsProtected(text, pos)
    local prefix = text:sub(1, pos)
    local _, openCount = prefix:gsub("|H", "")
    local _, closeCount = prefix:gsub("|h", "")
    return openCount > (closeCount / 2)
end

-- =========================================================
-- 4. FORMATTING LOGIC
-- =========================================================
function ns.FormatMessage(msg)
    local db = ns.db 
    if not db then return msg end

    -- 1. ХАЙЛАЙТИ (Keywords)
    if db.highlightKeywords then
        for _, word in ipairs(db.highlightKeywords) do
            if word and word ~= "" then
                local escaped = word:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
                msg = msg:gsub("("..escaped..")", function(match)
                    local s = msg:find(match, 1, true) 
                    if s and IsProtected(msg, s) then return match end
                    return "|cff" .. (db.myHighlightColor or "ff0000") .. match .. "|r"
                end)
            end
        end
    end

    -- 2. URL ПОСИЛАННЯ
    for _, rule in ipairs(LinkRegexRules) do
        local startIdx = 1
        while true do
            local s, e, cap1, cap2 = msg:find(rule.exp, startIdx)
            if not s then break end
            
            local url = cap1
            local tld = cap2
            local isValid = true

            if rule.verifyDomain and tld then
                if not ValidTopLevelDomains[tld:upper()] then
                    isValid = false
                end
            end

            if isValid and IsProtected(msg, s) then isValid = false end

            if isValid then
                local newLink = DecorateLink(url)
                msg = msg:sub(1, s-1) .. newLink .. msg:sub(e+1)
                startIdx = s + #newLink
            else
                startIdx = e + 1
            end
        end
    end

    -- 3. ПІДСВІТКА ВЛАСНОГО ІМЕНІ
    if PLAYER_NAME and PLAYER_NAME ~= "" then
        local escaped = gsub(PLAYER_NAME, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
        msg = gsub(msg, "("..escaped..")", function(match)
            local s = strfind(msg, match, 1, true)
            if s and IsProtected(msg, s) then return match end
            return "|cffffd700" .. match .. "|r"
        end)
    end
    
    return msg
end

-- =========================================================
-- 5. CHAT EVENT FILTER
-- =========================================================
local function MessageProcessor(self, event, msg, author, ...)
    local db = ns.db
    if not db then return false, msg, author, ... end

    -- A. ШВИДКИЙ ФІЛЬТР СИСТЕМНИХ ПОВІДОМЛЕНЬ
    if SystemEvents[event] and db.hideSystemSpam then
        return true 
    end

    local isPlayer = (author == PLAYER_NAME)
    
    if not isPlayer then
        -- Отримуємо унікальний ID повідомлення від сервера (11-й аргумент)
        -- Це ключ до вирішення проблеми "спаму" у різних фреймах
        local lineID = select(11, ...)
        
        local cleanMsg
        if (db.enableThrottle or db.enableSpamFilter) then
            cleanMsg = NormalizeText(msg)
        end

        -- D. ANTI-FLOOD (THROTTLE)
        if db.enableThrottle and cleanMsg and cleanMsg ~= "" then
            local now = GetTime()
            
            -- GC: Очистка таблиць
            if now - LAST_CLEANUP > CLEANUP_INTERVAL then
                HistoryTime = {}
                HistoryID = {}
                LAST_CLEANUP = now
            end

            local lastTime = HistoryTime[cleanMsg]
            local lastID = HistoryID[cleanMsg]

            -- КРИТИЧНЕ ВИПРАВЛЕННЯ:
            -- Якщо LineID збігається з попереднім, це те саме повідомлення в іншому вікні.
            -- Ми дозволяємо йому пройти (не return true).
            if lastID and lastID == lineID then
                -- Це дублікат для іншого фрейму - пропускаємо далі до форматування
            elseif lastTime and (now - lastTime < (db.throttleTime or 60)) then
                -- LineID інший, але текст той самий і час не пройшов -> БЛОКУЄМО
                return true 
            else
                -- Нове повідомлення, записуємо
                HistoryTime[cleanMsg] = now
                HistoryID[cleanMsg] = lineID
            end
        end

        -- E. SPAM FILTER (KEYWORDS)
        if db.enableSpamFilter and cleanMsg and cleanMsg ~= "" then
            if not CachedKeywords then ns.UpdateSpamCache() end
            
            for i = 1, #CachedKeywords do
                if strfind(cleanMsg, CachedKeywords[i], 1, true) then
                    return true 
                end
            end
        end
    end

    -- F. ФОРМАТУВАННЯ
    msg = ns.FormatMessage(msg)

    return false, msg, author, ...
end

-- =========================================================
-- 6. ENABLE & HOOKS
-- =========================================================
function Filters:OnEnable()
    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_MOTD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM",
        "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
        "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", 
        "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER"
    }
    
    for _, evt in ipairs(events) do
        ChatFrame_AddMessageEventFilter(evt, MessageProcessor)
    end

    if ns.db then ns.UpdateSpamCache() end

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
            
            local formatted = ns.FormatMessage(messageInfo.text)
            frame.Message:SetText(formatted)
            
            if ns.db and ns.Lists and ns.Lists.Fonts then
                local f = ns.Lists.Fonts[ns.db.fontID]
                if f and f.path then
                    local _, s, fl = frame.Message:GetFont()
                    frame.Message:SetFont(f.path, s, fl)
                end
            end
        end)
    end
end