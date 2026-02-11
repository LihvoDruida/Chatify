local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Filters = Chatify:NewModule("Filters", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- 1. DATA & CONFIG
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
    -- 1. Протоколи (http://...)
    { exp = "^(%a[%w+.-]+://%S+)", verifyDomain = false },
    { exp = "%f[%S](%a[%w+.-]+://%S+)", verifyDomain = false },
    
    -- 2. Email
    { exp = '^(%"[^%"]+%"@[%w_.-%%]+%.(%a%a+))', verifyDomain = true },
    { exp = '%f[%S](%"[^%"]+%"@[%w_.-%%]+%.(%a%a+))', verifyDomain = true },
    { exp = "(%S+@[%w_.-%%]+%.(%a%a+))", verifyDomain = true },
    
    -- 3. IP (IPv4)
    { exp = "^([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d[:/]%S+)", verifyDomain = false },
    { exp = "%f[%S]([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d[:/]%S+)", verifyDomain = false },
    { exp = "^([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d)%f[%D]", verifyDomain = false },
    { exp = "%f[%S]([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d)%f[%D]", verifyDomain = false },

    -- 4. Домени (www...)
    { exp = "^(www%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S](www%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    
    -- 5. Загальні домени
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
-- 2. HELPER FUNCTIONS
-- =========================================================

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
-- 3. FORMATTING LOGIC
-- =========================================================
function ns.FormatMessage(msg)
    local db = ns.db 
    if not db then return msg end

    -- 1. ХАЙЛАЙТИ
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

            if isValid and IsProtected(msg, s) then
                isValid = false
            end

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
    local myName = UnitName("player")
    if myName and myName ~= "" then
        local escaped = myName:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
        msg = msg:gsub("("..escaped..")", function(match)
            local s = msg:find(match, 1, true)
            if s and IsProtected(msg, s) then return match end
            return "|cffffd700" .. match .. "|r"
        end)
    end
    
    return msg
end

-- =========================================================
-- 4. CHAT EVENT FILTER
-- =========================================================
local function MessageProcessor(self, event, msg, author, ...)
    local db = ns.db
    if not db then return false, msg, author, ... end

    -- Спам фільтр
    if db.enableSpamFilter and db.spamKeywords then
        local upperMsg = msg:upper()
        for _, keyword in ipairs(db.spamKeywords) do
            if keyword and keyword ~= "" and upperMsg:find(keyword:upper(), 1, true) then
                return true
            end
        end
    end

    -- Форматування тексту
    msg = ns.FormatMessage(msg)

    return false, msg, author, ...
end

-- =========================================================
-- 5. ENABLE
-- =========================================================
function Filters:OnEnable()
    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_MOTD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM",
        "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT"
    }
    
    for _, evt in ipairs(events) do
        ChatFrame_AddMessageEventFilter(evt, MessageProcessor)
    end

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